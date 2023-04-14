pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "hardhat/console.sol";

contract RugRace is Ownable {
    using Counters for Counters.Counter;

    // ----- Events -----

    event GameStarted(uint256 indexed _gameId, uint128 _startTime, uint128 _endTime, uint256 _podNum, uint256 _funding, uint256 _bonus);
    event GameFinalized(uint256 indexed _gameId, uint256 _numRugged, uint256 _numUnrugged, uint256 _leftover, address _recipient);
    event UserAddedToPod(uint256 indexed _gameId, uint256 indexed _podId, address indexed _user);
    event Rug(uint256 indexed _gameId, uint256 indexed _podId, address _rugger, uint256 _rugTime, uint256 _amount);
    event BonusDistributed(uint256 indexed _gameId, uint256 indexed _podId, address indexed _user, uint256 _amount);
    event Claim(address indexed _user, uint256 _amount);

    // ----- State Variables -----
    Counters.Counter private gameId;

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
        uint256 intermissionsRemaining;
        uint128 intermissionStartTime;
        uint128 intermissionEndTime;
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

    uint256 public constant MIN_GAME_DURATION = 20 minutes;
    uint256 public constant MAX_GAME_DURATION = 3 hours;
    uint256 public constant MAX_POD_NUMBER = 50;
    uint256 public constant MAX_INTERMISSIONS = 2;
    uint256 public constant MAX_INTERMISSION_DURATION = 10 minutes;

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

    /**
     * @notice  Starts a new game
     * @param   _participants   Array of participants in the game
     * @param   _startTime      Start time in Unix Epoch seconds
     * @param   _endTime        End time in Unix Epoch seconds
     * @param   _podNum         Number of pods in the game
     * @param   _funding        Ether value provided as funding for pods
     * @param   _bonus          Ether value distributed among unrugged pods
     * @param   _seed           Seed for randomness
     */
    function startGame(
        address[] memory _participants,
        uint128 _startTime,
        uint128 _endTime,
        uint256 _podNum,
        uint256 _funding,
        uint256 _bonus,
        uint256 _seed
    ) external payable onlyOwner noGameActive finalized {
        require(_endTime > _startTime + MIN_GAME_DURATION && _endTime <= _startTime + MAX_GAME_DURATION, "!duration");
        require(_startTime >= block.timestamp, "!future");
        require(_participants.length % _podNum == 0, "!even");
        require(_podNum <= MAX_POD_NUMBER, "!podNum");

        require(_funding > 0, "!funding");
        require(msg.value == _funding + _bonus, "!value");

        gameId.increment();
        uint256 currentGame = gameId.current();

        GameInfo storage gameInfo = gameToGameInfo[currentGame];
        uint256 podSize = _participants.length / _podNum;
        gameInfo.startTime = _startTime;
        gameInfo.endTime = _endTime;
        gameInfo.podNum = _podNum;
        gameInfo.podSize = podSize;
        gameInfo.numParticipants = _participants.length;
        gameInfo.funding = _funding;
        gameInfo.fundingPerPod = _funding / _podNum;
        gameInfo.bonus = _bonus;
        gameInfo.podsRemaining = _podNum;
        gameInfo.intermissionsRemaining = MAX_INTERMISSIONS;

        _participants = shuffle(_participants, _seed);

        gameToParticipants[currentGame] = _participants;

        for (uint256 pod = 1; pod <= _podNum; ) {
            PodInfo storage podInfo = gameToPodToPodInfo[currentGame][pod];
            for (uint256 i = (pod - 1) * podSize; i < pod * podSize; ) {
                userToGamesParticipated[_participants[i]].push(currentGame);
                userToGameToPod[_participants[i]][currentGame] = pod;
                podInfo.participants.push(_participants[i]);

                emit UserAddedToPod(currentGame, pod, _participants[i]);

                unchecked {
                    ++i;
                }
            }
            unchecked {
                ++pod;
            }
        }

        emit GameStarted(currentGame, _startTime, _endTime, _podNum, _funding, _bonus);
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

        emit GameFinalized(currentGame, numPods - numUnrugged, numUnrugged, leftovers, owner());
    }

    function setIntermission(uint128 _startTime, uint128 _endTime) external onlyOwner gameActive {
        require(_endTime > _startTime && _startTime >= block.timestamp, "!timing");
        require(_endTime - _startTime <= MAX_INTERMISSION_DURATION, "!duration");

        uint256 currentGame = gameId.current();
        GameInfo storage game = gameToGameInfo[currentGame];

        require(game.intermissionsRemaining > 0, "!remaining");

        game.intermissionStartTime = _startTime;
        game.intermissionEndTime = _endTime;
        game.intermissionsRemaining--;

        // sTUB - Emit
    }

    // ----- Public Functions -----

    function rug() external gameActive {
        uint256 currentGame = gameId.current();
        uint256 pod = userToGameToPod[msg.sender][currentGame];
        require(pod > 0, "!player");

        PodInfo storage podInfo = gameToPodToPodInfo[currentGame][pod];
        require(podInfo.rugTime == 0, "!ruggable");

        GameInfo storage game = gameToGameInfo[currentGame];
        require(block.timestamp >= game.intermissionEndTime || block.timestamp < game.intermissionStartTime, "!intermission");

        podInfo.rugTime = block.timestamp;
        podInfo.rugger = msg.sender;

        game.podsRemaining--;

        uint256 payout = currentPayout();
        uint256 leftovers = game.fundingPerPod - payout;
        gameToUnusedFunds[currentGame] += leftovers;

        userToClaimable[msg.sender] += payout;

        emit Rug(currentGame, pod, msg.sender, block.timestamp, payout);
    }

    function claim() external {
        uint256 amount = userToClaimable[msg.sender];
        require(amount > 0, "!amount");
        userToClaimable[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit Claim(msg.sender, amount);
    }

    // ----- Internal Functions -----

    /**
     * @dev     Shuffles an array. Based on: https://ethereum.stackexchange.com/questions/134023/shuffle-array-mapping
     */
    function shuffle(address[] memory _array, uint256 _seed) internal pure returns (address[] memory) {
        uint256 counter = 0;
        uint256 j = 0;
        bytes32 b32 = keccak256(abi.encodePacked(_seed, counter));
        uint256 length = _array.length;

        for (uint256 i = 0; i < _array.length; i++) {
            if (j > 31) {
                b32 = keccak256(abi.encodePacked(_seed, ++counter));
                j = 0;
            }

            uint8 value = uint8(b32[j++]);

            uint256 n = value % length;

            address temp = _array[n];
            _array[n] = _array[i];
            _array[i] = temp;
        }

        return _array;
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
            emit BonusDistributed(_gameId, _podId, members[i], payoutPerUser);
        }
    }

    // ----- View Functions -----

    function currentPayout() public view returns (uint256) {
        uint256 currentGame = gameId.current();
        GameInfo storage gameInfo = gameToGameInfo[currentGame];

        uint256 timeElapsed = block.timestamp > gameInfo.startTime ? block.timestamp - gameInfo.startTime : 0;
        uint256 gameDuration = gameInfo.endTime - gameInfo.startTime;
        uint256 fundingPerPod = gameInfo.fundingPerPod;

        if (timeElapsed >= gameDuration) {
            return fundingPerPod;
        }

        return (fundingPerPod * (timeElapsed**2)) / (gameDuration**2);
    }

    function currentTimeElapsed() public view returns (uint256) {
        GameInfo storage gameInfo = gameToGameInfo[gameId.current()];

        uint256 timeElapsed = block.timestamp > gameInfo.startTime ? block.timestamp - gameInfo.startTime : 0;
        uint256 gameDuration = gameInfo.endTime - gameInfo.startTime;

        return timeElapsed >= gameDuration ? gameDuration : timeElapsed;
    }

    function currentGameIntermission() external view returns (uint256, uint256) {
        GameInfo storage gameInfo = gameToGameInfo[gameId.current()];

        return (gameInfo.intermissionStartTime, gameInfo.intermissionEndTime);
    }

    function currentIntermissionsRemaining() external view returns (uint256) {
        GameInfo storage gameInfo = gameToGameInfo[gameId.current()];

        return gameInfo.intermissionsRemaining;
    }

    function currentBonusPerPlayer() external view returns (uint256) {
        GameInfo storage gameInfo = gameToGameInfo[gameId.current()];

        return gameInfo.podsRemaining > 0 ? gameInfo.bonus / gameInfo.podsRemaining / gameInfo.podSize : 0;
    }

    function currentRugStatus(uint256 _pod) external view returns (uint256, address) {
        PodInfo storage pod = gameToPodToPodInfo[gameId.current()][_pod];
        return (pod.rugTime, pod.rugger);
    }

    function currentRuggedPodsInfo() external view returns (uint256, uint256) {
        GameInfo storage gameInfo = gameToGameInfo[gameId.current()];
        return (gameInfo.podNum - gameInfo.podsRemaining, gameInfo.podsRemaining);
    }

    function currentGameInfo() external view returns (GameInfo memory) {
        return gameToGameInfo[gameId.current()];
    }

    function currentPodByUser(address _user) external view returns (uint256) {
        return userToGameToPod[_user][gameId.current()];
    }

    function getParticipatedGames(address _user) external view returns (uint256[] memory) {
        return userToGamesParticipated[_user];
    }
}