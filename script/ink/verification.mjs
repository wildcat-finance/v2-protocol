import assert from 'node:assert/strict';
import { parseEnv } from 'node:util';
import { checkEndpoint, keccak, lower } from './inventory.mjs';

export const EXPLORERS = Object.freeze({
  57073: 'https://explorer.inkonchain.com',
  763373: 'https://explorer-sepolia.inkonchain.com',
});

export function verificationApiUrl(chainId) {
  assert(Object.hasOwn(EXPLORERS, chainId), 'unsupported Ink chain');
  return 'https://api.blockscout.com/v2/api?chainid=' + chainId;
}

export function verificationApiKey(env, dotenv = '') {
  const key = env.INK_BLOCKSCOUT_API_KEY ?? parseEnv(dotenv).INK_BLOCKSCOUT_API_KEY;
  assert(typeof key === 'string' && /^proapi_\S+$/.test(key),
    'set INK_BLOCKSCOUT_API_KEY to a Blockscout Pro key in .env or the environment');
  return key;
}

const targets = Object.freeze({
  WildcatArchController: 'src/WildcatArchController.sol:WildcatArchController',
  SphereXEngine: 'src/spherex-engine/SphereXEngine.sol:SphereXEngine',
  SanctionsList: 'src/WildcatCopyOfChainalysisList.sol:WildcatCopyOfChainalysisList',
  SanctionsAdapter: 'src/ChainalysisProxy.sol:ChainalysisProxy',
  WildcatSanctionsSentinel: 'src/WildcatSanctionsSentinel.sol:WildcatSanctionsSentinel',
  WildcatFeeRecipient: 'src/WildcatFeeRecipient.sol:WildcatFeeRecipient',
  WildcatMarket_initCodeStorage: 'src/market/WildcatMarket.sol:WildcatMarket',
  OpenTermHooks_initCodeStorage: 'src/access/OpenTermHooks.sol:OpenTermHooks',
  FixedTermHooks_initCodeStorage: 'src/access/FixedTermHooks.sol:FixedTermHooks',
  HooksFactory: 'src/HooksFactory.sol:HooksFactory',
  MarketLens: 'src/lens/MarketLens.sol:MarketLens',
  Wildcat4626WrapperFactory: 'src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory',
  OpenAccessRoleProvider: 'src/OpenAccessRoleProvider.sol:OpenAccessRoleProvider',
  MockArchControllerOwner: 'script/mock/MockArchControllerOwner.sol:MockArchControllerOwner',
});
const address = /^0x[0-9a-fA-F]{40}$/;
const hash = /^0x[0-9a-fA-F]{64}$/;
const bytes = /^0x(?:[0-9a-fA-F]{2})*$/;

export function validateVerificationInventory(inventory) {
  assert.equal(inventory.schemaVersion, 1);
  assert(['confirmed-bootstrap', 'confirmed-contracts-sanctions-pending'].includes(inventory.status), 'collect receipt-backed inventory before verification');
  if (inventory.status === 'confirmed-contracts-sanctions-pending') {
    assert.equal(inventory.chainId, 763373, 'deferred seeding is testnet-only');
    assert.equal(inventory.sanctions?.status, 'deferred');
    assert.equal(inventory.sanctions.observedCount, 0);
    assert.equal(inventory.launchReady, false);
  }
  assert(Number.isSafeInteger(inventory.chainId) && Object.hasOwn(EXPLORERS, inventory.chainId), 'unsupported Ink chain');
  assert(['live', 'rehearsal'].includes(inventory.mode), 'explicit inventory mode required');
  assert(address.test(inventory.deployer) && BigInt(inventory.deployer) !== 0n, 'invalid deployer');
  assert(Array.isArray(inventory.contracts), 'missing contract inventory');
  const expected = Object.keys(targets).filter(name =>
    (name !== 'MockArchControllerOwner' || inventory.chainId === 763373) &&
    (name !== 'WildcatFeeRecipient' || inventory.contracts.some(r => r.name === name)));
  assert.deepEqual(inventory.contracts.map(r => r.name).sort(), expected.sort(), 'verification contract set mismatch');
}

