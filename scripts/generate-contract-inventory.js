#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const parser = require("@solidity-parser/parser");
const { id, keccak256, toUtf8Bytes } = require("ethers");

const SCHEMA_VERSION = "1.0.0";

function usage() {
  console.log(`Usage:
  node scripts/generate-contract-inventory.js \\
    --release <name> --ref <git-ref> [--repo <path>] \\
    [--artifacts <path>] [--output <path>] [--check]

The source inventory is read directly from the requested Git commit. Supplying
--artifacts adds ABI signatures and hashes after proving that every first-party
artifact was compiled from that commit. --check compares generated output with
an existing --output file without writing it.`);
}

function readValue(argv, index, option) {
  const value = argv[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`Missing value for ${option}.`);
  }
  return value;
}

function parseArgs(argv) {
  const args = {
    artifacts: undefined,
    check: false,
    output: undefined,
    ref: undefined,
    release: undefined,
    repo: process.cwd(),
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--artifacts") {
      args.artifacts = readValue(argv, i, arg);
      i += 1;
    } else if (arg === "--check") {
      args.check = true;
    } else if (arg === "--output") {
      args.output = readValue(argv, i, arg);
      i += 1;
    } else if (arg === "--ref") {
      args.ref = readValue(argv, i, arg);
      i += 1;
    } else if (arg === "--release") {
      args.release = readValue(argv, i, arg);
      i += 1;
    } else if (arg === "--repo") {
      args.repo = readValue(argv, i, arg);
      i += 1;
    } else if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!args.release) throw new Error("Missing --release.");
  if (!args.ref) throw new Error("Missing --ref.");
  if (args.check && !args.output) {
    throw new Error("--check requires --output.");
  }
  return args;
}

function git(repo, args, options = {}) {
  const { trim = true, ...execOptions } = options;
  const output = execFileSync("git", ["-C", repo, ...args], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    stdio: ["ignore", "pipe", "pipe"],
    ...execOptions,
  });
  return trim ? output.trim() : output;
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

function contractBaseName(base) {
  const name = base?.baseName;
  return name?.namePath || name?.name || name?.type || "unknown";
}

