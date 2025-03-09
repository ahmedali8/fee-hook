// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/console2.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

/// @title FeeLibrary - Computes dynamic fees using bips (basis points)
/// @notice Handles fee calculations with Uniswap-style precision (hundredths of a bip)
library FeeLibrary {
    using FeeLibrary for uint24;

    /// @notice Thrown when the fee exceeds the maximum limit (100%)
    error FeeTooLarge(uint24 fee);

    /// @notice The maximum fee in hundredths of a bip (1,000,000 = 100%)
    uint24 public constant MAX_FEE_BIPS = 1_000_000;

    /// @notice Checks if a fee is valid (≤ 100%)
    /// @param self The fee to validate
    /// @return bool True if the fee is valid
    function isValid(uint24 self) internal pure returns (bool) {
        return self <= MAX_FEE_BIPS;
    }

    /// @notice Validates the fee and reverts if it exceeds 100%
    /// @param self The fee to validate
    function validate(uint24 self) internal pure {
        if (!self.isValid()) revert FeeTooLarge(self);
    }

    /// @notice Computes the fee amount for a given input
    /// @param amount The transaction amount
    /// @param feeBips The fee in hundredths of a bip (uint24)
    /// @return feeAmount The calculated fee amount
    function computeFee(uint256 amount, uint24 feeBips) internal pure returns (uint256 feeAmount) {
        feeBips.validate();
        console2.log("amount: ", amount);
        console2.log("feeBips: ", feeBips);
        feeAmount = FullMath.mulDiv(amount, uint256(feeBips), uint256(MAX_FEE_BIPS));
    }
}
