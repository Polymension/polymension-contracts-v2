// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IPriceFeeds {
    function getPrice(uint256 chainID) external view returns (uint256);
}
