const { exec } = require('child_process');
const hre = require('hardhat');

function runVerifyContractCommand(command) {
  return new Promise((resolve, reject) => {
    exec(command, (error, stdout) => {
      if (error) {
        console.error(`exec error: ${error}`);
        reject(error);
      } else {
        console.log(stdout);
        resolve(true);
      }
    });
  });
}

async function main() {
  // Deploy the contract
  // npx hardhat run scripts/deploy-infra.js --network optimism
  console.log('Deploying infrastructure contracts...');

  const bridgeAddress = '0x';

  console.log('Deploying PythPriceFeeds');
  const oracleAddress = network.name === 'optimisim' ? '0x0708325268dF9F66270F1401206434524814508b' : '0xA2aa501b19aff244D90cc15a4Cf739D2725B5729';
  const pythPriceFeeds = await hre.ethers.deployContract('PythPriceFeeds', [oracleAddress]);
  await pythPriceFeeds.waitForDeployment();

  console.log('Deploying UniswapV2');
  const routerAddress = network.name === 'optimism' ? '0xf1072055810c670959aF73CB21f7f88Ce2A9c8d4' : '0x8cfb0faEA320A9Dfa41C1eF31eea88A50D1F020e';
  const uniswapV2 = await hre.ethers.deployContract('UniswapV2', [routerAddress]);
  await uniswapV2.waitForDeployment();

  console.log(`PythPriceFeeds deployed to ${pythPriceFeeds.target}`);
  console.log(`UniswapV2 deployed to ${uniswapV2.target}`);

  // Verify the contracts
  console.log('Verifying contracts...');
  const ppfCommand = `npx hardhat verify --network ${network.name} ${pythPriceFeeds.target} ${oracleAddress}`;
  try {
    await runVerifyContractCommand(ppfCommand);
  } catch (error) {
    console.error('❌ Error verifying contract: ', error);
  }

  const uniswapCommand = `npx hardhat verify --network ${network.name} ${uniswapV2.target} ${routerAddress}`;
  try {
    await runVerifyContractCommand(uniswapCommand);
  } catch (error) {
    console.error('❌ Error verifying contract: ', error);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
