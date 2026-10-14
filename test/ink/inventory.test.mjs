import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { CORE, PLASMA, TESTNET_OWNER_SOURCE, validateTestnetOwnerSource, validateConfig, validatePlan, collectEvidence, checkEndpoint, keccak } from '../../script/ink/inventory.mjs';

const addr = i => '0x' + i.toString(16).padStart(40, '0');
const hash = i => '0x' + i.toString(16).padStart(64, '0');
function fixture(chainId = 57073) {
  const config = { schemaVersion: 1, chainId, mode: 'rehearsal', deployer: addr(999), expectedNonce: 0, deployFeeRecipient: false, feeRecipient: addr(998), protocolFeeBips: 500, sanctionsSnapshot: 'fixture.json' };
  const snapshot = { schemaVersion: 1, sourceChainId: 1, sourceOracle: addr(1), sourceBlockNumber: 1, sourceBlockHash: hash(1), fixture: true, addresses: [addr(44), addr(45)] };
  const names = ['WildcatArchController', 'SphereXEngine', 'SanctionsList', 'SanctionsAdapter', 'WildcatSanctionsSentinel', 'WildcatMarket_initCodeStorage', 'OpenTermHooks_initCodeStorage', 'FixedTermHooks_initCodeStorage', 'HooksFactory', 'MarketLens', 'Wildcat4626WrapperFactory', 'OpenAccessRoleProvider'];
  if (chainId === 763373) names.push('MockArchControllerOwner');
  const code = '0x6000';
  const codeHash = keccak(code);
  const contracts = names.map((name, i) => ({ name, address: addr(i + 1), kind: name.endsWith('_initCodeStorage') ? 'initcode-store' : 'contract', artifact: 'Fixture', constructorArgs: '0x', creationCodeHash: codeHash, runtimeCodeHash: codeHash, runtimeSize: 2 }));
  const candidate = { schemaVersion: 1, status: 'unconfirmed-candidate', coreCommit: CORE, plasmaReference: PLASMA, chainId, deployer: config.deployer, startNonce: 0, endNonce: contracts.length, contractCount: contracts.length, contracts };
  const transactions = contracts.map((r, i) => ({ hash: hash(100 + i), contractAddress: r.address, transaction: { from: config.deployer, to: null, nonce: '0x' + i.toString(16), value: '0x0', input: code } }));
  const broadcast = { chain: chainId, transactions };
  const receipts = transactions.map(t => ({ transactionHash: t.hash, status: '0x1', from: config.deployer, blockNumber: '0xa', blockHash: hash(10), contractAddress: t.contractAddress }));
  const rpc = async (method, params = []) => {
    if (method === 'eth_getBlockByNumber') return { number: '0xa', hash: hash(10) };
    if (method === 'eth_getTransactionReceipt') return receipts.find(r => r.transactionHash === params[0]);
    if (method === 'eth_getTransactionByHash') {
      const t = transactions.find(t => t.hash === params[0]);
      return t && { ...t.transaction, hash: t.hash, blockNumber: '0xa', blockHash: hash(10) };
    }
    if (method === 'eth_getCode') return code;
    if (method === 'eth_getTransactionCount') return '0x' + contracts.length.toString(16);
    if (method === 'eth_chainId') return '0x' + chainId.toString(16);
    if (method === 'web3_clientVersion') return 'anvil/test';
    throw new Error('unexpected RPC method ' + method);
  };
  return { config, snapshot, candidate, broadcast, receipts, rpc };
}

test('requires the exact pinned V2.5 testnet helper source', () => {
  const source = readFileSync(new URL('../../' + TESTNET_OWNER_SOURCE.path, import.meta.url));
  validateTestnetOwnerSource(source);
  assert.throws(() => validateTestnetOwnerSource(Buffer.concat([source, Buffer.from('\n')])), /source changed/);
});
test('fee validation matches the factory limit', () => {
  const { config, snapshot } = fixture();
  for (const fee of [0, 500, 1000]) validateConfig({ ...config, protocolFeeBips: fee }, snapshot);
  for (const fee of [-1, 1001, 10000]) {
    assert.throws(() => validateConfig({ ...config, protocolFeeBips: fee }, snapshot), /invalid fee/);
  }
});
test('testnet inventory requires a receipt-backed helper; mainnet excludes it', async () => {
  const f = fixture(763373);
  await checkEndpoint(f.config, f.rpc, 'http://127.0.0.1:8545');
  const evidence = await collectEvidence(f.config, f.candidate, f.broadcast, f.rpc);
  assert.equal(evidence.contracts.length, 13);
  assert.equal(evidence.contracts.at(-1).name, 'MockArchControllerOwner');
  assert.equal(evidence.contracts.at(-1).transactionHash, f.receipts.at(-1).transactionHash);
  f.config.chainId = f.candidate.chainId = f.broadcast.chain = 57073;
  assert.throws(() => validatePlan(f.config, f.candidate, f.broadcast));
});
test('testnet cannot promote a deployment missing the helper', () => {
  const f = fixture();
  f.config.chainId = f.candidate.chainId = f.broadcast.chain = 763373;
  assert.throws(() => validatePlan(f.config, f.candidate, f.broadcast));
});

