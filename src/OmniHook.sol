// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "forge-std/console2.sol";

contract OmniHook is BaseHook, Ownable {
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

        poolManager.take({currency: _feeCurrency, to: address(this), amount: _feeAmount});

        BeforeSwapDelta _returnDelta = toBeforeSwapDelta({
            deltaSpecified: int128(int256(_feeAmount)), // Specified delta (fee amount)
            deltaUnspecified: 0 // Unspecified delta (no change)
        });

        return (BaseHook.beforeSwap.selector, _returnDelta, 0);
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
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
