# YieldYoda

Maximizing Uniswap LP yields with Morpho lending protocols and Redstone oracles for improved capital and gas efficiency

## The problem it solves

YieldYoda improves Uniswap LP performance and enhances execution for traders. It lends idle funds through Morpho and uses Redstone's real-time price oracles to predict market movements. By withdrawing funds on-demand only when needed, it maximizes yields and cuts gas costs. The result: higher returns for LPs and optimal liquidity for trades.

## Challenges we ran into

It was so hard to do NoOp hooks, there are about 3 articles out there at most. Moreover, we need to do NoOp with a custom curve, even though it's similar to Uniswap, we still need to have a custom curve to get balances from Morpho. So it was like, let's create a Uniswap V3 in 2 days, but make it different;)

## Brief description on how your project fits into bounty track

YieldYoda optimizes Uniswap V4 liquidity provision by leveraging Morpho lending protocols and Redstone oracles:

The idea is that we can deposit and hold all of the LP funds into lending protocols and execute withdrawals only on-demand for traders swaps. While also, we use RedStone oracles to predict upcoming trade flow based on the underlying asset price action. Based on the prediction - it withdraws optimal amount of funds from Morpho to Uniswap Hook. This way, by withdrawing funds strategically, YieldYoda reduces the number of withdrawal transactions significantly enhancing gas-efficiency.

After trades executed, any excess liquidity is quickly redeposited into Morpho to ensure maximum capital efficiency, keeping funds earning yield when not needed for trades.

## Setting up

```
forge install
```

#### Testing

Test all project
```
make ta
```