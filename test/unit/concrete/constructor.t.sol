// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import {Unit_Test} from "../Unit.t.sol";

contract Constructor_Test is Unit_Test {
    function setUp() public virtual override {
        Unit_Test.setUp();
    }

    function test_defaultConstructorValues() public view {
        assertEq(hook.owner(), users.owner);

        assertEq(hook.maxBuyAmount(), DEFAULT_MAX_BUY_AMOUNT);
        assertEq(hook.maxSellAmount(), DEFAULT_MAX_SELL_AMOUNT);
        assertEq(hook.maxWalletAmount(), DEFAULT_MAX_WALLET_AMOUNT);

        assertEq(hook.buyFeeBips(), DEFAULT_BUY_FEE_BIPS);
        assertEq(hook.sellFeeBips(), DEFAULT_SELL_FEE_BIPS);

        assertEq(hook.cooldownBlocks(), DEFAULT_COOLDOWN_BLOCKS);
    }
}
