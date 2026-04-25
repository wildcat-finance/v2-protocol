#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const {
  getCanonicalFactory,
  getIndexedFactories,
  inventoryPathForNetwork,
  readInventory,
  readJson,
  validateInventory,
} = require("./factory-inventory");

const DEFAULT_SUBGRAPH_NETWORKS_PATH = path.join("..", "subgraph", "networks.json");
const DEFAULT_SDK_CONSTANTS_PATH = path.join("..", "wildcat.ts", "src", "constants.ts");

const CHAIN_IDS_BY_NETWORK = {
  mainnet: 1,
  sepolia: 11155111,
  "plasma-testnet": 9746,
  "plasma-mainnet": 9745,
};

const SDK_DEPLOYMENT_NAMES_BY_MARKET_TYPE = {
  legacy: "HooksFactory",
  revolving: "HooksFactoryRevolving",
};

function printUsage() {
  console.log(`Usage:
  node scripts/validate-factory-inventory.js --network <name>
    [--inventory <path>]
    [--subgraph-networks <path>]
    [--sdk-constants <path>]
    [--rpc-url <url>] [--cast-bin <path-or-name>]

Defaults:
  --inventory         deployments/<network>/factory-inventory.json
  --subgraph-networks ../subgraph/networks.json
  --sdk-constants     ../wildcat.ts/src/constants.ts
  --rpc-url           omitted; RPC registration checks are opt-in
  --cast-bin          cast
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

function optionalStringArg(args, key) {
  if (args[key] === true) {
    throw new Error(`Missing value for --${key}`);
  }
  return args[key];
}

function addressKey(value) {
  if (typeof value !== "string" || !/^0x[a-fA-F0-9]{40}$/.test(value)) {
    throw new Error(`Invalid address: ${value}`);
  }
  return value.toLowerCase();
}

function runCast(castBin, args) {
  try {
    return execFileSync(castBin, args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    const stderr = error.stderr ? error.stderr.toString().trim() : "";
    throw new Error(`cast ${args.join(" ")} failed${stderr ? `: ${stderr}` : ""}`);
  }
}

function castCall(castBin, rpcUrl, target, signature, callArgs = []) {
  return runCast(castBin, ["call", target, signature, ...callArgs, "--rpc-url", rpcUrl]);
}

function castBool(castBin, rpcUrl, target, signature, callArgs = []) {
  const result = castCall(castBin, rpcUrl, target, signature, callArgs);
  if (result === "true") return true;
  if (result === "false") return false;
  throw new Error(`Unexpected bool result for ${signature}: ${result}`);
}

function validateRpcChainId(castBin, rpcUrl, chainId, errors) {
  const rpcChainId = Number(runCast(castBin, ["chain-id", "--rpc-url", rpcUrl]));
  if (rpcChainId !== chainId) {
    errors.push(`RPC chain id mismatch: expected ${chainId}, got ${rpcChainId}`);
  }
}

function getNetworkConfig(subgraphNetworks, network) {
  const networkConfig = subgraphNetworks[network];
  if (!networkConfig) {
    throw new Error(`Missing subgraph network config for ${network}`);
  }
  if (!Array.isArray(networkConfig.hooksFactories)) {
    throw new Error(`Subgraph network ${network} is missing hooksFactories[]`);
  }
  return networkConfig;
}

function extractSdkDeploymentBlock(source, chainId) {
  const marker = `[SupportedChainId.${chainId === 1 ? "Mainnet" : chainId === 11155111 ? "Sepolia" : chainId === 9746 ? "PlasmaTestnet" : "PlasmaMainnet"}]`;
  const markerIndex = source.indexOf(marker);
  if (markerIndex === -1) {
    throw new Error(`SDK constants do not contain deployment block for chain ${chainId}`);
  }

  const blockStart = source.indexOf("{", markerIndex);
  if (blockStart === -1) {
    throw new Error(`Unable to find SDK deployment block start for chain ${chainId}`);
  }

  let depth = 0;
  for (let i = blockStart; i < source.length; i += 1) {
    const char = source[i];
    if (char === "{") depth += 1;
    if (char === "}") depth -= 1;
    if (depth === 0) {
      return source.slice(blockStart + 1, i);
    }
  }
  throw new Error(`Unable to find SDK deployment block end for chain ${chainId}`);
}

function parseSdkDeployments(constantsPath, chainId) {
  const source = fs.readFileSync(constantsPath, "utf8");
  const block = extractSdkDeploymentBlock(source, chainId);
  const deployments = {};
  const entryRegex = /([A-Za-z0-9_]+):\s*"([^"]+)"/g;
  let match;
  while ((match = entryRegex.exec(block)) !== null) {
    deployments[match[1]] = match[2];
  }
  return deployments;
}

function validateInventorySchema(inventory, network, chainId, errors, warnings) {
  const result = validateInventory(inventory, { network, chainId });
  errors.push(...result.errors);
  warnings.push(...result.warnings);
}

function validateSubgraphConfig(inventory, networkConfig, errors) {
  const subgraphFactoriesByAddress = new Map();
  const subgraphFactoriesByName = new Map();

  for (const [index, hooksFactory] of networkConfig.hooksFactories.entries()) {
    if (hooksFactory.indexed === false) {
      continue;
    }
    if (!hooksFactory.name) {
      errors.push(`subgraph hooksFactories[${index}] is missing name`);
      continue;
    }
    if (!hooksFactory.marketType) {
      errors.push(`subgraph hooksFactories[${index}] is missing marketType`);
    }
    if (!hooksFactory.address) {
      errors.push(`subgraph hooksFactories[${index}] is missing address`);
      continue;
    }
    const address = addressKey(hooksFactory.address);
    subgraphFactoriesByAddress.set(address, hooksFactory);
    subgraphFactoriesByName.set(hooksFactory.name, hooksFactory);
  }

  for (const inventoryFactory of getIndexedFactories(inventory)) {
    const subgraphFactory = subgraphFactoriesByAddress.get(addressKey(inventoryFactory.address));
    if (!subgraphFactory) {
      errors.push(
        `indexed inventory factory ${inventoryFactory.label} (${inventoryFactory.address}) is missing from subgraph hooksFactories[]`
      );
      continue;
    }
    if (subgraphFactory.marketType !== inventoryFactory.marketType) {
      errors.push(
        `subgraph marketType mismatch for ${inventoryFactory.label}: expected ${inventoryFactory.marketType}, got ${subgraphFactory.marketType}`
      );
    }
    if (Number(subgraphFactory.startBlock) !== inventoryFactory.startBlock) {
      errors.push(
        `subgraph startBlock mismatch for ${inventoryFactory.label}: expected ${inventoryFactory.startBlock}, got ${subgraphFactory.startBlock}`
      );
    }
  }

  for (const subgraphFactory of subgraphFactoriesByAddress.values()) {
    const inventoryFactory = inventory.hooksFactories.find(
      (entry) => addressKey(entry.address) === addressKey(subgraphFactory.address)
    );
    if (!inventoryFactory) {
      errors.push(
        `subgraph indexed factory ${subgraphFactory.name} (${subgraphFactory.address}) is missing from inventory`
      );
    } else if (inventoryFactory.indexed !== true) {
      errors.push(
        `subgraph indexed factory ${subgraphFactory.name} (${subgraphFactory.address}) is not indexed in inventory`
      );
    }
  }

  for (const [marketType, deploymentName] of Object.entries(SDK_DEPLOYMENT_NAMES_BY_MARKET_TYPE)) {
    const canonical = getCanonicalFactory(inventory, marketType);
    if (!canonical) {
      continue;
    }
    const subgraphSingleton = networkConfig.contracts?.[deploymentName];
    if (subgraphSingleton && addressKey(subgraphSingleton.address) !== addressKey(canonical.address)) {
      errors.push(
        `subgraph contracts.${deploymentName} does not match canonical ${marketType}: expected ${canonical.address}, got ${subgraphSingleton.address}`
      );
    }
    const namedFactory = subgraphFactoriesByName.get(deploymentName);
    if (namedFactory && addressKey(namedFactory.address) !== addressKey(canonical.address)) {
      errors.push(
        `subgraph hooksFactories name ${deploymentName} does not match canonical ${marketType}: expected ${canonical.address}, got ${namedFactory.address}`
      );
    }
  }
}

function validateSdkConstants(inventory, sdkDeployments, errors) {
  for (const [marketType, deploymentName] of Object.entries(SDK_DEPLOYMENT_NAMES_BY_MARKET_TYPE)) {
    const canonical = getCanonicalFactory(inventory, marketType);
    if (!canonical) {
      continue;
    }
    const sdkAddress = sdkDeployments[deploymentName];
    if (!sdkAddress) {
      errors.push(`SDK constants missing ${deploymentName} for canonical ${marketType} factory`);
      continue;
    }
    if (addressKey(sdkAddress) !== addressKey(canonical.address)) {
      errors.push(
        `SDK ${deploymentName} mismatch for canonical ${marketType}: expected ${canonical.address}, got ${sdkAddress}`
      );
    }
  }
}

function validateCoreDeployments(inventory, deploymentsJson, errors) {
  for (const [marketType, deploymentName] of Object.entries(SDK_DEPLOYMENT_NAMES_BY_MARKET_TYPE)) {
    const canonical = getCanonicalFactory(inventory, marketType);
    if (!canonical) {
      continue;
    }
    const deploymentAddress = deploymentsJson[deploymentName];
    if (!deploymentAddress) {
      errors.push(`deployments.json missing ${deploymentName} for canonical ${marketType} factory`);
      continue;
    }
    if (addressKey(deploymentAddress) !== addressKey(canonical.address)) {
      errors.push(
        `deployments.json ${deploymentName} mismatch for canonical ${marketType}: expected ${canonical.address}, got ${deploymentAddress}`
      );
    }
  }
}

function validateRpcRegistration(inventory, deploymentsJson, rpcUrl, castBin, chainId, errors) {
  validateRpcChainId(castBin, rpcUrl, chainId, errors);

  const archController = deploymentsJson.WildcatArchController;
  if (!archController) {
    errors.push("deployments.json missing WildcatArchController for RPC registration validation");
    return;
  }

  for (const inventoryFactory of inventory.hooksFactories) {
    const isRegisteredControllerFactory = castBool(
      castBin,
      rpcUrl,
      archController,
      "isRegisteredControllerFactory(address)(bool)",
      [inventoryFactory.address]
    );
    const isRegisteredController = castBool(
      castBin,
      rpcUrl,
      archController,
      "isRegisteredController(address)(bool)",
      [inventoryFactory.address]
    );

    const expectedRegistered = inventoryFactory.registered === true;
    if (
      isRegisteredControllerFactory !== expectedRegistered ||
      isRegisteredController !== expectedRegistered
    ) {
      errors.push(
        `RPC registration mismatch for ${inventoryFactory.label} (${inventoryFactory.address}): expected registered=${expectedRegistered}, ` +
          `isRegisteredControllerFactory=${isRegisteredControllerFactory}, isRegisteredController=${isRegisteredController}`
      );
    }
  }
}

function run() {
  const args = parseArgs(process.argv.slice(2));
  const network = optionalStringArg(args, "network") || process.env.DEPLOYMENTS_NETWORK;
  if (!network) {
    throw new Error("Missing --network or DEPLOYMENTS_NETWORK");
  }
  const chainId = CHAIN_IDS_BY_NETWORK[network];
  if (!chainId) {
    throw new Error(`Unsupported network for offline validation: ${network}`);
  }

  const inventoryPath = optionalStringArg(args, "inventory") || inventoryPathForNetwork(network);
  const deploymentsPath =
    optionalStringArg(args, "deployments") || path.join("deployments", network, "deployments.json");
  const subgraphNetworksPath =
    optionalStringArg(args, "subgraph-networks") || DEFAULT_SUBGRAPH_NETWORKS_PATH;
  const sdkConstantsPath = optionalStringArg(args, "sdk-constants") || DEFAULT_SDK_CONSTANTS_PATH;
  const rpcUrl = optionalStringArg(args, "rpc-url") || process.env.RPC_URL;
  const castBin = optionalStringArg(args, "cast-bin") || "cast";

  const inventory = readInventory(inventoryPath);
  const deploymentsJson = readJson(deploymentsPath);
  const subgraphNetworks = readJson(subgraphNetworksPath);
  const subgraphNetworkConfig = getNetworkConfig(subgraphNetworks, network);
  const sdkDeployments = parseSdkDeployments(sdkConstantsPath, chainId);

  const errors = [];
  const warnings = [];

  validateInventorySchema(inventory, network, chainId, errors, warnings);
  validateSubgraphConfig(inventory, subgraphNetworkConfig, errors);
  validateCoreDeployments(inventory, deploymentsJson, errors);
  validateSdkConstants(inventory, sdkDeployments, errors);
  if (rpcUrl) {
    validateRpcRegistration(inventory, deploymentsJson, rpcUrl, castBin, chainId, errors);
  }

  for (const warning of warnings) {
    console.warn(`Warning: ${warning}`);
  }

  if (errors.length > 0) {
    for (const error of errors) {
      console.error(`Error: ${error}`);
    }
    process.exit(1);
  }

  console.log(`Factory inventory offline validation passed for ${network}`);
  console.log(`Inventory: ${inventoryPath}`);
  console.log(`Subgraph networks: ${subgraphNetworksPath}`);
  console.log(`SDK constants: ${sdkConstantsPath}`);
  if (rpcUrl) {
    console.log(`RPC registration checks: enabled`);
  } else {
    console.log(`RPC registration checks: skipped`);
  }
}

if (require.main === module) {
  try {
    run();
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}
