import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { keccak, sha256 } from '../../script/ink/inventory.mjs';
import {
  EXPLORERS, validateVerificationInventory, verificationPlan, checkVerificationState,
  verificationArgs, verificationEnvironment, redactVerificationResult, verifyContracts,
} from '../../script/ink/verification.mjs';

const address = i => '0x' + i.toString(16).padStart(40, '0');
const hash = i => '0x' + i.toString(16).padStart(64, '0');
const root = resolve(import.meta.dirname, '../..');

function fixture(chainId = 763373) {
  const targets = [
    ['WildcatArchController', 'src/WildcatArchController.sol:WildcatArchController'],
    ['SphereXEngine', 'src/spherex-engine/SphereXEngine.sol:SphereXEngine'],
    ['SanctionsList', 'src/WildcatCopyOfChainalysisList.sol:WildcatCopyOfChainalysisList'],
    ['SanctionsAdapter', 'src/ChainalysisProxy.sol:ChainalysisProxy'],
    ['WildcatSanctionsSentinel', 'src/WildcatSanctionsSentinel.sol:WildcatSanctionsSentinel'],
    ['WildcatFeeRecipient', 'src/WildcatFeeRecipient.sol:WildcatFeeRecipient'],
    ['WildcatMarket_initCodeStorage', 'src/market/WildcatMarket.sol:WildcatMarket'],
    ['OpenTermHooks_initCodeStorage', 'src/access/OpenTermHooks.sol:OpenTermHooks'],
    ['FixedTermHooks_initCodeStorage', 'src/access/FixedTermHooks.sol:FixedTermHooks'],
    ['HooksFactory', 'src/HooksFactory.sol:HooksFactory'],
    ['MarketLens', 'src/lens/MarketLens.sol:MarketLens'],
    ['Wildcat4626WrapperFactory', 'src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory'],
    ['OpenAccessRoleProvider', 'src/OpenAccessRoleProvider.sol:OpenAccessRoleProvider'],
  ];
  if (chainId === 763373) targets.push(['MockArchControllerOwner', 'script/mock/MockArchControllerOwner.sol:MockArchControllerOwner']);
  const artifacts = new Map();
  const payloads = new Map();
  const inventory = { schemaVersion: 1, status: 'confirmed-bootstrap', mode: 'live', chainId, deployer: address(999) };
  inventory.contracts = targets.map(([name, target], index) => {
    const [path, contract] = target.split(':');
    artifacts.set(target, { bytecode: { object: '0x6000' }, deployedBytecode: { object: '0x6000' }, metadata: {
      compiler: { version: '0.8.25+commit.b61c2a91' },
      settings: { compilationTarget: { [path]: contract }, optimizer: { enabled: true, runs: 50000 }, viaIR: true, evmVersion: 'cancun', metadata: { bytecodeHash: 'none' } },
    } });
    const store = name.endsWith('_initCodeStorage');
    const constructorArgs = store ? '0x' : '0x' + '00'.repeat(31) + '01';
    const creation = store ? '0x6100035f81600a5f39f3006000' : '0x6000' + constructorArgs.slice(2);
    const runtime = store ? '0x006000' : '0x6000';
    const record = { name, artifact: target, address: address(index + 1), kind: store ? 'initcode-store' : 'contract', constructorArgs,
      creationCodeHash: keccak(creation), runtimeCodeHash: keccak(runtime), runtimeSize: store ? 3 : 2,
      transactionHash: hash(100 + index), blockHash: hash(10), blockNumber: 10 };
    payloads.set(record.address, { creation, runtime });
    return record;
  });
  const calls = [];
  const rpc = async (method, params) => {
    calls.push(method);
    if (method === 'eth_chainId') return '0x' + chainId.toString(16);
    if (method === 'web3_clientVersion') return 'op-reth/test';
    if (method === 'eth_getBlockByNumber') return params[0] === '0xa' ? { number: '0xa', hash: hash(10) } : { number: '0x14', hash: hash(20) };
    if (method === 'eth_getCode') return payloads.get(params[0]).runtime;
    const r = inventory.contracts.find(r => r.transactionHash === params[0]);
    if (method === 'eth_getTransactionReceipt') return { transactionHash: r.transactionHash, status: '0x1', from: inventory.deployer, contractAddress: r.address, blockNumber: '0xa', blockHash: hash(10) };
    if (method === 'eth_getTransactionByHash') return { hash: r.transactionHash, from: inventory.deployer, to: null, input: payloads.get(r.address).creation, blockNumber: '0xa', blockHash: hash(10), value: '0x0', chainId: '0x' + chainId.toString(16) };
    throw new Error('unexpected RPC method ' + method);
  };
  const loadArtifact = target => artifacts.get(target);
  return { inventory, artifacts, loadArtifact, rpc, calls };
}

