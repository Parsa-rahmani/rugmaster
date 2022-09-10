pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "hardhat/console.sol";

contract RugRace is Ownable {
    using Counters for Counters.Counter;
    // ----- State Variables -----
    Counters.Counter private gameId;

    mapping(uint256 => mapping(uint256 => uint256)) public gameToPodToTimeRugged;

    mapping(uint256 => address[]) public gameToParticipants;
    mapping(uint256 => GameInfo) public gameToGameInfo;
    mapping(uint256 => mapping(uint256 => PodInfo)) public gameToPodToPodInfo;
    mapping(uint256 => uint256) public gameToUnusedFunds;

    struct GameInfo {
        uint128 startTime;
        uint128 endTime;
        uint256 podNum;
        uint256 podSize;
        uint256 numParticipants;
        uint256 funding;
        uint256 fundingPerPod;
        uint256 bonus;
        uint256 podsRemaining;
        bool finalized;
    }

    struct PodInfo {
        uint256 rugTime;
        address rugger;
        address[] participants;
    }

    mapping(address => uint256[]) public userToGamesParticipated;
    mapping(address => mapping(uint256 => uint256)) public userToGameToPod;
    mapping(address => uint256) public userToClaimable;

    uint256 public constant MIN_DURATION = 30 minutes;
    uint256 public constant MAX_POD_NUMBER = 50;

    // ----- Modifiers -----

    modifier noGameActive() {
        require(block.timestamp >= gameToGameInfo[gameId.current()].endTime, "!ended");
        _;
    }

    modifier gameActive() {
        require(
            block.timestamp < gameToGameInfo[gameId.current()].endTime && block.timestamp >= gameToGameInfo[gameId.current()].startTime,
            "!ended"
        );
        _;
    }

    modifier finalized() {
        require(gameToGameInfo[gameId.current()].finalized, "!finalized");
        _;
    }

    // ----- Construction -----

    constructor() {
        // So we can start the first game
        gameToGameInfo[0].finalized = true;
    }

    // ----- Owner Functions -----

    function startGame(
        address[] memory _participants,
        uint128 _startTime,
        uint128 _endTime,
        uint256 _podNum,
        uint256 _funding,
        uint256 _bonus
    ) external payable onlyOwner noGameActive finalized {
        require(_endTime > _startTime + MIN_DURATION, "!duration");
        require(_startTime >= block.timestamp, "!future");
        require(_participants.length % _podNum == 0, "!even");
        require(_podNum <= MAX_POD_NUMBER, "!podNum");

        require(_funding > 0, "!funding");
        require(msg.value == _funding + _bonus, "!value");

        gameId.increment();
        uint256 currentGame = gameId.current();

        GameInfo storage params = gameToGameInfo[currentGame];
        uint256 podSize = _participants.length / _podNum;
        params.startTime = _startTime;
        params.endTime = _endTime;
        params.podNum = _podNum;
        params.podSize = podSize;
        params.numParticipants = _participants.length;
        params.funding = _funding;
        params.fundingPerPod = _funding / _podNum;
        params.bonus = _bonus;
        params.podsRemaining = _podNum;

        _participants = shuffle(_participants);

        gameToParticipants[currentGame] = _participants;

        for (uint256 pod = 1; pod <= _podNum; ) {
            PodInfo storage podInfo = gameToPodToPodInfo[currentGame][pod];
            for (uint256 i = (pod - 1) * podSize; i < pod * podSize; ) {
                userToGamesParticipated[_participants[i]].push(currentGame);
                userToGameToPod[_participants[i]][currentGame] = pod;
                podInfo.participants.push(_participants[i]);

                // STUB - emit event

                unchecked {
                    ++i;
                }
            }
            unchecked {
                ++pod;
            }
        }

        // STUB - Emit event
    }

    function closeout() external onlyOwner noGameActive {
        uint256 currentGame = gameId.current();
        GameInfo storage game = gameToGameInfo[currentGame];

        // Determine the number of pods have not rugged
        uint256 numPods = game.podNum;
        uint256 numUnrugged = game.podsRemaining;

        // Record the pod numbers
        uint256 counter;
        uint256[] memory unruggedPods = new uint256[](numUnrugged);
        for (uint256 i = 1; i <= numPods; ) {
            if (gameToPodToPodInfo[currentGame][i].rugTime == 0) {
                unruggedPods[counter] = i;
                unchecked {
                    ++counter;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Distribute bonuses to unrugged pods, if any
        uint256 bonusPerPod = numUnrugged > 0 ? game.bonus / numUnrugged : 0;
        if (bonusPerPod > 0) {
            for (uint256 i = 0; i < numUnrugged; ) {
                distributeBonus(currentGame, unruggedPods[i], bonusPerPod);
                unchecked {
                    ++i;
                }
            }
        }

        // Withdraw leftover funds to owner
        uint256 leftovers = gameToUnusedFunds[currentGame] + game.fundingPerPod * numUnrugged;
        gameToUnusedFunds[currentGame] = 0;
        payable(owner()).transfer(leftovers);

        // Finalize the game
        game.finalized = true;

        // STUB - Event
    }

    // ----- Public Functions -----

    function rug() external gameActive {
        uint256 currentGame = gameId.current();
        uint256 pod = userToGameToPod[msg.sender][currentGame];
        require(pod > 0, "!player");

        PodInfo storage podInfo = gameToPodToPodInfo[currentGame][pod];
        require(podInfo.rugTime == 0, "!ruggable");

        podInfo.rugTime = block.timestamp;
        podInfo.rugger = msg.sender;

        GameInfo storage game = gameToGameInfo[currentGame];
        game.podsRemaining--;

        uint256 payout = currentPayout();
        uint256 leftovers = game.fundingPerPod - payout;
        gameToUnusedFunds[currentGame] += leftovers;

        userToClaimable[msg.sender] += payout;

        // STUB - Emit events
    }

    function claim() external {
        uint256 amount = userToClaimable[msg.sender];
        require(amount > 0, "!amount");
        userToClaimable[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        // STUB - emit event
    }

    // ----- Internal Functions -----

    // STUB - make it actually shuffle later
    function shuffle(address[] memory _participants) internal view returns (address[] memory) {
        return _participants;
    }

    function distributeBonus(
        uint256 _gameId,
        uint256 _podId,
        uint256 _amount
    ) internal {
        address[] memory members = gameToPodToPodInfo[_gameId][_podId].participants;

        uint256 len = members.length;
        uint256 payoutPerUser = _amount / len;
        for (uint256 i; i < len; ++i) {
            userToClaimable[members[i]] += payoutPerUser;
            // STUB - Emit Event
        }
        // STUB - Emit Events
    }

    // ----- View Functions -----

    function currentPayout() public view returns (uint256) {
        uint256 currentGame = gameId.current();
        GameInfo storage params = gameToGameInfo[currentGame];

        return params.fundingPerPod / 10;
        // uint256 timeElapsed = block.timestamp > params.startTime ? block.timestamp - params.startTime : 0;
        // return (timeElapsed**2) / 3600; //TODO: Parametrize this
    }

    function getParticipatedGames(address _user) external view returns (uint256[] memory) {
        return userToGamesParticipated[_user];
    }
}
