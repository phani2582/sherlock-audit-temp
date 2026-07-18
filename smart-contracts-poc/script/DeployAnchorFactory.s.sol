// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {NetworkConfig} from "./NetworkConfig.sol";
import {AnchoredProviderFactory} from "../contracts/AnchoredProviderFactory.sol";

/// @dev Minimal CreateX interface for CREATE3 deployment.
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

/// @notice Deploy an AnchoredProviderFactory via CREATE3 for deterministic addresses.
///         One factory instance per reference oracle (the proposal's PythAnchorFactory /
///         ChainlinkAnchorFactory) — REFERENCE picks which oracle this instance anchors to.
///         CREATE3 addresses ignore initCode, so the same REFERENCE + DEPLOY_VERSION yields the
///         same factory address on every chain even though the oracle constructor arg differs.
///
/// ENV:
///   PRIVATE_KEY     – deployer private key (becomes factory ADMIN_ROLE)
///   NETWORK         – network name (key in script/config/networks.json)
///   DEPLOY_VERSION  – version string for salt entropy (e.g. "v1")
///   REFERENCE       – "pyth" | "chainlink" | "compressed" — reference oracle family
///   ORACLE          – (optional) overrides the networks.json oracle lookup
///
/// Writes:
///   script/config/networks.json  → .{NETWORK}.deployments.{REFERENCE}AnchorFactory
///
/// Usage:
///   NETWORK=base DEPLOY_VERSION=v1 REFERENCE=chainlink \
///     forge script script/DeployAnchorFactory.s.sol --rpc-url $RPC_URL --broadcast
contract DeployAnchorFactory is NetworkConfig {
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory network = vm.envString("NETWORK");
        string memory version = vm.envString("DEPLOY_VERSION");
        string memory ref = vm.envString("REFERENCE");
        address owner = vm.addr(deployerKey);

        // Validate REFERENCE on BOTH paths (it feeds the salt + registry key, not just the lookup),
        // so an ORACLE override can't silently produce a non-canonical salt with a bad reference.
        string memory oracleKey = _oracleKey(ref);

        address oracle = vm.envOr("ORACLE", address(0));
        if (oracle == address(0)) {
            oracle = _deployment(network, oracleKey);
        }
        // An empty "oracle" entry in networks.json decodes to a nonzero sentinel (0x...20), so the
        // address(0) guard alone is not enough; require real bytecode at the resolved oracle. This
        // catches empty/typo entries before they burn the one-shot canonical CREATE3 address.
        require(oracle != address(0), "set ORACLE or deploy the reference oracle first");
        require(oracle.code.length > 0, "resolved oracle has no code (empty/typo networks.json entry?)");

        ICreateX createx = ICreateX(CREATEX);

        // --- salt ---
        // CreateX salt format: [20 bytes sender] [1 byte flags] [11 bytes entropy]
        // address(0) prefix = permissionless, 0x00 flag = no cross-chain redeploy protection.
        // _guard() hashes this salt: guardedSalt = keccak256(abi.encode(salt)).
        // computeCreate3Address expects the guarded (post-_guard) salt.
        bytes32 salt = bytes32(abi.encodePacked(
            bytes20(0), bytes1(0),
            bytes11(keccak256(abi.encodePacked("AnchoredProviderFactory-", ref, "-", version)))
        ));

        // --- predict address ---
        bytes32 guardedSalt = keccak256(abi.encode(salt));
        address predicted = createx.computeCreate3Address(guardedSalt);
        console.log("Predicted address:", predicted);

        // --- deploy ---
        bytes memory initCode = abi.encodePacked(
            type(AnchoredProviderFactory).creationCode,
            abi.encode(owner, oracle)
        );

        vm.startBroadcast(deployerKey);
        address deployed = createx.deployCreate3(salt, initCode);
        vm.stopBroadcast();

        require(deployed == predicted, "address mismatch");

        _writeDeployment(network, string.concat(ref, "AnchorFactory"), deployed);

        console.log("Network:", network);
        console.log("Reference oracle:", oracle);
        console.log("Anchor factory deployed at", deployed);
        console.log("Salt:", vm.toString(salt));
    }

    /// @dev networks.json deployments key per reference family: PythOracle is registered as
    ///      "oracle", ChainlinkOracle (Data Streams) as "dataStreamsOracle", CompressedOracle
    ///      (self-contained, for chains without Pyth/Chainlink infra) as "compressedOracle".
    function _oracleKey(string memory ref) internal pure returns (string memory) {
        bytes32 r = keccak256(bytes(ref));
        if (r == keccak256("pyth")) return "oracle";
        if (r == keccak256("chainlink")) return "dataStreamsOracle";
        if (r == keccak256("compressed")) return "compressedOracle";
        revert("REFERENCE must be 'pyth', 'chainlink' or 'compressed'");
    }
}
