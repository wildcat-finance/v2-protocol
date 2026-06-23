#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const INVENTORY_SCHEMA_VERSION = "1.0.0";
const INVENTORY_FILE_NAME = "factory-inventory.json";
const DEFAULT_MARKET_TYPES = ["legacy", "revolving"];

const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;
const BYTES32_REGEX = /^0x[a-fA-F0-9]{64}$/;

function printUsage() {
  console.log(`Usage:
  node scripts/factory-inventory.js validate --network <name> [--chain-id <id>] [--input <path>]
  node scripts/factory-inventory.js summary --network <name> [--input <path>]
  node scripts/factory-inventory.js upsert --network <name> --chain-id <id> --label <label>
    --market-type <type> --address <address> --canonical <true|false>
    --indexed <true|false> --registered <true|false> [--start-block <block>]
    [--deployment-key <key>] [--init-code-storage <address>] [--init-code-hash <bytes32>]
    [--input <path>] [--output <path>] [--create] [--preserve-start-block]

Defaults:
  --input deployments/<network>/factory-inventory.json
  --output same as --input
`);
}

function parseArgs(argv) {
  if (argv.includes("--help") || argv.includes("-h")) {
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

function networkNameToChainId(networkName) {
  if (networkName === "mainnet") return 1;
  if (networkName === "sepolia") return 11155111;
  return null;
}

function inventoryPathForNetwork(network, deploymentsDir = "deployments") {
  if (!network) {
    throw new Error("Missing network.");
  }
  return path.join(deploymentsDir, network, INVENTORY_FILE_NAME);
}

function ensureDirForFile(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  ensureDirForFile(filePath);
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function readInventory(filePath) {
  return readJson(filePath);
}

function readInventoryOrCreate(filePath, { network, chainId, marketTypes, create }) {
  if (fs.existsSync(filePath)) {
    return readInventory(filePath);
  }
  if (!create) {
    throw new Error(`Factory inventory not found: ${filePath}`);
  }
  return createInventory({ network, chainId, marketTypes });
}

function writeInventory(filePath, inventory) {
  const result = validateInventory(inventory);
  if (!result.ok) {
    throw new Error(`Invalid factory inventory:\n${result.errors.map((error) => `- ${error}`).join("\n")}`);
  }
  writeJson(filePath, inventory);
}

function createInventory({ network, chainId, marketTypes = DEFAULT_MARKET_TYPES } = {}) {
  if (!network) {
    throw new Error("Missing network.");
  }
  const resolvedChainId = chainId ?? networkNameToChainId(network);
  if (!Number.isInteger(Number(resolvedChainId))) {
    throw new Error(`Missing chain id for network ${network}.`);
  }
  return {
    schemaVersion: INVENTORY_SCHEMA_VERSION,
    network,
    chainId: Number(resolvedChainId),
    marketTypes: [...marketTypes],
    hooksFactories: [],
  };
}

function isAddress(value) {
  return typeof value === "string" && ADDRESS_REGEX.test(value);
}

function isBytes32(value) {
  return typeof value === "string" && BYTES32_REGEX.test(value);
}

function addressKey(address) {
  if (!isAddress(address)) {
    throw new Error(`Invalid address: ${address}`);
  }
  return address.toLowerCase();
}

function removeUndefinedFields(value) {
  return Object.fromEntries(Object.entries(value).filter(([, fieldValue]) => fieldValue !== undefined));
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function hasOwn(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key);
}

function requireString(errors, entry, pathName) {
  const value = entry[pathName];
  if (typeof value !== "string" || value.trim() === "") {
    errors.push(`${pathName} must be a nonempty string`);
  }
}

function validateOptionalString(errors, entry, pathName) {
  if (hasOwn(entry, pathName) && typeof entry[pathName] !== "string") {
    errors.push(`${pathName} must be a string when present`);
  }
}

function validateFactoryEntry(entry, index, marketTypes) {
  const errors = [];
  const prefix = `hooksFactories[${index}]`;

  if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
    return [`${prefix} must be an object`];
  }

  requireString(errors, entry, "label");
  requireString(errors, entry, "marketType");

  if (!isAddress(entry.address)) {
    errors.push(`${prefix}.address must be a valid EVM address`);
  }

  if (!Number.isSafeInteger(entry.startBlock) || entry.startBlock < 0) {
    errors.push(`${prefix}.startBlock must be a nonnegative safe integer`);
  }

  for (const field of ["canonical", "indexed", "registered"]) {
    if (typeof entry[field] !== "boolean") {
      errors.push(`${prefix}.${field} must be a boolean`);
    }
  }

  if (typeof entry.marketType === "string" && !marketTypes.has(entry.marketType)) {
    errors.push(`${prefix}.marketType is not listed in top-level marketTypes`);
  }

  if (entry.canonical === true && entry.registered !== true) {
    errors.push(`${prefix} is canonical but not registered`);
  }

  if (entry.canonical === true && entry.indexed !== true) {
    errors.push(`${prefix} is canonical but not indexed`);
  }

  if (entry.indexed === true && (!Number.isSafeInteger(entry.startBlock) || entry.startBlock === 0)) {
    errors.push(`${prefix} is indexed but has no nonzero startBlock`);
  }

  validateOptionalString(errors, entry, "deploymentKey");
  validateOptionalString(errors, entry, "notes");

  if (hasOwn(entry, "deployTxHash") && !isBytes32(entry.deployTxHash)) {
    errors.push(`${prefix}.deployTxHash must be bytes32 when present`);
  }

  if (hasOwn(entry, "registerTxHash") && !isBytes32(entry.registerTxHash)) {
    errors.push(`${prefix}.registerTxHash must be bytes32 when present`);
  }

  if (hasOwn(entry, "initCodeHash") && !isBytes32(entry.initCodeHash)) {
    errors.push(`${prefix}.initCodeHash must be bytes32 when present`);
  }

  if (hasOwn(entry, "initCodeStorage") && !isAddress(entry.initCodeStorage)) {
    errors.push(`${prefix}.initCodeStorage must be a valid EVM address when present`);
  }

  return errors.map((error) => (error.startsWith(prefix) ? error : `${prefix}.${error}`));
}

function validateInventory(inventory, options = {}) {
  const errors = [];
  const warnings = [];

  if (!inventory || typeof inventory !== "object" || Array.isArray(inventory)) {
    return { ok: false, errors: ["inventory must be an object"], warnings };
  }

  if (inventory.schemaVersion !== INVENTORY_SCHEMA_VERSION) {
    errors.push(
      `schemaVersion must be ${INVENTORY_SCHEMA_VERSION}; got ${inventory.schemaVersion || "<missing>"}`
    );
  }

  if (typeof inventory.network !== "string" || inventory.network.trim() === "") {
    errors.push("network must be a nonempty string");
  }

  if (options.network && inventory.network !== options.network) {
    errors.push(`network mismatch: expected ${options.network}, got ${inventory.network}`);
  }

  if (!Number.isSafeInteger(inventory.chainId) || inventory.chainId <= 0) {
    errors.push("chainId must be a positive safe integer");
  }

  const expectedChainId =
    options.chainId !== undefined ? Number(options.chainId) : networkNameToChainId(inventory.network);
  if (expectedChainId && inventory.chainId !== expectedChainId) {
    errors.push(`chainId mismatch: expected ${expectedChainId}, got ${inventory.chainId}`);
  }

  if (!Array.isArray(inventory.marketTypes) || inventory.marketTypes.length === 0) {
    errors.push("marketTypes must be a nonempty array");
  }

  const marketTypes = new Set();
  if (Array.isArray(inventory.marketTypes)) {
    for (const [index, marketType] of inventory.marketTypes.entries()) {
      if (typeof marketType !== "string" || marketType.trim() === "") {
        errors.push(`marketTypes[${index}] must be a nonempty string`);
      } else if (marketTypes.has(marketType)) {
        errors.push(`marketTypes contains duplicate value ${marketType}`);
      } else {
        marketTypes.add(marketType);
      }
    }
  }

  if (!Array.isArray(inventory.hooksFactories)) {
    errors.push("hooksFactories must be an array");
    return { ok: false, errors, warnings };
  }

  const labels = new Set();
  const addresses = new Map();
  const canonicalByMarketType = new Map();

  for (const [index, entry] of inventory.hooksFactories.entries()) {
    errors.push(...validateFactoryEntry(entry, index, marketTypes));

    if (!entry || typeof entry !== "object") {
      continue;
    }

    if (typeof entry.label === "string") {
      if (labels.has(entry.label)) {
        errors.push(`hooksFactories[${index}].label duplicates ${entry.label}`);
      }
      labels.add(entry.label);
    }

    if (isAddress(entry.address)) {
      const key = entry.address.toLowerCase();
      if (addresses.has(key)) {
        errors.push(
          `hooksFactories[${index}].address duplicates hooksFactories[${addresses.get(key)}].address`
        );
      }
      addresses.set(key, index);
    }

    if (entry.canonical === true && typeof entry.marketType === "string") {
      const existing = canonicalByMarketType.get(entry.marketType);
      if (existing !== undefined) {
        errors.push(
          `marketType ${entry.marketType} has multiple canonical factories: hooksFactories[${existing}] and hooksFactories[${index}]`
        );
      }
      canonicalByMarketType.set(entry.marketType, index);
    }

    if (inventory.network === "mainnet" && entry.indexed === false) {
      warnings.push(
        `hooksFactories[${index}] is not indexed on mainnet; confirm it cannot have live markets or user funds`
      );
    }
  }

  return { ok: errors.length === 0, errors, warnings };
}

function assertValidInventory(inventory, options = {}) {
  const result = validateInventory(inventory, options);
  if (!result.ok) {
    throw new Error(`Invalid factory inventory:\n${result.errors.map((error) => `- ${error}`).join("\n")}`);
  }
  return inventory;
}

function upsertFactory(inventory, factoryEntry) {
  const next = cloneJson(inventory);
  const incoming = removeUndefinedFields({ ...factoryEntry });
  const incomingAddressKey = addressKey(incoming.address);

  const labelIndex = next.hooksFactories.findIndex((entry) => entry.label === incoming.label);
  const addressIndex = next.hooksFactories.findIndex(
    (entry) => isAddress(entry.address) && entry.address.toLowerCase() === incomingAddressKey
  );

  if (labelIndex !== -1 && addressIndex !== -1 && labelIndex !== addressIndex) {
    throw new Error(
      `Cannot upsert factory ${incoming.label}: label and address match different inventory entries`
    );
  }

  const replaceIndex = labelIndex !== -1 ? labelIndex : addressIndex;
  const merged = replaceIndex === -1 ? incoming : { ...next.hooksFactories[replaceIndex], ...incoming };

  if (merged.canonical === true) {
    for (const entry of next.hooksFactories) {
      if (entry.marketType === merged.marketType) {
        entry.canonical = false;
      }
    }
  }

  if (replaceIndex === -1) {
    next.hooksFactories.push(merged);
  } else {
    next.hooksFactories[replaceIndex] = merged;
  }

  return assertValidInventory(next);
}

function findFactoryEntry(inventory, factoryEntry) {
  const incomingAddressKey = factoryEntry.address ? addressKey(factoryEntry.address) : null;
  return inventory.hooksFactories.find(
    (entry) =>
      entry.label === factoryEntry.label ||
      (incomingAddressKey && isAddress(entry.address) && entry.address.toLowerCase() === incomingAddressKey)
  );
}

function getCanonicalFactory(inventory, marketType) {
  return inventory.hooksFactories.find(
    (entry) => entry.marketType === marketType && entry.canonical === true
  );
}

function getIndexedFactories(inventory, marketType) {
  return inventory.hooksFactories.filter(
    (entry) => entry.indexed === true && (!marketType || entry.marketType === marketType)
  );
}

function resolveInputPath(args) {
  if (args.input) {
    return args.input;
  }
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  if (!network) {
    throw new Error("Missing --network, DEPLOYMENTS_NETWORK, or --input.");
  }
  return inventoryPathForNetwork(network);
}

function resolveOutputPath(args) {
  return args.output || resolveInputPath(args);
}

function parseBoolean(value, fieldName) {
  if (typeof value === "boolean") {
    return value;
  }
  if (value === "true" || value === "1") {
    return true;
  }
  if (value === "false" || value === "0") {
    return false;
  }
  throw new Error(`Invalid boolean for --${fieldName}: ${value}`);
}

function parseSafeInteger(value, fieldName) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error(`Invalid integer for --${fieldName}: ${value}`);
  }
  return parsed;
}

