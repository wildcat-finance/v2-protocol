#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

function usage() {
  console.error(
    "Usage: node scripts/gas-sweep-metrics.js [--artifacts <dir>] [--snapshot <file>]"
  );
}

function parseArgs(argv) {
  const args = { artifacts: "deploy-out", snapshot: undefined };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--artifacts") {
      args.artifacts = argv[++i];
    } else if (arg === "--snapshot") {
      args.snapshot = argv[++i];
    } else if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (!args.artifacts) throw new Error("Missing value for --artifacts.");
  if (argv.includes("--snapshot") && !args.snapshot) {
    throw new Error("Missing value for --snapshot.");
  }
  return args;
}

function walkJsonFiles(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkJsonFiles(entryPath));
    } else if (entry.isFile() && entry.name.endsWith(".json")) {
      files.push(entryPath);
    }
  }
  return files;
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonicalize(value[key])])
    );
  }
  return value;
}

function canonicalJson(value) {
  return JSON.stringify(canonicalize(value));
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function byteLength(bytecode) {
  if (!bytecode) return 0;
  const value = bytecode.startsWith("0x") ? bytecode.slice(2) : bytecode;
  return Math.floor(value.length / 2);
}

function expandStorageType(typeId, types, active = new Set()) {
  const type = types?.[typeId];
  if (!type) return { missingType: typeId };
  if (active.has(typeId)) return { recursiveType: type.label };

  const nextActive = new Set(active);
  nextActive.add(typeId);
  const expanded = {
    encoding: type.encoding,
    label: type.label,
    numberOfBytes: type.numberOfBytes,
  };
  if (type.base)
    expanded.base = expandStorageType(type.base, types, nextActive);
  if (type.key) expanded.key = expandStorageType(type.key, types, nextActive);
  if (type.value)
    expanded.value = expandStorageType(type.value, types, nextActive);
  if (type.members) {
    expanded.members = type.members.map((member) => ({
      label: member.label,
      offset: member.offset,
      slot: member.slot,
      type: expandStorageType(member.type, types, nextActive),
    }));
  }
  return expanded;
}

function normalizeStorageLayout(layout) {
  if (!Array.isArray(layout?.storage) || !layout?.types) return undefined;
  return layout.storage.map((entry) => ({
    label: entry.label,
    offset: entry.offset,
    slot: entry.slot,
    type: expandStorageType(entry.type, layout.types),
  }));
}

function readTargetArtifact(file) {
  const artifact = JSON.parse(fs.readFileSync(file, "utf8"));
  const compilationTarget = artifact.metadata?.settings?.compilationTarget;
  if (!compilationTarget) return undefined;
  const targets = Object.entries(compilationTarget).filter(([source]) =>
    source.startsWith("src/")
  );
  if (targets.length === 0) return undefined;
  if (targets.length !== 1) {
    throw new Error(
      `Expected one compilation target in ${file}, found ${targets.length}.`
    );
  }

  const [[source, contract]] = targets;
  const initcode = artifact.bytecode?.object || "";
  const runtime = artifact.deployedBytecode?.object || "";
  const storageLayout = normalizeStorageLayout(artifact.storageLayout);
  const hasStorageLayout = storageLayout !== undefined;
  return {
    source,
    contract,
    initcodeBytes: byteLength(initcode),
    runtimeBytes: byteLength(runtime),
    eip170Margin: 24_576 - byteLength(runtime),
    eip3860Margin: 49_152 - byteLength(initcode),
    initcodeSha256: sha256(initcode),
    runtimeSha256: sha256(runtime),
    abiSha256: sha256(canonicalJson(artifact.abi || [])),
    storageLayoutSha256: hasStorageLayout
      ? sha256(canonicalJson(storageLayout))
      : null,
    abiEntries: artifact.abi?.length || 0,
    storageEntries: hasStorageLayout ? storageLayout.length : null,
  };
}

function getBuildSettings(artifactFiles) {
  for (const file of artifactFiles) {
    const artifact = JSON.parse(fs.readFileSync(file, "utf8"));
    const target = artifact.metadata?.settings?.compilationTarget;
    if (
      !target ||
      !Object.keys(target).some((source) => source.startsWith("src/"))
    )
      continue;
    const settings = artifact.metadata.settings;
    return {
      compiler: artifact.metadata.compiler?.version,
      evmVersion: settings.evmVersion,
      viaIR: settings.viaIR,
      optimizer: settings.optimizer,
      metadata: settings.metadata,
    };
  }
  throw new Error("No production Solidity artifacts found.");
}

function readGasSnapshot(snapshotPath) {
  const contents = fs.readFileSync(snapshotPath, "utf8");
  const gas = [];
  let cases = 0;
  let gasCases = 0;
  let fuzzCases = 0;
  let invariantCases = 0;
  for (const line of contents.split("\n")) {
    if (!line) continue;
    cases += 1;
    const gasMatch = line.match(/ \(gas: (\d+)\)$/);
    if (gasMatch) {
      gasCases += 1;
      gas.push(Number(gasMatch[1]));
      continue;
    }
    const fuzzMatch = line.match(/ \(runs: \d+, μ: (\d+), ~: \d+\)$/);
    if (fuzzMatch) {
      fuzzCases += 1;
      gas.push(Number(fuzzMatch[1]));
      continue;
    }
    if (/ \(runs: \d+, calls: \d+, reverts: \d+\)$/.test(line)) {
      invariantCases += 1;
      continue;
    }
    throw new Error(`Unrecognized gas snapshot line: ${line}`);
  }
  gas.sort((a, b) => a - b);
  const median = gas.length
    ? gas.length % 2
      ? gas[(gas.length - 1) / 2]
      : Math.floor((gas[gas.length / 2 - 1] + gas[gas.length / 2]) / 2)
    : 0;
  return {
    cases,
    gasCases,
    fuzzCases,
    invariantCases,
    sha256: sha256(contents),
    minimumGas: gas[0] || 0,
    medianGas: median,
    maximumGas: gas[gas.length - 1] || 0,
    totalGas: gas.reduce((sum, value) => sum + value, 0),
  };
}

function main() {
  const args = parseArgs(process.argv);
  const artifactFiles = walkJsonFiles(args.artifacts);
  const contractsByKey = new Map();

  for (const file of artifactFiles) {
    const contract = readTargetArtifact(file);
    if (!contract) continue;
    const key = `${contract.source}:${contract.contract}`;
    const previous = contractsByKey.get(key);
    if (previous && canonicalJson(previous) !== canonicalJson(contract)) {
      throw new Error(`Conflicting artifacts found for ${key}.`);
    }
    contractsByKey.set(key, contract);
  }

  const contracts = [...contractsByKey.values()].sort(
    (a, b) =>
      a.source.localeCompare(b.source) || a.contract.localeCompare(b.contract)
  );
  if (contracts.length === 0)
    throw new Error("No production Solidity artifacts found.");

  const result = {
    schemaVersion: 2,
    gitCommit: execFileSync("git", ["rev-parse", "HEAD"], {
      encoding: "utf8",
    }).trim(),
    build: getBuildSettings(artifactFiles),
    contractCount: contracts.length,
    contracts,
  };
  if (args.snapshot) result.gasSnapshot = readGasSnapshot(args.snapshot);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
