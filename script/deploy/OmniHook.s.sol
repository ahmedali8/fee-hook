// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Constants} from "../base/Constants.sol";

import {OmniHook} from "src/OmniHook.sol";

/// @notice Mines the address and deploys the OmniHook.sol Hook contract
contract DeployOmniHook is Script, Constants {
    function setUp() public {}

    function deployOmniHook(address initialOwner, uint24 initialBips) internal returns (OmniHook omniHook) {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER, initialOwner, initialBips);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(OmniHook).creationCode, constructorArgs);

        omniHook = new OmniHook{salt: salt}(IPoolManager(POOLMANAGER), initialOwner, initialBips);

        require(address(omniHook) == hookAddress, "CounterScript: hook address mismatch");
    }

    function run() public {
        uint24 initialBips = 10_000; // 1%

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        console2.log("caller: ", msg.sender);
        OmniHook omniHook = deployOmniHook(msg.sender, initialBips);
        vm.stopBroadcast();

        // Log the omni hook address
        console2.log("OmniHook deployed at:", address(omniHook));
    }
}
