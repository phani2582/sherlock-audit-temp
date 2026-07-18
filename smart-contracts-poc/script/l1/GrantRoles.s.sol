// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {NetworkConfig} from "../NetworkConfig.sol";
import {PriceProviderFactory} from "../../contracts/PriceProviderFactory.sol";

/// @notice Grant roles on L1 PriceProviderFactory from config.
///
/// ENV:
///   PRIVATE_KEY  – admin private key
///
/// Reads:
///   script/config/networks.json  → .ethereum.deployments.factory, .ethereum.access.admins
///
/// Usage:
///   forge script script/l1/GrantRoles.s.sol --rpc-url $ETH_RPC --broadcast
contract GrantRolesL1 is NetworkConfig {
    string constant NETWORK = "ethereum";

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        address factoryAddr = _deployment(NETWORK, "factory");
        require(factoryAddr != address(0), "factory not deployed");

        address[] memory admins = _admins(NETWORK);

        PriceProviderFactory factory = PriceProviderFactory(factoryAddr);

        console.log("Factory:", factoryAddr);

        uint256 granted;

        vm.startBroadcast(deployerKey);
        granted += _grantAll(factory, factory.ADMIN_ROLE(), "ADMIN", admins);
        vm.stopBroadcast();

        console.log("Granted:", granted);
    }

    function _grantAll(
        PriceProviderFactory factory,
        bytes32 role,
        string memory name,
        address[] memory accounts
    ) internal returns (uint256 granted) {
        for (uint256 i; i < accounts.length; i++) {
            if (factory.hasRole(role, accounts[i])) {
                console.log(string.concat("  skip ", name), accounts[i]);
                continue;
            }
            factory.grantRole(role, accounts[i]);
            console.log(string.concat("  grant ", name), accounts[i]);
            granted++;
        }
    }
}
