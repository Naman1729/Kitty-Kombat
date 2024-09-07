// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address _vrfCoordinator;
        uint256 _subscriptionId;
        bytes32 _keyHash;
        address _ccipRouter;
        address _link;
        uint64 avalancheFujiChainSelector;
        uint64 arbSepoliaChainSelector;
    }

    NetworkConfig private networkConfig;

    constructor() {
        if (block.chainid == 43113) {
            setAvalancheFujiConfig();
        }
        else if (block.chainid == 421614) {
            setArbitrumSepoliaConfig();
        }
    }

    function setAvalancheFujiConfig() internal {
        networkConfig = NetworkConfig({
            _vrfCoordinator: 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE,
            _subscriptionId: 93849518357465269678837244623482242722379179533955684596858073734069220968326,
            _keyHash: 0xc799bd1e3bd4d1a41cd4968997a4e03dfd2a3c7c04b695881138580163f42887,
            _ccipRouter: 0xF694E193200268f9a4868e4Aa017A0118C9a8177,
            _link: 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846,
            avalancheFujiChainSelector: 14767482510784806043,
            arbSepoliaChainSelector: 3478487238524512106
        });
    }

    function setArbitrumSepoliaConfig() internal {
        networkConfig = NetworkConfig({
            _vrfCoordinator: 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61,
            _subscriptionId: 8423322005455333394606656323561384006414869976422455313092127678173703439320,
            _keyHash: 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be,
            _ccipRouter: 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165,
            _link: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E,
            avalancheFujiChainSelector: 14767482510784806043,
            arbSepoliaChainSelector: 3478487238524512106
        });
    }

    function getNetworkConfig() external view returns (NetworkConfig memory) {
        return networkConfig;
    }
}