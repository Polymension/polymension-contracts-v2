//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import './base/CustomChanIbcApp.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IPriceFeeds} from './interfaces/IPriceFeeds.sol';
import {IDex} from './interfaces/IDex.sol';

contract Bridge is CustomChanIbcApp, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum BridgeType {
        NATIVE_TO_NATIVE, // 0
        NATIVE_TO_ERC20, // 1
        ERC20_TO_ERC20, // 2
        ERC20_TO_NATIVE // 3
    }

    IPriceFeeds public priceFeeds;
    IDex public dex;

    mapping(address => bool) public supportedTokens;
    mapping(bytes32 => address) public tokenAddresses;

    error TokenNotSupported(address tokenAddress);
    error InsufficientBalance(uint256 balance, uint256 amount);
    error InsufficientAllowance(uint256 allowance, uint256 amount);
    error InvalidCoinPrices();
    error InvalidPayload();
    error ZeroAddress();
    error ZeroAmount();
    error SwapFailed();

    modifier checkZeroAddress(address addr) {
        if (addr == address(0)) {
            revert ZeroAddress();
        }
        _;
    }

    modifier checkZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert ZeroAmount();
        }
        _;
    }

    modifier checkPayloadLength(uint256 payloadLength) {
        if (payloadLength == 0) {
            revert InvalidPayload();
        }
        _;
    }

    constructor(IbcDispatcher _dispatcher) CustomChanIbcApp(_dispatcher) {}

    /**
     * @dev Set the oracle address.
     * This function can only be called by the owner of the contract.
     * @param _priceFeeds The address of the oracle.
     */
    function setPriceFeedsAddress(address _priceFeeds) external onlyOwner {
        priceFeeds = IPriceFeeds(_priceFeeds);
    }

    /**
     * @dev Set the DEX address.
     * This function can only be called by the owner of the contract.
     * @param _dex The address of the DEX.
     */
    function setDexAddress(address payable _dex) external onlyOwner {
        dex = IDex(_dex);
    }

    /**
     * @dev Add a supported token.
     * This function can only be called by the owner of the contract.
     * @param _tokenAddress The address of the token.
     */
    function addSupportedToken(address _tokenAddress) external onlyOwner {
        supportedTokens[_tokenAddress] = true;
    }

    /**
     * @dev Add a token address.
     * This function can only be called by the owner of the contract.
     * @param _tokenSymbol The symbol of the token.
     * @param _tokenAddress The address of the token.
     */
    function addTokenAddress(bytes32 _tokenSymbol, address _tokenAddress) external onlyOwner {
        tokenAddresses[_tokenSymbol] = _tokenAddress;
    }

    function nativeToNative(
        bytes32 _channelId,
        bytes memory _payload,
        uint256 _timeoutSeconds
    ) external payable nonReentrant checkPayloadLength(_payload.length) checkZeroAmount(msg.value) {
        (uint256 targetNetworkId, address to, uint256 slippage) = abi.decode(_payload, (uint256, address, uint256));

        uint256 amountIn = msg.value;

        uint256 amountOut = _calculateNativeAmountOut(block.chainid, targetNetworkId, amountIn);

        bytes memory data = abi.encode(block.chainid, targetNetworkId, msg.sender, to, amountIn, amountOut, slippage);
        bytes memory payload = abi.encode(BridgeType.NATIVE_TO_NATIVE, data);

        uint64 timeoutTimestamp = uint64((block.timestamp + _timeoutSeconds) * 1000000000);

        // calling the Dispatcher to send the packet
        dispatcher.sendPacket(_channelId, payload, timeoutTimestamp);
    }

    function nativeToErc20(
        bytes32 _channelId,
        bytes memory _payload,
        uint256 _timeoutSeconds
    ) external payable nonReentrant checkPayloadLength(_payload.length) checkZeroAmount(msg.value) {
        (uint256 targetNetworkId, bytes32 targetNativeToken, address targetTokenAddress, address to, uint256 slippage) = _decodeNativeToErc20Payload(
            _payload
        );

        uint256 amountIn = msg.value;

        bytes memory data = _encodeNativeToErc20Data(targetNetworkId, targetNativeToken, targetTokenAddress, to, amountIn, slippage);
        bytes memory payload = abi.encode(BridgeType.NATIVE_TO_ERC20, data);

        uint64 timeoutTimestamp = _calculateTimeoutTimestamp(_timeoutSeconds);

        // calling the Dispatcher to send the packet
        dispatcher.sendPacket(_channelId, payload, timeoutTimestamp);
    }

    function erc20ToNative(
        bytes32 _channelId,
        bytes memory _payload,
        uint256 _timeoutSeconds
    ) external nonReentrant checkPayloadLength(_payload.length) {
        (uint256 targetNetworkId, address sourceTokenAddress, address to, uint256 amountIn, uint256 slippage) = abi.decode(
            _payload,
            (uint256, address, address, uint256, uint256)
        );

        if (!supportedTokens[sourceTokenAddress]) {
            revert TokenNotSupported(sourceTokenAddress);
        }

        _transferSourceToken(sourceTokenAddress, amountIn);

        uint256 nativeAmount = _calculateTokenToNativeAmountOut(sourceTokenAddress, amountIn);
        uint256 amountOut = _calculateNativeAmountOut(block.chainid, targetNetworkId, nativeAmount);

        bytes memory data = abi.encode(block.chainid, targetNetworkId, sourceTokenAddress, msg.sender, to, amountIn, amountOut, slippage);
        bytes memory payload = abi.encode(BridgeType.ERC20_TO_NATIVE, data);

        uint64 timeoutTimestamp = uint64((block.timestamp + _timeoutSeconds) * 1000000000);

        // calling the Dispatcher to send the packet
        dispatcher.sendPacket(_channelId, payload, timeoutTimestamp);
    }

    // function erc20ToErc20(
    //     bytes32 _channelId,
    //     bytes memory _payload,
    //     uint256 _timeoutSeconds
    // ) external nonReentrant checkPayloadLength(_payload.length) {
    //     (
    //         uint256 targetNetworkId,
    //         address sourceTokenAddress,
    //         bytes32 targetNativeToken,
    //         address targetTokenAddress,
    //         address to,
    //         uint256 amountIn,
    //         uint256 slippage
    //     ) = abi.decode(_payload, (uint256, address, bytes32, address, address, uint256, uint256));

    //     if (!supportedTokens[sourceTokenAddress]) {
    //         revert TokenNotSupported(sourceTokenAddress);
    //     }

    //     IERC20 sourceToken = IERC20(sourceTokenAddress);

    //     uint256 allowance = sourceToken.allowance(msg.sender, address(this));
    //     if (allowance < amountIn) {
    //         revert InsufficientAllowance(allowance, amountIn);
    //     }

    //     sourceToken.safeTransferFrom(msg.sender, address(this), amountIn);

    //     uint256 nativeAmount = _calculateTokenToNativeAmountOut(sourceTokenAddress, amountIn);
    //     uint256 amountOut = _calculateNativeAmountOut(block.chainid, targetNetworkId, nativeAmount);

    //     bytes memory data = abi.encode(
    //         block.chainid,
    //         targetNetworkId,
    //         sourceTokenAddress,
    //         targetNativeToken,
    //         targetTokenAddress,
    //         msg.sender,
    //         to,
    //         amountIn,
    //         amountOut,
    //         slippage
    //     );
    //     bytes memory payload = abi.encode(BridgeType.ERC20_TO_ERC20, data);

    //     uint64 timeoutTimestamp = uint64((block.timestamp + _timeoutSeconds) * 1000000000);

    //     // calling the Dispatcher to send the packet
    //     dispatcher.sendPacket(_channelId, payload, timeoutTimestamp);
    // }

    /**
     * @dev Packet lifecycle callback that implements packet receipt logic and returns and acknowledgement packet.
     *      MUST be overriden by the inheriting contract.
     *
     * @param packet the IBC packet encoded by the source and relayed by the relayer.
     */
    function onRecvPacket(IbcPacket memory packet) external override onlyIbcDispatcher returns (AckPacket memory ackPacket) {
        recvedPackets.push(packet);

        (
            uint256 srcNetworkId,
            uint256 tgtNetworkId,
            address tgtTokenAddress,
            ,
            address to,
            uint256 amountIn,
            uint256 amountOut,
            uint256 slippage
        ) = abi.decode(packet.data, (uint256, uint256, address, address, address, uint256, uint256, uint256));

        uint256 caBalance = address(this).balance;
        uint256 calculatedAmountOut = _calculateNativeAmountOut(srcNetworkId, tgtNetworkId, amountIn);
        uint256 minAmountOut = amountOut - ((amountOut * slippage) / 10000);

        if (calculatedAmountOut < minAmountOut) {
            return AckPacket(false, packet.data);
        } else if (caBalance < amountOut) {
            return AckPacket(false, packet.data);
        } else {
            if (tgtTokenAddress == address(0)) {
                (bool sent, ) = payable(to).call{value: amountOut}('');
                if (!sent) {
                    return AckPacket(false, packet.data);
                } else {
                    return AckPacket(true, packet.data);
                }
            } else {
                try dex.swapEthToToken{value: amountOut}(tgtTokenAddress, to) {
                    return AckPacket(true, packet.data);
                } catch {
                    return AckPacket(false, packet.data);
                }
            }
        }
    }

    /**
     * @dev Packet lifecycle callback that implements packet acknowledgment logic.
     *      MUST be overriden by the inheriting contract.
     *
     * @param ack the acknowledgment packet encoded by the destination and relayed by the relayer.
     */
    function onAcknowledgementPacket(IbcPacket calldata, AckPacket calldata ack) external override onlyIbcDispatcher {
        ackPackets.push(ack);

        if (!ack.success) {
            (, , , address sender, , uint256 amountIn, , ) = abi.decode(
                ack.data,
                (uint256, uint256, address, address, address, uint256, uint256, uint256)
            );

            (bool sent, ) = payable(sender).call{value: amountIn}('');
            if (!sent) {
                revert InsufficientBalance(address(this).balance, amountIn);
            }
        }
    }

    /**
     * @dev Packet lifecycle callback that implements packet receipt logic and return and acknowledgement packet.
     *      MUST be overriden by the inheriting contract.
     *      NOT SUPPORTED YET
     *
     * @param packet the IBC packet encoded by the counterparty and relayed by the relayer
     */
    function onTimeoutPacket(IbcPacket calldata packet) external override onlyIbcDispatcher {
        timeoutPackets.push(packet);
        // do logic
    }

    /**
     * @dev Withdraw the contract balance to the owner.
     * This function can only be called by the owner of the contract.
     * @param amount The amount to withdraw.
     */
    function withdraw(uint256 amount) external onlyOwner {
        (bool sent, ) = payable(owner()).call{value: amount}('');
        if (!sent) {
            revert InsufficientBalance(address(this).balance, amount);
        }
    }

    function _calculateTimeoutTimestamp(uint256 _timeoutSeconds) internal view returns (uint64) {
        return uint64((block.timestamp + _timeoutSeconds) * 1000000000);
    }

    /**
     * @dev Calculate the amount out.
     * @param _sourceNetworkId The source network ID.
     * @param _targetNetworkId The target network ID.
     * @param _amountIn The amount in.
     * @return The amount out.
     */
    function _calculateNativeAmountOut(uint256 _sourceNetworkId, uint256 _targetNetworkId, uint256 _amountIn) internal view returns (uint256) {
        uint256 sourceNetworkPrice = priceFeeds.getNativePrice(_sourceNetworkId);
        uint256 targetNetworkPrice = priceFeeds.getNativePrice(_targetNetworkId);

        if (sourceNetworkPrice <= 0 || targetNetworkPrice <= 0) {
            revert InvalidCoinPrices();
        }

        return (_amountIn * targetNetworkPrice) / sourceNetworkPrice;
    }

    function _calculateTokenToNativeAmountOut(address _tokenAddress, uint256 _tokenAmount) public view returns (uint256) {
        uint256 tokenPrice = priceFeeds.getTokenPrice(_tokenAddress);
        uint256 nativeCoinPrice = priceFeeds.getNativePrice(block.chainid);

        return (_tokenAmount * tokenPrice) / nativeCoinPrice;
    }

    function _decodeNativeToErc20Payload(bytes memory _payload) internal pure returns (uint256, bytes32, address, address, uint256) {
        return abi.decode(_payload, (uint256, bytes32, address, address, uint256));
    }

    function _encodeNativeToErc20Data(
        uint256 targetNetworkId,
        bytes32 targetNativeToken,
        address targetTokenAddress,
        address to,
        uint256 amountIn,
        uint256 slippage
    ) internal view returns (bytes memory) {
        uint256 amountOut = _calculateNativeAmountOut(block.chainid, targetNetworkId, amountIn);

        return abi.encode(block.chainid, targetNetworkId, targetNativeToken, targetTokenAddress, msg.sender, to, amountIn, amountOut, slippage);
    }

    function _transferSourceToken(address sourceTokenAddress, uint256 amountIn) internal {
        IERC20 sourceToken = IERC20(sourceTokenAddress);

        uint256 allowance = sourceToken.allowance(msg.sender, address(this));
        if (allowance < amountIn) {
            revert InsufficientAllowance(allowance, amountIn);
        }

        sourceToken.safeTransferFrom(msg.sender, address(this), amountIn);
    }

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}
