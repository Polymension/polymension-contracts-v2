// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract VaultToken is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public token;

    address public bridgeAddress;

    uint256 public totalStaked;

    mapping(address => uint256) public stakedBalances;

    error OnlyBridge();
    error InsufficientBalance();
    error InsufficientStakedBalance();

    modifier onlyBridge() {
        if (msg.sender != bridgeAddress) {
            revert OnlyBridge();
        }
        _;
    }

    modifier checkBalance(uint256 _amount) {
        if (token.balanceOf(address(this)) < _amount) {
            revert InsufficientBalance();
        }
        _;
    }

    constructor(address _tokenAddress, address _bridgeAddress) {
        token = IERC20(_tokenAddress);
        bridgeAddress = _bridgeAddress;
    }

    function stake(uint256 _amount) external {
        token.safeTransferFrom(msg.sender, address(this), _amount);
        stakedBalances[msg.sender] += _amount;
        totalStaked += _amount;
    }

    function unstake(uint256 _amount) external checkBalance(_amount) {
        if (stakedBalances[msg.sender] < _amount) {
            revert InsufficientStakedBalance();
        }

        stakedBalances[msg.sender] -= _amount;
        totalStaked -= _amount;
        token.safeTransfer(msg.sender, _amount);
    }

    function transferToken(address _to, uint256 _amount) external onlyBridge checkBalance(_amount) {
        token.safeTransfer(_to, _amount);
    }
}
