import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

export const CORE = 'c7be4039f8f383a9dda4e45f63331c17d63f9ed9';
export const PLASMA = '1bc514b1b0b903b1e94ca8046741fa8c9d367294';
export const TESTNET_OWNER_SOURCE = Object.freeze({
  commit: '05165ad4c4020c1400048680b85b3585f84e8527',
  path: 'script/mock/MockArchControllerOwner.sol',
  sha256: 'af9c73d6b6fed19f2027c625011e82a64946feed3fe481177cadeb84bf80693a',
  version: '2',
});
const address = /^0x[0-9a-fA-F]{40}$/;
const hash = /^0x[0-9a-fA-F]{64}$/;
const bytes = /^0x(?:[0-9a-fA-F]{2})*$/;
export const lower = x => String(x).toLowerCase();
export const sha256 = data => createHash('sha256').update(data).digest('hex');
export function validateTestnetOwnerSource(source) {
  // the helper is a verbatim backport; the Ink clone needn't contain V2.5 history.
  assert.equal(sha256(source), TESTNET_OWNER_SOURCE.sha256, 'testnet owner source changed');
}
export function keccak(data) {
  const input = Buffer.isBuffer(data) ? '0x' + data.toString('hex') : data;
  assert(bytes.test(input), 'invalid hash input');
  return execFileSync('cast', ['keccak', input], { encoding: 'utf8', maxBuffer: 1024 * 1024 }).trim();
}
export function readJson(path) {
  const raw = readFileSync(path);
  assert(raw.length < 16 * 1024 * 1024, 'JSON input exceeds 16 MiB');
  return { raw, value: JSON.parse(raw) };
}
function validAddress(x) { return address.test(x) && BigInt(x) !== 0n; }
function exactKeys(value, keys, name) {
  assert(value && typeof value === 'object' && !Array.isArray(value), name + ' must be an object');
  assert.deepEqual(Object.keys(value).sort(), keys.sort(), name + ': missing/unknown field');
}

export function validateConfig(c, s) {
  exactKeys(c, ['schemaVersion', 'chainId', 'mode', 'deployer', 'expectedNonce', 'deployFeeRecipient', 'feeRecipient', 'protocolFeeBips', 'sanctionsSnapshot'], 'config');
  exactKeys(s, ['schemaVersion', 'sourceChainId', 'sourceOracle', 'sourceBlockNumber', 'sourceBlockHash', 'fixture', 'addresses'], 'snapshot');
  assert.equal(c.schemaVersion, 1);
  assert([57073, 763373].includes(c.chainId), 'unsupported Ink chain');
  assert(['rehearsal', 'live'].includes(c.mode), 'explicit rehearsal/live mode required');
  assert(validAddress(c.deployer) && validAddress(c.feeRecipient), 'deployer/fee recipient required');
  assert(Number.isSafeInteger(c.expectedNonce) && c.expectedNonce >= 0, 'invalid nonce');
  assert(Number.isInteger(c.protocolFeeBips) && c.protocolFeeBips >= 0 && c.protocolFeeBips <= 10000, 'invalid fee');
  assert.equal(typeof c.deployFeeRecipient, 'boolean');
  assert.equal(typeof c.sanctionsSnapshot, 'string');
  assert.equal(s.schemaVersion, 1);
  assert.equal(s.sourceChainId, 1);
  assert(validAddress(s.sourceOracle), 'snapshot source oracle required');
  assert(Number.isSafeInteger(s.sourceBlockNumber) && s.sourceBlockNumber > 0, 'snapshot block required');
  assert(hash.test(s.sourceBlockHash) && BigInt(s.sourceBlockHash) !== 0n, 'snapshot block hash required');
  assert.equal(typeof s.fixture, 'boolean');
  assert(c.mode !== 'live' || !s.fixture, 'fixture sanctions cannot be used live');
  assert(Array.isArray(s.addresses) && s.addresses.length > 0 && s.addresses.length <= 10000, 'snapshot must contain 1..10000 addresses');
  let previous = 0n;
  for (const a of s.addresses) {
    assert(validAddress(a) && BigInt(a) > previous, 'snapshot addresses must be sorted, unique, nonzero');
    previous = BigInt(a);
  }
}

