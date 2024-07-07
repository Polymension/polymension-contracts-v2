// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDex {
    function swapEthToToken(address _token, address _to) external payable returns (uint[] memory);

    function swapTokenToEth(address _token, uint256 _amount, address _to) external returns (uint[] memory);
}
