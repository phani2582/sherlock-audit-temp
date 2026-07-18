// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {NetworkConfig} from "../NetworkConfig.sol";
import {PriceProviderFactoryL2} from "../../contracts/PriceProviderFactoryL2.sol";

/// @notice Create one or more L2 PriceProviders via the factory.
///
/// ── Mode 1: single provider via ENV ──────────────────────────────────
///   PRIVATE_KEY       – factory owner private key
///   NETWORK           – loads FACTORY & ORACLE from deployments.json
///   FEED_ID           – Pyth Lazer feed id (uint256, e.g. "631" for WETH)
///   CEX_STEP          – CEX step in 1e18-based BPS (e.g. "400000000000000" = 0.04%)
///   MAX_TIME_DELTA    – max staleness in seconds (e.g. "10")
///   FUTURE_TOLERANCE  – L2 sequencer skew tolerance in seconds (e.g. "5")
///   FACTORY           – (optional, overrides deployments.json)
///   ORACLE            – (optional, overrides deployments.json)
///
/// ── Mode 2: batch via config file ────────────────────────────────────
///   PRIVATE_KEY  – factory owner private key
///   CONFIG       – path to JSON config file
///
/// Config JSON format:
///   {
///     "factory": "0x...",
///     "oracle":  "0x...",
///     "feeds": [
///       { "feedId": 631, "cexStep": 400000000000000, "maxTimeDelta": 10, "futureTolerance": 5 },
///       { "feedId": 397, "cexStep": 300000000000000, "maxTimeDelta": 10, "futureTolerance": 5 }
///     ]
///   }
contract CreatePriceProviderL2 is NetworkConfig {
    struct FeedConfig {
        int256  cexStep;
        uint256 feedId;
        uint256 futureTolerance;
        uint256 maxTimeDelta;
    }

    struct Config {
        address factory;
        FeedConfig[] feeds;
        address oracle;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        string memory configPath = vm.envOr("CONFIG", string(""));

        if (bytes(configPath).length > 0) {
            _runFromConfig(deployerKey, configPath);
        } else {
            _runFromEnv(deployerKey);
        }
    }

    function _loadDeploy(string memory key) internal returns (address) {
        string memory network = vm.envOr("NETWORK", string(""));
        if (bytes(network).length == 0) return address(0);
        return _deployment(network, key);
    }

    function _runFromEnv(uint256 deployerKey) internal {
        address factoryAddr     = vm.envOr("FACTORY", _loadDeploy("factory"));
        address oracle          = vm.envOr("ORACLE", _loadDeploy("oracle"));
        require(factoryAddr != address(0), "set FACTORY or NETWORK");
        require(oracle != address(0), "set ORACLE or NETWORK");
        uint256 feedIdRaw       = vm.envUint("FEED_ID");
        int256  cexStep         = vm.envInt("CEX_STEP");
        uint256 maxTimeDelta    = vm.envUint("MAX_TIME_DELTA");
        uint256 futureTolerance = vm.envUint("FUTURE_TOLERANCE");

        PriceProviderFactoryL2 factory = PriceProviderFactoryL2(factoryAddr);

        vm.startBroadcast(deployerKey);
        address provider = factory.createPriceProvider(
            oracle, bytes32(feedIdRaw), cexStep, maxTimeDelta, futureTolerance,
            address(0x68749665FF8D2d112Fa859AA293F07A622782F38), address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
        );
        vm.stopBroadcast();

        console.log("Provider deployed at", provider);
    }

    function _runFromConfig(uint256 deployerKey, string memory configPath) internal {
        string memory json = vm.readFile(configPath);

        address factoryAddr = abi.decode(vm.parseJson(json, ".factory"), (address));
        address oracle      = abi.decode(vm.parseJson(json, ".oracle"),  (address));

        bytes memory rawFeeds = vm.parseJson(json, ".feeds");
        FeedConfig[] memory feeds = abi.decode(rawFeeds, (FeedConfig[]));

        PriceProviderFactoryL2 factory = PriceProviderFactoryL2(factoryAddr);

        vm.startBroadcast(deployerKey);
        for (uint256 i; i < feeds.length; ++i) {
            FeedConfig memory f = feeds[i];
            address provider = factory.createPriceProvider(
                oracle,
                bytes32(f.feedId),
                f.cexStep,
                f.maxTimeDelta,
                f.futureTolerance,
                address(0x68749665FF8D2d112Fa859AA293F07A622782F38),
                address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
            );
            console.log("Provider for feed %d deployed at %s", f.feedId, provider);
        }
        vm.stopBroadcast();

        console.log("Total providers created:", feeds.length);
    }
}