export function verificationPlan(inventory, loadArtifact) {
  validateVerificationInventory(inventory);
  const seen = new Set();
  return inventory.contracts.map(r => {
    assert(address.test(r.address) && BigInt(r.address) !== 0n && !seen.has(lower(r.address)), 'invalid/duplicate contract address');
    seen.add(lower(r.address));
    assert(hash.test(r.creationCodeHash) && hash.test(r.runtimeCodeHash) && hash.test(r.transactionHash), 'missing deployment hashes');
    assert(hash.test(r.blockHash) && Number.isSafeInteger(r.blockNumber) && r.blockNumber > 0, 'missing deployment block');
    assert(bytes.test(r.constructorArgs), 'invalid constructor arguments');
    const target = targets[r.name];
    assert(r.artifact === target || target.endsWith('/' + r.artifact), 'artifact mismatch: ' + r.name);
    const store = r.name.endsWith('_initCodeStorage');
    assert.equal(r.kind, store ? 'initcode-store' : 'contract', 'artifact kind mismatch');
    const artifact = loadArtifact(target);
    const m = typeof artifact.metadata === 'string' ? JSON.parse(artifact.metadata) : artifact.metadata;
    const [path, name] = target.split(':');
    assert.deepEqual(m.settings.compilationTarget, { [path]: name }, 'compilation target mismatch');
    assert(/^0\.8\.25\+commit\.[0-9a-f]{8}$/.test(m.compiler.version), 'compiler mismatch');
    assert(m.settings.viaIR && m.settings.optimizer.enabled && m.settings.optimizer.runs === 50000, 'optimizer mismatch');
    assert.equal(m.settings.evmVersion, 'cancun');
    assert.equal(m.settings.metadata.bytecodeHash, 'none');
    const code = artifact.bytecode.object;
    assert(bytes.test(code) && code.length > 2, 'missing creation bytecode');
    let creation = code + r.constructorArgs.slice(2);
    if (store) {
      assert.equal(r.constructorArgs, '0x', 'initcode stores have no constructor arguments');
      const size = (code.length - 2) / 2 + 1;
      assert(size <= 24576, 'initcode store exceeds EIP-170');
      creation = '0x61' + size.toString(16).padStart(4, '0') + '5f81600a5f39f300' + code.slice(2);
      assert.equal(lower(r.runtimeCodeHash), keccak('0x00' + code.slice(2)), 'stored initcode changed');
      assert.equal(r.runtimeSize, size, 'initcode store size mismatch');
    } else {
      assert(bytes.test(artifact.deployedBytecode.object), 'missing runtime bytecode');
      assert.equal(r.runtimeSize, (artifact.deployedBytecode.object.length - 2) / 2, 'runtime size mismatch');
    }
    assert.equal(keccak(creation), lower(r.creationCodeHash), 'build/constructor mismatch: ' + r.name + '; use the original deployment source, not a redeployment');
    return { ...r, target, compiler: m.compiler.version };
  });
}

export async function checkVerificationState(inventory, plan, rpc, rpcUrl) {
  // verification may run after handoff or keeper updates. check code/receipts, not bootstrap authority or the current nonce.
  await checkEndpoint(inventory, rpc, rpcUrl);
  const checkpoint = await rpc('eth_getBlockByNumber', ['latest', false]);
  assert(checkpoint && hash.test(checkpoint.hash), 'missing verification checkpoint');
  for (const r of plan) {
    const code = await rpc('eth_getCode', [r.address, checkpoint.number]);
    assert(bytes.test(code) && code.length > 2, 'no deployed code: ' + r.name);
    assert.equal(keccak(code), lower(r.runtimeCodeHash), 'deployed code mismatch: ' + r.name);
    const receipt = await rpc('eth_getTransactionReceipt', [r.transactionHash]);
    assert(receipt && BigInt(receipt.status) === 1n, 'missing/reverted creation receipt: ' + r.name);
    assert.equal(lower(receipt.transactionHash), lower(r.transactionHash));
    assert.equal(lower(receipt.contractAddress), lower(r.address));
    assert.equal(lower(receipt.from), lower(inventory.deployer));
    assert.equal(lower(receipt.blockHash), lower(r.blockHash));
    assert.equal(Number(BigInt(receipt.blockNumber)), r.blockNumber);
    assert(BigInt(receipt.blockNumber) <= BigInt(checkpoint.number), 'creation is after checkpoint');
    const block = await rpc('eth_getBlockByNumber', [receipt.blockNumber, false]);
    assert.equal(lower(block?.hash), lower(r.blockHash), 'creation receipt reorged: ' + r.name);
    const tx = await rpc('eth_getTransactionByHash', [r.transactionHash]);
    assert(tx && !tx.to, 'missing/non-CREATE transaction: ' + r.name);
    assert.equal(lower(tx.hash), lower(r.transactionHash));
    assert.equal(lower(tx.from), lower(inventory.deployer));
    assert.equal(lower(tx.blockHash), lower(receipt.blockHash));
    assert.equal(BigInt(tx.blockNumber), BigInt(receipt.blockNumber));
    assert.equal(BigInt(tx.value), 0n);
    if (tx.chainId !== undefined) assert.equal(Number(BigInt(tx.chainId)), inventory.chainId);
    assert.equal(keccak(tx.input), lower(r.creationCodeHash), 'creation transaction mismatch: ' + r.name);
  }
  assert.equal(lower((await rpc('eth_getBlockByNumber', [checkpoint.number, false]))?.hash), lower(checkpoint.hash), 'verification checkpoint reorged');
  return { number: Number(BigInt(checkpoint.number)), hash: checkpoint.hash };
}