function sourceInventory(repo, commit) {
  const listing = git(repo, [
    "ls-tree",
    "-r",
    "--name-only",
    commit,
    "--",
    "src",
  ]);
  const sourcePaths = listing
    .split("\n")
    .filter((sourcePath) => sourcePath.endsWith(".sol"))
    .sort();

  if (sourcePaths.length === 0) {
    throw new Error(`No Solidity source files found under src/ at ${commit}.`);
  }

  const contentsByPath = new Map();
  const sources = sourcePaths.map((sourcePath) => {
    const contents = git(repo, ["show", `${commit}:${sourcePath}`], {
      maxBuffer: 16 * 1024 * 1024,
      trim: false,
    });
    contentsByPath.set(sourcePath, contents);

    let ast;
    try {
      ast = parser.parse(contents, {
        loc: false,
        range: false,
        tolerant: false,
      });
    } catch (error) {
      throw new Error(`Could not parse ${sourcePath}: ${error.message}`);
    }

    const declarations = (ast.children || [])
      .filter((node) => node.type === "ContractDefinition")
      .map((node) => ({
        name: node.name,
        kind: node.kind,
        bases: (node.baseContracts || []).map(contractBaseName),
      }))
      .sort((a, b) => a.name.localeCompare(b.name));

    return {
      path: sourcePath,
      gitBlob: git(repo, ["rev-parse", `${commit}:${sourcePath}`]),
      keccak256: keccak256(toUtf8Bytes(contents)),
      declarations,
    };
  });

  return { contentsByPath, sources };
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

function gitLinks(repo, commit) {
  const links = [];
  for (const line of git(repo, ["ls-tree", "-r", commit]).split("\n")) {
    const match = line.match(/^160000 commit ([0-9a-f]{40})\t(.+)$/);
    if (!match) continue;
    links.push({ path: match[2], commit: match[1] });
  }
  return links.sort((a, b) => b.path.length - a.path.length);
}

function committedDependencySource(repo, commit, sourcePath, links) {
  const link = links.find(
    (candidate) =>
      sourcePath === candidate.path ||
      sourcePath.startsWith(`${candidate.path}/`)
  );
  if (!link) {
    return {
      contents: git(repo, ["show", `${commit}:${sourcePath}`], {
        maxBuffer: 16 * 1024 * 1024,
        trim: false,
      }),
      dependency: null,
    };
  }

  const relativePath = sourcePath.slice(link.path.length + 1);
  const submodulePath = path.join(repo, ...link.path.split("/"));
  return {
    contents: git(submodulePath, ["show", `${link.commit}:${relativePath}`], {
      maxBuffer: 16 * 1024 * 1024,
      trim: false,
    }),
    dependency: link,
  };
}

function canonicalAbiType(parameter) {
  if (!parameter.type.startsWith("tuple")) return parameter.type;
  const suffix = parameter.type.slice("tuple".length);
  const components = (parameter.components || []).map(canonicalAbiType);
  return `(${components.join(",")})${suffix}`;
}

function abiSignature(entry, fallbackName) {
  const inputs = (entry.inputs || []).map(canonicalAbiType).join(",");
  return `${entry.name || fallbackName}(${inputs})`;
}

function abiSurface(artifact) {
  const abi = artifact.abi || [];
  const errors = [];
  const events = [];
  const functions = [];
  const constructors = [];
  const special = [];

  for (const entry of abi) {
    if (entry.type === "error") {
      const signature = abiSignature(entry, "error");
      errors.push({ signature, selector: id(signature).slice(0, 10) });
    } else if (entry.type === "event") {
      const signature = abiSignature(entry, "event");
      events.push({
        signature,
        topic0: entry.anonymous ? null : id(signature),
        anonymous: Boolean(entry.anonymous),
      });
    } else if (entry.type === "function") {
      const signature = abiSignature(entry, "function");
      const selector = `0x${
        artifact.methodIdentifiers?.[signature] || id(signature).slice(2, 10)
      }`;
      functions.push({ signature, selector });
    } else if (entry.type === "constructor") {
      constructors.push(abiSignature(entry, "constructor"));
    } else if (entry.type === "fallback" || entry.type === "receive") {
      special.push(entry.type);
    }
  }

  const bySignature = (a, b) => a.signature.localeCompare(b.signature);
  errors.sort(bySignature);
  events.sort(bySignature);
  functions.sort(bySignature);
  constructors.sort();
  special.sort();

  return {
    sha256: sha256(canonicalJson(abi)),
    entryCount: abi.length,
    constructors,
    errors,
    events,
    functions,
    special,
  };
}

function buildSettings(artifact) {
  const settings = artifact.metadata.settings;
  return {
    compiler: artifact.metadata.compiler?.version || null,
    evmVersion: settings.evmVersion || null,
    viaIR: Boolean(settings.viaIR),
    optimizer: settings.optimizer || null,
    metadata: settings.metadata || null,
  };
}

function artifactInventory(
  repo,
  commit,
  artifactDirectory,
  sources,
  contentsByPath
) {
  const checkedOutCommit = git(repo, ["rev-parse", "HEAD"]);
  if (checkedOutCommit !== commit) {
    throw new Error(
      `ABI inventory requires the repository checkout at ${commit}; found ${checkedOutCommit}.`
    );
  }

  const links = gitLinks(repo, commit);
  const referencedDependencies = new Map();
  const declarationByKey = new Map();
  for (const source of sources) {
    for (const declaration of source.declarations) {
      declarationByKey.set(`${source.path}:${declaration.name}`, {
        source: source.path,
        ...declaration,
      });
    }
  }

  const artifactsByKey = new Map();
  for (const artifactPath of walkJsonFiles(artifactDirectory)) {
    let artifact;
    try {
      artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
    } catch (_error) {
      continue;
    }

    const compilationTarget = artifact.metadata?.settings?.compilationTarget;
    if (!compilationTarget) continue;
    const targets = Object.entries(compilationTarget).filter(([sourcePath]) =>
      sourcePath.startsWith("src/")
    );
    if (targets.length === 0) continue;
    if (targets.length !== 1) {
      throw new Error(
        `Expected one first-party compilation target in ${artifactPath}; found ${targets.length}.`
      );
    }

    const [[sourcePath, name]] = targets;
    const key = `${sourcePath}:${name}`;
    if (artifactsByKey.has(key)) {
      throw new Error(`Duplicate artifact for ${key}.`);
    }
    if (!declarationByKey.has(key)) {
      throw new Error(
        `Artifact target ${key} is not declared by the requested commit.`
      );
    }

    for (const [metadataPath, metadataSource] of Object.entries(
      artifact.metadata.sources || {}
    )) {
      let contents = contentsByPath.get(metadataPath);
      if (contents === undefined) {
        let resolved;
        try {
          resolved = committedDependencySource(
            repo,
            commit,
            metadataPath,
            links
          );
        } catch (_error) {
          throw new Error(
            `${key} was compiled with source absent from the requested commit: ${metadataPath}.`
          );
        }
        contents = resolved.contents;
        if (resolved.dependency) {
          referencedDependencies.set(
            resolved.dependency.path,
            resolved.dependency
          );
        }
      }
      const expectedHash = keccak256(toUtf8Bytes(contents));
      if (metadataSource.keccak256 !== expectedHash) {
        throw new Error(
          `${key} artifact source mismatch for ${metadataPath}: expected ${expectedHash}, got ${metadataSource.keccak256}.`
        );
      }
    }

    artifactsByKey.set(key, {
      artifact,
      settings: buildSettings(artifact),
    });
  }

  const missing = [...declarationByKey.keys()].filter(
    (key) => !artifactsByKey.has(key)
  );
  if (missing.length > 0) {
    throw new Error(`Missing first-party artifacts:\n${missing.join("\n")}`);
  }

  const settingsByFingerprint = new Map();
  for (const { settings } of artifactsByKey.values()) {
    settingsByFingerprint.set(canonicalJson(settings), settings);
  }
  if (settingsByFingerprint.size !== 1) {
    throw new Error(
      `Artifacts use ${settingsByFingerprint.size} compiler setting sets; expected one.`
    );
  }

  const abis = [...declarationByKey.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, declaration]) => ({
      ...declaration,
      abi: abiSurface(artifactsByKey.get(key).artifact),
    }));

  return {
    abiArtifactBuild: [...settingsByFingerprint.values()][0],
    dependencies: [...referencedDependencies.values()].sort((a, b) =>
      a.path.localeCompare(b.path)
    ),
    abis,
  };
}

