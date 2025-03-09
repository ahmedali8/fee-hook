// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// v4-core
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

// v4-periphery
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FeeLibrary} from "./libraries/FeeLibrary.sol";

contract OmniHook is BaseHook, Ownable {
    using FeeLibrary for uint256;
    using FeeLibrary for uint24;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for *;

    // 100 -> 0.01%
    uint24 public feeBips;

    event FeeUpdated(uint24 newFeeBips);

    constructor(IPoolManager _poolManager, address _initialOwner, uint24 _initialFeeBips)
        BaseHook(_poolManager)
        Ownable(_initialOwner)
    {
        _initialFeeBips.validate();
        feeBips = _initialFeeBips;
    }

    // To receive ETH
    receive() external payable {}

    /// @notice Updates the fee in bips
    /// @param _newFeeBips New fee in hundredths of a bip
    function setFee(uint24 _newFeeBips) external onlyOwner {
        _newFeeBips.validate();
        feeBips = _newFeeBips;
        emit FeeUpdated(_newFeeBips);
    }

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        bool _exactInput = params.amountSpecified < 0;
        uint256 _amount = _exactInput ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        if (
            // swapExactETHForTokens
            // If exactInput and zeroForOne -> take eth fee
            // specified token is input token (eth)
            // OR
            // swapTokensForExactETH
            // If exactOutput and oneForZero -> take eth fee
            // specified token is output token (eth)
            (_exactInput && params.zeroForOne) || (!_exactInput && !params.zeroForOne)
        ) {
            Currency _feeCurrency = key.currency0;

            uint256 _feeAmount = calculateFee(_amount);

            poolManager.take({currency: _feeCurrency, to: address(this), amount: _feeAmount});

            BeforeSwapDelta _returnDelta = toBeforeSwapDelta({
                deltaSpecified: int128(int256(_feeAmount)), // Specified delta (fee amount)
                deltaUnspecified: 0 // Unspecified delta (no change)
            });

            return (BaseHook.beforeSwap.selector, _returnDelta, 0);
        }

        // base case -> no fee
        return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        bool _exactInput = params.amountSpecified < 0;

        // no fee by default
        uint256 _feeAmount = 0;

        // swapETHForExactTokens
        // If exactOutput and zeroForOne -> take eth fee
        // unspecified token is input token (eth)
        if (!_exactInput && params.zeroForOne) {
            _feeAmount = calculateFee(uint256(uint128(-delta.amount0())));
        }

        // swapExactTokensForETH
        // If exactInput and oneForZero -> take eth fee
        // unspecified token is output token (eth)
        if (_exactInput && !params.zeroForOne) {
            _feeAmount = calculateFee(uint256(uint128(delta.amount0())));
        }

        Currency _feeCurrency = key.currency0;
        poolManager.take({currency: _feeCurrency, to: address(this), amount: _feeAmount});

        return (BaseHook.afterSwap.selector, _feeAmount.toInt128());
    }

    /// @notice Calculates the fee amount without rounding up
    /// @param amount The transaction amount
    /// @return feeAmount The calculated fee amount
    function calculateFee(uint256 amount) public view returns (uint256) {
        return amount.computeFee(feeBips);
    }

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
