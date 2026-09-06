// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "./interfaces/IERC20.sol";

/// @notice Staking avec recompenses lineaires financees explicitement (modele reward-per-token
/// + notifyRewardAmount, a la Synthetix).
///
/// Le taux de recompense n'est plus fixe arbitrairement par l'owner : il derive d'un montant
/// reellement transfere au contrat (`notifyRewardAmount`) reparti sur une duree fixe. Cela
/// garantit que toute recompense qui s'accumule est deja backee par un vrai transfert, et - avec
/// stakingToken != rewardToken impose au deploiement - que ce financement ne peut jamais entamer
/// le solde qui garantit `totalSupply` (le principal stake).
contract StakingRewards {
    uint256 private constant PRECISION = 1e18;
    uint256 public constant REWARD_DURATION = 7 days;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;
    address public immutable owner;

    uint256 public rewardRate; // recompenses distribuees par seconde, sur l'ensemble des stakers
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public rewardReserve; // recompenses financees et pas encore distribuees

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardFunded(uint256 amount, uint256 newRewardRate);

    constructor(IERC20 _stakingToken, IERC20 _rewardToken) {
        require(address(_stakingToken) != address(_rewardToken), "StakingRewards: staking and reward token must differ");
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        owner = msg.sender;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        uint256 elapsed = lastTimeRewardApplicable() - lastUpdateTime;
        return rewardPerTokenStored + (elapsed * rewardRate * PRECISION) / totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        uint256 accrued = (balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / PRECISION;
        return accrued + rewards[account];
    }

    /// @notice Finance une nouvelle periode de recompenses de `REWARD_DURATION`. Le taux est
    /// recalcule a partir du montant reellement transfere, en reportant les recompenses non
    /// distribuees de la periode en cours le cas echeant.
    function notifyRewardAmount(uint256 amount) external updateReward(address(0)) {
        require(msg.sender == owner, "StakingRewards: not owner");
        require(amount > 0, "StakingRewards: zero amount");

        if (block.timestamp >= periodFinish) {
            rewardRate = amount / REWARD_DURATION;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            rewardRate = (amount + remaining * rewardRate) / REWARD_DURATION;
        }

        rewardReserve += amount;
        periodFinish = block.timestamp + REWARD_DURATION;

        emit RewardFunded(amount, rewardRate);

        require(
            rewardToken.transferFrom(msg.sender, address(this), amount), "StakingRewards: funding transferFrom failed"
        );
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
        rewardReserve -= reward;

        emit RewardPaid(msg.sender, reward);

        require(rewardToken.transfer(msg.sender, reward), "StakingRewards: reward transfer failed");
    }
}
