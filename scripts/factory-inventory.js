#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const LEGACY_INVENTORY_SCHEMA_VERSION = "1.0.0";
const INVENTORY_SCHEMA_VERSION = "1.1.0";
const INVENTORY_FILE_NAME = "factory-inventory.json";
const DEFAULT_MARKET_TYPES = ["legacy", "revolving"];
const LIFECYCLES = new Set(["canonical", "live", "retired"]);
const AUTHORITY_HELPER_FORWARD_SIGNATURE =
  "executeProtocolAction(address,bytes)";

const HOOK_FACTORY_FIELDS = new Set([
  "label",
  "marketType",
  "address",
  "startBlock",
  "canonical",
  "lifecycle",
  "indexed",
  "registered",
  "deploymentKey",
  "deployTxHash",
  "registerTxHash",
  "wrapperFactory",
  "initCodeStorage",
  "initCodeHash",
  "notes",
]);
const WRAPPER_FACTORY_FIELDS = new Set([
  "label",
  "address",
  "startBlock",
  "lifecycle",
  "indexed",
  "deployTxHash",
  "v1Factory",
  "notes",
]);

const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;
const BYTES32_REGEX = /^0x[a-fA-F0-9]{64}$/;
const SAFE_DEPLOYMENT_KEY_REGEX =
  /^[A-Za-z][A-Za-z0-9]*(?:(?::|_|-)[A-Za-z0-9-]+)*$/;
const RAW_TIMESTAMP_LABEL_REGEX = /(?:^|[_-])\d{8}-\d{6}$/;
const GET_REGISTERED_CONTROLLER_FACTORIES_SELECTOR = "0x6e0fb58d";
const GET_REGISTERED_CONTROLLERS_SELECTOR = "0xdb316dbc";
const V1_FACTORY_SELECTOR = "0x8083f7bb";
const PUBLIC_RPC_URLS = {
  mainnet: "https://ethereum-rpc.publicnode.com",
  sepolia: "https://ethereum-sepolia-rpc.publicnode.com",
};

