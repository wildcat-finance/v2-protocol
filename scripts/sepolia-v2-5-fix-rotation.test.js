const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");
const { spawnSync } = require("node:child_process");
const {
  ARTIFACTS,
  assertRotationPlan,
  assertRehearsalPlan,
  buildRehearsalPlan,
  replacementImpactReport,
} = require("./sepolia-v2-5-fix-rotation");

const root = path.resolve(__dirname, "..");
const read = (file) =>
  JSON.parse(fs.readFileSync(path.join(root, file), "utf8"));
const rotation = read("deployments/sepolia/v2-5-4.json");
const plan = read("deployments/sepolia/plan-v2-5-4.json");
const previousPlan = read(rotation.baseline.plan);
const previousImpact = read(rotation.baseline.impact);
const artifacts = Object.fromEntries(
  Object.entries(ARTIFACTS).map(([key, definition]) => {
    const artifact = read(
      `deploy-out/${path.basename(definition.source)}/${
        definition.contract
      }.json`
    );
    return [
      key,
      { ...definition, artifact, bytecode: artifact.bytecode.object },
    ];
  })
);

test("2.5.4 compares to the completed 2.5.3 generation and rebinds unchanged lenses", () => {
  const report = replacementImpactReport(
    rotation,
    artifacts,
    previousPlan,
    previousImpact
  );
  assert.equal(report.comparedAgainst, "v2-5-sepolia-fix-1");
  assert.equal(report.components.filter((c) => c.exactChanged).length, 8);
  assert.equal(
    report.components.filter((c) => c.decision === "replace").length,
    12
  );
  for (const name of [
    "marketLensCore",
    "marketLensAggregator",
    "marketLensLive",
    "marketLens",
  ]) {
    const component = report.components.find((c) => c.component === name);
    assert.equal(component.exactChanged, false);
    assert.equal(component.constructorBindingsChanged, true);
    assert.equal(component.decision, "replace");
  }
  assert.throws(
    () =>
      replacementImpactReport(
        rotation,
        artifacts,
        { ...previousPlan, release: "v2-5" },
        previousImpact
      ),
    /Baseline plan release/
  );
});

test("reuse fails if either reused implementation changes", () => {
  for (const component of ["identityRegistry", "accessListFactory"]) {
    const changed = {
      ...artifacts,
      [component]: { ...artifacts[component], bytecode: "0x00" },
    };
    assert.throws(
      () =>
        replacementImpactReport(
          rotation,
          changed,
          previousPlan,
          previousImpact
        ),
      new RegExp(`Cannot reuse ${component}`)
    );
  }
  const changedImpact = structuredClone(previousImpact);
  changedImpact.components.find(
    (c) => c.component === "standardFactory"
  ).replacementCreationCodeHash = "0x00";
  assert.throws(
    () =>
      replacementImpactReport(rotation, artifacts, previousPlan, changedImpact),
    /baseline bytecode/
  );
});

test("activation rejects an added retirement call or an old wrapper binding", () => {
  assert.doesNotThrow(() => assertRotationPlan(plan, rotation, artifacts));
  const retirement = structuredClone(plan);
  retirement.transactions.push({
    id: "retire-predecessor",
    kind: "call",
    to: rotation.authority.archController,
    functionSignature: "removeControllerFactory(address)",
    args: [rotation.superseded.standardHooksFactory],
  });
  assert.throws(() => assertRotationPlan(retirement, rotation, artifacts));
  const stale = structuredClone(plan);
  stale.transactions.find(
    (t) => t.id === "deploy-hooks-factory-standard"
  ).constructorArgs.decoded[2] = rotation.superseded.wrapperFactory;
  assert.throws(() => assertRotationPlan(stale, rotation, artifacts));
});

test("Anvil transform preserves live actions and rejects edited calldata", () => {
  const rehearsal = buildRehearsalPlan(plan);
  assert.equal(rehearsal.chainId, 31337);
  assert.doesNotThrow(() => assertRehearsalPlan(rehearsal, plan));
  rehearsal.transactions[0].constructorArgs.decoded[0] =
    rotation.superseded.standardHooksFactory;
  assert.throws(() => assertRehearsalPlan(rehearsal, plan));
});

test("historical default cannot relabel the 2.5.3 packet as 2.5.4", () => {
  const env = { ...process.env };
  delete env.SEPOLIA_REPLACEMENT_CONFIG;
  const result = spawnSync(
    process.execPath,
    ["scripts/sepolia-v2-5-fix-rotation.js", "validate"],
    { cwd: root, env, encoding: "utf8" }
  );
  assert.notEqual(result.status, 0);
  assert.match(
    result.stderr,
    /Package version does not match selected release 2\.5\.3/
  );
});
