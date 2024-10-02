// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
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

/// Simple hook that modify LP fee if liquidity is below or above a hardcoded threshold
contract IncentivizeLpHook is BaseTestHooks {
    using Hooks for IHooks;
    using CurrencySettler for Currency;

    IPoolManager immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(manager));
        _;
    }
    
    // function getHookPermissions() public pure returns (Hooks.Permissions memory) {
    //     return Hooks.Permissions({
    //         beforeInitialize: false,
    //         afterInitialize: false,
    //         beforeAddLiquidity: false,
    //         afterAddLiquidity: false,
    //         beforeRemoveLiquidity: false,
    //         afterRemoveLiquidity: false,
    //         beforeSwap: true,
    //         afterSwap: false,
    //         beforeDonate: false,
    //         afterDonate: false,
    //         beforeSwapReturnDelta: false,
    //         afterSwapReturnDelta: false,
    //         afterAddLiquidityReturnDelta: false,
    //         afterRemoveLiquidityReturnDelta: false
    //     });
    // }

    function afterInitialize(address, PoolKey calldata key, uint160, int24, bytes calldata)
        external
        override
        returns (bytes4)
    {
        manager.updateDynamicLPFee(key, 300);
        return IHooks.afterInitialize.selector;
    }

    function beforeSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata, /* params**/
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
         // update fee
        uint24 fee = 1000;
        manager.updateDynamicLPFee(key, fee);
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        //return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }
}