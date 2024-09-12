// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {MarketParamsLib} from "@forks/morpho/libraries/MarketParamsLib.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IChainlinkOracle} from "@forks/morpho-oracles/IChainlinkOracle.sol";
import {IMorpho, MarketParams, Position as MorphoPosition, Id} from "@forks/morpho/IMorpho.sol";
import {IUnicord} from "@src/interfaces/IUnicord.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {TestERC20} from "v4-core/test/TestERC20.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {MorphoBalancesLib} from "@forks/morpho/libraries/MorphoBalancesLib.sol";

abstract contract UnicordTestBase is Test, Deployers {
    using TestAccountLib for TestAccount;

    IUnicord hook;

    TestERC20 USDC;
    TestERC20 DAI;

    TestAccount marketCreator;
    TestAccount morphoLpProvider;
    TestAccount alice;
    TestAccount swapper;

    Id dDAImId;
    Id dUSDCmId;
    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    uint256 unicordId;

    function labelTokens() public {
        DAI = TestERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        vm.label(address(DAI), "DAI");
        USDC = TestERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        vm.label(address(USDC), "USDC");
        marketCreator = TestAccountLib.createTestAccount("marketCreator");
        morphoLpProvider = TestAccountLib.createTestAccount("morphoLpProvider");
    }

    function create_and_approve_accounts() public {
        alice = TestAccountLib.createTestAccount("alice");
        swapper = TestAccountLib.createTestAccount("swapper");

        vm.startPrank(alice.addr);
        USDC.approve(address(hook), type(uint256).max);
        DAI.approve(address(hook), type(uint256).max);

        USDC.approve(address(morpho), type(uint256).max);
        DAI.approve(address(morpho), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper.addr);
        USDC.approve(address(swapRouter), type(uint256).max);
        DAI.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    // -- Uniswap V4 -- //

    function swapDAI_USDC_Out(
        uint256 amount
    ) public returns (uint256, uint256) {
        return swap(true, int256(amount));
    }

    function swapDAI_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return swap(true, -int256(amount));
    }

    function swapUSDC_DAI_Out(
        uint256 amount
    ) public returns (uint256, uint256) {
        return swap(false, int256(amount));
    }

    function swapUSDC_DAI_In(uint256 amount) public returns (uint256, uint256) {
        return swap(false, -int256(amount));
    }

    function swap(
        bool zeroForOne,
        int256 amount
    ) internal returns (uint256, uint256) {
        vm.prank(swapper.addr);
        BalanceDelta delta = swapRouter.swap(
            key,
            IPoolManager.SwapParams(
                zeroForOne,
                amount,
                zeroForOne == true
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            ),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
        return (
            uint256(int256(delta.amount0())),
            uint256(int256(delta.amount1()))
        );
    }

    // -- Morpho -- //

    function create_morpho_market(
        address loanToken,
        address collateralToken,
        uint256 lltv,
        address oracle
    ) internal returns (Id) {
        MarketParams memory marketParams = MarketParams(
            loanToken,
            collateralToken,
            oracle,
            0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC, // We have only 1 irm in morpho so we can use this address
            lltv
        );

        vm.prank(marketCreator.addr);
        morpho.createMarket(marketParams);
        return MarketParamsLib.id(marketParams);
    }

    function modifyMockOracle(
        address oracle,
        uint256 newPrice
    ) internal returns (IChainlinkOracle iface) {
        //NOTICE: https://github.com/morpho-org/morpho-blue-oracles
        iface = IChainlinkOracle(oracle);

        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(iface.price.selector),
            abi.encode(newPrice)
        );

        console.log("> vault", address(iface.VAULT()));
        console.log("> conversionSample", iface.VAULT_CONVERSION_SAMPLE());
        console.log("> baseFeed1", address(iface.BASE_FEED_1()));
        console.log("> baseFeed2", address(iface.BASE_FEED_2()));
        console.log("> quoteFeed1", address(iface.QUOTE_FEED_1()));
        console.log("> quoteFeed2", address(iface.QUOTE_FEED_2()));
        console.log("> scaleFactor", iface.SCALE_FACTOR());
        return iface;
    }

    function provideLiquidityToMorpho(Id marketId, uint256 amount) internal {
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);
        console.log(">>", marketParams.loanToken);

        vm.startPrank(morphoLpProvider.addr);
        deal(marketParams.loanToken, morphoLpProvider.addr, amount);

        TestERC20(marketParams.loanToken).approve(
            address(morpho),
            type(uint256).max
        );
        (, uint256 shares) = morpho.supply(
            marketParams,
            amount,
            0,
            morphoLpProvider.addr,
            ""
        );

        assertEqMorphoState(marketId, morphoLpProvider.addr, shares, 0, 0);
        assertEqBalanceStateZero(morphoLpProvider.addr);
        vm.stopPrank();
    }

    // -- Custom assertions -- //

    function assertEqMorphoState(
        Id marketId,
        address owner,
        uint256 _supplyShares,
        uint256 _borrowShares,
        uint256 _collateral
    ) public view {
        MorphoPosition memory p;
        p = morpho.position(marketId, owner);
        assertApproxEqAbs(
            p.supplyShares,
            _supplyShares,
            10,
            "supply shares not equal"
        );
        assertApproxEqAbs(
            p.borrowShares,
            _borrowShares,
            10,
            "borrow shares not equal"
        );
        assertApproxEqAbs(
            p.collateral,
            _collateral,
            10000,
            "collateral not equal"
        );
    }

    function assertEqMorphoA(
        Id marketId,
        address owner,
        uint256 _supplyAssets,
        uint256 _borrowAssets,
        uint256 _collateral
    ) public view {
        MorphoPosition memory p;
        p = morpho.position(marketId, owner);

        assertApproxEqAbs(
            MorphoBalancesLib.expectedSupplyAssets(
                morpho,
                morpho.idToMarketParams(marketId),
                owner
            ),
            _supplyAssets,
            10,
            "supply assets not equal"
        );
        assertApproxEqAbs(
            MorphoBalancesLib.expectedBorrowAssets(
                morpho,
                morpho.idToMarketParams(marketId),
                owner
            ),
            _borrowAssets,
            10,
            "borrow assets not equal"
        );
        assertApproxEqAbs(
            p.collateral,
            _collateral,
            10000,
            "collateral not equal"
        );
    }

    function assertEqBalanceStateZero(address owner) public view {
        assertEqBalanceState(owner, 0, 0, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceDAI,
        uint256 _balanceUSDC
    ) public view {
        assertEqBalanceState(owner, _balanceDAI, _balanceUSDC, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceDAI,
        uint256 _balanceUSDC,
        uint256 _balanceETH
    ) public view {
        assertApproxEqAbs(
            DAI.balanceOf(owner),
            _balanceDAI,
            10,
            "Balance DAI not equal"
        );
        assertApproxEqAbs(
            USDC.balanceOf(owner),
            _balanceUSDC,
            10,
            "Balance USDC not equal"
        );
        assertApproxEqAbs(
            owner.balance,
            _balanceETH,
            10,
            "Balance ETH not equal"
        );
    }
}
