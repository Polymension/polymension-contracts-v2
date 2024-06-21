// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDex {
    function swap(address token, address to) external payable;
}
