// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AMMTest is Test {
    SimpleAMM amm;
    MockERC20 token0;
    MockERC20 token1;

    address lp = makeAddr("lp");
    address trader = makeAddr("trader");

    function setUp() public {
        token0 = new MockERC20();
        token1 = new MockERC20();
        amm = new SimpleAMM(address(token0), address(token1));

        token0.mint(lp, 1_000_000 ether);
        token1.mint(lp, 1_000_000 ether);
        vm.startPrank(lp);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
        amm.mint(10_000 ether, 20_000 ether, 0);
        vm.stopPrank();
    }

    function test_mint_creditsLiquidityMinusMinimumLock() public view {
        uint256 expected = 10_000 ether * 20_000 ether - amm.MINIMUM_LIQUIDITY();
        assertEq(amm.liquidityOf(lp), expected);
        assertEq(amm.totalLiquidity(), expected + amm.MINIMUM_LIQUIDITY());
        assertEq(amm.liquidityOf(address(0)), amm.MINIMUM_LIQUIDITY());
    }

    function test_mint_revertsOnSlippage() public {
        token0.mint(trader, 100 ether);
        token1.mint(trader, 200 ether);
        vm.startPrank(trader);
        token0.approve(address(amm), 100 ether);
        token1.approve(address(amm), 200 ether);
        vm.expectRevert("SimpleAMM: slippage");
        amm.mint(100 ether, 200 ether, type(uint256).max);
        vm.stopPrank();
    }

    function test_burn_returnsProportionalShareAndBurnsLiquidity() public {
        vm.startPrank(lp);
        uint256 liquidity = amm.liquidityOf(lp);
        (uint256 amount0, uint256 amount1) = amm.burn(liquidity, 0, 0);
        vm.stopPrank();

        assertEq(amm.liquidityOf(lp), 0);
        assertApproxEqAbs(amount0, 10_000 ether, 1e6);
        assertApproxEqAbs(amount1, 20_000 ether, 1e6);
        assertEq(token0.balanceOf(lp), 1_000_000 ether - 10_000 ether + amount0);
    }

    function test_burn_revertsOnSlippage() public {
        vm.startPrank(lp);
        uint256 liquidity = amm.liquidityOf(lp);
        vm.expectRevert("SimpleAMM: slippage");
        amm.burn(liquidity, type(uint256).max, 0);
        vm.stopPrank();
    }

    function test_burn_revertsIfMoreThanOwnedLiquidity() public {
        vm.prank(trader);
        vm.expectRevert("SimpleAMM: insufficient liquidity");
        amm.burn(1, 0, 0);
    }

    function test_swap_revertsOnSlippage() public {
        token0.mint(trader, 100 ether);
        vm.startPrank(trader);
        token0.approve(address(amm), 100 ether);
        vm.expectRevert("SimpleAMM: slippage");
        amm.swap0For1(100 ether, type(uint256).max);
        vm.stopPrank();
    }

    /// @dev L'invariant du produit constant x*y=k ne peut jamais baisser après un swap
    /// (arrondi de la division vers le bas systématiquement en faveur du pool).
    function testFuzz_swapNeverDecreasesConstantProduct(uint256 amount0In) public {
        amount0In = bound(amount0In, 1, 1_000_000 ether);

        token0.mint(trader, amount0In);
        vm.startPrank(trader);
        token0.approve(address(amm), amount0In);

        uint256 kBefore = amm.reserve0() * amm.reserve1();

        try amm.swap0For1(amount0In, 0) {
            uint256 kAfter = amm.reserve0() * amm.reserve1();
            assertGe(kAfter, kBefore);
        } catch {
            // "Liquidite insuffisante" pour ce montant : rien à vérifier.
        }
        vm.stopPrank();
    }

    /// @dev Les réserves internes reflètent toujours les soldes réels détenus par le pool.
    function testFuzz_reservesNeverExceedRealBalances(uint256 amount0In) public {
        amount0In = bound(amount0In, 1, 1_000_000 ether);

        token0.mint(trader, amount0In);
        vm.startPrank(trader);
        token0.approve(address(amm), amount0In);

        try amm.swap0For1(amount0In, 0) {
            assertGe(token0.balanceOf(address(amm)), amm.reserve0());
            assertGe(token1.balanceOf(address(amm)), amm.reserve1());
        } catch {
            // swap refusé, rien à vérifier.
        }
        vm.stopPrank();
    }

    /// @dev Deposer puis retirer toute sa liquidite ne peut jamais rendre plus que ce qui a ete
    /// deposer, ni laisser le pool en insolvabilite vis-a-vis de ses soldes reels.
    function testFuzz_mintThenBurn_neverExceedsPoolBalance(uint96 amount0, uint96 amount1) public {
        amount0 = uint96(bound(amount0, 1e6, 1_000_000 ether));
        amount1 = uint96(bound(amount1, 1e6, 1_000_000 ether));

        token0.mint(trader, amount0);
        token1.mint(trader, amount1);
        vm.startPrank(trader);
        token0.approve(address(amm), amount0);
        token1.approve(address(amm), amount1);

        uint256 liquidity = amm.mint(amount0, amount1, 0);
        (uint256 out0, uint256 out1) = amm.burn(liquidity, 0, 0);
        vm.stopPrank();

        assertLe(out0, amount0);
        assertLe(out1, amount1);
        assertGe(token0.balanceOf(address(amm)), amm.reserve0());
        assertGe(token1.balanceOf(address(amm)), amm.reserve1());
    }
}
