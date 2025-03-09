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

contract OmniHook is BaseHook, Ownable {
    using FeeLibrary for uint256;
    using FeeLibrary for uint24;
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;

    error FeeUnchanged();

    // 100 -> 0.01%
    uint24 public feeBips;

    event FeeUpdated(uint24 oldFeeBips, uint24 newFeeBips);

    event HookFee(PoolId indexed id, address indexed sender, uint128 feeAmount0, uint128 feeAmount1);

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
    /// @param newFeeBips New fee in hundredths of a bip
    function setFee(uint24 newFeeBips) external onlyOwner {
        newFeeBips.validate();
        uint24 _oldFeeBips = feeBips;
        if (newFeeBips == _oldFeeBips) revert FeeUnchanged();
        feeBips = newFeeBips;
        emit FeeUpdated(_oldFeeBips, newFeeBips);
    }

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        bool _exactInput = params.amountSpecified < 0;
        uint256 _amount = _exactInput ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        BeforeSwapDelta delta = toBeforeSwapDelta(0, 0); // default no fee

        if (
            // swapExactETHForTokens
            // If exactInput and zeroForOne -> take eth fee
            // specified token is input token (eth)
            // (_exactInput && params.zeroForOne)
            // OR
            // swapTokensForExactETH
            // If exactOutput and oneForZero -> take eth fee
            // specified token is output token (eth)
            // (!_exactInput && !params.zeroForOne)
            //
            // specifiedIsZero
            _exactInput == params.zeroForOne
        ) {
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

        // we wanna take fee in unspecified token i.e. eth
        // if (!_exactInput && params.zeroForOne)
        // swapETHForExactTokens
        // If exactOutput and zeroForOne -> take eth fee
        // unspecified token is input token (eth)
        // uint128(-delta.amount0())
        //
        // if (_exactInput && !params.zeroForOne)
        // swapExactTokensForETH
        // If exactInput and oneForZero -> take eth fee
        // unspecified token is output token (eth)
        // uint128(delta.amount0())
        if (_exactInput != params.zeroForOne) {
            unchecked {
                _feeAmount = uint256(uint128(params.zeroForOne ? -delta.amount0() : delta.amount0())).computeFee(feeBips);
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
