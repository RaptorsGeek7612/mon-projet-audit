// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract StakingRewardsScript is Script {
    function run(address stakingToken, address rewardToken) external returns (StakingRewards staking) {
        vm.startBroadcast();
        staking = new StakingRewards(IERC20(stakingToken), IERC20(rewardToken));
        vm.stopBroadcast();
    }
}
