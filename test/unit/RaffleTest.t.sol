// SPDX-Licence-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /** Events */
    event Raffle__playerEntered(address indexed PLAYER);
    event Raffle__winnerPicked(address indexed winner);

    Raffle raffle;
    HelperConfig helperConfig;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 calbackGasLimit;
    address linkToken;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle raffleDeployer = new DeployRaffle();
        console.log("Deploying Raffle");
        (raffle, helperConfig) = raffleDeployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            calbackGasLimit,
            ,

        ) = helperConfig.activeNetworkConfig();
        console.log("Raffle deployed at ", address(raffle));
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitialisesInOpenState() public view {
        assert(raffle.getLotteryState() == Raffle.LotteryState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        // Arange
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughFunds.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        raffle.enterRaffle{value: entranceFee}();
        assert(raffle.getPlayer(0) == PLAYER);
        // Assert
    }

    function testEmitsEventOnEntrance() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectEmit(true, false, false, false, address(raffle));
        emit Raffle__playerEntered(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange in modifier

        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle__LotteryNotOpen.selector);
        vm.prank(PLAYER); // why is this needed?
        raffle.enterRaffle{value: entranceFee}();
    }

    /////////////////////
    // ckeckUpkeep tests
    /////////////////////
    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(upKeepNeeded == false);
    }

    function testCheckUpKeepReturnsFalseIfRaffleNotOpen()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange in modifier
        raffle.performUpkeep("");

        // Act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assert(upKeepNeeded == false);
    }

    function testCheckUpKeepReturnsFalseIfEnoughtHasntPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // Act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assert(upKeepNeeded == false);
    }

    function testCheckUpKeepReturnsTrueWhenParamsAreGood()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange in modifier

        // Act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assert(upKeepNeeded);
    }

    /////////////////////
    // performUpkeep tests
    /////////////////////

    function testPerformUpKeepCanOnlyRunIfcheckUpKeepIsTrue()
        public
        raffleEnteredAndTimePassed
    {
        // Arange in modifier
        // Act / Assert
        raffle.performUpkeep("");
    }

    function testPerformUpKeepRevertsIfCheckUpKeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numberPlayers = 0;
        uint256 lotteryState = 0;
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numberPlayers,
                lotteryState
            )
        );
        raffle.performUpkeep("");
    }

    // Testing using the output of an event
    function testPerformUpKeepUpdateRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange in modifier
        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emit Raffle__RequestedRaffleWinner(requestId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.LotteryState lotteryState = raffle.getLotteryState();

        // Assert
        assert(uint256(requestId) > 0);
        assert(lotteryState == Raffle.LotteryState.CALCULATING);
    }

    function testFulfilRandomWordsCanOnlyBeCalledAfterPerformUpKeep(
        uint256 randomRequestId
    ) public raffleEnteredAndTimePassed skipFork {
        // Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfilRandomWordsPicksAWinnerResetAndSendMoney()
        public
        raffleEnteredAndTimePassed
        skipFork
    {
        // Arrange
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1; // because modifier has already entered one PLAYER

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE); // hoax == prank + deal
            raffle.enterRaffle{value: entranceFee}();
        }

        vm.recordLogs();
        raffle.performUpkeep("");

        uint256 prize = entranceFee * (additionalEntrants + 1);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();
        // pretend to be chainlink VRF to get a random number and pick a winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        assert(raffle.getLotteryState() == Raffle.LotteryState.OPEN);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getPlayerLength() == 0);
        assert(raffle.getLastTimeStamp() > previousTimeStamp);
        assert(
            raffle.getRecentWinner().balance ==
                STARTING_USER_BALANCE + prize - entranceFee
        );
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }
}
