// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {NetworkConfig} from "../NetworkConfig.sol";
import {PythOracle} from "../../contracts/oracles/providers/PythOracle.sol";

/// @dev Minimal CreateX interface for CREATE3 deployment.
///      CreateX is deployed at the same address on all supported chains.
interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode)
        external
        payable
        returns (address newContract);

    function computeCreate3Address(bytes32 salt)
        external
        view
        returns (address computedAddress);
}

/// @notice Deploy PythOracle via CREATE3 for deterministic addresses across chains.
///
/// Skips automatically if PythLazer has no code on the target chain.
///
/// ENV:
///   PRIVATE_KEY     – deployer private key (becomes oracle owner)
///   NETWORK         – network name
///   DEPLOY_VERSION  – version string for salt entropy (e.g. "v1")
///   PYTH_LAZER      – (optional) override PythLazer address
///
/// Config:
///   script/config/networks.json  → .{NETWORK}.oracle
///
/// Writes:
///   script/config/networks.json  → .{NETWORK}.deployments.oracle
///
/// Usage:
///   NETWORK=base DEPLOY_VERSION=v1 forge script script/l2/DeployPythOracle.s.sol \
///     --rpc-url $RPC_URL --broadcast
contract DeployPythOracleL2 is NetworkConfig {
    /// @dev Canonical CreateX factory address (same on all EVM chains).
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    /// @dev PythLazer proxy — deployed at the same address on all supported chains.
    address constant PYTH_LAZER = 0xACeA761c27A909d4D3895128EBe6370FDE2dF481;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory network = vm.envString("NETWORK");
        string memory version = vm.envString("DEPLOY_VERSION");

        // --- pythLazer ---
        address pythLazer = vm.envOr("PYTH_LAZER", PYTH_LAZER);

        // --- preflight: skip if pythLazer not deployed on this chain ---
        uint256 codeSize;
        assembly { codeSize := extcodesize(pythLazer) }
        if (codeSize == 0) {
            console.log("SKIP:", network, "- PythLazer not deployed at", pythLazer);
            return;
        }

        // --- config ---
        uint256 maxTimeDrift        = _oracleMaxTimeDrift(network);
        uint8[] memory expectedProperties = _oracleExpectedProperties(network);

        address owner = vm.addr(deployerKey);
        ICreateX createx = ICreateX(CREATEX);

        // --- salt ---
        // CreateX salt format: [20 bytes sender] [1 byte flags] [11 bytes entropy]
        // address(0) prefix = permissionless, 0x00 flag = no cross-chain redeploy protection.
        // _guard() hashes this salt: guardedSalt = keccak256(abi.encode(salt)).
        // computeCreate3Address expects the guarded (post-_guard) salt.
        bytes32 salt = bytes32(abi.encodePacked(
            bytes20(0), bytes1(0),
            bytes11(keccak256(abi.encodePacked("PythOracle-", version)))
        ));

        // --- predict address ---
        bytes32 guardedSalt = keccak256(abi.encode(salt));
        address predicted = createx.computeCreate3Address(guardedSalt);
        console.log("Predicted address:", predicted);

        // --- deploy ---
        bytes memory initCode = abi.encodePacked(
            type(PythOracle).creationCode,
            abi.encode(owner, pythLazer, maxTimeDrift, expectedProperties)
        );

        vm.startBroadcast(deployerKey);
        address deployed = createx.deployCreate3(salt, initCode);
        vm.stopBroadcast();

        require(deployed == predicted, "address mismatch");

        _writeDeployment(network, "oracle", deployed);

        console.log("Network:", network);
        console.log("PythOracle deployed at", deployed);
        console.log("Salt:", vm.toString(salt));
    }
}
