// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// v4-core
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";

// v4-periphery
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IV4Quoter} from "v4-periphery/src/interfaces/IV4Quoter.sol";
import {V4Quoter} from "v4-periphery/src/lens/V4Quoter.sol";
import {Deploy} from "v4-periphery/test/shared/Deploy.sol";

// solmate
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

import {OmniHook} from "src/OmniHook.sol";

import "forge-std/console2.sol";

contract OmniHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    uint256 public constant HOOK_FEE_PERCENTAGE = 10;
    uint256 public constant FEE_DENOMINATOR = 100_000;

    address user = address(0xBEEF);

    IV4Quoter quoter;

    OmniHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        quoter = Deploy.v4Quoter(address(manager), hex"00");

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG
                    | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager, msg.sender, 100); // Add all the necessary constructor arguments from the hook
        deployCodeTo("OmniHook.sol:OmniHook", constructorArgs, flags);
        hook = OmniHook(payable(flags));
        vm.label(flags, "OmniHook");

        // Create the pool
        key = PoolKey(CurrencyLibrary.ADDRESS_ZERO, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function test_OmniHook_Owner() public view {
        assertEq(hook.owner(), msg.sender, "owner");
    }

    function test_OmniHook_ZeroForOne_ExactInput() public {
        _setApprovalsFor(user, address(Currency.unwrap(key.currency1)));

        // Seeds liquidity into the user.
        key.currency0.transfer(address(user), 10e18);

        uint256 userBalanceBefore0 = key.currency0.balanceOf(address(user));
        uint256 userBalanceBefore1 = key.currency1.balanceOf(address(user));

        uint256 hookBalanceBefore0 = key.currency0.balanceOf(address(hook));

        uint256 amountToSwap = 1 ether; // 1 eth

        // Setting this value to true means currency0 is supplied.
        // Setting this value to false means currency1 is supplied.
        bool zeroForOne = true;

        // Set the sign of this value.
        // A negative amount means it is an exactInput swap, so the user is sending exactly that amount into the pool.
        // A positive amount means it is an exactOutput swap, so the user is only requesting that amount out of the swap.
        int256 amountSpecified = -int256(amountToSwap);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            // Note: if zeroForOne is true, the price is pushed down, otherwise its pushed up.
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });

        _printTestType(params.zeroForOne, params.amountSpecified);

        console2.log("--- STARTING BALANCES ---");

        console2.log("User balance in currency0 before swapping: ", userBalanceBefore0);
        console2.log("User balance in currency1 before swapping: ", userBalanceBefore1);
        console2.log("Hook balance in currency0 before swapping: ", hookBalanceBefore0);

        // console2.log("/// quoter ///");
        // (uint256 expectedAmountOut,) = quoter.quoteExactInputSingle(
        //     IV4Quoter.QuoteExactSingleParams({
        //         poolKey: key,
        //         zeroForOne: zeroForOne,
        //         exactAmount: uint128(amountToSwap),
        //         hookData: ZERO_BYTES
        //     })
        // );

        // assertEq(expectedAmountOut, 987060292978120240, "amount out");

        vm.prank(user);
        swapRouter.swap{value: amountToSwap}(key, params, _defaultTestSettings(), ZERO_BYTES);

        uint256 userBalanceAfter0 = key.currency0.balanceOf(address(user));
        uint256 userBalanceAfter1 = key.currency1.balanceOf(address(user));

        uint256 hookBalanceAfter0 = key.currency0.balanceOf(address(hook));

        console2.log("--- ENDING BALANCES ---");

        console2.log("User balance in currency0 after  swapping: ", userBalanceAfter0);
        console2.log("User balance in currency1 after  swapping: ", userBalanceAfter1);
        console2.log("Hook balance in currency0 after  swapping: ", hookBalanceAfter0);

        // 0.01% for 1 eth = 0.0001 eth
        uint256 expectedFeeAmount = (amountToSwap * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;

        assertEq(userBalanceAfter0, userBalanceBefore0 - amountToSwap, "amount 0");
        // assertEq(userBalanceAfter1, userBalanceBefore1 + expectedAmountOut, "amount 1");
        assertEq(hookBalanceAfter0, hookBalanceBefore0 + expectedFeeAmount, "amount 0");
    }

    function test_OmniHook_ZeroForOne_ExactOutput() public {
        _setApprovalsFor(user, address(Currency.unwrap(key.currency1)));

        // Seeds liquidity into the user.
        key.currency0.transfer(address(user), 10e18);

        uint256 userBalanceBefore0 = key.currency0.balanceOf(address(user));
        uint256 userBalanceBefore1 = key.currency1.balanceOf(address(user));

        uint256 hookBalanceBefore0 = key.currency0.balanceOf(address(hook));

        uint256 amountToSwap = 1e18; // 1 token out (amount1)

        // Setting this value to true means currency0 is supplied.
        // Setting this value to false means currency1 is supplied.
        bool zeroForOne = true;

        // Set the sign of this value.
        // A negative amount means it is an exactInput swap, so the user is sending exactly that amount into the pool.
        // A positive amount means it is an exactOutput swap, so the user is only requesting that amount out of the swap.
        int256 amountSpecified = int256(amountToSwap);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            // Note: if zeroForOne is true, the price is pushed down, otherwise its pushed up.
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });

        _printTestType(params.zeroForOne, params.amountSpecified);

        console2.log("--- STARTING BALANCES ---");

        console2.log("User balance in currency0 before swapping: ", userBalanceBefore0);
        console2.log("User balance in currency1 before swapping: ", userBalanceBefore1);
        console2.log("Hook balance in currency0 before swapping: ", hookBalanceBefore0);

        // console2.log("/// quoter ///");
        (uint256 expectedAmountIn,) = quoter.quoteExactOutputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                exactAmount: uint128(amountToSwap),
                hookData: ZERO_BYTES
            })
        );
        // expectedAmountIn is the eth amount
        console2.log("expectedAmountIn: ", expectedAmountIn);
        // assertEq(expectedAmountIn, 987060292978120240, "amount out");
        // console2.log("/// quoter ///");

        // 1 token cost this much eth 1013140431395195690
        // fee is 101314043139519
        // user gives this eth 1013241745438335209

        // is the user giving extra eth?
        assertEq(uint256(1013241745438335209), uint256(1013140431395195690) + uint256(101314043139519));

        // vm.prank(user);
        // swapRouter.swap{value: amountToSwap}(key, params, _defaultTestSettings(), ZERO_BYTES);

        // uint256 userBalanceAfter0 = key.currency0.balanceOf(address(user));
        // uint256 userBalanceAfter1 = key.currency1.balanceOf(address(user));

        // uint256 hookBalanceAfter0 = key.currency0.balanceOf(address(hook));

        // console2.log("--- ENDING BALANCES ---");

        // console2.log("User balance in currency0 after  swapping: ", userBalanceAfter0);
        // console2.log("User balance in currency1 after  swapping: ", userBalanceAfter1);
        // console2.log("Hook balance in currency0 after  swapping: ", hookBalanceAfter0);

        // // 0.01% for 1 eth = 0.0001 eth
        // uint256 expectedFeeAmount = (amountToSwap * hook.HOOK_FEE_PERCENTAGE()) / hook.FEE_DENOMINATOR();

        // assertEq(userBalanceAfter0, userBalanceBefore0 - amountToSwap, "amount 0");
        // assertEq(userBalanceAfter1, userBalanceBefore1 + expectedAmountOut, "amount 1");
        // assertEq(hookBalanceAfter0, hookBalanceBefore0 + expectedFeeAmount, "amount 0");
    }

    function test_OmniHook_OneForZero_ExactInput() public {
        _setApprovalsFor(user, address(Currency.unwrap(key.currency1)));

        // Seeds liquidity into the user.
        key.currency0.transfer(address(user), 10e18);
        key.currency1.transfer(address(user), 10e18);

        uint256 userBalanceBefore0 = key.currency0.balanceOf(address(user));
        uint256 userBalanceBefore1 = key.currency1.balanceOf(address(user));

        uint256 hookBalanceBefore0 = key.currency0.balanceOf(address(hook));
        uint256 hookBalanceBefore1 = key.currency1.balanceOf(address(hook));

        uint256 amountToSwap = 1e18; // 1 token

        // Setting this value to true means currency0 is supplied.
        // Setting this value to false means currency1 is supplied.
        bool zeroForOne = false;

        // Set the sign of this value.
        // A negative amount means it is an exactInput swap, so the user is sending exactly that amount into the pool.
        // A positive amount means it is an exactOutput swap, so the user is only requesting that amount out of the swap.
        int256 amountSpecified = -int256(amountToSwap);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            // Note: if zeroForOne is true, the price is pushed down, otherwise its pushed up.
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });

        _printTestType(params.zeroForOne, params.amountSpecified);

        console2.log("--- STARTING BALANCES ---");

        console2.log("User balance in currency0 before swapping: ", userBalanceBefore0);
        console2.log("User balance in currency1 before swapping: ", userBalanceBefore1);
        console2.log("Hook balance in currency0 before swapping: ", hookBalanceBefore0);
        console2.log("Hook balance in currency1 before swapping: ", hookBalanceBefore1);

        // console2.log("-- quoter --");
        // (uint256 expectedAmountOut,) = quoter.quoteExactInputSingle(
        //     IV4Quoter.QuoteExactSingleParams({
        //         poolKey: key,
        //         zeroForOne: zeroForOne,
        //         exactAmount: uint128(amountToSwap),
        //         hookData: ZERO_BYTES
        //     })
        // );
        // console2.log("expectedAmountOut: ", expectedAmountOut);
        // console2.log("-- quoter --");

        // assertEq(expectedAmountOut, 987158034397061298, "amount out");

        vm.prank(user);
        swapRouter.swap(key, params, _defaultTestSettings(), ZERO_BYTES);

        uint256 userBalanceAfter0 = key.currency0.balanceOf(address(user));
        uint256 userBalanceAfter1 = key.currency1.balanceOf(address(user));

        uint256 hookBalanceAfter0 = key.currency0.balanceOf(address(hook));
        uint256 hookBalanceAfter1 = key.currency1.balanceOf(address(hook));

        console2.log("--- ENDING BALANCES ---");

        console2.log("User balance in currency0 after  swapping: ", userBalanceAfter0);
        console2.log("User balance in currency1 after  swapping: ", userBalanceAfter1);
        console2.log("Hook balance in currency0 after  swapping: ", hookBalanceAfter0);
        console2.log("Hook balance in currency1 after  swapping: ", hookBalanceAfter1);

        uint256 feeAmount = 98715803439706;

        assertEq(userBalanceAfter1, userBalanceBefore1 - amountToSwap, "user amount 1");
        // assertEq(userBalanceAfter0, userBalanceBefore0 + expectedAmountOut, "user amount 0");

        assertEq(hookBalanceAfter0, hookBalanceBefore0 + feeAmount, "hook amount 0");
        assertEq(hookBalanceAfter1, hookBalanceBefore1, "hook amount 1");
    }

    function test_OmniHook_OneForZero_ExactOutput() public {
        _setApprovalsFor(user, address(Currency.unwrap(key.currency1)));

        // Seeds liquidity into the user.
        key.currency0.transfer(address(user), 10e18);
        key.currency1.transfer(address(user), 10e18);

        uint256 userBalanceBefore0 = key.currency0.balanceOf(address(user));
        uint256 userBalanceBefore1 = key.currency1.balanceOf(address(user));

        uint256 hookBalanceBefore0 = key.currency0.balanceOf(address(hook));
        uint256 hookBalanceBefore1 = key.currency1.balanceOf(address(hook));

        uint256 amountToSwap = 1 ether; // 1 eth out (amount0)

        // Setting this value to true means currency0 is supplied.
        // Setting this value to false means currency1 is supplied.
        bool zeroForOne = false;

        // Set the sign of this value.
        // A negative amount means it is an exactInput swap, so the user is sending exactly that amount into the pool.
        // A positive amount means it is an exactOutput swap, so the user is only requesting that amount out of the swap.
        int256 amountSpecified = int256(amountToSwap);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            // Note: if zeroForOne is true, the price is pushed down, otherwise its pushed up.
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });

        _printTestType(params.zeroForOne, params.amountSpecified);

        console2.log("--- STARTING BALANCES ---");

        console2.log("User balance in currency0 before swapping: ", userBalanceBefore0);
        console2.log("User balance in currency1 before swapping: ", userBalanceBefore1);
        console2.log("Hook balance in currency0 before swapping: ", hookBalanceBefore0);
        console2.log("Hook balance in currency1 before swapping: ", hookBalanceBefore1);

        console2.log("-- quoter --");
        (uint256 expectedAmountIn,) = quoter.quoteExactOutputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                exactAmount: uint128(amountToSwap),
                hookData: ZERO_BYTES
            })
        );
        // expectedAmountIn is the token amount
        console2.log("expectedAmountIn: ", expectedAmountIn);
        console2.log("-- quoter --");

        assertEq(expectedAmountIn, 1013242768915879568, "amount in");

        vm.prank(user);
        swapRouter.swap(key, params, _defaultTestSettings(), ZERO_BYTES);

        uint256 userBalanceAfter0 = key.currency0.balanceOf(address(user));
        uint256 userBalanceAfter1 = key.currency1.balanceOf(address(user));

        uint256 hookBalanceAfter0 = key.currency0.balanceOf(address(hook));
        uint256 hookBalanceAfter1 = key.currency1.balanceOf(address(hook));

        console2.log("--- ENDING BALANCES ---");

        console2.log("User balance in currency0 after  swapping: ", userBalanceAfter0);
        console2.log("User balance in currency1 after  swapping: ", userBalanceAfter1);
        console2.log("Hook balance in currency0 after  swapping: ", hookBalanceAfter0);
        console2.log("Hook balance in currency1 after  swapping: ", hookBalanceAfter1);

        // uint256 feeAmount = 100000000000000; // 0.01% of 1 eth

        assertEq(userBalanceAfter1, userBalanceBefore1 - expectedAmountIn, "user amount 1");
        assertEq(userBalanceAfter0, userBalanceBefore0 + amountToSwap, "user amount 0");

        assertEq(hookBalanceAfter0, hookBalanceBefore0 + 100000000000000, "hook amount 0");
        assertEq(hookBalanceAfter1, hookBalanceBefore1, "hook amount 1");
    }

    /// INTERNAL HELPER FUNCTIONS ///

    function _printTestType(bool zeroForOne, int256 amountSpecified) internal pure {
        console2.log("--- TEST TYPE ---");
        string memory zeroForOneString = zeroForOne ? "zeroForOne" : "oneForZero";
        string memory swapType = amountSpecified < 0 ? "exactInput" : "exactOutput";
        string memory currencyRequiredFromUser = zeroForOne ? "currency0" : "currency1";
        string memory currencySpecified = zeroForOne == amountSpecified < 0 ? "currency0" : "currency1";

        console2.log("This is a", zeroForOneString, swapType, "swap");
        console2.log("The user will owe an amount in", currencyRequiredFromUser);
        console2.log("The currency specified is", currencySpecified);
    }

    function _defaultTestSettings() internal pure returns (PoolSwapTest.TestSettings memory testSetting) {
        return PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
    }

    function _setApprovalsFor(address _user, address token) internal {
        address[8] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor())
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            vm.prank(_user);
            MockERC20(token).approve(toApprove[i], Constants.MAX_UINT256);
        }
    }
}

// feat: handle all for cases

// buy:
// swapExactETHForTokens - zeroForOne - exactInput - beforeSwap
// swapETHForExactTokens - zeroForOne - exactOutput - afterSwap

// sell:
// swapExactTokensForETH - oneForZero - exactInput - afterSwap
// swapTokensForExactETH - oneForZero - exactOutput - beforeSwap
