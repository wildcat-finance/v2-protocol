#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const HANDOFF_SCHEMA_VERSION = "1.0.0";
const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;
const BYTES32_REGEX = /^0x[a-fA-F0-9]{64}$/;
const SAFE_PATH_SEGMENT_REGEX = /^[A-Za-z0-9_-]+$/;
const KNOWN_FLAGS = new Set([
  "network",
  "release",
  "inventory",
  "deployments",
  "run-state",
  "plan",
  "output-dir",
  "input",
  "check",
]);

const FACTORY_ARTIFACTS = {
  legacy: "src/IHooksFactory.sol:IHooksFactory",
  revolving: "src/IHooksFactoryRevolving.sol:IHooksFactoryRevolving",
  wrapper: "src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory",
  wrapperV1:
    "src/vault/Wildcat4626WrapperFactory.sol:IWildcat4626WrapperFactoryV1",
};

const RELEASE_CONTRACTS = [
  {
    key: "WildcatMarket_initCodeStorage",
    planOutput: "wildcat-market-init-code-storage",
    kind: "market-init-code-storage",
    forgeArtifactName: "script/common/DeployScriptBase.sol:InitCodeStorage",
    abiArtifactName: "src/market/WildcatMarket.sol:WildcatMarket",
  },
  {
    key: "HooksFactory",
    planOutput: "hooks-factory-standard",
    kind: "hooks-factory",
    forgeArtifactName: "src/HooksFactory.sol:HooksFactory",
    abiArtifactName: "src/IHooksFactory.sol:IHooksFactory",
  },
  {
    key: "WildcatMarketRevolving_initCodeStorage",
    planOutput: "wildcat-market-revolving-init-code-storage",
    kind: "market-init-code-storage",
    forgeArtifactName: "script/common/DeployScriptBase.sol:InitCodeStorage",
    abiArtifactName:
      "src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving",
  },
  {
    key: "HooksFactoryRevolving",
    planOutput: "hooks-factory-revolving",
    kind: "hooks-factory",
    forgeArtifactName: "src/HooksFactoryRevolving.sol:HooksFactoryRevolving",
    abiArtifactName: "src/IHooksFactoryRevolving.sol:IHooksFactoryRevolving",
  },
  {
    key: "MarketLensCore",
    planOutput: "market-lens-core",
    kind: "lens-helper-core",
    forgeArtifactName: "src/lens/MarketLensCore.sol:MarketLensCore",
    abiArtifactName: "src/lens/MarketLensCore.sol:MarketLensCore",
  },
  {
    key: "MarketLensAggregator",
    planOutput: "market-lens-aggregator",
    kind: "lens-helper-aggregator",
    forgeArtifactName: "src/lens/MarketLensAggregator.sol:MarketLensAggregator",
    abiArtifactName: "src/lens/MarketLensAggregator.sol:MarketLensAggregator",
  },
  {
    key: "MarketLensLive",
    planOutput: "market-lens-live",
    kind: "lens-helper-live",
    forgeArtifactName: "src/lens/MarketLensLive.sol:MarketLensLive",
    abiArtifactName: "src/lens/MarketLensLive.sol:MarketLensLive",
  },
  {
    key: "MarketLens",
    planOutput: "market-lens",
    kind: "lens-facade",
    forgeArtifactName: "src/lens/MarketLens.sol:MarketLens",
    abiArtifactName: "src/lens/MarketLens.sol:MarketLens",
  },
  {
    key: "Wildcat4626WrapperFactory",
    planOutput: "wildcat-4626-wrapper-factory",
    kind: "wrapper-factory",
    forgeArtifactName: FACTORY_ARTIFACTS.wrapper,
    abiArtifactName: FACTORY_ARTIFACTS.wrapper,
  },
  {
    key: "OpenTermHooks_initCodeStorage",
    planOutput: "open-term-hooks-init-code-storage",
    kind: "hooks-template-init-code-storage",
    forgeArtifactName: "script/common/DeployScriptBase.sol:InitCodeStorage",
    abiArtifactName: "src/access/OpenTermHooks.sol:OpenTermHooks",
  },
  {
    key: "FixedTermHooks_initCodeStorage",
    planOutput: "fixed-term-hooks-init-code-storage",
    kind: "hooks-template-init-code-storage",
    forgeArtifactName: "script/common/DeployScriptBase.sol:InitCodeStorage",
    abiArtifactName: "src/access/FixedTermHooks.sol:FixedTermHooks",
  },
  {
    key: "PeriodicTermHooks_initCodeStorage",
    planOutput: "periodic-term-hooks-init-code-storage",
    kind: "hooks-template-init-code-storage",
    forgeArtifactName: "script/common/DeployScriptBase.sol:InitCodeStorage",
    abiArtifactName: "src/access/PeriodicTermHooks.sol:PeriodicTermHooks",
  },
];

