pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

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

    constructor() {
        // So we can start the first game
        gameToGameInfo[0].finalized = true;
    }

    function startGame(
        address[] memory _participants,
        uint128 _startTime,
        uint128 _endTime,
        uint256 _podNum,
        uint256 _bonus
    ) external payable onlyOwner noGameActive finalized {
        require(_endTime > _startTime + MIN_DURATION, "!duration");
        require(_participants.length % _podNum == 0, "!even");

        // STUB - ensure funding adequate
        // STUB - ensure bonus appropriate

        gameId.increment();
        uint256 currentGame = gameId.current();

        GameInfo storage params = gameToGameInfo[currentGame];
        uint256 podSize = _participants.length / _podNum;
        params.startTime = _startTime;
        params.endTime = _endTime;
        params.podNum = _podNum;
        params.podSize = podSize;
        params.numParticipants = _participants.length;
        params.funding = msg.value;
        params.fundingPerPod = msg.value / _podNum;
        params.bonus = _bonus;

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

        // Determine if any pods have not rugged
        uint256 numPods = game.podNum;
        uint256[] memory unruggedPods;
        uint256 j;
        for (uint256 i = 1; 1 <= numPods; ) {
            if (gameToPodToPodInfo[currentGame][i].rugTime == 0) {
                unruggedPods[j] = i;
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Distribute bonuses to unrugged pods, if any
        uint256 availableBonus = calculateBonus(currentGame);
        uint256 bonusPerPod = unruggedPods.length > 0 ? availableBonus / unruggedPods.length : 0;

        for (uint256 i = 0; i < unruggedPods.length; ) {
            distributeBonus(currentGame, unruggedPods[i], bonusPerPod);
        }

        // Withdraw leftover funds to owner
        uint256 leftovers = gameToUnusedFunds[currentGame];
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
        podInfo.rugTime = block.timestamp;
        podInfo.rugger = msg.sender;

        uint256 payout = currentPayout();
        uint256 leftovers = gameToGameInfo[currentGame].fundingPerPod - payout;
        gameToUnusedFunds[currentGame] += leftovers;

        userToClaimable[msg.sender] += payout;

        // STUB - Emit events
    }

    function distributeBonus(
        uint256 _gameId,
        uint256 _podId,
        uint256 _amount
    ) internal {
        address[] memory members = gameToPodToPodInfo[_gameId][_podId].participants;

        uint256 payoutPerUser = _amount / members.length;
        for (uint256 i; i < members.length; ) {
            userToClaimable[members[i]] += payoutPerUser;
            // STUB - Emit Event
        }
        // STUB - Emit Events
    }

    function claim() external {
        uint256 amount = userToClaimable[msg.sender];
        userToClaimable[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        // STUB - emit event
    }

    // ----- Internal Functions -----

    // STUB - make it actually shuffle later
    function shuffle(address[] memory _participants) internal view returns (address[] memory) {
        return _participants;
    }

    // ----- View Functions -----

    function currentPayout() public view returns (uint256) {
        uint256 currentGame = gameId.current();
        GameInfo storage params = gameToGameInfo[currentGame];
        uint256 timeElapsed = block.timestamp > params.startTime ? block.timestamp - params.startTime : 0;
        return (timeElapsed**2) / 3600; //TODO: Parametrize this
    }

    function calculateBonus(uint256 _gameId) public view returns (uint256) {
        // STUB - Calculate bonus amount
        return 1 ether;
    }
}
