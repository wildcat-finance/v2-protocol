import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { CORE, PLASMA, keccak, sha256, planHash, collectEvidence } from '../../script/ink/inventory.mjs';
import { validateParent, combinedPlan, checkPrefix, checkResumeRpc } from '../../script/ink/continuation.mjs';
import { validateVerificationInventory } from '../../script/ink/verification.mjs';

const addr = n => '0x' + BigInt(n).toString(16).padStart(40, '0');
const word = n => BigInt(n).toString(16).padStart(64, '0');
const hash = n => '0x' + word(n);
const code = '0x6000', codeHash = keccak(code);
const selector = sig => keccak(Buffer.from(sig)).slice(0, 10);

function fixture() {
  const config = { schemaVersion: 1, chainId: 763373, mode: 'live', deployer: addr(999), expectedNonce: 1, deployFeeRecipient: false, feeRecipient: addr(998), protocolFeeBips: 500, sanctionsSnapshot: 'snapshot.json' };
  const snapshot = { schemaVersion: 1, sourceChainId: 1, sourceOracle: addr(900), sourceBlockNumber: 1, sourceBlockHash: hash(1), fixture: false, addresses: Array.from({ length: 137 }, (_, i) => addr(i + 1000)) };
  const rawConfig = Buffer.from(JSON.stringify(config)), rawSnapshot = Buffer.from(JSON.stringify(snapshot));
  const prepared = { configHash: keccak(rawConfig), snapshotHash: keccak(rawSnapshot) };
  const names = ['WildcatArchController', 'SphereXEngine', 'SanctionsList', 'SanctionsAdapter', 'WildcatSanctionsSentinel', 'WildcatMarket_initCodeStorage', 'OpenTermHooks_initCodeStorage', 'FixedTermHooks_initCodeStorage', 'HooksFactory', 'MarketLens', 'Wildcat4626WrapperFactory', 'OpenAccessRoleProvider', 'MockArchControllerOwner'];
  const contracts = names.map((name, i) => ({ name, address: addr(i + 1), artifact: 'Fixture', kind: name.endsWith('_initCodeStorage') ? 'initcode-store' : 'contract', constructorArgs: '0x', creationCodeHash: codeHash, runtimeCodeHash: codeHash, runtimeSize: 2 }));
  const transactions = [];
  const push = (to, input, contractAddress = to) => transactions.push({ hash: hash(transactions.length + 100), contractAddress, transaction: { from: config.deployer, to, input, value: '0x0', nonce: '0x' + (transactions.length + 1).toString(16) } });
  for (const r of contracts.slice(0, 3)) push(null, code, r.address);
  for (const batch of [snapshot.addresses.slice(0, 100), snapshot.addresses.slice(100)]) {
    push(contracts[2].address, selector('addToSanctionsList(address[])') + word(32) + word(batch.length) + batch.map(word).join(''));
  }
  for (const r of contracts.slice(3)) push(null, code, r.address);
  push(contracts[3].address, selector('setSanctionsRegistry(address)') + word(contracts[2].address));
  push(contracts[0].address, selector('transferOwnership(address)') + word(contracts.at(-1).address));
  const candidate = { schemaVersion: 1, status: 'unconfirmed-candidate', coreCommit: CORE, plasmaReference: PLASMA, chainId: config.chainId, deployer: config.deployer, startNonce: 1, endNonce: transactions.length + 1, contractCount: contracts.length, contracts, configHash: prepared.configHash, snapshotHash: prepared.snapshotHash, sphereXPatternsHash: hash(130) };
  const rawCandidate = Buffer.from(JSON.stringify(candidate));
  const broadcast = { chain: config.chainId, transactions, receipts: [{ blockHash: hash(777) }] };
  const parent = {
    raw: { 'config.original.json': rawConfig, 'snapshot.original.json': rawSnapshot },
    hashes: { 'candidate.json': sha256(rawCandidate) },
    data: { 'config.original.json': config, 'snapshot.original.json': snapshot, 'prepared.json': prepared, 'candidate.json': candidate, 'broadcast.json': broadcast, 'transaction-plan.json': { candidateHash: sha256(rawCandidate), planHash: planHash(broadcast) } },
  };
  const c = { ...config, expectedNonce: 4, mode: 'rehearsal' };
  const next = { ...candidate, startNonce: 4, endNonce: candidate.endNonce - 2, sanctionsSeeded: false, contracts: contracts.map((r, i) => ({ ...r, address: i < 3 ? r.address : addr(i + 50) })) };
  const translate = a => next.contracts[contracts.findIndex(r => r.address === a)]?.address ?? a;
  const continuation = { chain: config.chainId, transactions: transactions.slice(5).map((t, i) => ({ ...t, hash: hash(200 + i), contractAddress: translate(t.contractAddress), transaction: { ...t.transaction, to: translate(t.transaction.to), nonce: '0x' + (i + 4).toString(16), input: t.transaction.input.replace(word(contracts.at(-1).address), word(next.contracts.at(-1).address)) } })) };
  return { c, parent, next, continuation, snapshotHash: prepared.snapshotHash };
}

