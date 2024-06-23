//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IEntropyConsumer} from '@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol';
import {IEntropy} from '@pythnetwork/entropy-sdk-solidity/IEntropy.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol';

library LotteryErrors {
    error IncorrectSender();

    error InsufficientFee();
}

interface ILotteryPolyERC721 is IERC721Enumerable {
    function lotteryMint(address winner) external;
}

/// Example contract using Pyth Entropy to allow a user to flip a secure fair coin.
/// Users interact with the contract by requesting a random number from the entropy provider.
/// The entropy provider will then fulfill the request by revealing their random number.
/// Once the provider has fulfilled their request the entropy contract will call back
/// the requesting contract with the generated random number.
///
/// The CoinFlip contract implements the IEntropyConsumer interface imported from the Solidity SDK.
/// The interface helps in integrating with Entropy correctly.
contract PythLottery is IEntropyConsumer, Ownable {
    // state variables
    ILotteryPolyERC721 public lotteryNFT;
    uint256 public eligibleAddressCount = 100;
    address[] public eligibleAdresses;
    bool public mintEnabled = true;

    // events
    // Event emitted when a coin flip is requested. The sequence number can be used to identify a request
    event RandomNumberRequest(uint64 sequenceNumber);

    // Event emitted when the result of the coin flip is known.
    event WinnerResult(uint64 sequenceNumber, uint256 randomNumber, address winner);

    mapping(uint64 sequenceNumber => address winner) public getWinnerFromSequenceNumber;

    // Contracts using Pyth Entropy should import the solidity SDK and then store both the Entropy contract
    // and a specific entropy provider to use for requests. Each provider commits to a sequence of random numbers.
    // Providers are then responsible for fulfilling a request on chain by revealing their random number.
    // Users should choose a reliable provider who they trust to uphold these commitments.
    // (For the moment, the only available provider is 0x6CC14824Ea2918f5De5C2f75A9Da968ad4BD6344)
    IEntropy private entropy;
    address private entropyProvider;

    constructor(address _entropy, address _entropyProvider) Ownable() {
        entropy = IEntropy(_entropy);
        entropyProvider = _entropyProvider;
    }

    // Request to flip a coin. The caller should generate and pass in a random number when calling this method.
    function requestRandomNumber(bytes32 userRandomNumber) internal {
        // The entropy protocol requires the caller to pay a fee (in native gas tokens) per requested random number.
        // This fee can either be paid by the contract itself or passed on to the end user.
        // This implementation of the requestFlip method passes on the fee to the end user.
        uint256 fee = entropy.getFee(entropyProvider);
        if (msg.value < fee) {
            revert LotteryErrors.InsufficientFee();
        }

        // Request the random number from the Entropy protocol. The call returns a sequence number that uniquely
        // identifies the generated random number. Callers can use this sequence number to match which request
        // is being revealed in the next stage of the protocol.
        uint64 sequenceNumber = entropy.requestWithCallback{value: fee}(entropyProvider, userRandomNumber);

        emit RandomNumberRequest(sequenceNumber);
    }

    // Get the fee to flip a coin. See the comment above about fees.
    function getFee() external view returns (uint256 fee) {
        fee = entropy.getFee(entropyProvider);
    }

    function runLottery(address[] memory addresses, bytes32 userRandomNumber) external payable onlyOwner {
        eligibleAdresses = addresses;
        requestRandomNumber(userRandomNumber);
    }

    function setEligibleAddressCount(uint256 count) external onlyOwner {
        eligibleAddressCount = count;
    }

    function setLotteryNFT(address newLotteryNFT) external onlyOwner {
        lotteryNFT = ILotteryPolyERC721(newLotteryNFT);
    }

    function setMintEnabled(bool enabled) external onlyOwner {
        mintEnabled = enabled;
    }

    // This method is required by the IEntropyConsumer interface.
    // It is called by the entropy contract when a random number is generated.
    function entropyCallback(
        uint64 sequenceNumber,
        // If your app uses multiple providers, you can use this argument
        // to distinguish which one is calling the app back. This app only
        // uses one provider so this argument is not used.
        address,
        bytes32 randomNumberBytes32
    ) internal override {
        uint256 randomNumber = uint256(randomNumberBytes32) % eligibleAddressCount;
        address winner = eligibleAdresses[randomNumber];
        getWinnerFromSequenceNumber[sequenceNumber] = winner;
        if (mintEnabled) lotteryNFT.lotteryMint(winner);
        emit WinnerResult(sequenceNumber, randomNumber, winner);
    }

    // This method is required by the IEntropyConsumer interface.
    // It returns the address of the entropy contract which will call the callback.
    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    receive() external payable {}
}
