// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// TYPES
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

// LIBRARIES
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {FeeLibrary} from "./libraries/FeeLibrary.sol";

// INTERFACES
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

// ABSTRACT CONTRACTS
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title OmniHook
/// @notice A Uniswap v4 hook contract that implements fee collection logic before and after swaps.
/// @dev This contract applies dynamic fees based on swap direction and token flows.
contract OmniHook is BaseHook, Ownable {
    using FeeLibrary for uint256;
    using FeeLibrary for uint24;
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;

    /// @notice Error thrown when attempting to set the same fee value.
    error FeeUnchanged();

    /// @notice Fee percentage represented in hundredths of a bip (1 bip = 0.0001%).
    uint24 public feeBips;

    /// @notice Emitted when the fee is updated.
    /// @param oldFeeBips Previous fee value.
    /// @param newFeeBips New fee value.
    event FeeUpdated(uint24 oldFeeBips, uint24 newFeeBips);

    /// @notice Emitted when a swap fee is collected.
    /// @param id The pool ID where the fee was taken.
    /// @param sender Address of the swap initiator.
    /// @param feeAmount0 Fee amount deducted from token0.
    /// @param feeAmount1 Fee amount deducted from token1.
    event HookFee(PoolId indexed id, address indexed sender, uint128 feeAmount0, uint128 feeAmount1);

    /// @notice Initializes the contract with the pool manager and an initial fee.
    /// @dev Ensures that the initial fee value is validated.
    /// @param _poolManager Address of the Uniswap v4 Pool Manager.
    /// @param _initialOwner Address of the contract owner.
    /// @param _initialFeeBips Initial fee in hundredths of a bip (0.0001% units).
    constructor(IPoolManager _poolManager, address _initialOwner, uint24 _initialFeeBips)
        BaseHook(_poolManager)
        Ownable(_initialOwner)
    {
        _initialFeeBips.validate();
        feeBips = _initialFeeBips;
    }

    /// @notice Allows the contract to receive ETH.
    receive() external payable {}

    /// @notice Updates the fee in hundredths of a bip.
    /// @dev Emits a `FeeUpdated` event if the fee is changed.
    /// @param newFeeBips The new fee value.
    function setFee(uint24 newFeeBips) external onlyOwner {
        newFeeBips.validate();
        uint24 _oldFeeBips = feeBips;
        if (newFeeBips == _oldFeeBips) revert FeeUnchanged();
        feeBips = newFeeBips;
        emit FeeUpdated(_oldFeeBips, newFeeBips);
    }

    /// @notice Hook executed before a swap to deduct fees when applicable.
    /// @dev The contract deducts a fee from the specified input token when conditions are met.
    ///
    /// Fee Deduction Logic:
    /// - swapExactETHForTokens
    ///   - If `exactInput` is `true` and `zeroForOne` is `true`, the specified token is ETH.
    ///   - exactInput && params.zeroForOne
    ///
    /// - swapTokensForExactETH
    ///   - If `exactInput` is `false` (exactOutput) and `zeroForOne` is `false` (oneForZero), the specified token is ETH.
    ///   - !_exactInput && !params.zeroForOne
    ///
    /// Combined control flow: exactInput == params.zeroForOne
    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        bool _exactInput = params.amountSpecified < 0;
        uint256 _amount = _exactInput ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        BeforeSwapDelta delta = toBeforeSwapDelta(0, 0); // default no fee

        if (_exactInput == params.zeroForOne) {
            uint256 _feeAmount;
            unchecked {
                _feeAmount = _amount.computeFee(feeBips);
            }

            if (_feeAmount == 0) return (BaseHook.beforeSwap.selector, delta, 0);

            poolManager.take({currency: key.currency0, to: address(this), amount: _feeAmount});

            emit HookFee(key.toId(), msg.sender, uint128(_feeAmount), 0);

            delta = toBeforeSwapDelta({
                deltaSpecified: int128(int256(_feeAmount)), // Specified delta (fee amount)
                deltaUnspecified: 0 // Unspecified delta (no change)
            });
        }

        return (BaseHook.beforeSwap.selector, delta, 0);
    }

    /// @notice Hook executed after a swap to deduct fees when applicable.
    /// @dev The contract deducts a fee from the unspecified token when conditions are met.
    ///
    /// Fee Deduction Logic:
    /// - swapETHForExactTokens
    ///   - If `exactInput` is `false` (exactOutput) and `zeroForOne` is `true`, the unspecified token is ETH.
    ///   - !exactInput && params.zeroForOne
    ///   - uint128(-delta.amount0())
    ///
    /// - swapExactTokensForETH
    ///   - If `exactInput` is `true` and `zeroForOne` is `false` (oneForZero), the unspecified token is ETH.
    ///   - exactInput && !params.zeroForOne
    ///   - uint128(delta.amount0())
    ///
    /// Combined control flow: exactInput != params.zeroForOne
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

        if (_exactInput != params.zeroForOne) {
            unchecked {
                _feeAmount =
                    uint256(uint128(params.zeroForOne ? -delta.amount0() : delta.amount0())).computeFee(feeBips);
            }

            if (_feeAmount == 0) return (BaseHook.afterSwap.selector, _feeAmount.toInt128());

            poolManager.take({currency: key.currency0, to: address(this), amount: _feeAmount});

            emit HookFee(key.toId(), msg.sender, uint128(_feeAmount), 0);
        }

        return (BaseHook.afterSwap.selector, _feeAmount.toInt128());
    }

    /// @notice Calculates the fee amount without rounding up
    /// @param amount The transaction amount
    /// @return fee The calculated fee amount
    function calculateFee(uint256 amount) external view returns (uint256 fee) {
        unchecked {
            fee = amount.computeFee(feeBips);
        }
    }

    /// @inheritdoc BaseHook
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
