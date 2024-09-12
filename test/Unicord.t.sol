// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {UnicordTestBase} from "@test/libraries/UnicordTestBase.sol";
import {ErrorsLib} from "@forks/morpho/libraries/ErrorsLib.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {Unicord} from "@src/Unicord.sol";
import {IUnicord} from "@src/interfaces/IUnicord.sol";

contract UnicordTest is UnicordTestBase {
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
        unicordId = hook.deposit(key, 1000 ether, 1000 * 1e18, alice.addr);
        assertEq(unicordId, 0);

        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqMorphoA(dDAImId, address(hook), 0, 0, amountToDep0);
        assertEqMorphoA(dUSDCmId, address(hook), 0, 0, amountToDep1);
    }

    function test_swap_price_up_in() public {
        uint256 usdcToSwap = 100 * 1e6;
        test_deposit();

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (uint256 deltaDAI, ) = swapUSDC_DAI_In(usdcToSwap);
        assertApproxEqAbs(deltaDAI, 100018384742682681812, 1e1);

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

    function test_swap_price_down_in() public {
        uint256 daiToSwap = 100 ether;
        test_deposit();

        deal(address(DAI), address(swapper.addr), daiToSwap);
        assertEqBalanceState(swapper.addr, daiToSwap, 0);

        (, uint256 deltaUSDC) = swapDAI_USDC_In(daiToSwap);
        assertApproxEqAbs(deltaUSDC, 99952317, 1e1);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(dDAImId, address(hook), 0, 0, amountToDep0 + daiToSwap);
        assertEqMorphoA(
            dUSDCmId,
            address(hook),
            0,
            0,
            amountToDep1 - deltaUSDC
        );
    }

    function test_swap_price_down_out() public {
        uint256 usdcToGetFSwap = 100 * 1e6;
        uint256 daiToSwapQ = 100018384742682681812;
        test_deposit();

        deal(address(DAI), address(swapper.addr), daiToSwapQ);
        assertEqBalanceState(swapper.addr, daiToSwapQ, 0);

        swapDAI_USDC_Out(usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, usdcToGetFSwap);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(
            dDAImId,
            address(hook),
            0,
            0,
            amountToDep0 + daiToSwapQ
        );
        assertEqMorphoA(
            dUSDCmId,
            address(hook),
            0,
            0,
            amountToDep1 - usdcToGetFSwap
        );
    }

    // -- Helpers --

    function init_hook() internal {
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo("Unicord.sol", abi.encode(manager), hookAddress);
        Unicord _hook = Unicord(hookAddress);

        uint160 initialSQRTPrice = 79215074834764545259897; // Tick: -276328

        (key, ) = initPool(
            Currency.wrap(address(DAI)),
            Currency.wrap(address(USDC)),
            _hook,
            500,
            initialSQRTPrice,
            ZERO_BYTES
        );

        hook = IUnicord(hookAddress);

        int24 deltaTick = 30;
        hook.setInitialPrise(
            key,
            initialSQRTPrice,
            -276328 - deltaTick,
            -276328 + deltaTick,
            dDAImId,
            dUSDCmId
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
