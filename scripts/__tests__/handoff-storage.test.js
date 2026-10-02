const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync, spawnSync } = require("node:child_process");
const {
  buildHandoff,
  validateHandoff,
  releaseDefinitions,
} = require("../generate-handoff");

const PREPARED =
  "script/common/PreparedInitCodeStorage.sol:PreparedInitCodeStorage";
const LINKED =
  "script/common/PreparedInitCodeStorage.sol:LinkedInitCodeStorage";
const address = (i) => `0x${i.toString(16).padStart(40, "0")}`;

function fixture(t, { split = true, splitHook = false } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "wildcat-handoff-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const network = "anvil";
  const release = "storage-test";
  const deployments = {};
  for (const [index, definition] of releaseDefinitions(release, {}).entries()) {
    deployments[definition.deploymentKey] = address(index + 1);
    if (
      definition.storage &&
      split &&
      (definition.kind === "market-init-code-storage" ||
        (splitHook && definition.key === "PeriodicTermHooks_initCodeStorage"))
    ) {
      deployments[`${definition.deploymentKey}_secondary`] = address(
        index + 101
      );
    }
  }
  const definitions = releaseDefinitions(release, deployments);
  const transactions = definitions.map((definition) => ({
    id: `deploy-${definition.planOutput}`,
    output: definition.planOutput,
    kind: "deploy",
    artifactName: definition.storage
      ? deployments[`${definition.deploymentKey}_secondary`]
        ? LINKED
        : split
        ? PREPARED
        : definition.forgeArtifactName
      : definition.forgeArtifactName,
  }));
  const runState = Object.fromEntries(
    transactions.map((transaction, index) => [
      transaction.id,
      {
        status: "verified",
        blockNumber: index + 1,
        txHash: `0x${(index + 1).toString(16).padStart(64, "0")}`,
        resolvedAddress: deployments[definitions[index].deploymentKey],
      },
    ])
  );
  const record = (key, marketType) => ({
    label: `${key}_${release}`,
    address: deployments[`${key}_${release}`],
    startBlock: 1,
    lifecycle: "canonical",
    canonical: true,
    registered: true,
    indexed: true,
    marketType,
    v1Factory: null,
  });
  const inventory = {
    schemaVersion: "1.1.0",
    network,
    chainId: 31337,
    recordCount: 3,
    hooksFactories: [
      record("HooksFactory", "legacy"),
      record("HooksFactoryRevolving", "revolving"),
    ],
    wrapperFactories: [record("Wildcat4626WrapperFactory", null)],
  };
  const write = (name, value) => {
    const file = path.join(directory, `${name}.json`);
    fs.writeFileSync(file, JSON.stringify(value));
    return file;
  };
  const input = {
    network,
    release,
    inventoryPath: write("inventory", inventory),
    deploymentsPath: write("deployments", deployments),
    planPath: write("plan", { network, release, transactions }),
    runStatePath: write("run-state", runState),
  };
  return {
    input,
    deployments,
    transactions,
    runState,
    validate: (handoff) =>
      validateHandoff(handoff, inventory, deployments, network, release),
  };
}

test("handoff records actual installers, both stores and their receipt provenance", (t) => {
  const f = fixture(t);
  const handoff = buildHandoff(f.input);
  assert.deepEqual(f.validate(handoff), []);
  assert.equal(handoff.releaseContracts.length, 16);
  const primary = handoff.releaseContracts.find(
    (c) => c.deploymentKey === "WildcatMarket_initCodeStorage_storage-test"
  );
  const secondary = handoff.releaseContracts.find(
    (c) => c.deploymentKey === `${primary.deploymentKey}_secondary`
  );
  assert.equal(primary.forgeArtifactName, LINKED);
  assert.equal(secondary.forgeArtifactName, PREPARED);
  assert.equal(secondary.abiArtifactName, PREPARED);
  assert.ok(secondary.startBlock > 0 && secondary.deployTxHash);
  assert.equal(secondary.address, f.deployments[secondary.deploymentKey]);
  assert.equal(
    handoff.releaseContracts.find((c) =>
      c.deploymentKey.startsWith("OpenTermHooks")
    ).forgeArtifactName,
    PREPARED
  );
});

test("handoff includes a future oversized hook's companion as well as both markets", (t) => {
  const f = fixture(t, { splitHook: true });
  const handoff = buildHandoff(f.input);
  assert.equal(handoff.releaseContracts.length, 17);
  assert.deepEqual(f.validate(handoff), []);
});

