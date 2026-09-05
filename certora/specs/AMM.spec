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
