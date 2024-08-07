//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import './base/CustomChanIbcApp.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import {IPriceFeeds} from './interfaces/IPriceFeeds.sol';
import {IDex} from './interfaces/IDex.sol';

contract Bridge is CustomChanIbcApp, ReentrancyGuard {
    IPriceFeeds public priceFeeds;
    IDex public dex;

    error TokenNotSupported(address tokenAddress);
    error InsufficientBalance(uint256 balance, uint256 amount);
    error InvalidCoinPrices();
    error ZeroAddress();
    error ZeroAmount();

    modifier checkZeroAddress(address addr) {
        if (addr == address(0)) {
            revert ZeroAddress();
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
     * @dev Bridge the token from one network to another.
     * Performs checks on address, amount, and token support status.
     * Uses non-reentrant guard to prevent reentrancy attacks.
     * @param _channelId The channel ID.
     * @param _srcTokenAddress The address of the source token.
     * @param _tgtNetworkId The ID of the target network.
     * @param _tgtTokenAddress The address of the target token.
     * @param _to The address to send the token to.
     * @param _slippage The allowed slippage percentage.
     * @param _timeoutSeconds The timeout in seconds.
     */
    function bridge(
        bytes32 _channelId,
        address _srcTokenAddress,
        uint256 _tgtNetworkId,
        address _tgtTokenAddress,
        address _to,
        uint256 _amount,
        uint256 _slippage,
        uint256 _timeoutSeconds
    ) external payable nonReentrant checkZeroAddress(_to) {
        uint256 amount = msg.value;

        if (msg.value == 0) {
            try dex.swapTokenToEth(_srcTokenAddress, _amount, address(this)) returns (uint256[] memory amounts) {
                amount = amounts[amounts.length - 1];
            } catch {
                revert TokenNotSupported(_srcTokenAddress);
            }
        }

        uint256 amountOut = _calculateAmountOut(block.chainid, _tgtNetworkId, amount);

        bytes memory payload = abi.encode(block.chainid, _tgtNetworkId, _tgtTokenAddress, msg.sender, _to, amount, amountOut, _slippage);
        uint64 timeoutTimestamp = uint64((block.timestamp + _timeoutSeconds) * 1000000000);

        // calling the Dispatcher to send the packet
        dispatcher.sendPacket(_channelId, payload, timeoutTimestamp);
    }

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
        uint256 calculatedAmountOut = _calculateAmountOut(srcNetworkId, tgtNetworkId, amountIn);
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

    /**
     * @dev Calculates the output token amount based on source and target network prices.
     * @param srcNetworkId ID of the source network.
     * @param tgtNetworkId ID of the target network.
     * @param amountIn Input amount of tokens.
     * @return Calculated output amount of tokens.
     *
     * Fetches prices from the oracle. Reverts if prices are invalid.
     */
    function _calculateAmountOut(uint256 srcNetworkId, uint256 tgtNetworkId, uint256 amountIn) internal view returns (uint256) {
        uint256 srcNetworkPrice = priceFeeds.getPrice(srcNetworkId);
        uint256 tgtNetworkPrice = priceFeeds.getPrice(tgtNetworkId);

        if (srcNetworkPrice <= 0 || tgtNetworkPrice <= 0) {
            revert InvalidCoinPrices();
        }

        return (amountIn * tgtNetworkPrice) / srcNetworkPrice;
    }

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}