export function rpcClient(url) {
  const parsed = new URL(url);
  assert(['http:', 'https:'].includes(parsed.protocol), 'HTTP(S) RPC required');
  let id = 0;
  return async (method, params = []) => {
    try {
      const response = await fetch(url, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: ++id, method, params }),
        signal: AbortSignal.timeout(30000),
      });
      assert(response.ok, 'HTTP ' + response.status);
      const data = await response.json();
      assert(!data.error && Object.hasOwn(data, 'result'), 'JSON-RPC failure');
      return data.result;
    } catch {
      // RPC URLs and upstream errors can contain credentials; don't echo them.
      throw new Error('RPC request failed: ' + method);
    }
  };
}

export async function checkEndpoint(c, rpc, url) {
  assert.equal(Number(BigInt(await rpc('eth_chainId'))), c.chainId, 'RPC chain mismatch');
  const client = await rpc('web3_clientVersion');
  const anvil = /anvil/i.test(client);
  if (c.mode === 'rehearsal') {
    assert(['localhost', '127.0.0.1', '[::1]'].includes(new URL(url).hostname) && anvil, 'rehearsal requires loopback Anvil');
  } else assert(!anvil, 'live inventory cannot use Anvil');
  return client;
}

const REQUIRED = [
  'WildcatArchController', 'SphereXEngine', 'SanctionsList', 'SanctionsAdapter',
  'WildcatSanctionsSentinel', 'WildcatMarket_initCodeStorage', 'OpenTermHooks_initCodeStorage',
  'FixedTermHooks_initCodeStorage', 'HooksFactory', 'MarketLens', 'Wildcat4626WrapperFactory',
  'OpenAccessRoleProvider',
];
export function validatePlan(c, candidate, broadcast) {
  assert.equal(candidate.schemaVersion, 1);
  assert.equal(candidate.status, 'unconfirmed-candidate');
  assert.equal(candidate.coreCommit, CORE);
  assert.equal(candidate.plasmaReference, PLASMA);
  assert.equal(candidate.chainId, c.chainId);
  assert.equal(Number(broadcast.chain), c.chainId, 'broadcast chain mismatch');
  assert.equal(lower(candidate.deployer), lower(c.deployer));
  assert.equal(candidate.startNonce, c.expectedNonce);
  assert(Number.isSafeInteger(candidate.endNonce) && candidate.endNonce > candidate.startNonce);
  const expected = [...REQUIRED];
  if (c.deployFeeRecipient) expected.push('WildcatFeeRecipient');
  if (c.chainId === 763373) expected.push('MockArchControllerOwner');
  assert.equal(candidate.contractCount, expected.length);
  assert.equal(candidate.contracts.length, expected.length);
  assert.deepEqual(candidate.contracts.map(x => x.name).sort(), expected.sort(), 'contract manifest mismatch');
  const byAddress = new Map();
  for (const r of candidate.contracts) {
    assert(validAddress(r.address) && !byAddress.has(lower(r.address)), 'duplicate/invalid deployment address');
    assert(hash.test(r.creationCodeHash) && hash.test(r.runtimeCodeHash), 'missing code commitments');
    assert(bytes.test(r.constructorArgs), 'invalid constructor args');
    assert(Number.isInteger(r.runtimeSize) && r.runtimeSize > 0 && r.runtimeSize <= 24576, 'runtime size limit');
    assert.equal(r.kind, r.name.endsWith('_initCodeStorage') ? 'initcode-store' : 'contract');
    byAddress.set(lower(r.address), r);
  }
  const txs = broadcast.transactions;
  assert(Array.isArray(txs) && txs.length === candidate.endNonce - candidate.startNonce, 'incomplete transaction plan');
  const created = new Set();
  for (let i = 0; i < txs.length; i++) {
    const t = txs[i].transaction;
    assert(t && lower(t.from) === lower(c.deployer), 'unexpected transaction sender');
    assert.equal(BigInt(t.nonce), BigInt(c.expectedNonce + i), 'non-contiguous nonce sequence');
    assert.equal(BigInt(t.value ?? '0x0'), 0n, 'unexpected ETH transfer');
    assert(bytes.test(t.input), 'invalid transaction input');
    if (t.chainId !== undefined) assert.equal(Number(BigInt(t.chainId)), c.chainId, 'transaction chain mismatch');
    if (t.to === null || t.to === undefined) {
      const r = byAddress.get(lower(txs[i].contractAddress));
      assert(r && !created.has(lower(r.address)), 'unexpected/duplicate CREATE');
      assert.equal(keccak(t.input), lower(r.creationCodeHash), 'creation payload mismatch');
      created.add(lower(r.address));
    } else assert(byAddress.has(lower(t.to)), 'call outside deployment');
  }
  assert.equal(created.size, expected.length, 'missing CREATE transaction');
  return txs;
}

