// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @notice Shared config reader/writer for all deployment scripts.
///         Reads from `script/config/networks.json` — a single file
///         containing per-network config keyed by network name.
///
/// JSON structure:
///   {
///     "<network>": {
///       "deployments": { "factory": "0x...", "oracle": "0x...", ... },
///       "access":      { "admins": ["0x..."] },
///       "oracle":      { "maxTimeDrift": 60, "expectedProperties": [0,4,5,12] },
///       "feeds":       { ... },
///       "providers":   { ... }
///     }
///   }
abstract contract NetworkConfig is Script {
    string constant NETWORKS_JSON = "script/config/networks.json";

    // ── reads ───────────────────────────────────────────────────────

    function _configJson() internal view returns (string memory) {
        return vm.readFile(NETWORKS_JSON);
    }

    function _deployment(string memory network, string memory key) internal view returns (address) {
        return abi.decode(
            vm.parseJson(_configJson(), string.concat(".", network, ".deployments.", key)),
            (address)
        );
    }

    function _admins(string memory network) internal view returns (address[] memory) {
        return abi.decode(
            vm.parseJson(_configJson(), string.concat(".", network, ".access.admins")),
            (address[])
        );
    }

    function _oracleMaxTimeDrift(string memory network) internal view returns (uint256) {
        return abi.decode(
            vm.parseJson(_configJson(), string.concat(".", network, ".oracle.maxTimeDrift")),
            (uint256)
        );
    }

    function _oracleExpectedProperties(string memory network) internal view returns (uint8[] memory) {
        return abi.decode(
            vm.parseJson(_configJson(), string.concat(".", network, ".oracle.expectedProperties")),
            (uint8[])
        );
    }

    // ── writes ──────────────────────────────────────────────────────

    function _writeDeployment(string memory network, string memory key, address addr) internal {
        // Only persist on a real broadcast. A dry-run / simulation must NOT mutate the registry:
        // CREATE3 addresses are deterministic and already logged by the caller, so a dry-run would
        // otherwise overwrite live deployment addresses with not-yet-deployed predicted ones.
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console.log("Dry-run: registry NOT updated (pass --broadcast to persist)", network, key);
            return;
        }
        vm.writeJson(
            vm.toString(addr),
            NETWORKS_JSON,
            string.concat(".", network, ".deployments.", key)
        );
    }
}
