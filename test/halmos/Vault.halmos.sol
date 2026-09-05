// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Vault} from "../../src/Vault.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Tests d'exécution symbolique (halmos). Lancer avec: halmos --contract VaultHalmosTest
contract VaultHalmosTest is SymTest, Test {
    Vault vault;
    MockERC20 token;

    function setUp() public {
        token = new MockERC20();
        vault = _deployVault(token);
    }

    /// @dev `new Vault(...)` fait planter halmos (bug connu : résolution d'artefact
    /// incorrecte pour un contrat importé d'un autre fichier avec `immutable`).
    /// Contournement : déployer via vm.getCode + create bas niveau, que halmos gère
    /// correctement.
    function _deployVault(IERC20 asset) internal returns (Vault deployed) {
        bytes memory code = vm.getCode("Vault.sol:Vault");
        bytes memory initcode = abi.encodePacked(code, abi.encode(address(asset)));
        address addr;
        assembly {
            addr := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(addr != address(0), "Vault deploy failed");
        deployed = Vault(addr);
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
            // vm.expectRevert(string) isn't supported by halmos; use try/catch instead.
            try vault.withdraw(withdrawAmount) {
                assert(false);
            } catch {
                // expected: reverts on insufficient balance
            }
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
