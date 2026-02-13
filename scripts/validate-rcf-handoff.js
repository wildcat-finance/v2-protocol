#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

function printUsage() {
  console.log(`Usage:
  node scripts/validate-rcf-handoff.js --input <path>

Example:
  node scripts/validate-rcf-handoff.js --input deployments/sepolia/rcf-v2-handoff.json
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

function fail(errors, message) {
  errors.push(message);
}

function isAddress(value) {
  return typeof value === "string" && /^0x[0-9a-fA-F]{40}$/.test(value);
}

function isTxHash(value) {
  return typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value);
}

function validate(input) {
  const errors = [];

  if (typeof input !== "object" || input === null) {
    fail(errors, "artifact must be an object");
    return errors;
  }

  if (input.schemaVersion !== "1.0.0") {
    fail(errors, "schemaVersion must be 1.0.0");
  }

  if (typeof input.generatedAt !== "string" || Number.isNaN(Date.parse(input.generatedAt))) {
    fail(errors, "generatedAt must be an ISO timestamp string");
  }

  if (!input.chain || typeof input.chain !== "object") {
    fail(errors, "chain is required");
  } else {
    if (!Number.isInteger(input.chain.id) || input.chain.id <= 0) {
      fail(errors, "chain.id must be a positive integer");
    }
    if (typeof input.chain.network !== "string" || input.chain.network.length === 0) {
      fail(errors, "chain.network must be a non-empty string");
    }
  }

  const addressFields = [
    "archController",
    "hooksFactoryLegacy",
    "hooksFactoryRevolving",
    "marketLensLatest",
    "wildcatMarketRevolvingInitCodeStorage",
  ];
  if (!input.addresses || typeof input.addresses !== "object") {
    fail(errors, "addresses is required");
  } else {
    for (const field of addressFields) {
      if (!isAddress(input.addresses[field])) {
        fail(errors, `addresses.${field} must be a valid address`);
      }
    }
  }

  const txHashFields = [
    "deployHooksFactoryRevolving",
    "registerControllerFactory",
    "registerWithArchController",
    "deployMarketLens",
  ];
  if (!input.txHashes || typeof input.txHashes !== "object") {
    fail(errors, "txHashes is required");
  } else {
    for (const field of txHashFields) {
      const value = input.txHashes[field];
      if (value !== null && !isTxHash(value)) {
        fail(errors, `txHashes.${field} must be null or a tx hash`);
      }
    }
  }

  if (!input.routing || typeof input.routing !== "object") {
    fail(errors, "routing is required");
  } else {
    if (input.routing.defaultMarketType !== "legacy") {
      fail(errors, "routing.defaultMarketType must be legacy");
    }
    if (
      !input.routing.factoryByMarketType ||
      !isAddress(input.routing.factoryByMarketType.legacy) ||
      !isAddress(input.routing.factoryByMarketType.revolving)
    ) {
      fail(errors, "routing.factoryByMarketType.{legacy,revolving} must be valid addresses");
    }
    if (!isAddress(input.routing.latestLens)) {
      fail(errors, "routing.latestLens must be a valid address");
    }
    if (
      !input.routing.marketTypeByFactory ||
      typeof input.routing.marketTypeByFactory !== "object"
    ) {
      fail(errors, "routing.marketTypeByFactory must be an object");
    } else {
      const values = Object.values(input.routing.marketTypeByFactory);
      for (const value of values) {
        if (value !== "legacy" && value !== "revolving") {
          fail(errors, "routing.marketTypeByFactory values must be legacy|revolving");
        }
      }
    }
  }

  if (!input.abiSurface || typeof input.abiSurface !== "object") {
    fail(errors, "abiSurface is required");
  } else {
    if (!input.abiSurface.selectors || typeof input.abiSurface.selectors !== "object") {
      fail(errors, "abiSurface.selectors is required");
    }
    if (!Array.isArray(input.abiSurface.notes)) {
      fail(errors, "abiSurface.notes must be an array");
    }
  }

  return errors;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const inputPath = args.input;
  if (!inputPath) {
    throw new Error("Missing --input");
  }
  const absolutePath = path.resolve(process.cwd(), inputPath);
  if (!fs.existsSync(absolutePath)) {
    throw new Error(`Input file not found: ${absolutePath}`);
  }

  const artifact = JSON.parse(fs.readFileSync(absolutePath, "utf8"));
  const errors = validate(artifact);
  if (errors.length > 0) {
    console.error("Invalid handoff artifact:");
    for (const error of errors) {
      console.error(`- ${error}`);
    }
    process.exit(1);
  }
  console.log(`Handoff artifact is valid: ${inputPath}`);
}

try {
  main();
} catch (error) {
  console.error(error.message || error);
  process.exit(1);
}
