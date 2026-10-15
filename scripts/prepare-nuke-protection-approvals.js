#!/usr/bin/env node
// Prepare owner transactions only. This script never signs or broadcasts.
const { JsonRpcProvider, Contract, Interface, getAddress, keccak256 } = require('ethers');

async function main() {
  const args = process.argv.slice(2);
  const approved = !args.includes('--disable');
  const addresses = args.filter((arg) => arg !== '--disable').map(getAddress);
  if (!process.env.RPC_URL || addresses.length < 2) {
    throw new Error('Usage: RPC_URL=... node scripts/prepare-nuke-protection-approvals.js [--disable] FEATURE_FACTORY MARKET_FACTORY...');
  }
  const [featureFactory, ...marketFactories] = addresses;
  const provider = new JsonRpcProvider(process.env.RPC_URL);
  const network = await provider.getNetwork();
  // Pin reads to one block so the review artifact describes one observed state.
  const block = await provider.getBlock('latest');
  if (!block) throw new Error('Latest block unavailable');
  const blockTag = block.number;
  const featureCode = await provider.getCode(featureFactory, blockTag);
  if (approved && featureCode === '0x') throw new Error('Feature factory has no deployed code');
  const abi = [
    'function archController() view returns (address)',
    'function isApprovedNukeProtectionFactory(address) view returns (bool)',
    'function setNukeProtectionFactoryApproval(address,bool)',
  ];
  const iface = new Interface(abi);
  const transactions = [];
  for (const address of [...new Set(marketFactories)]) {
    const code = await provider.getCode(address, blockTag);
    if (code === '0x') throw new Error(`Market factory has no deployed code: ${address}`);
    const factory = new Contract(address, abi, provider);
    const archController = await factory.archController({ blockTag });
    const arch = new Contract(archController, ['function owner() view returns (address)'], provider);
    const owner = await arch.owner({ blockTag });
    const currentlyApproved = await factory.isApprovedNukeProtectionFactory(featureFactory, { blockTag });
    transactions.push({
      from: owner,
      to: address,
      value: '0',
      data: iface.encodeFunctionData('setNukeProtectionFactoryApproval', [featureFactory, approved]),
      archController,
      marketFactoryCodeHash: keccak256(code),
      currentlyApproved,
    });
  }
  console.log(JSON.stringify({
    chainId: network.chainId.toString(),
    blockNumber: block.number,
    blockHash: block.hash,
    featureFactory,
    featureFactoryCodeHash: keccak256(featureCode),
    approved,
    transactions,
  }, null, 2));
}

main().catch((error) => {
  console.error(error.shortMessage || error.message);
  process.exitCode = 1;
});
