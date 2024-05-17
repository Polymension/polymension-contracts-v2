// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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

contract PriceFeeds is Ownable {
    IPythPriceFeeds public oracle;

    mapping(uint256 => bytes32) public priceFeeds;

    constructor(address _oracle) Ownable() {
        oracle = IPythPriceFeeds(_oracle);
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = IPythPriceFeeds(_oracle);
    }

    function setPriceFeed(uint256 chainID, bytes32 feed) external onlyOwner {
        priceFeeds[chainID] = feed;
    }

    function getPrice(uint256 chainID) external view returns (int, int32) {
        IPythPriceFeeds.Price memory price = oracle.getPriceUnsafe(priceFeeds[chainID]);

        return (price.price, price.expo);
    }
}
