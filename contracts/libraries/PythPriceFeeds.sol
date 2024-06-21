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

    mapping(uint256 => bytes32) public priceFeeds;

    error ZeroAddress();

    constructor(address _oracleAddr) Ownable() {
        oracle = IPythPriceFeeds(_oracleAddr);
    }

    function setOracle(address _oracleAddr) external onlyOwner {
        if (_oracleAddr == address(0)) revert ZeroAddress();
        oracle = IPythPriceFeeds(_oracleAddr);
    }

    function setPriceFeed(uint256 chainId, bytes32 feed) external onlyOwner {
        priceFeeds[chainId] = feed;
    }

    function getPrice(uint256 chainId) external view returns (uint256) {
        IPythPriceFeeds.Price memory data = oracle.getPriceUnsafe(priceFeeds[chainId]);

        uint256 priceInWei = uint256(int256(data.price)) * 10 ** uint256(int256(18 + data.expo));

        return priceInWei;
    }
}
