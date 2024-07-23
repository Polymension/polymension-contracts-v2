// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IVaultNative {
    function transferNative(address _to, uint256 _amount) external;
}

interface IVaultToken {
    function transferToken(address _to, uint256 _amount) external;
}
