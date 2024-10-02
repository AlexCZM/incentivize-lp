// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IncentivizeLpHook} from "../src/IncentivizeLpHook.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

contract IncentivizeLpHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    IncentivizeLpHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager); // managers is declared in Fixtures-> Deployers

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("IncentivizeLpHook.sol:IncentivizeLpHook", constructorArgs, flags);
        hook = IncentivizeLpHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 30, IHooks(hook)); // , , fee, tickSpacing, hooks
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provide liquidity to [-10, 10] *tickSpacing interval around the current tick calculated from sqrtPriceX96
        tickLower = TickMath.minUsableTick(key.tickSpacing); //-6930 - (10 * key.tickSpacing);//
        tickUpper = TickMath.maxUsableTick(key.tickSpacing); //-6930 + (10 * key.tickSpacing);//

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function test_setup() public view {
        uint128 liquidity = manager.getLiquidity(poolId);
        console.log("liquidity: ", liquidity);

        (uint160 sqrtPriceX96, int24 currentTick, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(poolId);
        (uint128 liqGross, int128 liqNet) = manager.getTickLiquidity(poolId, tickLower);
        console.log("liqGross: ", liqGross);
        console.log("liquidityNet ...");
        console.logInt(liqNet);
        console.log("sqrtPriceX96: ", sqrtPriceX96);
        console.log("currentTick ... ");
        console.logInt(currentTick);
        console.log("protocolFee: ", protocolFee);
        console.log("lpFee: ", lpFee);
    }

    function testLiquidityHooks_1() public {
        bool zeroForOne = true;
        int256 amountSpecified = -1e18;

        (,,, uint24 lpFeeBefore) = manager.getSlot0(poolId);

        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        (,,, uint24 lpFeeAfter) = manager.getSlot0(poolId);

        console.log("lpFeeBefore: ", lpFeeBefore);
        console.log("lpFeeAfter: ", lpFeeAfter);
    }
}
