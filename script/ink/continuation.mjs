import assert from 'node:assert/strict';
import { readdirSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { keccak, sha256, lower, readJson, validateConfig, validatePlan, planHash, collectTransactionEvidence } from './inventory.mjs';

const files = ['prepared.json', 'config.original.json', 'snapshot.original.json', 'candidate.json', 'transaction-plan.json'];
const names = ['WildcatArchController', 'SphereXEngine', 'SanctionsList'];
const seedSelector = '0x' + keccak(Buffer.from('addToSanctionsList(address[])')).slice(2, 10);
const word = n => BigInt(n).toString(16).padStart(64, '0');

export function readParent(path, archived = false) {
  const attempt = archived ? 'broadcast.json' : readdirSync(path).filter(n => /^broadcast-\d+\.json$/.test(n)).sort().at(-1);
  assert(attempt, 'parent has no archived broadcast attempt');
  const raw = Object.fromEntries([...files, attempt].map(name => [name === attempt ? 'broadcast.json' : name, readFileSync(join(path, name))]));
  const data = Object.fromEntries(Object.entries(raw).map(([name, bytes]) => [name, JSON.parse(bytes)]));
  return { raw, data, attempt, hashes: Object.fromEntries(Object.entries(raw).map(([name, bytes]) => [name, sha256(bytes)])) };
}

export function archiveParent(parent, run) {
  const path = join(run, 'parent');
  mkdirSync(path);
  for (const [name, bytes] of Object.entries(parent.raw)) writeFileSync(join(path, name), bytes, { flag: 'wx', mode: 0o600 });
}

export function validateParent(parent, c, snapshotHash) {
  const pc = parent.data['config.original.json'], ps = parent.data['snapshot.original.json'];
  const candidate = parent.data['candidate.json'], p = parent.data['prepared.json'];
  const plan = parent.data['transaction-plan.json'], broadcast = parent.data['broadcast.json'];
  validateConfig(pc, ps);
  assert.equal(c.chainId, 763373, 'continuation is Ink Sepolia only');
  for (const key of ['chainId', 'deployer', 'deployFeeRecipient', 'feeRecipient', 'protocolFeeBips']) {
    assert.equal(lower(c[key]), lower(pc[key]), 'continuation changed ' + key);
  }
  assert(c.mode !== 'live' || pc.mode === 'live', 'a rehearsal parent cannot become a live deployment');
  assert.equal(c.expectedNonce, pc.expectedNonce + 3, 'continuation must start after the three CREATEs');
  assert.equal(p.configHash, keccak(parent.raw['config.original.json']), 'parent config changed');
  assert.equal(p.snapshotHash, keccak(parent.raw['snapshot.original.json']), 'parent snapshot changed');
  assert.equal(snapshotHash, p.snapshotHash, 'keep the deferred snapshot unchanged');
  assert.equal(candidate.configHash, p.configHash);
  assert.equal(candidate.snapshotHash, p.snapshotHash);
  assert.equal(plan.candidateHash, parent.hashes['candidate.json'], 'parent candidate changed');
  assert.equal(plan.planHash, planHash(broadcast), 'parent plan changed');
  validatePlan(pc, candidate, broadcast);
  assert.deepEqual(candidate.contracts.slice(0, 3).map(r => r.name), names, 'unexpected deployed prefix');
  for (let i = 0; i < 3; ++i) {
    assert(!broadcast.transactions[i].transaction.to, 'prefix must contain only CREATEs');
    assert.equal(lower(broadcast.transactions[i].contractAddress), lower(candidate.contracts[i].address));
  }
  const list = candidate.contracts[2].address;
  const seedCount = Math.ceil(ps.addresses.length / 100);
  for (let i = 0; i < seedCount; ++i) {
    const t = broadcast.transactions[3 + i]?.transaction;
    const batch = ps.addresses.slice(i * 100, (i + 1) * 100);
    assert.equal(lower(t?.to), lower(list), 'unexpected call before continuation');
    assert.equal(lower(t.input), seedSelector + word(32) + word(batch.length) + batch.map(a => word(a)).join(''), 'parent seeding payload changed');
  }
  return { config: pc, candidate, broadcast, seedCount, prepared: p };
}

export async function checkPrefix(parent, c, snapshotHash, rpc) {
  const p = validateParent(parent, c, snapshotHash);
  for (const tag of ['latest', 'pending']) {
    assert.equal(Number(BigInt(await rpc('eth_getTransactionCount', [c.deployer, tag]))), c.expectedNonce, 'continuation nonce changed or pending transaction exists');
  }
  const prefix = { ...p.candidate, contracts: p.candidate.contracts.slice(0, 3), endNonce: c.expectedNonce };
  // fetch canonical receipts; a stale archived block hash isn't evidence of a different CREATE.
  return collectTransactionEvidence(c, prefix, p.broadcast.transactions.slice(0, 3), rpc);
}

export function combinedPlan(parent, c, candidate, broadcast) {
  const p = validateParent(parent, c, candidate.snapshotHash);
  assert.equal(candidate.startNonce, c.expectedNonce);
  assert.equal(candidate.sanctionsSeeded, false, 'continuation must record seeding as deferred');
  assert.equal(candidate.endNonce, p.candidate.endNonce - p.seedCount, 'only the seed calls may be removed');
  assert.deepEqual(candidate.contracts.slice(0, 3), p.candidate.contracts.slice(0, 3), 'reused contracts changed');
  assert.equal(candidate.sphereXPatternsHash, p.candidate.sphereXPatternsHash, 'SphereX patterns changed');
  const rest = p.broadcast.transactions.slice(3 + p.seedCount);
  assert.equal(broadcast.transactions.length, rest.length, 'continuation call count changed');
  const addressChanges = new Map(p.candidate.contracts.map(r => [lower(r.address), lower(candidate.contracts.find(x => x.name === r.name)?.address)]));
  const translateAddress = a => addressChanges.get(lower(a)) ?? lower(a);
  // ABI words only; bytecode and CREATE arguments are checked against build commitments and runtime bindings.
  const translateCall = input => input.slice(0, 10) + (input.slice(10).match(/.{64}/g) ?? []).map(w => {
    if (!/^0{24}/.test(w)) return w;
    const next = addressChanges.get('0x' + w.slice(24));
    return next ? '0'.repeat(24) + next.slice(2) : w;
  }).join('');
  for (let i = 0; i < rest.length; ++i) {
    const old = rest[i], next = broadcast.transactions[i], a = old.transaction, b = next.transaction;
    assert.equal(Boolean(b.to), Boolean(a.to), 'CREATE/call order changed');
    if (a.to) {
      assert.equal(lower(b.to), translateAddress(a.to), 'continuation call target changed');
      assert.equal(lower(b.input), translateCall(lower(a.input)), 'continuation call changed beyond address rebinding');
      assert.notEqual(lower(b.to), lower(candidate.contracts[2].address), 'continuation must not seed the list');
    } else assert.equal(lower(next.contractAddress), translateAddress(old.contractAddress), 'continuation CREATE order changed');
  }
  const combined = { ...broadcast, transactions: [...p.broadcast.transactions.slice(0, 3), ...broadcast.transactions] };
  const combinedCandidate = { ...candidate, startNonce: p.candidate.startNonce };
  const combinedConfig = { ...c, expectedNonce: p.config.expectedNonce };
  validatePlan(combinedConfig, combinedCandidate, combined);
  return { config: combinedConfig, candidate: combinedCandidate, broadcast: combined };
}

export function checkResumeRpc(cachePath, url) {
  const cache = readJson(cachePath).value;
  assert(Array.isArray(cache.transactions) && cache.transactions.length > 0, 'missing Forge RPC cache');
  assert(cache.transactions.every(t => t.rpc === url), 'saved Forge RPC differs; --rpc-url does not retarget --resume');
}
