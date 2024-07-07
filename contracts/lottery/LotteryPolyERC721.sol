//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '../base/CustomChanIbcApp.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '@openzeppelin/contracts/utils/Strings.sol';

library LotteryErrors {
    error IncorrectSender();

    error InsufficientFee();
}

/// Example contract using Pyth Entropy to allow a user to flip a secure fair coin.
/// Users interact with the contract by requesting a random number from the entropy provider.
/// The entropy provider will then fulfill the request by revealing their random number.
/// Once the provider has fulfilled their request the entropy contract will call back
/// the requesting contract with the generated random number.
///
/// The CoinFlip contract implements the IEntropyConsumer interface imported from the Solidity SDK.
/// The interface helps in integrating with Entropy correctly.
contract LotteryPolyERC721 is ERC721Enumerable, CustomChanIbcApp {
    using Strings for uint256;

    // state variables
    address public lottery;
    uint256 public nextMintId;
    uint256 public maxMintId;
    string public baseUri;
    string public baseExtension = '.json';

    // events
    // Event emitted when a coin flip is requested. The sequence number can be used to identify a request
    event LotteryMinted(address winner, uint256 id);
    event TokenBridged(bytes32 channelId, address sender, uint256 tokenId);
    event TokenReceived(address sender, uint256 tokenId);

    // modifiers
    modifier onlyLottery() {
        require(msg.sender == lottery, 'Only lottery contract can run this!');
        _;
    }

    // mappings
    mapping(uint256 tokenId => address owner) public getOwnerFromLockedTokenId;

    // constructor
    constructor(
        IbcDispatcher _dispatcher,
        address _lottery,
        uint256 _startMintId,
        uint256 _endMintId,
        string memory _baseUri
    ) CustomChanIbcApp(_dispatcher) ERC721('Polymension Lottery', 'POLYLOTTERY') {
        lottery = _lottery;
        nextMintId = _startMintId;
        maxMintId = _endMintId;
        baseUri = _baseUri;
    }

    function lotteryMint(address winner) external onlyLottery {
        require(nextMintId <= maxMintId, 'All tokens minted');

        _safeMint(winner, nextMintId);

        emit LotteryMinted(winner, nextMintId);

        nextMintId++;
    }

    function bridgeNFT(bytes32 channelId, uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, 'You are not the NFT owner.');

        safeTransferFrom(msg.sender, address(this), tokenId); // lock token
        getOwnerFromLockedTokenId[tokenId] = msg.sender;

        bytes memory payload = abi.encode(msg.sender, nextMintId);
        _sendPacket(channelId, 10 hours, payload);

        emit TokenBridged(channelId, msg.sender, tokenId);
    }

    function setBaseUri(string memory uri) external onlyOwner {
        baseUri = uri;
    }

    function setBaseExtension(string memory extension) external onlyOwner {
        baseExtension = extension;
    }

    function setLottery(address _lottery) external onlyOwner {
        lottery = _lottery;
    }

    function withdraw() external onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}('');
        require(success);
    }

    /**
     * @dev Packet lifecycle callback that implements packet receipt logic and returns and acknowledgement packet.
     *      MUST be overriden by the inheriting contract.
     * @param packet the IBC packet encoded by the source and relayed by the relayer.
     */
    function onRecvPacket(IbcPacket memory packet) external override onlyIbcDispatcher returns (AckPacket memory ackPacket) {
        recvedPackets.push(packet);
        // decoding the caller address from the packet data
        (address sender, uint256 tokenId) = abi.decode(packet.data, (address, uint256));

        if (getOwnerFromLockedTokenId[tokenId] != sender) {
            _safeMint(sender, tokenId);
        } else {
            safeTransferFrom(address(this), sender, tokenId);
            getOwnerFromLockedTokenId[tokenId] = address(0);
        }

        emit TokenReceived(sender, tokenId);

        return AckPacket(true, abi.encode(packet.data));
    }

    // public functions
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), 'Token does not exist');
        return string(abi.encodePacked(baseUri, tokenId.toString(), baseExtension));
    }

    // internal functions
    function _baseURI() internal view virtual override returns (string memory) {
        return baseUri;
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
