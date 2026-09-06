// Certora Verification Language (CVL) spec pour StakingRewards
//
// L'accrual des recompenses (rewardPerToken) repose sur une multiplication et une division
// impliquant block.timestamp, rewardRate et totalSupply : arithmetique non-lineaire du meme
// type que celle qui defie deja le solveur sur l'AMM (cf. AMM.spec, qui evite la meme
// difficulte). Cette spec se concentre donc sur les proprietes structurelles (comptabilite,
// controle d'acces, absence de fuite entre comptes), qui sont ce que Certora prouve bien ;
// l'exactitude de l'accrual dans le temps est verifiee par fuzzing dans StakingRewards.t.sol.

methods {
    function stake(uint256) external;
    function withdraw(uint256) external;
    function getReward() external;
    function setRewardRate(uint256) external;
    function balanceOf(address) external returns (uint256) envfree;
    function totalSupply() external returns (uint256) envfree;
    function owner() external returns (address) envfree;

    // Sans ce resume, un appel non resolu vers stakingToken/rewardToken serait traite comme
    // pouvant "havoc" le storage du contrat (cf. le meme correctif applique a Vault.spec).
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

// stake() must credit the caller and grow totalSupply by exactly `amount`.
rule stakeIncreasesBalanceAndSupply(uint256 amount) {
    env e;
    require amount > 0;

    uint256 balBefore = balanceOf(e.msg.sender);
    uint256 supplyBefore = totalSupply();

    stake(e, amount);

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

// No function should ever change another user's staked balance (no cross-account leakage).
rule onlyCallerBalanceChanges(method f, address other) {
    env e;
    require other != e.msg.sender;

    uint256 otherBalBefore = balanceOf(other);

    calldataarg args;
    f(e, args);

    assert balanceOf(other) == otherBalBefore;
}

// Only the owner may change the reward rate.
rule setRewardRateOnlyOwner(uint256 newRate) {
    env e;
    require e.msg.sender != owner();

    setRewardRate@withrevert(e, newRate);

    assert lastReverted;
}
