// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @author  Vaibhav Goyal
 * @title   Sample Raffel Contract
 * @dev     This contract is a sample contract for Raffel.
 * @notice  Implements Chainlink VRFv2.5
 */

contract Raffel is VRFConsumerBaseV2Plus {
    /** ERROR */
    error Raffel__SendMoreETHtoEnterRaffel();
    error Raffel__TrnsferFailedToWinner();
    error Raffel__RaffelNotOpen();
    error Raffel__UpkeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffelState
    );

    /** Type Declarations */
    enum RaffelState {
        OPEN, //0
        CALCULATING // 1
    }

    /** STATE VARIABLES */
    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    // @dev interval in seconds
    uint256 private immutable i_intervalForLottery;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffelState private s_raffelState;

    constructor(
        uint256 entranceFee,
        uint256 intervalForLottery,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_intervalForLottery = intervalForLottery;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffelState = RaffelState.OPEN;
    } //VRFConsumerBaseV2Plus has a constructor so we can add that the others contract's constructor like shown above

    /** EVENTS */
    event Raffel__Entered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffelWinner(uint256 indexed requestId);

    /**FUNCTIONS */
    function enterRaffel() public payable {
        // require(
        //     msg.value >= i_entranceFee,
        //     "Not enough ETH to enter the raffel"
        // ); cost more gas because of the error message as a string
        if (msg.value < i_entranceFee) {
            revert Raffel__SendMoreETHtoEnterRaffel();
        }

        if (s_raffelState != RaffelState.OPEN) {
            revert Raffel__RaffelNotOpen();
        }
        s_players.push(payable(msg.sender)); // push the player to array
        emit Raffel__Entered(msg.sender); // emit the event
    }

    /**
     * @notice  .
     * @dev     This is the function that chain;ink nodes will call to check if the lottery is ready to pick the winner.
    The following should be true in oreder of upkeepNeeded to be true:
    1. The timeInterval has passed between the raffel runs
    2. The raffel state is OPEN
    3. The contract has ETH
    4. Implicitly, your subscription has LINK
     * @param   -Ignored  .
     * @return  upkeepNeeded - true if its time to restart the lottery .
     * @return  bytes  .
     */
    function checkUpkeep(
        bytes memory /* callData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_intervalForLottery);
        bool raffelIsOpen = s_raffelState == RaffelState.OPEN;
        bool contractHasETH = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded =
            timeHasPassed &&
            raffelIsOpen &&
            contractHasETH &&
            hasPlayers;
        return (upkeepNeeded, "");
    }

    // 1.get a random number
    // 2.Use the random number to pick a winner
    // 3.Automate the process by automatically calling the pickWinner function
    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffel__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffelState)
            );
        }

        s_raffelState = RaffelState.CALCULATING;
        // Get a random number from Chainlink VRFv2.5
        //1. Request a RNG
        //2. Get RNG
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATION,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        //VRFV2PlusClient.RandomWordsRequest is a special type of struct declared in the VRFV2PlusClient library
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffelWinner(requestId);
        // s_vrfCoordinator is a state variable inherited from VRFConsumerBaseV2Plus
        // it is of type IVRFCoordinatorV2Plus in which requestRandomWords is a function
    }

    // 4. Implement the fulfillRandomWords function, here we will pick a winner

    // CEI: Check-Effects-Interactions
    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] calldata randomWords
    ) internal override {
        //Checks
        // requires,conditionals

        //Effects(internal contract state)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        s_raffelState = RaffelState.OPEN;
        emit WinnerPicked(s_recentWinner);

        //Interactions(external contract Interaction)
        (bool successMsg, ) = payable(s_recentWinner).call{
            value: address(this).balance
        }("");
        if (!successMsg) {
            revert Raffel__TrnsferFailedToWinner();
        }
    }

    /** GETTER FUNCTION */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffelState() external view returns (RaffelState) {
        return s_raffelState;
    }

    function getPlayersLength() external view returns (uint256) {
        return s_players.length;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getWinner() external view returns (address) {
        return s_recentWinner;
    }
}
