// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "./interfaces/IERC20.sol";

contract SimpleAMM {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    // Ajout rudimentaire de liquidité pour notre test
    function mint(uint256 amount0, uint256 amount1) external {
        // Effects before interactions.
        reserve0 += amount0;
        reserve1 += amount1;

        require(token0.transferFrom(msg.sender, address(this), amount0), "Transfert token0 echoue");
        require(token1.transferFrom(msg.sender, address(this), amount1), "Transfert token1 echoue");
    }

    // Fonction de Swap (Échange de Token0 contre Token1)
    function swap0For1(uint256 amount0In) external returns (uint256 amount1Out) {
        require(amount0In > 0, "Montant invalide");

        // Calcul mathématique basé sur x * y = k
        // amount1Out = (reserve1 * amount0In) / (reserve0 + amount0In)
        uint256 numerator = reserve1 * amount0In;
        uint256 denominator = reserve0 + amount0In;
        amount1Out = numerator / denominator;

        require(amount1Out < reserve1, "Liquidite insuffisante");

        // Effects before interactions.
        reserve0 += amount0In;
        reserve1 -= amount1Out;

        require(token0.transferFrom(msg.sender, address(this), amount0In), "Transfert token0 echoue");
        require(token1.transfer(msg.sender, amount1Out), "Transfert token1 echoue");
    }
}
