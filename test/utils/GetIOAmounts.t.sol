// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {GetIOAmounts} from "./GetIOAmounts.sol";

contract GetAmountsTest is Test {
    using CurrencyLibrary for Currency;

    GetIOAmounts internal getIOAmounts;

    function setUp() public {
        getIOAmounts = new GetIOAmounts();
    }

    function test_GetInputAmount() public {
        uint256 inputAmount = getIOAmounts.getInputAmountJS(
            GetIOAmounts.GetInputAmountJSParams(
                PoolKey(
                    Currency.wrap(0x0000000000000000000000000000000000000000),
                    Currency.wrap(0x7db8A8D1E9483115b9e8028d610e3C365c649f6a),
                    3000,
                    60,
                    IHooks(address(0))
                ),
                161189,
                3162275221685340688940,
                250541255178517414234103244537599,
                0x7db8A8D1E9483115b9e8028d610e3C365c649f6a,
                1000000000000000000000000
            )
        );
        uint256 expectedInputAmount = 111445638425664157;
        assertEq(inputAmount, expectedInputAmount);
    }

    function test_GetOutputAmount() public {
        uint256 outputAmount = getIOAmounts.getOutputAmountJS(
            GetIOAmounts.GetOutputAmountJSParams(
                PoolKey(
                    Currency.wrap(0x0000000000000000000000000000000000000000),
                    Currency.wrap(0x7db8A8D1E9483115b9e8028d610e3C365c649f6a),
                    3000,
                    60,
                    IHooks(address(0))
                ),
                161189,
                3162275221685340688940,
                250541255178517414234103244537599,
                0x0000000000000000000000000000000000000000,
                1000000000000000000
            )
        );
        uint256 expectedOutputAmount = 4992481033526295848721357;
        assertEq(outputAmount, expectedOutputAmount);
    }
}
