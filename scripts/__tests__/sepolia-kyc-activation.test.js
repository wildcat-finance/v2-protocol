const { test } = require("node:test");
const assert = require("node:assert/strict");
const { buildEntries, buildInventoryPendingRecords, loadArtifacts } = require("../sepolia-v2-5-fix-rotation");
const { assertActivationPlan } = require("../factory-inventory");
const { authorizedHelperTransactions } = require("../plan");
const { loadReusedDeployments } = require("../reused-deployments");
const { validateKycRoleProvider } = require("../role-provider-factories");
const draft = require("../../deployments/sepolia/v2.5.9.json");
const { ownership } = require("../../deployments/sepolia/ceremony-config.json");

const rotation = {
  ...draft,
  kycRoleProvider: { ...draft.kycRoleProvider, administrator: "0x0000000000000000000000000000000000000001" },
};
const artifacts = loadArtifacts(rotation);
const options = {
  rotation,
  reuseIdentityRegistry: true,
  reuseAccessListRoleProviderFactory: true,
  reusedDeployments: loadReusedDeployments(rotation),
};

function activationPlan() {
  return {
    release: rotation.release,
    network: rotation.network,
    expectedExecutor: rotation.expectedExecutor,
    transactions: authorizedHelperTransactions(buildEntries(rotation, artifacts),
      rotation.authority.helper, ownership.forwardedFunctionSignatures),
  };
}

test("v2.5.9 deploys one shared KYC provider and approves both wrapper paths", () => {
  const plan = activationPlan();
  assertActivationPlan(plan, rotation.network, options);
  assert.equal(plan.transactions.length, 27);
  assert.ok(plan.transactions.slice(0, 15).every((tx) => tx.kind === "deploy"));
  assert.ok(plan.transactions.slice(15).every((tx) => tx.kind === "call"));
  assert.deepEqual(rotation.retirementTargets, []);
  assert.deepEqual(Array.from(options.reusedDeployments.keys()), ["access-list-role-provider-factory"]);
  const records = buildInventoryPendingRecords(rotation, artifacts).map(({ value }) => value);
  assert.deepEqual(records.filter((record) => record.role === "kycRoleProvider").map((record) => record.address),
    [{ $ref: "kyc-role-provider" }]);
});

test("v2.5.9 binds the KYC administrator and exact runtime", () => {
  for (const administrator of [null, "0x0000000000000000000000000000000000000000"]) {
    assert.throws(() => validateKycRoleProvider({ ...rotation.kycRoleProvider, administrator }), /administrator/);
  }
  const plan = activationPlan();
  const provider = plan.transactions.find((tx) => tx.output === "kyc-role-provider");
  provider.constructorArgs.decoded = [rotation.expectedExecutor];
  assert.throws(() => assertActivationPlan(plan, rotation.network, options), /deploy-kyc-role-provider/);
  const changed = { ...rotation, kycRoleProvider: { ...rotation.kycRoleProvider, runtimeCodeHash: "0x" + "11".repeat(32) } };
  assert.throws(() => buildEntries(changed, artifacts), /Pinned KYC runtime/);
});

test("v2.5.9 rejects missing, misdirected or revoked wrapper approvals", () => {
  for (const marketType of ["standard", "revolving"]) {
    const plan = activationPlan();
    const approval = plan.transactions.find((tx) => tx.id === `approve-${marketType}-wrapper-factory`);
    assert.equal(approval.to, rotation.authority.helper);
    approval.forwardedCall.args[0] = rotation.superseded.wrapperFactory;
    assert.throws(() => assertActivationPlan(plan, rotation.network, options), /wrapper-factory/);
    approval.forwardedCall.args = [{ $ref: "wildcat-4626-wrapper-factory" }, false];
    assert.throws(() => assertActivationPlan(plan, rotation.network, options), /wrapper-factory/);
    plan.transactions = plan.transactions.filter((tx) => tx !== approval);
    assert.throws(() => assertActivationPlan(plan, rotation.network, options), /exactly 27/);
  }
});