function renderInventory(args) {
  const repo = git(path.resolve(args.repo), ["rev-parse", "--show-toplevel"]);
  const commit = git(repo, ["rev-parse", "--verify", `${args.ref}^{commit}`]);
  const sourceTree = git(repo, ["rev-parse", `${commit}:src`]);
  const { contentsByPath, sources } = sourceInventory(repo, commit);
  const declarationCount = sources.reduce(
    (count, source) => count + source.declarations.length,
    0
  );

  const inventory = {
    schemaVersion: SCHEMA_VERSION,
    generator: {
      path: "scripts/generate-contract-inventory.js",
      command: "yarn inventory:contracts",
    },
    release: args.release,
    commit,
    sourceTree,
    sourceUnitCount: sources.length,
    declarationCount,
    sources,
  };

  if (args.artifacts) {
    const artifactDirectory = path.resolve(repo, args.artifacts);
    if (!fs.statSync(artifactDirectory).isDirectory()) {
      throw new Error(`Artifact path is not a directory: ${artifactDirectory}`);
    }
    Object.assign(
      inventory,
      artifactInventory(
        repo,
        commit,
        artifactDirectory,
        sources,
        contentsByPath
      )
    );
  }

  return `${JSON.stringify(inventory, null, 2)}\n`;
}

function writeAtomic(filePath, contents) {
  const absolutePath = path.resolve(filePath);
  fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
  const temporaryPath = `${absolutePath}.tmp-${process.pid}`;
  fs.writeFileSync(temporaryPath, contents, "utf8");
  fs.renameSync(temporaryPath, absolutePath);
}

function main() {
  const args = parseArgs(process.argv);
  const output = renderInventory(args);

  if (args.check) {
    const expected = fs.readFileSync(path.resolve(args.output), "utf8");
    if (expected !== output) {
      throw new Error(`Generated inventory differs from ${args.output}.`);
    }
    console.log(`Contract inventory is current: ${args.output}`);
  } else if (args.output) {
    writeAtomic(args.output, output);
    console.log(`Wrote contract inventory: ${args.output}`);
  } else {
    process.stdout.write(output);
  }
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
