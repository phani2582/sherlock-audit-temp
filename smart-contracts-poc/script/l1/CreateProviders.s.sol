// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {NetworkConfig} from "../NetworkConfig.sol";
import {PriceProviderFactory} from "../../contracts/PriceProviderFactory.sol";

/// @notice Create L1 PriceProviders via factory on Ethereum.
///
/// ── Mode 1: single provider via ENV ──────────────────────────────────
///   PRIVATE_KEY       – factory creator private key
///   FEED_ID           – Pyth Lazer feed id (uint256)
///   CEX_STEP          – CEX step in 1e18-based BPS
///   MAX_TIME_DELTA    – max staleness in seconds
///   FACTORY           – (optional, falls back to deployments.json)
///   ORACLE            – (optional, falls back to deployments.json)
///
/// ── Mode 2: batch via config file ────────────────────────────────────
///   PRIVATE_KEY  – factory creator private key
///   CONFIG       – path to JSON config
///
///   {
///     "factory": "0x...",    (optional — falls back to deployments.json)
///     "oracle":  "0x...",    (optional — falls back to deployments.json)
///     "feeds": [
///       { "feedId": 631, "cexStep": 400000000000000, "maxTimeDelta": 10 }
///     ]
///   }
///
/// Usage:
///   forge script script/l1/CreateProviders.s.sol --rpc-url $ETH_RPC --broadcast
contract CreateProvidersL1 is NetworkConfig {
    string constant NETWORK = "ethereum";

    struct FeedConfig {
        int256  cexStep;
        uint256 feedId;
        uint256 maxTimeDelta;
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

    function _runFromEnv(uint256 deployerKey) internal {
        address factoryAddr = vm.envOr("FACTORY", _deployment(NETWORK, "factory"));
        address oracle      = vm.envOr("ORACLE",  _deployment(NETWORK, "oracle"));
        require(factoryAddr != address(0), "set FACTORY or populate deployments.json");
        require(oracle != address(0), "set ORACLE or populate deployments.json");

        bytes32 feedIdRaw      = vm.envBytes32("FEED_ID");
        int256  cexStep        = vm.envInt("CEX_STEP");
        uint256 maxTimeDelta   = vm.envUint("MAX_TIME_DELTA");

        PriceProviderFactory factory = PriceProviderFactory(factoryAddr);

        vm.startBroadcast(deployerKey);
        address provider = factory.createPriceProvider(
            oracle, feedIdRaw, cexStep, maxTimeDelta,
            address(0), address(0)
        );
        vm.stopBroadcast();

        console.log("Provider deployed at", provider);
    }

    function _runFromConfig(uint256 deployerKey, string memory configPath) internal {
        string memory json = vm.readFile(configPath);

        address factoryAddr;
        address oracle;

        try vm.parseJsonAddress(json, ".factory") returns (address a) {
            factoryAddr = a;
        } catch {
            factoryAddr = _deployment(NETWORK, "factory");
        }

        try vm.parseJsonAddress(json, ".oracle") returns (address a) {
            oracle = a;
        } catch {
            oracle = _deployment(NETWORK, "oracle");
        }

        require(factoryAddr != address(0), "factory address not found");
        require(oracle != address(0), "oracle address not found");

        bytes memory rawFeeds = vm.parseJson(json, ".feeds");
        FeedConfig[] memory feeds = abi.decode(rawFeeds, (FeedConfig[]));

        PriceProviderFactory factory = PriceProviderFactory(factoryAddr);

        vm.startBroadcast(deployerKey);
        for (uint256 i; i < feeds.length; ++i) {
            FeedConfig memory f = feeds[i];
            address provider = factory.createPriceProvider(
                oracle, bytes32(f.feedId), f.cexStep, f.maxTimeDelta,
                address(0), address(0)
            );
            console.log("Provider for feed %d at %s", f.feedId, provider);
        }
        vm.stopBroadcast();

        console.log("Total providers created:", feeds.length);
    }
}
