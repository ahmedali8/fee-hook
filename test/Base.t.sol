// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import {Fixtures} from "./utils/Fixtures.sol";
import {Users} from "./utils/Types.sol";
import {Constants} from "./utils/Constants.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";

// v4-core
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";

// v4-periphery
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IV4Quoter} from "v4-periphery/src/interfaces/IV4Quoter.sol";
import {V4Quoter} from "v4-periphery/src/lens/V4Quoter.sol";
import {Deploy} from "v4-periphery/test/shared/Deploy.sol";
import {FeeHook} from "src/FeeHook.sol";

/// @notice Common contract members needed across test contracts.
abstract contract Base_Test is Fixtures, Constants {
    using EasyPosm for IPositionManager;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/

    IV4Quoter internal quoter;
    Users internal users;

    uint256 internal tokenId;
    int24 internal tickLower;
    int24 internal tickUpper;

    /*//////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    //////////////////////////////////////////////////////////////*/

    FeeHook internal hook;

    /*//////////////////////////////////////////////////////////////
                            SET-UP FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @dev A setup function invoked before each test case.
    function setUp() public virtual {
        // Create users for testing.
        users = Users({
            owner: createUser("Owner"),
            sender: createUser("Sender"),
            alice: createUser("Alice"),
            bob: createUser("Bob"),
            eve: createUser("Eve")
        });

        // Creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployAndApprovePosm(manager);
        quoter = Deploy.v4Quoter(address(manager), hex"00");

        // Deploy the hook to an address with the correct flags
        address _hookFlags = address(
            uint160(
                Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                    | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory _hookConstructorArgs = abi.encode(
            manager,
            users.owner,
            DEFAULT_MAX_BUY_AMOUNT,
            DEFAULT_MAX_SELL_AMOUNT,
            DEFAULT_MAX_WALLET_AMOUNT,
            DEFAULT_BUY_FEE_BIPS,
            DEFAULT_SELL_FEE_BIPS,
            DEFAULT_COOLDOWN_BLOCKS
        );
        deployCodeTo("FeeHook.sol:FeeHook", _hookConstructorArgs, _hookFlags);
        hook = FeeHook(payable(_hookFlags));

        // Label the test contracts
        vm.label({account: address(manager), newLabel: "PoolManager"});
        vm.label({account: Currency.unwrap(currency0), newLabel: "MockToken0"});
        vm.label({account: Currency.unwrap(currency1), newLabel: "MockToken1"});
        vm.label({account: address(permit2), newLabel: "Permit2"});
        vm.label({account: address(posm), newLabel: "PositionManager"});
        vm.label({account: address(quoter), newLabel: "Quoter"});
        vm.label({account: address(hook), newLabel: "FeeHook"});

        // Create Pool Key
        key = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: DEFAULT_TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        // Initialize Pool with 1:1 price ratio
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint({
            poolKey: key,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidityAmount,
            amount0Max: amount0Expected + 1,
            amount1Max: amount1Expected + 1,
            recipient: address(this),
            deadline: block.timestamp,
            hookData: ZERO_BYTES
        });

        // Set `users.sender` as the default caller for the tests.
        resetPrank({msgSender: users.sender});
    }

    /*//////////////////////////////////////////////////////////////
                            UTILS
    //////////////////////////////////////////////////////////////*/

    /// @dev Helper function that multiplies the `amount` by `10^18` and returns a `uint256.`
    function toWei(uint256 value) internal pure returns (uint256 result) {
        result = bn(value, 18);
    }

    /// @dev Helper function that multiplies the `amount` by `10^decimals` and returns a `uint256.`
    function bn(uint256 amount, uint256 decimals) internal pure returns (uint256 result) {
        result = amount * 10 ** decimals;
    }

    /// @dev Generates a user, labels its address, and funds it with 100 test ether.
    function createUser(string memory name) internal returns (address payable) {
        return createUser(name, 100 ether);
    }

    /// @dev Generates a user, labels its address, and funds it with test balance.
    function createUser(string memory name, uint256 balance) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: balance});
        return user;
    }

    /// @dev Stops the active prank and sets a new one.
    function resetPrank(address msgSender) internal {
        vm.stopPrank();
        vm.startPrank(msgSender);
    }
}
