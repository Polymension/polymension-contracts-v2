// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^4.9.6
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract CustomERC721 is ERC721Enumerable, Ownable {
    using Strings for uint256;

    uint256 private _nextTokenId;

    address private bridgeContract;

    mapping(uint256 => bool) private isBurn;

    modifier onlyBridgeContract() {
        require(_msgSender() == bridgeContract, 'Only bridge contract');
        _;
    }

    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    function _baseURI() internal pure override returns (string memory) {
        return 'https://storage.polymension.com/bridge-nft/';
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), '.json')) : '';
    }

    function setBridgeContract(address _bridgeContract) public onlyOwner {
        require(bridgeContract == address(0), 'Bridge contract already set');
        bridgeContract = _bridgeContract;
    }

    function setStartTokenId(uint256 _startTokenId) public onlyOwner {
        _nextTokenId = _startTokenId;
    }

    function safeMint(address to) public {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    function bridgeMint(address to, uint256 tokenId) internal onlyBridgeContract {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) public virtual onlyBridgeContract {
        //solhint-disable-next-line max-line-length
        require(isBurn[tokenId] == false, 'This NFT has already been burnt');
        require(_isApprovedOrOwner(_msgSender(), tokenId), 'ERC721: caller is not token owner or approved');
        isBurn[tokenId] = true;
        _burn(tokenId);
    }

    function mintBack(address to, uint256 tokenId) public onlyBridgeContract {
        require(isBurn[tokenId] == true, 'This NFT has not been burnt yet');
        isBurn[tokenId] = false;
        _mint(to, tokenId);
    }
}
