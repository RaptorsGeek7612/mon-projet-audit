// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract VaultScript is Script {
    function run(address asset) external returns (Vault vault) {
        vm.startBroadcast();
        vault = new Vault(IERC20(asset));
        vm.stopBroadcast();
    }
}