function parseList(value) {
  if (!value) {
    return DEFAULT_MARKET_TYPES;
  }
  return value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function requireArg(args, key) {
  const value = args[key];
  if (value === undefined || value === true || value === "") {
    throw new Error(`Missing --${key}`);
  }
  return value;
}

function optionalArg(args, key) {
  const value = args[key];
  if (value === undefined || value === true || value === "") {
    return undefined;
  }
  return value;
}

function buildFactoryEntryFromArgs(args) {
  return removeUndefinedFields({
    label: requireArg(args, "label"),
    marketType: requireArg(args, "market-type"),
    address: requireArg(args, "address"),
    startBlock:
      args["start-block"] === undefined ? undefined : parseSafeInteger(args["start-block"], "start-block"),
    canonical: parseBoolean(requireArg(args, "canonical"), "canonical"),
    indexed: parseBoolean(requireArg(args, "indexed"), "indexed"),
    registered: parseBoolean(requireArg(args, "registered"), "registered"),
    deploymentKey: optionalArg(args, "deployment-key"),
    deployTxHash: optionalArg(args, "deploy-tx-hash"),
    registerTxHash: optionalArg(args, "register-tx-hash"),
    initCodeStorage: optionalArg(args, "init-code-storage"),
    initCodeHash: optionalArg(args, "init-code-hash"),
    notes: optionalArg(args, "notes"),
  });
}

function runValidate(args) {
  const inputPath = resolveInputPath(args);
  const inventory = readInventory(inputPath);
  const result = validateInventory(inventory, {
    network: args.network,
    chainId: args["chain-id"] ? Number(args["chain-id"]) : undefined,
  });

  for (const warning of result.warnings) {
    console.warn(`Warning: ${warning}`);
  }

  if (!result.ok) {
    for (const error of result.errors) {
      console.error(`Error: ${error}`);
    }
    process.exit(1);
  }

  console.log(`Inventory valid: ${inputPath}`);
}

function runSummary(args) {
  const inputPath = resolveInputPath(args);
  const inventory = assertValidInventory(readInventory(inputPath), {
    network: args.network,
    chainId: args["chain-id"] ? Number(args["chain-id"]) : undefined,
  });

  console.log(`${inventory.network} (${inventory.chainId})`);
  for (const marketType of inventory.marketTypes) {
    const canonical = getCanonicalFactory(inventory, marketType);
    const indexed = getIndexedFactories(inventory, marketType);
    console.log(
      `- ${marketType}: canonical=${canonical ? canonical.label : "<none>"} indexed=${indexed.length}`
    );
  }
}

function runUpsert(args) {
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  const chainId = args["chain-id"] ? Number(args["chain-id"]) : networkNameToChainId(network);
  if (!network) {
    throw new Error("Missing --network or DEPLOYMENTS_NETWORK.");
  }
  if (!Number.isSafeInteger(chainId) || chainId <= 0) {
    throw new Error("Missing valid --chain-id.");
  }

  const inputPath = resolveInputPath(args);
  const outputPath = resolveOutputPath(args);
  const inventory = assertValidInventory(
    readInventoryOrCreate(inputPath, {
      network,
      chainId,
      marketTypes: parseList(args["market-types"]),
      create: args.create === true,
    }),
    { network, chainId }
  );

  const factoryEntry = buildFactoryEntryFromArgs(args);
  const existing = findFactoryEntry(inventory, factoryEntry);
  if (args["preserve-start-block"] === true && existing?.startBlock) {
    delete factoryEntry.startBlock;
  }

  const next = assertValidInventory(upsertFactory(inventory, factoryEntry), { network, chainId });
  writeInventory(outputPath, next);
  console.log(`Inventory updated: ${outputPath}`);
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv.includes("--help") || argv.includes("-h")) {
    printUsage();
    process.exit(0);
  }

  const command = argv[0].startsWith("--") ? "validate" : argv[0];
  const args = parseArgs(argv[0].startsWith("--") ? argv : argv.slice(1));

  if (command === "validate") {
    runValidate(args);
    return;
  }
  if (command === "summary") {
    runSummary(args);
    return;
  }
  if (command === "upsert") {
    runUpsert(args);
    return;
  }

  throw new Error(`Unknown command: ${command}`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

module.exports = {
  INVENTORY_FILE_NAME,
  INVENTORY_SCHEMA_VERSION,
  DEFAULT_MARKET_TYPES,
  createInventory,
  getCanonicalFactory,
  getIndexedFactories,
  inventoryPathForNetwork,
  readInventory,
  readInventoryOrCreate,
  readJson,
  upsertFactory,
  validateInventory,
  writeInventory,
  writeJson,
};
