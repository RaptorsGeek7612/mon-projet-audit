// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "./interfaces/IERC20.sol";

/// @notice Staking avec recompenses lineaires dans le temps (modele reward-per-token, a la Synthetix).
contract StakingRewards {
    uint256 private constant PRECISION = 1e18;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;
    address public immutable owner;

    uint256 public rewardRate; // recompenses distribuees par seconde, sur l'ensemble des stakers
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    constructor(IERC20 _stakingToken, IERC20 _rewardToken) {
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        owner = msg.sender;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        uint256 elapsed = block.timestamp - lastUpdateTime;
        return rewardPerTokenStored + (elapsed * rewardRate * PRECISION) / totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        uint256 accrued = (balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / PRECISION;
        return accrued + rewards[account];
    }

    function setRewardRate(uint256 _rewardRate) external updateReward(address(0)) {
        require(msg.sender == owner, "StakingRewards: not owner");
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    function stake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "StakingRewards: zero amount");

        // Effects before interactions.
        totalSupply += amount;
        balanceOf[msg.sender] += amount;

        emit Staked(msg.sender, amount);

        require(stakingToken.transferFrom(msg.sender, address(this), amount), "StakingRewards: transferFrom failed");
    }

    function withdraw(uint256 amount) external updateReward(msg.sender) {
        uint256 bal = balanceOf[msg.sender];
        require(amount > 0 && amount <= bal, "StakingRewards: invalid amount");

        // Effects before interactions.
        totalSupply -= amount;
        balanceOf[msg.sender] = bal - amount;

        emit Withdrawn(msg.sender, amount);

        require(stakingToken.transfer(msg.sender, amount), "StakingRewards: transfer failed");
    }

    function getReward() external updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward == 0) return;

        // Effects before interactions.
        rewards[msg.sender] = 0;

        emit RewardPaid(msg.sender, reward);

        require(rewardToken.transfer(msg.sender, reward), "StakingRewards: reward transfer failed");
    }
}
