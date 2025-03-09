// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {FeeLibrary} from "./libraries/FeeLibrary.sol";

import "forge-std/console2.sol";

contract OmniHook is BaseHook, Ownable {
    using FeeLibrary for uint256;
    using FeeLibrary for uint24;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for *;

    // 100 -> 0.01%
    uint24 public feeBips = 100;

    // the fee is represented in hundredths of a bip, so the max is 100%
    uint256 public constant MAX_FEE = 100_000;

    uint256 public constant HOOK_FEE_PERCENTAGE = 10; // 0.01% fee
    uint256 public constant FEE_DENOMINATOR = 100000;

    constructor(IPoolManager _poolManager, address _initialOwner) BaseHook(_poolManager) Ownable(_initialOwner) {}

    /// @notice Calculates the fee amount without rounding up
    /// @param amount The transaction amount
    /// @return feeAmount The calculated fee amount
    function calculateFee(uint256 amount) public view returns (uint256) {
        return amount.computeFee(feeBips);
    }

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        console2.log("/// Before Swap Start ///");

        // in this case the amount is actually the eth amount
        (Currency _inputCurrency, Currency _outputCurrency, uint256 _amount) = _getInputOutputAndAmount(key, params);

        console2.log("// -- //");
        console2.log("inputCurrency: ", address(Currency.unwrap(_inputCurrency)));
        console2.log("outputCurrency: ", address(Currency.unwrap(_outputCurrency)));
        console2.log("amount: ", _amount);
        console2.log("// -- //");

        bool exactInput = params.amountSpecified < 0;
        console2.log("exactInput: ", exactInput);
        bool specifiedIsZero = params.zeroForOne == exactInput;
        console2.log("specifiedIsZero: ", specifiedIsZero);

        // we wanna take fee in specified token and it must be eth

        // swapExactETHForTokens
        // If exactInput and zeroForOne -> take eth fee
        if (exactInput && params.zeroForOne) {
            // specified token is input token (eth)

            // taking fee on input token (eth) i.e. when user is buying tokens
            Currency _feeCurrency = key.currency0;

            // uint256 _feeAmount = (_amount * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;
            uint256 _feeAmount = calculateFee(_amount);
            console2.log("feeAmount: ", _feeAmount);

            console2.log("swapExactETHForTokens - taking fee");

            poolManager.take({currency: _feeCurrency, to: address(this), amount: _feeAmount});

            BeforeSwapDelta _returnDelta = toBeforeSwapDelta({
                deltaSpecified: int128(int256(_feeAmount)), // Specified delta (fee amount)
                deltaUnspecified: 0 // Unspecified delta (no change)
            });

            console2.log("/// Before Swap End ///");
            return (BaseHook.beforeSwap.selector, _returnDelta, 0);
        }

        // swapTokensForExactETH
        // If exactOutput and oneForZero -> take eth fee
        if (!exactInput && !params.zeroForOne) {
            // specified token is output token (eth)

            Currency _feeCurrency = key.currency0;

            // uint256 _feeAmount = (_amount * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;
            uint256 _feeAmount = calculateFee(_amount);
            console2.log("feeAmount: ", _feeAmount);

            console2.log("swapTokensForExactETH - taking fee");

            poolManager.take({currency: _feeCurrency, to: address(this), amount: _feeAmount});

            BeforeSwapDelta _returnDelta = toBeforeSwapDelta({
                deltaSpecified: int128(int256(_feeAmount)), // Specified delta (fee amount)
                deltaUnspecified: 0 // Unspecified delta (no change)
            });

            console2.log("/// Before Swap End ///");
            return (BaseHook.beforeSwap.selector, _returnDelta, 0);
        }

        // uint256 _swapAmount =
        //     exactInput ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        // uint256 _feeAmount = (_swapAmount * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;

        // Currency _feeCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        // console2.log("feeCurrency: ", address(Currency.unwrap(_feeCurrency)));

        // if (!_feeCurrency.isAddressZero()) {
        //     console2.log("/// Before Swap End ///");
        //     return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        // }

        // console2.log("taking fee");

        // poolManager.take({currency: _feeCurrency, to: address(this), amount: _feeAmount});

        // BeforeSwapDelta _returnDelta = toBeforeSwapDelta({
        //     deltaSpecified: int128(int256(_feeAmount)), // Specified delta (fee amount)
        //     deltaUnspecified: 0 // Unspecified delta (no change)
        // });

        // console2.log("/// Before Swap End ///");
        // return (BaseHook.beforeSwap.selector, _returnDelta, 0);

        // base case -> no fee
        console2.log("beforeSwap - no fee");
        return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        console2.log("/// After Swap Start ///");

        // in this case the amount is actually the token amount
        (Currency _inputCurrency, Currency _outputCurrency, uint256 _amount) = _getInputOutputAndAmount(key, params);

        console2.log("// -- //");
        console2.log("inputCurrency: ", address(Currency.unwrap(_inputCurrency)));
        console2.log("outputCurrency: ", address(Currency.unwrap(_outputCurrency)));
        console2.log("amount: ", _amount);
        console2.log("// -- //");

        bool exactInput = params.amountSpecified < 0;
        console2.log("exactInput: ", exactInput);
        bool specifiedIsZero = params.zeroForOne == exactInput;
        console2.log("specifiedIsZero: ", specifiedIsZero);

        // swapETHForExactTokens
        // If exactOutput and zeroForOne -> take eth fee
        if (!exactInput && params.zeroForOne) {
            // unspecified token is input token (eth)

            Currency _feeCurrency = key.currency0;

            console2.log("amount0: ", delta.amount0());
            console2.log("amount1: ", delta.amount1());

            // uint256 _feeAmount = (uint256(uint128(-delta.amount0())) * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;
            uint256 _feeAmount = calculateFee(uint256(uint128(-delta.amount0())));
            console2.log("feeAmount: ", _feeAmount);

            console2.log("swapETHForExactTokens - taking fee");

            poolManager.take({currency: _feeCurrency, to: address(this), amount: _feeAmount});

            console2.log("/// After Swap End ///");
            return (BaseHook.afterSwap.selector, _feeAmount.toInt128());
        }

        // swapExactTokensForETH
        // If exactInput and oneForZero -> take eth fee
        if (exactInput && !params.zeroForOne) {
            // unspecified token is output token (eth)

            Currency _feeCurrency = key.currency0;

            console2.log("amount0: ", delta.amount0());
            console2.log("amount1: ", delta.amount1());

            // uint256 _feeAmount = (uint256(uint128(-delta.amount0())) * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;
            uint256 _feeAmount = calculateFee(uint256(uint128(delta.amount0())));
            console2.log("feeAmount: ", _feeAmount);

            console2.log("swapExactTokensForETH - taking fee");

            poolManager.take({currency: _feeCurrency, to: address(this), amount: _feeAmount});

            console2.log("/// After Swap End ///");
            return (BaseHook.afterSwap.selector, _feeAmount.toInt128());
        }

        // base case -> no fee
        console2.log("afterSwap - no fee");
        console2.log("/// After Swap End ///");
        return (BaseHook.afterSwap.selector, 0);

        // if (specifiedIsZero) {
        //     console2.log("/// After Swap End ///");
        //     return (BaseHook.afterSwap.selector, 0);
        // }

        // // taking hook fee on unspecified token (output token) i.e. when user is selling tokens and getting eth in return
        // // uint256 _feeAmount = (uint256(delta.amount0) * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;

        // int128 amount0 = delta.amount0();
        // console2.log("amount0: ", amount0);
        // int128 amount1 = delta.amount1();
        // console2.log("amount1: ", amount1);

        // // we will calculate fee on amount0
        // uint256 _feeAmount = (uint256(amount0.toUint128()) * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;
        // console2.log("feeAmount: ", _feeAmount);

        // poolManager.take({currency: key.currency0, to: address(this), amount: _feeAmount});

        // console2.log("/// After Swap End ///");
        // return (BaseHook.afterSwap.selector, _feeAmount.toInt128());
    }

    // To receive ETH
    receive() external payable {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _getInputOutputAndAmount(PoolKey calldata key, IPoolManager.SwapParams calldata params)
        internal
        pure
        returns (Currency input, Currency output, uint256 amount)
    {
        (input, output) = params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        amount = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
    }
}
