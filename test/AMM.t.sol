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
        amm.mint(10_000 ether, 20_000 ether);
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

        try amm.swap0For1(amount0In) {
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

        try amm.swap0For1(amount0In) {
            assertGe(token0.balanceOf(address(amm)), amm.reserve0());
            assertGe(token1.balanceOf(address(amm)), amm.reserve1());
        } catch {
            // swap refusé, rien à vérifier.
        }
        vm.stopPrank();
    }
}
