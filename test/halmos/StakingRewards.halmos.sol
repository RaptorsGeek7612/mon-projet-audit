// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {StakingRewards} from "../../src/StakingRewards.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Tests d'execution symbolique (halmos). Lancer avec: halmos --contract StakingRewardsHalmosTest
///
/// L'accrual des recompenses (rewardPerToken: multiplication * division sur des variables
/// symboliques) releve de la meme classe d'arithmetique non-lineaire qui fait deja timeout
/// le solveur sur l'invariant de l'AMM (cf. AMM.halmos.sol) : non tente ici. Cette propriete
/// est prouvee concretement par testFuzz_stakeWithdrawInterleaved_neverLosesAccruedRewards
/// et test_equalStakers_splitRewardsEqually dans StakingRewards.t.sol.
contract StakingRewardsHalmosTest is SymTest, Test {
    StakingRewards staking;
    MockERC20 stakingToken;

    function setUp() public {
        stakingToken = new MockERC20();
        MockERC20 rewardToken = new MockERC20();
        staking = _deployStakingRewards(stakingToken, rewardToken);
    }

    /// @dev `new StakingRewards(...)` fait planter halmos (bug connu : resolution d'artefact
    /// incorrecte pour un contrat importe d'un autre fichier avec `immutable`).
    /// Contournement : deployer via vm.getCode + create bas niveau, que halmos gere
    /// correctement.
    function _deployStakingRewards(IERC20 _stakingToken, IERC20 _rewardToken)
        internal
        returns (StakingRewards deployed)
    {
        bytes memory code = vm.getCode("StakingRewards.sol:StakingRewards");
        bytes memory initcode = abi.encodePacked(code, abi.encode(address(_stakingToken), address(_rewardToken)));
        address addr;
        assembly {
            addr := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(addr != address(0), "StakingRewards deploy failed");
        deployed = StakingRewards(addr);
    }

    /// @dev Un retrait ne peut jamais depasser ce que l'utilisateur a reellement stake.
    function check_withdrawNeverExceedsStake(address user, uint256 stakeAmount, uint256 withdrawAmount) public {
        vm.assume(user != address(0));
        stakeAmount = bound(stakeAmount, 1, type(uint128).max);

        stakingToken.mint(user, stakeAmount);

        vm.prank(user);
        stakingToken.approve(address(staking), stakeAmount);

        vm.prank(user);
        staking.stake(stakeAmount);

        vm.prank(user);
        if (withdrawAmount > stakeAmount) {
            // vm.expectRevert(string) isn't supported by halmos; use try/catch instead.
            try staking.withdraw(withdrawAmount) {
                assert(false);
            } catch {
                // expected: reverts on invalid amount
            }
        } else {
            staking.withdraw(withdrawAmount);
            assert(staking.balanceOf(user) == stakeAmount - withdrawAmount);
        }
    }

    /// @dev Seul le proprietaire peut financer une nouvelle periode de recompenses.
    function check_onlyOwnerCanNotifyReward(address caller, uint256 amount) public {
        vm.assume(caller != address(this));
        vm.assume(amount > 0);

        vm.prank(caller);
        try staking.notifyRewardAmount(amount) {
            assert(false);
        } catch {
            // expected: reverts for any non-owner caller
        }
    }
}