test('accepts explicit config and rejects live fixtures, duplicates, unknown keys', () => {
  const { config: c, snapshot: s } = fixture();
  validateConfig(c, s);
  assert.throws(() => validateConfig({ ...c, mode: 'live' }, s), /fixture/);
  assert.throws(() => validateConfig(c, { ...s, addresses: [addr(1), addr(1)] }), /unique/);
  assert.throws(() => validateConfig({ ...c, key: 'secret' }, s), /field/);
  assert.throws(() => validateConfig({ ...c, feeRecipient: addr(0) }, s));
});
test('rehearsal/live inventory namespaces cannot be confused', async () => {
  const f = fixture();
  await checkEndpoint(f.config, f.rpc, 'http://127.0.0.1:8545');
  await assert.rejects(checkEndpoint(f.config, f.rpc, 'https://example.com'), /loopback/);
  await assert.rejects(checkEndpoint({ ...f.config, mode: 'live' }, f.rpc, 'http://127.0.0.1:8545'), /live inventory/);
});
test('rejects missing CREATEs and nonce drift', () => {
  const f = fixture();
  validatePlan(f.config, f.candidate, f.broadcast);
  f.broadcast.transactions[0].transaction.nonce = '0x1';
  assert.throws(() => validatePlan(f.config, f.candidate, f.broadcast), /nonce/);
  f.broadcast.transactions.shift();
  assert.throws(() => validatePlan(f.config, f.candidate, f.broadcast), /incomplete/);
});
test('requires exact creation payloads, addresses, and chain', () => {
  const f = fixture();
  f.broadcast.transactions[0].transaction.input = '0x6001';
  assert.throws(() => validatePlan(f.config, f.candidate, f.broadcast), /payload/);
  f.broadcast.chain = 1;
  assert.throws(() => validatePlan(f.config, f.candidate, f.broadcast), /chain/);
});
test('promotes only a complete receipt-backed deployment', async () => {
  const f = fixture();
  const evidence = await collectEvidence(f.config, f.candidate, f.broadcast, f.rpc);
  assert.equal(evidence.contracts.length, 12);
  assert.equal(evidence.receipts.length, 12);
});
test('interrupted run cannot promote; same plan can collect after final receipt', async () => {
  const f = fixture();
  const last = f.receipts.pop();
  await assert.rejects(collectEvidence(f.config, f.candidate, f.broadcast, f.rpc), /pending/);
  f.receipts.push(last);
  assert.equal((await collectEvidence(f.config, f.candidate, f.broadcast, f.rpc)).contracts.length, 12);
});
test('reverted transactions, changed code and changed transaction bodies fail closed', async () => {
  const f = fixture();
  f.receipts[0].status = '0x0';
  await assert.rejects(collectEvidence(f.config, f.candidate, f.broadcast, f.rpc), /reverted/);
  f.receipts[0].status = '0x1';
  const wrongCode = (m, p) => m === 'eth_getCode' ? '0x6001' : f.rpc(m, p);
  await assert.rejects(collectEvidence(f.config, f.candidate, f.broadcast, wrongCode), /runtime hash/);
  const wrongBody = async (m, p) => m === 'eth_getTransactionByHash' ? { ...await f.rpc(m, p), input: '0x6001' } : f.rpc(m, p);
  await assert.rejects(collectEvidence(f.config, f.candidate, f.broadcast, wrongBody), /input mismatch/);
});
test('confirmation depth and canonical block hashes are required', async () => {
  const f = fixture();
  await assert.rejects(collectEvidence(f.config, f.candidate, f.broadcast, f.rpc, 12), /confirmations/);
  f.receipts[0].blockHash = hash(11);
  await assert.rejects(collectEvidence(f.config, f.candidate, f.broadcast, f.rpc), /reorged/);
});
test('post-deployment deployer activity requires explicit reconciliation', async () => {
  const f = fixture();
  const rpc = (m, p) => m === 'eth_getTransactionCount' ? '0xd' : f.rpc(m, p);
  await assert.rejects(collectEvidence(f.config, f.candidate, f.broadcast, rpc), /outside this run/);
});
