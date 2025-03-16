// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

abstract contract Constants {
    uint40 internal constant MARCH_1_2025 = 1_740_787_200;

    uint128 internal constant MAX_UINT128 = type(uint128).max;
    uint256 internal constant MAX_UINT256 = type(uint256).max;
    uint40 internal constant MAX_UINT40 = type(uint40).max;

    /// @dev Default tickSpacing for DynamicFee Hook
    int24 internal constant DEFAULT_TICK_SPACING = 60;

    uint256 internal constant VIRTUAL_TOTAL_SUPPLY = 100_000_000 ether;

    uint128 internal constant DEFAULT_MAX_BUY_AMOUNT = (uint128(VIRTUAL_TOTAL_SUPPLY) * 10) / 1000;
    uint128 internal constant DEFAULT_MAX_SELL_AMOUNT = (uint128(VIRTUAL_TOTAL_SUPPLY) * 10) / 1000;
    uint128 internal constant DEFAULT_MAX_WALLET_AMOUNT = (uint128(VIRTUAL_TOTAL_SUPPLY) * 10) / 1000;
    uint24 internal constant DEFAULT_BUY_FEE_BIPS = 10_000; // 1%
    uint24 internal constant DEFAULT_SELL_FEE_BIPS = 20_000; // 2%
    uint32 internal constant DEFAULT_COOLDOWN_BLOCKS = 0;
}
