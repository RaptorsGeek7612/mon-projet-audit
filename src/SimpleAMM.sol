// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "./interfaces/IERC20.sol";

/// @notice AMM a produit constant (x*y=k) a deux jetons, avec parts de liquidite et retrait.
///
/// Bootstrap de la premiere liquidite via `amount0 * amount1` (pas de sqrt) : contrairement au
/// modele Uniswap V2, cela garde tout le contrat exempt de boucle, donc entierement prouvable
/// par Certora sans recourir a `optimistic_loop`. La proportionnalite des apports suivants ne
/// depend que du ratio reserves/totalLiquidity, pas de l'unite choisie pour le tout premier
/// depot : ce choix n'affecte que l'echelle des parts du tout premier fournisseur, jamais
/// l'equite entre fournisseurs.
contract SimpleAMM {
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidityOf;

    event Mint(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Burn(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed trader, uint256 amount0In, uint256 amount1Out);

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    /// @notice Ajoute de la liquidite et credite l'appelant des parts correspondantes.
    /// @param minLiquidity Protection anti-slippage : revert si moins de parts seraient emises.
    function mint(uint256 amount0, uint256 amount1, uint256 minLiquidity) external returns (uint256 liquidity) {
        require(amount0 > 0 && amount1 > 0, "SimpleAMM: zero amount");

        if (totalLiquidity == 0) {
            uint256 initialLiquidity = amount0 * amount1;
            require(initialLiquidity > MINIMUM_LIQUIDITY, "SimpleAMM: insufficient initial liquidity");
            liquidity = initialLiquidity - MINIMUM_LIQUIDITY;
            // Verrouille une part minimale et irrecuperable pour rendre le prix des parts
            // impossible a manipuler par donation directe au tout premier depot.
            liquidityOf[address(0)] += MINIMUM_LIQUIDITY;
            totalLiquidity += MINIMUM_LIQUIDITY;
        } else {
            liquidity = _min((amount0 * totalLiquidity) / reserve0, (amount1 * totalLiquidity) / reserve1);
        }
        require(liquidity > 0 && liquidity >= minLiquidity, "SimpleAMM: slippage");

        // Effects before interactions.
        reserve0 += amount0;
        reserve1 += amount1;
        totalLiquidity += liquidity;
        liquidityOf[msg.sender] += liquidity;

        emit Mint(msg.sender, amount0, amount1, liquidity);

        require(token0.transferFrom(msg.sender, address(this), amount0), "Transfert token0 echoue");
        require(token1.transferFrom(msg.sender, address(this), amount1), "Transfert token1 echoue");
    }

    /// @notice Retire de la liquidite : brule les parts de l'appelant contre sa part proportionnelle
    /// des reserves.
    /// @param minAmount0 Protection anti-slippage sur le montant de token0 restitue.
    /// @param minAmount1 Protection anti-slippage sur le montant de token1 restitue.
    function burn(uint256 liquidity, uint256 minAmount0, uint256 minAmount1)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        require(liquidity > 0 && liquidity <= liquidityOf[msg.sender], "SimpleAMM: insufficient liquidity");

        amount0 = (liquidity * reserve0) / totalLiquidity;
        amount1 = (liquidity * reserve1) / totalLiquidity;
        require(amount0 >= minAmount0 && amount1 >= minAmount1, "SimpleAMM: slippage");

        // Effects before interactions.
        liquidityOf[msg.sender] -= liquidity;
        totalLiquidity -= liquidity;
        reserve0 -= amount0;
        reserve1 -= amount1;

        emit Burn(msg.sender, amount0, amount1, liquidity);

        require(token0.transfer(msg.sender, amount0), "Transfert token0 echoue");
        require(token1.transfer(msg.sender, amount1), "Transfert token1 echoue");
    }

    /// @notice Echange token0 contre token1.
    /// @param minAmount1Out Protection anti-slippage : revert si le swap rendrait moins que ce montant.
    function swap0For1(uint256 amount0In, uint256 minAmount1Out) external returns (uint256 amount1Out) {
        require(amount0In > 0, "Montant invalide");

        // Calcul mathématique basé sur x * y = k
        // amount1Out = (reserve1 * amount0In) / (reserve0 + amount0In)
        uint256 numerator = reserve1 * amount0In;
        uint256 denominator = reserve0 + amount0In;
        amount1Out = numerator / denominator;

        require(amount1Out < reserve1, "Liquidite insuffisante");
        require(amount1Out >= minAmount1Out, "SimpleAMM: slippage");

        // Effects before interactions.
        reserve0 += amount0In;
        reserve1 -= amount1Out;

        emit Swap(msg.sender, amount0In, amount1Out);

        require(token0.transferFrom(msg.sender, address(this), amount0In), "Transfert token0 echoue");
        require(token1.transfer(msg.sender, amount1Out), "Transfert token1 echoue");
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
