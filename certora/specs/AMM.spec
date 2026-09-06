/*
   Spécification Certora pour SimpleAMM
*/

methods {
    // Déclaration des vues en 'envfree' car elles ne dépendent pas du contexte de transaction
    function reserve0() external returns (uint256) envfree;
    function reserve1() external returns (uint256) envfree;

    // On indique au Prover que les transferts des jetons externes renvoient toujours true pour simplifier la preuve de l'AMM
    function _.transferFrom(address, address, uint256) external => ALWAYS(true);
    function _.transfer(address, uint256) external => ALWAYS(true);
}

// Règle de validation du swap
rule swapIntegrity(uint256 amountIn) {
    env e;

    uint256 r0Before = reserve0();
    uint256 r1Before = reserve1();

    // Calcul mathématique de K initial en CVL
    mathint kBefore = r0Before * r1Before;

    // Déclencher l'action
    currentContract.swap0For1(e, amountIn);

    uint256 r0After = reserve0();
    uint256 r1After = reserve1();
    mathint kAfter = r0After * r1After;

    // Preuve de l'invariant x * y = k
    assert kAfter >= kBefore, "L'invariant du produit constant a ete viole !";
}

// mint() doit crediter les deux reserves exactement des montants fournis, ni plus ni moins.
rule mintIsExact(uint256 amount0, uint256 amount1) {
    env e;

    uint256 r0Before = reserve0();
    uint256 r1Before = reserve1();

    currentContract.mint(e, amount0, amount1);

    assert to_mathint(reserve0()) == r0Before + amount0, "reserve0 n'a pas ete creditee du montant exact";
    assert to_mathint(reserve1()) == r1Before + amount1, "reserve1 n'a pas ete creditee du montant exact";
}

// mint() ne peut jamais faire baisser le produit constant k (il ne fait que l'augmenter ou le laisser
// inchange si l'un des deux montants est nul).
rule mintNeverDecreasesConstantProduct(uint256 amount0, uint256 amount1) {
    env e;

    uint256 r0Before = reserve0();
    uint256 r1Before = reserve1();
    mathint kBefore = r0Before * r1Before;

    currentContract.mint(e, amount0, amount1);

    uint256 r0After = reserve0();
    uint256 r1After = reserve1();
    mathint kAfter = r0After * r1After;

    assert kAfter >= kBefore, "mint() a fait baisser le produit constant";
}
