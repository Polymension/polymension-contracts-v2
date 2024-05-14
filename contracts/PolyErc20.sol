//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import './base/CustomChanIbcApp.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract PolyErc20 is CustomChanIbcApp, ERC20 {
    constructor(
        IbcDispatcher _dispatcher,
        string memory tokenName_,
        string memory tokenSymbol_,
        uint256 tokenSupply_
    ) ERC20(tokenName_, tokenSymbol_) CustomChanIbcApp(_dispatcher) {
        _mint(msg.sender, tokenSupply_);
    }

    // IBC logic

    /**
     * @dev Sends a packet with the caller address over a specified channel.
     * @param channelId The ID of the channel (locally) to send the packet to.
     * @param timeoutSeconds The timeout in seconds (relative).
     */

    function sendPacket(bytes32 channelId, uint64 timeoutSeconds, bytes memory payload) internal {
        // setting the timeout timestamp at 10h from now
        uint64 timeoutTimestamp = uint64((block.timestamp + timeoutSeconds) * 1000000000);

        // calling the Dispatcher to send the packet
        dispatcher.sendPacket(channelId, payload, timeoutTimestamp);
    }

    function bridgeTokens(bytes32 channelId, address from, address to, uint256 amount) external {
        require(from == msg.sender, 'Only from address');

        // send packet
        bytes memory payload = abi.encode(from, to, amount);
        sendPacket(channelId, 10 hours, payload);
    }

    /**
     * @dev Packet lifecycle callback that implements packet receipt logic and returns and acknowledgement packet.
     *      MUST be overriden by the inheriting contract.
     *
     * @param packet the IBC packet encoded by the source and relayed by the relayer.
     */
    function onRecvPacket(IbcPacket memory packet) external override onlyIbcDispatcher returns (AckPacket memory ackPacket) {
        recvedPackets.push(packet);

        (address from, address to, uint256 amount) = abi.decode(packet.data, (address, address, uint256));

        // mint tokens
        _mint(to, amount);

        return AckPacket(true, packet.data);
    }

    /**
     * @dev Packet lifecycle callback that implements packet acknowledgment logic.
     *      MUST be overriden by the inheriting contract.
     *
     * @param ack the acknowledgment packet encoded by the destination and relayed by the relayer.
     */
    function onAcknowledgementPacket(IbcPacket calldata, AckPacket calldata ack) external override onlyIbcDispatcher {
        ackPackets.push(ack);

        (address from, address to, uint256 amount) = abi.decode(ack.data, (address, address, uint256));

        // burn tokens
        _burn(from, amount);
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
}
