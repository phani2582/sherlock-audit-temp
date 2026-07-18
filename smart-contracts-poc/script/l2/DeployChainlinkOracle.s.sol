// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {NetworkConfig} from "../NetworkConfig.sol";
import {ChainlinkOracle} from "../../contracts/oracles/providers/ChainlinkOracle.sol";

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

/// @notice Deploy ChainlinkOracle (Data Streams consumer) via CREATE3 for deterministic
///         addresses across chains. Mirrors DeployPythOracle — same CreateX flow, same
///         shared maxTimeDrift — but feeds the Data Streams constructor (verifierProxy, feeToken)
///         from per-chain config instead of the chain-constant PythLazer.
///
/// Skips automatically if the chain has no Data Streams config (no verifierProxy) or if the
/// configured verifierProxy has no code on the target chain.
///
/// ENV:
///   PRIVATE_KEY        – deployer private key (becomes oracle owner)
///   NETWORK            – network name
///   DEPLOY_VERSION     – version string for salt entropy (e.g. "v1")
///   CL_VERIFIER_PROXY  – (optional) override the Data Streams VerifierProxy address
///   CL_FEE_TOKEN       – (optional) override the verification fee token address
///
/// Config:
///   script/config/networks.json  → .{NETWORK}.oracle.maxTimeDrift
///                                   .{NETWORK}.oracle.chainlink.verifierProxy
///                                   .{NETWORK}.oracle.chainlink.feeToken
///
/// Writes:
///   script/config/networks.json  → .{NETWORK}.deployments.dataStreamsOracle
///
/// Usage:
///   NETWORK=base DEPLOY_VERSION=v1 forge script script/l2/DeployChainlinkOracle.s.sol \
///     --rpc-url $RPC_URL --broadcast
contract DeployChainlinkOracleL2 is NetworkConfig {
    /// @dev Canonical CreateX factory address (same on all EVM chains).
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory network = vm.envString("NETWORK");
        string memory version = vm.envString("DEPLOY_VERSION");

        string memory json = _configJson();

        // --- Data Streams addresses (per-chain; env overrides config) ---
        address verifierProxy = vm.envOr("CL_VERIFIER_PROXY", _clAddr(json, network, "verifierProxy"));
        address feeToken       = vm.envOr("CL_FEE_TOKEN",      _clAddr(json, network, "feeToken"));

        // --- preflight: skip chains without Data Streams config ---
        if (verifierProxy == address(0)) {
            console.log("SKIP:", network, "- no Data Streams verifierProxy configured");
            return;
        }

        // --- preflight: skip if verifierProxy not deployed on this chain ---
        uint256 codeSize;
        assembly { codeSize := extcodesize(verifierProxy) }
        if (codeSize == 0) {
            console.log("SKIP:", network, "- verifierProxy has no code");
            console.log("  verifierProxy:", verifierProxy);
            return;
        }

        // --- config ---
        uint256 maxTimeDrift = _oracleMaxTimeDrift(network);

        address owner = vm.addr(deployerKey);
        ICreateX createx = ICreateX(CREATEX);

        // --- salt ---
        // Distinct entropy ("ChainlinkOracle-") from PythOracle so the two land on different
        // deterministic CREATE3 addresses. CreateX salt format / guard identical to DeployPythOracle.
        bytes32 salt = bytes32(abi.encodePacked(
            bytes20(0), bytes1(0),
            bytes11(keccak256(abi.encodePacked("ChainlinkOracle-", version)))
        ));

        // --- predict address ---
        bytes32 guardedSalt = keccak256(abi.encode(salt));
        address predicted = createx.computeCreate3Address(guardedSalt);
        console.log("Predicted address:", predicted);

        // --- deploy ---
        bytes memory initCode = abi.encodePacked(
            type(ChainlinkOracle).creationCode,
            abi.encode(owner, maxTimeDrift, verifierProxy, feeToken)
        );

        vm.startBroadcast(deployerKey);
        address deployed = createx.deployCreate3(salt, initCode);
        vm.stopBroadcast();

        require(deployed == predicted, "address mismatch");

        _writeDeployment(network, "dataStreamsOracle", deployed);

        console.log("Network:", network);
        console.log("ChainlinkOracle deployed at", deployed);
        console.log("VerifierProxy:", verifierProxy);
        console.log("FeeToken:", feeToken);
        console.log("Salt:", vm.toString(salt));
    }

    /// @dev Reads .{network}.oracle.chainlink.{key} as an address; returns address(0) if absent.
    ///      (Same tolerant try/catch idiom as script/l1/CreateProviders.s.sol.)
    function _clAddr(string memory json, string memory network, string memory key)
        internal
        returns (address)
    {
        try vm.parseJsonAddress(json, string.concat(".", network, ".oracle.chainlink.", key))
            returns (address a)
        {
            return a;
        } catch {
            return address(0);
        }
    }
}
