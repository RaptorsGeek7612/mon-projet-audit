// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

/// @notice Coffre-fort minimaliste 1:1 (deposit/withdraw) servant de cible d'audit.
contract Vault {
    IERC20 public immutable asset;

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    constructor(IERC20 _asset) {
        asset = _asset;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Vault: zero amount");

        // Effects before interactions.
        balanceOf[msg.sender] += amount;
        totalSupply += amount;

        require(asset.transferFrom(msg.sender, address(this), amount), "Vault: transferFrom failed");

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Vault: zero amount");

        uint256 bal = balanceOf[msg.sender];
        require(bal >= amount, "Vault: insufficient balance");

        balanceOf[msg.sender] = bal - amount;
        totalSupply -= amount;

        require(asset.transfer(msg.sender, amount), "Vault: transfer failed");

        emit Withdraw(msg.sender, amount);
    }

    function totalAssets() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
