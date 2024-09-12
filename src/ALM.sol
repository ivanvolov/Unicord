// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {Id} from "@forks/morpho/IMorpho.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

import {IERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {BaseStrategyHook} from "@src/BaseStrategyHook.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";
import {CMathLib} from "@src/libraries/CMathLib.sol";

/// @title ALM
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALM is BaseStrategyHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    constructor(
        IPoolManager manager,
        Id _dDAImId,
        Id _dUSDCmId
    ) BaseStrategyHook(manager) {
        dDAImId = _dDAImId;
        dUSDCmId = _dUSDCmId;
    }

    function afterInitialize(
        address,
        PoolKey calldata,
        uint160,
        int24,
        bytes calldata
    ) external override returns (bytes4) {
        DAI.approve(address(morpho), type(uint256).max);
        USDC.approve(address(morpho), type(uint256).max);

        return ALM.afterInitialize.selector;
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
        PoolKey calldata,
        uint256 amount0,
        uint256 amount1,
        address to
    ) external override returns (uint256) {
        console.log(">> deposit");

        uint128 liquidity = CMathLib.getLiquidityFromAmountsSqrtPriceX96(
            sqrtPriceCurrent,
            CMathLib.getSqrtPriceAtTick(tickUpper),
            CMathLib.getSqrtPriceAtTick(tickLower),
            amount0,
            amount1
        );

        totalLiquidity += liquidity;

        (uint256 _amount0, uint256 _amount1) = CMathLib
            .getAmountsFromLiquiditySqrtPriceX96(
                sqrtPriceCurrent,
                CMathLib.getSqrtPriceAtTick(tickUpper),
                CMathLib.getSqrtPriceAtTick(tickLower),
                liquidity
            );

        if (liquidity == 0) revert ZeroLiquidity();
        console.log("_amount0", _amount0);
        console.log("_amount1", _amount1);
        DAI.transferFrom(msg.sender, address(this), _amount0);
        USDC.transferFrom(msg.sender, address(this), _amount1);

        morphoSupplyCollateral(dDAImId, DAI.balanceOf(address(this)));
        morphoSupplyCollateral(dUSDCmId, USDC.balanceOf(address(this)));

        almInfo[almIdCounter] = ALMInfo({
            liquidity: liquidity,
            sqrtPrice: sqrtPriceCurrent,
            amount0: _amount0,
            amount1: _amount1,
            owner: to
        });

        almIdCounter++;
        return almIdCounter - 1;
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
        ) = getSwapDeltas(params.amountSpecified, params.zeroForOne);

        if (params.zeroForOne) {
            console.log(">> USDC price go up...");
            console.log("> usdcOut", amountOut);
            console.log("> daiIn", amountIn);

            key.currency0.take(poolManager, address(this), amountIn, false);
            morphoSupplyCollateral(dDAImId, amountIn);
            redeemIfNotEnough(address(USDC), amountOut, dUSDCmId);
            key.currency1.settle(poolManager, address(this), amountOut, false);
        } else {
            console.log(">> USDC price go down...");
            console.log("> usdcIn", amountIn);
            console.log("> daiOut", amountOut);

            key.currency1.take(poolManager, address(this), amountIn, false);
            morphoSupplyCollateral(dUSDCmId, amountIn);
            redeemIfNotEnough(address(DAI), amountOut, dDAImId);
            key.currency0.settle(poolManager, address(this), amountOut, false);
        }

        sqrtPriceCurrent = sqrtPriceNext;
        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }

    function getSwapDeltas(
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
                (amountIn, , sqrtPriceNextX96) = CMathLib
                    .getSwapAmountsFromAmount1(
                        sqrtPriceCurrent,
                        totalLiquidity,
                        amountOut
                    );
            } else {
                (, amountIn, sqrtPriceNextX96) = CMathLib
                    .getSwapAmountsFromAmount0(
                        sqrtPriceCurrent,
                        totalLiquidity,
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
                (, amountOut, sqrtPriceNextX96) = CMathLib
                    .getSwapAmountsFromAmount0(
                        sqrtPriceCurrent,
                        totalLiquidity,
                        amountIn
                    );
            } else {
                (amountOut, , sqrtPriceNextX96) = CMathLib
                    .getSwapAmountsFromAmount1(
                        sqrtPriceCurrent,
                        totalLiquidity,
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
