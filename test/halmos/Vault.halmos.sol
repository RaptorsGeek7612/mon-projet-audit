// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Vault} from "../../src/Vault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Tests d'exécution symbolique (halmos). Lancer avec: halmos --contract VaultHalmosTest
contract VaultHalmosTest is SymTest, Test {
    Vault vault;
    MockERC20 token;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
    }

    /// @dev Un retrait ne peut jamais dépasser ce que l'utilisateur a réellement déposé.
    function check_withdrawNeverExceedsDeposit(address user, uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(user != address(0));
        depositAmount = bound(depositAmount, 1, type(uint128).max);

        token.mint(user, depositAmount);

        vm.prank(user);
        token.approve(address(vault), depositAmount);

        vm.prank(user);
        vault.deposit(depositAmount);

        vm.prank(user);
        if (withdrawAmount > depositAmount) {
            vm.expectRevert("Vault: insufficient balance");
            vault.withdraw(withdrawAmount);
        } else {
            vault.withdraw(withdrawAmount);
            assert(vault.balanceOf(user) == depositAmount - withdrawAmount);
        }
    }

    /// @dev Quelle que soit la séquence dépôt/retrait, le coffre reste solvable.
    function check_solvencyAfterArbitraryDepositWithdraw(address user, uint256 depositAmount, uint256 withdrawAmount)
        public
    {
        vm.assume(user != address(0));
        depositAmount = bound(depositAmount, 0, type(uint128).max);
        token.mint(user, depositAmount);

        vm.startPrank(user);
        token.approve(address(vault), depositAmount);
        if (depositAmount > 0) vault.deposit(depositAmount);

        withdrawAmount = bound(withdrawAmount, 0, vault.balanceOf(user));
        vault.withdraw(withdrawAmount);
        vm.stopPrank();

        assert(token.balanceOf(address(vault)) >= vault.totalSupply());
    }
}
