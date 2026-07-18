// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {PythLazer} from "pyth-lazer-sdk/PythLazer.sol";
import {PythLazerLib, PythLazerStructs} from "pyth-lazer-sdk/PythLazerLib.sol";
import {CompressedOracleV1} from "../contracts/oracles/compressed/CompressedOracle.sol";
import {PriceProvider} from "../contracts/PriceProvider.sol";
import {PriceProviderFactory} from "../contracts/PriceProviderFactory.sol";
import {PriceProviderFactoryL2} from "../contracts/PriceProviderFactoryL2.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";


contract DebugT is Test {

    address owner;
    address trustedSigner;
    PythLazer pythLazer;

    function setUp() external {
        trustedSigner = 0x26FB61A864c758AE9fBA027a96010480658385B9;
        owner = makeAddr("owner");

        PythLazer pythLazerImpl = new PythLazer();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(pythLazerImpl), owner, abi.encodeWithSelector(PythLazer.initialize.selector, owner)
        );
        pythLazer = PythLazer(address(proxy));

        vm.prank(owner);
        pythLazer.updateTrustedSigner(trustedSigner, 3000000000000000);
    }

    function test_debug_payload() external {
        bytes memory _update = hex"2a22999afb21346176b21712cdc9f8a199083a73112375b4c635c01b98f4417aed3dfba752ea9a72ec71d4a3322e3626ac69c11c4910fb69774417e29e434f9e57a2527e00005c93c7d37500064b3d48c4a8c003030000000703000000000005f5cb7f04fff8050000000000003e8f00000001030000000629bc9c73ba04fff805000000006111a25d0000000203000000002d9996ffcb04fff8050000000002204ae5";
        
        (bytes memory payload,) = pythLazer.verifyUpdate{value: 1}(_update);

        PythLazerLib.parseUpdateFromPayload(payload);
    }

    function test_debug_allow() external {

        vm.prank(0xB973b814A43EE884f5BFB5464036c9b3D9e4c942);
        vm.etch(0x9553b47efb53dcb6bf2319f5701453FEB941e85a, address(0xc72D1F81Da10C9491B21E8061Be10b8496EA60a5).code);
        (bool ok, bytes memory res) = address(0x9553b47efb53dcb6bf2319f5701453FEB941e85a).call(hex"eff77369000000000000000000000000000000000000000000000000000000006d51b89500000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a52feec3bad001007e71405c4a9816ef864339a9");
    }

    function test_debug_proxy() external {
        vm.createSelectFork("https://eth-mainnet.g.alchemy.com/v2/JOTalIT7XvCk43yCtK8sX");
        // vm.prank(0xB973b814A43EE884f5BFB5464036c9b3D9e4c942);
        bytes memory cd = hex"6e7c6a3900000000000000000000000000000000000000000000000000000000000000600000000000000000000000005ecf662abb8c2ab099862f9ef2ddc16cbc8a99770000000000000000000000003221901709f01737a601f9f02a01df6b13b2a6ff000000000000000000000000000000000000000000000000000000000000002469a99f7200000000fafa00000000fafa00000000fafa00000000fafa00019cbe817bf30000000000000000000000000000000000000000000000000000000000";
        (bool ok, bytes memory res) = address(0x5886BAD65ab1380Fc17bD64A962a784bA1a90b70).call(cd);
    }

    function test_pp() external {
        vm.createSelectFork("https://eth-mainnet.g.alchemy.com/v2/JOTalIT7XvCk43yCtK8sX");

        address[] memory providers = new address[](1);
        providers[0] = 0xB336269ea7b7Aa1038bd9BEaf51e5bDA2B83e782;

        PriceProvider(providers[0]).getBidAndAskPrice();
    }

    function test_old() external {
        vm.createSelectFork("https://eth-mainnet.g.alchemy.com/v2/JOTalIT7XvCk43yCtK8sX");
        (bool ok, bytes memory res) = address(0xaeA1773d7ba9eF4aFC9581D18cccFe6Acd8768f5).staticcall(abi.encodeWithSignature("magicNumber()"));
        require(ok);

        console2.log(abi.decode(res, (uint256)));
    }

    
    function test_view_pp() external {
        vm.createSelectFork("https://eth-mainnet.g.alchemy.com/v2/JOTalIT7XvCk43yCtK8sX");

        PriceProvider pp = PriceProvider(0xb6387f2Beb37fB2FC5F9d5b05704a632C3f9a801);

        console2.log("cex step", pp.marginStep());
        CompressedOracleV1(address(pp.offchainOracle())).getOracleData(pp.offchainFeedId());

        pp.getBidAndAskPrice();

    }
}


