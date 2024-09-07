// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { KittyCombat } from "src/KittyCombat.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

// Avanalanche Fuji - 0xF1470EF915C5FB9095c5AAdB2d44964ab63c8f96
// Arbitrum Sepolia - 0xafB70ecc8EE4b38047ADE26d0212ee4FC440d869

contract DeployKittyCombat is Script {
    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getNetworkConfig();
        KittyCombat kittyCombat;

        vm.startBroadcast();


        if (block.chainid == 43113) {
            kittyCombat = KittyCombat(0xF1470EF915C5FB9095c5AAdB2d44964ab63c8f96);

            uint64[] memory chainSelectors = new uint64[](1);
            address[] memory destAddrs = new address[](1);
            chainSelectors[0] = networkConfig.arbSepoliaChainSelector;    
            destAddrs[0] = 0xafB70ecc8EE4b38047ADE26d0212ee4FC440d869;

            kittyCombat.allowlistSender(0xafB70ecc8EE4b38047ADE26d0212ee4FC440d869, true);
            kittyCombat.allowlistSourceChain(networkConfig.arbSepoliaChainSelector, true);
            kittyCombat.setDestAddr(chainSelectors, destAddrs);
        }
        else {
            kittyCombat = KittyCombat(0xafB70ecc8EE4b38047ADE26d0212ee4FC440d869);
            
            uint64[] memory chainSelectors = new uint64[](1);
            address[] memory destAddrs = new address[](1);
            chainSelectors[0] = networkConfig.avalancheFujiChainSelector;    
            destAddrs[0] = 0xF1470EF915C5FB9095c5AAdB2d44964ab63c8f96;

            kittyCombat.allowlistSender(0xF1470EF915C5FB9095c5AAdB2d44964ab63c8f96, true);
            kittyCombat.allowlistSourceChain(networkConfig.avalancheFujiChainSelector, true);
            kittyCombat.setDestAddr(chainSelectors, destAddrs);
        }

        vm.stopBroadcast();
    }
}