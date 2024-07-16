// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IPriceFeeds {
    function getNativePrice(uint256 chainID) external view returns (uint256);

    function getTokenPrice(address token) external view returns (uint256);
}
