const { exec } = require('child_process');
const { getConfigPath } = require('./_helpers');
// const argsObject = require('../../contracts/arguments.js');
const { getDispatcherAddress } = require('./_vibc-helpers.js');

const config = require(getConfigPath());

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
  const opDispatcherAddr = getDispatcherAddress('optimism');
  const srcNetworkVerifyCommand = `npx hardhat verify --network optimism ${config.createChannel.srcAddr} ${opDispatcherAddr}`;

  await runVerifyContractCommand(srcNetworkVerifyCommand);

  const baseDispatcherAddr = getDispatcherAddress('base');
  const dstNetworkVerifyCommand = `npx hardhat verify --network base ${config.createChannel.dstAddr} ${baseDispatcherAddr}`;

  await runVerifyContractCommand(dstNetworkVerifyCommand);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
