const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { keccak256 } = require("ethers");
const {
  ARTIFACTS,
  EXPECTED_IDS,
  buildEntries,
  buildInventoryPendingRecords,
  prepareStorage,
} = require("../sepolia-v2-5-fix-rotation");
const { ROLE_PROVIDER_FACTORIES } = require("../role-provider-factories");
const { assertActivationPlan } = require("../factory-inventory");
const {
  assertSplitStorageCommitments,
  assertActivationTemplateCommitments,
} = require("../template-commitments");
const rotation = require("../../deployments/sepolia/v2.5.5.json");
const root = path.resolve(__dirname, "../..");

function artifacts() {
  const result = Object.fromEntries(
    Object.entries(ARTIFACTS).map(([key, definition], index) => [
      key,
      {
        ...definition,
        bytecode: `0x60${index.toString(16).padStart(2, "0")}`,
      },
    ])
  );
  result.standardMarket.bytecode = `0x${"ab".repeat(25616)}`;
  result.revolvingMarket.bytecode = `0x${"cd".repeat(26236)}`;
  result.splitReader = {
    artifact: { deployedBytecode: { object: "0x60006000f3" } },
  };
  for (const definition of ROLE_PROVIDER_FACTORIES) {
    if (definition.providerKind !== "ACCESS_LIST") continue;
    result[definition.contract] = {
      ...definition,
      bytecode: "0x6000",
      artifact: { deployedBytecode: { object: "0x6000" } },
    };
  }
  return result;
}

test("v2.5.5 activation has only new deployments and activation calls", () => {
  const entries = buildEntries(rotation, artifacts());
  assert.equal(entries.length, 25);
  assert.equal(entries.filter(({ kind }) => kind === "deploy").length, 15);
  assert.equal(entries.filter(({ kind }) => kind === "call").length, 10);
  assert.equal(
    entries.some(({ id }) => id === "deploy-borrower-identity-registry"),
    false
  );
  assert.deepEqual(rotation.retirementTargets, []);
  for (const [index, entry] of entries.entries()) {
    assert.deepEqual(entry.after, index ? [entries[index - 1].id] : []);
    assert.doesNotMatch(entry.description, /corrected|replacement/i);
    if (entry.kind !== "call") continue;
    assert.match(
      entry.functionSignature,
      /^(registerControllerFactory|addHooksTemplate|registerWithArchController)\(/
    );
  }
  for (const definition of ROLE_PROVIDER_FACTORIES) {
    assert.equal(
      entries.find(({ output }) => output === definition.output)?.artifactName,
      definition.providerKind === "ACCESS_LIST"
        ? definition.artifactName
        : undefined
    );
  }
  assertSplitStorageCommitments({ transactions: entries });
  assertActivationTemplateCommitments({ transactions: entries });
});

test("pending inventory covers every deployment, both split chunks, and reused identity", () => {
  const compiled = artifacts();
  const entries = buildEntries(rotation, compiled);
  const records = buildInventoryPendingRecords(rotation, compiled).map(
    ({ value }) => value
  );
  assert.equal(records.length, 16);
  assert.deepEqual(
    records.filter(({ reused }) => reused).map(({ role }) => role),
    ["identityRegistry"]
  );
  assert.deepEqual(
    records
      .filter(({ role }) => role === "roleProviderFactory")
      .map(({ providerKind }) => providerKind),
    ["ACCESS_LIST"]
  );
  for (const entry of entries.filter(({ kind }) => kind === "deploy")) {
    const matches = records.filter(
      ({ address }) => address?.$ref === entry.output
    );
    assert.equal(matches.length, 1, entry.id);
    assert.ok(matches[0].deploymentKey.includes("_v2.5.5"));
    if (entry.predicate.type === "splitCodeHash") {
      assert.deepEqual(matches[0].secondary, entry.predicate.secondary);
      assert.equal(
        matches[0].secondaryCodeHash,
        entry.predicate.secondaryCodeHash
      );
    }
  }
});

test("storage preparation preserves raw boundaries and split capacity", () => {
  const reader = "0x60006000f3";
  const firstLength = 24576 - 5 - 24;
  const raw = `0x${"aa".repeat(24575)}`;
  assert.deepEqual(prepareStorage(raw, reader), {
    primary: `0x00${raw.slice(2)}`,
    initCodeHash: keccak256(raw),
  });
  const bytes = `0x${"bb".repeat(firstLength + 24575)}`;
  const images = prepareStorage(bytes, reader);
  assert.equal((images.primary.length - 2) / 2, 24576);
  assert.equal((images.secondary.length - 2) / 2, 24576);
  const restored = `0x${images.primary.slice(
    reader.length,
    -48
  )}${images.secondary.slice(4)}`;
  assert.equal(restored, bytes);
  assert.throws(() => prepareStorage(`${bytes}00`, reader), /capacity/);
});

test("historical entry layout stays unchanged", () => {
  const historical = require("../../deployments/sepolia/v2-5-sepolia-fix-1.json");
  const entries = buildEntries(
    { ...historical, protocolVersion: "2.5.3" },
    artifacts()
  );
  assert.deepEqual(
    entries.map(({ id }) => id),
    EXPECTED_IDS
  );
  assert.equal(entries.filter(({ kind }) => kind === "deploy").length, 12);
  const historicalPlan = require("../../deployments/sepolia/plan-v2-5-sepolia-fix-1.json");
  assert.deepEqual(
    entries.map(({ description }) => description),
    historicalPlan.transactions.map(({ description }) => description)
  );
});

test("historical plan retains its inventory shape", () => {
  const plan = JSON.parse(
    fs.readFileSync(
      path.join(root, "deployments/sepolia/plan-v2.5.5.json"),
      "utf8"
    )
  );
  // current-artifact validation belongs to the current release test. the
  // historical wrapper init code intentionally differs after v2.5.7.
  assertActivationPlan(plan, "sepolia", {
    reuseIdentityRegistry: true,
  });
});

test("inventory finalization rejects extra role-provider deployments", () => {
  const reviewedPlan = JSON.parse(
    fs.readFileSync(
      path.join(root, "deployments/sepolia/plan-v2.5.5.json"),
      "utf8"
    )
  );
  for (const definition of ROLE_PROVIDER_FACTORIES) {
    if (definition.providerKind === "ACCESS_LIST") continue;
    const plan = structuredClone(reviewedPlan);
    plan.transactions.splice(2, 0, {
      id: `deploy-${definition.output}`,
      kind: "deploy",
      artifactName: definition.artifactName,
      output: definition.output,
    });
    assert.throws(
      () =>
        assertActivationPlan(plan, "sepolia", {
          reuseIdentityRegistry: true,
        }),
      /Activation plan must contain exactly 25 transactions/
    );
  }
});

test("release paths reject traversal without banning semantic versions", () => {
  for (const release of ["../v2.5.5", "v2..5", "v2/5", "v2\\5", ".v2", "v2."]) {
    const result = spawnSync(
      process.execPath,
      [
        "scripts/plan.js",
        "assemble",
        "--network",
        "sepolia",
        "--release",
        release,
      ],
      {
        cwd: root,
        encoding: "utf8",
      }
    );
    assert.equal(result.status, 1, release);
    assert.match(result.stderr, /Release must be a safe label/);
  }
});