test('an explicit continuation renumbers the remaining plan and keeps the public-registration handoff', () => {
  const f = fixture();
  const combined = combinedPlan(f.parent, f.c, f.next, f.continuation);
  assert.equal(combined.candidate.startNonce, 1);
  assert.equal(combined.broadcast.transactions.length, f.parent.data['broadcast.json'].transactions.length - 2);
  assert.equal(combined.broadcast.transactions.at(-1).transaction.input, selector('transferOwnership(address)') + word(f.next.contracts.at(-1).address));
  assert.equal(combined.broadcast.transactions[3].transaction.nonce, '0x4');
});

test('only seeding may be omitted; handoff and other configuration calls must survive', () => {
  const f = fixture();
  f.continuation.transactions.pop();
  assert.throws(() => combinedPlan(f.parent, f.c, f.next, f.continuation), /call count/);
  const g = fixture();
  g.continuation.transactions.at(-1).transaction.input = selector('transferOwnership(address)') + word(g.c.deployer);
  assert.throws(() => combinedPlan(g.parent, g.c, g.next, g.continuation), /rebinding/);
});

test('reused records, seeding status, destinations and nonce sequence cannot drift', () => {
  for (const mutate of [
    f => { f.next.contracts[0].runtimeSize = 3; },
    f => { f.next.sanctionsSeeded = true; },
    f => { f.continuation.transactions.at(-1).transaction.to = f.next.contracts[2].address; },
    f => { f.continuation.transactions[0].transaction.nonce = '0x5'; },
  ]) {
    const f = fixture(); mutate(f);
    assert.throws(() => combinedPlan(f.parent, f.c, f.next, f.continuation));
  }
});

test('parent commitments, fees, snapshot, network and starting nonce are checked', () => {
  for (const mutate of [
    f => { f.c.protocolFeeBips = 1000; },
    f => { f.c.expectedNonce = 5; },
    f => { f.c.chainId = 57073; },
    f => { f.snapshotHash = hash(999); },
    f => { f.parent.data['broadcast.json'].transactions[3].transaction.input += '00'; },
    f => { f.parent.hashes['candidate.json'] = 'changed'; },
  ]) {
    const f = fixture(); mutate(f);
    assert.throws(() => validateParent(f.parent, f.c, f.snapshotHash));
  }
});

function rpcFor(f, txs, nonce) {
  return async (method, params = []) => {
    if (method === 'eth_getTransactionCount') return '0x' + nonce.toString(16);
    if (method === 'eth_getBlockByNumber') return { number: '0xa', hash: hash(10) };
    if (method === 'eth_getCode') return code;
    const t = txs.find(t => t.hash === params[0]);
    if (method === 'eth_getTransactionReceipt') return t && { transactionHash: t.hash, status: '0x1', from: f.c.deployer, blockNumber: '0xa', blockHash: hash(10), contractAddress: t.transaction.to ? null : t.contractAddress };
    if (method === 'eth_getTransactionByHash') return t && { ...t.transaction, hash: t.hash, blockNumber: '0xa', blockHash: hash(10) };
    throw new Error('unexpected RPC: ' + method);
  };
}

test('prefix uses current canonical receipts, not an archived stale block hash', async () => {
  const f = fixture(), txs = f.parent.data['broadcast.json'].transactions.slice(0, 3);
  const result = await checkPrefix(f.parent, f.c, f.snapshotHash, rpcFor(f, txs, 4));
  assert.equal(result.receipts.length, 3);
  assert(result.receipts.every(r => r.blockHash === hash(10)));
  await assert.rejects(checkPrefix(f.parent, f.c, f.snapshotHash, rpcFor(f, txs, 5)), /nonce/);
  await assert.rejects(checkPrefix(f.parent, f.c, f.snapshotHash, rpcFor(f, txs.slice(0, 2), 4)), /missing/);
});

test('combined inventory requires receipts for both the parent and continuation', async () => {
  const f = fixture(), p = combinedPlan(f.parent, f.c, f.next, f.continuation);
  const rpc = rpcFor(f, p.broadcast.transactions, f.next.endNonce);
  const evidence = await collectEvidence(p.config, p.candidate, p.broadcast, rpc);
  assert.equal(evidence.contracts.length, 13);
  await assert.rejects(collectEvidence(p.config, p.candidate, p.broadcast, rpcFor(f, p.broadcast.transactions.slice(1), f.next.endNonce)), /missing/);
});

test('deferred inventory can be source-verified but is not a seeded bootstrap', () => {
  const f = fixture();
  const inventory = { ...f.next, status: 'confirmed-contracts-sanctions-pending', mode: 'rehearsal', launchReady: false, sanctions: { status: 'deferred', observedCount: 0 } };
  validateVerificationInventory(inventory);
  assert.throws(() => validateVerificationInventory({ ...inventory, chainId: 57073 }), /testnet/);
  assert.throws(() => validateVerificationInventory({ ...inventory, launchReady: true }));
});

test('resume refuses an inherited RPC destination even if the command uses another URL', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ink-continuation-cache-'));
  try {
    const path = join(dir, 'cache.json'), url = 'http://127.0.0.1:18548';
    writeFileSync(path, JSON.stringify({ transactions: [{ rpc: url }] }));
    checkResumeRpc(path, url);
    assert.throws(() => checkResumeRpc(path, 'http://127.0.0.1:8549'), /does not retarget/);
  } finally { rmSync(dir, { recursive: true }); }
});
