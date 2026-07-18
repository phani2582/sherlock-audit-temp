// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {CompressedOracleV1} from "../contracts/oracles/compressed/CompressedOracle.sol";

contract SetInput is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        address[] memory pushers = new address[](1);
        pushers[0] = 0xE564305A334872EBb13a7aA2e3987Cb56A9e2ca5;

        address[] memory oldPushers = new address[](1);
        oldPushers[0] = 0x5886BAD65ab1380Fc17bD64A962a784bA1a90b70;
        // oldPushers[1] = 0x5dD09c56FB135194A9D44Da67c032a69689ff2Ad;


        vm.startBroadcast(deployerKey);
        CompressedOracleV1 oracle = CompressedOracleV1(0x5EcF662aBB8C2AB099862F9Ef2DDc16CBC8A9977);
        oracle.removePushers(oldPushers);
        oracle.allowContractPushers(pushers);
    }
}
