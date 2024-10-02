# VolatilityDynamicFeeHook

## Overview
VolatilityDynamicFeeHook is a smart contract designed to work with Uniswap v4 as a hook. It implements a dynamic fee mechanism that adjusts based on the price volatility of the pool. This contract aims to optimize liquidity provision and trading by adapting fees to market conditions.

## How It Works

### Initialization:

When a pool is initialized, the contract sets a fixed base fee (0.3%) and records the timestamp.


### Dynamic Fee Calculation:

The contract tracks the minimum and maximum ticks observed during a 24-hour period.
Every 24 hours, it calculates a new fee based on the range of ticks observed:

The wider the range (higher volatility), the higher the fee, up to a maximum of 5%.
The fee is calculated as a proportion of the maximum tick range (4055 ticks which correspond to a 50% price change). Calculated fee is added on top of fixed fee (0.3%).


## Use Cases

1. Optimized Liquidity Provision

The dynamic fee structure encourages liquidity providers to maintain their positions even during volatile periods, ensuring deeper liquidity in the pool.

2. Volatility Protection

By increasing fees during high volatility periods, the hook helps counterbalance the risks of impermanent loss for liquidity providers.

3. Balanced Trading Environment

Higher fees during volatile periods can help reduce excessive speculation and promote more stable trading conditions.

## Further development/ improvements
1. Apply the higher fee only to higher risk token (eg. when volatile token is sold to pool);
2. Instead of updating the fee once every X hours, implement a 'moving window' technique to allow faster response to market conditions. 

## Set up

*requires [foundry](https://book.getfoundry.sh)*

```
forge install
forge test
```



Additional resources:

[Use this Template](https://github.com/uniswapfoundation/v4-template/generate)

[v4-periphery](https://github.com/uniswap/v4-periphery) contains advanced hook implementations that serve as a great reference

[v4-core](https://github.com/uniswap/v4-core)

[v4-by-example](https://v4-by-example.org)