test('builds explicit Blockscout commands for both chains with recorded constructor bytes', () => {
  for (const chainId of [57073, 763373]) {
    const f = fixture(chainId);
    const plan = verificationPlan(f.inventory, f.loadArtifact);
    assert.equal(plan.length, chainId === 763373 ? 14 : 13);
    const args = verificationArgs(chainId, plan[0]);
    for (const [flag, value] of [['--chain', String(chainId)], ['--verifier', 'blockscout'], ['--verifier-url', EXPLORERS[chainId] + '/api/'], ['--compiler-version', 'v0.8.25+commit.b61c2a91'], ['--num-of-optimizations', '50000'], ['--evm-version', 'cancun'], ['--constructor-args', plan[0].constructorArgs]]) {
      assert.equal(args[args.indexOf(flag) + 1], value);
    }
    assert(args.includes('--watch') && args.includes('--via-ir'));
    assert(!args.includes('--broadcast') && !args.includes('--rpc-url') && !args.includes('--compilation-profile'));
  }
});

test('rejects unconfirmed, incomplete, duplicate, and wrong-network inventory', () => {
  const f = fixture();
  assert.throws(() => validateVerificationInventory({ ...f.inventory, status: 'unconfirmed-candidate' }), /receipt-backed/);
  assert.throws(() => validateVerificationInventory({ ...f.inventory, chainId: 11155111 }), /unsupported/);
  assert.throws(() => validateVerificationInventory({ ...f.inventory, mode: 'test' }), /mode/);
  assert.throws(() => validateVerificationInventory({ ...f.inventory, contracts: f.inventory.contracts.slice(1) }), /contract set/);
  f.inventory.contracts[1].address = f.inventory.contracts[0].address;
  assert.throws(() => verificationPlan(f.inventory, f.loadArtifact), /duplicate/);
});

test('rejects changed source builds, compiler settings, constructor args, and artifact labels', () => {
  const f = fixture();
  const r = f.inventory.contracts[0];
  const a = f.artifacts.get(r.artifact);
  a.metadata.settings.optimizer.runs = 200;
  assert.throws(() => verificationPlan(f.inventory, f.loadArtifact), /optimizer/);
  a.metadata.settings.optimizer.runs = 50000;
  r.constructorArgs += '00';
  assert.throws(() => verificationPlan(f.inventory, f.loadArtifact), /build\/constructor/);
  r.constructorArgs = r.constructorArgs.slice(0, -2);
  a.bytecode.object = '0x6001';
  assert.throws(() => verificationPlan(f.inventory, f.loadArtifact), /build\/constructor/);
  r.artifact = 'src/Other.sol:Other';
  assert.throws(() => verificationPlan(f.inventory, f.loadArtifact), /artifact mismatch/);
});

test('checks stored initcode exactly and never submits it as a market or hook instance', async () => {
  const f = fixture();
  const plan = verificationPlan(f.inventory, f.loadArtifact);
  const store = plan.find(r => r.kind === 'initcode-store');
  assert.throws(() => verificationArgs(f.inventory.chainId, store), /not Solidity/);
  const submitted = [];
  const result = await verifyContracts(f.inventory.chainId, plan, args => { submitted.push(args[1]); return { status: 0 }; });
  assert.equal(result.status, 'complete');
  assert.deepEqual(result.counts, { verified: 11, failed: 0, 'bytecode-only': 3 });
  assert(!submitted.includes(store.address));
  f.inventory.contracts.find(r => r.kind === 'initcode-store').runtimeCodeHash = hash(99);
  assert.throws(() => verificationPlan(f.inventory, f.loadArtifact), /stored initcode/);
});

test('checks current code and canonical creation evidence without requiring bootstrap ownership or nonce', async () => {
  const f = fixture();
  const plan = verificationPlan(f.inventory, f.loadArtifact);
  const checkpoint = await checkVerificationState(f.inventory, plan, f.rpc, 'https://rpc.example.test');
  assert.deepEqual(checkpoint, { number: 20, hash: hash(20) });
  assert(!f.calls.includes('eth_getTransactionCount') && !f.calls.includes('eth_call'));
  await assert.rejects(checkVerificationState(f.inventory, plan,
    (m, p) => m === 'web3_clientVersion' ? 'anvil/test' : f.rpc(m, p), 'http://127.0.0.1:8548'), /live inventory/);
});

test('rejects changed runtime, creation transactions, reverted receipts, and reorgs before submission', async () => {
  const f = fixture();
  const plan = verificationPlan(f.inventory, f.loadArtifact);
  for (const [method, change, error] of [
    ['eth_getCode', () => '0x6001', /deployed code/],
    ['eth_getTransactionByHash', tx => ({ ...tx, input: '0x6001' }), /creation transaction/],
    ['eth_getTransactionReceipt', receipt => ({ ...receipt, status: '0x0' }), /reverted/],
    ['eth_getBlockByNumber', block => ({ ...block, hash: hash(99) }), /reorged/],
  ]) {
    const rpc = async (m, p) => m === method ? change(await f.rpc(m, p)) : f.rpc(m, p);
    await assert.rejects(checkVerificationState(f.inventory, plan, rpc, 'https://rpc.example.test'), error);
  }
});

