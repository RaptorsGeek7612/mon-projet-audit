// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract VaultTest is Test {
    Vault vault;
    MockERC20 token;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);

        token.mint(alice, 1_000 ether);
        token.mint(bob, 1_000 ether);

        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    function test_deposit_creditsBalanceAndPullsTokens() public {
        vm.prank(alice);
        vault.deposit(100 ether);

        assertEq(vault.balanceOf(alice), 100 ether);
        assertEq(vault.totalSupply(), 100 ether);
        assertEq(token.balanceOf(address(vault)), 100 ether);
        assertEq(token.balanceOf(alice), 900 ether);
    }

    function test_withdraw_debitsBalanceAndReturnsTokens() public {
        vm.startPrank(alice);
        vault.deposit(100 ether);
        vault.withdraw(40 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 60 ether);
        assertEq(vault.totalSupply(), 60 ether);
        assertEq(token.balanceOf(alice), 940 ether);
    }

    function test_withdraw_revertsWhenInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert("Vault: insufficient balance");
        vault.withdraw(1 ether);
    }

    function test_deposit_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("Vault: zero amount");
        vault.deposit(0);
    }

    function test_usersCannotWithdrawEachOthersFunds() public {
        vm.prank(alice);
        vault.deposit(100 ether);

        vm.prank(bob);
        vm.expectRevert("Vault: insufficient balance");
        vault.withdraw(1 ether);
    }

    /// @dev Invariant clé : la comptabilité interne ne dépasse jamais les actifs réellement détenus.
    function testFuzz_depositThenWithdraw_neverInsolvent(uint96 depositAmount, uint96 withdrawAmount) public {
        depositAmount = uint96(bound(depositAmount, 1, 1_000 ether));
        vm.prank(alice);
        vault.deposit(depositAmount);

        withdrawAmount = uint96(bound(withdrawAmount, 1, depositAmount));
        vm.prank(alice);
        vault.withdraw(withdrawAmount);

        assertEq(vault.balanceOf(alice), depositAmount - withdrawAmount);
        assertGe(token.balanceOf(address(vault)), vault.totalSupply());
    }

    function invariant_solvency() public view {
        assertGe(token.balanceOf(address(vault)), vault.totalSupply());
    }
}
