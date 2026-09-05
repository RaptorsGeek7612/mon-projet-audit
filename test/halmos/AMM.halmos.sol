// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {SimpleAMM} from "../../src/SimpleAMM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Contrats Mock pour simuler les Tokens sous forme symbolique
contract MockToken {
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }
}

contract AMMHalmosTest is Test {
    SimpleAMM amm;
    address mock0 = address(new MockToken());
    address mock1 = address(new MockToken());

    function setUp() public {
        amm = _deploySimpleAMM(mock0, mock1);
    }

    /// @dev `new SimpleAMM(...)` fait planter halmos (bug connu : résolution d'artefact
    /// incorrecte pour un contrat importé d'un autre fichier avec `immutable`).
    /// Contournement : déployer via vm.getCode + create bas niveau, que halmos gère
    /// correctement.
    function _deploySimpleAMM(address token0, address token1) internal returns (SimpleAMM deployed) {
        bytes memory code = vm.getCode("SimpleAMM.sol:SimpleAMM");
        bytes memory initcode = abi.encodePacked(code, abi.encode(token0, token1));
        address addr;
        assembly {
            addr := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(addr != address(0), "SimpleAMM deploy failed");
        deployed = SimpleAMM(addr);
    }

    function check_SwapInvariant(uint256 initRes0, uint256 initRes1, uint256 amountIn) public {
        // 1. Hypothèses réalistes pour le solveur (éviter overflows et divisions par 0).
        // Plages volontairement modestes : la propriété est invariante d'échelle, et des
        // valeurs de l'ordre de "ether" (1e18+) font exploser le temps de résolution SMT
        // (multiplication/division non linéaires) au-delà du timeout par défaut de halmos.
        vm.assume(initRes0 > 1000 && initRes1 > 1000);
        vm.assume(initRes0 < 1_000_000 && initRes1 < 1_000_000);
        vm.assume(amountIn > 0 && amountIn < 100_000);

        // Injecter manuellement les réserves initiales symboliques
        // reserve0 -> slot 0, reserve1 -> slot 1 (token0/token1 sont immutable, donc
        // n'occupent aucun slot de storage : cf. `forge inspect SimpleAMM storage-layout`).
        vm.store(address(amm), bytes32(uint256(0)), bytes32(initRes0));
        vm.store(address(amm), bytes32(uint256(1)), bytes32(initRes1));

        uint256 kBefore = initRes0 * initRes1;

        // 2. Action symbolique
        try amm.swap0For1(amountIn) returns (uint256) {
            // 3. Vérification de l'invariant
            uint256 kAfter = amm.reserve0() * amm.reserve1();
            assert(kAfter >= kBefore);
        } catch {
            // Si le require interne de l'AMM a bloqué le swap, le contrat a bien réagi
        }
    }
}
