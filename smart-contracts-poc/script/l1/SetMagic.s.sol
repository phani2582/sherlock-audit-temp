// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {NetworkConfig} from "../NetworkConfig.sol";
import {PriceProviderFactory} from "../../contracts/PriceProviderFactory.sol";

/// @notice Batch-set confidence params on Ethereum L1 providers.
///
/// ENV:
///   PRIVATE_KEY  – updater private key
///   CONFIG       – (optional) path to confidence config JSON
///
/// Config JSON:
///   { "confidence": [{ "provider": "0x...", "value": 500000 }] }
///
/// Without CONFIG: applies DEFAULT_CONFIDENCE to all providers.
///
/// Usage:
///   forge script script/l1/SetMagic.s.sol --rpc-url $ETH_RPC --broadcast
contract SetConfidenceL1 is NetworkConfig {
    string constant NETWORK = "ethereum";
    uint256 constant DEFAULT_CONFIDENCE = 300_000; // 3 bps
    uint256 constant PAGE_SIZE = 100;

    struct ConfidenceEntry {
        address provider;
        uint256 value;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        address factoryAddr = _deployment(NETWORK, "factory");
        require(factoryAddr != address(0), "factory not deployed");

        PriceProviderFactory factory = PriceProviderFactory(factoryAddr);
        console.log("Factory:", factoryAddr);

        string memory configPath = vm.envOr("CONFIG", string(""));

        if (bytes(configPath).length > 0) {
            _runFromConfig(deployerKey, factory, configPath);
        } else {
            _runDefault(deployerKey, factory);
        }
    }

    function _runFromConfig(
        uint256 deployerKey,
        PriceProviderFactory factory,
        string memory configPath
    ) internal {
        string memory json = vm.readFile(configPath);
        bytes memory raw = vm.parseJson(json, ".confidence");
        ConfidenceEntry[] memory entries = abi.decode(raw, (ConfidenceEntry[]));

        address[] memory providers = new address[](entries.length);
        uint256[] memory values    = new uint256[](entries.length);
        for (uint256 i; i < entries.length; i++) {
            providers[i] = entries[i].provider;
            values[i]    = entries[i].value;
        }

        vm.startBroadcast(deployerKey);
        factory.setConfidence(providers, values);
        vm.stopBroadcast();

        console.log("Updated:", entries.length);
    }

    function _runDefault(uint256 deployerKey, PriceProviderFactory factory) internal {
        uint256 total = factory.providerCount();
        console.log("Providers:", total);

        vm.startBroadcast(deployerKey);

        for (uint256 offset; offset < total; offset += PAGE_SIZE) {
            uint256 limit = PAGE_SIZE;
            if (offset + limit > total) limit = total - offset;

            (address[] memory providers,,) = factory.getAllProviders(offset, limit);
            uint256[] memory values = new uint256[](providers.length);
            for (uint256 i; i < providers.length; i++) {
                values[i] = DEFAULT_CONFIDENCE;
            }

            factory.setConfidence(providers, values);
            console.log("  batch:", providers.length);
        }

        vm.stopBroadcast();
    }
}
