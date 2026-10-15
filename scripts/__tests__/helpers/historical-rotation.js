const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { keccak256 } = require("ethers");
const { loadArtifacts } = require("../../sepolia-v2-5-fix-rotation");
const { loadReusedDeployments } = require("../../reused-deployments");

const root = path.resolve(__dirname, "../../..");

function baselineJson(rotation, name) {
  return JSON.parse(execFileSync("git", ["show",
    `${rotation.inventoryBaselineCommit}:deployments/sepolia/${name}`],
  { cwd: root, encoding: "utf8", maxBuffer: 8 * 1024 * 1024 }));
}

// historical plans expect the inventory before activation, not today's aliases.
// intercept fixture reads; never rewrite deployment records or build outputs.
function mockHistoricalInputs(t, rotation, artifacts) {
  const state = {
    inventory: baselineJson(rotation, "factory-inventory.json"),
    deployments: baselineJson(rotation, "deployments.json"),
  };
  const files = new Map([
    [path.join(root, "deployments/sepolia/factory-inventory.json"), state.inventory],
    [path.join(root, "deployments/sepolia/deployments.json"), state.deployments],
  ]);
  for (const { source, contract, artifact, bytecode } of Object.values(artifacts)) {
    const snapshot = structuredClone(artifact);
    snapshot.bytecode.object = bytecode;
    files.set(path.join(root, "deploy-out", path.basename(source), `${contract}.json`), snapshot);
  }
  const readFileSync = fs.readFileSync;
  t.mock.method(fs, "readFileSync", (filename, options) => {
    if (!files.has(filename)) return readFileSync(filename, options);
    const bytes = Buffer.from(JSON.stringify(files.get(filename)));
    const encoding = typeof options === "string" ? options : options?.encoding;
    return encoding ? bytes.toString(encoding) : bytes;
  });
  return state;
}

// restore historical creation code from the frozen plans. canonical runtime
// artifacts still check the unchanged AccessList factory and storage reader.
function historicalArtifacts(rotation, plan) {
  const artifacts = loadArtifacts(rotation);
  const plans = rotation.baseRelease
    ? [baselineJson(rotation, `plan-${rotation.baseRelease}.json`), plan]
    : [plan];
  for (const source of plans) {
    for (const artifact of Object.values(artifacts)) {
      const entry = source.transactions.find((tx) => tx.kind === "deploy" &&
        (artifact.storedInitCode ? tx.id === artifact.previousId : tx.artifactName === artifact.artifactName));
      if (!entry) continue;
      if (!artifact.storedInitCode) {
        artifact.bytecode = entry.initCode;
        continue;
      }
      const primary = entry.constructorArgs.decoded[0];
      if (entry.predicate.type === "splitCodeHash") {
        const length = parseInt(primary.slice(-8, -4), 16);
        const secondary = source.transactions.find((tx) => tx.output === entry.predicate.secondary.$ref);
        artifact.bytecode = `0x${primary.slice(-48 - length * 2, -48)}${secondary.constructorArgs.decoded[0].slice(4)}`;
      } else {
        assert.equal(entry.predicate.type, "codeHash");
        assert.ok(primary.startsWith("0x00"));
        artifact.bytecode = `0x${primary.slice(4)}`;
      }
      assert.equal(keccak256(artifact.bytecode), entry.predicate.initCodeHash);
    }
  }
  for (const [output, record] of loadReusedDeployments(rotation)) {
    const artifact = Object.values(artifacts).find((value) =>
      value.output === output || value.previousId === `deploy-${output}`);
    assert.ok(artifact, output);
    artifact.bytecode = record.bytecode;
  }
  return artifacts;
}

module.exports = { historicalArtifacts, mockHistoricalInputs };