test("handoff rejects a missing companion and a fabricated installer", (t) => {
  const f = fixture(t);
  const handoff = buildHandoff(f.input);
  const index = handoff.releaseContracts.findIndex((c) =>
    c.deploymentKey.endsWith("_secondary")
  );
  const [secondary] = handoff.releaseContracts.splice(index, 1);
  assert.match(f.validate(handoff).join("\n"), /omits.*_secondary/);
  handoff.releaseContracts.splice(index, 0, secondary);
  secondary.forgeArtifactName = "Unreviewed.sol:Installer";
  assert.match(f.validate(handoff).join("\n"), /invalid artifact name/);
});

test("handoff does not infer the storage installer without verified plan metadata", (t) => {
  const f = fixture(t);
  const secondary = f.transactions.find((tx) => tx.output.endsWith("-secondary"));
  delete f.runState[secondary.id];
  fs.writeFileSync(f.input.runStatePath, JSON.stringify(f.runState));
  assert.throws(() => buildHandoff(f.input), /_secondary requires verified plan artifact metadata/);
  fs.unlinkSync(f.input.runStatePath);
  assert.throws(
    () => buildHandoff(f.input),
    /requires verified plan artifact metadata/
  );
});

test("handoff fails when the secondary receipt disagrees with the deployment record", (t) => {
  const f = fixture(t);
  const tx = f.transactions.find((tx) => tx.output.endsWith("-secondary"));
  f.runState[tx.id].resolvedAddress = address(999);
  fs.writeFileSync(f.input.runStatePath, JSON.stringify(f.runState));
  assert.throws(
    () => buildHandoff(f.input),
    /Run-state address mismatch.*_secondary/
  );
});

test("historical single-store handoffs still validate with their original artifacts", (t) => {
  const f = fixture(t, { split: false });
  const handoff = buildHandoff(f.input);
  assert.equal(handoff.releaseContracts.length, 14);
  assert.deepEqual(f.validate(handoff), []);
});

test("handoff Markdown escapes labels and still passes --check", (context) => {
  const setup = fixture(context);
  const directory = path.dirname(setup.input.inventoryPath);
  const labels = [
    ["plain|label", String.raw`plain\|label`],
    [String.raw`left\|right`, String.raw`left\\\|right`],
    [String.raw`double\\|pipe`, String.raw`double\\\\\|pipe`],
  ];
  const inventory = JSON.parse(fs.readFileSync(setup.input.inventoryPath));
  const records = [...inventory.hooksFactories, ...inventory.wrapperFactories];
  records.forEach((record, index) => (record.label = labels[index][0]));
  fs.writeFileSync(setup.input.inventoryPath, JSON.stringify(inventory));
  const args = [
    require.resolve("../generate-handoff"),
    "--network",
    setup.input.network,
    "--release",
    setup.input.release,
    "--inventory",
    setup.input.inventoryPath,
    "--deployments",
    setup.input.deploymentsPath,
    "--plan",
    setup.input.planPath,
    "--run-state",
    setup.input.runStatePath,
    "--output-dir",
    directory,
  ];
  execFileSync(process.execPath, args, { encoding: "utf8", timeout: 10_000 });
  const markdownPath = path.join(directory, `handoff-${setup.input.release}.md`);
  const markdown = fs.readFileSync(markdownPath, "utf8");
  for (const [, escaped] of labels) {
    assert.ok(markdown.includes(`| ${escaped} |`), escaped);
  }
  const handoff = JSON.parse(
    fs.readFileSync(path.join(directory, `handoff-${setup.input.release}.json`))
  );
  assert.deepEqual(
    handoff.factoryGenerations.map((generation) => generation.label),
    labels.map(([label]) => label)
  );
  execFileSync(process.execPath, [...args, "--check"], {
    encoding: "utf8",
    timeout: 10_000,
  });
  fs.writeFileSync(
    markdownPath,
    markdown.replace(`| ${labels[1][1]} |`, "| missing-label |")
  );
  const missing = spawnSync(process.execPath, [...args, "--check"], {
    encoding: "utf8",
    timeout: 10_000,
  });
  assert.ifError(missing.error);
  assert.equal(missing.status, 1);
  assert.ok(missing.stderr.includes(`omits factory ${labels[1][0]}`));
});
