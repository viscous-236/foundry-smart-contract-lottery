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

pragma solidity ^0.8.18;

// import {VRFConsumerBaseV2Plus} from "@chainlink/contracts@1.3.0/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";

/**
 * @author  Vaibhav Goyal
 * @title   Sample Raffel Contract
 * @dev     This contract is a sample contract for Raffel.
 * @notice  Implements Chainlink VRFv2.5
 */

contract Raffel {
    /** ERROR */
    error Raffel__SendMoreETHtoEnterRaffel();

    /** STATE VARIABLES */
    uint256 private immutable i_entranceFee;
    // @dev interval in seconds
    uint256 private immutable i_intervalForLottery;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;

    constructor(uint256 entranceFee, uint256 intervalForLottery) {
        i_entranceFee = entranceFee;
        i_intervalForLottery = intervalForLottery;
        s_lastTimeStamp = block.timestamp;
    }

    /** EVENTS */
    event Raffel__Entered(address indexed player);

    /**FUNCTIONS */
    function enterRaffel() public payable {
        // require(
        //     msg.value >= i_entranceFee,
        //     "Not enough ETH to enter the raffel"
        // ); cost more gas because of the error message as a string
        if (msg.value < i_entranceFee) {
            revert Raffel__SendMoreETHtoEnterRaffel();
        }
        s_players.push(payable(msg.sender)); // push the player to array
        emit Raffel__Entered(msg.sender); // emit the event
    }

    // 1.get a random number
    // 2.Use the random number to pick a winner
    // 3.Automate the process by automatically calling the pickWinner function
    function pickWinner() public {
        if ((block.timestamp - s_lastTimeStamp) < i_intervalForLottery) {
            revert();
        }
        // Get a random number from Chainlink VRFv2.5
        //1. Request a RNG
        //2. Get RNG
        // requestId = s_vrfCoordinator.requestRandomWords(
        //     VRFV2PlusClient.RandomWordsRequest({
        //         keyHash: s_keyHash,
        //         subId: s_subscriptionId,
        //         requestConfirmations: requestConfirmations,
        //         callbackGasLimit: callbackGasLimit,
        //         numWords: numWords,
        //         extraArgs: VRFV2PlusClient._argsToBytes(
        //             // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
        //             VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
        //         )
        //     })
        // );
    }

    /** GETTER FUNCTION */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }
}