const ABI_CHANGES_SINCE_V2 = [
  {
    component: "WildcatMarket and WildcatMarketRevolving",
    artifactNames: [
      "src/market/WildcatMarket.sol:WildcatMarket",
      "src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving",
    ],
    changed: ["version() return value changed from '2' to '2.5'."],
    added: [
      "scaledTransferRounding() returns keccak256('scaleAmountDown').",
      "executePendingAnnualInterestBipsReduction() applies a matured hooks proposal.",
      "AprReductionNotReduction error.",
      "ExecutePendingAprReductionNotEnabled error.",
    ],
  },
  {
    component: "PeriodicTermHooks",
    artifactNames: ["src/access/PeriodicTermHooks.sol:PeriodicTermHooks"],
    changed: [],
    added: [
      "AnnualInterestBipsReductionProposed event.",
      "AnnualInterestBipsReductionProposalCancelled event.",
      "AnnualInterestBipsReductionExecuted event.",
      "AprReductionProposalDuringWithdrawalWindow error.",
      "AprReductionProposalNotReduction error.",
      "NoPendingAprChange error.",
      "AprChangeDoesNotMatchProposal error.",
      "AprChangeNotReady error.",
      "AprReductionProposalExpired error.",
      "AprReductionProposalOnClosedMarket error.",
      "UnpaidWithdrawalsExist error.",
      "templateVersion() returns 2; version() remains 'PeriodicTermHooks'.",
      "pendingAprChanges(address), getHookedMarket(address), getHookedMarkets(address[]), isWithdrawalWindowOpen(address), and getPendingAprChange(address) views.",
    ],
  },
  {
    component: "Access-control hook templates",
    artifactNames: [
      "src/access/OpenTermHooks.sol:OpenTermHooks",
      "src/access/FixedTermHooks.sol:FixedTermHooks",
      "src/access/PeriodicTermHooks.sol:PeriodicTermHooks",
    ],
    changed: [],
    added: [
      "isMarketTransferDisabled(address) reports the immutable per-market transfer policy.",
      "DepositHookNotEnabled error.",
    ],
  },
  {
    component: "MarketLens",
    artifactNames: [
      "src/lens/MarketLens.sol:MarketLens",
      "src/lens/MarketLensCore.sol:MarketLensCore",
      "src/lens/MarketLensAggregator.sol:MarketLensAggregator",
    ],
    changed: [
      "HooksConfigData return tuples append useOnExecutePendingAnnualInterestBipsReduction; consumers must regenerate ABI tuple decoders.",
    ],
    added: [],
  },
  {
    component: "Wildcat4626WrapperFactory",
    artifactNames: [
      "src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory",
    ],
    changed: [],
    added: [
      "MarketTransfersDisabled(address) error.",
      "UnsupportedMarketTransferPolicy(address,address) error.",
    ],
  },
  {
    component: "WildcatMarketRevolving",
    artifactNames: [
      "src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving",
      "src/interfaces/IWildcatMarketRevolving.sol:IWildcatMarketRevolving",
    ],
    changed: [],
    added: ["commitmentFeeBips() view.", "drawnAmount() view."],
  },
  {
    component: "Market event surface",
    artifactNames: [
      "src/interfaces/IMarketEventsAndErrors.sol:IMarketEventsAndErrors",
    ],
    changed: [],
    removed: ["SanctionedAccountAssetsSentToEscrow event."],
  },
];

