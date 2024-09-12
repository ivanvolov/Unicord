// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

interface IALM {
    error ZeroLiquidity();

    error AddLiquidityThroughHook();

    error InRange();

    error NotAnALMOwner();

    error NoSwapWillOccur();

    struct ALMInfo {
        uint128 liquidity;
        uint160 sqrtPrice;
        uint256 amount0;
        uint256 amount1;
        address owner;
    }

    function deposit(
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        address to
    ) external returns (uint256 almId);

    function setInitialPrise(
        uint160 initialSQRTPrice,
        int24 _tickUpper,
        int24 _tickLower
    ) external;

    function getCurrentTick(PoolId poolId) external view returns (int24);

    function getALMInfo(uint256 almId) external view returns (ALMInfo memory);
}
