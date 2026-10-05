const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { createHash } = require("node:crypto");
const { getAddress, keccak256 } = require("ethers");

const ROOT = path.resolve(__dirname, "..");
const REUSABLE = {
  "access-list-role-provider-factory": "AccessListRoleProviderFactory",
  "open-term-hooks-init-code-storage": "OpenTermHooks_initCodeStorage",
  "fixed-term-hooks-init-code-storage": "FixedTermHooks_initCodeStorage",
  "periodic-term-hooks-init-code-storage": "PeriodicTermHooks_initCodeStorage",
};

// Only these unchanged, independently deployed components may be carried into
// a new factory generation. Original receipts remain owned by the pinned handoff.
function loadReusedDeployments(rotation) {
  const specs = rotation.reusedDeployments || [];
  const records = new Map();
  if (!specs.length) return records;
  if (rotation.network !== "sepolia" || rotation.chainId !== 11155111 ||
      !/^[0-9a-f]{40}$/.test(rotation.inventoryBaselineCommit)) {
    throw new Error("Reused deployments require a pinned Sepolia baseline");
  }
  const readPinned = (filename) => {
    if (!/^deployments\/sepolia\/(?:handoff|template-update|plan)-v\d+\.\d+\.\d+\.json$/.test(filename)) {
      throw new Error(`Invalid reused deployment source: ${filename}`);
    }
    const bytes = execFileSync("git", ["show", `${rotation.inventoryBaselineCommit}:${filename}`],
      { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
    if (!bytes.equals(fs.readFileSync(path.join(ROOT, filename)))) {
      throw new Error(`Reused deployment source differs from its pinned baseline: ${filename}`);
    }
    return { json: JSON.parse(bytes), sha256: createHash("sha256").update(bytes).digest("hex") };
  };
  for (const spec of specs) {
    const key = REUSABLE[spec.output];
    if (!key || records.has(spec.output)) throw new Error("Unsupported or duplicate reused deployment output");
    const source = readPinned(spec.handoff);
    const handoff = source.json;
    if (handoff.chain?.network !== rotation.network || handoff.chain?.chainId !== rotation.chainId ||
        !/^v\d+\.\d+\.\d+$/.test(handoff.release)) {
      throw new Error("Reused handoff has the wrong release or network");
    }
    const deploymentKey = `${key}_${handoff.release}`;
    const record = (handoff.releaseContracts || handoff.templates || []).find((r) => r.deploymentKey === deploymentKey);
    const planPath = `deployments/sepolia/plan-${handoff.release}.json`;
    const sourcePlan = readPinned(planPath);
    const plan = sourcePlan.json;
    const entry = plan.transactions.find((tx) => tx.kind === "deploy" && tx.output === spec.output);
    if (!record || !entry || plan.release !== handoff.release || plan.network !== rotation.network ||
        plan.chainId !== rotation.chainId || record.forgeArtifactName !== entry.artifactName ||
        !/^0x[0-9a-fA-F]{64}$/.test(record.deployTxHash) ||
        !Number.isSafeInteger(record.startBlock) || record.startBlock <= 0) {
      throw new Error(`Missing original deployment provenance for ${spec.output}`);
    }
    const storage = key.endsWith("_initCodeStorage");
    if (storage && (entry.predicate.type !== "codeHash" ||
        entry.predicate.initCodeHash !== record.initCodeHash ||
        entry.artifactName !== "script/common/PreparedInitCodeStorage.sol:PreparedInitCodeStorage" ||
        entry.constructorArgs.decoded.length !== 1 ||
        !entry.constructorArgs.decoded[0].startsWith("0x00") ||
        keccak256(entry.constructorArgs.decoded[0]) !== entry.predicate.expect ||
        keccak256(`0x${entry.constructorArgs.decoded[0].slice(4)}`) !== record.initCodeHash)) {
      throw new Error(`Reused template storage commitment differs: ${spec.output}`);
    }
    if (!storage && (entry.constructorArgs.decoded.length || entry.predicate.type !== "codeHash")) {
      throw new Error("Reused AccessList factory must have no constructor bindings");
    }
    records.set(spec.output, {
      output: spec.output,
      address: getAddress(record.address),
      startBlock: record.startBlock,
      txHash: record.deployTxHash,
      forgeArtifactName: record.forgeArtifactName,
      abiArtifactName: record.abiArtifactName,
      ...(storage ? { initCodeHash: record.initCodeHash } : {}),
      runtimeCodeHash: entry.predicate.expect,
      bytecode: storage ? `0x${entry.constructorArgs.decoded[0].slice(4)}` : entry.initCode,
      provenance: {
        output: spec.output,
        deploymentKey,
        handoff: spec.handoff,
        handoffSha256: source.sha256,
        plan: planPath,
        planSha256: sourcePlan.sha256,
        inventoryBaselineCommit: rotation.inventoryBaselineCommit,
      },
    });
  }
  return records;
}

function loadReleaseReuse(network, release) {
  if (!/^[a-z0-9-]+$/.test(network) || !/^v\d+\.\d+\.\d+$/.test(release)) return new Map();
  const file = path.join(ROOT, "deployments", network, `${release}.json`);
  if (!fs.existsSync(file)) return new Map();
  const config = JSON.parse(fs.readFileSync(file, "utf8"));
  if (config.network !== network || config.release !== release) throw new Error("Reuse config identity mismatch");
  return loadReusedDeployments(config);
}

module.exports = { loadReusedDeployments, loadReleaseReuse };
