// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { VRFConsumerBaseV2Plus, IVRFCoordinatorV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

contract KittyCombat is ERC721, VRFConsumerBaseV2Plus, CCIPReceiver {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    // errors
    error KittyCombat__IncorrectFeesSent();
    error KittyCombat__NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); 
    error KittyCombat__SourceChainNotAllowlisted(uint64 sourceChainSelector); 
    error KittyCombat__SenderNotAllowlisted(address sender);

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
        uint64 chainSelectorForHealLockUp;
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

    struct CatHealParams {
        uint256 lockUpDeadline;
        address catOwner;
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
    uint64[] public selectedChainSelectors;
    mapping(uint256 tokenId => mapping(uint64 sourceChainSelector => CatHealParams)) public healParams;


    // chainlink vrf parameters
    bytes32 public keyHash;
    uint32 public vrfCallbackGaslimit;
    uint16 public requestConfirmations;
    uint32 public numWords = 2;
    uint256 public subscriptionId;

    // chainlink ccip parameters
    mapping(uint64 => bool) public allowlistedSourceChains;
    mapping(address => bool) public allowlistedSenders;
    IERC20 private s_linkToken;
    mapping(uint64 chainSelector => address destAddr) public chainSelectorToDestAddr;
    uint256 public gasLimit1 = 300_000;
    uint256 public gasLimit2 = 400_000;


    // events
    event MintRequested(uint256 requestId, address user);
    event CatMinted(uint256 tokenId, address user);
    event VirusMinted(uint256 tokenId, address user);
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector, 
        address receiver,
        bytes data,
        address feeToken,
        uint256 fees
    );

    event MessageReceived(
        bytes32 indexed messageId, 
        uint64 indexed sourceChainSelector,
        address sender
    );

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!allowlistedSourceChains[_sourceChainSelector])
            revert KittyCombat__SourceChainNotAllowlisted(_sourceChainSelector);
        if (!allowlistedSenders[_sender]) revert KittyCombat__SenderNotAllowlisted(_sender);
        _;
    }

    constructor(
        address _cattyNip, 
        address _vrfCoordinator, 
        uint32 _vrfCallbackGaslimit, 
        uint16 _requestConfirmations,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        address _ccipRouter,
        address _link
    ) ERC721("KittyCombat", "KC") VRFConsumerBaseV2Plus(_vrfCoordinator) CCIPReceiver(_ccipRouter) {
        i_cattyNip = _cattyNip;
        currentFee = INIT_FEE;
        keyHash = _keyHash;
        vrfCallbackGaslimit = _vrfCallbackGaslimit;
        requestConfirmations = _requestConfirmations;
        subscriptionId = _subscriptionId;
        s_linkToken = IERC20(_link);
    }

    function setDestAddr(uint64[] memory _selectedChainSelectors, address[] memory _destinationAddresses) external onlyOwner {
        require(_selectedChainSelectors.length == _destinationAddresses.length, "Invalid input");

        for (uint256 i = 0; i < _selectedChainSelectors.length; i++) {
            selectedChainSelectors.push(_selectedChainSelectors[i]);
            chainSelectorToDestAddr[_selectedChainSelectors[i]] = _destinationAddresses[i];
        }
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
                callbackGasLimit: vrfCallbackGaslimit,
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
        _virus.coolDownDeadline = block.timestamp + 3 days;

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
        _cat.catInfectionInfo.chainSelectorForHealLockUp = selectedChainSelectors[immDiff % selectedChainSelectors.length];
    }

    function bridgeCatForHeal(uint256 catTokenId) external returns (bytes32 messageId) {
        // check for token id, for ownership, and cat is actualled infected
        CatInfo storage _cat = catInfo[tokenIdToIndexInfo[catTokenId].index];
        require(_cat.catInfectionInfo.isInfected, "Cat is not infected");
        require(_ownerOf(catTokenId) == msg.sender, "Only owner can bridge");
        require(_cat.catInfectionInfo.bridgeTimestamp == 0, "Cat already bridged");

        _cat.catInfectionInfo.bridgeTimestamp = block.timestamp;

        uint64 _destinationChainSelector = _cat.catInfectionInfo.chainSelectorForHealLockUp;
        address _receiver = chainSelectorToDestAddr[_destinationChainSelector];
        bool _isMessageForHeal = true;

        bytes memory _data = abi.encode(_isMessageForHeal, catTokenId, _cat.catInfectionInfo.lockupDuration, _ownerOf(catTokenId));

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _data,
            address(s_linkToken),
            gasLimit1
        );

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        s_linkToken.transferFrom(msg.sender, address(this), fees);

        s_linkToken.approve(address(router), fees);

        messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        emit MessageSent(
            messageId,
            _destinationChainSelector,
            _receiver,
            _data,
            address(s_linkToken),
            fees
        );
    }

    function bridgeHealedCatBackToSourceChain(uint256 catTokenIdBasedSourceChain, uint64 sourceChainSelector) external returns (bytes32 messageId) {
        CatHealParams memory _healParams = healParams[catTokenIdBasedSourceChain][sourceChainSelector];
        require(block.timestamp > _healParams.lockUpDeadline, "Cat is still under healing lockup");
        require(msg.sender == _healParams.catOwner, "Only cat owner can bridge healed cat back");

        address _receiver = chainSelectorToDestAddr[sourceChainSelector];

        bool _isMessageForHeal = false;
        bytes memory _data = abi.encode(_isMessageForHeal, catTokenIdBasedSourceChain, _healParams.lockUpDeadline);

        delete healParams[catTokenIdBasedSourceChain][sourceChainSelector];

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _data,
            address(s_linkToken),
            gasLimit2
        );

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(sourceChainSelector, evm2AnyMessage);

        s_linkToken.transferFrom(msg.sender, address(this), fees);

        s_linkToken.approve(address(router), fees);

        messageId = router.ccipSend(sourceChainSelector, evm2AnyMessage);

        emit MessageSent(
            messageId,
            sourceChainSelector,
            _receiver,
            _data,
            address(s_linkToken),
            fees
        );
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address))) {
        bool _isMessageForHeal;
        bytes memory _data = any2EvmMessage.data;
        assembly {
            _isMessageForHeal := mload(add(_data, 0x20))
        }

        // handling for healing on destination chain
        if (_isMessageForHeal) {
            (, uint256 catTokenId, uint256 lockupDuration, address catOwner) = abi.decode(_data, (bool, uint256, uint256, address));

            healParams[catTokenId][any2EvmMessage.sourceChainSelector] = CatHealParams({
                lockUpDeadline: block.timestamp + lockupDuration,
                catOwner: catOwner
            });
        }
        // handling for settling healed cat back to source chain
        else {
            (, uint256 catTokenIdBasedSourceChain, uint256 lockUpDeadline) = abi.decode(_data, (bool, uint256, uint256));
            CatInfo storage _cat = catInfo[tokenIdToIndexInfo[catTokenIdBasedSourceChain].index];

            _cat.lives -= 1;
            _cat.catInfectionInfo.isInfected = false;
            _cat.catInfectionInfo.lockupDuration = 0;
            _cat.catInfectionInfo.infectedBy = 0;
            _cat.catInfectionInfo.bridgeTimestamp = 0;
            _cat.catInfectionInfo.chainSelectorForHealLockUp = 0;
            _cat.catInfectionInfo.coolDownDeadline = lockUpDeadline + MAX_COOLDOWN_DEADLINE;

            if (_cat.lives == 0) {
                _cat.isAngelCat = true;
            }
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address))
        );
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
                    chainSelectorForHealLockUp: 0,
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
                coolDownDeadline: block.timestamp + MAX_COOLDOWN_DEADLINE - 2 days,
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

    function allowlistSourceChain(
        uint64 _sourceChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }

    function allowlistSender(address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
    }

    function withdrawFees() external onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success);
    }

    function setVrfCallbackGasLimit(uint32 _vrfCallbackGasLimit) external onlyOwner {
        vrfCallbackGaslimit = _vrfCallbackGasLimit;
    }

    function setGaslimit1(uint256 _gasLimit1) external onlyOwner {
        gasLimit1 = _gasLimit1;
    }

    function setGaslimit2(uint256 _gasLimit2) external onlyOwner {
        gasLimit2 = _gasLimit2;
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

    function _buildCCIPMessage(
        address _receiver,
        bytes memory _data,
        address _feeTokenAddress,
        uint256 _gasLimit
    ) private pure returns (Client.EVM2AnyMessage memory) {
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver),
                data: _data,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV1({gasLimit: _gasLimit})
                ),
                feeToken: _feeTokenAddress
            });
    }

    function supportsInterface(bytes4 interfaceId) public pure override(ERC721, CCIPReceiver) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}