function printUsage() {
  console.log(`Usage:
  node scripts/generate-handoff.js --network <name> --release <tag>
    [--inventory <path>] [--deployments <path>] [--run-state <path>]
    [--plan <path>] [--output-dir <path>]
  node scripts/generate-handoff.js --network <name> --release <tag> --check
    [--inventory <path>] [--deployments <path>] [--input <path>]

Defaults:
  --inventory   deployments/<network>/factory-inventory.json
  --deployments deployments/<network>/deployments.json
  --run-state   deployments/<network>/run-state-<release>.json (optional)
  --plan        deployments/<network>/plan-<release>.json
  --output-dir  deployments/<network>
  --input       deployments/<network>/handoff-<release>.json
`);
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--"))
      throw new Error(`Unexpected argument: ${token}`);
    const key = token.slice(2);
    if (!KNOWN_FLAGS.has(key)) throw new Error(`Unknown flag: --${key}`);
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      args[key] = true;
      continue;
    }
    args[key] = next;
    index += 1;
  }
  return args;
}

function requiredArg(args, name) {
  const value = args[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Missing --${name}.`);
  }
  return value;
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new Error(`Could not read JSON ${filePath}: ${error.message}`);
  }
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function writeText(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, value, "utf8");
}

function isAddress(value) {
  return typeof value === "string" && ADDRESS_REGEX.test(value);
}

function addressKey(value) {
  if (!isAddress(value)) throw new Error(`Invalid address: ${value}`);
  return value.toLowerCase();
}

function assertInventory(inventory, network) {
  if (inventory?.schemaVersion !== "1.1.0") {
    throw new Error("factory-inventory.json must use schemaVersion 1.1.0");
  }
  if (inventory.network !== network) {
    throw new Error(
      `Inventory network mismatch: expected ${network}, got ${inventory.network}`
    );
  }
  if (!Number.isSafeInteger(inventory.chainId) || inventory.chainId <= 0) {
    throw new Error("Inventory chainId must be a positive safe integer");
  }
  if (
    !Array.isArray(inventory.hooksFactories) ||
    !Array.isArray(inventory.wrapperFactories)
  ) {
    throw new Error(
      "Inventory must contain hooksFactories and wrapperFactories arrays"
    );
  }
  const records = [...inventory.hooksFactories, ...inventory.wrapperFactories];
  if (inventory.recordCount !== records.length) {
    throw new Error(
      `Inventory recordCount ${inventory.recordCount} does not equal ${records.length}`
    );
  }
  const seen = new Set();
  for (const record of records) {
    if (!isAddress(record.address))
      throw new Error(`Invalid inventory address for ${record.label}`);
    const key = addressKey(record.address);
    if (seen.has(key))
      throw new Error(`Duplicate inventory address: ${record.address}`);
    seen.add(key);
    if (!Number.isSafeInteger(record.startBlock) || record.startBlock < 0) {
      throw new Error(`Invalid startBlock for ${record.label}`);
    }
    if (!["canonical", "live", "retired"].includes(record.lifecycle)) {
      throw new Error(`Invalid lifecycle for ${record.label}`);
    }
    if (typeof record.indexed !== "boolean") {
      throw new Error(`Missing indexed boolean for ${record.label}`);
    }
    if (record.lifecycle === "retired" && record.indexed) {
      throw new Error(
        `Retired inventory record must not be indexed: ${record.label}`
      );
    }
  }
  return inventory;
}

function assertDeployments(deployments) {
  if (
    !deployments ||
    typeof deployments !== "object" ||
    Array.isArray(deployments)
  ) {
    throw new Error("deployments.json must be an object");
  }
  for (const [key, value] of Object.entries(deployments)) {
    if (!isAddress(value))
      throw new Error(`Invalid deployments.json address at ${key}`);
  }
  return deployments;
}

function canonicalRecord(records, description) {
  const matches = records.filter((record) => record.lifecycle === "canonical");
  if (matches.length !== 1) {
    throw new Error(
      `Expected exactly one canonical ${description}; found ${matches.length}`
    );
  }
  return matches[0];
}

function loadRunMetadata(planPath, runStatePath, network, release) {
  if (!fs.existsSync(runStatePath)) {
    return {
      plan: null,
      runState: null,
      byOutput: new Map(),
      byAddress: new Map(),
    };
  }
  if (!fs.existsSync(planPath)) {
    throw new Error(`Run-state exists but plan is missing: ${planPath}`);
  }
  const plan = readJson(planPath);
  const runState = readJson(runStatePath);
  if (plan.network !== network || plan.release !== release) {
    throw new Error(`Plan identity mismatch in ${planPath}`);
  }
  if (!Array.isArray(plan.transactions))
    throw new Error("Plan transactions must be an array");

  const byOutput = new Map();
  const byAddress = new Map();
  for (const transaction of plan.transactions) {
    const state = runState[transaction.id];
    if (!state) continue;
    if (state.status !== "verified") {
      throw new Error(`Run-state entry ${transaction.id} is not verified`);
    }
    if (!Number.isSafeInteger(state.blockNumber) || state.blockNumber <= 0) {
      throw new Error(
        `Run-state entry ${transaction.id} has invalid blockNumber`
      );
    }
    if (typeof state.txHash !== "string" || !BYTES32_REGEX.test(state.txHash)) {
      throw new Error(`Run-state entry ${transaction.id} has invalid txHash`);
    }
    if (transaction.kind !== "deploy") continue;
    if (!isAddress(state.resolvedAddress)) {
      throw new Error(
        `Run-state deployment ${transaction.id} has invalid resolvedAddress`
      );
    }
    const metadata = {
      transactionId: transaction.id,
      output: transaction.output,
      address: state.resolvedAddress,
      startBlock: state.blockNumber,
      txHash: state.txHash || null,
      forgeArtifactName: transaction.artifactName,
    };
    byOutput.set(transaction.output, metadata);
    byAddress.set(addressKey(state.resolvedAddress), metadata);
  }
  return { plan, runState, byOutput, byAddress };
}

function releaseDeployment(definition, release, deployments, runMetadata) {
  const deploymentKey = `${definition.key}_${release}`;
  const fromDeployments = deployments[deploymentKey];
  const fromRun = runMetadata.byOutput.get(definition.planOutput);
  const address = fromDeployments || fromRun?.address;
  if (!address) return null;
  if (!isAddress(address))
    throw new Error(`Invalid release address for ${deploymentKey}`);
  if (
    fromDeployments &&
    fromRun &&
    addressKey(fromDeployments) !== addressKey(fromRun.address)
  ) {
    throw new Error(`Run-state address mismatch for ${deploymentKey}`);
  }
  if (
    fromRun?.forgeArtifactName &&
    fromRun.forgeArtifactName !== definition.forgeArtifactName
  ) {
    throw new Error(
      `Plan artifact mismatch for ${deploymentKey}: expected ${definition.forgeArtifactName}, got ${fromRun.forgeArtifactName}`
    );
  }
  return {
    deploymentKey,
    kind: definition.kind,
    address,
    startBlock: fromRun?.startBlock ?? null,
    deployTxHash: fromRun?.txHash ?? null,
    forgeArtifactName: definition.forgeArtifactName,
    abiArtifactName: definition.abiArtifactName,
  };
}

function factoryGenerations(inventory, release) {
  const hooks = inventory.hooksFactories.map((record) => ({
    label: record.label,
    kind: "hooks-factory",
    marketType: record.marketType,
    address: record.address,
    startBlock: record.startBlock,
    lifecycle: record.lifecycle,
    canonical: record.canonical,
    registered: record.registered,
    indexAll: record.indexed,
    exclusionReason: record.indexed
      ? null
      : `inventory lifecycle is ${record.lifecycle}`,
    forgeArtifactName: FACTORY_ARTIFACTS[record.marketType],
  }));
  const wrappers = inventory.wrapperFactories.map((record) => ({
    label: record.label,
    kind: "wrapper-factory",
    marketType: null,
    address: record.address,
    startBlock: record.startBlock,
    lifecycle: record.lifecycle,
    canonical: record.lifecycle === "canonical",
    registered: null,
    indexAll: record.indexed,
    exclusionReason: record.indexed
      ? null
      : `inventory lifecycle is ${record.lifecycle}`,
    v1Factory: record.v1Factory,
    forgeArtifactName:
      record.v1Factory === null && !record.label.endsWith(`_${release}`)
        ? FACTORY_ARTIFACTS.wrapperV1
        : FACTORY_ARTIFACTS.wrapper,
  }));
  return [...hooks, ...wrappers];
}

function buildHandoff({
  network,
  release,
  inventoryPath,
  deploymentsPath,
  planPath,
  runStatePath,
}) {
  const inventory = assertInventory(readJson(inventoryPath), network);
  const deployments = assertDeployments(readJson(deploymentsPath));
  const runMetadata = loadRunMetadata(planPath, runStatePath, network, release);
  const standard = canonicalRecord(
    inventory.hooksFactories.filter((record) => record.marketType === "legacy"),
    "legacy hooks factory"
  );
  const revolving = canonicalRecord(
    inventory.hooksFactories.filter(
      (record) => record.marketType === "revolving"
    ),
    "revolving hooks factory"
  );
  const wrapper = canonicalRecord(
    inventory.wrapperFactories,
    "wrapper factory"
  );

  const releaseContracts = RELEASE_CONTRACTS.map((definition) =>
    releaseDeployment(definition, release, deployments, runMetadata)
  ).filter(Boolean);
  const generations = factoryGenerations(inventory, release);

  return {
    schemaVersion: HANDOFF_SCHEMA_VERSION,
    generatedAt: new Date().toISOString(),
    release,
    chain: { network, chainId: inventory.chainId },
    sources: {
      factoryInventory: inventoryPath,
      deployments: deploymentsPath,
      plan: runMetadata.plan ? planPath : null,
      runState: runMetadata.runState ? runStatePath : null,
    },
    canonicalAddresses: {
      archController: deployments.WildcatArchController || null,
      sanctionsSentinel: deployments.WildcatSanctionsSentinel || null,
      standardHooksFactory: standard.address,
      revolvingHooksFactory: revolving.address,
      marketLens: deployments.MarketLens || null,
      wrapperFactory: wrapper.address,
    },
    factoryGenerations: generations,
    releaseContracts,
    routing: {
      factories:
        "Use canonical lifecycle records for new deployments and SDK routing. Continue indexing every generation with indexAll=true. Do not index records with indexAll=false; they remain in the append-only inventory.",
      wrapper4626: {
        facade: wrapper.address,
        v1Factory: wrapper.v1Factory,
        behavior:
          "The canonical v2.5 facade serves locally recorded v2.5 floor-rounding markets. Markets without scaledTransferRounding() fall through to v1Factory when configured. Markets declaring an unsupported rounding do not fall through.",
      },
      lens: {
        facade: deployments.MarketLens || null,
        coreHelper: deployments.MarketLensCore || null,
        aggregationHelper: deployments.MarketLensAggregator || null,
        liveHelper: deployments.MarketLensLive || null,
        behavior:
          "Treat MarketLens as the public facade. It static-calls the core, aggregation, or live helper selected by the requested method; helper addresses are implementation contracts, not replacement facade addresses.",
      },
      canonicalVsLive:
        "Canonical means the generation selected for new deployments and current aliases. Live means an older generation that remains indexed for its existing markets. Retired generations stay recorded but are excluded from indexing.",
    },
    abiChangesSinceDeployedV2: ABI_CHANGES_SINCE_V2,
  };
}

function validateHandoff(
  handoff,
  inventory,
  deployments,
  expectedNetwork,
  expectedRelease
) {
  const errors = [];
  if (handoff?.schemaVersion !== HANDOFF_SCHEMA_VERSION) {
    errors.push(`schemaVersion must be ${HANDOFF_SCHEMA_VERSION}`);
  }
  if (handoff?.release !== expectedRelease)
    errors.push(`release must be ${expectedRelease}`);
  if (handoff?.chain?.network !== expectedNetwork) {
    errors.push(`chain.network must be ${expectedNetwork}`);
  }
  if (handoff?.chain?.chainId !== inventory.chainId) {
    errors.push(`chain.chainId must be ${inventory.chainId}`);
  }
  if (!Array.isArray(handoff?.factoryGenerations)) {
    errors.push("factoryGenerations must be an array");
  } else {
    const inventoryRecords = [
      ...inventory.hooksFactories,
      ...inventory.wrapperFactories,
    ];
    if (handoff.factoryGenerations.length !== inventoryRecords.length) {
      errors.push(
        "factoryGenerations must include every inventory factory record"
      );
    }
    const inventoryByAddress = new Map(
      inventoryRecords.map((record) => [addressKey(record.address), record])
    );
    for (const generation of handoff.factoryGenerations) {
      if (!isAddress(generation.address)) {
        errors.push(
          `factory generation ${generation.label} has an invalid address`
        );
        continue;
      }
      const record = inventoryByAddress.get(addressKey(generation.address));
      if (!record) {
        errors.push(
          `factory generation ${generation.label} address is absent from inventory`
        );
        continue;
      }
      if (generation.startBlock !== record.startBlock) {
        errors.push(
          `factory generation ${generation.label} startBlock differs from inventory`
        );
      }
      if (
        generation.lifecycle !== record.lifecycle ||
        generation.indexAll !== record.indexed
      ) {
        errors.push(
          `factory generation ${generation.label} lifecycle/indexAll differs from inventory`
        );
      }
      if (typeof generation.forgeArtifactName !== "string") {
        errors.push(
          `factory generation ${generation.label} lacks forgeArtifactName`
        );
      }
    }
  }
  if (!Array.isArray(handoff?.releaseContracts)) {
    errors.push("releaseContracts must be an array");
  } else {
    const deploymentAddresses = new Set(
      Object.values(deployments).map(addressKey)
    );
    for (const contract of handoff.releaseContracts) {
      if (!isAddress(contract.address)) {
        errors.push(
          `release contract ${contract.deploymentKey} has an invalid address`
        );
      } else if (!deploymentAddresses.has(addressKey(contract.address))) {
        errors.push(
          `release contract ${contract.deploymentKey} address is absent from deployments.json`
        );
      }
      if (
        contract.startBlock !== null &&
        (!Number.isSafeInteger(contract.startBlock) || contract.startBlock <= 0)
      ) {
        errors.push(
          `release contract ${contract.deploymentKey} has an invalid startBlock`
        );
      }
      if (!contract.forgeArtifactName || !contract.abiArtifactName) {
        errors.push(
          `release contract ${contract.deploymentKey} lacks an artifact name`
        );
      }
    }
  }
  if (
    !Array.isArray(handoff?.abiChangesSinceDeployedV2) ||
    handoff.abiChangesSinceDeployedV2.length === 0
  ) {
    errors.push("abiChangesSinceDeployedV2 must be a nonempty array");
  }
  for (const [name, value] of Object.entries(
    handoff?.canonicalAddresses || {}
  )) {
    if (value !== null && !isAddress(value))
      errors.push(`canonicalAddresses.${name} is invalid`);
  }
  const canonicalHooks = inventory.hooksFactories.filter(
    (record) => record.lifecycle === "canonical"
  );
  const expectedCanonical = {
    archController: deployments.WildcatArchController || null,
    sanctionsSentinel: deployments.WildcatSanctionsSentinel || null,
    standardHooksFactory:
      canonicalHooks.find((record) => record.marketType === "legacy")
        ?.address || null,
    revolvingHooksFactory:
      canonicalHooks.find((record) => record.marketType === "revolving")
        ?.address || null,
    marketLens: deployments.MarketLens || null,
    wrapperFactory:
      inventory.wrapperFactories.find(
        (record) => record.lifecycle === "canonical"
      )?.address || null,
  };
  for (const [name, expected] of Object.entries(expectedCanonical)) {
    const actual = handoff?.canonicalAddresses?.[name] ?? null;
    if (
      actual !== expected &&
      (!isAddress(actual) ||
        !isAddress(expected) ||
        addressKey(actual) !== addressKey(expected))
    ) {
      errors.push(`canonicalAddresses.${name} differs from source files`);
    }
  }
  if (
    typeof handoff?.routing?.factories !== "string" ||
    typeof handoff?.routing?.wrapper4626?.behavior !== "string" ||
    typeof handoff?.routing?.lens?.behavior !== "string" ||
    typeof handoff?.routing?.canonicalVsLive !== "string"
  ) {
    errors.push("routing prose is incomplete");
  }
  return errors;
}

function markdownCell(value) {
  if (value === null || value === undefined) return "-";
  return String(value).replace(/\|/g, "\\|");
}

function renderMarkdown(handoff) {
  const lines = [
    `# Wildcat ${handoff.release} handoff — ${handoff.chain.network}`,
    "",
    `Chain ID: \`${handoff.chain.chainId}\`. Generated: \`${handoff.generatedAt}\`.`,
    "",
    "## Factory indexing",
    "",
    "| Label | Kind | Market type | Address | Start block | Lifecycle | Index all | ABI artifact |",
    "| --- | --- | --- | --- | ---: | --- | --- | --- |",
  ];
  for (const generation of handoff.factoryGenerations) {
    lines.push(
      `| ${markdownCell(generation.label)} | ${markdownCell(
        generation.kind
      )} | ${markdownCell(generation.marketType)} | \`${
        generation.address
      }\` | ${generation.startBlock} | ${generation.lifecycle} | ${
        generation.indexAll ? "yes" : "no"
      } | \`${generation.forgeArtifactName}\` |`
    );
  }

  lines.push("", "## Routing", "");
  lines.push(`- ${handoff.routing.factories}`);
  lines.push(`- 4626: ${handoff.routing.wrapper4626.behavior}`);
  lines.push(`- Lens: ${handoff.routing.lens.behavior}`);
  lines.push(`- Lifecycle: ${handoff.routing.canonicalVsLive}`);

  lines.push("", "## Release contracts", "");
  lines.push(
    "| Deployment key | Kind | Address | Start block | ABI artifact |"
  );
  lines.push("| --- | --- | --- | ---: | --- |");
  if (handoff.releaseContracts.length === 0) {
    lines.push("| _No release-labelled deployments found_ | - | - | - | - |");
  } else {
    for (const contract of handoff.releaseContracts) {
      lines.push(
        `| ${contract.deploymentKey} | ${contract.kind} | \`${
          contract.address
        }\` | ${markdownCell(contract.startBlock)} | \`${
          contract.abiArtifactName
        }\` |`
      );
    }
  }

  lines.push("", "## ABI changes since deployed v2", "");
  for (const change of handoff.abiChangesSinceDeployedV2) {
    lines.push(`### ${change.component}`, "");
    for (const entry of change.changed || []) lines.push(`- Changed: ${entry}`);
    for (const entry of change.added || []) lines.push(`- Added: ${entry}`);
    for (const entry of change.removed || []) lines.push(`- Removed: ${entry}`);
    lines.push("");
  }
  return `${lines.join("\n").trim()}\n`;
}

