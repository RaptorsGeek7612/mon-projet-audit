// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";

contract SimpleAMMScript is Script {
    function run(address token0, address token1) external returns (SimpleAMM amm) {
        vm.startBroadcast();
        amm = new SimpleAMM(token0, token1);
        vm.stopBroadcast();
    }
}
