const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle");
const { ethers } = require("hardhat");

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
      await race
        .connect(devWallet)
        .startGame(participants, startTime, startTime + gameLength, 3, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(4) });
    });

    it("Should NOT start a new game with improper parameters", async function () {
      await expect(
        race
          .connect(devWallet)
          .startGame(participants, 0, startTime + gameLength, 3, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(4) }),
      ).to.be.revertedWith("!future");

      await expect(
        race.connect(devWallet).startGame(participants, startTime, startTime, 3, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(4) }),
      ).to.be.revertedWith("!duration");

      await expect(
        race
          .connect(devWallet)
          .startGame(participants, startTime + 10, startTime + gameLength, 4, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(4) }),
      ).to.be.revertedWith("!even");

      await expect(
        race
          .connect(devWallet)
          .startGame(participants, startTime + 10, startTime + gameLength, 3, 0, ETHER_ONE, { value: ETHER_ONE.mul(4) }),
      ).to.be.revertedWith("!funding");

      await expect(
        race
          .connect(devWallet)
          .startGame(participants, startTime + 10, startTime + gameLength, 3, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(1) }),
      ).to.be.revertedWith("!value");
    });

    it("Should rug a pod and pay the rugger", async function () {
      await race
        .connect(devWallet)
        .startGame(participants, startTime, startTime + gameLength, 3, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(4) });
      await network.provider.send("evm_increaseTime", [60]);

      expect(await race.userToClaimable(citizen1.address)).to.eq(0);
      await race.connect(citizen1).rug();
      expect(await race.userToClaimable(citizen1.address)).to.eq(ethers.utils.parseEther("0.1"));
    });

    it("Should not allow rugging the same pod twice", async function () {
      await race
        .connect(devWallet)
        .startGame(participants, startTime, startTime + gameLength, 3, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(4) });
      await network.provider.send("evm_increaseTime", [60]);

      await race.connect(citizen1).rug();
      expect(await race.userToClaimable(citizen1.address)).to.eq(ethers.utils.parseEther("0.1"));
      await expect(race.connect(citizen1).rug()).to.be.revertedWith("!ruggable");
    });

    it("Should not allow rugging if the user is not in this game", async function () {
      await race
        .connect(devWallet)
        .startGame(participants, startTime, startTime + gameLength, 3, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(4) });
      await network.provider.send("evm_increaseTime", [60]);

      await expect(race.connect(citizen7).rug()).to.be.revertedWith("!player");
    });

    it("Should closeout a game and distribute the bonus among the unrugged pods", async function () {
      await race
        .connect(devWallet)
        .startGame(participants, startTime, startTime + gameLength, 3, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(4) });
      await network.provider.send("evm_increaseTime", [60]);

      expect(await race.userToClaimable(citizen1.address)).to.eq(0);
      await race.connect(citizen1).rug();
      expect(await race.userToClaimable(citizen1.address)).to.eq(ethers.utils.parseEther("0.1"));

      await network.provider.send("evm_increaseTime", [3600]);

      expect(await race.connect(devWallet).closeout()).to.changeEtherBalance(devWallet, ethers.utils.parseEther("2.9"));
      expect(await race.userToClaimable(citizen1.address)).to.eq(ethers.utils.parseEther("0.1"));
      expect(await race.userToClaimable(citizen2.address)).to.eq(0);
      expect(await race.userToClaimable(citizen3.address)).to.eq(ethers.utils.parseEther("0.25"));
      expect(await race.userToClaimable(citizen4.address)).to.eq(ethers.utils.parseEther("0.25"));
      expect(await race.userToClaimable(citizen5.address)).to.eq(ethers.utils.parseEther("0.25"));
      expect(await race.userToClaimable(citizen6.address)).to.eq(ethers.utils.parseEther("0.25"));
    });

    it("Should have all the correct view function values", async function () {
      expect(await network.provider.send("eth_getBalance", [race.address])).to.eq("0x0");

      expect(await race.userToGameToPod(citizen1.address, 1)).to.eq([0]);
      expect(await race.userToGameToPod(citizen2.address, 1)).to.eq([0]);
      expect(await race.userToGameToPod(citizen3.address, 1)).to.eq([0]);
      expect(await race.userToGameToPod(citizen4.address, 1)).to.eq([0]);
      expect(await race.userToGameToPod(citizen5.address, 1)).to.eq([0]);
      expect(await race.userToGameToPod(citizen6.address, 1)).to.eq([0]);

      expect(await race.userToClaimable(citizen1.address)).to.eq(0);
      expect(await race.userToClaimable(citizen2.address)).to.eq(0);
      expect(await race.userToClaimable(citizen3.address)).to.eq(0);
      expect(await race.userToClaimable(citizen4.address)).to.eq(0);
      expect(await race.userToClaimable(citizen5.address)).to.eq(0);
      expect(await race.userToClaimable(citizen6.address)).to.eq(0);

      await race
        .connect(devWallet)
        .startGame(participants, startTime, startTime + gameLength, 3, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(4) });
      await network.provider.send("evm_increaseTime", [60]);

      expect(await network.provider.send("eth_getBalance", [race.address])).to.eq("0x3782dace9d900000");

      expect((await race.userToGamesParticipated(citizen1.address, 0)).toString()).to.eq("1");
      expect((await race.userToGamesParticipated(citizen2.address, 0)).toString()).to.eq("1");
      expect((await race.userToGamesParticipated(citizen3.address, 0)).toString()).to.eq("1");
      expect((await race.userToGamesParticipated(citizen4.address, 0)).toString()).to.eq("1");
      expect((await race.userToGamesParticipated(citizen5.address, 0)).toString()).to.eq("1");
      expect((await race.userToGamesParticipated(citizen6.address, 0)).toString()).to.eq("1");

      expect(await race.userToGameToPod(citizen1.address, 1)).to.eq(1);
      expect(await race.userToGameToPod(citizen2.address, 1)).to.eq(1);
      expect(await race.userToGameToPod(citizen3.address, 1)).to.eq(2);
      expect(await race.userToGameToPod(citizen4.address, 1)).to.eq(2);
      expect(await race.userToGameToPod(citizen5.address, 1)).to.eq(3);
      expect(await race.userToGameToPod(citizen6.address, 1)).to.eq(3);

      expect(await race.userToClaimable(citizen1.address)).to.eq(0);
      expect(await race.userToClaimable(citizen2.address)).to.eq(0);
      expect(await race.userToClaimable(citizen3.address)).to.eq(0);
      expect(await race.userToClaimable(citizen4.address)).to.eq(0);
      expect(await race.userToClaimable(citizen5.address)).to.eq(0);
      expect(await race.userToClaimable(citizen6.address)).to.eq(0);

      await race.connect(citizen1).rug();
      await network.provider.send("evm_increaseTime", [3600]);

      expect(await race.userToClaimable(citizen1.address)).to.eq(ethers.utils.parseEther("0.1"));
      expect(await race.userToClaimable(citizen2.address)).to.eq(0);
      expect(await race.userToClaimable(citizen3.address)).to.eq(0);
      expect(await race.userToClaimable(citizen4.address)).to.eq(0);
      expect(await race.userToClaimable(citizen5.address)).to.eq(0);
      expect(await race.userToClaimable(citizen6.address)).to.eq(0);

      expect(await race.connect(devWallet).closeout()).to.changeEtherBalance(devWallet, ethers.utils.parseEther("2.9"));

      expect((await race.userToGamesParticipated(citizen1.address, 0)).toString()).to.eq("1");
      expect((await race.userToGamesParticipated(citizen2.address, 0)).toString()).to.eq("1");
      expect((await race.userToGamesParticipated(citizen3.address, 0)).toString()).to.eq("1");
      expect((await race.userToGamesParticipated(citizen4.address, 0)).toString()).to.eq("1");
      expect((await race.userToGamesParticipated(citizen5.address, 0)).toString()).to.eq("1");
      expect((await race.userToGamesParticipated(citizen6.address, 0)).toString()).to.eq("1");

      expect(await race.userToGameToPod(citizen1.address, 1)).to.eq(1);
      expect(await race.userToGameToPod(citizen2.address, 1)).to.eq(1);
      expect(await race.userToGameToPod(citizen3.address, 1)).to.eq(2);
      expect(await race.userToGameToPod(citizen4.address, 1)).to.eq(2);
      expect(await race.userToGameToPod(citizen5.address, 1)).to.eq(3);
      expect(await race.userToGameToPod(citizen6.address, 1)).to.eq(3);

      expect(await race.userToClaimable(citizen1.address)).to.eq(ethers.utils.parseEther("0.1"));
      expect(await race.userToClaimable(citizen2.address)).to.eq(0);
      expect(await race.userToClaimable(citizen3.address)).to.eq(ethers.utils.parseEther("0.25"));
      expect(await race.userToClaimable(citizen4.address)).to.eq(ethers.utils.parseEther("0.25"));
      expect(await race.userToClaimable(citizen5.address)).to.eq(ethers.utils.parseEther("0.25"));
      expect(await race.userToClaimable(citizen6.address)).to.eq(ethers.utils.parseEther("0.25"));

      expect(await race.connect(citizen1).claim()).to.changeEtherBalance(citizen1, ethers.utils.parseEther("0.1"));
      await expect(race.connect(citizen2).claim()).to.be.revertedWith("!amount");
      expect(await race.connect(citizen3).claim()).to.changeEtherBalance(citizen3, ethers.utils.parseEther("0.25"));
      expect(await race.connect(citizen4).claim()).to.changeEtherBalance(citizen4, ethers.utils.parseEther("0.25"));
      expect(await race.connect(citizen5).claim()).to.changeEtherBalance(citizen5, ethers.utils.parseEther("0.25"));
      expect(await race.connect(citizen6).claim()).to.changeEtherBalance(citizen6, ethers.utils.parseEther("0.25"));

      expect(await race.userToClaimable(citizen1.address)).to.eq(0);
      expect(await race.userToClaimable(citizen2.address)).to.eq(0);
      expect(await race.userToClaimable(citizen3.address)).to.eq(0);
      expect(await race.userToClaimable(citizen4.address)).to.eq(0);
      expect(await race.userToClaimable(citizen5.address)).to.eq(0);
      expect(await race.userToClaimable(citizen6.address)).to.eq(0);

      expect(await network.provider.send("eth_getBalance", [race.address])).to.eq("0x0");

      // Game 2

      expect(await race.userToGameToPod(citizen1.address, 2)).to.eq([0]);
      expect(await race.userToGameToPod(citizen2.address, 2)).to.eq([0]);
      expect(await race.userToGameToPod(citizen3.address, 2)).to.eq([0]);
      expect(await race.userToGameToPod(citizen4.address, 2)).to.eq([0]);
      expect(await race.userToGameToPod(citizen5.address, 2)).to.eq([0]);
      expect(await race.userToGameToPod(citizen6.address, 2)).to.eq([0]);

      expect(await race.userToClaimable(citizen1.address)).to.eq(0);
      expect(await race.userToClaimable(citizen2.address)).to.eq(0);
      expect(await race.userToClaimable(citizen3.address)).to.eq(0);
      expect(await race.userToClaimable(citizen4.address)).to.eq(0);
      expect(await race.userToClaimable(citizen5.address)).to.eq(0);
      expect(await race.userToClaimable(citizen6.address)).to.eq(0);

      const blockNumBefore = await ethers.provider.getBlockNumber();
      const blockBefore = await ethers.provider.getBlock(blockNumBefore);
      const timestampBefore = blockBefore.timestamp;
      startTime = timestampBefore + 10;
      await network.provider.send("evm_setNextBlockTimestamp", [startTime - 1]);

      await race
        .connect(devWallet)
        .startGame(participants, startTime, startTime + gameLength, 3, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(4) });
      await network.provider.send("evm_increaseTime", [60]);

      expect(await network.provider.send("eth_getBalance", [race.address])).to.eq("0x3782dace9d900000");

      expect((await race.userToGamesParticipated(citizen1.address, 1)).toString()).to.eq("2");
      expect((await race.userToGamesParticipated(citizen2.address, 1)).toString()).to.eq("2");
      expect((await race.userToGamesParticipated(citizen3.address, 1)).toString()).to.eq("2");
      expect((await race.userToGamesParticipated(citizen4.address, 1)).toString()).to.eq("2");
      expect((await race.userToGamesParticipated(citizen5.address, 1)).toString()).to.eq("2");
      expect((await race.userToGamesParticipated(citizen6.address, 1)).toString()).to.eq("2");

      expect(await race.userToGameToPod(citizen1.address, 2)).to.eq(1);
      expect(await race.userToGameToPod(citizen2.address, 2)).to.eq(1);
      expect(await race.userToGameToPod(citizen3.address, 2)).to.eq(2);
      expect(await race.userToGameToPod(citizen4.address, 2)).to.eq(2);
      expect(await race.userToGameToPod(citizen5.address, 2)).to.eq(3);
      expect(await race.userToGameToPod(citizen6.address, 2)).to.eq(3);

      expect(await race.userToClaimable(citizen1.address)).to.eq(0);
      expect(await race.userToClaimable(citizen2.address)).to.eq(0);
      expect(await race.userToClaimable(citizen3.address)).to.eq(0);
      expect(await race.userToClaimable(citizen4.address)).to.eq(0);
      expect(await race.userToClaimable(citizen5.address)).to.eq(0);
      expect(await race.userToClaimable(citizen6.address)).to.eq(0);

      await race.connect(citizen1).rug();
      await network.provider.send("evm_increaseTime", [3600]);

      expect(await race.userToClaimable(citizen1.address)).to.eq(ethers.utils.parseEther("0.1"));
      expect(await race.userToClaimable(citizen2.address)).to.eq(0);
      expect(await race.userToClaimable(citizen3.address)).to.eq(0);
      expect(await race.userToClaimable(citizen4.address)).to.eq(0);
      expect(await race.userToClaimable(citizen5.address)).to.eq(0);
      expect(await race.userToClaimable(citizen6.address)).to.eq(0);

      expect(await race.connect(devWallet).closeout()).to.changeEtherBalance(devWallet, ethers.utils.parseEther("2.9"));

      expect((await race.userToGamesParticipated(citizen1.address, 1)).toString()).to.eq("2");
      expect((await race.userToGamesParticipated(citizen2.address, 1)).toString()).to.eq("2");
      expect((await race.userToGamesParticipated(citizen3.address, 1)).toString()).to.eq("2");
      expect((await race.userToGamesParticipated(citizen4.address, 1)).toString()).to.eq("2");
      expect((await race.userToGamesParticipated(citizen5.address, 1)).toString()).to.eq("2");
      expect((await race.userToGamesParticipated(citizen6.address, 1)).toString()).to.eq("2");

      expect(await race.userToGameToPod(citizen1.address, 2)).to.eq(1);
      expect(await race.userToGameToPod(citizen2.address, 2)).to.eq(1);
      expect(await race.userToGameToPod(citizen3.address, 2)).to.eq(2);
      expect(await race.userToGameToPod(citizen4.address, 2)).to.eq(2);
      expect(await race.userToGameToPod(citizen5.address, 2)).to.eq(3);
      expect(await race.userToGameToPod(citizen6.address, 2)).to.eq(3);

      expect(await race.userToClaimable(citizen1.address)).to.eq(ethers.utils.parseEther("0.1"));
      expect(await race.userToClaimable(citizen2.address)).to.eq(0);
      expect(await race.userToClaimable(citizen3.address)).to.eq(ethers.utils.parseEther("0.25"));
      expect(await race.userToClaimable(citizen4.address)).to.eq(ethers.utils.parseEther("0.25"));
      expect(await race.userToClaimable(citizen5.address)).to.eq(ethers.utils.parseEther("0.25"));
      expect(await race.userToClaimable(citizen6.address)).to.eq(ethers.utils.parseEther("0.25"));

      expect(await race.connect(citizen1).claim()).to.changeEtherBalance(citizen1, ethers.utils.parseEther("0.1"));
      await expect(race.connect(citizen2).claim()).to.be.revertedWith("!amount");
      expect(await race.connect(citizen3).claim()).to.changeEtherBalance(citizen3, ethers.utils.parseEther("0.25"));
      expect(await race.connect(citizen4).claim()).to.changeEtherBalance(citizen4, ethers.utils.parseEther("0.25"));
      expect(await race.connect(citizen5).claim()).to.changeEtherBalance(citizen5, ethers.utils.parseEther("0.25"));
      expect(await race.connect(citizen6).claim()).to.changeEtherBalance(citizen6, ethers.utils.parseEther("0.25"));

      expect(await race.userToClaimable(citizen1.address)).to.eq(0);
      expect(await race.userToClaimable(citizen2.address)).to.eq(0);
      expect(await race.userToClaimable(citizen3.address)).to.eq(0);
      expect(await race.userToClaimable(citizen4.address)).to.eq(0);
      expect(await race.userToClaimable(citizen5.address)).to.eq(0);
      expect(await race.userToClaimable(citizen6.address)).to.eq(0);

      expect(await network.provider.send("eth_getBalance", [race.address])).to.eq("0x0");
    });

    it("Should withdraw a claimable balance", async function () {
      await race
        .connect(devWallet)
        .startGame(participants, startTime, startTime + gameLength, 3, ETHER_ONE.mul(3), ETHER_ONE, { value: ETHER_ONE.mul(4) });
      await network.provider.send("evm_increaseTime", [60]);

      expect(await race.userToClaimable(citizen1.address)).to.eq(0);
      await race.connect(citizen1).rug();
      expect(await race.userToClaimable(citizen1.address)).to.eq(ethers.utils.parseEther("0.1"));

      expect(await race.connect(citizen1).claim()).to.changeEtherBalance(citizen1, ethers.utils.parseEther("0.1"));
    });
  });
});
