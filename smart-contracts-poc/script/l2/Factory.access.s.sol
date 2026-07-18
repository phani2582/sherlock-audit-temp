// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {NetworkConfig} from "../NetworkConfig.sol";
import {PriceProviderFactory} from "../../contracts/PriceProviderFactory.sol";

/// @notice Grant roles on PriceProviderFactory from config.
///
/// ── Environment variables ───────────────────────────────────────────
///   PRIVATE_KEY  – admin private key
///   NETWORK      – network name (arbitrum, base, optimism, etc.)
///
/// Reads:
///   script/config/networks.json  → .{NETWORK}.deployments.factory, .{NETWORK}.access.admins
///
/// Usage:
///   NETWORK=base forge script script/l2/Factory.access.s.sol \
///     --rpc-url $RPC_URL --broadcast
contract FactoryAccess is NetworkConfig {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory network = vm.envString("NETWORK");

        address factoryAddr = _deployment(network, "factory");
        require(factoryAddr != address(0), "factory not deployed");

        address[] memory admins = _admins(network);

        PriceProviderFactory factory = PriceProviderFactory(factoryAddr);

        console.log("Network:", network);
        console.log("Factory:", factoryAddr);

        uint256 granted;

        vm.startBroadcast(deployerKey);
        granted += _grantAll(factory, factory.ADMIN_ROLE(), "ADMIN_ROLE", admins);
        vm.stopBroadcast();

        console.log("Granted:", granted);
    }

    function _grantAll(
        PriceProviderFactory factory,
        bytes32 role,
        string memory roleName,
        address[] memory accounts
    ) internal returns (uint256 granted) {
        for (uint256 i; i < accounts.length; i++) {
            if (factory.hasRole(role, accounts[i])) {
                console.log(string.concat("  skip ", roleName, " (already granted)"), accounts[i]);
                continue;
            }
            factory.grantRole(role, accounts[i]);
            console.log(string.concat("  grant ", roleName), accounts[i]);
            granted++;
        }
    }
}
