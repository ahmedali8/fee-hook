// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {JavascriptFfi} from "./JavascriptFfi.sol";

contract GetIOAmounts is JavascriptFfi {
    using CurrencyLibrary for Currency;

    struct GetInputAmountJSParams {
        PoolKey key;
        int24 tick;
        uint256 liquidity;
        uint256 sqrtRatioX96;
        address outputCurrencyAddress;
        uint256 outputRawAmount;
    }

    function getInputAmountJS(GetInputAmountJSParams memory params) public returns (uint256) {
        string memory jsParameters = string(
            abi.encodePacked(
                vm.toString(block.chainid),
                ",",
                vm.toString(Currency.unwrap(params.key.currency1)),
                ",",
                vm.toString(uint256(18)), // currency1Decimals
                ",",
                vm.toString(params.tick),
                ",",
                vm.toString(params.liquidity),
                ",",
                vm.toString(params.sqrtRatioX96),
                ",",
                vm.toString(params.key.fee),
                ",",
                vm.toString(params.key.tickSpacing),
                ",",
                vm.toString(params.outputCurrencyAddress),
                ",",
                vm.toString(params.outputRawAmount)
            )
        );

        string memory scriptName = "forge-test-getInputAmount";
        bytes memory jsResult = runScript(scriptName, jsParameters);

        return abi.decode(jsResult, (uint256));
    }

    struct GetOutputAmountJSParams {
        PoolKey key;
        int24 tick;
        uint256 liquidity;
        uint256 sqrtRatioX96;
        address inputCurrencyAddress;
        uint256 inputRawAmount;
    }

    function getOutputAmountJS(GetOutputAmountJSParams memory params) public returns (uint256) {
        string memory jsParameters = string(
            abi.encodePacked(
                vm.toString(block.chainid),
                ",",
                vm.toString(Currency.unwrap(params.key.currency1)),
                ",",
                vm.toString(uint256(18)), // currency1Decimals
                ",",
                vm.toString(params.tick),
                ",",
                vm.toString(params.liquidity),
                ",",
                vm.toString(params.sqrtRatioX96),
                ",",
                vm.toString(params.key.fee),
                ",",
                vm.toString(params.key.tickSpacing),
                ",",
                vm.toString(params.inputCurrencyAddress),
                ",",
                vm.toString(params.inputRawAmount)
            )
        );

        string memory scriptName = "forge-test-getOutputAmount";
        bytes memory jsResult = runScript(scriptName, jsParameters);

        return abi.decode(jsResult, (uint256));
    }
}