test('partial failures are visible, later contracts still run, and retries are verification-only', async () => {
  const f = fixture();
  const plan = verificationPlan(f.inventory, f.loadArtifact);
  let attempts = 0;
  const failed = await verifyContracts(f.inventory.chainId, plan, () => ++attempts === 2 ? { status: 1, stderr: 'Pending in queue' } : { status: 0 });
  assert.equal(attempts, 11);
  assert.equal(failed.status, 'incomplete');
  assert.equal(failed.counts.failed, 1);
  const retried = await verifyContracts(f.inventory.chainId, plan, args => {
    assert.equal(args[0], 'verify-contract');
    assert(!args.includes('--broadcast'));
    return { status: 0, stdout: 'Contract source code already verified' };
  });
  assert.equal(retried.status, 'complete');
});

test('timeouts and spawn failures never count as verified', async () => {
  const f = fixture();
  const plan = verificationPlan(f.inventory, f.loadArtifact).filter(r => r.kind === 'contract').slice(0, 2);
  let attempts = 0;
  const result = await verifyContracts(f.inventory.chainId, plan, () => {
    if (++attempts === 1) return { status: null, signal: 'SIGTERM', error: new Error('timeout') };
    throw new Error('forge missing');
  });
  assert.equal(result.counts.failed, 2);
  assert.equal(result.status, 'incomplete');
});

test('the optional Ink API key is environment-only and redacted from saved output', () => {
  const env = verificationEnvironment({ PATH: '/bin', ETHERSCAN_API_KEY: 'unrelated', VERIFIER_API_KEY: 'unrelated', VERIFIER_URL: 'other', ETH_RPC_URL: 'secret-url' }, 'ink-test-key');
  assert.equal(env.ETHERSCAN_API_KEY, 'ink-test-key');
  assert.equal(env.FOUNDRY_PROFILE, 'ink');
  assert.equal(env.VERIFIER_API_KEY, '');
  assert.equal(env.VERIFIER_URL, undefined);
  assert.equal(env.ETH_RPC_URL, undefined);
  assert.equal(verificationEnvironment(env).ETHERSCAN_API_KEY, '');
  const result = redactVerificationResult({ status: 1, stdout: 'ink-test-key', stderr: 'invalid ink-test-key', error: new Error('ink-test-key') }, 'ink-test-key');
  assert(!JSON.stringify(result).includes('ink-test-key'));
  assert.equal(result.stdout, '[redacted]');
});

test('CLI skips rehearsal without RPC or explorer calls and preserves inventory on live preflight failure', () => {
  const runRoot = resolve(root, 'deployments/ink/runs');
  mkdirSync(runRoot, { recursive: true });
  const run = mkdtempSync(resolve(runRoot, 'verification-test-'));
  try {
    const f = fixture();
    f.inventory.mode = 'rehearsal';
    const original = JSON.stringify(f.inventory);
    writeFileSync(resolve(run, 'inventory.json'), original, { flag: 'wx' });
    const env = { ...process.env, INK_RPC_URL: '', INK_BLOCKSCOUT_API_KEY: 'ink-test-key' };
    const skipped = spawnSync(process.execPath, ['script/ink/ink.mjs', 'verify', run], { cwd: root, env, encoding: 'utf8' });
    assert.equal(skipped.status, 0, skipped.stderr);
    let reports = readdirSync(run).filter(name => name.startsWith('verification-'));
    assert.equal(reports.length, 1);
    const report = JSON.parse(readFileSync(resolve(run, reports[0])));
    assert.equal(report.status, 'skipped-rehearsal');
    assert.equal(report.inventoryHash, sha256(original));
    f.inventory.mode = 'live';
    const live = JSON.stringify(f.inventory);
    writeFileSync(resolve(run, 'inventory.json'), live);
    const failed = spawnSync(process.execPath, ['script/ink/ink.mjs', 'verify', run], { cwd: root, env, encoding: 'utf8' });
    assert.equal(failed.status, 1);
    assert.match(failed.stderr, /do not redeploy/);
    assert.equal(readFileSync(resolve(run, 'inventory.json'), 'utf8'), live);
    reports = readdirSync(run).filter(name => name.startsWith('verification-'));
    assert.equal(reports.length, 2);
    assert(!reports.some(name => readFileSync(resolve(run, name), 'utf8').includes('ink-test-key')));
  } finally {
    rmSync(run, { recursive: true });
  }
});
