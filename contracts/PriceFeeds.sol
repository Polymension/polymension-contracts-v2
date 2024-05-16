// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

contract PriceFeeds {
    function getPrice(address addr) public view returns (int, uint8) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(addr);

        (, int answer, , , ) = dataFeed.latestRoundData();

        uint8 decimals = dataFeed.decimals();

        return (answer, decimals);
    }
}
