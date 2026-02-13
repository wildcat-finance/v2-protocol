#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const HANDOFF_SCHEMA_VERSION = "1.0.0";

function printUsage() {
  console.log(`Usage:
  node scripts/generate-rcf-handoff.js --network <name> [--chain-id <id>] [--rpc-url <url>]
    [--deployments-file <path>] [--output <path>]
    [--legacy-factory <address>] [--revolving-factory <address>] [--market-lens <address>] [--arch-controller <address>]
    [--hooks-script <name>] [--lens-script <name>]

Defaults:
  --deployments-file deployments/<network>/deployments.json
  --output           deployments/<network>/rcf-v2-handoff.json
  --hooks-script     DeployHooksFactoryRevolving.sol
  --lens-script      DeployMarketLens.sol
`);
}

function parseArgs(argv) {
  if (argv.length === 0 || argv.includes("--help") || argv.includes("-h")) {
    printUsage();
    process.exit(0);
  }
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) {
      throw new Error(`Unexpected argument: ${token}`);
    }
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      args[key] = true;
      continue;
    }
    args[key] = next;
    i += 1;
  }
  return args;
}

function chainIdToNetworkName(chainId) {
  if (chainId === 1) return "mainnet";
  if (chainId === 11155111) return "sepolia";
  return `chain-${chainId}`;
}