export function planHash(broadcast) {
  return sha256(JSON.stringify(broadcast.transactions.map(({ contractAddress, transaction: t }) => ({
    from: lower(t.from), to: t.to ? lower(t.to) : null, input: lower(t.input),
    value: String(BigInt(t.value ?? '0x0')), nonce: String(BigInt(t.nonce)), created: lower(contractAddress ?? ''),
  }))));
}

export async function collectEvidence(c, candidate, broadcast, rpc, confirmations = 1) {
  const txs = validatePlan(c, candidate, broadcast);
  assert(Number.isSafeInteger(confirmations) && confirmations >= 1, 'confirmations must be positive');
  const checkpoint = await rpc('eth_getBlockByNumber', ['latest', false]);
  assert(checkpoint && hash.test(checkpoint.hash), 'missing verification block');
  const confirmedNonce = BigInt(await rpc('eth_getTransactionCount', [c.deployer, checkpoint.number]));
  assert(confirmedNonce >= BigInt(candidate.endNonce), 'broadcast incomplete at verification block');
  assert.equal(confirmedNonce, BigInt(candidate.endNonce), 'deployer used outside this run; reconcile before inventory');
  const receipts = [];
  const hashes = new Set();
  for (const planned of txs) {
    assert(hash.test(planned.hash) && !hashes.has(lower(planned.hash)), 'missing/duplicate transaction hash');
    hashes.add(lower(planned.hash));
    const receipt = await rpc('eth_getTransactionReceipt', [planned.hash]);
    assert(receipt && BigInt(receipt.status) === 1n, 'pending, missing, or reverted transaction: ' + planned.hash);
    assert.equal(lower(receipt.transactionHash), lower(planned.hash));
    assert.equal(lower(receipt.from), lower(c.deployer), 'receipt sender mismatch');
    assert(BigInt(checkpoint.number) - BigInt(receipt.blockNumber) + 1n >= BigInt(confirmations), 'insufficient confirmations');
    const block = await rpc('eth_getBlockByNumber', [receipt.blockNumber, false]);
    assert.equal(lower(block?.hash), lower(receipt.blockHash), 'receipt reorged');
    const actual = await rpc('eth_getTransactionByHash', [planned.hash]);
    assert(actual, 'transaction body unavailable');
    assert.equal(lower(actual.hash), lower(planned.hash), 'transaction hash mismatch');
    assert.equal(lower(actual.blockHash), lower(receipt.blockHash), 'transaction block mismatch');
    assert.equal(BigInt(actual.blockNumber), BigInt(receipt.blockNumber), 'transaction block number mismatch');
    if (actual.chainId !== undefined) assert.equal(Number(BigInt(actual.chainId)), c.chainId, 'transaction chain mismatch');
    const t = planned.transaction;
    for (const key of ['from', 'input']) assert.equal(lower(actual[key]), lower(t[key]), 'transaction ' + key + ' mismatch');
    assert.equal(lower(actual.to ?? ''), lower(t.to ?? ''), 'transaction destination mismatch');
    assert.equal(BigInt(actual.nonce), BigInt(t.nonce), 'transaction nonce mismatch');
    assert.equal(BigInt(actual.value), 0n, 'transaction transferred ETH');
    if (!t.to) assert.equal(lower(receipt.contractAddress), lower(planned.contractAddress), 'CREATE receipt mismatch');
    receipts.push(receipt);
  }
  const contracts = [];
  for (const r of candidate.contracts) {
    const code = await rpc('eth_getCode', [r.address, checkpoint.number]);
    assert(bytes.test(code) && code.length > 2, 'no deployed code: ' + r.name);
    assert.equal((code.length - 2) / 2, r.runtimeSize, 'runtime size mismatch: ' + r.name);
    assert.equal(keccak(code), lower(r.runtimeCodeHash), 'runtime hash mismatch: ' + r.name);
    const receipt = receipts.find(x => lower(x.contractAddress) === lower(r.address));
    assert(receipt, 'no CREATE receipt: ' + r.name);
    contracts.push({ ...r, transactionHash: receipt.transactionHash, blockNumber: Number(BigInt(receipt.blockNumber)), blockHash: receipt.blockHash });
  }
  assert.equal(lower((await rpc('eth_getBlockByNumber', [checkpoint.number, false]))?.hash), lower(checkpoint.hash), 'verification block reorged');
  return { checkpoint, contracts, receipts };
}