function pathsFor(args, network, release) {
  const networkDir = path.join("deployments", network);
  const outputDir = args["output-dir"] || networkDir;
  return {
    inventoryPath:
      args.inventory || path.join(networkDir, "factory-inventory.json"),
    deploymentsPath:
      args.deployments || path.join(networkDir, "deployments.json"),
    runStatePath:
      args["run-state"] || path.join(networkDir, `run-state-${release}.json`),
    planPath: args.plan || path.join(networkDir, `plan-${release}.json`),
    jsonPath: args.input || path.join(outputDir, `handoff-${release}.json`),
    markdownPath: path.join(outputDir, `handoff-${release}.md`),
  };
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv.includes("--help") || argv.includes("-h")) {
    printUsage();
    return;
  }
  const args = parseArgs(argv);
  const network = requiredArg(args, "network");
  const release = requiredArg(args, "release");
  if (!SAFE_PATH_SEGMENT_REGEX.test(network)) {
    throw new Error(
      "--network must contain only letters, digits, dashes, and underscores"
    );
  }
  if (!SAFE_PATH_SEGMENT_REGEX.test(release)) {
    throw new Error(
      "--release must contain only letters, digits, dashes, and underscores"
    );
  }
  const paths = pathsFor(args, network, release);
  const inventory = assertInventory(readJson(paths.inventoryPath), network);
  const deployments = assertDeployments(readJson(paths.deploymentsPath));

  if (args.check === true) {
    const handoff = readJson(paths.jsonPath);
    const errors = validateHandoff(
      handoff,
      inventory,
      deployments,
      network,
      release
    );
    if (!fs.existsSync(paths.markdownPath)) {
      errors.push(`Markdown companion is missing: ${paths.markdownPath}`);
    } else {
      const markdown = fs.readFileSync(paths.markdownPath, "utf8");
      if (!markdown.startsWith(`# Wildcat ${release} handoff`)) {
        errors.push("Markdown companion has an invalid title");
      }
      for (const generation of handoff.factoryGenerations || []) {
        if (!markdown.includes(generation.label)) {
          errors.push(`Markdown companion omits factory ${generation.label}`);
        }
      }
    }
    if (errors.length > 0) {
      for (const error of errors) console.error(`Error: ${error}`);
      process.exitCode = 1;
      return;
    }
    console.log(`Handoff valid: ${paths.jsonPath}`);
    console.log(
      `Factory inventory addresses verified: ${handoff.factoryGenerations.length}`
    );
    console.log(`Markdown companion present: ${paths.markdownPath}`);
    return;
  }

  const handoff = buildHandoff({ network, release, ...paths });
  const errors = validateHandoff(
    handoff,
    inventory,
    deployments,
    network,
    release
  );
  if (errors.length > 0) throw new Error(errors.join("\n"));
  writeJson(paths.jsonPath, handoff);
  writeText(paths.markdownPath, renderMarkdown(handoff));
  console.log(`Handoff written: ${paths.jsonPath}`);
  console.log(`Markdown written: ${paths.markdownPath}`);
  console.log(`Factory generations: ${handoff.factoryGenerations.length}`);
  console.log(`Release contracts: ${handoff.releaseContracts.length}`);
}

try {
  main();
} catch (error) {
  console.error(error.message || error);
  process.exit(1);
}
