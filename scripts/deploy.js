const hre = require("hardhat");

// ----- Deployment Parameters -----

// ----------------------------------

async function main() {
  console.log("Deploying... ");

  // Deploy the contract
  const Race = await hre.ethers.getContractFactory("RugRace");
  const race = await Race.deploy();
  await race.deployed();
  console.log("Contract deployed to:", race.address);

  // We have to wait for a few block confirmations to make sure Etherscan will pick up the bytecode.
  const txConfirmations = 5;
  await race.deployTransaction.wait(txConfirmations);

  // Verify the contract
  console.log("Verifying...");
  // This runs the hardhat task, you can call this via CLI with npx hardhat verify ...

  await hre.run("verify:verify", {
    address: race.address,
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
