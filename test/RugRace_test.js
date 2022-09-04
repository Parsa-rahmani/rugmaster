const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle");
const { ethers } = require("hardhat");
const { isCallTrace } = require("hardhat/internal/hardhat-network/stack-traces/message-trace");

use(solidity);

const provider = waffle.provider;
const [devWallet, citizen1, citizen2, citizen3, citizen4, citizen5, citizen6, citizen7, citizen8, citizen9, citizen10] =
  provider.getWallets();

const participants = [citizen1.address, citizen2.address, citizen3.address, citizen4.address, citizen5.address, citizen6.address];
const gameLength = 3600;

const ETHER_ONE = hre.ethers.utils.parseEther("1");

describe("Rug Race", function () {
  describe("Core", function () {
    beforeEach(async function () {
      Race = await ethers.getContractFactory("RugRace");
      race = await Race.deploy();

      const blockNumBefore = await ethers.provider.getBlockNumber();
      const blockBefore = await ethers.provider.getBlock(blockNumBefore);
      const timestampBefore = blockBefore.timestamp;
      startTime = timestampBefore + 10;
      await network.provider.send("evm_setNextBlockTimestamp", [startTime - 1]);
    });

    it("Should start a new game", async function () {
      await race.connect(devWallet).startGame(participants, startTime, startTime + gameLength, 3, ETHER_ONE);
    });
  });
});
