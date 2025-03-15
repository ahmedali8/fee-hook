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

import "forge-std/console2.sol";

/// @title FeeHook
/// @notice A Uniswap v4 hook contract that implements fee collection logic before and after swaps.
/// @dev This contract applies dynamic fees based on swap direction and token flows.
contract FeeHook is BaseHook, Ownable {
    using FeeLibrary for uint256;
    using FeeLibrary for uint24;
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;

    /// ------------------------------- ///
    ///          ERROR MESSAGES         ///
    /// ------------------------------- ///

    error AlreadyLaunched();
    error InvalidBlacklistAction();
    error InvalidWhitelistAction();
    error ETHTransferFailed();
    error NotLaunched();
    error BlacklistedUser();
    error CooldownActive();
    error MaxBuyExceeded();
    error MaxSellExceeded();
    error MaxWalletExceeded();

    /// ------------------------------- ///
    ///         STATE VARIABLES         ///
    /// ------------------------------- ///

    address public constant DEAD_ADDRESS = address(0xdEaD);

    /// @notice Flag indicating whether trading is enabled.
    uint32 public launchBlock;

    /// @notice Swap fees in basis points (1 bip = 0.0001%)
    /// Fee percentage represented in hundredths of a bip (1 bip = 0.0001%).
    uint24 public buyFeeBips;
    uint24 public sellFeeBips;

    /// @notice Cooldown period for transactions (blocks)
    uint32 public cooldownBlocks;

    /// @notice Maximum buy, sell, and wallet limits
    uint128 public maxBuyAmount;
    uint128 public maxSellAmount;
    uint128 public maxWalletAmount;

    /// @notice Tracks last transaction block for cooldown enforcement
    mapping(address user => uint32 lastBlock) public userLastTransactionBlock;

    /// @notice Blacklisted addresses (prevent bots)
    mapping(address user => bool blacklisted) public isBlacklisted;

    /// @notice Excluded from fees
    mapping(address user => bool excluded) public isExcludedFromFees;

    /// @notice Excluded from trading limits
    mapping(address user => bool excluded) public isExcludedFromTradeLimits;

    /// ------------------------------- ///
    ///          EVENTS                 ///
    /// ------------------------------- ///

    event Launched(uint32 launchBlock);
    event SwapFeesUpdated(uint24 oldBuyFeeBips, uint24 newBuyFeeBips, uint24 oldSellFeeBips, uint24 newSellFeeBips);
    event TradeLimitsUpdated(uint128 maxBuy, uint128 maxSell, uint128 maxWallet);
    event CooldownBlocksUpdated(uint32 blocks);
    event LimitsEnabledUpdated(bool enabled);
    event FeeEnabledUpdated(bool enabled);
    event CooldownEnabledUpdated(bool enabled);
    event AddressBlacklisted(address indexed user, bool status);
    event AddressWhitelisted(address indexed user, bool isExcludedFromFees, bool isExcludedFromTradeLimits);

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
    /// @param _maxBuyAmount Initial max buy limit.
    /// @param _maxSellAmount Initial max sell limit.
    /// @param _maxWalletAmount Initial max wallet size.
    /// @param _initialBuyFeeBips Initial buy fee (in hundredths of a bip).
    /// @param _initialSellFeeBips Initial sell fee (in hundredths of a bip).
    /// @param _cooldownBlocks Initial cooldown block duration.
    constructor(
        IPoolManager _poolManager,
        address _initialOwner,
        uint128 _maxBuyAmount,
        uint128 _maxSellAmount,
        uint128 _maxWalletAmount,
        uint24 _initialBuyFeeBips,
        uint24 _initialSellFeeBips,
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

        _updateWhitelist(DEAD_ADDRESS, true, true);
    }

    /// @notice Allows the contract to receive ETH.
    /// TODO: distribute eth to wallets
    receive() external payable {
        // (bool _success,) = owner().call{value: msg.value}("");
        // if (!_success) revert ETHTransferFailed();
    }

    function _transferOwnership(address newOwner) internal override {
        address _oldOwner = owner();
        if (_oldOwner != address(0)) {
            _updateWhitelist(_oldOwner, false, false);
        }
        _updateWhitelist(newOwner, true, true);
        super._transferOwnership(newOwner);
    }

    /// @notice Hook executed before a swap to deduct fees when applicable.
    /// @dev The contract deducts a fee from the specified input token when conditions are met.
    ///
    /// Fee Deduction Logic:
    /// - swapExactETHForTokens (Buy)
    ///   - If `exactInput` is `true` and `zeroForOne` is `true`, the specified token is ETH.
    ///   - exactInput && params.zeroForOne
    ///
    /// - swapTokensForExactETH (Sell)
    ///   - If `exactInput` is `false` (exactOutput) and `zeroForOne` is `false` (oneForZero), the specified token is ETH.
    ///   - !_exactInput && !params.zeroForOne
    ///
    /// Combined control flow: exactInput == params.zeroForOne
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata /* hookData */
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        bool _exactInput = params.amountSpecified < 0;
        uint256 _amount = uint256(_exactInput ? -params.amountSpecified : params.amountSpecified);

        if (_exactInput != params.zeroForOne) return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);

        // Trading must be enabled
        if (!isLaunched()) revert NotLaunched();

        // Sender cannot be blacklisted
        if (isBlacklisted[sender]) revert BlacklistedUser();

        // Transaction Limits (Limits must be enabled OR sender must not be excluded from limits)
        if (isTradeLimitsEnabled() && !isExcludedFromTradeLimits[sender]) {
            // Cooldown Enforcement
            if (isCooldownEnabled()) {
                uint32 _blockNumber = uint32(block.number);
                if (_blockNumber < userLastTransactionBlock[sender] + cooldownBlocks) {
                    revert CooldownActive();
                }
                userLastTransactionBlock[sender] = _blockNumber;
            }

            // Check Max Buy Limit
            if (_exactInput && params.zeroForOne && _amount > maxBuyAmount) revert MaxBuyExceeded();

            // Check Max Sell Limit
            if (!_exactInput && !params.zeroForOne && _amount > maxSellAmount) revert MaxSellExceeded();

            // Check Max Wallet Limit
            if (key.currency1.balanceOf(sender) > maxWalletAmount) revert MaxWalletExceeded();
        }

        // Global Fee Disable Check OR Fee Exemption Check
        if (!isFeeEnabled() || isExcludedFromFees[sender]) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        uint256 _feeAmount;
        unchecked {
            _feeAmount = _amount.computeFee(_exactInput ? buyFeeBips : sellFeeBips);
        }

        // If No Fee, Return Early
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
    /// - swapETHForExactTokens (Buy)
    ///   - If `exactInput` is `false` (exactOutput) and `zeroForOne` is `true`, the unspecified token is ETH.
    ///   - !exactInput && params.zeroForOne
    ///   - uint128(-delta.amount0())
    ///
    /// - swapExactTokensForETH (Sell)
    ///   - If `exactInput` is `true` and `zeroForOne` is `false` (oneForZero), the unspecified token is ETH.
    ///   - exactInput && !params.zeroForOne
    ///   - uint128(delta.amount0())
    ///
    /// Combined control flow: exactInput != params.zeroForOne
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata /* hookData */
    ) internal override returns (bytes4, int128) {
        bool _exactInput = params.amountSpecified < 0;

        if (_exactInput == params.zeroForOne) return (BaseHook.afterSwap.selector, 0);

        // Global Fee Disable Check OR Fee Exemption Check
        if (!isFeeEnabled() || isExcludedFromFees[sender]) return (BaseHook.afterSwap.selector, 0);

        uint256 _feeAmount;
        unchecked {
            uint24 _feeBips = _exactInput ? sellFeeBips : buyFeeBips;
            uint256 _amount = uint256(uint128(params.zeroForOne ? -delta.amount0() : delta.amount0()));
            _feeAmount = _amount.computeFee(_feeBips);
        }

        if (_feeAmount == 0) return (BaseHook.afterSwap.selector, 0);

        poolManager.take({currency: key.currency0, to: address(this), amount: _feeAmount});
        emit HookFee(key.toId(), msg.sender, uint128(_feeAmount), 0);

        return (BaseHook.afterSwap.selector, _feeAmount.toInt128());
    }

    /// @notice Calculates the fee amount without rounding up
    /// @param amount The transaction amount
    /// @return buyFee The calculated buy fee amount
    /// @return sellFee The calculated sell fee amount
    function calculateFees(uint256 amount) external view returns (uint256 buyFee, uint256 sellFee) {
        unchecked {
            buyFee = amount.computeFee(buyFeeBips);
            sellFee = amount.computeFee(sellFeeBips);
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
    function launch() external onlyOwner {
        if (uint32(launchBlock) > 0) revert AlreadyLaunched();

        launchBlock = uint32(block.number);

        emit Launched(launchBlock);
    }

    function setTradeLimits(uint128 newMaxBuy, uint128 newMaxSell, uint128 newMaxWallet) external onlyOwner {
        maxBuyAmount = newMaxBuy;
        maxSellAmount = newMaxSell;
        maxWalletAmount = newMaxWallet;
        emit TradeLimitsUpdated(newMaxBuy, newMaxSell, newMaxWallet);
    }

    function setCooldownBlocks(uint32 newCooldownBlocks) external onlyOwner {
        cooldownBlocks = newCooldownBlocks;
        emit CooldownBlocksUpdated(newCooldownBlocks);
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

    /// @notice Adds or removes a single address from the blacklist.
    /// @param user Address to blacklist or unblacklist.
    /// @param status True to blacklist, false to remove from blacklist.
    function setBlacklist(address user, bool status) external onlyOwner {
        _updateBlacklist(user, status);
    }

    /// @notice Adds or removes multiple addresses from the blacklist.
    /// @param users List of user addresses.
    /// @param status True to blacklist, false to remove from blacklist.
    function setBlacklistBatch(address[] calldata users, bool status) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            _updateBlacklist(users[i], status);
        }
    }

    /// @notice Excludes a single address from fees and trading limits.
    /// @param user Address to update.
    /// @param excludeFees True to exclude from fees, false to include.
    /// @param excludeLimits True to exclude from limits, false to include.
    function setWhitelist(address user, bool excludeFees, bool excludeLimits) external onlyOwner {
        _updateWhitelist(user, excludeFees, excludeLimits);
    }

    /// @notice Excludes multiple addresses from fees and trading limits.
    /// @param users List of user addresses.
    /// @param excludeFees True to exclude from fees, false to include.
    /// @param excludeLimits True to exclude from limits, false to include.
    function setWhitelistBatch(address[] calldata users, bool excludeFees, bool excludeLimits) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            _updateWhitelist(users[i], excludeFees, excludeLimits);
        }
    }

    /// ------------------------------- ///
    ///       CONSTANT FUNCTIONS        ///
    /// ------------------------------- ///

    /// @notice Whether trading is enabled.
    /// @dev Trading is enabled if launchBlock is greater than zero.
    /// @return `true` if trading is enabled, `false` otherwise.
    function isLaunched() public view returns (bool) {
        return launchBlock > 0;
    }

    /// @notice Whether cooldowns are enabled
    /// @dev If cooldownBlocks is zero, then cooldowns are disabled
    /// @return `true` if cooldowns are enabled, `false` otherwise.
    function isCooldownEnabled() public view returns (bool) {
        return cooldownBlocks > 0;
    }

    /// @notice Whether trading limits are enabled.
    /// @dev If buyFeeBips or sellFeeBips are zero, then fees are disabled.
    /// @return `true` if trading limits are enabled, `false` otherwise.
    function isFeeEnabled() public view returns (bool) {
        return buyFeeBips > 0 || sellFeeBips > 0;
    }

    /// @notice Whether trading limits are enabled.
    /// @dev If maxBuyAmount, maxSellAmount, and maxWalletAmount are all zero, then limits are disabled.
    /// @return `true` if trading limits are enabled, `false` otherwise.
    function isTradeLimitsEnabled() public view returns (bool) {
        return maxBuyAmount > 0 && maxSellAmount > 0 && maxWalletAmount > 0;
    }

    /// ------------------------------- ///
    ///       INTERNAL FUNCTIONS        ///
    /// ------------------------------- ///

    /// @dev Internal function to update the blacklist mapping.
    /// @param user Address to blacklist or un-blacklist.
    /// @param status True to blacklist, false to remove from blacklist.
    function _updateBlacklist(address user, bool status) internal {
        if (
            user == address(0) || user == address(poolManager) || user == address(this) || isExcludedFromFees[user]
                || isExcludedFromTradeLimits[user] || isBlacklisted[user] == status
        ) {
            revert InvalidBlacklistAction();
        }

        isBlacklisted[user] = status;
        emit AddressBlacklisted(user, status);
    }

    /// @dev Internal function to update whitelist mappings.
    /// @param user Address to update.
    /// @param excludeFees True to exclude from fees, false to include.
    /// @param excludeLimits True to exclude from limits, false to include.
    function _updateWhitelist(address user, bool excludeFees, bool excludeLimits) internal {
        bool _feesUnchanged = isExcludedFromFees[user] == excludeFees;
        bool _limitsUnchanged = isExcludedFromTradeLimits[user] == excludeLimits;

        // Check if user is zero address or both values are unchanged
        if (user == address(0) || (_feesUnchanged && _limitsUnchanged)) {
            revert InvalidWhitelistAction();
        }

        // Only update storage if values are changing
        if (!_feesUnchanged) isExcludedFromFees[user] = excludeFees;
        if (!_limitsUnchanged) isExcludedFromTradeLimits[user] = excludeLimits;

        emit AddressWhitelisted(user, excludeFees, excludeLimits);
    }
}
