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

/// @title TaxHook
/// @notice A Uniswap v4 hook contract that implements fee collection logic before and after swaps.
/// @dev This contract applies dynamic fees based on swap direction and token flows.
contract TaxHook is BaseHook, Ownable {
    using FeeLibrary for uint256;
    using FeeLibrary for uint24;
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;

    /// ------------------------------- ///
    ///          ERROR MESSAGES         ///
    /// ------------------------------- ///

    error InvalidLimit();
    error InvalidCooldown();
    error AlreadyLaunched();
    error InvalidBlacklistAction();
    error InvalidWhitelistAction();

    /// ------------------------------- ///
    ///         STATE VARIABLES         ///
    /// ------------------------------- ///

    /// @notice Fee percentage represented in hundredths of a bip (1 bip = 0.0001%).
    uint24 public feeBips;

    /// @notice Swap fees in basis points (1 bip = 0.0001%)
    uint24 public buyFeeBips;
    uint24 public sellFeeBips;

    /// @notice Maximum buy, sell, and wallet limits
    uint256 public maxBuyAmount;
    uint256 public maxSellAmount;
    uint256 public maxWalletAmount;

    /// @notice Whether cooldowns are enabled
    bool public isCooldownEnabled;

    /// @notice Cooldown period for transactions (blocks)
    uint32 public cooldownBlocks;

    bool public isLimitsEnabled;

    bool public isTaxEnabled;

    /// @notice Flag indicating whether trading is enabled.
    bool public isLaunched;
    uint32 public launchBlock;
    uint64 public launchTime;

    /// @notice Tracks last transaction block for cooldown enforcement
    mapping(address user => uint32 lastBlock) public userLastTransactionBlock;

    /// @notice Blacklisted addresses (prevent bots)
    mapping(address user => bool blacklisted) public isBlacklisted;

    /// @notice Excluded from fees
    mapping(address user => bool excluded) public isExcludedFromFees;

    /// @notice Excluded from trading limits
    mapping(address user => bool excluded) public isExcludedFromLimits;

    /// ------------------------------- ///
    ///          EVENTS                 ///
    /// ------------------------------- ///

    event Launched(uint32 launchBlock, uint64 launchTime);
    event SwapFeesUpdated(uint24 oldBuyFeeBips, uint24 newBuyFeeBips, uint24 oldSellFeeBips, uint24 newSellFeeBips);
    event TradeLimitsUpdated(uint256 maxBuy, uint256 maxSell, uint256 maxWallet);
    event CooldownBlocksUpdated(uint32 blocks);
    event LimitsEnabledUpdated(bool enabled);
    event TaxEnabledUpdated(bool enabled);
    event CooldownEnabledUpdated(bool enabled);
    event AddressBlacklisted(address indexed user, bool status);
    event AddressWhitelisted(address indexed user, bool isExcludedFromFees, bool isExcludedFromLimits);

    /// @notice Emitted when a swap fee is collected.
    /// @param id The pool ID where the fee was taken.
    /// @param sender Address of the swap initiator.
    /// @param feeAmount0 Fee amount deducted from token0.
    /// @param feeAmount1 Fee amount deducted from token1.
    event HookFee(PoolId indexed id, address indexed sender, uint128 feeAmount0, uint128 feeAmount1);

    /// ------------------------------- ///
    ///       CONTRACT CONSTRUCTOR      ///
    /// ------------------------------- ///

    /// @notice Initializes the contract with the pool manager and default settings.
    /// @param _poolManager The Uniswap v4 Pool Manager.
    /// @param _initialOwner The initial contract owner.
    /// @param _initialBuyFeeBips Initial buy fee (in hundredths of a bip).
    /// @param _initialSellFeeBips Initial sell fee (in hundredths of a bip).
    /// @param _maxBuyAmount Initial max buy limit.
    /// @param _maxSellAmount Initial max sell limit.
    /// @param _maxWalletAmount Initial max wallet size.
    /// @param _cooldownBlocks Initial cooldown block duration.
    constructor(
        IPoolManager _poolManager,
        address _initialOwner,
        uint24 _initialBuyFeeBips,
        uint24 _initialSellFeeBips,
        uint256 _maxBuyAmount,
        uint256 _maxSellAmount,
        uint256 _maxWalletAmount,
        uint32 _cooldownBlocks
    ) BaseHook(_poolManager) Ownable(_initialOwner) {
        // Validate initial fee values
        _initialBuyFeeBips.validate();
        _initialSellFeeBips.validate();

        // Set initial fees
        buyFeeBips = _initialBuyFeeBips;
        sellFeeBips = _initialSellFeeBips;

        // Set transaction limits
        maxBuyAmount = _maxBuyAmount;
        maxSellAmount = _maxSellAmount;
        maxWalletAmount = _maxWalletAmount;

        // Set cooldown settings
        cooldownBlocks = _cooldownBlocks;

        // Default state settings
        isLimitsEnabled = true;
        isTaxEnabled = true;
        // isCooldownEnabled = false;
    }

    /// @notice Allows the contract to receive ETH.
    receive() external payable {}

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

        if (_exactInput != params.zeroForOne) return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);

        uint256 _feeAmount;
        unchecked {
            _feeAmount = uint256(_exactInput ? -params.amountSpecified : params.amountSpecified).computeFee(feeBips);
        }

        if (_feeAmount == 0) return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);

        poolManager.take({currency: key.currency0, to: address(this), amount: _feeAmount});
        emit HookFee(key.toId(), msg.sender, uint128(_feeAmount), 0);

        return (
            BaseHook.beforeSwap.selector,
            toBeforeSwapDelta({
                deltaSpecified: int128(int256(_feeAmount)), // Specified delta (fee amount)
                deltaUnspecified: 0 // Unspecified delta (no change)
            }),
            0
        );
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

        if (_exactInput == params.zeroForOne) return (BaseHook.afterSwap.selector, 0);

        uint256 _feeAmount;
        unchecked {
            _feeAmount = uint256(uint128(params.zeroForOne ? -delta.amount0() : delta.amount0())).computeFee(feeBips);
        }

        if (_feeAmount == 0) return (BaseHook.afterSwap.selector, 0);

        poolManager.take({currency: key.currency0, to: address(this), amount: _feeAmount});
        emit HookFee(key.toId(), msg.sender, uint128(_feeAmount), 0);

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

    /// ------------------------------- ///
    ///       ADMIN SETTER FUNCTIONS   ///
    /// ------------------------------- ///

    /// @notice Enables trading by setting launch parameters.
    /// @dev Can only be called once.
    function enableTrading() external onlyOwner {
        if (isLaunched) revert AlreadyLaunched();

        isLaunched = true;
        launchBlock = uint32(block.number);
        launchTime = uint64(block.timestamp);

        emit Launched(launchBlock, launchTime);
    }

    function setTradeLimits(uint256 newMaxBuy, uint256 newMaxSell, uint256 newMaxWallet) external onlyOwner {
        if (newMaxBuy == 0 || newMaxSell == 0 || newMaxWallet == 0) revert InvalidLimit();
        maxBuyAmount = newMaxBuy;
        maxSellAmount = newMaxSell;
        maxWalletAmount = newMaxWallet;
        emit TradeLimitsUpdated(newMaxBuy, newMaxSell, newMaxWallet);
    }

    /// @notice Enables or disables trading limits.
    /// @param status `true` to enable limits, `false` to disable.
    function setLimitsEnabled(bool status) external onlyOwner {
        isLimitsEnabled = status;
        emit LimitsEnabledUpdated(status);
    }

    /// @notice Enables or disables tax collection.
    /// @param status `true` to enable tax, `false` to disable.
    function setTaxEnabled(bool status) external onlyOwner {
        isTaxEnabled = status;
        emit TaxEnabledUpdated(status);
    }

    /// @notice Enables or disables the cooldown mechanism.
    /// @param status `true` to enable cooldowns, `false` to disable.
    function setCooldownEnabled(bool status) external onlyOwner {
        isCooldownEnabled = status;
        emit CooldownEnabledUpdated(status);
    }

    function setCooldownBlocks(uint32 newCooldownBlocks) external onlyOwner {
        if (newCooldownBlocks == 0) revert InvalidCooldown();
        cooldownBlocks = newCooldownBlocks;
        emit CooldownBlocksUpdated(newCooldownBlocks);
    }

    function setBlacklist(address user, bool status) external onlyOwner {
        if (user == address(0)) revert InvalidBlacklistAction();
        isBlacklisted[user] = status;
        emit AddressBlacklisted(user, status);
    }

    function setWhitelist(address user, bool excludeFees, bool excludeLimits) external onlyOwner {
        if (user == address(0)) revert InvalidWhitelistAction();
        isExcludedFromFees[user] = excludeFees;
        isExcludedFromLimits[user] = excludeLimits;
        emit AddressWhitelisted(user, excludeFees, excludeLimits);
    }

    /// @notice Updates buy and sell fees.
    /// @param newBuyFeeBips New buy fee (in hundredths of a bip).
    /// @param newSellFeeBips New sell fee (in hundredths of a bip).
    function setSwapFees(uint24 newBuyFeeBips, uint24 newSellFeeBips) external onlyOwner {
        newBuyFeeBips.validate();
        newSellFeeBips.validate();

        uint24 _oldBuyFeeBips = buyFeeBips;
        uint24 _oldSellFeeBips = sellFeeBips;

        buyFeeBips = newBuyFeeBips;
        sellFeeBips = newSellFeeBips;

        emit SwapFeesUpdated(_oldBuyFeeBips, newBuyFeeBips, _oldSellFeeBips, newSellFeeBips);
    }
}
