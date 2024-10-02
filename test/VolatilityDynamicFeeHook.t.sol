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
import {VolatilityDynamicFeeHook} from "../src/VolatilityDynamicFeeHook.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

contract VolatilityDynamicFeeHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // hook constants
    uint24 constant MAX_FEE = 50_000; // 5%
    uint24 constant FIXED_FEE = 3_000; // 0.3%

    VolatilityDynamicFeeHook hook;
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
        deployCodeTo("VolatilityDynamicFeeHook.sol:VolatilityDynamicFeeHook", constructorArgs, flags);
        hook = VolatilityDynamicFeeHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 30, IHooks(hook)); // , , fee, tickSpacing, hooks
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        tickLower = -120;
        tickUpper = 120;

        uint128 liquidityAmount = 1_000e18;

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
        // ensure pool has liquidity over a wider range of ticks
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-9_000, 9_000, 1_000e18, 0), ZERO_BYTES
        );
    }

    // ensure that the same tick swap doesn't change the fee
    function test_sameTickSwap_minFee() public {
        // A negative amount means it is an exactInput swap, so the user is sending exactly that amount into the pool.
        // A positive amount means it is an exactOutput swap, so the user is only requesting that amount out of the swap.
        int256 amountSpecified = -10;
        bool zeroForOne = false;
        (, int24 tickBefore,, uint24 lpFeeBefore) = manager.getSlot0(poolId);

        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        (, int24 tickAfter,,) = manager.getSlot0(poolId);

        // lp fee is updated once every 24hours
        vm.warp(block.timestamp + 25 hours);
        // trigger any potential fee update
        swap(key, zeroForOne, -1, ZERO_BYTES);

        (,,, uint24 lpFeeAfter) = manager.getSlot0(poolId);
        assertEq(tickBefore, tickAfter, "Not same tick swap");
        assertEq(lpFeeBefore, lpFeeAfter, "LP fee changed; NOK");
    }

    // LP fee is capped at maxFee when price changes by more than  50%
    function test_highVolatility_maxFeeCapped() public {
        int256 amountSpecified = -250e18;
        bool zeroForOne = false;
        (, int24 tickBefore,,) = manager.getSlot0(poolId);

        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        (, int24 tickAfter,,) = manager.getSlot0(poolId);

        // lp fee is updated once every 24hours
        vm.warp(block.timestamp + 25 hours);
        swap(key, zeroForOne, -10, ZERO_BYTES);

        (,,, uint24 lpFeeAfter) = manager.getSlot0(poolId);
        assertGt(tickAfter, tickBefore + 4055, "deltaTick must be bigger than 4055 ticks");
        assertEq(lpFeeAfter, MAX_FEE + FIXED_FEE, "LP fee not capped");
    }

    // Cross tick swap but deltaTick is smaller than 4055 ticks
    function test_crossTickSwap() public {
        int256 amountSpecified = -25e18;
        bool zeroForOne = false;
        (, int24 tickBefore,,) = manager.getSlot0(poolId);

        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        (, int24 tickAfter,,) = manager.getSlot0(poolId);

        // lp fee is updated once every 24hours
        vm.warp(block.timestamp + 25 hours);
        swap(key, zeroForOne, -10, ZERO_BYTES);

        (,,, uint24 lpFeeAfter) = manager.getSlot0(poolId);
        assertLt(tickAfter, tickBefore + 4055, "deltaTick must be smaller than 4055 ticks");
        assertGt(lpFeeAfter, FIXED_FEE, "LP fee not greater than FIXED_FEE");
        console.log("lpFeeAfter", lpFeeAfter);
    }

    function test_emitEvent() public {
        int256 amountSpecified = -25e18;
        bool zeroForOne = false;

        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        vm.expectEmit(true, true, false, false);
        emit VolatilityDynamicFeeHook.FeeUpdated(7611);

        // lp fee is updated once every 24hours
        vm.warp(block.timestamp + 25 hours);
        swap(key, zeroForOne, -10, ZERO_BYTES);
    }
}
