// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/// @notice Shared constants used in scripts
contract Constants {
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    address constant POOL_MANAGER_ANVIL_ADDRESS = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address constant POSITION_MANAGER_ANVIL_ADDRESS = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

    address constant POOL_MANAGER_SEPOLIA_ADDRESS = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address constant POSITION_MANAGER_SEPOLIA_ADDRESS = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;

    IPoolManager constant POOLMANAGER = IPoolManager(POOL_MANAGER_SEPOLIA_ADDRESS);
    PositionManager constant posm = PositionManager(payable(POSITION_MANAGER_SEPOLIA_ADDRESS));
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
}
