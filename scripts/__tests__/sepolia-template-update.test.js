const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  assertRotationPlan,
  assertRehearsalPlan,
  buildRehearsalPlan,
  buildInventoryPendingRecords,
  buildTemplateUpdateHandoff,
  loadArtifacts,
} = require("../sepolia-v2-5-fix-rotation");
const rotation = require("../../deployments/sepolia/v2.5.6.json");
const plan = require("../../deployments/sepolia/plan-v2.5.6.json");
const deployments = require("../../deployments/sepolia/deployments.json");
const artifacts = loadArtifacts(rotation);
const call = (entry) => entry.forwardedCall;

test("template update deploys only three stores, registers both factories, then disables old templates", () => {
  assertRotationPlan(plan, rotation, artifacts);
  assert.equal(plan.transactions.length, 15);
  const stores = plan.transactions.slice(0, 3);
  assert.ok(stores.every((entry) => entry.kind === "deploy"));
  assert.deepEqual(stores.map((entry) => entry.output), [
    "open-term-hooks-init-code-storage",
    "fixed-term-hooks-init-code-storage",
    "periodic-term-hooks-init-code-storage",
  ]);
  for (const entry of plan.transactions.slice(3, 9)) {
    assert.equal(call(entry).functionSignature,
      "addHooksTemplate(address,string,address,address,uint80,uint16,bytes32)");
    assert.ok(Object.values(rotation.existing).includes(call(entry).target));
    assert.equal(entry.to, rotation.authority.helper);
    const store = stores.find((store) => store.output === call(entry).args[0].$ref);
    assert.equal(call(entry).args[6], store.predicate.initCodeHash);
    assert.equal(entry.predicate.expect, store.predicate.initCodeHash);
  }
  for (const entry of plan.transactions.slice(9)) {
    assert.equal(call(entry).functionSignature, "disableHooksTemplate(address)");
    assert.ok(Object.values(rotation.previousTemplates).includes(call(entry).args[0]));
    assert.equal(entry.to, rotation.authority.helper);
    assert.equal(entry.predicate.expect[3], true, "template remains registered");
    assert.equal(entry.predicate.expect[4], false, "template is disabled");
  }
  const pending = buildInventoryPendingRecords(rotation, artifacts);
  assert.equal(pending.length, 3);
  assert.ok(pending.every(({ value }) => value.recordType === "initCodeStorage"));
  assertRehearsalPlan(buildRehearsalPlan(plan), plan);
});

test("template update rejects another factory, an unapproved disable, and reused bytecode drift", () => {
  const wrongFactory = structuredClone(plan);
  wrongFactory.transactions[3].forwardedCall.target = rotation.authority.archController;
  assert.throws(() => assertRotationPlan(wrongFactory, rotation, artifacts));
  const wrongDisable = structuredClone(plan);
  wrongDisable.transactions[9].forwardedCall.args[0] = rotation.authority.archController;
  assert.throws(() => assertRotationPlan(wrongDisable, rotation, artifacts));
  const changedArtifacts = { ...artifacts, standardMarket: { ...artifacts.standardMarket, bytecode: "0x6000" } };
  assert.throws(() => assertRotationPlan(plan, rotation, changedArtifacts), /bytecode differs from baseline/);
  const wrongReuse = structuredClone(rotation);
  wrongReuse.reused.marketLensCore = rotation.reused.marketLens;
  assert.throws(() => assertRotationPlan(plan, wrongReuse, artifacts), /receipt-backed baseline/);
});

function verifiedRun() {
  return Object.fromEntries(plan.transactions.map((entry, index) => [entry.id, {
    status: "verified",
    txHash: `0x${(index + 1).toString(16).padStart(64, "0")}`,
    blockNumber: 12000000 + index,
    ...(entry.kind === "deploy" ? { resolvedAddress: `0x${(index + 1).toString(16).padStart(40, "0")}` } : {}),
  }]));
}

test("template handoff preserves factory aliases and deployment history with receipt-backed template cutover", () => {
  const run = verifiedRun();
  const result = buildTemplateUpdateHandoff(rotation, plan, run, deployments, "ab".repeat(32));
  for (const [key, address] of Object.entries(deployments)) {
    if (Object.keys(rotation.previousTemplates).some((name) => key === `${name}_initCodeStorage`)) continue;
    assert.equal(result.deployments[key], address, key);
  }
  assert.equal(Object.keys(result.deployments).length, Object.keys(deployments).length + 3);
  assert.equal(result.handoff.kind, "hook-template-update");
  assert.equal(result.handoff.factoryInventoryChanged, false);
  assert.equal(result.handoff.baseHandoff.path, "deployments/sepolia/handoff-v2.5.5.json");
  assert.equal(result.handoff.templates.length, 3);
  for (const template of result.handoff.templates) {
    assert.equal(template.registrations.length, 2);
    assert.ok(template.registrations.every(({ previousTemplateDisabled }) => previousTemplateDisabled.txHash));
    assert.equal(result.deployments[template.deploymentKey], template.address);
    assert.equal(result.deployments[`${template.name}_initCodeStorage`], template.address);
  }
  assert.deepEqual(buildTemplateUpdateHandoff(rotation, plan, run, result.deployments, "ab".repeat(32)), result);
});

test("template handoff refuses incomplete disabling and conflicting deployment evidence", () => {
  const run = verifiedRun();
  run[plan.transactions.at(-1).id].status = "submitted";
  assert.throws(() => buildTemplateUpdateHandoff(rotation, plan, run, deployments, "ab".repeat(32)), /Missing verified/);
  const conflict = { ...deployments };
  conflict["OpenTermHooks_initCodeStorage_v2.5.6"] = rotation.authority.archController;
  assert.throws(() => buildTemplateUpdateHandoff(rotation, plan, verifiedRun(), conflict, "ab".repeat(32)), /Conflicting receipt-backed/);
});
