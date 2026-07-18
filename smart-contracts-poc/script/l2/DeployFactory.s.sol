// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {NetworkConfig} from "../NetworkConfig.sol";
import {PriceProviderFactoryL2} from "../../contracts/PriceProviderFactoryL2.sol";

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

/// @notice Deploy PriceProviderFactoryL2 via CREATE3 for deterministic addresses.
///
/// ENV:
///   PRIVATE_KEY     – deployer private key (becomes factory admin)
///   NETWORK         – network name (arbitrum, base, linea, optimism)
///   DEPLOY_VERSION  – version string for salt entropy (e.g. "v1")
///
/// Writes:
///   script/config/networks.json  → .{NETWORK}.deployments.factory
///
/// Usage:
///   NETWORK=base DEPLOY_VERSION=v1 forge script script/l2/DeployFactory.s.sol \
///     --rpc-url $RPC_URL --broadcast
contract DeployFactoryL2 is NetworkConfig {
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory network = vm.envString("NETWORK");
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
            bytes11(keccak256(abi.encodePacked("PriceProviderFactory-", version)))
        ));

        // --- predict address ---
        bytes32 guardedSalt = keccak256(abi.encode(salt));
        address predicted = createx.computeCreate3Address(guardedSalt);
        console.log("Predicted address:", predicted);

        // --- deploy ---
        bytes memory initCode = abi.encodePacked(
            type(PriceProviderFactoryL2).creationCode,
            abi.encode(owner)
        );

        vm.startBroadcast(deployerKey);
        address deployed = createx.deployCreate3(salt, initCode);
        vm.stopBroadcast();

        require(deployed == predicted, "address mismatch");

        _writeDeployment(network, "factory", deployed);

        console.log("Network:", network);
        console.log("Factory deployed at", deployed);
        console.log("Salt:", vm.toString(salt));
    }
}
