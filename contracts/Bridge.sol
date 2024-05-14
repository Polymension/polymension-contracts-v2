//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import './base/CustomChanIbcApp.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract Bridge is CustomChanIbcApp {
    using SafeERC20 for IERC20;

    mapping(address => mapping(uint256 => address)) public crossChainTokenRouter; // token => tgtNetworkID => tokenAddress
    mapping(uint256 => mapping(address => uint256)) public crossChainTokenBalance; // tgtNetworkID => token => balance | zero address means native token

    error TokenNotSupported(address tokenAddress);
    error InsufficientTreasuryBalance(uint256 balance, uint256 amount);
    error InsufficientBalance(uint256 balance, uint256 amount);
    error InsufficientAllowance(uint256 allowance, uint256 amount);
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
        crossChainTokenBalance[tgtNetworkID][tgtTokenAddress] += amount;
    }

    /**
     *   @dev Decrease the treasury balance of a token on a target network
     *   @param tgtNetworkID the ID of the target network
     *   @param tgtTokenAddress the address of the token on the target network
     *   @param amount the amount to decrease the treasury balance by
     */
    function decreaseTreasuryBalance(uint256 tgtNetworkID, address tgtTokenAddress, uint256 amount) external onlyOwner {
        uint256 balance = crossChainTokenBalance[tgtNetworkID][tgtTokenAddress];
        if (balance < amount) {
            revert InsufficientTreasuryBalance(balance, amount);
        }
        crossChainTokenBalance[tgtNetworkID][tgtTokenAddress] -= amount;
    }

    /**
     *   @dev Bridge native coins to a target network
     *   @param channelId the ID of the channel
     *   @param tgtNetworkID the ID of the target network
     *   @param to the address to send the coins to
     */
    function bridgeCoins(bytes32 channelId, uint256 tgtNetworkID, address to) external payable checkZeroAddress(to) checkZeroAmount(msg.value) {
        // TODO: implement
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
    ) external checkZeroAddress(to) checkZeroAmount(amount) {
        address sender = msg.sender;
        address tgtTokenAddress = crossChainTokenRouter[srcTokenAddress][tgtNetworkID];
        uint256 treasuryBalance = crossChainTokenBalance[tgtNetworkID][tgtTokenAddress];
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

        crossChainTokenBalance[tgtNetworkID][tgtTokenAddress] -= amount;

        bytes memory payload = abi.encode(false, tgtNetworkID, srcTokenAddress, tgtTokenAddress, sender, to, amount);
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

        (bool isNativeTransfer, , , address tgtTokenAddress, , address to, uint256 amount) = abi.decode(
            packet.data,
            (bool, uint256, address, address, address, address, uint256)
        );

        if (isNativeTransfer) {
            // for native token
        } else {
            IERC20 token = IERC20(tgtTokenAddress);
            if (token.balanceOf(address(this)) < amount) {
                return AckPacket(false, packet.data);
            } else {
                token.safeTransfer(to, amount);
                return AckPacket(true, packet.data);
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
            (bool isNativeTransfer, uint256 tgtNetworkID, address srcTokenAddress, address tgtTokenAddress, address sender, , uint256 amount) = abi
                .decode(ack.data, (bool, uint256, address, address, address, address, uint256));

            if (isNativeTransfer) {
                // for native token
            } else {
                IERC20 token = IERC20(srcTokenAddress);
                token.safeTransfer(sender, amount);
                crossChainTokenBalance[tgtNetworkID][tgtTokenAddress] += amount;
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
}
