//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./base/CustomChanIbcApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "./security/ReentrancyGuard.sol";

contract BridgeNFT is CustomChanIbcApp, ReentrancyGuard {
    address private _berc721;

    mapping(address => mapping(uint256 => bool)) public isSupportedToken;

    error TokenCannotBeBridged();
    error InsufficientApproval(uint256 allowance, uint256 amount);
    error InvalidParameter();
    error ZeroAddress();
    error NonexistentToken(uint256 tokenId);

    event BridgeToken(bytes payload);

    modifier checkZeroAddress(address addr) {
        if (addr == address(0)) {
            revert ZeroAddress();
        }
        _;
    }

    modifier checkZeroAmount(address nftCA, address addr, uint256 tokenId) {
        IERC721 token = IERC721(nftCA);
        if (token.ownerOf(tokenId) != addr) {
            revert NonexistentToken(tokenId);
        }
        _;
    }

    modifier checkBERC721(address nftCA) {
        if (nftCA == _berc721) {
            revert TokenCannotBeBridged();
        }
        _;
    }

    constructor(IbcDispatcher _dispatcher, address _initialOwner) CustomChanIbcApp(_dispatcher) Ownable(_initialOwner) {}

    /**
     *   @dev Set the address of the BERC721 contract
     *   @param berc721 the address of the BERC721 contract
     */
    function setBERC721Address(address berc721) external onlyOwner {
        _berc721 = berc721;
    }

    /**
     * @dev Support a token for bridging
     * @param srcTokenAddress the address of the token to be bridged
     * @param tgtNetworkID the network ID of the target chain
     */
    function supportToken(address srcTokenAddress, uint256 tgtNetworkID) external onlyOwner {
        isSupportedToken[srcTokenAddress][tgtNetworkID] = true;
    }

    function bridgeToken(
        bytes32 channelId,
        address srcTokenAddress,
        uint256 tgtNetworkID,
        address to,
        uint256 tokenId
    ) external nonReentrant checkZeroAddress(to) checkZeroAmount(srcTokenAddress, msg.sender, tokenId) checkBERC721(srcTokenAddress) {
        address sender = msg.sender;
        if (!isSupportedToken[srcTokenAddress][tgtNetworkID]) {
            revert TokenCannotBeBridged();
        }

        IERC721 token = IERC721(srcTokenAddress);

        uint256 spender = token.getApproved(tokenId);
        if (spender != address(this)) {
            revert InsufficientApproval(spender, tokenId);
        }

        token.safeTransferFrom(sender, address(this), tokenId);

        bytes memory payload = abi.encode(block.chainid, tgtNetworkID, srcTokenAddress, sender, to, tokenId);
        _sendPacket(channelId, 10 hours, payload);

        emit BridgeToken(payload);
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
