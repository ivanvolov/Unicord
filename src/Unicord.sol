// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

import {IERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {BaseStrategyHook} from "@src/BaseStrategyHook.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";
import {UnicordMathLib} from "@src/libraries/UnicordMathLib.sol";

/// @title Unicord
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract Unicord is BaseStrategyHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    constructor(IPoolManager manager) BaseStrategyHook(manager) {}

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24,
        bytes calldata
    ) external override returns (bytes4) {
        IERC20(Currency.unwrap(key.currency0)).approve(
            address(morpho),
            type(uint256).max
        );
        IERC20(Currency.unwrap(key.currency1)).approve(
            address(morpho),
            type(uint256).max
        );

        return Unicord.afterInitialize.selector;
    }

    /// @notice  Disable adding liquidity through the PM
    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function deposit(
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        address to
    ) external override returns (uint256) {
        console.log(">> deposit");

        uint128 liquidity = UnicordMathLib.getLiquidityFromAmountsSqrtPriceX96(
            poolsInfo[key.toId()].sqrtPriceCurrent,
            UnicordMathLib.getSqrtPriceAtTick(poolsInfo[key.toId()].tickUpper),
            UnicordMathLib.getSqrtPriceAtTick(poolsInfo[key.toId()].tickLower),
            amount0,
            amount1
        );

        poolsInfo[key.toId()].totalLiquidity += liquidity;

        (uint256 _amount0, uint256 _amount1) = UnicordMathLib
            .getAmountsFromLiquiditySqrtPriceX96(
                poolsInfo[key.toId()].sqrtPriceCurrent,
                UnicordMathLib.getSqrtPriceAtTick(
                    poolsInfo[key.toId()].tickUpper
                ),
                UnicordMathLib.getSqrtPriceAtTick(
                    poolsInfo[key.toId()].tickLower
                ),
                liquidity
            );

        if (liquidity == 0) revert ZeroLiquidity();
        console.log("_amount0", _amount0);
        console.log("_amount1", _amount1);
        IERC20(Currency.unwrap(key.currency0)).transferFrom(
            msg.sender,
            address(this),
            _amount0
        );
        IERC20(Currency.unwrap(key.currency1)).transferFrom(
            msg.sender,
            address(this),
            _amount1
        );

        morphoSupplyCollateral(
            poolsInfo[key.toId()].dToken0MId,
            IERC20(Currency.unwrap(key.currency0)).balanceOf(address(this))
        );
        morphoSupplyCollateral(
            poolsInfo[key.toId()].dToken1MId,
            IERC20(Currency.unwrap(key.currency1)).balanceOf(address(this))
        );

        placedPositionsInfo[key.toId()][
            poolsInfo[key.toId()].positionIdCounter
        ] = PlacedPositionInfo({
            liquidity: liquidity,
            sqrtPrice: poolsInfo[key.toId()].sqrtPriceCurrent,
            amount0: _amount0,
            amount1: _amount1,
            owner: to
        });

        poolsInfo[key.toId()].positionIdCounter++;
        return poolsInfo[key.toId()].positionIdCounter - 1;
    }

    // Swapping
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        (
            BeforeSwapDelta beforeSwapDelta,
            uint256 amountOut,
            uint256 amountIn,
            uint160 sqrtPriceNext
        ) = getSwapDeltas(
                key.toId(),
                params.amountSpecified,
                params.zeroForOne
            );

        _beforeSwap(key, params.zeroForOne, amountIn, amountOut);

        poolsInfo[key.toId()].sqrtPriceCurrent = sqrtPriceNext;
        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }

    //@Notice: This is to eliminate stack to deep
    function _beforeSwap(
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        if (zeroForOne) {
            console.log(">> USDC price go up...");
            console.log("> usdcOut", amountOut);
            console.log("> daiIn", amountIn);

            key.currency0.take(poolManager, address(this), amountIn, false);
            morphoSupplyCollateral(poolsInfo[key.toId()].dToken0MId, amountIn);
            redeemIfNotEnough(
                Currency.unwrap(key.currency1),
                amountOut,
                poolsInfo[key.toId()].dToken1MId
            );
            key.currency1.settle(poolManager, address(this), amountOut, false);
        } else {
            console.log(">> USDC price go down...");
            console.log("> usdcIn", amountIn);
            console.log("> daiOut", amountOut);

            key.currency1.take(poolManager, address(this), amountIn, false);
            morphoSupplyCollateral(poolsInfo[key.toId()].dToken1MId, amountIn);
            redeemIfNotEnough(
                Currency.unwrap(key.currency0),
                amountOut,
                poolsInfo[key.toId()].dToken0MId
            );
            key.currency0.settle(poolManager, address(this), amountOut, false);
        }
    }

    function getSwapDeltas(
        PoolId poolId,
        int256 amountSpecified,
        bool zeroForOne
    )
        internal
        view
        returns (
            BeforeSwapDelta beforeSwapDelta,
            uint256 amountOut,
            uint256 amountIn,
            uint160 sqrtPriceNextX96
        )
    {
        if (amountSpecified > 0) {
            console.log("> amount specified positive");
            amountOut = uint256(amountSpecified);

            if (zeroForOne) {
                (amountIn, , sqrtPriceNextX96) = UnicordMathLib
                    .getSwapAmountsFromAmount1(
                        poolsInfo[poolId].sqrtPriceCurrent,
                        poolsInfo[poolId].totalLiquidity,
                        amountOut
                    );
            } else {
                (, amountIn, sqrtPriceNextX96) = UnicordMathLib
                    .getSwapAmountsFromAmount0(
                        poolsInfo[poolId].sqrtPriceCurrent,
                        poolsInfo[poolId].totalLiquidity,
                        amountOut
                    );
            }

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(amountOut)), // specified token = token1/token0
                int128(uint128(amountIn)) // unspecified token = token0/token1
            );
        } else {
            console.log("> amount specified negative");
            amountIn = uint256(-amountSpecified);

            if (zeroForOne) {
                (, amountOut, sqrtPriceNextX96) = UnicordMathLib
                    .getSwapAmountsFromAmount0(
                        poolsInfo[poolId].sqrtPriceCurrent,
                        poolsInfo[poolId].totalLiquidity,
                        amountIn
                    );
            } else {
                (amountOut, , sqrtPriceNextX96) = UnicordMathLib
                    .getSwapAmountsFromAmount1(
                        poolsInfo[poolId].sqrtPriceCurrent,
                        poolsInfo[poolId].totalLiquidity,
                        amountIn
                    );
            }

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(amountIn)), // specified token = token0/token1
                -int128(uint128(amountOut)) // unspecified token = token1/token0
            );
        }
    }

    function redeemIfNotEnough(address token, uint256 amount, Id id) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) {
            morphoWithdrawCollateral(id, amount - balance);
        }
    }
}
