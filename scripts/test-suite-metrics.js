#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

function usage() {
  console.error(
    [
      "Usage: node scripts/test-suite-metrics.js [options]",
      "",
      "Options:",
      "  --artifacts <dir>       Foundry artifact directory (default: out)",
      "  --cache <file>          Foundry source cache (default: cache/solidity-files-cache.json)",
      "  --prefix <path>         Test source prefix; repeatable (default: test/)",
      "  --exclude-prefix <path> Excluded source prefix; repeatable (default: test/fizz/)",
      "  --compact               Omit per-artifact case copies; retain the parity ledger",
      "  -h, --help              Show this help",
    ].join("\n")
  );
}

function parseArgs(argv) {
  const args = {
    artifacts: "out",
    cache: "cache/solidity-files-cache.json",
    prefixes: [],
    excludedPrefixes: [],
    compact: false,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--artifacts") {
      args.artifacts = argv[++i];
    } else if (arg === "--cache") {
      args.cache = argv[++i];
    } else if (arg === "--prefix") {
      args.prefixes.push(argv[++i]);
    } else if (arg === "--exclude-prefix") {
      args.excludedPrefixes.push(argv[++i]);
    } else if (arg === "--compact") {
      args.compact = true;
    } else if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!args.artifacts) throw new Error("Missing value for --artifacts.");
  if (!args.cache) throw new Error("Missing value for --cache.");
  if (args.prefixes.some((value) => !value)) {
    throw new Error("Missing value for --prefix.");
  }
  if (args.excludedPrefixes.some((value) => !value)) {
    throw new Error("Missing value for --exclude-prefix.");
  }

  if (args.prefixes.length === 0) args.prefixes.push("test/");
  if (args.excludedPrefixes.length === 0) {
    args.excludedPrefixes.push("test/fizz/");
  }
  return args;
}

