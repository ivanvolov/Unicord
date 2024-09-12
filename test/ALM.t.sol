// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {ALMTestBase} from "@test/libraries/ALMTestBase.sol";
import {ErrorsLib} from "@forks/morpho/libraries/ErrorsLib.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {ALM} from "@src/ALM.sol";
import {IALM} from "@src/interfaces/IALM.sol";

contract ALMTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(20_734_421);

        deployFreshManagerAndRouters();

        labelTokens();
        create_and_seed_morpho_markets();
        init_hook();
        create_and_approve_accounts();
    }

    uint256 amountToDep0 = 999999999999999994151; //DAI
    uint256 amountToDep1 = 1045259706; //USDC

    function test_deposit() public {
        deal(address(DAI), address(alice.addr), amountToDep0);
        deal(address(USDC), address(alice.addr), amountToDep1);
        vm.prank(alice.addr);
        almId = hook.deposit(key, 1000 ether, 1000 * 1e18, alice.addr);
        assertEq(almId, 0);

        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqMorphoA(dDAImId, address(hook), 0, 0, amountToDep0);
        assertEqMorphoA(dUSDCmId, address(hook), 0, 0, amountToDep1);
    }

    function test_swap_price_up_in() public {
        uint256 usdcToSwap = 1000 * 1e6;
        test_deposit();

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (uint256 deltaDAI, ) = swapUSDC_DAI_In(usdcToSwap);
        assertApproxEqAbs(deltaDAI, 998866253455794652571, 1e1);

        assertEqBalanceState(swapper.addr, deltaDAI, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(dDAImId, address(hook), 0, 0, amountToDep0 - deltaDAI);
        assertEqMorphoA(
            dUSDCmId,
            address(hook),
            0,
            0,
            amountToDep1 + usdcToSwap
        );
    }

    function test_swap_price_up_out() public {
        uint256 usdcToSwapQ = 99952317;
        uint256 daiToGetFSwap = 100 ether;
        test_deposit();

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        swapUSDC_DAI_Out(daiToGetFSwap);

        assertEqBalanceState(swapper.addr, daiToGetFSwap, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(
            dDAImId,
            address(hook),
            0,
            0,
            amountToDep0 - daiToGetFSwap
        );
        assertEqMorphoA(
            dUSDCmId,
            address(hook),
            0,
            0,
            amountToDep1 + usdcToSwapQ
        );
    }

    // function test_swap_price_down() public {
    //     uint256 daiToSwap = 1 ether / 5;
    //     test_deposit();

    //     deal(address(DAI), address(swapper.addr), daiToSwap);
    //     assertEqBalanceState(swapper.addr, daiToSwap, 0);

    //     (uint256 deltaUSDC, ) = swapDAI_USDC_In(daiToSwap);
    //     assertEq(deltaUSDC, 887490956);

    //     assertEqBalanceState(swapper.addr, 0, deltaUSDC);
    //     assertEqBalanceState(address(hook), 0, 0);
    // }

    // -- Helpers --

    function init_hook() internal {
        router = new HookEnabledSwapRouter(manager);

        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo(
            "ALM.sol",
            abi.encode(manager, dDAImId, dUSDCmId),
            hookAddress
        );
        ALM _hook = ALM(hookAddress);

        uint160 initialSQRTPrice = 79215074834764545259897; // Tick: -276328

        (key, ) = initPool(
            Currency.wrap(address(DAI)),
            Currency.wrap(address(USDC)),
            _hook,
            500,
            initialSQRTPrice,
            ZERO_BYTES
        );

        hook = IALM(hookAddress);

        int24 deltaTick = 30;
        hook.setInitialPrise(
            initialSQRTPrice,
            -276328 - deltaTick,
            -276328 + deltaTick
        );

        // This is needed in order to simulate proper accounting
        deal(address(USDC), address(manager), 10000 * 1e6);
        deal(address(DAI), address(manager), 10000 ether);
    }

    function create_and_seed_morpho_markets() internal {
        address oracle = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;

        modifyMockOracle(oracle, 1851340816804029821232973); //1 usdc for dai

        dDAImId = create_morpho_market(
            address(USDC),
            address(DAI),
            915000000000000000,
            oracle
        );

        dUSDCmId = create_morpho_market(
            address(DAI),
            address(USDC),
            915000000000000000,
            oracle
        );

        // We won't provide liquidity cause we will not borrow it from HERE. This market is only for interest mining.
    }
}
