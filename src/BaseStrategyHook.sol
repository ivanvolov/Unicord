// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {Position} from "v4-core/libraries/Position.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IMorpho, Id, Position as MorphoPosition} from "@forks/morpho/IMorpho.sol";
import {IALM} from "@src/interfaces/IALM.sol";
import {MorphoBalancesLib} from "@forks/morpho/libraries/MorphoBalancesLib.sol";

import {MainDemoConsumerBase} from "@redstone-finance/data-services/MainDemoConsumerBase.sol";

import {PRBMath} from "@src/libraries/math/PRBMath.sol";
import {CMathLib} from "@src/libraries/CMathLib.sol";
import {Id} from "@forks/morpho/IMorpho.sol";

abstract contract BaseStrategyHook is BaseHook, MainDemoConsumerBase, IALM {
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;

    mapping(PoolId => PoolInfo) poolsInfo;
    mapping(PoolId => mapping(uint256 => PlacedPositionInfo)) placedPositionsInfo;

    function setInitialPrise(
        PoolKey calldata key,
        uint160 initialSQRTPrice,
        int24 tickUpper,
        int24 tickLower,
        Id dToken0MId,
        Id dToken1MId
    ) external onlyHookDeployer {
        poolsInfo[key.toId()] = PoolInfo({
            dToken0MId: dToken0MId,
            dToken1MId: dToken1MId,
            sqrtPriceCurrent: initialSQRTPrice,
            totalLiquidity: 0,
            tickUpper: tickUpper,
            tickLower: tickLower,
            positionIdCounter: 0
        });
    }

    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    bytes internal constant ZERO_BYTES = bytes("");
    address public immutable hookDeployer;

    function getPlacedPositionInfo(
        PoolId poolId,
        uint256 almId
    ) external view override returns (PlacedPositionInfo memory) {
        return placedPositionsInfo[poolId][almId];
    }

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        hookDeployer = msg.sender;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function getCurrentTick(
        PoolId poolId
    ) public view override returns (int24) {
        return
            CMathLib.getTickFromSqrtPrice(poolsInfo[poolId].sqrtPriceCurrent);
    }

    // --- Morpho Wrappers ---
    function morphoWithdrawCollateral(
        Id morphoMarketId,
        uint256 amount
    ) internal {
        morpho.withdrawCollateral(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            address(this),
            address(this)
        );
    }

    function morphoSupplyCollateral(
        Id morphoMarketId,
        uint256 amount
    ) internal {
        morpho.supplyCollateral(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            address(this),
            ZERO_BYTES
        );
    }

    /// @dev Only the hook deployer may call this function
    modifier onlyHookDeployer() {
        if (msg.sender != hookDeployer) revert NotHookDeployer();
        _;
    }
}
