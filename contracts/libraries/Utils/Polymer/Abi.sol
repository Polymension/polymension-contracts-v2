//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IbcPacket, AckPacket} from '@open-ibc/vibc-core-smart-contracts/contracts/libs/Ibc.sol';
import {BridgeType} from './Enum.sol';

library AbiUtils {
    function _decodePayload(bytes memory _data) internal pure returns (BridgeType, bytes memory) {
        return abi.decode(_data, (BridgeType, bytes));
    }

    function _encodePayload(BridgeType _bridgeType, bytes memory _data) internal pure returns (bytes memory) {
        return abi.encode(_bridgeType, _data);
    }

    // <NATIVE_TO_NATIVE>
    function _decodeNativeToNativeInputs(bytes memory _inputs) internal pure returns (bytes32, address, uint256) {
        return abi.decode(_inputs, (bytes32, address, uint256));
    }

    function _encodeNativeToNativeData(
        address _sender,
        address _to,
        uint256 _amountIn,
        uint256 _sourceAmountOut,
        uint256 _minAmountOut
    ) internal pure returns (bytes memory) {
        return abi.encode(_sender, _to, _amountIn, _sourceAmountOut, _minAmountOut);
    }

    function _decodeNativeToNativeData(bytes memory _data) internal pure returns (address, address, uint256, uint256, uint256) {
        return abi.decode(_data, (address, address, uint256, uint256, uint256));
    }

    // </NATIVE_TO_NATIVE>

    // <NATIVE_TO_TOKEN>
    function _decodeNativeToTokenInputs(bytes memory _inputs) internal pure returns (bytes32, address, address, uint256) {
        return abi.decode(_inputs, (bytes32, address, address, uint256));
    }

    function _encodeNativeToTokenData(
        address _sender,
        address _to,
        address _token,
        uint256 _amountIn,
        uint256 _sourceAmountOut,
        uint256 _minAmountOut
    ) internal pure returns (bytes memory) {
        return abi.encode(_sender, _to, _token, _amountIn, _sourceAmountOut, _minAmountOut);
    }

    function _decodeNativeToTokenData(bytes memory _data) internal pure returns (address, address, address, uint256, uint256, uint256) {
        return abi.decode(_data, (address, address, address, uint256, uint256, uint256));
    }

    // </NATIVE_TO_TOKEN>

    // <TOKEN_TO_NATIVE>
    function _decodeTokenToNativeInputs(bytes memory _inputs) internal pure returns (address, address, uint256, uint256) {
        return abi.decode(_inputs, (address, address, uint256, uint256));
    }

    function _encodeTokenToNativeData(
        address _sender,
        address _to,
        address _token,
        uint256 _amountIn,
        uint256 _sourceAmountOut,
        uint256 _minAmountOut
    ) internal pure returns (bytes memory) {
        return abi.encode(_sender, _to, _token, _amountIn, _sourceAmountOut, _minAmountOut);
    }

    function _decodeTokenToNativeData(bytes memory _data) internal pure returns (address, address, address, uint256, uint256, uint256) {
        return abi.decode(_data, (address, address, address, uint256, uint256, uint256));
    }

    // </TOKEN_TO_NATIVE>

    // <TOKEN_TO_TOKEN>
    function _decodeTokenToTokenInputs(bytes memory _inputs) internal pure returns (address, address, address, uint256, uint256) {
        return abi.decode(_inputs, (address, address, address, uint256, uint256));
    }

    function _encodeTokenToTokenData(
        address _sender,
        address _to,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _sourceAmountOut,
        uint256 _minAmountOut
    ) internal pure returns (bytes memory) {
        return abi.encode(_sender, _to, _tokenIn, _tokenOut, _amountIn, _sourceAmountOut, _minAmountOut);
    }

    function _decodeTokenToTokenData(bytes memory _data) internal pure returns (address, address, address, address, uint256, uint256, uint256) {
        return abi.decode(_data, (address, address, address, address, uint256, uint256, uint256));
    }

    // </TOKEN_TO_TOKEN>

    function _decodePacket(IbcPacket memory _packet) internal pure returns (bytes32, bytes32, BridgeType, bytes memory) {
        bytes32 sourceChannelId = _packet.src.channelId;
        bytes32 targetChannelId = _packet.dest.channelId;
        (BridgeType bridgeType, bytes memory data) = abi.decode(_packet.data, (BridgeType, bytes));
        return (sourceChannelId, targetChannelId, bridgeType, data);
    }
}
