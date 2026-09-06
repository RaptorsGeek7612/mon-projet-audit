// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {SimpleAMM} from "../../src/SimpleAMM.sol";

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

    function check_SwapInvariant(uint256 amountIn) public {
        // Réserves initiales concrètes plutôt que symboliques : combiner une division
        // symbolique (amount1Out) avec une multiplication symbolique sur *trois* variables
        // libres est hors de portée du solveur SMT (timeout même à 300s, quelle que soit
        // la plage). Fixer les réserves ne garde qu'amountIn symbolique, ce qui suffit à
        // couvrir tous les montants de swap possibles pour ce point de départ.
        uint256 initRes0 = 10_000;
        uint256 initRes1 = 20_000;
        vm.assume(amountIn > 0 && amountIn < 100_000);

        // Injecter manuellement les réserves initiales symboliques
        // reserve0 -> slot 0, reserve1 -> slot 1 (token0/token1 sont immutable, donc
        // n'occupent aucun slot de storage : cf. `forge inspect SimpleAMM storage-layout`).
        vm.store(address(amm), bytes32(uint256(0)), bytes32(initRes0));
        vm.store(address(amm), bytes32(uint256(1)), bytes32(initRes1));

        uint256 kBefore = initRes0 * initRes1;

        // 2. Action symbolique
        try amm.swap0For1(amountIn, 0) returns (uint256) {
            // 3. Vérification de l'invariant
            uint256 kAfter = amm.reserve0() * amm.reserve1();
            assert(kAfter >= kBefore);
        } catch {
            // Si le require interne de l'AMM a bloqué le swap, le contrat a bien réagi
        }
    }
}
