// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {TokenVestingVault} from "../src/TokenVestingVault.sol";

contract DeployTokenVestingVault is Script {
    function run() external returns (TokenVestingVault vault) {
        address initialOwner = vm.envAddress("INITIAL_OWNER");

        vm.startBroadcast();
        vault = new TokenVestingVault(initialOwner);
        vm.stopBroadcast();
    }
}
