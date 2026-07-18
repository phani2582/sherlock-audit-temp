// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {NetworkConfig} from "../NetworkConfig.sol";
import {OracleBase} from "../../contracts/oracles/providers/OracleBase.sol";

/// @notice One-shot post-deploy configuration for the production oracles on a network:
///   RECONCILE each oracle's approved-factory allow-list to the configured desired set: factories
///   currently approved but NOT in config are removed, and configured factories not yet approved are
///   added (on BOTH oracles). The config list (or env APPROVED_FACTORIES) is the source of truth, so
///   shrinking it removes the dropped factories on the next run.
///
/// The oracles are registrationless: there is no REGISTRAR_ROLE to grant and no feeds to register —
/// any feed id carried in a provider-SIGNED payload (Pyth Lazer / Chainlink DS) is stored on push.
///
/// Idempotent: factories already present are skipped. Safe to re-run after adding more factories.
///
/// ── IMPORTANT: approved factories & isPool ─────────────────────────────────────────────────────
/// OracleBase.register(feedId, pool, factory) validates the pool via IPoolFactory(factory).isPool(pool).
/// A factory in the allow-list MUST implement isPool for register() to succeed through it. NOTE: the
/// project's own PriceProviderFactory and AnchoredProviderFactory do NOT implement isPool — approving
/// them only seeds the set; register() through them reverts until/unless they expose isPool. Addresses
/// are taken verbatim from config/env at the operator's explicit direction.
///
/// ── ENV ────────────────────────────────────────────────────────────────────────────────────────
///   PRIVATE_KEY         – deployer/admin key (must hold ADMIN_ROLE on both oracles)
///   NETWORK             – network name (default "base")
///   APPROVED_FACTORIES  – optional comma-separated factory addresses; overrides the config list
///
/// Reads from networks.json:
///   .<net>.deployments.oracle             → PythOracle
///   .<net>.deployments.dataStreamsOracle  → ChainlinkOracle
///   .<net>.access.approvedFactories       → default factory allow-list
///
/// Usage:
///   NETWORK=base PRIVATE_KEY=0x... forge script script/l2/ConfigureOracles.s.sol --rpc-url base [--broadcast]
///   (or via script/configure-oracles.sh)
contract ConfigureOracles is NetworkConfig {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        string memory network = vm.envOr("NETWORK", string("base"));

        address pythAddr = _deployment(network, "oracle");
        address clAddr   = _deployment(network, "dataStreamsOracle");
        require(pythAddr != address(0) && pythAddr.code.length > 0, "Pyth oracle not deployed");
        require(clAddr   != address(0) && clAddr.code.length   > 0, "Chainlink oracle not deployed");

        OracleBase pyth = OracleBase(payable(pythAddr));
        OracleBase cl   = OracleBase(payable(clAddr));

        address[] memory factories = _approvedFactories(network);

        console.log("Network:          ", network);
        console.log("Deployer:         ", deployer);
        console.log("Pyth oracle:      ", pythAddr);
        console.log("Chainlink oracle: ", clAddr);
        console.log("Desired factories:", factories.length);

        // Fail fast (before broadcasting any tx) if the broadcaster cannot perform the admin-gated steps.
        require(pyth.hasRole(pyth.ADMIN_ROLE(), deployer), "deployer lacks ADMIN_ROLE on Pyth oracle");
        require(cl.hasRole(cl.ADMIN_ROLE(), deployer),     "deployer lacks ADMIN_ROLE on Chainlink oracle");

        vm.startBroadcast(deployerKey);

        // reconcile each oracle's approved-factory set to the desired (config) set
        _reconcileFactories(pyth, factories);
        _reconcileFactories(cl, factories);

        vm.stopBroadcast();
    }

    // ── helpers ──────────────────────────────────────────────────────────────────────────────────

    /// @dev Make `o`'s approved-factory set equal `desired`: remove any currently-approved factory not in
    ///      `desired`, then add any `desired` factory not yet approved. Iterates a memory snapshot of the
    ///      on-chain set, so removals (swap-and-pop on-chain) don't disturb the loop. Idempotent.
    function _reconcileFactories(OracleBase o, address[] memory desired) internal {
        uint256 cur = o.approvedFactoryCount();
        address[] memory current = cur == 0 ? new address[](0) : o.getApprovedFactories(0, cur);
        for (uint256 i; i < current.length; ++i) {
            if (!_contains(desired, current[i])) {
                o.removeApprovedFactory(current[i]);
                console.log("  factory removed:", current[i]);
            }
        }
        for (uint256 i; i < desired.length; ++i) {
            address f = desired[i];
            if (f == address(0)) continue;
            if (o.isApprovedFactory(f)) { console.log("  factory already approved:", f); continue; }
            o.addApprovedFactory(f);
            console.log("  factory approved:", f);
        }
    }

    function _contains(address[] memory arr, address x) private pure returns (bool) {
        for (uint256 i; i < arr.length; ++i) if (arr[i] == x) return true;
        return false;
    }

    function _approvedFactories(string memory network) internal view returns (address[] memory) {
        address[] memory fromEnv = vm.envOr("APPROVED_FACTORIES", ",", new address[](0));
        if (fromEnv.length > 0) return fromEnv;
        bytes memory raw = vm.parseJson(_configJson(), string.concat(".", network, ".access.approvedFactories"));
        if (raw.length == 0) return new address[](0);
        return abi.decode(raw, (address[]));
    }
}
