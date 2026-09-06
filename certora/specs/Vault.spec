// Certora Verification Language (CVL) spec for Vault.sol

methods {
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function balanceOf(address) external returns (uint256) envfree;
    function totalSupply() external returns (uint256) envfree;

    // Sans ce résumé, un appel non résolu vers `asset` (transferFrom/transfer)
    // est traité par le Prover comme pouvant "havoc" (modifier arbitrairement)
    // le storage du Vault, ce qui casse trivialement l'invariant de comptabilité
    // sans rapport avec un vrai bug. Cf. le même résumé dans AMM.spec.
    function _.transferFrom(address, address, uint256) external => ALWAYS(true);
    function _.transfer(address, uint256) external => ALWAYS(true);
}

// Ghost tracking the sum of all balanceOf entries, kept in sync via storage hooks.
ghost mathint sumOfBalances {
    init_state axiom sumOfBalances == 0;
}

hook Sstore balanceOf[KEY address user] uint256 newValue (uint256 oldValue) {
    sumOfBalances = sumOfBalances - oldValue + newValue;
}

// Core accounting invariant: totalSupply is always exactly the sum of individual balances.
invariant totalSupplyEqualsSumOfBalances()
    to_mathint(totalSupply()) == sumOfBalances;

// deposit() must credit the caller and grow totalSupply by exactly `amount`.
rule depositIncreasesBalanceAndSupply(uint256 amount) {
    env e;
    require amount > 0;

    uint256 balBefore = balanceOf(e.msg.sender);
    uint256 supplyBefore = totalSupply();

    deposit(e, amount);

    assert balanceOf(e.msg.sender) == balBefore + amount;
    assert totalSupply() == supplyBefore + amount;
}

// withdraw() must debit the caller and shrink totalSupply by exactly `amount`.
rule withdrawDecreasesBalanceAndSupply(uint256 amount) {
    env e;
    uint256 balBefore = balanceOf(e.msg.sender);
    require amount > 0 && amount <= balBefore;

    uint256 supplyBefore = totalSupply();

    withdraw(e, amount);

    assert balanceOf(e.msg.sender) == balBefore - amount;
    assert totalSupply() == supplyBefore - amount;
}

// withdraw() must revert if the caller asks for more than their own balance.
rule withdrawRevertsIfInsufficientBalance(uint256 amount) {
    env e;
    uint256 balBefore = balanceOf(e.msg.sender);
    require amount > balBefore;

    withdraw@withrevert(e, amount);

    assert lastReverted;
}

// No function should ever change another user's balance (no cross-account leakage).
rule onlyCallerBalanceChanges(method f, address other) {
    env e;
    require other != e.msg.sender;

    uint256 otherBalBefore = balanceOf(other);

    calldataarg args;
    f(e, args);

    assert balanceOf(other) == otherBalBefore;
}