export function verificationArgs(chainId, record) {
  assert(Object.hasOwn(EXPLORERS, chainId), 'unsupported Ink chain');
  assert.equal(record.kind, 'contract', 'initcode stores are not Solidity contract instances');
  const args = ['verify-contract', record.address, record.target,
    '--chain', String(chainId), '--verifier', 'blockscout', '--verifier-url', verificationApiUrl(chainId),
    '--compiler-version', 'v' + record.compiler, '--num-of-optimizations', '50000', '--via-ir', '--evm-version', 'cancun',
    '--watch', '--retries', '5', '--delay', '5'];
  if (record.constructorArgs !== '0x') args.push('--constructor-args', record.constructorArgs);
  return args;
}

export function verificationEnvironment(env, apiKey) {
  const result = { ...env, FOUNDRY_PROFILE: 'ink' };
  // the explorer gets only its own API key. RPC and unrelated verifier credentials aren't needed.
  for (const key of ['ETHERSCAN_API_KEY', 'VERIFIER_API_KEY', 'VERIFIER_URL', 'ETH_RPC_URL', 'ETH_RPC_HEADERS', 'ETH_RPC_JWT_SECRET', 'CHAIN']) delete result[key];
  // Forge's verify-contract config gives VERIFIER_API_KEY precedence, even when empty.
  // set both so submission and status polling use the same key, without dotenv fallback.
  result.ETHERSCAN_API_KEY = apiKey || '';
  result.VERIFIER_API_KEY = apiKey || '';
  return result;
}

export function redactVerificationResult(result, apiKey) {
  const redact = value => apiKey && value ? value.replaceAll(apiKey, '[redacted]') : value;
  return { status: result.status, signal: result.signal, stdout: redact(result.stdout), stderr: redact(result.stderr),
    error: result.error ? { message: redact(result.error.message) } : undefined };
}

export async function verifyContracts(chainId, plan, runForge, progress = () => {}) {
  const contracts = [];
  for (const r of plan) {
    const entry = { name: r.name, address: r.address, target: r.target, explorerUrl: EXPLORERS[chainId] + '/address/' + r.address + '?tab=contract' };
    if (r.kind === 'initcode-store') {
      contracts.push({ ...entry, status: 'bytecode-only', reason: 'STOP || creation bytecode; not a running Solidity contract. receipt and stored bytes checked locally.' });
      continue;
    }
    progress('verifying ' + r.name);
    try {
      const result = await runForge(verificationArgs(chainId, r));
      const ok = result.status === 0 && !result.error && !result.signal;
      contracts.push({ ...entry, status: ok ? 'verified' : 'failed', exitCode: result.status,
        output: [result.stdout, result.stderr, result.error?.message].filter(Boolean).join('\n') });
      progress(r.name + ': ' + (ok ? 'verified' : 'failed; retry verification, not deployment'));
    } catch (error) {
      contracts.push({ ...entry, status: 'failed', output: error.message });
      progress(r.name + ': verification failed');
    }
  }
  const counts = { verified: 0, failed: 0, 'bytecode-only': 0 };
  for (const r of contracts) counts[r.status]++;
  return { status: counts.failed ? 'incomplete' : 'complete', counts, contracts };
}
