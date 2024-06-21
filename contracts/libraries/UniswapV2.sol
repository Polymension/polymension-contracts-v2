// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IUniswapV2Router02} from '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract UniswapV2 is Ownable {
    IUniswapV2Router02 public uniswapRouter;

    error ZeroAddress();

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
     * @dev Swap ETH for tokens
     * @param token The token address to swap ETH for
     * @param to The address to send the swapped tokens to
     */
    function swap(address token, address to) external payable {
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = token;

        uniswapRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(
            0, // Minimum amount of tokens to accept, set to 0 for simplicity
            path,
            to,
            block.timestamp
        );
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
