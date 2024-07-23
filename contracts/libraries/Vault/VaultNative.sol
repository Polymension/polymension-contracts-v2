// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

contract VaultNative is Ownable {
    address public bridgeAddress;

    uint256 public totalStaked;

    mapping(address => uint256) public stakedBalances;

    error OnlyBridge();
    error InsufficientBalance();
    error InsufficientStakedBalance();
    error FailedTransfer();

    constructor(address _bridgeAddress) {
        bridgeAddress = _bridgeAddress;
    }

    modifier onlyBridge() {
        if (msg.sender != bridgeAddress) {
            revert OnlyBridge();
        }
        _;
    }

    modifier checkBalance(uint256 _amount) {
        if (address(this).balance < _amount) {
            revert InsufficientBalance();
        }
        _;
    }

    function stake() external payable {
        uint256 amount = msg.value;
        stakedBalances[msg.sender] += amount;
        totalStaked += amount;
    }

    function unstake(uint256 _amount) external {
        if (stakedBalances[msg.sender] < _amount) {
            revert InsufficientStakedBalance();
        }

        stakedBalances[msg.sender] -= _amount;
        totalStaked -= _amount;

        (bool success, ) = msg.sender.call{value: _amount}('');
        if (!success) {
            revert FailedTransfer();
        }
    }

    function transferNative(address _to, uint256 _amount) external onlyBridge checkBalance(_amount) {
        (bool success, ) = _to.call{value: _amount}('');
        if (!success) {
            revert FailedTransfer();
        }
    }
}
