// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { KittyCombat } from "src/KittyCombat.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

// 0xF1c8170181364DeD1C56c4361DED2eB47f2eef1b

contract DeployKittyCombat is Script {
    function run() external returns (KittyCombat) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getNetworkConfig();
        uint16 requestConfirmations = 3;
        uint32 vrfCallbackGaslimit = 400_000;

        vm.startBroadcast();

        KittyCombat kittyCombat = new KittyCombat(
            networkConfig._vrfCoordinator,
            vrfCallbackGaslimit,
            requestConfirmations,
            networkConfig._subscriptionId,
            networkConfig._keyHash,
            networkConfig._ccipRouter,
            networkConfig._link
        );

        vm.stopBroadcast();

        return kittyCombat;
    }
}