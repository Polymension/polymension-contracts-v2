// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IUniswapV2Router02} from '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract UniswapV2 is Ownable {
    IUniswapV2Router02 public uniswapRouter;

    error ZeroAddress();
    error FailedSwap();

    constructor(address _rooterAddr) Ownable() {
        uniswapRouter = IUniswapV2Router02(_rooterAddr);
    }

    /**
     * @dev Set the router address
     * @param _rooterAddr The address of the router
     */
    function setRouterAddress(address _rooterAddr) public onlyOwner {
        if (_rooterAddr == address(0)) revert ZeroAddress();
        uniswapRouter = IUniswapV2Router02(_rooterAddr);
    }

    /**
     * @dev Swap tokens for ETH
     * @param _token The address of the token
     * @param _to The address to receive ETH
     */
    function swapEthToToken(address _token, address _to) external payable returns (uint[] memory) {
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = _token;

        uint[] memory amounts = uniswapRouter.swapExactETHForTokens{value: msg.value}(
            0, // Minimum amount of tokens to accept, set to 0 for simplicity
            path,
            _to,
            block.timestamp
        );

        return amounts;
    }

    /**
     * @dev Swap tokens for ETH
     * @param _token The address of the token
     * @param _amount The amount of token to swap
     * @param _to The address to receive ETH
     */
    function swapTokenToEth(address _token, uint256 _amount, address _to) external returns (uint256[] memory) {
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        IERC20(_token).approve(address(uniswapRouter), _amount);

        address[] memory path = new address[](2);
        path[0] = _token;
        path[1] = uniswapRouter.WETH();

        uint[] memory amounts = uniswapRouter.swapExactTokensForETH(
            _amount,
            0, // Minimum amount of ETH to accept, set to 0 for simplicity
            path,
            _to,
            block.timestamp
        );

        uint256 remaining = IERC20(_token).balanceOf(address(this));
        if (remaining > 0) {
            IERC20(_token).transfer(msg.sender, remaining);
        }

        return amounts;
    }

    /**
     * @dev To receive ETH from uniswapRouter when swapping
     */
    receive() external payable {}

    /**
     * @dev Fallback function to receive ETH from uniswapRouter when swapping
     */
    fallback() external payable {}
}
