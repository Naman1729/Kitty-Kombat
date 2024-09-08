// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {Test, console} from "forge-std/Test.sol";
import {KittyCombat} from "../src/KittyCombat.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract KittyCombatTest is Test {
    address user;
    LinkToken link;
    bytes32 keyHash;
    address ccipRouter;
    uint256 subscriptionId;
    uint32 vrfCallbackGaslimit;
    uint16 requestConfirmations;
    KittyCombat public kittyCombat;
    VRFCoordinatorV2_5Mock vrfCoordinator;
    uint256 constant INIT_FEE = 0.001 ether;
    uint256 public constant FEE_LINEAR_INC = 0.0001 ether;
    address owner = makeAddr("owner");

    function setUp() external {
        vm.startPrank(owner);
        link = new LinkToken();
        vrfCoordinator = new VRFCoordinatorV2_5Mock(0.0001 ether, 1e7, 45e15);

        requestConfirmations = 3;
        keyHash = 0x83250c5584ffa93feb6ee082981c5ebe484c865196750b39835ad4f13780435d;
        subscriptionId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(subscriptionId, 10 ether);
        ccipRouter = 0xF694E193200268f9a4868e4Aa017A0118C9a8177;
        vrfCallbackGaslimit = 300_000;

        kittyCombat = new KittyCombat(
            address(vrfCoordinator),
            vrfCallbackGaslimit,
            requestConfirmations,
            subscriptionId,
            keyHash,
            ccipRouter,
            address(link)
        );
        vrfCoordinator.addConsumer(subscriptionId, address(kittyCombat));
        user = makeAddr("user");
        vm.stopPrank();
    }

    function test_constructor() external view {
        assert(INIT_FEE == kittyCombat.currentFee());
        assert(vrfCallbackGaslimit == kittyCombat.vrfCallbackGaslimit());
        assert(requestConfirmations == kittyCombat.requestConfirmations());
        assert(subscriptionId == kittyCombat.subscriptionId());
        assert(keyHash == kittyCombat.keyHash());
    }

    function test_mintKittyOrVirusIfUserNotHaveEnoughFee() external {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                KittyCombat.KittyCombat__IncorrectFeesSent.selector
            )
        );
        kittyCombat.mintKittyOrVirus();
        vm.stopPrank();
    }

    function test_mintKittyOrVirus() external {
        vm.startPrank(user);
        uint256 fee = kittyCombat.currentFee();
        vm.deal(user, fee);
        kittyCombat.mintKittyOrVirus{value: fee}();
        vm.stopPrank();

        assert(user == kittyCombat.reqIdToUser(1));
        assertEq(fee + FEE_LINEAR_INC, kittyCombat.currentFee());
    }

    function test_setDestAddrIfCallerIsNotOwner() external {
        vm.startPrank(user);
        uint64[] memory _selectedChainSelectors = new uint64[](1);
        address[] memory _destinationAddresses = new address[](1);

        vm.expectRevert();
        kittyCombat.setDestAddr(_selectedChainSelectors, _destinationAddresses);
        vm.stopPrank();
    }

    function test_setDestAddrIfLengthIsNotSame() external {
        vm.startPrank(owner);
        uint64[] memory _selectedChainSelectors = new uint64[](1);
        address[] memory _destinationAddresses = new address[](2);

        _selectedChainSelectors[0] = 1;
        _destinationAddresses[0] = address(0x1);
        _destinationAddresses[1] = address(0x2);

        vm.expectRevert("Invalid input");
        kittyCombat.setDestAddr(_selectedChainSelectors, _destinationAddresses);
    }

    function test_setDestAddr() external {
        vm.startPrank(owner);
        uint64[] memory _selectedChainSelectors = new uint64[](1);
        address[] memory _destinationAddresses = new address[](1);
        _selectedChainSelectors[0] = 1;
        _destinationAddresses[0] = address(0x1);
        kittyCombat.setDestAddr(_selectedChainSelectors, _destinationAddresses);

        assert(
            _selectedChainSelectors[0] == kittyCombat.selectedChainSelectors(0)
        );
        assert(
            _destinationAddresses[0] ==
                kittyCombat.chainSelectorToDestAddr(
                    kittyCombat.selectedChainSelectors(0)
                )
        );
    }

    function test_setVrfCallbackGasLimit(uint32 _vrfCallbackGaslimit) external {
        vm.startPrank(owner);
        kittyCombat.setVrfCallbackGasLimit(_vrfCallbackGaslimit);

        assert(_vrfCallbackGaslimit == kittyCombat.vrfCallbackGaslimit());
    }

    function test_setVrfCallbackGasLimitIfCallerIsNotOwner() external {
        uint32 _vrfCallbackGaslimit = 100000;
        vm.expectRevert();
        kittyCombat.setVrfCallbackGasLimit(_vrfCallbackGaslimit);
    }

    function test_setGaslimit1(uint256 _gasLimit1) external {
        vm.startPrank(owner);
        kittyCombat.setGaslimit1(_gasLimit1);

        assert(_gasLimit1 == kittyCombat.gasLimit1());
    }

    function test_setGaslimit1IfCallerIsNotOwner(uint256 _gasLimit1) external {
        vm.expectRevert();
        kittyCombat.setGaslimit1(_gasLimit1);
    }

    function test_setGaslimit2(uint256 _gasLimit2) external {
        vm.startPrank(owner);
        kittyCombat.setGaslimit2(_gasLimit2);

        assert(_gasLimit2 == kittyCombat.gasLimit2());
    }

    function test_setGaslimit2IfCallerIsNotOwner(uint256 _gasLimit2) external {
        vm.expectRevert();
        kittyCombat.setGaslimit2(_gasLimit2);
    }

    function test_mintKittyOrVirusFor20Participants() external {
        uint256 numberOfCats = 0;
        uint256 numberOfViruses = 0;

        for (uint256 i = 0; i < 20; i++) {
            string memory _name = string(
                abi.encodePacked("user", Strings.toString(i))
            );
            address tempUser = makeAddr(_name);
            vm.startPrank(tempUser);
            vm.deal(tempUser, kittyCombat.currentFee());

            kittyCombat.mintKittyOrVirus{value: kittyCombat.currentFee()}();
            vrfCoordinator.fulfillRandomWords(i + 1, address(kittyCombat));
            (, bool isCat) = kittyCombat.tokenIdToIndexInfo(i + 1);
            if (isCat) {
                numberOfCats++;
            } else {
                numberOfViruses++;
            }
            vm.stopPrank();
        }

        console.log("Number of Cats: ", numberOfCats);
        console.log("Number of Viruses: ", numberOfViruses);

        string memory tempName = string(
            abi.encodePacked("user", Strings.toString(19))
        );
        assert(makeAddr(tempName) == kittyCombat.reqIdToUser(20));
        assertEq(kittyCombat.currentFee(), INIT_FEE + (FEE_LINEAR_INC * 20));
    }

    function test_withdrawFeesIfCallerIsNotOwner() external {
        vm.startPrank(user);
        vm.expectRevert();
        kittyCombat.withdrawFees();
        vm.stopPrank();
    }

    function test_withdrawFees() external {
        vm.startPrank(owner);
        uint256 fee = kittyCombat.currentFee();
        vm.deal(owner, fee);

        kittyCombat.mintKittyOrVirus{value: fee}();
        uint256 balance = address(kittyCombat).balance;
        uint256 balanceOwner = address(owner).balance;
        kittyCombat.withdrawFees();

        assertEq(0, address(kittyCombat).balance);
        assert(balance != address(kittyCombat).balance);
        assert(balance + balanceOwner == address(owner).balance);
        vm.stopPrank();
    }

    function test_setPerLockupTime(uint256 _perLockupTime) external {
        vm.startPrank(owner);
        kittyCombat.setPerLockupTime(_perLockupTime);

        assert(_perLockupTime == kittyCombat.perLockupTime());
    }

    function test_setPerLockupTimeIfCallerIsNotOwner() external {
        uint256 _perLockupTime = 2 days;
        vm.expectRevert();
        kittyCombat.setPerLockupTime(_perLockupTime);
    }

    function test_allowlistSourceChainIfCallerIsNotOwner() external{ 
        uint64 sourceChainSelector = 11155111;
        vm.expectRevert();
        kittyCombat.allowlistSourceChain(sourceChainSelector, true);
    }
    function test_allowlistSourceChain() external {
        vm.startPrank(owner);
        uint64 sourceChainSelector = 11155111;
        kittyCombat.allowlistSourceChain(sourceChainSelector, true);
        vm.stopPrank();
        assertEq(kittyCombat.allowlistedSourceChains(sourceChainSelector), true);
    }

    function test_allowlistSenderIfCallerIsNotOwner() external{
        vm.expectRevert();
        kittyCombat.allowlistSender(user, true);
    }
    function test_allowlistSender() external{
        vm.startPrank(owner);
        kittyCombat.allowlistSender(user, true);
        vm.stopPrank();
        assertEq(kittyCombat.allowlistedSenders(user), true);
    }

    function test_setCooldownDeadlineIfCallerIsNotOwner() external{
        uint256 coolDownDeadline = 2 days;
        vm.expectRevert();
        kittyCombat.setCooldownDeadline(coolDownDeadline);
    }

    function test_setCooldownDeadline() external{
        vm.startPrank(owner);
        uint256 coolDownDeadline = 2 days;
        kittyCombat.setCooldownDeadline(coolDownDeadline);
        vm.stopPrank();
        assertEq(kittyCombat.cooldownDeadline(), coolDownDeadline);
    }

    function test_setCooldownDeadlineMoreThanMaxCooldownDeadline() external{
        vm.startPrank(owner);
        uint256 coolDownDeadline = 6 days;
        vm.expectRevert("Invalid cooldown deadline");
        kittyCombat.setCooldownDeadline(coolDownDeadline);
        vm.stopPrank();
    }

    modifier mintKittyOrVirusFor10Participants() {
        for (uint256 i = 0; i < 10; i++) {
            string memory _name = string(
                abi.encodePacked("user", Strings.toString(i))
            );
            address tempUser = makeAddr(_name);
            vm.startPrank(tempUser);
            vm.deal(tempUser, kittyCombat.currentFee());

            kittyCombat.mintKittyOrVirus{value: kittyCombat.currentFee()}();
            vrfCoordinator.fulfillRandomWords(i + 1, address(kittyCombat));
            (, bool isCat) = kittyCombat.tokenIdToIndexInfo(i + 1);
            vm.stopPrank();
        }
        _;
    }
    
    function test_attackIfAttackerIsCat() external mintKittyOrVirusFor10Participants {
        address attacker = makeAddr(string(abi.encodePacked("user", Strings.toString(1))));
        vm.startPrank(attacker);
        vm.expectRevert("Invalid token ids");
        kittyCombat.attack(1, 2);
        vm.stopPrank();
    }

    function test_attackIfAttackerIsNotOwner() external mintKittyOrVirusFor10Participants {
        vm.expectRevert("Only owner can attack");
        kittyCombat.attack(8, 2);
    }

    function test_attackWhenAttackerIsOnCooldown() external mintKittyOrVirusFor10Participants {
        address attacker = makeAddr(string(abi.encodePacked("user", Strings.toString(7))));
        uint256 attackerVirusTokenId = 8;
        uint256 catTokenId = 2;
        vm.startPrank(owner);
        kittyCombat.setCooldownDeadline(1 minutes);
        vm.stopPrank();
        vm.startPrank(attacker);
        vm.expectRevert("Virus is on cooldown");
        kittyCombat.attack(attackerVirusTokenId, catTokenId);
        vm.stopPrank();
    }

    function test_attack() external mintKittyOrVirusFor10Participants {
        address attacker = makeAddr(string(abi.encodePacked("user", Strings.toString(7))));
        uint256 attackerVirusTokenId = 8;
        uint256 catTokenId = 2;
        uint64[] memory _selectedChainSelectors = new uint64[](1);
        _selectedChainSelectors[0] = 1;
        address[] memory _destinationAddresses = new address[](1);
        _destinationAddresses[0] = address(0x1);
        vm.startPrank(owner);
        kittyCombat.setCooldownDeadline(1 minutes);
        kittyCombat.setDestAddr(_selectedChainSelectors, _destinationAddresses);
        vm.stopPrank();
        vm.startPrank(attacker);
        vm.warp(block.timestamp + kittyCombat.cooldownDeadline());
        kittyCombat.attack(attackerVirusTokenId, catTokenId);
        vm.stopPrank();
    }
    
    function test_bridgeCatForHealIfCatIsNotInfected() external mintKittyOrVirusFor10Participants {
        uint256 catTokenId = 1;
        vm.expectRevert("Cat is not infected");
        kittyCombat.bridgeCatForHeal(catTokenId);
    }
    function test_bridgeCatForHealIfCallerIsNotCatOwner() external mintKittyOrVirusFor10Participants {
        address attacker = makeAddr(string(abi.encodePacked("user", Strings.toString(7))));
        uint256 attackerVirusTokenId = 8;
        uint256 catTokenId = 2;
        uint64[] memory _selectedChainSelectors = new uint64[](1);
        _selectedChainSelectors[0] = uint64(block.chainid);
        address[] memory _destinationAddresses = new address[](1);
        _destinationAddresses[0] = address(kittyCombat);
        
        vm.startPrank(owner);
        kittyCombat.setCooldownDeadline(1 minutes);
        kittyCombat.setDestAddr(_selectedChainSelectors, _destinationAddresses);
        vm.stopPrank();
        
        vm.startPrank(attacker);
        vm.warp(block.timestamp + kittyCombat.cooldownDeadline());
        kittyCombat.attack(attackerVirusTokenId, catTokenId);
        vm.stopPrank();
        
        vm.expectRevert("Only owner can bridge");
        kittyCombat.bridgeCatForHeal(catTokenId);
    }
}
