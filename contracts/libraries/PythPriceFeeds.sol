// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

interface IPythPriceFeeds {
    struct Price {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint publishTime;
    }

    function getPriceUnsafe(bytes32 id) external view returns (Price memory price);
}

contract PythPriceFeeds is Ownable {
    IPythPriceFeeds public oracle;

    mapping(uint256 => bytes32) public nativePriceFeeds;
    mapping(address => bytes32) public tokenPriceFeeds;

    error ZeroAddress();
    error NotFoundFeed();

    constructor(address _oracleAddr) Ownable() {
        oracle = IPythPriceFeeds(_oracleAddr);
    }

    function setOracle(address _oracleAddr) external onlyOwner {
        if (_oracleAddr == address(0)) revert ZeroAddress();
        oracle = IPythPriceFeeds(_oracleAddr);
    }

    function setNativePriceFeed(uint256 _chainId, bytes32 _feed) external onlyOwner {
        nativePriceFeeds[_chainId] = _feed;
    }

    function setTokenPriceFeed(address _token, bytes32 _feed) external onlyOwner {
        tokenPriceFeeds[_token] = _feed;
    }

    function getNativePrice(uint256 _chainId) external view returns (uint256) {
        if (nativePriceFeeds[_chainId] == bytes32(0)) {
            revert NotFoundFeed();
        }

        IPythPriceFeeds.Price memory data = oracle.getPriceUnsafe(nativePriceFeeds[_chainId]);

        uint256 priceInWei = uint256(int256(data.price)) * 10 ** uint256(int256(18 + data.expo));

        return priceInWei;
    }

    function getTokenPrice(address _token) external view returns (uint256) {
        if (tokenPriceFeeds[_token] == bytes32(0)) {
            revert NotFoundFeed();
        }

        IPythPriceFeeds.Price memory data = oracle.getPriceUnsafe(tokenPriceFeeds[_token]);

        uint256 priceInWei = uint256(int256(data.price)) * 10 ** uint256(int256(18 + data.expo));

        return priceInWei;
    }
}
