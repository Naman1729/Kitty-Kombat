// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { VRFConsumerBaseV2Plus, IVRFCoordinatorV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract KittyCombat is ERC721, VRFConsumerBaseV2Plus {
    using Strings for uint256;
    // errors
    error KittyCombat__IncorrectFeesSent();

    // enums
    enum VirusType {
        Whisker_Woes,        // 70
        Furrball_Fiasco,     // 25
        Clawdemic            // 5    (deadliest)
    }

    // structs
    struct CatInfection {
        bool isInfected;
        uint256 lockupDuration;
        uint256 infectedBy;  // virus token id
        uint256 healedBy;    // token id of angel cat
        uint256 bridgeTimestamp;
        uint256 chainIdForHealLockUp;
        uint256 coolDownDeadline;
    }

    struct CatInfo {
        uint256 tokenId;
        uint256 immunity;
        uint256 lives;
        CatInfection catInfectionInfo;
        uint256 colour;
        bool isAngelCat;
    }

    struct VirusInfo {
        uint256 tokenId;
        VirusType virusType;
        uint256 strength;
        uint256 growthFactor;
        uint256 coolDownDeadline;
        uint256[] infectedTokenIds;
    }

    struct IndexRoleInfo {
        uint256 index;
        bool isCat;
    }

    // variables
    address public immutable i_cattyNip;
    uint256 public constant MAX_COOLDOWN_DEADLINE = 5 days;
    uint256 public constant MAX_IMMUNITY = 100;
    uint256 public constant INIT_LIVES = 9;
    uint256 public tokenIdToMint = 1;
    CatInfo[] public catInfo;
    VirusInfo[] public virusInfo;
    uint256 public constant INIT_FEE = 0.001 ether;
    uint256 public constant FEE_LINEAR_INC = 0.0001 ether;
    uint256 public currentFee; 
    uint256 public constant MAX_STRENGTH = 10000;
    uint256 public constant MAX_GROWTH_FACTOR = 10;
    uint256 public constant MAX_COLOUR = 7;
    mapping(uint256 tokenId => IndexRoleInfo indexInfo) public tokenIdToIndexInfo;
    mapping(uint256 reqId => address user) public reqIdToUser;
    string[] public VIRUS_TYPE_ARR = ["Whisker Woes", "Furrball Fiasco", "Clawdemic"];
    uint256[] public selectedChainIds;

    // chainlink vrd parameters
    bytes32 public keyHash;
    uint32 public callbackGaslimit;
    uint16 public requestConfirmations;
    uint32 public numWords = 2;
    uint256 public subscriptionId;


    // events
    event MintRequested(uint256 requestId, address user);
    event CatMinted(uint256 tokenId, address user);
    event VirusMinted(uint256 tokenId, address user);

    constructor(
        address _cattyNip, 
        address _vrfCoordinator, 
        uint32 _callbackGaslimit, 
        uint16 _requestConfirmations,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint256[] memory _selectedChainIds
    ) ERC721("KittyCombat", "KC") VRFConsumerBaseV2Plus(_vrfCoordinator) {
        i_cattyNip = _cattyNip;
        currentFee = INIT_FEE;
        keyHash = _keyHash;
        callbackGaslimit = _callbackGaslimit;
        requestConfirmations = _requestConfirmations;
        subscriptionId = _subscriptionId;
        selectedChainIds = _selectedChainIds;
    }

    function mintKittyOrVirus() external payable {
        uint256 _fee = currentFee;

        if (msg.value != _fee) {
            revert KittyCombat__IncorrectFeesSent();
        }

        currentFee += FEE_LINEAR_INC;

        // Request chainlink vrf for 2 random numbers
        // first will be used to decide a cat(80) or a virus(20)
        
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGaslimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: false
                    })
                )
            })
        );

        reqIdToUser[requestId] = msg.sender;

        emit MintRequested(requestId, msg.sender);
    }

    function attack(uint256 attackerVirusTokenId, uint256 catTokenId) external {
        IndexRoleInfo memory _virusInfo = tokenIdToIndexInfo[attackerVirusTokenId];
        IndexRoleInfo memory _catInfo =  tokenIdToIndexInfo[catTokenId];

        CatInfo storage _cat = catInfo[_catInfo.index];
        VirusInfo storage _virus = virusInfo[_virusInfo.index];

        require(_virusInfo.isCat == false && _catInfo.isCat == true && !_cat.isAngelCat, "Invalid token ids");
        require(_ownerOf(attackerVirusTokenId) == msg.sender, "Only owner can attack");
        require(block.timestamp > virusInfo[_virusInfo.index].coolDownDeadline, "Virus is on cooldown");
        require(block.timestamp > catInfo[_catInfo.index].catInfectionInfo.coolDownDeadline && !catInfo[_catInfo.index].catInfectionInfo.isInfected, "Cat is on cooldown");

        _cat.catInfectionInfo.isInfected = true;
        _cat.catInfectionInfo.infectedBy = attackerVirusTokenId;
        _virus.infectedTokenIds.push(catTokenId);

        uint256 mod;
        uint256 inc;
        if (_virus.virusType == VirusType.Whisker_Woes) {
            mod = 70;
            inc = 0;
        }
        else if (_virus.virusType == VirusType.Furrball_Fiasco) {
            mod = 25;
            inc = 70;
        }
        else {
            mod = 5;
            inc = 95;
        }

        uint256 x = _virus.strength % mod;
        uint256 virusImm = x + inc;

        if (_cat.immunity > virusImm) {
            revert("Cat immune to virus");
        }

        uint256 immDiff = (virusImm - _cat.immunity);
    

        _cat.catInfectionInfo.lockupDuration = immDiff * 3 hours;
        _cat.catInfectionInfo.chainIdForHealLockUp = selectedChainIds[immDiff % selectedChainIds.length];
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address user = reqIdToUser[requestId];

        _mint(user, tokenIdToMint);
        // 1. decide whether to mint a cat or a virus
        uint256 catOrVirus = randomWords[0] % 100;
        uint256 traitsDeciding = randomWords[1];
        if (catOrVirus < 80) {
            // mint a cat
            catInfo.push(CatInfo({
                tokenId: tokenIdToMint,
                immunity: traitsDeciding % MAX_IMMUNITY,
                lives: INIT_LIVES,
                catInfectionInfo: CatInfection({
                    isInfected: false,
                    lockupDuration: 0,
                    infectedBy: 0,
                    healedBy: 0,
                    bridgeTimestamp: 0,
                    chainIdForHealLockUp: 0,
                    coolDownDeadline: block.timestamp + MAX_COOLDOWN_DEADLINE
                }),
                colour: traitsDeciding % MAX_COLOUR,
                isAngelCat: false
            }));

            tokenIdToIndexInfo[tokenIdToMint] = IndexRoleInfo({
                index: catInfo.length - 1,
                isCat: true
            });

            emit CatMinted(tokenIdToMint, user);
        }
        else {
            // mint a virus
            virusInfo.push(VirusInfo({
                tokenId: tokenIdToMint,
                virusType: VirusType(traitsDeciding % 3),
                strength: traitsDeciding % MAX_STRENGTH,
                growthFactor: traitsDeciding % MAX_GROWTH_FACTOR,
                coolDownDeadline: block.timestamp + MAX_COOLDOWN_DEADLINE - 3 days,
                infectedTokenIds: new uint256[](0)
            }));

            tokenIdToIndexInfo[tokenIdToMint] = IndexRoleInfo({
                index: virusInfo.length - 1,
                isCat: false
            });

            emit VirusMinted(tokenIdToMint, user);
        }
        tokenIdToMint++;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "data:application/json;base64,";
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (tokenId >= tokenIdToMint) {
            return "";
        }

        if(tokenIdToIndexInfo[tokenId].isCat) {
            CatInfo memory cat = catInfo[tokenIdToIndexInfo[tokenId].index];
            return string(abi.encodePacked(
                _baseURI(),
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name": "', cat.isAngelCat ? "Angel Cat" : "Cat", 
                            '", "tokenId": "', tokenId.toString(), 
                            '", "immunity": "', cat.immunity.toString(),
                            '", "lives": "', cat.lives.toString(),
                            '", "isInfected": "', cat.catInfectionInfo.isInfected ? 'true' : 'false',
                            '", "colour": "', cat.colour.toString(),
                            '"}'
                        )
                    )
                )
            ));
        }
        else {
            VirusInfo memory virus = virusInfo[tokenIdToIndexInfo[tokenId].index];
            return string(abi.encodePacked(
                _baseURI(),
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name": "Virus',
                            '", "tokenId": "', tokenId.toString(),
                            '", "virusType": "', VIRUS_TYPE_ARR[uint256(virus.virusType)],
                            '", "strength": "', virus.strength.toString(),
                            '", "growthFactor": "', virus.growthFactor.toString(),
                            '"}'
                        )
                    )
                )
            ));
        }
    }
}