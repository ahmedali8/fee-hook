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

import "forge-std/console2.sol";

contract OmniHook is BaseHook, Ownable {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for *;

    uint256 public constant HOOK_FEE_PERCENTAGE = 10; // 0.01% fee
    uint256 public constant FEE_DENOMINATOR = 100000;

    constructor(IPoolManager _poolManager, address _initialOwner) BaseHook(_poolManager) Ownable(_initialOwner) {}

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 _swapAmount =
            params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        uint256 _feeAmount = (_swapAmount * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;

        Currency _feeCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        console2.log("feeCurrency: ", address(Currency.unwrap(_feeCurrency)));

        if (!_feeCurrency.isAddressZero()) return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);

        console2.log("taking fee");

        poolManager.take({currency: _feeCurrency, to: address(this), amount: _feeAmount});

        BeforeSwapDelta _returnDelta = toBeforeSwapDelta({
            deltaSpecified: int128(int256(_feeAmount)), // Specified delta (fee amount)
            deltaUnspecified: 0 // Unspecified delta (no change)
        });

        return (BaseHook.beforeSwap.selector, _returnDelta, 0);
    }

    function _afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, BalanceDelta delta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        console2.log("// After Swap //");

        bool exactInput = params.amountSpecified < 0;
        console2.log("exactInput: ", exactInput);
        bool specifiedIsZero = params.zeroForOne == exactInput;
        console2.log("specifiedIsZero: ", specifiedIsZero);

        if (specifiedIsZero) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // taking hook fee on unspecified token (output token) i.e. when user is selling tokens and getting eth in return
        // uint256 _feeAmount = (uint256(delta.amount0) * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;

        int128 amount0 = delta.amount0();
        console2.log("amount0: ", amount0);
        int128 amount1 = delta.amount1();
        console2.log("amount1: ", amount1);

        // we will calculate fee on amount0
        uint256 _feeAmount = (uint256(amount0.toUint128()) * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;
        console2.log("feeAmount: ", _feeAmount);

        poolManager.take({currency: key.currency0, to: address(this), amount: _feeAmount});

        return (BaseHook.afterSwap.selector, _feeAmount.toInt128());
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
}
