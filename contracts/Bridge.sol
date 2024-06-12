//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./base/CustomChanIbcApp.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {PriceFeeds} from "./PriceFeeds.sol";

contract Bridge is CustomChanIbcApp, ReentrancyGuard {
    using SafeERC20 for IERC20;

    PriceFeeds public priceAggregator;

    mapping(address => mapping(uint256 => address)) public crossChainTokenRouter; // token => tgtNetworkID => tokenAddress
    mapping(uint256 => mapping(address => uint256)) public crossChainBalance; // tgtNetworkID => token => balance | zero address means native token

    error TokenNotSupported(address tokenAddress);
    error InsufficientTreasuryBalance(uint256 balance, uint256 amount);
    error InsufficientBalance(uint256 balance, uint256 amount);
    error InsufficientAllowance(uint256 allowance, uint256 amount);
    error InvalidCoinPrices();
    error InvalidParameter();
    error ZeroAddress();
    error ZeroAmount();

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

    constructor(IbcDispatcher _dispatcher) CustomChanIbcApp(_dispatcher) {}

    /**
     *   @dev Set the oracle contract
     *   @param _oracle the address of the oracle contract
     */
    function setOracle(address _oracle) external onlyOwner {
        priceAggregator = PriceFeeds(_oracle);
    }

    /**
     *   @dev Support a token on a target network
     *   @param srcTokenAddress the address of the token on the source network
     *   @param tgtNetworkID the ID of the target network
     *   @param tgtTokenAddress the address of the token on the target network
     */
    function supportToken(address srcTokenAddress, uint256 tgtNetworkID, address tgtTokenAddress) external onlyOwner {
        crossChainTokenRouter[srcTokenAddress][tgtNetworkID] = tgtTokenAddress;
    }

    /**
     *   @dev Increase the treasury balance of a token on a target network
     *   @param tgtNetworkID the ID of the target network
     *   @param tgtTokenAddress the address of the token on the target network
     *   @param amount the amount to increase the treasury balance by
     */
    function increaseTreasuryBalance(uint256 tgtNetworkID, address tgtTokenAddress, uint256 amount) external onlyOwner {
        crossChainBalance[tgtNetworkID][tgtTokenAddress] += amount;
    }

    /**
     *   @dev Decrease the treasury balance of a token on a target network
     *   @param tgtNetworkID the ID of the target network
     *   @param tgtTokenAddress the address of the token on the target network
     *   @param amount the amount to decrease the treasury balance by
     */
    function decreaseTreasuryBalance(uint256 tgtNetworkID, address tgtTokenAddress, uint256 amount) external onlyOwner {
        uint256 balance = crossChainBalance[tgtNetworkID][tgtTokenAddress];
        if (balance < amount) {
            revert InsufficientTreasuryBalance(balance, amount);
        }
        crossChainBalance[tgtNetworkID][tgtTokenAddress] -= amount;
    }

    /**
     *   @dev Bridge native coins to a target network
     *   @param channelId the ID of the channel
     *   @param tgtNetworkID the ID of the target network
     *   @param to the address to send the coins to
     */
    function bridgeCoins(
        bytes32 channelId,
        uint256 tgtNetworkID,
        address to,
        uint256 slippage
    ) external payable nonReentrant checkZeroAddress(to) checkZeroAmount(msg.value) {
        uint256 amountOut = _calculateAmountOut(block.chainid, tgtNetworkID, msg.value);

        crossChainBalance[tgtNetworkID][address(0)] -= amountOut;

        bytes memory bridgeData = abi.encode(block.chainid, tgtNetworkID, msg.sender, to, msg.value, amountOut, slippage);
        bytes memory payload = abi.encode(true, bridgeData);
        _sendPacket(channelId, 10 hours, payload);
    }

    /**
     *   @dev Bridge tokens to a target network
     *   @param channelId the ID of the channel
     *   @param srcTokenAddress the address of the token on the source network
     *   @param tgtNetworkID the ID of the target network
     *   @param to the address to send the tokens to
     *   @param amount the amount of tokens to send
     */
    function bridgeTokens(
        bytes32 channelId,
        address srcTokenAddress,
        uint256 tgtNetworkID,
        address to,
        uint256 amount
    ) external nonReentrant checkZeroAddress(to) checkZeroAmount(amount) {
        address sender = msg.sender;
        address tgtTokenAddress = crossChainTokenRouter[srcTokenAddress][tgtNetworkID];
        uint256 treasuryBalance = crossChainBalance[tgtNetworkID][tgtTokenAddress];
        if (tgtTokenAddress == address(0)) {
            revert TokenNotSupported(tgtTokenAddress);
        }
        if (treasuryBalance < amount) {
            revert InsufficientTreasuryBalance(treasuryBalance, amount);
        }

        IERC20 token = IERC20(srcTokenAddress);
        uint256 balance = token.balanceOf(sender);
        if (balance < amount) {
            revert InsufficientBalance(balance, amount);
        }

        uint256 allowance = token.allowance(sender, address(this));
        if (allowance < amount) {
            revert InsufficientAllowance(allowance, amount);
        }

        token.safeTransferFrom(sender, address(this), amount);

        crossChainBalance[tgtNetworkID][tgtTokenAddress] -= amount;

        bytes memory bridgeData = abi.encode(block.chainid, tgtNetworkID, srcTokenAddress, tgtTokenAddress, sender, to, amount);
        bytes memory payload = abi.encode(false, bridgeData);
        _sendPacket(channelId, 10 hours, payload);
    }

    /**
     * @dev Packet lifecycle callback that implements packet receipt logic and returns and acknowledgement packet.
     *      MUST be overriden by the inheriting contract.
     *
     * @param packet the IBC packet encoded by the source and relayed by the relayer.
     */
    function onRecvPacket(IbcPacket memory packet) external override onlyIbcDispatcher returns (AckPacket memory ackPacket) {
        recvedPackets.push(packet);

        (bool isNativeTransfer, bytes memory bridgeData) = abi.decode(packet.data, (bool, bytes));

        if (isNativeTransfer) {
            uint256 balance = address(this).balance;
            (uint256 srcNetworkID, , , address to, , uint256 amountOut, uint256 slippage) = abi.decode(
                bridgeData,
                (uint256, uint256, address, address, uint256, uint256, uint256)
            );

            uint256 calculatedAmountOut = _calculateAmountOut(srcNetworkID, block.chainid, amountOut);
            uint256 slippageAmount = (amountOut * slippage) / 10000;

            if (calculatedAmountOut < amountOut - slippageAmount) {
                return AckPacket(false, packet.data);
            } else if (balance < amountOut) {
                return AckPacket(false, packet.data);
            } else {
                (bool sent, ) = payable(to).call{value: amountOut}("");
                if (!sent) {
                    return AckPacket(false, packet.data);
                }
                crossChainBalance[srcNetworkID][address(0)] += amountOut;
                return AckPacket(true, packet.data);
            }
        } else {
            (uint256 srcNetworkID, , address srcTokenAddress, address tgtTokenAddress, , address to, uint256 amount) = abi.decode(
                bridgeData,
                (uint256, uint256, address, address, address, address, uint256)
            );
            IERC20 token = IERC20(tgtTokenAddress);
            if (token.balanceOf(address(this)) < amount) {
                return AckPacket(false, packet.data);
            } else {
                try token.transfer(to, amount) {
                    crossChainBalance[srcNetworkID][srcTokenAddress] += amount;
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
            (bool isNativeTransfer, bytes memory bridgeData) = abi.decode(ack.data, (bool, bytes));

            if (isNativeTransfer) {
                (, uint256 tgtNetworkID, address sender, , uint256 amountIn, , ) = abi.decode(
                    bridgeData,
                    (uint256, uint256, address, address, uint256, uint256, uint256)
                );
                (bool sent, ) = payable(sender).call{value: amountIn}("");
                if (!sent) {
                    revert InsufficientBalance(address(this).balance, amountIn);
                }
                crossChainBalance[tgtNetworkID][address(0)] += amountIn;
            } else {
                (, uint256 tgtNetworkID, address srcTokenAddress, address tgtTokenAddress, address sender, , uint256 amount) = abi.decode(
                    bridgeData,
                    (uint256, uint256, address, address, address, address, uint256)
                );
                IERC20 token = IERC20(srcTokenAddress);
                token.safeTransfer(sender, amount);
                crossChainBalance[tgtNetworkID][tgtTokenAddress] += amount;
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
     * @dev Sends a packet with the caller address over a specified channel.
     * @param channelId The ID of the channel (locally) to send the packet to.
     * @param timeoutSeconds The timeout in seconds (relative).
     */
    function _sendPacket(bytes32 channelId, uint64 timeoutSeconds, bytes memory payload) internal {
        // setting the timeout timestamp at 10h from now
        uint64 timeoutTimestamp = uint64((block.timestamp + timeoutSeconds) * 1000000000);

        // calling the Dispatcher to send the packet
        dispatcher.sendPacket(channelId, payload, timeoutTimestamp);
    }

    function _calculateAmountOut(uint256 srcNetworkID, uint256 tgtNetworkID, uint256 amountIn) internal view returns (uint256) {
        (int srcNetworkCoinPrice, int32 srcNetworkCoinDecimals) = priceAggregator.getPrice(srcNetworkID);
        (int tgtNetworkCoinPrice, int32 tgtNetworkCoinDecimals) = priceAggregator.getPrice(tgtNetworkID);

        if (srcNetworkCoinPrice <= 0 || tgtNetworkCoinPrice <= 0) {
            revert InvalidCoinPrices();
        }

        uint256 srcPriceInWei = uint256(int256(srcNetworkCoinPrice)) * 10 ** uint256(int256(18 + srcNetworkCoinDecimals));
        uint256 tgtPriceInWei = uint256(int256(tgtNetworkCoinPrice)) * 10 ** uint256(int256(18 + tgtNetworkCoinDecimals));

        uint256 amountOut = (amountIn * tgtPriceInWei) / srcPriceInWei;

        return amountOut;
    }

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}