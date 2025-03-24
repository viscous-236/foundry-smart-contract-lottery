//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Raffel} from "src/Raffel.sol";
import {DeployRaffel} from "script/DeployRaffel.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffelTest is Test, CodeConstants {
    Raffel public raffel;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 intervalForLottery;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    event Raffel__Entered(address indexed player);
    event WinnerPicked(address indexed winner);

    modifier raffelEntered() {
        vm.prank(PLAYER);
        vm.deal(PLAYER, entranceFee);
        raffel.enterRaffel{value: entranceFee}();
        vm.warp(block.timestamp + intervalForLottery + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier paidForEntranceFee() {
        vm.prank(PLAYER);
        vm.deal(PLAYER, entranceFee);
        _;
    }

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function setUp() external {
        DeployRaffel deployer = new DeployRaffel();
        (raffel, helperConfig) = deployer.DeployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        intervalForLottery = config.intervalForLottery;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testInitailRaffelState() public view {
        assert(raffel.getRaffelState() == Raffel.RaffelState.OPEN);
    }
    /*//////////////////////////////////////////////////////////////
                            ENTER RAFFEL
    //////////////////////////////////////////////////////////////*/
    function testRaffelRevertWhenNotPayedWithEnoughETH() public {
        //ARRANGE
        vm.prank(PLAYER);
        //ACT/ASSERT
        vm.expectRevert(Raffel.Raffel__SendMoreETHtoEnterRaffel.selector);
        raffel.enterRaffel();
    }

    function testRaffelStoresPLayersWhenTheyEnter() public paidForEntranceFee {
        //ARRANGE
        //ACT
        raffel.enterRaffel{value: entranceFee}();
        vm.prank(PLAYER);
        vm.deal(PLAYER, entranceFee);
        raffel.enterRaffel{value: entranceFee}();
        //ASSERT
        assert(raffel.getPlayersLength() == 2);
    }

    function testRaffelRecordPlayersWhenTheyEnter() public paidForEntranceFee {
        //ARRANGE
        //ACT
        raffel.enterRaffel{value: entranceFee}();
        //ASSERT
        assert(raffel.getPlayer(0) == PLAYER);
    }

    function testEnteringRaffelEmitsEvent() public paidForEntranceFee {
        // ARRANGE
        // ACT
        vm.expectEmit(true, false, false, false, address(raffel));
        emit Raffel__Entered(PLAYER);
        // ASSERT
        raffel.enterRaffel{value: entranceFee}();
    }

    function testRaffelRevertsWhenNotOpen() public paidForEntranceFee {
        // ARRANGE
        raffel.enterRaffel{value: entranceFee}();
        vm.warp(block.timestamp + intervalForLottery + 1);
        vm.roll(block.number + 1);
        raffel.performUpkeep("");
        // ACT/ASSERT
        vm.expectRevert(Raffel.Raffel__RaffelNotOpen.selector);
        vm.prank(PLAYER);
        vm.deal(PLAYER, entranceFee);
        raffel.enterRaffel{value: entranceFee}();
    }

    /*//////////////////////////////////////////////////////////////
                            CHECKUPKEEP
    //////////////////////////////////////////////////////////////*/

    function testCheckUpkeepReturnsFalseWhenContractHasNoETH() public {
        //ARRANGE
        vm.warp(block.timestamp + intervalForLottery + 1);
        vm.roll(block.number + 1);
        //ACT
        (bool upkeepNeeded, ) = raffel.checkUpkeep("");
        //ASSERT
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseWhenContractIsNotOpen()
        public
        paidForEntranceFee
    {
        //ARRANGE
        raffel.enterRaffel{value: entranceFee}();
        vm.warp(block.timestamp + intervalForLottery + 1);
        vm.roll(block.number + 1);
        raffel.performUpkeep("");

        //ACT
        (bool upkeepNeeded, ) = raffel.checkUpkeep("");
        //ASSERT
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseWhenTimeHasNotPasses()
        public
        paidForEntranceFee
    {
        //ARRANGE
        raffel.enterRaffel{value: entranceFee}();
        //ACT
        (bool upkeepNeeded, ) = raffel.checkUpkeep("");
        //ASSERT
        assert(!upkeepNeeded);
    }

    /*//////////////////////////////////////////////////////////////
                            PERFORMUPKEEP
    //////////////////////////////////////////////////////////////*/

    function testPerformUpkeepRevertsWhenUpkeepNeededIsFalse()
        public
        paidForEntranceFee
    {
        // ARRANGE
        raffel.enterRaffel{value: entranceFee}();

        // ACT/ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffel.Raffel__UpkeepNotNeeded.selector,
                address(raffel).balance,
                raffel.getPlayersLength(),
                uint256(raffel.getRaffelState())
            )
        );
        raffel.performUpkeep("");
    }

    //What if we need to get data from emmited events in our tests?
    function testPerformUpkeepUpdatesRaffelStateAndEmitRequestId()
        public
        paidForEntranceFee
    {
        //ARRANGE
        raffel.enterRaffel{value: entranceFee}();
        vm.warp(block.timestamp + intervalForLottery + 1);
        vm.roll(block.number + 1);

        //ACT
        vm.recordLogs(); // will keep track of all events and logs emitted by this performUpkeep
        raffel.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /**
        struct Log {
        // The topics of the log, including the signature, if any.
        bytes32[] topics;
        // The raw data of the log.
        bytes data;
        // The address of the log's emitter.
        address emitter;
        } */
        bytes32 requestId = entries[1].topics[1]; //entries[0] is for VRFCoordinator
        // and top[0] is always reserved for something else.
        Raffel.RaffelState raffelState = raffel.getRaffelState();
        assert(uint256(raffelState) == 1);
        assert(requestId > 0);
    }

    /*//////////////////////////////////////////////////////////////
                            FULFILLRANDOMWORDS
    //////////////////////////////////////////////////////////////*/
    // function testFulfillRandomWordsCanOlyBeCalledAfterPerformUpkeep()
    //     public
    //     raffelEntered
    // {
    //     //ARRANGE/ACT/ASSERT
    //     vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
    //     VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
    //         0,
    //         address(raffel)
    //     );
    //     // Here we have taken request id 0 but we can check for 1,2,3,4,5,6,7,8,9,10 etc
    //     // So for this we have fuzz testing
    // }

    function testFulfillRandomWordsCanOlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffelEntered skipFork {
        //ARRANGE/ACT/ASSERT
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffel)
        );
    } // This Fuzz test will run 256 times byDefault for different requestIds
    // This is a example of stateless Fuzz test
    //Only VRF Coordinator can call fulfillRandomWords
    //We use VRFCoordinatorV2_5Mock.fulfillRandomWords instead of calling raffel.fulfillRandomWords directly because fulfillRandomWords is meant to be called only by Chainlink VRF (the coordinator). and as we are using local environment we are using VRFCoordinatorV2_5Mock to simulate the Chainlink response by manually calling fulfillRandomWords.

    function testFulfillRandomWordsPicsAWinnerResetsAndSendMoney()
        public
        raffelEntered
        skipFork
    {
        //ARRANGE
        uint256 additionalEntries = 3; // Total 4 entries
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntries;
            i++
        ) {
            address newPlayer = address(uint160(i)); // address
            hoax(newPlayer, 1 ether);
            raffel.enterRaffel{value: entranceFee}();
        }
        uint256 startingTimeStamp = raffel.getLastTimeStamp();
        uint256 winnerStarttingBalance = expectedWinner.balance;

        //ACT
        vm.recordLogs();
        raffel.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffel)
        );

        //ASSERT
        address recentWinner = raffel.getWinner();
        Raffel.RaffelState raffelState = raffel.getRaffelState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffel.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntries + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffelState) == 0); // RaffelState.OPEN
        assert(winnerBalance == winnerStarttingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
    //     We use VRFCoordinatorV2_5Mock.fulfillRandomWords instead of calling raffel.fulfillRandomWords directly because fulfillRandomWords is meant to be called only by Chainlink VRF (the coordinator).

    // ⸻

    // Why Call VRFCoordinatorV2_5Mock.fulfillRandomWords?
    // 	1.	Chainlink VRF calls fulfillRandomWords automatically
    // 	•	The fulfillRandomWords function in Raffel.sol is a callback function that Chainlink VRF calls when it provides randomness.
    // 	•	The smart contract itself does not have permission to call it directly.
    // 	2.	Mocking the Chainlink VRF Behavior
    // 	•	Since we are testing in a local environment (Foundry), there’s no real Chainlink VRF to call fulfillRandomWords.
    // 	•	Instead, we use VRFCoordinatorV2_5Mock to simulate the Chainlink response by manually calling fulfillRandomWords.
    // 	3.	VRF Security: Only the Coordinator Can Call It
    // 	•	The fulfillRandomWords function in Raffel.sol has a modifier (or require check) that ensures only the Chainlink VRF Coordinator can call it.
    // 	•	If we try calling raffel.fulfillRandomWords(...) directly, it would revert due to access control.

    // ⸻
}
