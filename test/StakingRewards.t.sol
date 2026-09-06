// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract StakingRewardsTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(stakingToken, rewardToken);

        stakingToken.mint(alice, 1_000 ether);
        stakingToken.mint(bob, 1_000 ether);
        rewardToken.mint(address(this), 10_000_000 ether);
        rewardToken.approve(address(staking), type(uint256).max);

        vm.prank(alice);
        stakingToken.approve(address(staking), type(uint256).max);
        vm.prank(bob);
        stakingToken.approve(address(staking), type(uint256).max);
    }

    function test_constructor_revertsIfStakingAndRewardTokenAreTheSame() public {
        vm.expectRevert("StakingRewards: staking and reward token must differ");
        new StakingRewards(stakingToken, stakingToken);
    }

    function test_stake_creditsBalanceAndPullsTokens() public {
        vm.prank(alice);
        staking.stake(100 ether);

        assertEq(staking.balanceOf(alice), 100 ether);
        assertEq(staking.totalSupply(), 100 ether);
        assertEq(stakingToken.balanceOf(address(staking)), 100 ether);
    }

    function test_withdraw_debitsBalanceAndReturnsTokens() public {
        vm.startPrank(alice);
        staking.stake(100 ether);
        staking.withdraw(40 ether);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), 60 ether);
        assertEq(staking.totalSupply(), 60 ether);
        assertEq(stakingToken.balanceOf(alice), 940 ether);
    }

    function test_withdraw_revertsWhenInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert("StakingRewards: invalid amount");
        staking.withdraw(1 ether);
    }

    function test_notifyRewardAmount_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("StakingRewards: not owner");
        staking.notifyRewardAmount(7 days * 1 ether);

        staking.notifyRewardAmount(7 days * 1 ether);
        assertEq(staking.rewardRate(), 1 ether);
        assertEq(staking.periodFinish(), block.timestamp + 7 days);
    }

    function test_notifyRewardAmount_pullsFundingFromOwner() public {
        uint256 before = rewardToken.balanceOf(address(this));
        staking.notifyRewardAmount(7 days * 1 ether);

        assertEq(rewardToken.balanceOf(address(this)), before - 7 days * 1 ether);
        assertEq(rewardToken.balanceOf(address(staking)), 7 days * 1 ether);
        assertEq(staking.rewardReserve(), 7 days * 1 ether);
    }

    /// @dev Seul staker : sur une periode sans mouvement dans la duree financee, il touche
    /// exactement rewardRate * duree.
    function test_soleStaker_earnsExactlyRewardRateTimesElapsed() public {
        staking.notifyRewardAmount(7 days * 1 ether); // rewardRate == 1 ether / seconde

        vm.prank(alice);
        staking.stake(100 ether);

        vm.warp(block.timestamp + 5 days);

        assertEq(staking.earned(alice), 1 ether * 5 days);
    }

    /// @dev L'accrual s'arrete a periodFinish : pas de recompense infinie sans re-financement.
    function test_earned_stopsAccruingAfterPeriodFinish() public {
        staking.notifyRewardAmount(7 days * 1 ether);

        vm.prank(alice);
        staking.stake(100 ether);

        vm.warp(block.timestamp + 30 days);

        assertEq(staking.earned(alice), 1 ether * 7 days);
    }

    /// @dev Deux stakers a parts egales se partagent les recompenses a parts egales.
    function test_equalStakers_splitRewardsEqually() public {
        staking.notifyRewardAmount(7 days * 2 ether); // rewardRate == 2 ether / seconde

        vm.prank(alice);
        staking.stake(100 ether);
        vm.prank(bob);
        staking.stake(100 ether);

        vm.warp(block.timestamp + 1 days);

        assertEq(staking.earned(alice), staking.earned(bob));
        assertApproxEqAbs(staking.earned(alice) + staking.earned(bob), 2 ether * 1 days, 2);
    }

    function test_getReward_paysOutEarnedAndZeroesIt() public {
        staking.notifyRewardAmount(7 days * 1 ether);

        vm.startPrank(alice);
        staking.stake(100 ether);
        vm.warp(block.timestamp + 1 days);

        uint256 earnedBefore = staking.earned(alice);
        staking.getReward();
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(alice), earnedBefore);
        assertEq(staking.earned(alice), 0);
        assertEq(staking.rewards(alice), 0);
        assertEq(staking.rewardReserve(), 7 days * 1 ether - earnedBefore);
    }

    /// @dev Deposer/retirer/reclamer dans n'importe quel ordre ne doit jamais faire perdre ou dupliquer
    /// de recompenses deja comptabilisees : `rewards[user]` + la portion courue reste coherente.
    function testFuzz_stakeWithdrawInterleaved_neverLosesAccruedRewards(uint96 stakeAmount, uint32 warpSeconds) public {
        stakeAmount = uint96(bound(stakeAmount, 1, 1_000 ether));
        warpSeconds = uint32(bound(warpSeconds, 1, 365 days));

        staking.notifyRewardAmount(7 days * 1 ether);

        vm.startPrank(alice);
        staking.stake(stakeAmount);
        vm.warp(block.timestamp + warpSeconds);

        uint256 earnedBeforeWithdraw = staking.earned(alice);
        staking.withdraw(stakeAmount);
        vm.stopPrank();

        // Un retrait total ne fait pas evoluer rewardPerToken (totalSupply devient nul), donc
        // les recompenses courues ne doivent pas bouger.
        assertEq(staking.earned(alice), earnedBeforeWithdraw);
    }

    /// @dev Ce que touche un staker ne peut jamais depasser ce qui a ete reellement finance,
    /// quelle que soit la duree ecoulee (protection contre un sur-paiement de l'accrual).
    function testFuzz_rewardPayoutsNeverExceedFundedAmount(uint96 fundedAmount, uint32 warpSeconds) public {
        fundedAmount = uint96(bound(fundedAmount, 7 days, 1_000_000 ether));
        warpSeconds = uint32(bound(warpSeconds, 1, 30 days));

        staking.notifyRewardAmount(fundedAmount);

        vm.prank(alice);
        staking.stake(100 ether);

        vm.warp(block.timestamp + warpSeconds);

        vm.prank(alice);
        staking.getReward();

        assertLe(rewardToken.balanceOf(alice), fundedAmount);
    }

    /// @dev Invariant cle : la comptabilite interne (totalSupply) ne depasse jamais les jetons
    /// de staking reellement detenus par le contrat. Garanti structurellement des lors que
    /// stakingToken != rewardToken (impose au constructeur) : le flux de recompenses ne peut
    /// jamais toucher ce solde.
    function invariant_stakingTokenSolvency() public view {
        assertGe(stakingToken.balanceOf(address(staking)), staking.totalSupply());
    }
}