function normalizePrefix(value) {
  const normalized = value.replaceAll("\\", "/").replace(/^\.\//, "");
  return normalized.endsWith("/") ? normalized : `${normalized}/`;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function byteLength(bytecode) {
  if (!bytecode) return 0;
  const value = bytecode.startsWith("0x") ? bytecode.slice(2) : bytecode;
  return Math.floor(value.length / 2);
}

function collectArtifactPaths(value, paths = new Set()) {
  if (!value || typeof value !== "object") return paths;
  if (typeof value.path === "string") paths.add(value.path);
  for (const child of Object.values(value)) collectArtifactPaths(child, paths);
  return paths;
}

function getCompilationTarget(artifact, artifactPath, fallbackSource) {
  const entries = Object.entries(
    artifact.metadata?.settings?.compilationTarget || {}
  );
  if (entries.length === 0 && fallbackSource) {
    return {
      source: fallbackSource,
      contract: path.basename(artifactPath, ".json"),
    };
  }
  if (entries.length !== 1) {
    throw new Error(
      `Expected one compilation target in ${artifactPath}, found ${entries.length}.`
    );
  }
  const [[source, contract]] = entries;
  return { source, contract };
}

function getMethodName(signature) {
  const index = signature.indexOf("(");
  return index === -1 ? signature : signature.slice(0, index);
}

function isTestMethod(signature) {
  const name = getMethodName(signature);
  return (
    (name.startsWith("test") && !name.startsWith("testFail")) ||
    name.startsWith("invariant")
  );
}

function isInvariantMethod(signature) {
  return getMethodName(signature).startsWith("invariant");
}

function sourceCategory(source, prefixes) {
  const prefix = prefixes.find((candidate) => source.startsWith(candidate));
  const relative = prefix ? source.slice(prefix.length) : source;
  const slash = relative.indexOf("/");
  return slash === -1 ? "root" : relative.slice(0, slash);
}

function sum(values) {
  return values.reduce((total, value) => total + value, 0);
}

function main() {
  const args = parseArgs(process.argv);
  const prefixes = args.prefixes.map(normalizePrefix);
  const excludedPrefixes = args.excludedPrefixes.map(normalizePrefix);
  const cache = readJson(args.cache);
  const artifactCache = new Map();

  function readArtifact(relativePath) {
    const artifactPath = path.join(args.artifacts, relativePath);
    if (!artifactCache.has(artifactPath)) {
      artifactCache.set(artifactPath, readJson(artifactPath));
    }
    return artifactCache.get(artifactPath);
  }

  function isSelectedSource(source) {
    return (
      prefixes.some((prefix) => source.startsWith(prefix)) &&
      !excludedPrefixes.some((prefix) => source.startsWith(prefix))
    );
  }

  const contractsById = new Map();
  const contractsBySourceAndName = new Map();
  const artifactPathsBySource = new Map();

  for (const [source, sourceData] of Object.entries(cache.files || {})) {
    const artifactPaths = [
      ...collectArtifactPaths(sourceData.artifacts),
    ].sort();
    artifactPathsBySource.set(source, artifactPaths);
    if (artifactPaths.length === 0) continue;

    const artifact = readArtifact(artifactPaths[0]);
    const ast = artifact.ast;
    if (!ast || !Array.isArray(ast.nodes)) continue;

    for (const node of ast.nodes) {
      if (node.nodeType !== "ContractDefinition") continue;
      const ownFunctions = (node.nodes || [])
        .filter(
          (child) =>
            child.nodeType === "FunctionDefinition" &&
            typeof child.functionSelector === "string"
        )
        .map((child) => ({
          id: child.id,
          name: child.name,
          selector: child.functionSelector,
        }));
      const contract = {
        id: node.id,
        source,
        name: node.name,
        abstract: node.abstract === true,
        linearizedBaseContracts: node.linearizedBaseContracts || [node.id],
        ownFunctions,
      };
      contractsById.set(contract.id, contract);
      contractsBySourceAndName.set(`${source}:${contract.name}`, contract);
    }
  }

  const artifactsByKey = new Map();

  for (const [source, artifactPaths] of artifactPathsBySource) {
    if (!isSelectedSource(source)) continue;
    for (const artifactPath of artifactPaths) {
      const artifact = readArtifact(artifactPath);
      const target = getCompilationTarget(artifact, artifactPath, source);
      if (target.source !== source || !isSelectedSource(target.source))
        continue;

      const key = `${target.source}:${target.contract}`;
      const methodIdentifiers = artifact.methodIdentifiers || {};
      const abiFunctions = new Map(
        (artifact.abi || [])
          .filter((entry) => entry.type === "function")
          .map((entry) => [
            `${entry.name}(${(entry.inputs || [])
              .map((input) => input.type)
              .join(",")})`,
            entry,
          ])
      );
      const suiteContract = contractsBySourceAndName.get(key);
      const cases = Object.entries(methodIdentifiers)
        .filter(([signature]) => isTestMethod(signature))
        .map(([signature, selector]) => {
          let origin;
          for (const contractId of suiteContract?.linearizedBaseContracts ||
            []) {
            const candidate = contractsById.get(contractId);
            if (!candidate) continue;
            const declaration = candidate.ownFunctions.find(
              (method) =>
                method.selector === selector &&
                method.name === getMethodName(signature)
            );
            if (declaration) {
              origin = {
                source: candidate.source,
                contract: candidate.name,
                functionId: declaration.id,
              };
              break;
            }
          }
          const abi = abiFunctions.get(signature);
          return {
            signature,
            selector,
            kind: isInvariantMethod(signature) ? "invariant" : "test",
            parameterized:
              abi !== undefined
                ? (abi.inputs?.length || 0) > 0
                : !signature.endsWith("()"),
            inherited:
              origin !== undefined &&
              (origin.source !== target.source ||
                origin.contract !== target.contract),
            origin: origin || null,
          };
        })
        .sort((a, b) => a.signature.localeCompare(b.signature));

      const record = {
        source: target.source,
        contract: target.contract,
        category: sourceCategory(target.source, prefixes),
        abstract: suiteContract?.abstract === true,
        initcodeBytes: byteLength(artifact.bytecode?.object),
        runtimeBytes: byteLength(artifact.deployedBytecode?.object),
        cases,
      };

      const previous = artifactsByKey.get(key);
      if (previous && JSON.stringify(previous) !== JSON.stringify(record)) {
        throw new Error(`Conflicting artifacts found for ${key}.`);
      }
      artifactsByKey.set(key, record);
    }
  }

  const artifacts = [...artifactsByKey.values()].sort(
    (a, b) =>
      b.initcodeBytes - a.initcodeBytes ||
      a.source.localeCompare(b.source) ||
      a.contract.localeCompare(b.contract)
  );
  const suites = artifacts.filter(
    (artifact) =>
      !artifact.abstract &&
      artifact.initcodeBytes > 0 &&
      artifact.cases.length > 0
  );
  const cases = suites.flatMap((suite) =>
    suite.cases.map((testCase) => ({
      suite: `${suite.source}:${suite.contract}`,
      ...testCase,
    }))
  );

  const categoryMap = new Map();
  for (const artifact of artifacts) {
    if (!categoryMap.has(artifact.category)) {
      categoryMap.set(artifact.category, {
        category: artifact.category,
        artifacts: 0,
        bytecodeArtifacts: 0,
        suites: 0,
        tests: 0,
        invariants: 0,
        inheritedEntries: 0,
        parameterizedEntries: 0,
        initcodeBytes: 0,
        runtimeBytes: 0,
      });
    }
    const category = categoryMap.get(artifact.category);
    category.artifacts += 1;
    if (artifact.initcodeBytes > 0) category.bytecodeArtifacts += 1;
    const runnableCases =
      !artifact.abstract && artifact.initcodeBytes > 0 ? artifact.cases : [];
    if (runnableCases.length > 0) category.suites += 1;
    category.tests += runnableCases.filter(
      (entry) => entry.kind === "test"
    ).length;
    category.invariants += runnableCases.filter(
      (entry) => entry.kind === "invariant"
    ).length;
    category.inheritedEntries += runnableCases.filter(
      (entry) => entry.inherited
    ).length;
    category.parameterizedEntries += runnableCases.filter(
      (entry) => entry.parameterized
    ).length;
    category.initcodeBytes += artifact.initcodeBytes;
    category.runtimeBytes += artifact.runtimeBytes;
  }

  const originMap = new Map();
  for (const testCase of cases) {
    const originKey = testCase.origin
      ? `${testCase.origin.source}:${testCase.origin.contract}:${testCase.signature}`
      : `unknown:${testCase.signature}`;
    if (!originMap.has(originKey)) {
      originMap.set(originKey, {
        origin: testCase.origin,
        signature: testCase.signature,
        kind: testCase.kind,
        parameterized: testCase.parameterized,
        suites: [],
      });
    }
    originMap.get(originKey).suites.push(testCase.suite);
  }

  const propertyGroups = [...originMap.values()]
    .map((group) => ({
      ...group,
      suites: group.suites.sort(),
      concreteEntries: group.suites.length,
    }))
    .sort(
      (a, b) =>
        b.concreteEntries - a.concreteEntries ||
        (a.origin?.source || "").localeCompare(b.origin?.source || "") ||
        a.signature.localeCompare(b.signature)
    );

  const firstArtifact = artifacts[0]
    ? readArtifact(artifactPathsBySource.get(artifacts[0].source)[0])
    : undefined;
  const result = {
    schemaVersion: 1,
    gitCommit: execFileSync("git", ["rev-parse", "HEAD"], {
      encoding: "utf8",
    }).trim(),
    artifactsDirectory: args.artifacts,
    cacheFile: args.cache,
    buildIds: cache.builds || [],
    compiler: firstArtifact
      ? {
          version: firstArtifact.metadata?.compiler?.version,
          evmVersion: firstArtifact.metadata?.settings?.evmVersion,
          viaIR: firstArtifact.metadata?.settings?.viaIR,
          optimizer: firstArtifact.metadata?.settings?.optimizer,
          metadata: firstArtifact.metadata?.settings?.metadata,
        }
      : null,
    includedPrefixes: prefixes,
    excludedPrefixes,
    totals: {
      sourceFiles: new Set(artifacts.map((artifact) => artifact.source)).size,
      artifacts: artifacts.length,
      bytecodeArtifacts: artifacts.filter(
        (artifact) => artifact.initcodeBytes > 0
      ).length,
      suites: suites.length,
      entries: cases.length,
      tests: cases.filter((entry) => entry.kind === "test").length,
      invariants: cases.filter((entry) => entry.kind === "invariant").length,
      parameterizedEntries: cases.filter((entry) => entry.parameterized).length,
      inheritedEntries: cases.filter((entry) => entry.inherited).length,
      inheritedTests: cases.filter(
        (entry) => entry.inherited && entry.kind === "test"
      ).length,
      inheritedInvariants: cases.filter(
        (entry) => entry.inherited && entry.kind === "invariant"
      ).length,
      unknownOrigins: cases.filter((entry) => entry.origin === null).length,
      uniqueDeclaredProperties: propertyGroups.length,
      initcodeBytes: sum(artifacts.map((artifact) => artifact.initcodeBytes)),
      runtimeBytes: sum(artifacts.map((artifact) => artifact.runtimeBytes)),
    },
    categories: [...categoryMap.values()].sort((a, b) =>
      a.category.localeCompare(b.category)
    ),
    artifacts: args.compact
      ? artifacts.map(({ cases, ...artifact }) => ({
          ...artifact,
          caseCount: cases.length,
        }))
      : artifacts,
    propertyGroups,
  };

  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

try {
  main();
} catch (error) {
  console.error(error.stack || error.message);
  process.exit(1);
}
