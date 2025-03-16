// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Constants} from "../base/Constants.sol";

import {FeeHook} from "src/FeeHook.sol";

/// @notice Mines the address and deploys the FeeHook.sol Hook contract
contract DeployFeeHookScript is Script, Constants {
    function setUp() public {}

    function deployFeeHook(
        address initialOwner,
        uint128 maxBuyAmount,
        uint128 maxSellAmount,
        uint128 maxWalletAmount,
        uint24 initialBuyFeeBips,
        uint24 initialSellFeeBips,
        uint32 cooldownBlocks
    ) internal returns (FeeHook feeHook) {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(
            POOLMANAGER,
            initialOwner,
            maxBuyAmount,
            maxSellAmount,
            maxWalletAmount,
            initialBuyFeeBips,
            initialSellFeeBips,
            cooldownBlocks
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(FeeHook).creationCode, constructorArgs);

        feeHook = new FeeHook{salt: salt}(
            IPoolManager(POOLMANAGER),
            initialOwner,
            maxBuyAmount,
            maxSellAmount,
            maxWalletAmount,
            initialBuyFeeBips,
            initialSellFeeBips,
            cooldownBlocks
        );

        require(address(feeHook) == hookAddress, "DeployFeeHookScript: hook address mismatch");
    }

    function run() public {
        // Deploy the hook using CREATE2
        vm.startBroadcast();
        console2.log("caller: ", msg.sender);
        FeeHook feeHook = deployFeeHook({
            initialOwner: msg.sender,
            maxBuyAmount: (100_000_000 ether * 10) / 1000, // 1% of 100M
            maxSellAmount: (100_000_000 ether * 10) / 1000, // 1% of 100M
            maxWalletAmount: (100_000_000 ether * 10) / 1000, // 1% of 100M
            initialBuyFeeBips: 10_000, // 1%
            initialSellFeeBips: 10_000, // 1%
            cooldownBlocks: 3
        });
        vm.stopBroadcast();

        // Log the omni hook address
        console2.log("FeeHook deployed at:", address(feeHook));
    }
}
