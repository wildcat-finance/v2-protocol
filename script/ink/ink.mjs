#!/usr/bin/env node
// offchain deployment evidence. no onchain inventory or V2.5 ceremony machinery.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { resolve, relative, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CORE, PLASMA, sha256, keccak, readJson, validateConfig, rpcClient, checkEndpoint, validatePlan, planHash, collectEvidence } from './inventory.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
process.chdir(root);
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !/^(FOUNDRY_|DAPP_)/.test(key)));
env.FOUNDRY_PROFILE = 'ink';
const runRoot = join(root, 'deployments/ink/runs');
function tool(command, args) {
  return execFileSync(command, args, { cwd: root, env, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}
function local(path) {
  const full = resolve(root, path);
  assert(!relative(root, full).startsWith('..'), 'path must be inside this repository');
  return full;
}
function writeNew(path, data) { writeFileSync(path, JSON.stringify(data, null, 2) + '\n', { flag: 'wx', mode: 0o600 }); }
function sources() {
  assert.equal(tool('git', ['rev-parse', 'v2.1.0^{}']), CORE, 'unexpected V2.1 tag');
  tool('git', ['merge-base', '--is-ancestor', CORE, 'HEAD']);
  for (const path of [...tool('git', ['ls-tree', '-r', '--name-only', CORE, 'src']).split('\n'), 'script/mock/MockArchControllerOwner.sol']) {
    const baseline = execFileSync('git', ['show', CORE + ':' + path], { cwd: root });
    assert(readFileSync(path).equals(baseline), 'V2.1 core changed: ' + path);
  }
  const dependencies = tool('git', ['ls-tree', CORE, 'lib/']).split('\n').map(line => {
    const [, commit, path] = line.match(/^160000 commit (\w+)\t(.+)$/);
    assert.equal(tool('git', ['-C', path, 'rev-parse', 'HEAD']), commit, 'dependency pin changed: ' + path);
    assert.equal(tool('git', ['-C', path, 'status', '--porcelain', '--untracked-files=no']), '', 'dirty dependency: ' + path);
    return { path, commit };
  });
  for (const path of ['src/ChainalysisProxy.sol', 'src/WildcatCopyOfChainalysisList.sol', 'src/OpenAccessRoleProvider.sol', 'src/spherex-engine/SphereXEngine.sol', 'src/spherex-engine/ISphereXEngine.sol']) {
    assert.equal(readFileSync(path, 'utf8').trimEnd(), tool('git', ['show', PLASMA + ':' + path]), 'Plasma support source changed: ' + path);
  }
  const plasmaPatterns = tool('git', ['show', PLASMA + ':script/DeployV2Plasma.sol']).match(/patterns\[\d+\] = 0x[0-9a-f]+/g);
  const inkPatterns = readFileSync('script/ink/SphereXPatterns.sol', 'utf8').match(/patterns\[\d+\] = 0x[0-9a-f]+/g);
  assert.equal(plasmaPatterns.length, 130);
  assert.deepEqual(inkPatterns, plasmaPatterns, 'SphereX pattern set drifted');
  const files = tool('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', 'src', 'script/ink', 'script/mock/MockArchControllerOwner.sol', 'test/ink', 'foundry.toml', '.gitmodules']).split('\0').filter(Boolean).sort();
  return { core: CORE, dependencies, files: files.map(path => ({ path, sha256: sha256(readFileSync(path)) })) };
}
function build() {
  const result = spawnSync('forge', ['build', '--offline'], { cwd: root, env, stdio: 'inherit' });
  assert.equal(result.status, 0, 'Ink build failed');
  const layout = readJson('ink-out/SphereXEngine.sol/SphereXEngine.json').value.storageLayout.storage;
  for (const [label, slot] of [['_engineRules', '3'], ['_allowedSenders', '4'], ['_allowedPatterns', '5']]) {
    const actual = layout.find(x => x.label === label);
    assert(actual?.slot === slot && actual?.offset === 0, 'SphereX verification storage layout changed');
  }
  const artifacts = {};
  for (const name of ['WildcatArchController', 'SphereXEngine', 'WildcatCopyOfChainalysisList', 'ChainalysisProxy', 'WildcatSanctionsSentinel', 'WildcatFeeRecipient', 'WildcatMarket', 'OpenTermHooks', 'FixedTermHooks', 'HooksFactory', 'MarketLens', 'Wildcat4626WrapperFactory', 'OpenAccessRoleProvider', 'MockArchControllerOwner']) {
    const artifact = readJson('ink-out/' + name + '.sol/' + name + '.json').value;
    const m = typeof artifact.metadata === 'string' ? JSON.parse(artifact.metadata) : artifact.metadata;
    assert(m.compiler.version.startsWith('0.8.25+'), 'compiler changed');
    assert(m.settings.viaIR && m.settings.optimizer.enabled && m.settings.optimizer.runs === 50000, 'optimizer changed');
    assert.equal(m.settings.evmVersion, 'cancun');
    assert.equal(m.settings.metadata.bytecodeHash, 'none');
    const runtimeSize = (artifact.deployedBytecode.object.length - 2) / 2;
    const initSize = (artifact.bytecode.object.length - 2) / 2;
    assert(runtimeSize > 0 && runtimeSize <= 24576 && initSize <= 49152, 'contract size limit: ' + name);
    if (['WildcatMarket', 'OpenTermHooks', 'FixedTermHooks'].includes(name)) assert(initSize + 1 <= 24576, 'initcode store too large: ' + name);
    artifacts[name] = { creationCodeHash: keccak(artifact.bytecode.object), runtimeSize, initSize };
  }
  return artifacts;
}
function configAt(path) {
  const config = readJson(local(path));
  const snapshot = readJson(local(config.value.sanctionsSnapshot));
  validateConfig(config.value, snapshot.value);
  return { c: config.value, s: snapshot.value, configHash: keccak(config.raw), snapshotHash: keccak(snapshot.raw) };
}
function runPath(path) {
  const full = local(path);
  assert(full.startsWith(runRoot + '/') && full !== runRoot, 'run directory must be under deployments/ink/runs');
  return full;
}
function checkPrepared(run) {
  const p = readJson(join(run, 'prepared.json')).value;
  const now = configAt(p.config);
  assert.equal(now.configHash, p.configHash, 'config changed since preparation');
  assert.equal(now.snapshotHash, p.snapshotHash, 'snapshot changed since preparation');
  assert.deepEqual(sources(), p.sources, 'source changed since preparation; use a new run');
  env.INK_CONFIG = local(p.config);
  env.INK_CANDIDATE = join(run, 'candidate.json');
  return { p, ...now };
}
function broadcastPath(c) { return join(root, 'broadcast/DeployInk.s.sol', String(c.chainId), 'run-latest.json'); }
function walletFlags(flags, c) {
  const result = [];
  for (let i = 0; i < flags.length; ++i) {
    const flag = flags[i];
    if (flag === '--broadcast') result.push(flag, '--slow');
    else if (flag === '--account') {
      assert(flags[i + 1] && !flags[i + 1].startsWith('-'), 'missing keystore alias');
      result.push(flag, flags[++i]);
    } else if (flag === '--ledger' || flag === '--trezor') result.push(flag);
    else if (flag === '--unlocked') {
      assert.equal(c.mode, 'rehearsal', 'unlocked signer only allowed for local rehearsals');
      result.push(flag);
    } else throw new Error('unsupported option: ' + flag);
  }
  return result;
}

async function main() {
  const [command, arg, ...args] = process.argv.slice(2);
  assert(['check', 'simulate', 'prepare', 'run', 'resume', 'collect'].includes(command), 'usage: ink.mjs check | simulate CONFIG RUN | prepare CONFIG RUN | run RUN [--broadcast --account ALIAS] | resume RUN ... | collect RUN [CONFIRMATIONS]');
  if (command === 'check') {
    assert(arg === undefined && args.length === 0, 'check takes no arguments');
    sources();
    const artifacts = build();
    console.log(JSON.stringify(artifacts, null, 2));
    return;
  }
  if (command === 'simulate') {
    assert.equal(args.length, 1, 'simulate requires CONFIG RUN');
    const info = configAt(arg), run = runPath(args[0]);
    assert.equal(info.c.mode, 'rehearsal', 'offline simulation requires rehearsal config');
    assert(!existsSync(run), 'run directory already exists');
    const source = sources(), artifacts = build();
    mkdirSync(dirname(run), { recursive: true });
    mkdirSync(run);
    env.INK_CONFIG = local(arg);
    env.INK_CANDIDATE = join(run, 'candidate.json');
    const target = 'script/ink/DeployInk.s.sol:' + (info.c.chainId === 57073 ? 'DeployInkMainnet' : 'DeployInkTestnet');
    // offline Forge reserves nonce 1 for its script sender. keep its internal sender separate
    // from the configured broadcast EOA, whose CREATE nonce the script checks explicitly.
    const result = spawnSync('forge', ['script', target, '--offline', '--chain-id', String(info.c.chainId)], { cwd: root, env, stdio: 'inherit' });
    assert.equal(result.status, 0, 'offline script simulation failed');
    writeNew(join(run, 'simulation.json'), {
      schemaVersion: 1, status: 'offline-simulation-only', mode: 'rehearsal', chainId: info.c.chainId,
      configHash: info.configHash, snapshotHash: info.snapshotHash, sources: source, artifacts,
      candidateHash: sha256(readFileSync(env.INK_CANDIDATE)),
    });
    console.log('offline simulation only; no fork, broadcast, receipts, or deployment inventory');
    return;
  }
  const url = process.env.INK_RPC_URL;
  assert(url, 'set INK_RPC_URL; it is never stored in inventory');
  const rpc = rpcClient(url);
  if (command === 'prepare') {
    assert.equal(args.length, 1, 'prepare requires CONFIG RUN');
    const config = local(arg), run = runPath(args[0]);
    assert(!existsSync(run), 'run directory already exists');
    const info = configAt(config);
    const source = sources();
    const dirty = tool('git', ['status', '--porcelain', '--untracked-files=all', '--', 'src', 'script/ink', 'script/mock/MockArchControllerOwner.sol', 'test/ink', 'foundry.toml', '.gitmodules']) !== '';
    assert(info.c.mode !== 'live' || !dirty, 'live preparation requires committed, clean deployment source');
    await checkEndpoint(info.c, rpc, url);
    assert.equal(Number(BigInt(await rpc('eth_getTransactionCount', [info.c.deployer, 'pending']))), info.c.expectedNonce, 'deployer nonce mismatch');
    const artifacts = build();
    const checkpoint = await rpc('eth_getBlockByNumber', ['latest', false]);
    const fork = info.c.mode === 'rehearsal' ? (await rpc('anvil_nodeInfo')).forkConfig : undefined;
    mkdirSync(dirname(run), { recursive: true });
    mkdirSync(run);
    writeFileSync(join(run, 'config.original.json'), readFileSync(config), { flag: 'wx', mode: 0o600 });
    writeFileSync(join(run, 'snapshot.original.json'), readFileSync(local(info.c.sanctionsSnapshot)), { flag: 'wx', mode: 0o600 });
    writeNew(join(run, 'prepared.json'), {
      schemaVersion: 1, config: relative(root, config), configHash: info.configHash, snapshotHash: info.snapshotHash,
      sources: source, sourceCommit: tool('git', ['rev-parse', 'HEAD']), sourceTreeDirty: dirty, artifacts,
      forge: tool('forge', ['--version']).split('\n')[0],
      checkpoint: { number: checkpoint.number, hash: checkpoint.hash },
      // forkUrl may contain RPC credentials; don't archive it.
      fork: fork ? { forkBlockNumber: fork.forkBlockNumber, forkBlockHash: fork.forkBlockHash, forkChainId: fork.forkChainId } : null,
    });
    console.log('prepared ' + relative(root, run) + ' (' + info.c.mode + '; no transactions sent)');
    return;
  }
  const run = runPath(arg);
  const { p, c, s } = checkPrepared(run);
  await checkEndpoint(c, rpc, url);
  const target = 'script/ink/DeployInk.s.sol:' + (c.chainId === 57073 ? 'DeployInkMainnet' : 'DeployInkTestnet');
  if (command === 'run' || command === 'resume') {
    assert.deepEqual(build(), p.artifacts, 'build commitments changed');
    const flags = walletFlags(args, c);
    if (command === 'resume') {
      assert(flags.includes('--broadcast'), 'resume requires --broadcast');
      const saved = readJson(join(run, 'transaction-plan.json')).value;
      assert.equal(saved.candidateHash, sha256(readFileSync(env.INK_CANDIDATE)), 'candidate changed');
      const candidate = readJson(env.INK_CANDIDATE).value;
      assert.equal(candidate.configHash, p.configHash);
      assert.equal(candidate.snapshotHash, p.snapshotHash);
      validatePlan(c, candidate, readJson(broadcastPath(c)).value);
      assert.equal(planHash(readJson(broadcastPath(c)).value), saved.planHash, 'Forge run-latest belongs to another run');
      flags.push('--resume');
    } else assert(!existsSync(env.INK_CANDIDATE), 'candidate already exists: resume saved transactions or prepare a new run');
    const result = spawnSync('forge', ['script', target, '--offline', '--rpc-url', url, '--sender', c.deployer, ...flags], { cwd: root, env, stdio: 'inherit' });
    if (flags.includes('--broadcast') && existsSync(env.INK_CANDIDATE) && existsSync(broadcastPath(c))) {
      const candidate = readJson(env.INK_CANDIDATE).value;
      assert.equal(candidate.configHash, p.configHash);
      assert.equal(candidate.snapshotHash, p.snapshotHash);
      const broadcast = readJson(broadcastPath(c)).value;
      validatePlan(c, candidate, broadcast);
      const saved = { planHash: planHash(broadcast), candidateHash: sha256(readFileSync(env.INK_CANDIDATE)) };
      const planPath = join(run, 'transaction-plan.json');
      if (!existsSync(planPath)) writeNew(planPath, saved);
      else assert.deepEqual(readJson(planPath).value, saved, 'resume changed the plan/candidate');
      // keep attempts append-only. omit Forge cache and RPC config, which may contain secrets.
      writeNew(join(run, 'broadcast-' + Date.now() + '.json'), { chain: broadcast.chain, transactions: broadcast.transactions, receipts: broadcast.receipts });
    }
    assert.equal(result.status, 0, 'Forge did not complete; candidate is NOT deployment inventory');
    console.log('not promoted: run collect after confirmation; candidate alone proves nothing');
    return;
  }
  assert(args.length <= 1, 'collect accepts at most a confirmation count');
  const confirmations = args.length ? Number(args[0]) : (c.mode === 'live' ? 12 : 1);
  const inventoryPath = join(run, 'inventory.json');
  assert(!existsSync(inventoryPath), 'inventory already exists; preserve it');
  const candidate = readJson(env.INK_CANDIDATE).value;
  assert.equal(candidate.configHash, p.configHash);
  assert.equal(candidate.snapshotHash, p.snapshotHash);
  const plan = readJson(join(run, 'transaction-plan.json')).value;
  assert.equal(plan.candidateHash, sha256(readFileSync(env.INK_CANDIDATE)), 'candidate changed');
  const broadcast = readJson(broadcastPath(c)).value;
  assert.equal(plan.planHash, planHash(broadcast), 'Forge run-latest belongs to another run');
  const evidence = await collectEvidence(c, candidate, broadcast, rpc, confirmations);
  const verification = spawnSync('forge', ['script', 'script/ink/DeployInk.s.sol:VerifyInk', '--offline', '--rpc-url', url, '--fork-block-number', String(BigInt(evidence.checkpoint.number))], { cwd: root, env, stdio: 'inherit' });
  assert.equal(verification.status, 0, 'post-broadcast binding/authority verification failed');
  assert.equal((await rpc('eth_getBlockByNumber', [evidence.checkpoint.number, false])).hash, evidence.checkpoint.hash, 'verification block reorged');
  const deployed = Object.fromEntries(candidate.contracts.map(r => [r.name, r.address]));
  writeNew(inventoryPath, {
    schemaVersion: 1, status: 'confirmed-bootstrap', mode: c.mode, chainId: c.chainId,
    launchReady: false, launchGate: 'External sanctions updater/source freshness and consumer rollout are not verified here.',
    deployer: c.deployer, sourceCommit: p.sourceCommit, sourceTreeDirty: p.sourceTreeDirty, sourceManifestHash: sha256(JSON.stringify(p.sources)),
    startNonce: candidate.startNonce, endNonce: candidate.endNonce,
    transactionPlanHash: plan.planHash, candidateHash: plan.candidateHash,
    build: p.artifacts, configHash: p.configHash, snapshotHash: p.snapshotHash, sanctionsSource: s,
    sphereXPatternsHash: candidate.sphereXPatternsHash, feeRecipient: candidate.feeRecipient,
    verificationBlock: { number: Number(BigInt(evidence.checkpoint.number)), hash: evidence.checkpoint.hash }, confirmations,
    authorities: {
      archOwner: deployed.MockArchControllerOwner ?? c.deployer,
      testnetOwnerBootstrapAuthorizedAccount: deployed.MockArchControllerOwner ? c.deployer : null,
      archSphereXAdmin: c.deployer, archSphereXOperator: c.deployer,
      engineAdmin: c.deployer, engineOperator: c.deployer, engineSenderAdder: deployed.WildcatArchController,
      sanctionsAdapterOwner: c.deployer, sanctionsListUpdater: c.deployer,
      feeRecipientOwner: c.deployFeeRecipient ? c.deployer : null, treasuryRecipient: c.feeRecipient,
      pendingArchAdmin: null, pendingEngineAdmin: null,
    },
    contracts: evidence.contracts, receipts: evidence.receipts,
  });
  console.log('confirmed ' + c.mode + ' bootstrap: ' + relative(root, inventoryPath));
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
