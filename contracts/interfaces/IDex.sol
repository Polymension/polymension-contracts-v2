// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IDex {
    function swapNativeToToken(address _token, address _to) external payable returns (uint[] memory);

    function swapTokenToNative(address _token, uint256 _amount, address _to) external returns (uint[] memory);
}
