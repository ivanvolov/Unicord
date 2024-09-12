// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Id} from "@forks/morpho/IMorpho.sol";

interface IALM {
    error ZeroLiquidity();
    error AddLiquidityThroughHook();
    error NotHookDeployer();

    struct PlacedPositionInfo {
        uint128 liquidity;
        uint160 sqrtPrice;
        uint256 amount0;
        uint256 amount1;
        address owner;
    }

    struct PoolInfo {
        Id dToken0MId;
        Id dToken1MId;
        uint160 sqrtPriceCurrent;
        uint128 totalLiquidity;
        int24 tickUpper;
        int24 tickLower;
        uint256 positionIdCounter;
    }

    function deposit(
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        address to
    ) external returns (uint256 almId);

    function setInitialPrise(
        PoolKey calldata key,
        uint160 initialSQRTPrice,
        int24 tickUpper,
        int24 tickLower,
        Id dToken0MId,
        Id dToken1MId
    ) external;

    function getCurrentTick(PoolId poolId) external view returns (int24);

    function getPlacedPositionInfo(
        PoolId poolId,
        uint256 almId
    ) external view returns (PlacedPositionInfo memory);
}
