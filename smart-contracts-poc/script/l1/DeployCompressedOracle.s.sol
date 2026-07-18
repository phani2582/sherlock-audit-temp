// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {NetworkConfig} from "../NetworkConfig.sol";
import {CompressedOracleV1} from "../../contracts/oracles/compressed/CompressedOracle.sol";

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

/// @notice Deploy CompressedOracleV1 via CREATE3 on Ethereum L1.
///
/// ENV:
///   PRIVATE_KEY     – deployer private key (becomes oracle owner/admin)
///   DEPLOY_VERSION  – version string for salt entropy (e.g. "v1")
///
/// Writes:
///   script/config/networks.json  → .ethereum.deployments.compressedOracle
///
/// Usage:
///   DEPLOY_VERSION=v1 forge script script/l1/DeployCompressedOracle.s.sol --rpc-url $ETH_RPC --broadcast
contract DeployCompressedOracleL1 is NetworkConfig {
    string constant NETWORK = "ethereum";
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory version = vm.envString("DEPLOY_VERSION");
        address owner = vm.addr(deployerKey);

        ICreateX createx = ICreateX(CREATEX);

        // --- salt ---
        // CreateX salt format: [20 bytes sender] [1 byte flags] [11 bytes entropy]
        // address(0) prefix = permissionless, 0x00 flag = no cross-chain redeploy protection.
        // _guard() hashes this salt: guardedSalt = keccak256(abi.encode(salt)).
        // computeCreate3Address expects the guarded (post-_guard) salt.
        bytes32 salt = bytes32(abi.encodePacked(
            bytes20(0), bytes1(0),
            bytes11(keccak256(abi.encodePacked("CompressedOracleV1-", version)))
        ));

        // --- predict address ---
        bytes32 guardedSalt = keccak256(abi.encode(salt));
        address predicted = createx.computeCreate3Address(guardedSalt);
        console.log("Predicted address:", predicted);

        // --- deploy ---
        bytes memory initCode = abi.encodePacked(
            type(CompressedOracleV1).creationCode,
            abi.encode(owner)
        );

        vm.startBroadcast(deployerKey);
        address deployed = createx.deployCreate3(salt, initCode);
        vm.stopBroadcast();

        require(deployed == predicted, "address mismatch");

        _writeDeployment(NETWORK, "compressedOracle", deployed);

        console.log("CompressedOracleV1 deployed at", deployed);
        console.log("Owner:", owner);
        console.log("Salt:", vm.toString(salt));
    }
}