function printUsage() {
  console.log(`Usage:
  node scripts/factory-inventory.js validate --network <name> [--chain-id <id>] [--input <path>]
  node scripts/factory-inventory.js summary --network <name> [--input <path>]
  node scripts/factory-inventory.js migrate --input <path> [--output <path>]
  node scripts/factory-inventory.js upsert --network <name> --chain-id <id> --label <label>
    --market-type <type> --address <address> --canonical <true|false>
    --indexed <true|false> --registered <true|false> [--start-block <block>]
    [--lifecycle <canonical|live|retired>]
    [--deployment-key <key>] [--wrapper-factory <address>] [--init-code-storage <address>]
    [--init-code-hash <bytes32>]
    [--input <path>] [--output <path>] [--create] [--preserve-start-block]
  node scripts/factory-inventory.js upsert-wrapper --network <name> --chain-id <id>
    --label <label> --address <address> --lifecycle <canonical|live|retired>
    --indexed <true|false> --v1-factory <address|null> [--start-block <block>]
    [--deploy-tx-hash <bytes32>] [--notes <text>] [--input <path>] [--output <path>]
  node scripts/factory-inventory.js lint --network <name> [--input <path>]
    [--deployments <path>] [--handoff <path>] [--allowlist <path>]
  node scripts/factory-inventory.js reconcile --network <name> [--rpc-url <url>]
    [--input <path>] [--deployments <path>] [--handoff <path>] [--output <path>]
  node scripts/factory-inventory.js deactivation-targets --network <name>
    [--input <path>] [--exclude <address,address>]
  node scripts/factory-inventory.js retirement-entries --network <name>
    --expected-executor <address> [--input <path>] [--deployments <path>]
  node scripts/factory-inventory.js validate-activation-plan --network <name>
    --plan <path>
  node scripts/factory-inventory.js validate-retirement-plan --network <name>
    --plan <path> [--input <path>] [--deployments <path>]
  node scripts/factory-inventory.js apply-run --network <name> --run-state <path>
    [--plan <path>] [--pending-directory <path>] [--rpc-url <url>]
    [--input <path>] [--deployments <path>]
  node scripts/factory-inventory.js apply-retirement --network <name> --run-state <path>
    [--plan <path>] [--rpc-url <url>] [--input <path>] [--deployments <path>]

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

function writeJsonAtomic(filePath, value) {
  ensureDirForFile(filePath);
  const temporaryPath = `${filePath}.${process.pid}.tmp`;
  fs.writeFileSync(
    temporaryPath,
    `${JSON.stringify(value, null, 2)}\n`,
    "utf8"
  );
  fs.renameSync(temporaryPath, filePath);
}

function readInventory(filePath) {
  return readJson(filePath);
}

function readInventoryOrCreate(
  filePath,
  { network, chainId, marketTypes, create }
) {
  if (fs.existsSync(filePath)) {
    return readInventory(filePath);
  }
  if (!create) {
    throw new Error(`Factory inventory not found: ${filePath}`);
  }
  return createInventory({ network, chainId, marketTypes });
}

function readCommittedInventory(filePath) {
  let repoRoot;
  try {
    repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], {
      cwd: process.cwd(),
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch (_error) {
    return null;
  }

  const absolutePath = path.resolve(filePath);
  const relativePath = path.relative(repoRoot, absolutePath);
  if (relativePath.startsWith("..") || path.isAbsolute(relativePath)) {
    return null;
  }

  try {
    const source = execFileSync(
      "git",
      ["show", `HEAD:${relativePath.split(path.sep).join("/")}`],
      {
        cwd: repoRoot,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }
    );
    return JSON.parse(source);
  } catch (_error) {
    return null;
  }
}

function validateAppendOnly(inventory, previousInventory) {
  const errors = [];
  if (
    inventory.schemaVersion !== INVENTORY_SCHEMA_VERSION ||
    previousInventory?.schemaVersion !== INVENTORY_SCHEMA_VERSION
  ) {
    return errors;
  }

  if (inventory.recordCount < previousInventory.recordCount) {
    errors.push(
      `recordCount must not decrease from committed value ${previousInventory.recordCount}; got ${inventory.recordCount}`
    );
  }

  for (const collectionName of ["hooksFactories", "wrapperFactories"]) {
    const currentEntries = Array.isArray(inventory[collectionName])
      ? inventory[collectionName]
      : [];
    for (const previousEntry of previousInventory[collectionName] || []) {
      const currentEntry = currentEntries.find(
        (entry) =>
          isAddress(entry.address) &&
          addressKey(entry.address) === addressKey(previousEntry.address)
      );
      if (!currentEntry) {
        errors.push(
          `${collectionName} deleted committed record ${previousEntry.label} (${previousEntry.address})`
        );
      } else if (currentEntry.label !== previousEntry.label) {
        errors.push(
          `${collectionName} changed committed label for ${previousEntry.address}: expected ${previousEntry.label}, got ${currentEntry.label}`
        );
      }
    }
  }
  return errors;
}

function validateInventoryFile(inventory, filePath, options = {}) {
  const result = validateInventory(inventory, options);
  const previousInventory = readCommittedInventory(filePath);
  result.errors.push(...validateAppendOnly(inventory, previousInventory));
  result.ok = result.errors.length === 0;
  return result;
}

function writeInventory(filePath, inventory) {
  const result = validateInventoryFile(inventory, filePath);
  if (!result.ok) {
    throw new Error(
      `Invalid factory inventory:\n${result.errors
        .map((error) => `- ${error}`)
        .join("\n")}`
    );
  }
  writeJson(filePath, inventory);
}

function createInventory({
  network,
  chainId,
  marketTypes = DEFAULT_MARKET_TYPES,
} = {}) {
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
    recordCount: 0,
    hooksFactories: [],
    wrapperFactories: [],
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

function logicalCall(transaction) {
  if (!transaction || transaction.kind === "deploy") return null;
  return transaction.forwardedCall || {
    target: transaction.to,
    functionSignature: transaction.functionSignature,
    args: transaction.args,
  };
}

function getFactoryDeactivationTargets(inventory, excludedAddresses = []) {
  const excluded = new Set(excludedAddresses.map(addressKey));
  return inventory.hooksFactories
    .filter(
      (entry) =>
        entry.registered === true && !excluded.has(addressKey(entry.address))
    )
    .map((entry) => ({ factory: entry.address, label: entry.label }));
}

function getFactoryRetirementTargets(inventory) {
  return inventory.hooksFactories
    .filter(
      (entry) =>
        entry.registered === true &&
        entry.lifecycle !== "canonical" &&
        entry.canonical !== true
    )
    .map((entry) => ({ factory: entry.address, label: entry.label }));
}

function getPlanRetirementTargets(plan, inventory, archController) {
  const targets = [];
  const seen = new Set();
  for (const transaction of plan.transactions || []) {
    const call = logicalCall(transaction);
    if (call?.functionSignature !== "removeControllerFactory(address)") {
      continue;
    }
    const factory = call.args?.[0];
    if (
      !isAddress(call.target) ||
      addressKey(call.target) !== addressKey(archController) ||
      !isAddress(factory)
    ) {
      throw new Error(`Invalid retirement target in ${transaction.id}`);
    }
    const factoryKey = addressKey(factory);
    if (seen.has(factoryKey)) {
      throw new Error(`Duplicate retirement target ${factory}`);
    }
    seen.add(factoryKey);
    const entry = inventory.hooksFactories.find(
      (candidate) => addressKey(candidate.address) === factoryKey
    );
    if (!entry) {
      throw new Error(`Retirement target ${factory} is missing from inventory`);
    }
    if (entry.lifecycle === "canonical" || entry.canonical === true) {
      throw new Error(`Retirement plan targets canonical factory ${entry.label}`);
    }
    targets.push({ factory: entry.address, label: entry.label });
  }
  if (targets.length === 0) {
    throw new Error("Retirement plan does not contain any factory targets");
  }
  return targets;
}

function recordFactoryDeactivations(inventory, targets) {
  for (const target of targets) {
    const entry = inventory.hooksFactories.find(
      (candidate) =>
        addressKey(candidate.address) === addressKey(target.factory)
    );
    if (!entry) {
      throw new Error(
        `Factory deactivation target disappeared from inventory: ${target.label} (${target.factory})`
      );
    }
    entry.registered = false;
  }
}

function assertFactoryDeactivationPlan(plan, targets, archController) {
  if (!isAddress(archController)) {
    throw new Error(
      "Missing valid ArchController for factory deactivation plan"
    );
  }
  const controllerFactorySignature = "removeControllerFactory(address)";
  const controllerSignature = "removeController(address)";
  const controllerFactoryPredicate =
    "isRegisteredControllerFactory(address) view returns (bool)";
  const controllerPredicate =
    "isRegisteredController(address) view returns (bool)";
  const controllerFactoryCalls = plan.transactions.filter(
    (transaction) => logicalCall(transaction)?.functionSignature === controllerFactorySignature
  );
  const controllerCalls = plan.transactions.filter(
    (transaction) => logicalCall(transaction)?.functionSignature === controllerSignature
  );

  if (
    plan.transactions.some(
      (transaction) => logicalCall(transaction)?.functionSignature === "removeMarket(address)"
    )
  ) {
    throw new Error(
      "Factory deactivation plan must not remove existing markets"
    );
  }

  if (
    controllerFactoryCalls.length !== targets.length ||
    controllerCalls.length !== targets.length
  ) {
    throw new Error(
      `Expected ${targets.length} controller-factory and controller removals; found ${controllerFactoryCalls.length} and ${controllerCalls.length}`
    );
  }

  function assertRemoval(target, signature, predicateSignature) {
    const matches = plan.transactions
      .map((transaction, index) => ({ transaction, index }))
      .filter(
        ({ transaction }) => {
          const call = logicalCall(transaction);
          return (
            call?.functionSignature === signature &&
            Array.isArray(call.args) &&
            call.args.length === 1 &&
            isAddress(call.args[0]) &&
            addressKey(call.args[0]) === addressKey(target.factory)
          );
        }
      );
    if (matches.length !== 1) {
      throw new Error(
        `Expected exactly one ${signature} call for ${target.label} (${target.factory}); found ${matches.length}`
      );
    }
    const { transaction, index } = matches[0];
    const call = logicalCall(transaction);
    const predicate = transaction.predicate;
    if (
      !isAddress(call.target) ||
      addressKey(call.target) !== addressKey(archController) ||
      predicate?.type !== "callEq" ||
      !isAddress(predicate.target) ||
      addressKey(predicate.target) !== addressKey(archController) ||
      predicate.call?.sig !== predicateSignature ||
      !Array.isArray(predicate.call?.args) ||
      predicate.call.args.length !== 1 ||
      !isAddress(predicate.call.args[0]) ||
      addressKey(predicate.call.args[0]) !== addressKey(target.factory) ||
      predicate.expect !== false
    ) {
      throw new Error(
        `Invalid ${signature} destination or predicate for ${target.label} (${target.factory})`
      );
    }
    return index;
  }

  for (const target of targets) {
    const controllerFactoryIndex = assertRemoval(
      target,
      controllerFactorySignature,
      controllerFactoryPredicate
    );
    const controllerIndex = assertRemoval(
      target,
      controllerSignature,
      controllerPredicate
    );
    if (controllerIndex <= controllerFactoryIndex) {
      throw new Error(
        `Unsafe factory deactivation order for ${target.label} (${target.factory})`
      );
    }
  }
}

function authorizedHelperContext(network, deployments = null) {
  const ceremonyConfigPath = path.join(
    "deployments",
    network,
    "ceremony-config.json"
  );
  if (!fs.existsSync(ceremonyConfigPath)) return null;

  const ceremonyConfig = readJson(ceremonyConfigPath);
  if (
    ceremonyConfig.schemaVersion !== "2.0.0" ||
    ceremonyConfig.ownership?.type !== "authorized-helper" ||
    typeof ceremonyConfig.ownership.archControllerKey !== "string" ||
    typeof ceremonyConfig.ownership.helperOwnerKey !== "string" ||
    typeof ceremonyConfig.ownership.legacyHelperOwnerKey !== "string" ||
    typeof ceremonyConfig.ownership.helperVersion !== "string" ||
    !Array.isArray(ceremonyConfig.ownership.retainedAuthorizedAccounts) ||
    ceremonyConfig.ownership.retainedAuthorizedAccounts.some(
      (account) => !isAddress(account)
    ) ||
    new Set(
      ceremonyConfig.ownership.retainedAuthorizedAccounts.map((account) =>
        account.toLowerCase()
      )
    ).size !== ceremonyConfig.ownership.retainedAuthorizedAccounts.length ||
    !Array.isArray(ceremonyConfig.ownership.revokedSphereXEngineOperators) ||
    ceremonyConfig.ownership.revokedSphereXEngineOperators.some(
      (account) => !isAddress(account)
    ) ||
    new Set(
      ceremonyConfig.ownership.revokedSphereXEngineOperators.map((account) =>
        account.toLowerCase()
      )
    ).size !== ceremonyConfig.ownership.revokedSphereXEngineOperators.length ||
    !Array.isArray(ceremonyConfig.ownership.forwardedFunctionSignatures) ||
    ceremonyConfig.ownership.forwardedFunctionSignatures.length === 0 ||
    new Set(ceremonyConfig.ownership.forwardedFunctionSignatures).size !==
      ceremonyConfig.ownership.forwardedFunctionSignatures.length
  ) {
    throw new Error(`Invalid authorized-helper ceremony config: ${ceremonyConfigPath}`);
  }
  const resolvedDeployments =
    deployments ||
    readJson(path.join("deployments", network, "deployments.json"));
  const archController =
    resolvedDeployments[ceremonyConfig.ownership.archControllerKey];
  const helperOwner =
    resolvedDeployments[ceremonyConfig.ownership.helperOwnerKey];
  if (!isAddress(archController) || !isAddress(helperOwner)) {
    throw new Error(
      `Authorized-helper ceremony config references a missing deployment address: ${ceremonyConfigPath}`
    );
  }
  return {
    archController,
    helperOwner,
    forwardedFunctionSignatures:
      ceremonyConfig.ownership.forwardedFunctionSignatures,
  };
}

function assertAuthorizedHelperBoundary(plan, context) {
  if (!context) return;
  const forwardedSignatures = new Set(context.forwardedFunctionSignatures);
  if (
    !isAddress(plan.expectedExecutor) ||
    plan.transactions.some(
      (transaction) =>
        transaction.id === "reclaim-arch-controller-ownership" ||
        transaction.id === "restore-arch-controller-ownership" ||
        transaction.reverifyUntil !== undefined
    )
  ) {
    throw new Error(
      "Authorized-helper plan must not contain temporary ownership transactions"
    );
  }
  for (const transaction of plan.transactions) {
    if (transaction.kind !== "call") continue;
    const call = logicalCall(transaction);
    const shouldForward = forwardedSignatures.has(call.functionSignature);
    const isForwarded = transaction.forwardedCall !== undefined;
    if (shouldForward !== isForwarded) {
      throw new Error(
        `${transaction.id}: authorized-helper forwarding does not match ceremony config`
      );
    }
    if (
      isForwarded &&
      (!isAddress(transaction.to) ||
        addressKey(transaction.to) !== addressKey(context.helperOwner) ||
        transaction.functionSignature !== AUTHORITY_HELPER_FORWARD_SIGNATURE ||
        transaction.args !== undefined)
    ) {
      throw new Error(
        `${transaction.id}: invalid authorized-helper forwarding envelope`
      );
    }
  }
}

function assertActivationPlan(plan, network, options = {}) {
  if (!Array.isArray(plan.transactions) || plan.network !== network) {
    throw new Error(`Activation plan does not belong to network ${network}`);
  }
  if (typeof plan.release !== "string" || plan.release.endsWith("-retirement")) {
    throw new Error("Activation plan must not use the retirement release suffix");
  }
  const forbiddenSignatures = new Set([
    "removeControllerFactory(address)",
    "removeController(address)",
    "removeMarket(address)",
  ]);
  const forbidden = plan.transactions.find((transaction) =>
    forbiddenSignatures.has(logicalCall(transaction)?.functionSignature)
  );
  if (forbidden) {
    throw new Error(
      `Activation plan must not retire factories or markets; found ${logicalCall(forbidden).functionSignature}`
    );
  }

  const allExpectedTransactions = [
    {
      id: "deploy-wildcat-4626-wrapper-factory",
      kind: "deploy",
      artifactName:
        "src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory",
    },
    {
      id: "deploy-borrower-identity-registry",
      kind: "deploy",
      artifactName:
        "src/WildcatBorrowerIdentityRegistry.sol:WildcatBorrowerIdentityRegistry",
    },
    {
      id: "deploy-access-list-role-provider-factory",
      kind: "deploy",
      artifactName:
        "src/providers/AccessListRoleProviderFactory.sol:AccessListRoleProviderFactory",
    },
    {
      id: "deploy-wildcat-market-init-code-storage",
      kind: "deploy",
      artifactName: "script/common/DeployScriptBase.sol:InitCodeStorage",
    },
    {
      id: "deploy-hooks-factory-standard",
      kind: "deploy",
      artifactName: "src/HooksFactory.sol:HooksFactory",
    },
    {
      id: "deploy-wildcat-market-revolving-init-code-storage",
      kind: "deploy",
      artifactName: "script/common/DeployScriptBase.sol:InitCodeStorage",
    },
    {
      id: "deploy-hooks-factory-revolving",
      kind: "deploy",
      artifactName: "src/HooksFactoryRevolving.sol:HooksFactoryRevolving",
    },
    {
      id: "deploy-market-lens-core",
      kind: "deploy",
      artifactName: "src/lens/MarketLensCore.sol:MarketLensCore",
    },
    {
      id: "deploy-market-lens-aggregator",
      kind: "deploy",
      artifactName: "src/lens/MarketLensAggregator.sol:MarketLensAggregator",
    },
    {
      id: "deploy-market-lens-live",
      kind: "deploy",
      artifactName: "src/lens/MarketLensLive.sol:MarketLensLive",
    },
    {
      id: "deploy-market-lens",
      kind: "deploy",
      artifactName: "src/lens/MarketLens.sol:MarketLens",
    },
    {
      id: "deploy-open-term-hooks-init-code-storage",
      kind: "deploy",
      artifactName: "script/common/DeployScriptBase.sol:InitCodeStorage",
    },
    {
      id: "deploy-fixed-term-hooks-init-code-storage",
      kind: "deploy",
      artifactName: "script/common/DeployScriptBase.sol:InitCodeStorage",
    },
    {
      id: "deploy-periodic-term-hooks-init-code-storage",
      kind: "deploy",
      artifactName: "script/common/DeployScriptBase.sol:InitCodeStorage",
    },
    {
      id: "register-controller-factory-standard",
      kind: "call",
      functionSignature: "registerControllerFactory(address)",
    },
    {
      id: "register-controller-factory-revolving",
      kind: "call",
      functionSignature: "registerControllerFactory(address)",
    },
    ...[
      "add-standard-open-term-template",
      "add-standard-fixed-term-template",
      "add-standard-periodic-term-template",
      "add-revolving-open-term-template",
      "add-revolving-fixed-term-template",
      "add-revolving-periodic-term-template",
    ].map((id) => ({
      id,
      kind: "call",
      functionSignature:
        "addHooksTemplate(address,string,address,address,uint80,uint16)",
    })),
    {
      id: "register-hooks-factory-standard",
      kind: "call",
      functionSignature: "registerWithArchController()",
    },
    {
      id: "register-hooks-factory-revolving",
      kind: "call",
      functionSignature: "registerWithArchController()",
    },
  ];
  const omittedDeploymentIds = new Set();
  if (options.reuseIdentityRegistry === true) {
    omittedDeploymentIds.add("deploy-borrower-identity-registry");
  }
  if (options.reuseAccessListRoleProviderFactory === true) {
    omittedDeploymentIds.add("deploy-access-list-role-provider-factory");
  }
  const expectedTransactions = allExpectedTransactions.filter(
    ({ id }) => !omittedDeploymentIds.has(id)
  );
  const authorityHelper = authorizedHelperContext(network);
  if (plan.transactions.length !== expectedTransactions.length) {
    throw new Error(
      `Activation plan must contain exactly ${expectedTransactions.length} transactions; found ${plan.transactions.length}`
    );
  }
  for (const [index, expected] of expectedTransactions.entries()) {
    const transaction = plan.transactions[index];
    if (
      transaction.id !== expected.id ||
      transaction.kind !== expected.kind ||
      (expected.artifactName &&
        transaction.artifactName !== expected.artifactName) ||
      (expected.functionSignature &&
        logicalCall(transaction)?.functionSignature !== expected.functionSignature)
    ) {
      throw new Error(
        `Activation transaction ${index + 1} must be ${expected.id}`
      );
    }
  }
  assertAuthorizedHelperBoundary(plan, authorityHelper);

  const requiredDeployments = [
    {
      id: "deploy-borrower-identity-registry",
      output: "borrower-identity-registry",
      reuseOption: "reuseIdentityRegistry",
      artifactName:
        "src/WildcatBorrowerIdentityRegistry.sol:WildcatBorrowerIdentityRegistry",
    },
    {
      id: "deploy-access-list-role-provider-factory",
      output: "access-list-role-provider-factory",
      reuseOption: "reuseAccessListRoleProviderFactory",
      artifactName:
        "src/providers/AccessListRoleProviderFactory.sol:AccessListRoleProviderFactory",
    },
  ];
  for (const required of requiredDeployments) {
    const transaction = plan.transactions.find(
      (candidate) => candidate.id === required.id
    );
    if (options[required.reuseOption] === true) {
      if (transaction !== undefined) {
        throw new Error(
          `Activation plan deploys ${required.id} despite its reused inventory record`
        );
      }
      continue;
    }
    if (
      transaction?.kind !== "deploy" ||
      transaction.output !== required.output ||
      transaction.artifactName !== required.artifactName
    ) {
      throw new Error(`Activation plan has an invalid ${required.id} deployment`);
    }
  }

  const optionalProviderFactoryArtifacts = [
    "MerkleRoleProviderFactory.sol",
    "ERC20RoleProviderFactory.sol",
    "ERC4626AssetsRoleProviderFactory.sol",
    "ERC721RoleProviderFactory.sol",
    "ERC1155RoleProviderFactory.sol",
  ];
  const optionalProvider = plan.transactions.find(
    (transaction) =>
      transaction.kind === "deploy" &&
      optionalProviderFactoryArtifacts.some((artifact) =>
        transaction.artifactName?.includes(artifact)
      )
  );
  if (optionalProvider) {
    throw new Error(
      `Activation plan includes unsupported optional provider factory ${optionalProvider.artifactName}`
    );
  }

  const standardIndex = plan.transactions.findIndex(
    (transaction) => transaction.id === "register-hooks-factory-standard"
  );
  const revolvingIndex = plan.transactions.findIndex(
    (transaction) => transaction.id === "register-hooks-factory-revolving"
  );
  if (
    standardIndex === -1 ||
    revolvingIndex === -1 ||
    standardIndex >= revolvingIndex
  ) {
    throw new Error(
      "Activation plan must register the standard and revolving factories in order"
    );
  }
}

function removeUndefinedFields(value) {
  return Object.fromEntries(
    Object.entries(value).filter(([, fieldValue]) => fieldValue !== undefined)
  );
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function lifecycleForLegacyFactory(entry) {
  if (entry.canonical === true) return "canonical";
  if (entry.indexed === true) return "live";
  return "retired";
}

function migrateHookFactoryEntry(entry) {
  const {
    label,
    marketType,
    address,
    startBlock,
    canonical,
    indexed,
    registered,
    ...optionalFields
  } = entry;
  return {
    label,
    marketType,
    address,
    startBlock,
    canonical,
    lifecycle: lifecycleForLegacyFactory(entry),
    indexed,
    registered,
    ...optionalFields,
  };
}

function migrateInventory(inventory) {
  if (inventory?.schemaVersion !== LEGACY_INVENTORY_SCHEMA_VERSION) {
    throw new Error(
      `Can only migrate schema ${LEGACY_INVENTORY_SCHEMA_VERSION}; got ${
        inventory?.schemaVersion || "<missing>"
      }`
    );
  }
  assertValidInventory(inventory);
  const hooksFactories = inventory.hooksFactories.map(migrateHookFactoryEntry);
  return {
    schemaVersion: INVENTORY_SCHEMA_VERSION,
    network: inventory.network,
    chainId: inventory.chainId,
    marketTypes: cloneJson(inventory.marketTypes),
    recordCount: hooksFactories.length,
    hooksFactories,
    wrapperFactories: [],
  };
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

function validateAllowedFields(errors, entry, allowedFields, prefix) {
  for (const key of Object.keys(entry)) {
    if (!allowedFields.has(key)) {
      errors.push(`${prefix}.${key} is not allowed by schema 1.1`);
    }
  }
}

function validateLabel(errors, entry, prefix) {
  if (typeof entry.label !== "string" || entry.label.trim() === "") {
    errors.push(`${prefix}.label must be a nonempty string`);
  } else if (entry.label.includes(".")) {
    errors.push(`${prefix}.label must not contain dots`);
  }
}

function validateFactoryEntry(entry, index, marketTypes, schemaVersion) {
  const errors = [];
  const prefix = `hooksFactories[${index}]`;

  if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
    return [`${prefix} must be an object`];
  }

  if (schemaVersion === INVENTORY_SCHEMA_VERSION) {
    validateAllowedFields(errors, entry, HOOK_FACTORY_FIELDS, prefix);
    validateLabel(errors, entry, prefix);
  } else {
    requireString(errors, entry, "label");
  }
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

  if (schemaVersion === INVENTORY_SCHEMA_VERSION) {
    if (!LIFECYCLES.has(entry.lifecycle)) {
      errors.push(`${prefix}.lifecycle must be canonical, live, or retired`);
    }
    if (entry.lifecycle === "retired" && entry.indexed !== false) {
      errors.push(`${prefix} is retired but indexed is not false`);
    }
    if ((entry.lifecycle === "canonical") !== (entry.canonical === true)) {
      errors.push(`${prefix}.canonical must agree with lifecycle`);
    }
  }

  if (
    typeof entry.marketType === "string" &&
    !marketTypes.has(entry.marketType)
  ) {
    errors.push(`${prefix}.marketType is not listed in top-level marketTypes`);
  }

  if (entry.canonical === true && entry.registered !== true) {
    errors.push(`${prefix} is canonical but not registered`);
  }

  if (entry.canonical === true && entry.indexed !== true) {
    errors.push(`${prefix} is canonical but not indexed`);
  }

  if (
    entry.indexed === true &&
    (!Number.isSafeInteger(entry.startBlock) || entry.startBlock === 0)
  ) {
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
    errors.push(
      `${prefix}.initCodeStorage must be a valid EVM address when present`
    );
  }

  if (hasOwn(entry, "wrapperFactory") && !isAddress(entry.wrapperFactory)) {
    errors.push(
      `${prefix}.wrapperFactory must be a valid EVM address when present`
    );
  }

  return errors.map((error) =>
    error.startsWith(prefix) ? error : `${prefix}.${error}`
  );
}

function validateWrapperFactoryEntry(entry, index) {
  const errors = [];
  const prefix = `wrapperFactories[${index}]`;

  if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
    return [`${prefix} must be an object`];
  }

  validateAllowedFields(errors, entry, WRAPPER_FACTORY_FIELDS, prefix);
  validateLabel(errors, entry, prefix);

  if (!isAddress(entry.address)) {
    errors.push(`${prefix}.address must be a valid EVM address`);
  }
  if (!Number.isSafeInteger(entry.startBlock) || entry.startBlock < 0) {
    errors.push(`${prefix}.startBlock must be a nonnegative safe integer`);
  }
  if (!LIFECYCLES.has(entry.lifecycle)) {
    errors.push(`${prefix}.lifecycle must be canonical, live, or retired`);
  }
  if (typeof entry.indexed !== "boolean") {
    errors.push(`${prefix}.indexed must be a boolean`);
  }
  if (entry.lifecycle === "retired" && entry.indexed !== false) {
    errors.push(`${prefix} is retired but indexed is not false`);
  }
  if (entry.lifecycle === "canonical" && entry.indexed !== true) {
    errors.push(`${prefix} is canonical but not indexed`);
  }
  if (
    entry.indexed === true &&
    (!Number.isSafeInteger(entry.startBlock) || entry.startBlock === 0)
  ) {
    errors.push(`${prefix} is indexed but has no nonzero startBlock`);
  }
  if (entry.v1Factory !== null && !isAddress(entry.v1Factory)) {
    errors.push(`${prefix}.v1Factory must be a valid EVM address or null`);
  }
  if (hasOwn(entry, "deployTxHash") && !isBytes32(entry.deployTxHash)) {
    errors.push(`${prefix}.deployTxHash must be bytes32 when present`);
  }
  validateOptionalString(errors, entry, "notes");

  return errors.map((error) =>
    error.startsWith(prefix) ? error : `${prefix}.${error}`
  );
}

function validateInventory(inventory, options = {}) {
  const errors = [];
  const warnings = [];

  if (!inventory || typeof inventory !== "object" || Array.isArray(inventory)) {
    return { ok: false, errors: ["inventory must be an object"], warnings };
  }

  const supportedSchemaVersions = new Set([
    LEGACY_INVENTORY_SCHEMA_VERSION,
    INVENTORY_SCHEMA_VERSION,
  ]);
  if (!supportedSchemaVersions.has(inventory.schemaVersion)) {
    errors.push(
      `schemaVersion must be ${LEGACY_INVENTORY_SCHEMA_VERSION} or ${INVENTORY_SCHEMA_VERSION}; got ${
        inventory.schemaVersion || "<missing>"
      }`
    );
  }
  const isVersion11 = inventory.schemaVersion === INVENTORY_SCHEMA_VERSION;

  if (isVersion11) {
    const topLevelFields = new Set([
      "schemaVersion",
      "network",
      "chainId",
      "marketTypes",
      "recordCount",
      "hooksFactories",
      "wrapperFactories",
    ]);
    validateAllowedFields(errors, inventory, topLevelFields, "inventory");
  }

  if (
    typeof inventory.network !== "string" ||
    inventory.network.trim() === ""
  ) {
    errors.push("network must be a nonempty string");
  }

  if (options.network && inventory.network !== options.network) {
    errors.push(
      `network mismatch: expected ${options.network}, got ${inventory.network}`
    );
  }

  if (!Number.isSafeInteger(inventory.chainId) || inventory.chainId <= 0) {
    errors.push("chainId must be a positive safe integer");
  }

  const expectedChainId =
    options.chainId !== undefined
      ? Number(options.chainId)
      : networkNameToChainId(inventory.network);
  if (expectedChainId && inventory.chainId !== expectedChainId) {
    errors.push(
      `chainId mismatch: expected ${expectedChainId}, got ${inventory.chainId}`
    );
  }

  if (
    !Array.isArray(inventory.marketTypes) ||
    inventory.marketTypes.length === 0
  ) {
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
  const factoryCountByMarketType = new Map();
  const canonicalIndexesByMarketType = new Map();

  for (const [index, entry] of inventory.hooksFactories.entries()) {
    errors.push(
      ...validateFactoryEntry(
        entry,
        index,
        marketTypes,
        inventory.schemaVersion
      )
    );

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
          `hooksFactories[${index}].address duplicates hooksFactories[${addresses.get(
            key
          )}].address`
        );
      }
      addresses.set(key, index);
    }

    if (typeof entry.marketType === "string") {
      factoryCountByMarketType.set(
        entry.marketType,
        (factoryCountByMarketType.get(entry.marketType) || 0) + 1
      );
    }

    const isCanonical = isVersion11
      ? entry.lifecycle === "canonical"
      : entry.canonical === true;
    if (isCanonical && typeof entry.marketType === "string") {
      const indexes = canonicalIndexesByMarketType.get(entry.marketType) || [];
      indexes.push(index);
      canonicalIndexesByMarketType.set(entry.marketType, indexes);
    }

    if (inventory.network === "mainnet" && entry.indexed === false) {
      warnings.push(
        `hooksFactories[${index}] is not indexed on mainnet; confirm it cannot have live markets or user funds`
      );
    }
  }

  for (const marketType of factoryCountByMarketType.keys()) {
    const canonicalIndexes = canonicalIndexesByMarketType.get(marketType) || [];
    if (isVersion11 && canonicalIndexes.length !== 1) {
      errors.push(
        `marketType ${marketType} must have exactly one canonical lifecycle; found ${canonicalIndexes.length}`
      );
    } else if (!isVersion11 && canonicalIndexes.length > 1) {
      errors.push(
        `marketType ${marketType} has multiple canonical factories: ${canonicalIndexes
          .map((index) => `hooksFactories[${index}]`)
          .join(" and ")}`
      );
    }
  }

  if (isVersion11) {
    if (!Array.isArray(inventory.wrapperFactories)) {
      errors.push("wrapperFactories must be an array");
    } else {
      let canonicalWrapperCount = 0;
      for (const [index, entry] of inventory.wrapperFactories.entries()) {
        errors.push(...validateWrapperFactoryEntry(entry, index));
        if (!entry || typeof entry !== "object") continue;

        if (typeof entry.label === "string") {
          if (labels.has(entry.label)) {
            errors.push(
              `wrapperFactories[${index}].label duplicates ${entry.label}`
            );
          }
          labels.add(entry.label);
        }
        if (isAddress(entry.address)) {
          const key = entry.address.toLowerCase();
          if (addresses.has(key)) {
            errors.push(
              `wrapperFactories[${index}].address duplicates ${addresses.get(
                key
              )}`
            );
          }
          addresses.set(key, `wrapperFactories[${index}].address`);
        }
        if (entry.lifecycle === "canonical") canonicalWrapperCount += 1;
        if (inventory.network === "mainnet" && entry.indexed === false) {
          warnings.push(
            `wrapperFactories[${index}] is not indexed on mainnet; confirm it cannot have live wrappers or user funds`
          );
        }
      }
      if (canonicalWrapperCount > 1) {
        errors.push(
          `wrapperFactories must have at most one canonical lifecycle; found ${canonicalWrapperCount}`
        );
      }
    }

    const totalRecords =
      inventory.hooksFactories.length +
      (Array.isArray(inventory.wrapperFactories)
        ? inventory.wrapperFactories.length
        : 0);
    if (
      !Number.isSafeInteger(inventory.recordCount) ||
      inventory.recordCount < 0
    ) {
      errors.push("recordCount must be a nonnegative safe integer");
    } else if (inventory.recordCount !== totalRecords) {
      errors.push(
        `recordCount must equal total inventory records: expected ${totalRecords}, got ${inventory.recordCount}`
      );
    }
  }

  return { ok: errors.length === 0, errors, warnings };
}

function assertValidInventory(inventory, options = {}) {
  const result = validateInventory(inventory, options);
  if (!result.ok) {
    throw new Error(
      `Invalid factory inventory:\n${result.errors
        .map((error) => `- ${error}`)
        .join("\n")}`
    );
  }
  return inventory;
}

function upsertFactory(inventory, factoryEntry) {
  const next = cloneJson(inventory);
  const incoming = removeUndefinedFields({ ...factoryEntry });
  const incomingAddressKey = addressKey(incoming.address);

  const labelIndex = next.hooksFactories.findIndex(
    (entry) => entry.label === incoming.label
  );
  const addressIndex = next.hooksFactories.findIndex(
    (entry) =>
      isAddress(entry.address) &&
      entry.address.toLowerCase() === incomingAddressKey
  );

  if (labelIndex !== -1 && addressIndex !== -1 && labelIndex !== addressIndex) {
    throw new Error(
      `Cannot upsert factory ${incoming.label}: label and address match different inventory entries`
    );
  }

  const replaceIndex = labelIndex !== -1 ? labelIndex : addressIndex;
  const merged =
    replaceIndex === -1
      ? incoming
      : { ...next.hooksFactories[replaceIndex], ...incoming };

  if (
    next.schemaVersion === INVENTORY_SCHEMA_VERSION &&
    !hasOwn(incoming, "lifecycle")
  ) {
    merged.lifecycle = lifecycleForLegacyFactory(merged);
  }

  if (merged.canonical === true) {
    for (const entry of next.hooksFactories) {
      if (entry.marketType === merged.marketType) {
        entry.canonical = false;
        if (
          next.schemaVersion === INVENTORY_SCHEMA_VERSION &&
          entry.lifecycle === "canonical"
        ) {
          entry.lifecycle = "live";
        }
      }
    }
  }

  if (replaceIndex === -1) {
    next.hooksFactories.push(merged);
  } else {
    next.hooksFactories[replaceIndex] = merged;
  }

  if (next.schemaVersion === INVENTORY_SCHEMA_VERSION) {
    next.recordCount =
      next.hooksFactories.length + next.wrapperFactories.length;
  }

  return assertValidInventory(next);
}

function upsertWrapperFactory(inventory, wrapperEntry) {
  if (inventory.schemaVersion !== INVENTORY_SCHEMA_VERSION) {
    throw new Error("Wrapper factories require inventory schema 1.1.0");
  }

  const next = cloneJson(inventory);
  const incoming = removeUndefinedFields({ ...wrapperEntry });
  const incomingAddressKey = addressKey(incoming.address);
  const labelIndex = next.wrapperFactories.findIndex(
    (entry) => entry.label === incoming.label
  );
  const addressIndex = next.wrapperFactories.findIndex(
    (entry) =>
      isAddress(entry.address) &&
      entry.address.toLowerCase() === incomingAddressKey
  );

  if (labelIndex !== -1 && addressIndex !== -1 && labelIndex !== addressIndex) {
    throw new Error(
      `Cannot upsert wrapper factory ${incoming.label}: label and address match different inventory entries`
    );
  }

  const replaceIndex = labelIndex !== -1 ? labelIndex : addressIndex;
  const merged =
    replaceIndex === -1
      ? incoming
      : { ...next.wrapperFactories[replaceIndex], ...incoming };

  if (merged.lifecycle === "canonical") {
    for (const entry of next.wrapperFactories) {
      if (entry.lifecycle === "canonical") entry.lifecycle = "live";
    }
  }

  if (replaceIndex === -1) {
    next.wrapperFactories.push(merged);
  } else {
    next.wrapperFactories[replaceIndex] = merged;
  }
  next.recordCount = next.hooksFactories.length + next.wrapperFactories.length;
  return assertValidInventory(next);
}

function findFactoryEntry(inventory, factoryEntry) {
  const incomingAddressKey = factoryEntry.address
    ? addressKey(factoryEntry.address)
    : null;
  return inventory.hooksFactories.find(
    (entry) =>
      entry.label === factoryEntry.label ||
      (incomingAddressKey &&
        isAddress(entry.address) &&
        entry.address.toLowerCase() === incomingAddressKey)
  );
}

function findWrapperFactoryEntry(inventory, wrapperEntry) {
  const incomingAddressKey = wrapperEntry.address
    ? addressKey(wrapperEntry.address)
    : null;
  return (inventory.wrapperFactories || []).find(
    (entry) =>
      entry.label === wrapperEntry.label ||
      (incomingAddressKey &&
        isAddress(entry.address) &&
        entry.address.toLowerCase() === incomingAddressKey)
  );
}

function getCanonicalFactory(inventory, marketType) {
  return inventory.hooksFactories.find(
    (entry) =>
      entry.marketType === marketType &&
      (inventory.schemaVersion === INVENTORY_SCHEMA_VERSION
        ? entry.lifecycle === "canonical"
        : entry.canonical === true)
  );
}

function getCanonicalWrapperFactory(inventory) {
  return (inventory.wrapperFactories || []).find(
    (entry) => entry.lifecycle === "canonical"
  );
}

function getIndexedFactories(inventory, marketType) {
  return inventory.hooksFactories.filter(
    (entry) =>
      entry.indexed === true && (!marketType || entry.marketType === marketType)
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

function parseLifecycle(value) {
  if (!LIFECYCLES.has(value)) {
    throw new Error(`Invalid lifecycle: ${value}`);
  }
  return value;
}

function parseNullableAddress(value, fieldName) {
  if (value === "null") return null;
  if (!isAddress(value)) {
    throw new Error(`Invalid address or null for --${fieldName}: ${value}`);
  }
  return value;
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
      args["start-block"] === undefined
        ? undefined
        : parseSafeInteger(args["start-block"], "start-block"),
    canonical: parseBoolean(requireArg(args, "canonical"), "canonical"),
    lifecycle:
      args.lifecycle === undefined
        ? undefined
        : parseLifecycle(requireArg(args, "lifecycle")),
    indexed: parseBoolean(requireArg(args, "indexed"), "indexed"),
    registered: parseBoolean(requireArg(args, "registered"), "registered"),
    deploymentKey: optionalArg(args, "deployment-key"),
    deployTxHash: optionalArg(args, "deploy-tx-hash"),
    registerTxHash: optionalArg(args, "register-tx-hash"),
    wrapperFactory: optionalArg(args, "wrapper-factory"),
    initCodeStorage: optionalArg(args, "init-code-storage"),
    initCodeHash: optionalArg(args, "init-code-hash"),
    notes: optionalArg(args, "notes"),
  });
}

function buildWrapperFactoryEntryFromArgs(args) {
  return removeUndefinedFields({
    label: requireArg(args, "label"),
    address: requireArg(args, "address"),
    startBlock:
      args["start-block"] === undefined
        ? undefined
        : parseSafeInteger(args["start-block"], "start-block"),
    lifecycle: parseLifecycle(requireArg(args, "lifecycle")),
    indexed: parseBoolean(requireArg(args, "indexed"), "indexed"),
    deployTxHash: optionalArg(args, "deploy-tx-hash"),
    v1Factory: parseNullableAddress(
      requireArg(args, "v1-factory"),
      "v1-factory"
    ),
    notes: optionalArg(args, "notes"),
  });
}

function readOptionalJson(filePath) {
  if (!fs.existsSync(filePath)) return null;
  return readJson(filePath);
}

function expectedCanonicalAliases(inventory, handoff) {
  const aliases = new Map();
  const legacyFactory = getCanonicalFactory(inventory, "legacy");
  const revolvingFactory = getCanonicalFactory(inventory, "revolving");
  const wrapperFactory = getCanonicalWrapperFactory(inventory);

  if (legacyFactory) aliases.set("HooksFactory", legacyFactory.address);
  if (revolvingFactory)
    aliases.set("HooksFactoryRevolving", revolvingFactory.address);
  if (wrapperFactory)
    aliases.set("Wildcat4626WrapperFactory", wrapperFactory.address);
  // The handoff is a point-in-time release artifact, not current truth:
  // lens deployments after its generation (e.g. the PTH v2.1 lens) are
  // expected to be newer. Lens alias mismatches warn instead of erroring.
  return aliases;
}

function handoffMarketLensAddress(handoff) {
  for (const address of [
    handoff?.canonicalAddresses?.marketLens,
    handoff?.addresses?.marketLensLatest,
  ]) {
    if (isAddress(address)) return address;
  }
  return null;
}

function lintDeployments({ inventory, deployments, handoff, legacyKeys }) {
  const errors = [];
  const warnings = [];
  const allowlistedKeys = new Set(legacyKeys || []);

  for (const [key, value] of Object.entries(deployments)) {
    if (key.includes(".")) {
      errors.push(`deployments.json key ${key} contains a dot`);
    } else if (!SAFE_DEPLOYMENT_KEY_REGEX.test(key)) {
      errors.push(`deployments.json key ${key} has an unknown key shape`);
    }

    if (!isAddress(value)) {
      errors.push(
        `deployments.json key ${key} does not contain an EVM address`
      );
    }

    if (allowlistedKeys.has(key)) {
      warnings.push(`known legacy deployments.json key retained: ${key}`);
    } else if (RAW_TIMESTAMP_LABEL_REGEX.test(key)) {
      errors.push(
        `deployments.json key ${key} contains a raw timestamp and is not allowlisted`
      );
    }
  }

  for (const [alias, expectedAddress] of expectedCanonicalAliases(
    inventory,
    handoff
  )) {
    const actualAddress = deployments[alias];
    if (!actualAddress) {
      errors.push(
        `canonical alias ${alias} is missing; expected ${expectedAddress}`
      );
    } else if (
      isAddress(actualAddress) &&
      addressKey(actualAddress) !== addressKey(expectedAddress)
    ) {
      errors.push(
        `canonical alias ${alias} mismatch: expected ${expectedAddress}, got ${actualAddress}`
      );
    }
  }

  return { ok: errors.length === 0, errors, warnings };
}

function loadDotEnv(filePath = ".env") {
  if (!fs.existsSync(filePath)) return {};
  const values = {};
  for (const line of fs.readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const match = /^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(
      line.trim()
    );
    if (!match) continue;
    let value = match[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    } else {
      value = value.replace(/\s+#.*$/, "");
    }
    values[match[1]] = value;
  }
  return values;
}

function resolveRpcConfig(network, explicitRpcUrl) {
  if (explicitRpcUrl) return { url: explicitRpcUrl, source: "--rpc-url" };
  const dotEnv = loadDotEnv();
  const networkVariable =
    network === "sepolia" ? "SEPOLIA_RPC_URL" : "MAINNET_RPC_URL";
  for (const variableName of [networkVariable, "RPC_URL"]) {
    if (process.env[variableName]) {
      return {
        url: process.env[variableName],
        source: `environment:${variableName}`,
      };
    }
    if (dotEnv[variableName]) {
      return { url: dotEnv[variableName], source: `.env:${variableName}` };
    }
  }
  const fallback = PUBLIC_RPC_URLS[network];
  if (!fallback) throw new Error(`No default RPC URL for network ${network}`);
  return { url: fallback, source: "fallback:publicnode" };
}

function createRpcClient(rpcUrl) {
  let requestId = 0;
  return async function rpc(method, params = []) {
    requestId += 1;
    const response = await fetch(rpcUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: requestId, method, params }),
      signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) {
      throw new Error(`${method} HTTP ${response.status}`);
    }
    const payload = await response.json();
    if (payload.error) {
      throw new Error(
        `${method} RPC ${payload.error.code}: ${payload.error.message}`
      );
    }
    return payload.result;
  };
}

function decodeAddressArray(encoded, context) {
  if (typeof encoded !== "string" || !/^0x[a-fA-F0-9]*$/.test(encoded)) {
    throw new Error(`${context} returned malformed ABI data`);
  }
  const data = encoded.slice(2);
  if (data.length < 128) throw new Error(`${context} returned short ABI data`);
  const offset = Number(BigInt(`0x${data.slice(0, 64)}`));
  const lengthOffset = offset * 2;
  if (lengthOffset + 64 > data.length)
    throw new Error(`${context} returned invalid ABI offset`);
  const length = Number(
    BigInt(`0x${data.slice(lengthOffset, lengthOffset + 64)}`)
  );
  const addresses = [];
  for (let index = 0; index < length; index += 1) {
    const wordStart = lengthOffset + 64 + index * 64;
    const word = data.slice(wordStart, wordStart + 64);
    if (word.length !== 64)
      throw new Error(`${context} returned truncated address array`);
    addresses.push(`0x${word.slice(24)}`);
  }
  return addresses;
}

function decodeAddress(encoded, context) {
  if (typeof encoded !== "string" || !/^0x[a-fA-F0-9]{64}$/.test(encoded)) {
    throw new Error(`${context} returned malformed address data`);
  }
  return `0x${encoded.slice(-40)}`;
}

function receiptBlockNumber(receipt) {
  if (!receipt?.blockNumber || !/^0x[a-fA-F0-9]+$/.test(receipt.blockNumber))
    return null;
  const blockNumber = Number(BigInt(receipt.blockNumber));
  return Number.isSafeInteger(blockNumber) ? blockNumber : null;
}

function reconcileCanonicalAliases(inventory, deployments, handoff) {
  const errors = [];
  const entries = [];
  for (const [alias, expectedAddress] of expectedCanonicalAliases(
    inventory,
    handoff
  )) {
    const actualAddress = deployments[alias] || null;
    const matches =
      isAddress(actualAddress) &&
      addressKey(actualAddress) === addressKey(expectedAddress);
    entries.push({ alias, expectedAddress, actualAddress, matches });
    if (!actualAddress) {
      errors.push(
        `canonical alias ${alias} is missing; expected ${expectedAddress}`
      );
    } else if (!matches) {
      errors.push(
        `canonical alias ${alias} mismatch: expected ${expectedAddress}, got ${actualAddress}`
      );
    }
  }
  return { errors, entries };
}

async function reconcileRegistry({ rpc, archController, inventory, errors }) {
  const [encodedControllerFactories, encodedControllers] = await Promise.all([
    rpc("eth_call", [
      {
        to: archController,
        data: GET_REGISTERED_CONTROLLER_FACTORIES_SELECTOR,
      },
      "latest",
    ]),
    rpc("eth_call", [
      { to: archController, data: GET_REGISTERED_CONTROLLERS_SELECTOR },
      "latest",
    ]),
  ]);
  const controllerFactories = decodeAddressArray(
    encodedControllerFactories,
    "getRegisteredControllerFactories()"
  );
  const controllers = decodeAddressArray(
    encodedControllers,
    "getRegisteredControllers()"
  );
  const controllerKeys = new Set(controllers.map(addressKey));
  const controllerFactoryKeys = new Set(controllerFactories.map(addressKey));
  const registeredHooksFactories = controllerFactories.filter((address) =>
    controllerKeys.has(addressKey(address))
  );
  const factoryOnly = controllerFactories.filter(
    (address) => !controllerKeys.has(addressKey(address))
  );
  const controllerOnly = controllers.filter(
    (address) => !controllerFactoryKeys.has(addressKey(address))
  );
  const inventoryByAddress = new Map(
    inventory.hooksFactories.map((entry) => [addressKey(entry.address), entry])
  );

  for (const address of registeredHooksFactories) {
    if (!inventoryByAddress.has(addressKey(address))) {
      errors.push(
        `registered hooks factory ${address} is missing from inventory`
      );
    }
  }

  for (const entry of inventory.hooksFactories) {
    const registeredOnChain =
      controllerFactoryKeys.has(addressKey(entry.address)) &&
      controllerKeys.has(addressKey(entry.address));
    if (entry.registered !== registeredOnChain) {
      errors.push(
        `inventory registration mismatch for ${entry.label} (${entry.address}): expected registered=${entry.registered}, on-chain=${registeredOnChain}`
      );
    }
    const canonical =
      inventory.schemaVersion === INVENTORY_SCHEMA_VERSION
        ? entry.lifecycle === "canonical"
        : entry.canonical === true;
    if (canonical && !registeredOnChain) {
      errors.push(
        `canonical hooks factory ${entry.label} (${entry.address}) is not registered on-chain`
      );
    }
  }

  return {
    controllerFactories,
    controllers,
    registeredHooksFactories,
    factoryOnly,
    controllerOnly,
  };
}

async function reconcileWrappers({ rpc, inventory, errors }) {
  const entries = [];
  for (const wrapper of inventory.wrapperFactories || []) {
    const result = {
      label: wrapper.label,
      address: wrapper.address,
      codePresent: false,
      expectedV1Factory: wrapper.v1Factory,
      actualV1Factory: null,
    };
    try {
      const code = await rpc("eth_getCode", [wrapper.address, "latest"]);
      result.codePresent = typeof code === "string" && !/^0x0*$/.test(code);
      if (!result.codePresent) {
        errors.push(
          `wrapper factory ${wrapper.label} (${wrapper.address}) has no deployed code`
        );
      }
      if (wrapper.v1Factory !== null) {
        const encodedV1Factory = await rpc("eth_call", [
          { to: wrapper.address, data: V1_FACTORY_SELECTOR },
          "latest",
        ]);
        result.actualV1Factory = decodeAddress(
          encodedV1Factory,
          `${wrapper.label}.v1Factory()`
        );
        if (
          addressKey(result.actualV1Factory) !== addressKey(wrapper.v1Factory)
        ) {
          errors.push(
            `wrapper factory ${wrapper.label} v1Factory mismatch: expected ${wrapper.v1Factory}, got ${result.actualV1Factory}`
          );
        }
      }
    } catch (error) {
      errors.push(
        `wrapper factory ${wrapper.label} RPC check failed: ${error.message}`
      );
    }
    entries.push(result);
  }
  return entries;
}

async function reconcileIndexedRecords({ rpc, inventory, errors }) {
  const records = [
    ...inventory.hooksFactories.map((entry) => ({ kind: "hooks", ...entry })),
    ...(inventory.wrapperFactories || []).map((entry) => ({
      kind: "wrapper",
      ...entry,
    })),
  ].filter((entry) => entry.indexed === true);
  const results = [];
  for (const entry of records) {
    const result = {
      kind: entry.kind,
      label: entry.label,
      address: entry.address,
      startBlock: entry.startBlock,
      deployTxHash: entry.deployTxHash || null,
      receiptBlockNumber: null,
    };
    if (!Number.isSafeInteger(entry.startBlock) || entry.startBlock <= 0) {
      errors.push(
        `indexed ${entry.kind} factory ${entry.label} must have startBlock > 0`
      );
    }
    if (entry.deployTxHash) {
      try {
        const receipt = await rpc("eth_getTransactionReceipt", [
          entry.deployTxHash,
        ]);
        result.receiptBlockNumber = receiptBlockNumber(receipt);
        if (result.receiptBlockNumber === null) {
          errors.push(
            `deploy receipt missing or invalid for ${entry.label} (${entry.deployTxHash})`
          );
        } else if (result.receiptBlockNumber !== entry.startBlock) {
          errors.push(
            `startBlock mismatch for ${entry.label}: inventory=${entry.startBlock}, receipt=${result.receiptBlockNumber}`
          );
        }
      } catch (error) {
        errors.push(
          `deploy receipt check failed for ${entry.label}: ${error.message}`
        );
      }
    }
    results.push(result);
  }
  return results;
}

function runDeactivationTargets(args) {
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  if (!network) throw new Error("Missing --network or DEPLOYMENTS_NETWORK.");
  const inventory = assertValidInventory(
    readInventory(resolveInputPath(args)),
    {
      network,
    }
  );
  const excludeValue = optionalArg(args, "exclude");
  const excludedAddresses = excludeValue ? excludeValue.split(",") : [];
  for (const address of excludedAddresses) {
    if (!isAddress(address)) {
      throw new Error(`Invalid excluded factory address: ${address}`);
    }
  }
  process.stdout.write(
    JSON.stringify(getFactoryDeactivationTargets(inventory, excludedAddresses))
  );
}

function runValidateActivationPlan(args) {
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  if (!network) throw new Error("Missing --network or DEPLOYMENTS_NETWORK.");
  const planPath = requireArg(args, "plan");
  const plan = readJson(planPath);
  assertActivationPlan(plan, network);
  console.log(`Activation plan valid: ${planPath}`);
}

function retirementEntryId(role, index) {
  return `remove-superseded-${role}-${String(index + 1).padStart(2, "0")}`;
}

function retirementPlanEntry({
  id,
  chainId,
  expectedExecutor,
  archController,
  factory,
  label,
  removeFactoryRole,
  after,
}) {
  const functionSignature = removeFactoryRole
    ? "removeControllerFactory(address)"
    : "removeController(address)";
  const predicateSignature = removeFactoryRole
    ? "isRegisteredControllerFactory(address) view returns (bool)"
    : "isRegisteredController(address) view returns (bool)";
  return {
    id,
    kind: "call",
    to: archController,
    functionSignature,
    args: [factory],
    description: removeFactoryRole
      ? `Prevent the superseded hooks factory ${label} at ${factory} from re-registering as a controller.`
      : `Prevent the superseded hooks factory ${label} at ${factory} from registering new markets.`,
    envelope: {
      chainId,
      expectedExecutor,
      to: archController,
      value: "0",
      data: "functionSignature+args",
      gasLimitPolicy: "estimate*1.3",
      nonceCheck: "display-and-confirm",
    },
    predicate: {
      type: "callEq",
      target: archController,
      call: { sig: predicateSignature, args: [factory] },
      expect: false,
    },
    after,
  };
}

function retirementContext(args) {
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  if (!network) throw new Error("Missing --network or DEPLOYMENTS_NETWORK.");
  if (!/^[A-Za-z0-9_-]+$/.test(network)) {
    throw new Error("Network must contain only letters, digits, dashes, and underscores");
  }
  const inventoryPath = resolveInputPath({ ...args, network });
  const inventory = assertValidInventory(readInventory(inventoryPath), {
    network,
  });
  const deploymentsPath =
    optionalArg(args, "deployments") ||
    path.join("deployments", network, "deployments.json");
  const deployments = readJson(deploymentsPath);
  const archController = deployments.WildcatArchController;
  if (!isAddress(archController)) {
    throw new Error("deployments.json missing valid WildcatArchController");
  }
  const targets = getFactoryRetirementTargets(inventory);
  if (targets.length === 0) {
    throw new Error("No registered superseded hooks factories are available for retirement");
  }
  return {
    network,
    inventory,
    inventoryPath,
    deployments,
    deploymentsPath,
    archController,
    targets,
  };
}

function runRetirementEntries(args) {
  const context = retirementContext(args);
  const expectedExecutor = requireArg(args, "expected-executor");
  if (!isAddress(expectedExecutor)) {
    throw new Error("--expected-executor must be a valid address");
  }
  const outputDirectory = path.join(
    "deployments",
    context.network,
    "retirement-plan-entries"
  );
  fs.rmSync(outputDirectory, { recursive: true, force: true });
  fs.mkdirSync(outputDirectory, { recursive: true });

  let previousEntry = null;
  let sequence = 1;
  for (const [index, target] of context.targets.entries()) {
    const removeFactoryRoleId = retirementEntryId("controller-factory", index);
    const removeFactoryRole = retirementPlanEntry({
      id: removeFactoryRoleId,
      chainId: context.inventory.chainId,
      expectedExecutor,
      archController: context.archController,
      factory: target.factory,
      label: target.label,
      removeFactoryRole: true,
      after: previousEntry ? [previousEntry] : [],
    });
    writeJson(
      path.join(
        outputDirectory,
        `${String(sequence).padStart(2, "0")}-${removeFactoryRoleId}.json`
      ),
      removeFactoryRole
    );
    sequence += 1;

    const removeControllerId = retirementEntryId("controller", index);
    const removeController = retirementPlanEntry({
      id: removeControllerId,
      chainId: context.inventory.chainId,
      expectedExecutor,
      archController: context.archController,
      factory: target.factory,
      label: target.label,
      removeFactoryRole: false,
      after: [removeFactoryRoleId],
    });
    writeJson(
      path.join(
        outputDirectory,
        `${String(sequence).padStart(2, "0")}-${removeControllerId}.json`
      ),
      removeController
    );
    sequence += 1;
    previousEntry = removeControllerId;
  }

  console.log(`Retirement entries written: ${outputDirectory}`);
  console.log(
    `Retirement targets: ${context.targets.length} factories, ${context.targets.length * 2} calls`
  );
}

function assertRetirementPlan(plan, context) {
  if (plan.network !== context.network) {
    throw new Error(
      `Retirement plan network mismatch: expected ${context.network}, got ${plan.network}`
    );
  }
  if (typeof plan.release !== "string" || !plan.release.endsWith("-retirement")) {
    throw new Error("Retirement plan release must end with -retirement");
  }
  if (plan.transactions.some((transaction) => transaction.kind !== "call")) {
    throw new Error("Retirement plan must contain only calls");
  }

  const authorityHelper = authorizedHelperContext(
    context.network,
    context.deployments
  );
  const expectedTransactionCount = context.targets.length * 2;
  if (plan.transactions.length !== expectedTransactionCount) {
    throw new Error(
      `Expected ${expectedTransactionCount} retirement transactions, found ${plan.transactions.length}`
    );
  }
  if (
    authorityHelper &&
    addressKey(authorityHelper.archController) !==
      addressKey(context.archController)
  ) {
    throw new Error("Authority-helper ArchController does not match deployments.json");
  }
  assertAuthorizedHelperBoundary(plan, authorityHelper);
  assertFactoryDeactivationPlan(
    plan,
    context.targets,
    context.archController
  );
  for (const [index, target] of context.targets.entries()) {
    const removeFactoryRole = plan.transactions[index * 2];
    const removeController = plan.transactions[index * 2 + 1];
    const removeFactoryRoleCall = logicalCall(removeFactoryRole);
    const removeControllerCall = logicalCall(removeController);
    if (
      removeFactoryRole?.id !== retirementEntryId("controller-factory", index) ||
      removeFactoryRoleCall?.functionSignature !== "removeControllerFactory(address)" ||
      removeFactoryRoleCall.args?.length !== 1 ||
      !isAddress(removeFactoryRoleCall.args[0]) ||
      addressKey(removeFactoryRoleCall.args[0]) !== addressKey(target.factory) ||
      removeController?.id !== retirementEntryId("controller", index) ||
      removeControllerCall?.functionSignature !== "removeController(address)" ||
      removeControllerCall.args?.length !== 1 ||
      !isAddress(removeControllerCall.args[0]) ||
      addressKey(removeControllerCall.args[0]) !== addressKey(target.factory)
    ) {
      throw new Error(
        `Retirement plan must remove both roles for ${target.label} in the generated order`
      );
    }
  }
}

function runValidateRetirementPlan(args) {
  const context = retirementContext(args);
  const planPath = requireArg(args, "plan");
  const plan = readJson(planPath);
  assertRetirementPlan(plan, context);
  console.log(`Retirement plan valid: ${planPath}`);
  console.log(
    `Retirement targets: ${context.targets.length} factories, ${context.targets.length * 2} removal calls`
  );
}

async function runReconcile(args) {
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  if (!network) throw new Error("Missing --network or DEPLOYMENTS_NETWORK.");

  const inventoryPath = resolveInputPath(args);
  const rawInventory = readInventory(inventoryPath);
  const expectedChainId = networkNameToChainId(network) || rawInventory.chainId;
  if (!Number.isSafeInteger(expectedChainId) || expectedChainId <= 0) {
    throw new Error(
      `Could not determine reconcile chain id for network ${network}`
    );
  }
  const deploymentsPath =
    optionalArg(args, "deployments") ||
    path.join("deployments", network, "deployments.json");
  const handoffPath =
    optionalArg(args, "handoff") ||
    path.join("deployments", network, "rcf-v2-handoff.json");
  const outputPath =
    optionalArg(args, "output") ||
    path.join("deployments", network, "reconcile-report.json");
  const inventory = assertValidInventory(rawInventory, {
    network,
    chainId: expectedChainId,
  });
  const deployments = readJson(deploymentsPath);
  const handoff = readOptionalJson(handoffPath);
  const archController = deployments.WildcatArchController;
  if (!isAddress(archController)) {
    throw new Error("deployments.json missing valid WildcatArchController");
  }
  const rpcConfig = resolveRpcConfig(network, optionalArg(args, "rpc-url"));
  const rpc = createRpcClient(rpcConfig.url);
  const errors = [];
  const warnings = [];

  let actualChainId = null;
  let registry = {
    controllerFactories: [],
    controllers: [],
    registeredHooksFactories: [],
    factoryOnly: [],
    controllerOnly: [],
  };
  try {
    actualChainId = Number(BigInt(await rpc("eth_chainId")));
    if (actualChainId !== expectedChainId) {
      errors.push(
        `RPC chain id mismatch: expected ${expectedChainId}, got ${actualChainId}`
      );
    }
    registry = await reconcileRegistry({
      rpc,
      archController,
      inventory,
      errors,
    });
  } catch (error) {
    errors.push(`registry reconciliation failed: ${error.message}`);
  }

  const wrapperEntries = await reconcileWrappers({ rpc, inventory, errors });
  const indexedRecords = await reconcileIndexedRecords({
    rpc,
    inventory,
    errors,
  });
  const aliases = reconcileCanonicalAliases(inventory, deployments, handoff);
  errors.push(...aliases.errors);
  const handoffMarketLens = handoffMarketLensAddress(handoff);
  if (
    handoffMarketLens &&
    deployments.MarketLens &&
    deployments.MarketLens.toLowerCase() !== handoffMarketLens.toLowerCase()
  ) {
    warnings.push(
      `MarketLens alias (${deployments.MarketLens}) is newer than the handoff address (${handoffMarketLens}); expected between releases`
    );
  } else if (!handoffMarketLens && deployments.MarketLens) {
    warnings.push(
      "MarketLens canonical check skipped because no handoff marketLensLatest is available"
    );
  }

  const report = {
    schemaVersion: "1.0.0",
    generatedAt: new Date().toISOString(),
    network,
    expectedChainId,
    actualChainId,
    archController,
    rpcSource: rpcConfig.source,
    status: errors.length === 0 ? "green" : "red",
    errors,
    warnings,
    checks: {
      registry,
      wrappers: wrapperEntries,
      canonicalAliases: aliases.entries,
      indexedRecords,
    },
  };
  writeJson(outputPath, report);

  for (const warning of warnings) console.warn(`Warning: ${warning}`);
  for (const error of errors) console.error(`Error: ${error}`);
  console.log(`Reconcile ${report.status.toUpperCase()} for ${network}`);
  console.log(`Report: ${outputPath}`);
  if (errors.length > 0) process.exit(1);
}

function isRunStateReference(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.keys(value).length === 1 &&
    typeof value.$ref === "string"
  );
}

function resolveRunStateReferences(value, outputs) {
  if (isRunStateReference(value)) {
    const resolved = outputs.get(value.$ref);
    if (!resolved) {
      throw new Error(`Unresolved pending record $ref: ${value.$ref}`);
    }
    return resolved;
  }
  if (Array.isArray(value)) {
    return value.map((entry) => resolveRunStateReferences(entry, outputs));
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [
        key,
        resolveRunStateReferences(entry, outputs),
      ])
    );
  }
  return value;
}

function inferPlanPath(network, runStatePath, explicitPlanPath) {
  if (explicitPlanPath) return explicitPlanPath;
  const match = /^run-state-(.+)\.json$/.exec(path.basename(runStatePath));
  if (!match) {
    throw new Error(
      "Could not infer release from --run-state; provide --plan explicitly"
    );
  }
  return path.join("deployments", network, `plan-${match[1]}.json`);
}

function assertVerifiedRunState(plan, runState) {
  const planIds = new Set(
    plan.transactions.map((transaction) => transaction.id)
  );
  for (const transactionId of Object.keys(runState)) {
    if (!planIds.has(transactionId)) {
      throw new Error(
        `Run state contains unknown transaction id ${transactionId}`
      );
    }
  }
  for (const transaction of plan.transactions) {
    const state = runState[transaction.id];
    if (state?.status !== "verified") {
      throw new Error(`Run state entry ${transaction.id} is not verified`);
    }
    if (!isBytes32(state.txHash)) {
      throw new Error(`Run state entry ${transaction.id} has invalid txHash`);
    }
    if (!Number.isSafeInteger(state.blockNumber) || state.blockNumber <= 0) {
      throw new Error(
        `Run state entry ${transaction.id} has invalid blockNumber`
      );
    }
    if (transaction.kind === "deploy" && !isAddress(state.resolvedAddress)) {
      throw new Error(
        `Run state deployment ${transaction.id} has invalid resolvedAddress`
      );
    }
  }
}

function deploymentOutputsFromRunState(plan, runState) {
  const outputs = new Map();
  for (const transaction of plan.transactions) {
    if (transaction.kind === "deploy") {
      outputs.set(transaction.output, runState[transaction.id].resolvedAddress);
    }
  }
  return outputs;
}

function deploymentStateForPendingRecord(plan, runState, rawRecord, filePath) {
  if (!isRunStateReference(rawRecord.address)) {
    const isSupportedReuse =
      rawRecord.reused === true &&
      rawRecord.recordType === "deployment" &&
      (rawRecord.role === "identityRegistry" ||
        (rawRecord.role === "roleProviderFactory" &&
          rawRecord.providerKind === "ACCESS_LIST"));
    if (isSupportedReuse && isAddress(rawRecord.address)) return null;
    throw new Error(`${filePath}: pending address must be a plan $ref`);
  }
  const transaction = plan.transactions.find(
    (entry) =>
      entry.kind === "deploy" && entry.output === rawRecord.address.$ref
  );
  if (!transaction) {
    throw new Error(
      `${filePath}: no deployment transaction produces ${rawRecord.address.$ref}`
    );
  }
  return runState[transaction.id];
}

function assertNewInventoryRecord(inventory, collectionName, entry) {
  const existing = inventory[collectionName].find(
    (record) =>
      record.label === entry.label ||
      (isAddress(record.address) &&
        addressKey(record.address) === addressKey(entry.address))
  );
  if (existing) {
    throw new Error(
      `Append-only violation: ${collectionName} already contains ${entry.label} or ${entry.address}`
    );
  }
}

async function runApplyRun(args) {
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  if (!network) throw new Error("Missing --network or DEPLOYMENTS_NETWORK.");
  const runStatePath = requireArg(args, "run-state");
  const planPath = inferPlanPath(
    network,
    runStatePath,
    optionalArg(args, "plan")
  );
  const inventoryPath = resolveInputPath(args);
  const deploymentsPath =
    optionalArg(args, "deployments") ||
    path.join("deployments", network, "deployments.json");
  const plan = readJson(planPath);
  if (!Array.isArray(plan.transactions) || plan.network !== network) {
    throw new Error(`Plan ${planPath} does not belong to network ${network}`);
  }
  const releasePendingDirectory = path.join(
    "deployments",
    network,
    `inventory-pending-${plan.release}`
  );
  const legacyPendingDirectory = path.join(
    "deployments",
    network,
    "inventory-pending"
  );
  const pendingDirectory =
    optionalArg(args, "pending-directory") ||
    (fs.existsSync(releasePendingDirectory)
      ? releasePendingDirectory
      : legacyPendingDirectory);
  if (!fs.existsSync(pendingDirectory)) {
    throw new Error(
      `Pending inventory directory not found: ${pendingDirectory}`
    );
  }

  const runState = readJson(runStatePath);
  assertVerifiedRunState(plan, runState);
  const outputs = deploymentOutputsFromRunState(plan, runState);
  const pendingFiles = fs
    .readdirSync(pendingDirectory)
    .filter((fileName) => fileName.endsWith(".json"))
    .sort((left, right) => left.localeCompare(right));
  if (pendingFiles.length === 0) {
    throw new Error(
      `No pending inventory records found in ${pendingDirectory}`
    );
  }
  const pendingRecords = pendingFiles.map((fileName) => {
    const filePath = path.join(pendingDirectory, fileName);
    return { filePath, rawRecord: readJson(filePath) };
  });
  const reusedIdentityRecords = pendingRecords.filter(
    ({ rawRecord }) =>
      rawRecord.reused === true && rawRecord.role === "identityRegistry"
  );
  const reusedAccessListRecords = pendingRecords.filter(
    ({ rawRecord }) =>
      rawRecord.reused === true &&
      rawRecord.role === "roleProviderFactory" &&
      rawRecord.providerKind === "ACCESS_LIST"
  );
  if (
    reusedIdentityRecords.length > 1 ||
    reusedAccessListRecords.length > 1
  ) {
    throw new Error(
      "Pending inventory contains duplicate reused deployment records"
    );
  }

  let inventory = assertValidInventory(readInventory(inventoryPath), {
    network,
  });
  const deployments = readJson(deploymentsPath);
  for (const [records, deploymentKey] of [
    [reusedIdentityRecords, "WildcatBorrowerIdentityRegistry"],
    [reusedAccessListRecords, "AccessListRoleProviderFactory"],
  ]) {
    if (
      records.length === 1 &&
      (!isAddress(deployments[deploymentKey]) ||
        !isAddress(records[0].rawRecord.address) ||
        addressKey(deployments[deploymentKey]) !==
          addressKey(records[0].rawRecord.address))
    ) {
      throw new Error(
        `Reused ${deploymentKey} does not match its current deployment alias`
      );
    }
  }
  assertActivationPlan(plan, network, {
    reuseIdentityRegistry: reusedIdentityRecords.length === 1,
    reuseAccessListRoleProviderFactory: reusedAccessListRecords.length === 1,
  });
  const originalRecordCount = inventory.recordCount;
  let addedRecords = 0;
  let standardFactory = null;
  let revolvingFactory = null;
  let wrapperFactory = null;
  let marketLens = null;
  let borrowerIdentityRegistry = null;
  let accessListRoleProviderFactory = null;

  for (const { filePath, rawRecord } of pendingRecords) {
    if (
      rawRecord.network !== network ||
      rawRecord.chainId !== inventory.chainId
    ) {
      throw new Error(`${filePath}: network or chainId mismatch`);
    }
    const deployState = deploymentStateForPendingRecord(
      plan,
      runState,
      rawRecord,
      filePath
    );
    const record = resolveRunStateReferences(rawRecord, outputs);
    if (!isAddress(record.address)) {
      throw new Error(`${filePath}: resolved address is invalid`);
    }
    if (
      typeof record.deploymentKey !== "string" ||
      record.deploymentKey === ""
    ) {
      throw new Error(`${filePath}: deploymentKey is required`);
    }
    deployments[record.deploymentKey] = record.address;

    if (record.recordType === "hooksFactory") {
      if (!deployState) {
        throw new Error(
          `${filePath}: hooks factory must be deployed by the plan`
        );
      }
      const registerState = runState[record.registerEntryId];
      if (
        registerState?.status !== "verified" ||
        !isBytes32(registerState.txHash)
      ) {
        throw new Error(`${filePath}: registerEntryId is not verified`);
      }
      const entry = removeUndefinedFields({
        label: record.deploymentKey,
        marketType: record.marketType,
        address: record.address,
        startBlock: deployState.blockNumber,
        canonical: record.canonicalIntent === true,
        lifecycle: record.canonicalIntent === true ? "canonical" : "live",
        indexed: true,
        registered: true,
        deploymentKey: record.deploymentKey,
        deployTxHash: deployState.txHash,
        registerTxHash: registerState.txHash,
        wrapperFactory: record.wrapperFactory,
        initCodeStorage: record.initCodeStorage,
        initCodeHash: record.initCodeHash,
      });
      assertNewInventoryRecord(inventory, "hooksFactories", entry);
      inventory = upsertFactory(inventory, entry);
      addedRecords += 1;
      if (entry.marketType === "legacy") standardFactory = entry.address;
      if (entry.marketType === "revolving") revolvingFactory = entry.address;
      continue;
    }

    if (record.recordType === "wrapperFactory") {
      if (!deployState) {
        throw new Error(
          `${filePath}: wrapper factory must be deployed by the plan`
        );
      }
      const entry = {
        label: record.deploymentKey,
        address: record.address,
        startBlock: deployState.blockNumber,
        lifecycle: record.canonicalIntent === true ? "canonical" : "live",
        indexed: true,
        deployTxHash: deployState.txHash,
        v1Factory: record.v1Factory,
      };
      assertNewInventoryRecord(inventory, "wrapperFactories", entry);
      inventory = upsertWrapperFactory(inventory, entry);
      addedRecords += 1;
      wrapperFactory = entry.address;
      continue;
    }

    if (record.recordType === "deployment" && record.role === "facade") {
      marketLens = record.address;
    }
    if (
      record.recordType === "deployment" &&
      record.role === "identityRegistry"
    ) {
      borrowerIdentityRegistry = record.address;
    }
    if (
      record.recordType === "deployment" &&
      record.role === "roleProviderFactory" &&
      record.providerKind === "ACCESS_LIST"
    ) {
      accessListRoleProviderFactory = record.address;
    }
  }

  if (
    !standardFactory ||
    !revolvingFactory ||
    !wrapperFactory ||
    !marketLens ||
    !borrowerIdentityRegistry ||
    !accessListRoleProviderFactory
  ) {
    throw new Error(
      "Pending records must resolve standard/revolving hooks factories, wrapper factory, borrower identity registry, access-list role-provider factory, and MarketLens"
    );
  }
  if (addedRecords !== 3) {
    throw new Error(
      `Expected three append-only factory records, got ${addedRecords}`
    );
  }
  if (inventory.recordCount !== originalRecordCount + addedRecords) {
    throw new Error(
      `recordCount must grow from ${originalRecordCount} to ${
        originalRecordCount + addedRecords
      }; got ${inventory.recordCount}`
    );
  }

  deployments.HooksFactory = standardFactory;
  deployments.HooksFactoryRevolving = revolvingFactory;
  deployments.MarketLens = marketLens;
  deployments.Wildcat4626WrapperFactory = wrapperFactory;
  deployments.WildcatBorrowerIdentityRegistry = borrowerIdentityRegistry;
  deployments.AccessListRoleProviderFactory = accessListRoleProviderFactory;
  writeInventory(inventoryPath, inventory);
  writeJsonAtomic(deploymentsPath, deployments);
  console.log(
    `Applied ${addedRecords} append-only factory records; recordCount ${originalRecordCount} -> ${inventory.recordCount}`
  );
  console.log("Superseded hooks factories remain registered until the retirement ceremony");
  console.log(`Canonical aliases updated: ${deploymentsPath}`);

  await runReconcile({
    network,
    input: inventoryPath,
    deployments: deploymentsPath,
    handoff: optionalArg(args, "handoff"),
    output:
      optionalArg(args, "output") ||
      path.join("deployments", network, "reconcile-report.json"),
    "rpc-url": optionalArg(args, "rpc-url"),
  });
}

async function runApplyRetirement(args) {
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  if (!network) throw new Error("Missing --network or DEPLOYMENTS_NETWORK.");
  const runStatePath = requireArg(args, "run-state");
  const planPath = inferPlanPath(
    network,
    runStatePath,
    optionalArg(args, "plan")
  );
  const inventoryPath = resolveInputPath({ ...args, network });
  const deploymentsPath =
    optionalArg(args, "deployments") ||
    path.join("deployments", network, "deployments.json");
  const inventory = assertValidInventory(readInventory(inventoryPath), {
    network,
  });
  const deployments = readJson(deploymentsPath);
  const archController = deployments.WildcatArchController;
  if (!isAddress(archController)) {
    throw new Error("deployments.json missing valid WildcatArchController");
  }
  const plan = readJson(planPath);
  const runState = readJson(runStatePath);
  const targets = getPlanRetirementTargets(plan, inventory, archController);
  const context = {
    network,
    inventory,
    inventoryPath,
    deployments,
    deploymentsPath,
    archController,
    targets,
  };

  assertRetirementPlan(plan, context);
  assertVerifiedRunState(plan, runState);

  const planTargetKeys = new Set(targets.map((target) => addressKey(target.factory)));
  const unexpectedCurrentTargets = getFactoryRetirementTargets(inventory).filter(
    (target) => !planTargetKeys.has(addressKey(target.factory))
  );
  if (unexpectedCurrentTargets.length > 0) {
    throw new Error(
      `Retirement plan is stale; ${unexpectedCurrentTargets.length} registered superseded factories are missing`
    );
  }
  const registrationStates = new Set(
    targets.map((target) => {
      const entry = inventory.hooksFactories.find(
        (candidate) =>
          addressKey(candidate.address) === addressKey(target.factory)
      );
      return entry.registered;
    })
  );
  if (registrationStates.size !== 1) {
    throw new Error(
      "Retirement inventory is partially applied; reconcile it before retrying"
    );
  }
  if (registrationStates.has(true)) {
    recordFactoryDeactivations(inventory, targets);
    writeInventory(inventoryPath, inventory);
    console.log(
      `Recorded ${targets.length} superseded hooks factories as unregistered`
    );
  } else {
    console.log(
      `Retirement inventory already records ${targets.length} superseded hooks factories as unregistered`
    );
  }
  console.log("Canonical deployment aliases were not changed");

  await runReconcile({
    network,
    input: inventoryPath,
    deployments: deploymentsPath,
    handoff: optionalArg(args, "handoff"),
    output:
      optionalArg(args, "output") ||
      path.join("deployments", network, "reconcile-report.json"),
    "rpc-url": optionalArg(args, "rpc-url"),
  });
}

function runLint(args) {
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  if (!network) throw new Error("Missing --network or DEPLOYMENTS_NETWORK.");

  const inventoryPath = resolveInputPath(args);
  const deploymentsPath =
    optionalArg(args, "deployments") ||
    path.join("deployments", network, "deployments.json");
  const handoffPath =
    optionalArg(args, "handoff") ||
    path.join("deployments", network, "rcf-v2-handoff.json");
  const allowlistPath =
    optionalArg(args, "allowlist") ||
    path.join("deployments", "factory-inventory-lint-allowlist.json");

  const inventory = assertValidInventory(readInventory(inventoryPath), {
    network,
  });
  const deployments = readJson(deploymentsPath);
  const handoff = readOptionalJson(handoffPath);
  const allowlist = readJson(allowlistPath);
  const legacyKeys = allowlist.networks?.[network]?.legacyKeys || [];
  const result = lintDeployments({
    inventory,
    deployments,
    handoff,
    legacyKeys,
  });

  for (const warning of result.warnings) console.warn(`Warning: ${warning}`);
  for (const error of result.errors) console.error(`Error: ${error}`);
  if (!result.ok) process.exit(1);

  console.log(`Factory deployment lint passed for ${network}`);
}

function runValidate(args) {
  const inputPath = resolveInputPath(args);
  const inventory = readInventory(inputPath);
  const result = validateInventoryFile(inventory, inputPath, {
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
      `- ${marketType}: canonical=${
        canonical ? canonical.label : "<none>"
      } indexed=${indexed.length}`
    );
  }
  const canonicalWrapper = getCanonicalWrapperFactory(inventory);
  console.log(
    `- wrappers: canonical=${
      canonicalWrapper ? canonicalWrapper.label : "<none>"
    } indexed=${
      (inventory.wrapperFactories || []).filter(
        (entry) => entry.indexed === true
      ).length
    }`
  );
}

function runUpsert(args) {
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  const chainId = args["chain-id"]
    ? Number(args["chain-id"])
    : networkNameToChainId(network);
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

  const next = assertValidInventory(upsertFactory(inventory, factoryEntry), {
    network,
    chainId,
  });
  writeInventory(outputPath, next);
  console.log(`Inventory updated: ${outputPath}`);
}

function runUpsertWrapper(args) {
  const network = args.network || process.env.DEPLOYMENTS_NETWORK;
  const chainId = args["chain-id"]
    ? Number(args["chain-id"])
    : networkNameToChainId(network);
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

  const wrapperEntry = buildWrapperFactoryEntryFromArgs(args);
  const existing = findWrapperFactoryEntry(inventory, wrapperEntry);
  if (args["preserve-start-block"] === true && existing?.startBlock) {
    delete wrapperEntry.startBlock;
  }

  const next = assertValidInventory(
    upsertWrapperFactory(inventory, wrapperEntry),
    {
      network,
      chainId,
    }
  );
  writeInventory(outputPath, next);
  console.log(`Inventory updated: ${outputPath}`);
}

function runMigrate(args) {
  const inputPath = resolveInputPath(args);
  const outputPath = resolveOutputPath(args);
  const inventory = migrateInventory(readInventory(inputPath));
  writeInventory(outputPath, inventory);
  console.log(
    `Inventory migrated to ${INVENTORY_SCHEMA_VERSION}: ${outputPath}`
  );
}

async function main() {
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
  if (command === "upsert-wrapper" || command === "wrapper-upsert") {
    runUpsertWrapper(args);
    return;
  }
  if (command === "migrate") {
    runMigrate(args);
    return;
  }
  if (command === "lint") {
    runLint(args);
    return;
  }
  if (command === "reconcile") {
    await runReconcile(args);
    return;
  }
  if (command === "deactivation-targets") {
    runDeactivationTargets(args);
    return;
  }
  if (command === "retirement-entries") {
    runRetirementEntries(args);
    return;
  }
  if (command === "validate-activation-plan") {
    runValidateActivationPlan(args);
    return;
  }
  if (command === "validate-retirement-plan") {
    runValidateRetirementPlan(args);
    return;
  }
  if (command === "apply-run") {
    await runApplyRun(args);
    return;
  }
  if (command === "apply-retirement") {
    await runApplyRetirement(args);
    return;
  }

  throw new Error(`Unknown command: ${command}`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}

module.exports = {
  INVENTORY_FILE_NAME,
  INVENTORY_SCHEMA_VERSION,
  LEGACY_INVENTORY_SCHEMA_VERSION,
  DEFAULT_MARKET_TYPES,
  createInventory,
  getCanonicalFactory,
  getCanonicalWrapperFactory,
  getFactoryDeactivationTargets,
  getFactoryRetirementTargets,
  getPlanRetirementTargets,
  getIndexedFactories,
  inventoryPathForNetwork,
  migrateInventory,
  lintDeployments,
  assertFactoryDeactivationPlan,
  assertActivationPlan,
  assertRetirementPlan,
  reconcileCanonicalAliases,
  readInventory,
  readInventoryOrCreate,
  readJson,
  recordFactoryDeactivations,
  upsertFactory,
  upsertWrapperFactory,
  validateAppendOnly,
  validateInventory,
  validateInventoryFile,
  writeInventory,
  writeJson,
};
