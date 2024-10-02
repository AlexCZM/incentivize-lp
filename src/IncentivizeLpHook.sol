// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, toBeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {BaseTestHooks} from "v4-core/src/test/BaseTestHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// Simple hook that modify LP fee if liquidity is below or above a hardcoded threshold
contract IncentivizeLpHook is BaseTestHooks {
    using Hooks for IHooks;
    using CurrencySettler for Currency;
    using StateLibrary for IPoolManager;

    uint24 constant  MAX_FEE = 50_000; // 5%
    uint24 constant  INITIAL_FEE = 3_000; // 0.3%
    IPoolManager immutable manager;

    int24 public minTick;
    int24 public maxTick;
    uint256 public lastUpdateTimestamp;



    

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(manager));
        _;
    }

    function afterInitialize(address, PoolKey calldata key, uint160, int24, bytes calldata)
        external
        override
        returns (bytes4)
    {   
        lastUpdateTimestamp = block.timestamp;
        // minTick = TickMath.maxUsableTick(key.tickSpacing);
        // maxTick = TickMath.minUsableTick(key.tickSpacing);
        manager.updateDynamicLPFee(key, INITIAL_FEE);
        return IHooks.afterInitialize.selector;
    }

    function beforeSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata, /* params**/
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(key.toId());
        if (tick < minTick) minTick = tick;
        if (tick > maxTick) maxTick = tick;

        if (lastUpdateTimestamp - block.timestamp > 24 hours) {
            int24 deltaTick = maxTick - minTick;
            manager.updateDynamicLPFee(key, INITIAL_FEE + _getFee(deltaTick));

            minTick = 0;
            maxTick = 0;
            lastUpdateTimestamp = block.timestamp;
           
        }
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _getFee(int24 currentTick) internal view returns (uint24 fee) {
        // linear interpolation for a delta tick up to 4055 (corresponding to a 50% price change)
        // todo: use safecast?
        fee = uint24(MAX_FEE * _getAbs(currentTick) / 4055);
    }

    function _getAbs(int24 tick) internal view returns (uint256 absTick) {
        // from v4-core/src/libraries/TickMath.getSqrtPriceAtTick()
        assembly ("memory-safe") {
            tick := signextend(2, tick)
            // mask = 0 if tick >= 0 else -1 (all 1s)
            let mask := sar(255, tick)
            // if tick >= 0, |tick| = tick = 0 ^ tick
            // if tick < 0, |tick| = ~~|tick| = ~(-|tick| - 1) = ~(tick - 1) = (-1) ^ (tick - 1)
            // either way, |tick| = mask ^ (tick + mask)
            absTick := xor(mask, add(mask, tick))
        }
    }
}