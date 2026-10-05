const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { loadReusedDeployments } = require("../reused-deployments");
const { assertRotationPlan, loadArtifacts, buildInventoryPendingRecords,
  buildRehearsalPlan, assertRehearsalPlan } = require("../sepolia-v2-5-fix-rotation");
const { assertActivationPlan, upsertFactory, upsertWrapperFactory } = require("../factory-inventory");
const { buildHandoff, validateHandoff } = require("../generate-handoff");
const rotation = require("../../deployments/sepolia/v2.5.7.json");
const plan = require("../../deployments/sepolia/plan-v2.5.7.json");
const reused = loadReusedDeployments(rotation);
const artifacts = loadArtifacts(rotation);
const options = { reuseIdentityRegistry: true, reuseAccessListRoleProviderFactory: true,
  reusedDeployments: reused };

test("v2.5.7 replaces dependent factories and lenses while retaining four deployed components", () => {
  assertRotationPlan(plan, rotation, artifacts);
  assertActivationPlan(plan, "sepolia", options);
  assert.equal(plan.transactions.length, 21);
  assert.equal(plan.transactions.filter((tx) => tx.kind === "deploy").length, 11);
  assert.equal(reused.size, 4);
  for (const [output, record] of reused) {
    assert.ok(record.txHash && record.startBlock && record.provenance.handoffSha256);
    assert.equal(plan.transactions.some((tx) => tx.output === output), false);
    if (!record.initCodeHash) continue;
    const calls = plan.transactions.filter((tx) => tx.forwardedCall?.args[0] === record.address);
    assert.equal(calls.length, 2);
    for (const tx of calls) assert.equal(tx.forwardedCall.args[6], record.initCodeHash);
  }
  const rehearsal = buildRehearsalPlan(plan);
  assert.equal(rehearsal.release, "v2.5.7-rehearsal");
  assertRehearsalPlan(rehearsal, plan);
  rehearsal.transactions[0].constructorArgs.decoded.reverse();
  assert.throws(() => assertRehearsalPlan(rehearsal, plan), /mismatch|does not match/);
  const pending = buildInventoryPendingRecords(rotation, artifacts).map(({ value }) => value);
  assert.equal(pending.length, 16);
  assert.equal(pending.filter((record) => record.reused).length, 5);
  assert.equal(pending.filter((record) => record.provenance).length, 4);
});

test("reused registration validation rejects a missing pin, changed address, hash, or predicate", () => {
  assert.throws(() => assertActivationPlan(plan, "sepolia", { ...options, reusedDeployments: undefined }));
  for (const change of [
    (tx) => { tx.forwardedCall.args[0] = rotation.authority.archController; },
    (tx) => { tx.forwardedCall.args[6] = `0x${"ab".repeat(32)}`; },
    (tx) => { tx.predicate.call.args[0] = rotation.authority.archController; },
  ]) {
    const altered = structuredClone(plan);
    change(altered.transactions.find((tx) => tx.id === "add-standard-open-term-template"));
    assert.throws(() => assertActivationPlan(altered, "sepolia", options));
    assert.throws(() => assertRotationPlan(altered, rotation, artifacts));
  }
});

test("reuse rejects changed code and unsupported, duplicate, or unpinned sources", () => {
  const wrongPredecessor = structuredClone(rotation);
  wrongPredecessor.superseded.standardHooksFactory = rotation.authority.archController;
  assert.throws(() => assertRotationPlan(plan, wrongPredecessor, artifacts), /predecessor baseline/);
  for (const key of ["openTermHooks", "AccessListRoleProviderFactory"]) {
    const altered = { ...artifacts, [key]: { ...artifacts[key], bytecode: "0x6000" } };
    assert.throws(() => assertRotationPlan(plan, rotation, altered), /bytecode differs from baseline/);
  }
  for (const change of [
    (cfg) => { cfg.inventoryBaselineCommit = "HEAD"; },
    (cfg) => { cfg.reusedDeployments.push(cfg.reusedDeployments[0]); },
    (cfg) => { cfg.reusedDeployments[0].output = "hooks-factory-standard"; },
    (cfg) => { cfg.reusedDeployments[0].handoff = "../../package.json"; },
    (cfg) => { cfg.reusedDeployments[1].handoff = "deployments/sepolia/handoff-v2.5.5.json"; },
  ]) {
    const altered = structuredClone(rotation);
    change(altered);
    if (altered.reusedDeployments[1].handoff.endsWith("handoff-v2.5.5.json")) {
      assert.throws(() => assertRotationPlan(plan, altered, artifacts));
    } else assert.throws(() => loadReusedDeployments(altered));
  }
});

test("final handoff retains original deployment receipts and records reuse explicitly", (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wildcat-v257-handoff-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const deployments = structuredClone(require("../../deployments/sepolia/deployments.json"));
  let inventory = structuredClone(require("../../deployments/sepolia/factory-inventory.json"));
  const outputs = new Map();
  const run = Object.fromEntries(plan.transactions.map((tx, index) => {
    const record = { status: "verified", blockNumber: 13000000 + index,
      txHash: `0x${(index + 1).toString(16).padStart(64, "0")}` };
    if (tx.kind === "deploy") {
      record.resolvedAddress = `0x${(index + 1000).toString(16).padStart(40, "0")}`;
      outputs.set(tx.output, record.resolvedAddress);
    }
    return [tx.id, record];
  }));
  const pending = buildInventoryPendingRecords(rotation, artifacts).map(({ value }) => value);
  for (const record of pending) deployments[record.deploymentKey] =
    record.address.$ref ? outputs.get(record.address.$ref) : record.address;
  for (const [contract, type, output] of [["HooksFactory", "legacy", "hooks-factory-standard"],
    ["HooksFactoryRevolving", "revolving", "hooks-factory-revolving"]]) {
    const state = run[`deploy-${output}`];
    inventory = upsertFactory(inventory, { label: `${contract}_v2.5.7`, deploymentKey: `${contract}_v2.5.7`,
      marketType: type, address: state.resolvedAddress, startBlock: state.blockNumber,
      deployTxHash: state.txHash, canonical: true, lifecycle: "canonical", indexed: true, registered: true });
    deployments[contract] = state.resolvedAddress;
  }
  const wrapper = run["deploy-wildcat-4626-wrapper-factory"];
  inventory = upsertWrapperFactory(inventory, { label: "Wildcat4626WrapperFactory_v2.5.7",
    address: wrapper.resolvedAddress, startBlock: wrapper.blockNumber, deployTxHash: wrapper.txHash,
    lifecycle: "canonical", indexed: true, v1Factory: rotation.reused.v1WrapperFactory });
  deployments.Wildcat4626WrapperFactory = wrapper.resolvedAddress;
  deployments.MarketLens = outputs.get("market-lens");
  const write = (name, value) => {
    const file = path.join(dir, `${name}.json`);
    fs.writeFileSync(file, JSON.stringify(value));
    return file;
  };
  const handoff = buildHandoff({ network: "sepolia", release: "v2.5.7",
    inventoryPath: write("inventory", inventory), deploymentsPath: write("deployments", deployments),
    planPath: write("plan", plan), runStatePath: write("run", run) });
  assert.deepEqual(validateHandoff(handoff, inventory, deployments, "sepolia", "v2.5.7"), []);
  for (const record of reused.values()) {
    const final = handoff.releaseContracts.find((entry) => entry.address === record.address);
    assert.equal(final.reused, true);
    assert.equal(final.deployTxHash, record.txHash);
    assert.equal(final.startBlock, record.startBlock);
    assert.deepEqual(final.provenance, record.provenance);
  }
});
