//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import './base/CustomChanIbcApp.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {BridgeType} from './libraries/Utils/Polymer/Enum.sol';
import {AbiUtils} from './libraries/Utils/Polymer/Abi.sol';
import {IVaultNative, IVaultToken} from './interfaces/IVault.sol';
import {IPriceFeeds} from './interfaces/IPriceFeeds.sol';
import {IDex} from './interfaces/IDex.sol';

contract Bridge is CustomChanIbcApp, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IPriceFeeds public priceFeeds;
    IDex public dex;

    mapping(bytes32 => uint256) public chainIdFromChannelId; // channel id => chain id
    mapping(address => address) public vaultContractFromAddress; // token & zero address => vault contract address

    uint256 public platformSlippage = 100; // 1% (100/10000)

    error TokenNotSupported();
    error InsufficientBalance();
    error InsufficientAllowance();
    error InvalidCoinPrices();
    error InvalidPayload();
    error ZeroChannelId();
    error ZeroAddress();
    error ZeroAmount();
    error FailedTransfer();
    error FailedSwap();

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

    function nativeToNative(
        bytes32 _targetChannelId,
        bytes memory _inputs,
        uint256 _timeoutSeconds
    ) external payable nonReentrant checkPayloadLength(_inputs.length) checkZeroAmount(msg.value) {
        (bytes32 sourceChannelId, address to, uint256 minAmountOut) = AbiUtils._decodeNativeToNativeInputs(_inputs);

        uint256 amountIn = msg.value;
        uint256 sourceAmountOut = _calculateNativeToNativeAmountOut(sourceChannelId, _targetChannelId, amountIn);
        bytes memory data = AbiUtils._encodeNativeToNativeData(msg.sender, to, amountIn, sourceAmountOut, minAmountOut);
        bytes memory payload = AbiUtils._encodePayload(BridgeType.NATIVE_TO_NATIVE, data);
        uint64 timeoutTimestamp = _calculateTimeoutTimestamp(_timeoutSeconds);

        _transferNativeToVault(_getVaultContractAddress(address(0)), amountIn);

        // calling the Dispatcher to send the packet
        dispatcher.sendPacket(_targetChannelId, payload, timeoutTimestamp);
    }

    function nativeToToken(
        bytes32 _targetChannelId,
        bytes memory _inputs,
        uint256 _timeoutSeconds
    ) external payable nonReentrant checkPayloadLength(_inputs.length) checkZeroAmount(msg.value) {
        (bytes32 sourceChannelId, address to, address targetTokenAddress, uint256 minAmountOut) = AbiUtils._decodeNativeToTokenInputs(_inputs);

        uint256 amountIn = msg.value;
        uint256 sourceAmountOut = _calculateNativeToNativeAmountOut(sourceChannelId, _targetChannelId, amountIn);
        bytes memory data = AbiUtils._encodeNativeToTokenData(msg.sender, to, targetTokenAddress, amountIn, sourceAmountOut, minAmountOut);
        bytes memory payload = AbiUtils._encodePayload(BridgeType.NATIVE_TO_TOKEN, data);
        uint64 timeoutTimestamp = _calculateTimeoutTimestamp(_timeoutSeconds);

        _transferNativeToVault(_getVaultContractAddress(address(0)), amountIn);

        // calling the Dispatcher to send the packet
        dispatcher.sendPacket(_targetChannelId, payload, timeoutTimestamp);
    }

    function tokenToNative(
        bytes32 _targetChannelId,
        bytes memory _inputs,
        uint256 _timeoutSeconds
    ) external nonReentrant checkPayloadLength(_inputs.length) {
        (address to, address sourceTokenAddress, uint256 amountIn, uint256 minAmountOut) = AbiUtils._decodeTokenToNativeInputs(_inputs);

        if (sourceTokenAddress == address(0)) {
            revert ZeroAddress();
        }

        address vaultAddress = _getVaultContractAddress(sourceTokenAddress);
        if (vaultAddress == address(0)) {
            revert TokenNotSupported();
        }

        uint256 sourceAmountOut = _calculateExchangeAmount(sourceTokenAddress, amountIn);
        bytes memory data = AbiUtils._encodeTokenToNativeData(msg.sender, to, sourceTokenAddress, amountIn, sourceAmountOut, minAmountOut);
        bytes memory payload = AbiUtils._encodePayload(BridgeType.TOKEN_TO_NATIVE, data);
        uint64 timeoutTimestamp = _calculateTimeoutTimestamp(_timeoutSeconds);

        _transferTokenToVault(vaultAddress, sourceTokenAddress, amountIn);

        // calling the Dispatcher to send the packet
        dispatcher.sendPacket(_targetChannelId, payload, timeoutTimestamp);
    }

    function tokenToToken(
        bytes32 _targetChannelId,
        bytes memory _inputs,
        uint256 _timeoutSeconds
    ) external nonReentrant checkPayloadLength(_inputs.length) {
        (address to, address sourceTokenAddress, address targetTokenAddress, uint256 amountIn, uint256 minAmountOut) = AbiUtils
            ._decodeTokenToTokenInputs(_inputs);

        if (sourceTokenAddress == address(0)) {
            revert ZeroAddress();
        }

        address vaultAddress = _getVaultContractAddress(sourceTokenAddress);
        if (vaultAddress == address(0)) {
            revert TokenNotSupported();
        }

        uint256 sourceAmountOut = _calculateExchangeAmount(sourceTokenAddress, amountIn);
        bytes memory data = AbiUtils._encodeTokenToTokenData(
            msg.sender,
            to,
            sourceTokenAddress,
            targetTokenAddress,
            amountIn,
            sourceAmountOut,
            minAmountOut
        );
        bytes memory payload = AbiUtils._encodePayload(BridgeType.TOKEN_TO_TOKEN, data);
        uint64 timeoutTimestamp = _calculateTimeoutTimestamp(_timeoutSeconds);

        _transferTokenToVault(vaultAddress, sourceTokenAddress, amountIn);

        // calling the Dispatcher to send the packet
        dispatcher.sendPacket(_targetChannelId, payload, timeoutTimestamp);
    }

    /**
     * @dev Packet lifecycle callback that implements packet receipt logic and returns and acknowledgement packet.
     *      MUST be overriden by the inheriting contract.
     *
     * @param packet the IBC packet encoded by the source and relayed by the relayer.
     */
    function onRecvPacket(IbcPacket memory packet) external override onlyIbcDispatcher returns (AckPacket memory ackPacket) {
        recvedPackets.push(packet);
        (bytes32 sourceChannelId, bytes32 targetChannelId, BridgeType bridgeType, bytes memory data) = AbiUtils._decodePacket(packet);
        if (bridgeType == BridgeType.NATIVE_TO_NATIVE) {
            return _onRecvNativeToNative(sourceChannelId, targetChannelId, data);
        } else if (bridgeType == BridgeType.NATIVE_TO_TOKEN) {
            return _onRecvNativeToToken(sourceChannelId, targetChannelId, data);
        } else if (bridgeType == BridgeType.TOKEN_TO_NATIVE) {
            return _onRecvTokenToNative(sourceChannelId, targetChannelId, data);
        } else if (bridgeType == BridgeType.TOKEN_TO_TOKEN) {
            return _onRecvTokenToToken(sourceChannelId, targetChannelId, data);
        } else {
            return AckPacket(false, packet.data);
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
            (BridgeType bridgeType, bytes memory data) = AbiUtils._decodePayload(ack.data);
            if (bridgeType == BridgeType.NATIVE_TO_NATIVE) {
                (address sender, , uint256 amountIn, , ) = AbiUtils._decodeNativeToNativeData(data);
                address vaultAddress = _getVaultContractAddress(address(0));

                _transferNativeToSender(vaultAddress, sender, amountIn);
            } else if (bridgeType == BridgeType.NATIVE_TO_TOKEN) {
                (address sender, , , uint256 amountIn, , ) = AbiUtils._decodeNativeToTokenData(data);
                address vaultAddress = _getVaultContractAddress(address(0));

                _transferNativeToSender(vaultAddress, sender, amountIn);
            } else if (bridgeType == BridgeType.TOKEN_TO_NATIVE) {
                (address sender, , address tokenAddress, uint256 amountIn, , ) = AbiUtils._decodeTokenToNativeData(data);
                address vaultAddress = _getVaultContractAddress(tokenAddress);

                _transferTokenToSender(vaultAddress, sender, amountIn);
            } else if (bridgeType == BridgeType.TOKEN_TO_TOKEN) {
                (address sender, , address tokenAddress, , uint256 amountIn, , ) = AbiUtils._decodeTokenToTokenData(data);
                address vaultAddress = _getVaultContractAddress(tokenAddress);

                _transferTokenToSender(vaultAddress, sender, amountIn);
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

    function _getChainId(bytes32 _channelId) internal view returns (uint256) {
        return chainIdFromChannelId[_channelId];
    }

    function _getVaultContractAddress(address _tokenAddress) internal view returns (address) {
        return vaultContractFromAddress[_tokenAddress];
    }

    function _calculateTimeoutTimestamp(uint256 _timeoutSeconds) internal view returns (uint64) {
        return uint64((block.timestamp + _timeoutSeconds) * 1000000000);
    }

    function _calculateNativeToNativeAmountOut(
        bytes32 _sourceChannelId,
        bytes32 _targetChannelId,
        uint256 _amountIn
    ) internal view returns (uint256) {
        if (_sourceChannelId == bytes32(0) || _targetChannelId == bytes32(0)) {
            revert ZeroAddress();
        }
        if (_sourceChannelId == _targetChannelId) {
            return _amountIn;
        }

        uint256 sourceChainId = _getChainId(_sourceChannelId);
        uint256 targetChainId = _getChainId(_targetChannelId);

        uint256 sourceChainCoinPrice = priceFeeds.getNativePrice(sourceChainId);
        uint256 targetChainCoinPrice = priceFeeds.getNativePrice(targetChainId);

        if (sourceChainCoinPrice <= 0 || targetChainCoinPrice <= 0) {
            revert InvalidCoinPrices();
        }

        return (_amountIn * targetChainCoinPrice) / sourceChainCoinPrice;
    }

    function _calculateExchangeAmount(address _tokenAddress, uint256 _amountIn) public view returns (uint256) {
        uint256 tokenPrice = priceFeeds.getTokenPrice(_tokenAddress);
        uint256 nativeCoinPrice = priceFeeds.getNativePrice(block.chainid);

        return (_amountIn * tokenPrice) / nativeCoinPrice;
    }

    function _transferNativeToVault(address _vaultAddress, uint256 _amount) internal {
        (bool sent, ) = payable(_vaultAddress).call{value: _amount}('');
        if (!sent) {
            revert FailedTransfer();
        }
    }

    function _transferNativeToSender(address _vaultAddress, address _to, uint256 _amount) internal {
        IVaultNative vault = IVaultNative(_vaultAddress);

        try vault.transferNative(_to, _amount) {
            return;
        } catch {
            revert FailedTransfer();
        }
    }

    function _transferTokenToVault(address _vaultAddress, address _tokenAddress, uint256 _amount) internal {
        IERC20 token = IERC20(_tokenAddress);

        uint256 allowance = token.allowance(msg.sender, address(this));
        if (allowance < _amount) {
            revert InsufficientAllowance();
        }

        token.safeTransferFrom(msg.sender, _vaultAddress, _amount);
    }

    function _transferTokenToSender(address _vaultAddress, address _to, uint256 _amount) internal {
        IVaultToken vault = IVaultToken(_vaultAddress);

        try vault.transferToken(_to, _amount) {
            return;
        } catch {
            revert FailedTransfer();
        }
    }

    function _onRecvNativeToNative(
        bytes32 _sourceChannelId,
        bytes32 _targetChannelId,
        bytes memory _data
    ) internal returns (AckPacket memory ackPacket) {
        (, address to, uint256 amountIn, uint256 sourceAmountOut, uint256 minAmountOut) = AbiUtils._decodeNativeToNativeData(_data);

        bool isSuccess = _onRecvNativeTransfer(_sourceChannelId, _targetChannelId, to, amountIn, sourceAmountOut, minAmountOut);

        if (isSuccess) {
            return AckPacket(true, _data);
        } else {
            return AckPacket(false, _data);
        }
    }

    function _onRecvNativeToToken(
        bytes32 _sourceChannelId,
        bytes32 _targetChannelId,
        bytes memory _data
    ) internal returns (AckPacket memory ackPacket) {
        (, address to, address targetTokenAddress, uint256 amountIn, uint256 sourceAmountOut, uint256 minAmountOut) = AbiUtils
            ._decodeNativeToTokenData(_data);

        bool isSuccess = _onRecvTokenTransfer(_sourceChannelId, _targetChannelId, to, targetTokenAddress, amountIn, sourceAmountOut, minAmountOut);

        if (isSuccess) {
            return AckPacket(true, _data);
        } else {
            return AckPacket(false, _data);
        }
    }

    function _onRecvTokenToNative(
        bytes32 _sourceChannelId,
        bytes32 _targetChannelId,
        bytes memory _data
    ) internal returns (AckPacket memory ackPacket) {
        (, address to, , uint256 amountIn, uint256 sourceAmountOut, uint256 minAmountOut) = AbiUtils._decodeTokenToNativeData(_data);

        bool isSuccess = _onRecvNativeTransfer(_sourceChannelId, _targetChannelId, to, amountIn, sourceAmountOut, minAmountOut);

        if (isSuccess) {
            return AckPacket(true, _data);
        } else {
            return AckPacket(false, _data);
        }
    }

    function _onRecvTokenToToken(
        bytes32 _sourceChannelId,
        bytes32 _targetChannelId,
        bytes memory _data
    ) internal returns (AckPacket memory ackPacket) {
        (, address to, , address targetTokenAddress, uint256 amountIn, uint256 sourceAmountOut, uint256 minAmountOut) = AbiUtils
            ._decodeTokenToTokenData(_data);

        bool isSuccess = _onRecvTokenTransfer(_sourceChannelId, _targetChannelId, to, targetTokenAddress, amountIn, sourceAmountOut, minAmountOut);

        if (isSuccess) {
            return AckPacket(true, _data);
        } else {
            return AckPacket(false, _data);
        }
    }

    function _onRecvNativeTransfer(
        bytes32 _sourceChannelId,
        bytes32 _targetChannelId,
        address _to,
        uint256 _amountIn,
        uint256 _sourceAmountOut,
        uint256 _minAmountOut
    ) internal returns (bool) {
        uint256 maxAmountOut = _sourceAmountOut + ((_sourceAmountOut * platformSlippage) / 10000);
        uint256 targetAmountOut = _calculateNativeToNativeAmountOut(_sourceChannelId, _targetChannelId, _amountIn);

        if (targetAmountOut < _minAmountOut || targetAmountOut > maxAmountOut) {
            return false;
        }

        address vaultAddress = _getVaultContractAddress(address(0));

        if (vaultAddress == address(0)) {
            return false;
        }

        IVaultNative vault = IVaultNative(vaultAddress);

        try vault.transferNative(_to, targetAmountOut) {
            return true;
        } catch {
            return false;
        }
    }

    function _onRecvTokenTransfer(
        bytes32 _sourceChannelId,
        bytes32 _targetChannelId,
        address _to,
        address _tokenAddress,
        uint256 _amountIn,
        uint256 _sourceAmountOut,
        uint256 _minAmountOut
    ) internal returns (bool) {
        uint256 maxAmountOut = _sourceAmountOut + ((_sourceAmountOut * platformSlippage) / 10000);
        uint256 targetAmountOut = _calculateNativeToNativeAmountOut(_sourceChannelId, _targetChannelId, _amountIn);

        if (targetAmountOut < _minAmountOut || targetAmountOut > maxAmountOut) {
            return false;
        }

        address vaultAddress = _getVaultContractAddress(_tokenAddress);

        if (vaultAddress == address(0)) {
            vaultAddress = _getVaultContractAddress(address(0));

            if (vaultAddress == address(0) || address(vaultAddress).balance < targetAmountOut) {
                return false;
            }

            IVaultNative vault = IVaultNative(vaultAddress);

            try vault.transferNative(address(this), targetAmountOut) {
                try dex.swapNativeToToken{value: targetAmountOut}(_tokenAddress, _to) {
                    return false;
                } catch {
                    return false;
                }
            } catch {
                return false;
            }
        } else {
            IVaultToken vault = IVaultToken(vaultAddress);

            uint256 targetTokenAmountOut = _calculateExchangeAmount(_tokenAddress, targetAmountOut);

            try vault.transferToken(_to, targetTokenAmountOut) {
                return true;
            } catch {
                return false;
            }
        }
    }

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}
