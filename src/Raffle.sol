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
pragma solidity ^0.8.20;
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A simple raffle contract
 * @author YehoudaB
 * @notice this contract is for learning purposes only
 * @dev Implements Chainlink VRF V2 and Chainlink Automation
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughFunds();
    error Raffle__TransferFailed();
    error Raffle__LotteryNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        LotteryState state
    );

    /** type declaration */
    enum LotteryState {
        OPEN,
        CALCULATING
    }

    /** State variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    // @dev Duration of the lottery in seconds
    uint256 private immutable i_interval;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    /**  @dev gasLane is the keyHash in chainlink doc */
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_calbackGasLimit;
    address payable private recentWinner;
    LotteryState private s_lotteryState;

    /** Events */
    event Raffle__playerEntered(address indexed player);
    event Raffle__winnerPicked(address indexed winner);
    event Raffle__RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 calbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_calbackGasLimit = calbackGasLimit;
        s_lotteryState = LotteryState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughFunds();
        }
        if (s_lotteryState != LotteryState.OPEN) {
            revert Raffle__LotteryNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit Raffle__playerEntered(msg.sender);
    }

    /**
     *
     * @dev this is the  function that the chainlink Automation node will call to see
     * if it's time to perform an upkeep
     * the following should be true for this to return true:
     *  1. the time interval has passed between lotterie runs
     *  2. the lottery is in the OPEN state
     *  3. the contract has ETH (aka, players)
     *  4. (implicitly) The subscription is funded with LINK
     */
    function checkUpkeep(
        bytes calldata /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool lotteryIsOpen = s_lotteryState == LotteryState.OPEN;
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timeHasPassed &&
            lotteryIsOpen &&
            hasPlayers &&
            hasBalance);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata performData) external {
        (bool upkeepNeeded, ) = checkUpkeep(performData); // https://youtu.be/sas02qSFZ74?si=6PkTLKWmx-iqCDIl&t=16939
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                s_lotteryState
            );
        }

        s_lotteryState = LotteryState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_calbackGasLimit,
            NUM_WORDS
        );
        emit Raffle__RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /* _requestId */,
        uint256[] memory _randomWords
    ) internal override {
        uint256 indexOfWinner = _randomWords[0] % s_players.length;
        recentWinner = s_players[indexOfWinner];
        s_lastTimeStamp = block.timestamp;
        s_players = new address payable[](0);
        s_lotteryState = LotteryState.OPEN;
        emit Raffle__winnerPicked(recentWinner);
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**  Getter functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getLotteryState() external view returns (LotteryState) {
        return s_lotteryState;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getRecentWinner() external view returns (address) {
        return recentWinner;
    }

    function getPlayerLength() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
