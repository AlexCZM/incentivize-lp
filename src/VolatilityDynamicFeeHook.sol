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

/// Dynamic fee hook driven by volatility over X period
contract VolatilityDynamicFeeHook is BaseTestHooks {
    using Hooks for IHooks;
    using CurrencySettler for Currency;
    using StateLibrary for IPoolManager;

    uint24 constant MAX_FEE = 50_000; // 5%
    uint24 constant FIXED_FEE = 3_000; // 0.3%
    uint256 constant UPDATE_FEE_PERIOD = 24 hours;
    // 1.0001 ^ 4055 ~= 1.5
    // meaning that the price of one token increased by 50% against the other token
    uint256 constant MAX_TICK_DELTA = 4055; 
    IPoolManager immutable manager;

    int24 public minTick;
    int24 public maxTick;
    uint40 public lastUpdateTimestamp;

    event FeeUpdated(uint24 indexed newDynamicLPFee);

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
        lastUpdateTimestamp = uint40(block.timestamp);
        manager.updateDynamicLPFee(key, FIXED_FEE);
        return IHooks.afterInitialize.selector;
    }

    function beforeSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata, /* params**/
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        (, int24 tick,,) = manager.getSlot0(key.toId());
        if (tick < minTick) minTick = tick;
        if (tick > maxTick) maxTick = tick;

        if (block.timestamp - lastUpdateTimestamp > UPDATE_FEE_PERIOD) {
            int24 deltaTick = maxTick - minTick;
            uint24 newDynamicLPFee = FIXED_FEE + _getFee(deltaTick);
            manager.updateDynamicLPFee(key, newDynamicLPFee);
            emit FeeUpdated(newDynamicLPFee);

            minTick = 0;
            maxTick = 0;
            lastUpdateTimestamp = uint40(block.timestamp);
        }
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _getFee(int24 tickDelta) internal pure returns (uint24 fee) {
        uint256 absTick = _getAbs(tickDelta);
        // ensure fee is not greater than MAX_FEE when tick moves by more than MAX_TICK_DELTA ticks
        if (absTick >= MAX_TICK_DELTA) return MAX_FEE;
        fee = uint24(MAX_FEE * absTick / MAX_TICK_DELTA);
    }

    function _getAbs(int24 tick) internal pure returns (uint256 absTick) {
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
