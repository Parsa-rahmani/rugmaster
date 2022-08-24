pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract RugRace is Ownable {
    using Counters for Counters.Counter;
    // ----- State Variables -----
    Counters.Counter private gameId;

    mapping(uint256 => mapping(uint256 => uint256))
        public gameToPodToTimeRugged;

    mapping(uint256 => address[]) public gameToParticipants;
    mapping(uint256 => Parameters) public gameToParameters;

    struct Parameters {
        uint128 startTime;
        uint128 endTime;
        uint256 podNum;
        uint256 numParticipants;
        uint256 funding;
    }

    mapping(address => uint256[]) public userToGamesParticipated;

    uint256 public constant MIN_DURATION = 30 minutes;

    modifier noGameActive() {
        require(
            block.timestamp >= gameToParameters[gameId.current()].endTime,
            "!ended"
        );
        _;
    }

    modifier gameActive() {
        require(
            block.timestamp < gameToParameters[gameId.current()].endTime &&
                block.timestamp >= gameToParameters[gameId.current()].startTime,
            "!ended"
        );
        _;
    }

    constructor() {}

    function startGame(
        address[] calldata _participants,
        uint128 _startTime,
        uint128 _endTime,
        uint256 _podNum
    ) external payable onlyOwner noGameActive {
        require(_endTime > _startTime + MIN_DURATION, "!duration");
        require(_participants.length % _podNum == 0, "!even");

        gameId.increment();
        uint256 currentGame = gameId.current();
        gameToParticipants[currentGame] = _participants;

        Parameters storage params = gameToParameters[currentGame];
        params.startTime = _startTime;
        params.endTime = _endTime;
        params.podNum = _podNum;
        params.numParticipants = _participants.length;
        params.funding = msg.value;

        // STUB - ensure funding adequate

        // STUB - Emit event
    }

    function rug() external {
        uint256 currentGame = gameId.current();
    }

    function currentPayout() public view returns (uint256) {
        uint256 currentGame = gameId.current();
        Parameters storage params = gameToParameters[currentGame];
        uint256 timeElapsed = block.timestamp > params.startTime
            ? block.timestamp - params.startTime
            : 0;
        return (timeElapsed**2) / 3600;
    }
}