function networkNameToChainId(networkName) {
  if (networkName === "mainnet") return 1;
  if (networkName === "sepolia") return 11155111;
  return null;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function ensureDirForFile(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function writeJson(filePath, value) {
  ensureDirForFile(filePath);
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", "utf8");
}

function normalizeAddress(value, fieldName) {
  if (!value) {
    throw new Error(`Missing address for ${fieldName}`);
  }
  if (!/^0x[a-fA-F0-9]{40}$/.test(value)) {
    throw new Error(`Invalid address for ${fieldName}: ${value}`);
  }
  return value;
}

function resolveAddress(args, deployments, argKey, deploymentKey, fieldName) {
  const fromArg = args[argKey];
  const fromDeployments = deployments[deploymentKey];
  return normalizeAddress(fromArg || fromDeployments, fieldName);
}

function listNumericSubdirs(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs
    .readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && /^\d+$/.test(entry.name))
    .map((entry) => Number(entry.name))
    .sort((a, b) => b - a);
}

function findBroadcastRun(scriptName, chainId) {
  const scriptDir = path.join("broadcast", scriptName);
  const chainIds = chainId ? [Number(chainId)] : listNumericSubdirs(scriptDir);
  for (const candidateChainId of chainIds) {
    const broadcastPath = path.join(scriptDir, `${candidateChainId}`, "run-latest.json");
    if (fs.existsSync(broadcastPath)) {
      return { chainId: candidateChainId, path: broadcastPath, data: readJson(broadcastPath) };
    }
    const dryRunPath = path.join(scriptDir, `${candidateChainId}`, "dry-run", "run-latest.json");
    if (fs.existsSync(dryRunPath)) {
      return { chainId: candidateChainId, path: dryRunPath, data: readJson(dryRunPath) };
    }
  }
  return null;
}

function parseChainIdFromBroadcast(broadcast) {
  if (!broadcast?.data?.transactions?.length) return null;
  const tx = broadcast.data.transactions.find((item) => item?.transaction?.chainId);
  if (!tx?.transaction?.chainId) return null;
  return Number(BigInt(tx.transaction.chainId));
}

function findTransactionHash(transactions, predicate) {
  const match = transactions.find(predicate);
  return match ? match.hash : null;
}

function normalizeToLower(address) {
  return normalizeAddress(address, "address").toLowerCase();
}

function buildSelectors() {
  return {
    hooksFactoryRevolving: {
      deployMarket: "0xcad2a887",
      deployMarketAndHooks: "0xad4c77f5",
    },
    marketLens: {
      getMarketDataV2: "0x23af4bca",
      getMarketsDataV2: "0x74c3c3e9",
      getAllMarketsDataV2ForHooksTemplate: "0xf81c9b5c",
      getAggregatedAllMarketsDataV2ForHooksTemplate: "0xd6b73a70",
    },
    wildcatMarketRevolving: {
      commitmentFeeBips: "0x7b1fbd32",
      drawnAmount: "0x9a14f79d",
    },
    events: {
      marketDeployedTopic0:
        "0x6f8c7c94fc16393d1ebec38de9899ba8c6bd860a025aa60063b7cf4c40a16c09",
    },
  };
}

async function resolveChainId(args, hooksBroadcast, lensBroadcast) {
  if (args["chain-id"]) {
    return Number(args["chain-id"]);
  }
  const fromBroadcast =
    parseChainIdFromBroadcast(hooksBroadcast) || parseChainIdFromBroadcast(lensBroadcast);
  if (fromBroadcast) {
    return fromBroadcast;
  }
  const rpcUrl = args["rpc-url"] || process.env.RPC_URL;
  if (rpcUrl) {
    const chainId = execSync(`cast chain-id --rpc-url "${rpcUrl}"`, {
      stdio: ["ignore", "pipe", "pipe"],
      encoding: "utf8",
    }).trim();
    return Number(chainId);
  }
  throw new Error("Unable to resolve chain id; provide --chain-id or --rpc-url.");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  if (!network) {
    throw new Error("Missing --network (or DEPLOYMENTS_NETWORK).");
  }

  const deploymentsFile =
    args["deployments-file"] || path.join("deployments", network, "deployments.json");
  const outputPath = args.output || path.join("deployments", network, "rcf-v2-handoff.json");

  if (!fs.existsSync(deploymentsFile)) {
    throw new Error(`Deployments file not found: ${deploymentsFile}`);
  }
  const deployments = readJson(deploymentsFile);

  const addresses = {
    archController: resolveAddress(
      args,
      deployments,
      "arch-controller",
      "WildcatArchController",
      "archController"
    ),
    hooksFactoryLegacy: resolveAddress(
      args,
      deployments,
      "legacy-factory",
      "HooksFactory",
      "hooksFactoryLegacy"
    ),
    hooksFactoryRevolving: resolveAddress(
      args,
      deployments,
      "revolving-factory",
      "HooksFactoryRevolving",
      "hooksFactoryRevolving"
    ),
    marketLensLatest: resolveAddress(
      args,
      deployments,
      "market-lens",
      "MarketLens",
      "marketLensLatest"
    ),
    wildcatMarketRevolvingInitCodeStorage: resolveAddress(
      args,
      deployments,
      "revolving-market-initcode-storage",
      "WildcatMarketRevolving_initCodeStorage",
      "wildcatMarketRevolvingInitCodeStorage"
    ),
  };

  const hooksScriptName = args["hooks-script"] || "DeployHooksFactoryRevolving.sol";
  const lensScriptName = args["lens-script"] || "DeployMarketLens.sol";
  const chainIdHint = args["chain-id"] ? Number(args["chain-id"]) : networkNameToChainId(network);
  const hooksBroadcast = findBroadcastRun(hooksScriptName, chainIdHint);
  const lensBroadcast = findBroadcastRun(lensScriptName, chainIdHint);

  const chainId = await resolveChainId(args, hooksBroadcast, lensBroadcast);
  const chainNetwork = chainIdToNetworkName(chainId);

  const hooksTransactions = hooksBroadcast?.data?.transactions || [];
  const lensTransactions = lensBroadcast?.data?.transactions || [];
  const txHashes = {
    deployHooksFactoryRevolving: findTransactionHash(
      hooksTransactions,
      (tx) => tx.transactionType === "CREATE" && tx.contractName === "HooksFactoryRevolving"
    ),
    registerControllerFactory: findTransactionHash(
      hooksTransactions,
      (tx) =>
        tx.function === "registerControllerFactory(address)" &&
        tx.transaction &&
        tx.transaction.to &&
        normalizeToLower(tx.transaction.to) === normalizeToLower(addresses.archController)
    ),
    registerWithArchController: findTransactionHash(
      hooksTransactions,
      (tx) => tx.function === "registerWithArchController()"
    ),
    deployMarketLens: findTransactionHash(
      lensTransactions,
      (tx) => tx.transactionType === "CREATE" && tx.contractName === "MarketLens"
    ),
  };

  const selectors = buildSelectors();

  const handoff = {
    schemaVersion: HANDOFF_SCHEMA_VERSION,
    generatedAt: new Date().toISOString(),
    chain: {
      id: chainId,
      network: network,
      canonicalName: chainNetwork,
    },
    addresses,
    txHashes,
    routing: {
      defaultMarketType: "legacy",
      factoryByMarketType: {
        legacy: addresses.hooksFactoryLegacy,
        revolving: addresses.hooksFactoryRevolving,
      },
      marketTypeByFactory: {
        [addresses.hooksFactoryLegacy]: "legacy",
        [addresses.hooksFactoryRevolving]: "revolving",
      },
      latestLens: addresses.marketLensLatest,
    },
    abiSurface: {
      artifacts: {
        hooksFactoryLegacy: "src/IHooksFactory.sol:IHooksFactory",
        hooksFactoryRevolving: "src/IHooksFactoryRevolving.sol:IHooksFactoryRevolving",
        marketLens: "src/lens/MarketLens.sol:MarketLens",
        wildcatMarketRevolving: "src/interfaces/IWildcatMarketRevolving.sol:IWildcatMarketRevolving",
      },
      selectors,
      notes: [
        "Deployment event surface remains legacy MarketDeployed across both factories in this rollout.",
        "Revolving-only fields are exposed via WildcatMarketRevolving.commitmentFeeBips()/drawnAmount() and MarketLens V2 endpoints.",
      ],
    },
    sources: {
      deploymentsFile,
      hooksBroadcast: hooksBroadcast ? hooksBroadcast.path : null,
      lensBroadcast: lensBroadcast ? lensBroadcast.path : null,
      hooksScriptName,
      lensScriptName,
    },
  };

  writeJson(outputPath, handoff);
  console.log(`Handoff artifact written to ${outputPath}`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
