const { ethers } = require('hardhat');

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with the account:', deployer.address);

  try {
    const cf = await ethers.getContractFactory('BERC721');
    const contract = await cf.deploy('Bridge Collection', 'BC', '0xA2EAa2B06aF20C7Fc4616774621D3E54518fA8D2');

    console.log('Contract deployed at:', contract.target);
  } catch (error) {
    console.error('Error deploying contract:', error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
