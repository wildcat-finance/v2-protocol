#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync, spawnSync } = require("child_process");
const { Contract, JsonRpcProvider, getAddress, keccak256 } = require("ethers");
const { validatePlan } = require("./plan");

process.env.FOUNDRY_PROFILE = "deploy";

const REPO_ROOT = path.resolve(__dirname, "..");
const PACKAGE_PATH = path.join(REPO_ROOT, "package.json");
const CONFIG_PATH = path.join(
  REPO_ROOT,
  "deployments/sepolia/v2-5-sepolia-fix-1.json"
);
const PREVIOUS_PLAN_PATH = path.join(
  REPO_ROOT,
  "deployments/sepolia/plan-v2-5.json"
);
const DEFAULT_RPC_URL = "https://eth-sep.hinterlight.net";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const AUTHORITY_HELPER_FORWARD_SIGNATURE =
  "executeProtocolAction(address,bytes)";

const ARTIFACTS = {
  wrapperFactory: {
    artifactName:
      "src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory",
    source: "src/vault/Wildcat4626WrapperFactory.sol",
    contract: "Wildcat4626WrapperFactory",
    previousId: "deploy-wildcat-4626-wrapper-factory",
    previousAddressKey: "wrapperFactory",
    decision: "replace",
    reason: "embeds the corrected Wildcat4626Wrapper creation code",
  },
  identityRegistry: {
    artifactName:
      "src/WildcatBorrowerIdentityRegistry.sol:WildcatBorrowerIdentityRegistry",
    source: "src/WildcatBorrowerIdentityRegistry.sol",
    contract: "WildcatBorrowerIdentityRegistry",
    previousId: "deploy-borrower-identity-registry",
    decision: "reuse",
    reason: "bytecode and bindings are unchanged",
  },
  accessListFactory: {
    artifactName:
      "src/providers/AccessListRoleProviderFactory.sol:AccessListRoleProviderFactory",
    source: "src/providers/AccessListRoleProviderFactory.sol",
    contract: "AccessListRoleProviderFactory",
    previousId: "deploy-access-list-role-provider-factory",
    decision: "reuse",
    reason: "bytecode and bindings are unchanged",
  },
  standardMarket: {
    source: "src/market/WildcatMarket.sol",
    contract: "WildcatMarket",
    previousId: "deploy-wildcat-market-init-code-storage",
    previousAddressKey: "standardMarketInitCodeStorage",
    storedInitCode: true,
    decision: "replace",
    reason: "contains the delinquency and protocol-fee corrections",
  },
  standardFactory: {
    artifactName: "src/HooksFactory.sol:HooksFactory",
    source: "src/HooksFactory.sol",
    contract: "HooksFactory",
    previousId: "deploy-hooks-factory-standard",
    previousAddressKey: "standardHooksFactory",
    decision: "replace",
    reason: "must bind the replacement wrapper and standard market store",
  },
  revolvingMarket: {
    source: "src/market/WildcatMarketRevolving.sol",
    contract: "WildcatMarketRevolving",
    previousId: "deploy-wildcat-market-revolving-init-code-storage",
    previousAddressKey: "revolvingMarketInitCodeStorage",
    storedInitCode: true,
    decision: "replace",
    reason: "contains the revolving delinquency and protocol-fee corrections",
  },
  revolvingFactory: {
    artifactName: "src/HooksFactoryRevolving.sol:HooksFactoryRevolving",
    source: "src/HooksFactoryRevolving.sol",
    contract: "HooksFactoryRevolving",
    previousId: "deploy-hooks-factory-revolving",
    previousAddressKey: "revolvingHooksFactory",
    decision: "replace",
    reason: "must bind the replacement wrapper and revolving market store",
  },
  marketLensCore: {
    artifactName: "src/lens/MarketLensCore.sol:MarketLensCore",
    source: "src/lens/MarketLensCore.sol",
    contract: "MarketLensCore",
    previousId: "deploy-market-lens-core",
    previousAddressKey: "marketLensCore",
    decision: "replace",
    reason: "immutably binds the standard hooks factory",
  },
  marketLensAggregator: {
    artifactName: "src/lens/MarketLensAggregator.sol:MarketLensAggregator",
    source: "src/lens/MarketLensAggregator.sol",
    contract: "MarketLensAggregator",
    previousId: "deploy-market-lens-aggregator",
    previousAddressKey: "marketLensAggregator",
    decision: "replace",
    reason: "immutably binds the standard hooks factory",
  },
  marketLensLive: {
    artifactName: "src/lens/MarketLensLive.sol:MarketLensLive",
    source: "src/lens/MarketLensLive.sol",
    contract: "MarketLensLive",
    previousId: "deploy-market-lens-live",
    previousAddressKey: "marketLensLive",
    decision: "replace",
    reason: "immutably binds the standard hooks factory",
  },
  marketLens: {
    artifactName: "src/lens/MarketLens.sol:MarketLens",
    source: "src/lens/MarketLens.sol",
    contract: "MarketLens",
    previousId: "deploy-market-lens",
    previousAddressKey: "marketLens",
    decision: "replace",
    reason:
      "immutably binds the standard hooks factory and replacement helpers",
  },
  openTermHooks: {
    source: "src/access/OpenTermHooks.sol",
    contract: "OpenTermHooks",
    previousId: "deploy-open-term-hooks-init-code-storage",
    previousAddressKey: "openTermHooksInitCodeStorage",
    storedInitCode: true,
    decision: "replace",
    reason: "inherits the corrected transfer-recipient policy",
  },
  fixedTermHooks: {
    source: "src/access/FixedTermHooks.sol",
    contract: "FixedTermHooks",
    previousId: "deploy-fixed-term-hooks-init-code-storage",
    previousAddressKey: "fixedTermHooksInitCodeStorage",
    storedInitCode: true,
    decision: "replace",
    reason: "inherits the corrected transfer-recipient policy",
  },
  periodicTermHooks: {
    source: "src/access/PeriodicTermHooks.sol",
    contract: "PeriodicTermHooks",
    previousId: "deploy-periodic-term-hooks-init-code-storage",
    previousAddressKey: "periodicTermHooksInitCodeStorage",
    storedInitCode: true,
    decision: "replace",
    reason: "inherits the corrected transfer-recipient policy",
  },
};

const EXPECTED_IDS = [
  "deploy-wildcat-4626-wrapper-factory",
  "deploy-wildcat-market-init-code-storage",
  "deploy-hooks-factory-standard",
  "deploy-wildcat-market-revolving-init-code-storage",
  "deploy-hooks-factory-revolving",
  "deploy-market-lens-core",
  "deploy-market-lens-aggregator",
  "deploy-market-lens-live",
  "deploy-market-lens",
  "deploy-open-term-hooks-init-code-storage",
  "deploy-fixed-term-hooks-init-code-storage",
  "deploy-periodic-term-hooks-init-code-storage",
  "register-controller-factory-standard",
  "register-controller-factory-revolving",
  "add-standard-open-term-template",
  "add-standard-fixed-term-template",
  "add-standard-periodic-term-template",
  "add-revolving-open-term-template",
  "add-revolving-fixed-term-template",
  "add-revolving-periodic-term-template",
  "register-hooks-factory-standard",
  "register-hooks-factory-revolving",
];

function usage() {
  console.log(`Usage:
  node scripts/sepolia-v2-5-fix-rotation.js generate
  node scripts/sepolia-v2-5-fix-rotation.js validate
  node scripts/sepolia-v2-5-fix-rotation.js preflight [--rpc-url <url>] [--out <path>]
  node scripts/sepolia-v2-5-fix-rotation.js verify-activation
    --run-state <path> [--preflight <path>] [--rpc-url <url>] [--out <path>]

All commands are read-only with respect to Sepolia. generate writes local plan
artifacts and never signs or broadcasts a transaction.`);
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--"))
      throw new Error(`Unexpected argument: ${token}`);
    const key = token.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      args[key] = true;
    } else {
      args[key] = value;
      index += 1;
    }
  }
  return args;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function config() {
  const value = readJson(CONFIG_PATH);
  const protocolVersion = readJson(PACKAGE_PATH).version;
  if (
    value.schemaVersion !== "1.0.0" ||
    value.network !== "sepolia" ||
    value.chainId !== 11155111 ||
    typeof value.release !== "string" ||
    !/^[A-Za-z0-9_-]+$/.test(value.release) ||
    !/^[0-9a-f]{40}$/.test(value.contractSourceCommit) ||
    typeof protocolVersion !== "string" ||
    !/^\d+\.\d+\.\d+$/.test(protocolVersion) ||
    value.authorityPolicy !== "fixed"
  ) {
    throw new Error(
      `Invalid factory-replacement config: ${path.relative(
        REPO_ROOT,
        CONFIG_PATH
      )}`
    );
  }
  for (const address of [
    value.expectedExecutor,
    ...Object.values(value.authority),
    ...Object.values(value.reused),
    ...Object.values(value.superseded),
    value.templateFees.feeRecipient,
    value.templateFees.originationFeeAsset,
    ...value.retirementTargets,
  ]) {
    if (getAddress(address) !== address) {
      throw new Error(
        `Factory-replacement config address is not checksummed: ${address}`
      );
    }
  }
  assertEqual(
    value.retirementTargets,
    [
      value.superseded.standardHooksFactory,
      value.superseded.revolvingHooksFactory,
    ],
    "Retirement targets"
  );
  return { ...value, protocolVersion };
}

function git(...args) {
  return execFileSync("git", args, {
    cwd: REPO_ROOT,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}

function assertContractSourceBoundary(rotation) {
  git("cat-file", "-e", `${rotation.contractSourceCommit}^{commit}`);
  const tracked = spawnSync(
    "git",
    [
      "diff",
      "--quiet",
      rotation.contractSourceCommit,
      "--",
      "src",
      "lib",
      "foundry.toml",
      "remappings.txt",
    ],
    { cwd: REPO_ROOT }
  );
  if (tracked.status !== 0) {
    throw new Error(
      `Contract source differs from frozen commit ${rotation.contractSourceCommit}`
    );
  }
  const untracked = git(
    "status",
    "--porcelain",
    "--untracked-files=all",
    "--",
    "src",
    "lib",
    "foundry.toml",
    "remappings.txt"
  );
  if (untracked) {
    throw new Error(`Contract source boundary is dirty:\n${untracked}`);
  }
}

function artifactPath(source, contract) {
  return path.join(
    REPO_ROOT,
    "deploy-out",
    path.basename(source),
    `${contract}.json`
  );
}

function loadDeployArtifact(source, contract) {
  const filePath = artifactPath(source, contract);
  if (!fs.existsSync(filePath)) {
    throw new Error(
      `Missing deploy artifact: ${path.relative(REPO_ROOT, filePath)}`
    );
  }
  const artifact = readJson(filePath);
  const metadata =
    typeof artifact.metadata === "string"
      ? JSON.parse(artifact.metadata)
      : artifact.metadata;
  const target = metadata.settings?.compilationTarget || {};
  if (
    metadata.compiler?.version !== "0.8.25+commit.b61c2a91" ||
    metadata.settings?.optimizer?.enabled !== true ||
    metadata.settings?.optimizer?.runs !== 44 ||
    metadata.settings?.viaIR !== true ||
    metadata.settings?.evmVersion !== "cancun" ||
    target[source] !== contract
  ) {
    throw new Error(
      `${path.relative(
        REPO_ROOT,
        filePath
      )} is not a canonical deploy-profile artifact`
    );
  }
  for (const [sourceName, sourceMetadata] of Object.entries(
    metadata.sources || {}
  )) {
    const sourcePath = path.join(REPO_ROOT, sourceName);
    if (!fs.existsSync(sourcePath)) {
      throw new Error(`Artifact source is missing: ${sourceName}`);
    }
    const actualHash = keccak256(fs.readFileSync(sourcePath));
    if (actualHash.toLowerCase() !== sourceMetadata.keccak256?.toLowerCase()) {
      throw new Error(`Deploy artifact is stale for ${sourceName}`);
    }
  }
  const bytecode = artifact.bytecode?.object;
  if (typeof bytecode !== "string" || !/^0x[0-9a-fA-F]+$/.test(bytecode)) {
    throw new Error(
      `Invalid creation bytecode in ${path.relative(REPO_ROOT, filePath)}`
    );
  }
  return { artifact, bytecode };
}

function loadArtifacts() {
  return Object.fromEntries(
    Object.entries(ARTIFACTS).map(([key, definition]) => [
      key,
      {
        ...definition,
        ...loadDeployArtifact(definition.source, definition.contract),
      },
    ])
  );
}

function ref(output) {
  return { $ref: output };
}

function envelope(rotation, to, kind) {
  return {
    chainId: rotation.chainId,
    expectedExecutor: rotation.expectedExecutor,
    to: kind === "deploy" ? null : to,
    value: "0",
    data:
      kind === "deploy" ? "initCode+constructorArgs" : "functionSignature+args",
    gasLimitPolicy: "estimate*1.3",
    nonceCheck: "display-and-confirm",
  };
}

function deploy(rotation, values) {
  return {
    id: values.id,
    kind: "deploy",
    artifactName: values.artifactName,
    constructorArgs: { decoded: values.args },
    output: values.output,
    description: values.description,
    envelope: envelope(rotation, null, "deploy"),
    predicate: values.predicate,
    after: values.after ? [values.after] : [],
  };
}

function call(rotation, values) {
  return {
    id: values.id,
    kind: "call",
    to: values.to,
    functionSignature: values.signature,
    args: values.args,
    description: values.description,
    envelope: envelope(rotation, values.to, "call"),
    predicate: values.predicate,
    after: [values.after],
  };
}

function codePresent(output) {
  return { type: "codePresent", target: ref(output) };
}

function callEq(target, sig, args, expect) {
  return { type: "callEq", target, call: { sig, args }, expect };
}

function buildEntries(rotation, artifacts) {
  const initCodeStorage = "script/common/DeployScriptBase.sol:InitCodeStorage";
  const standardMarketHash = keccak256(artifacts.standardMarket.bytecode);
  const revolvingMarketHash = keccak256(artifacts.revolvingMarket.bytecode);
  const fees = rotation.templateFees;
  const versionLabel = `v${rotation.protocolVersion}`;
  const entries = [];

  entries.push(
    deploy(rotation, {
      id: EXPECTED_IDS[0],
      artifactName: ARTIFACTS.wrapperFactory.artifactName,
      args: [
        rotation.authority.archController,
        rotation.reused.v1WrapperFactory,
      ],
      output: "wildcat-4626-wrapper-factory",
      description: `Deploy the corrected Sepolia ${versionLabel} ERC-4626 wrapper factory.`,
      predicate: callEq(
        ref("wildcat-4626-wrapper-factory"),
        "v1Factory() view returns (address)",
        [],
        rotation.reused.v1WrapperFactory
      ),
    })
  );
  entries.push(
    deploy(rotation, {
      id: EXPECTED_IDS[1],
      artifactName: initCodeStorage,
      args: [artifacts.standardMarket.bytecode],
      output: "wildcat-market-init-code-storage",
      description: `Deploy the corrected Sepolia ${versionLabel} WildcatMarket init-code store.`,
      predicate: codePresent("wildcat-market-init-code-storage"),
      after: EXPECTED_IDS[0],
    })
  );
  entries.push(
    deploy(rotation, {
      id: EXPECTED_IDS[2],
      artifactName: ARTIFACTS.standardFactory.artifactName,
      args: [
        rotation.authority.archController,
        rotation.authority.sanctionsSentinel,
        ref("wildcat-4626-wrapper-factory"),
        ref("wildcat-market-init-code-storage"),
        standardMarketHash,
        rotation.reused.borrowerIdentityRegistry,
      ],
      output: "hooks-factory-standard",
      description: `Deploy the replacement Sepolia ${versionLabel} standard hooks factory.`,
      predicate: callEq(
        ref("hooks-factory-standard"),
        "marketInitCodeStorage() view returns (address)",
        [],
        ref("wildcat-market-init-code-storage")
      ),
      after: EXPECTED_IDS[1],
    })
  );
  entries.push(
    deploy(rotation, {
      id: EXPECTED_IDS[3],
      artifactName: initCodeStorage,
      args: [artifacts.revolvingMarket.bytecode],
      output: "wildcat-market-revolving-init-code-storage",
      description: `Deploy the corrected Sepolia ${versionLabel} WildcatMarketRevolving init-code store.`,
      predicate: codePresent("wildcat-market-revolving-init-code-storage"),
      after: EXPECTED_IDS[2],
    })
  );
  entries.push(
    deploy(rotation, {
      id: EXPECTED_IDS[4],
      artifactName: ARTIFACTS.revolvingFactory.artifactName,
      args: [
        rotation.authority.archController,
        rotation.authority.sanctionsSentinel,
        ref("wildcat-4626-wrapper-factory"),
        ref("wildcat-market-revolving-init-code-storage"),
        revolvingMarketHash,
        rotation.reused.borrowerIdentityRegistry,
      ],
      output: "hooks-factory-revolving",
      description: `Deploy the replacement Sepolia ${versionLabel} revolving hooks factory.`,
      predicate: callEq(
        ref("hooks-factory-revolving"),
        "marketInitCodeStorage() view returns (address)",
        [],
        ref("wildcat-market-revolving-init-code-storage")
      ),
      after: EXPECTED_IDS[3],
    })
  );

  const lens = [
    [
      EXPECTED_IDS[5],
      ARTIFACTS.marketLensCore.artifactName,
      "market-lens-core",
      "core helper",
    ],
    [
      EXPECTED_IDS[6],
      ARTIFACTS.marketLensAggregator.artifactName,
      "market-lens-aggregator",
      "aggregation helper",
    ],
    [
      EXPECTED_IDS[7],
      ARTIFACTS.marketLensLive.artifactName,
      "market-lens-live",
      "live-data helper",
    ],
  ];
  for (const [id, artifactName, output, label] of lens) {
    entries.push(
      deploy(rotation, {
        id,
        artifactName,
        args: [
          rotation.authority.archController,
          ref("hooks-factory-standard"),
        ],
        output,
        description: `Deploy the replacement Sepolia ${versionLabel} market-lens ${label}.`,
        predicate: callEq(
          ref(output),
          "hooksFactory() view returns (address)",
          [],
          ref("hooks-factory-standard")
        ),
        after: entries.at(-1).id,
      })
    );
  }
  entries.push(
    deploy(rotation, {
      id: EXPECTED_IDS[8],
      artifactName: ARTIFACTS.marketLens.artifactName,
      args: [
        rotation.authority.archController,
        ref("hooks-factory-standard"),
        ref("market-lens-core"),
        ref("market-lens-aggregator"),
        ref("market-lens-live"),
      ],
      output: "market-lens",
      description: `Deploy the replacement Sepolia ${versionLabel} market-lens facade.`,
      predicate: callEq(
        ref("market-lens"),
        "aggregationHelper() view returns (address)",
        [],
        ref("market-lens-aggregator")
      ),
      after: EXPECTED_IDS[7],
    })
  );

  const templates = [
    [
      EXPECTED_IDS[9],
      "open-term-hooks-init-code-storage",
      artifacts.openTermHooks,
    ],
    [
      EXPECTED_IDS[10],
      "fixed-term-hooks-init-code-storage",
      artifacts.fixedTermHooks,
    ],
    [
      EXPECTED_IDS[11],
      "periodic-term-hooks-init-code-storage",
      artifacts.periodicTermHooks,
    ],
  ];
  for (const [id, output, artifact] of templates) {
    entries.push(
      deploy(rotation, {
        id,
        artifactName: initCodeStorage,
        args: [artifact.bytecode],
        output,
        description: `Deploy the corrected Sepolia ${versionLabel} ${artifact.contract} init-code store.`,
        predicate: codePresent(output),
        after: entries.at(-1).id,
      })
    );
  }

  entries.push(
    call(rotation, {
      id: EXPECTED_IDS[12],
      to: rotation.authority.archController,
      signature: "registerControllerFactory(address)",
      args: [ref("hooks-factory-standard")],
      description:
        "Register the replacement standard factory for market deployment.",
      predicate: callEq(
        rotation.authority.archController,
        "isRegisteredControllerFactory(address) view returns (bool)",
        [ref("hooks-factory-standard")],
        true
      ),
      after: EXPECTED_IDS[11],
    })
  );
  entries.push(
    call(rotation, {
      id: EXPECTED_IDS[13],
      to: rotation.authority.archController,
      signature: "registerControllerFactory(address)",
      args: [ref("hooks-factory-revolving")],
      description:
        "Register the replacement revolving factory for market deployment.",
      predicate: callEq(
        rotation.authority.archController,
        "isRegisteredControllerFactory(address) view returns (bool)",
        [ref("hooks-factory-revolving")],
        true
      ),
      after: EXPECTED_IDS[12],
    })
  );

  const templateCalls = [
    [
      "standard",
      "open-term",
      "OpenTermHooks",
      "open-term-hooks-init-code-storage",
    ],
    [
      "standard",
      "fixed-term",
      "FixedTermHooks",
      "fixed-term-hooks-init-code-storage",
    ],
    [
      "standard",
      "periodic-term",
      "PeriodicTermHooks",
      "periodic-term-hooks-init-code-storage",
    ],
    [
      "revolving",
      "open-term",
      "OpenTermHooks",
      "open-term-hooks-init-code-storage",
    ],
    [
      "revolving",
      "fixed-term",
      "FixedTermHooks",
      "fixed-term-hooks-init-code-storage",
    ],
    [
      "revolving",
      "periodic-term",
      "PeriodicTermHooks",
      "periodic-term-hooks-init-code-storage",
    ],
  ];
  for (let index = 0; index < templateCalls.length; index += 1) {
    const [marketType, term, name, storage] = templateCalls[index];
    const factory = `hooks-factory-${marketType}`;
    entries.push(
      call(rotation, {
        id: `add-${marketType}-${term}-template`,
        to: ref(factory),
        signature:
          "addHooksTemplate(address,string,address,address,uint80,uint16)",
        args: [
          ref(storage),
          name,
          fees.feeRecipient,
          fees.originationFeeAsset,
          fees.originationFeeAmount,
          fees.protocolFeeBips,
        ],
        description: `Add corrected ${name} to the replacement ${marketType} factory.`,
        predicate: callEq(
          ref(factory),
          "isHooksTemplate(address) view returns (bool)",
          [ref(storage)],
          true
        ),
        after: entries.at(-1).id,
      })
    );
  }

  entries.push(
    call(rotation, {
      id: EXPECTED_IDS[20],
      to: ref("hooks-factory-standard"),
      signature: "registerWithArchController()",
      args: [],
      description: "Register the replacement standard factory as a controller.",
      predicate: callEq(
        rotation.authority.archController,
        "isRegisteredController(address) view returns (bool)",
        [ref("hooks-factory-standard")],
        true
      ),
      after: EXPECTED_IDS[19],
    })
  );
  entries.push(
    call(rotation, {
      id: EXPECTED_IDS[21],
      to: ref("hooks-factory-revolving"),
      signature: "registerWithArchController()",
      args: [],
      description:
        "Register the replacement revolving factory as a controller.",
      predicate: callEq(
        rotation.authority.archController,
        "isRegisteredController(address) view returns (bool)",
        [ref("hooks-factory-revolving")],
        true
      ),
      after: EXPECTED_IDS[20],
    })
  );

  if (entries.map(({ id }) => id).join("\n") !== EXPECTED_IDS.join("\n")) {
    throw new Error("Internal rotation entry order mismatch");
  }
  return entries;
}

function logicalCall(transaction) {
  return (
    transaction.forwardedCall || {
      target: transaction.to,
      functionSignature: transaction.functionSignature,
      args: transaction.args,
    }
  );
}

function assertEqual(actual, expected, context) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${context} mismatch`);
  }
}

function assertRotationPlan(plan, rotation, artifacts) {
  const generic = validatePlan(plan);
  if (!generic.ok) {
    throw new Error(
      `Invalid plan:\n${generic.errors.map((error) => `- ${error}`).join("\n")}`
    );
  }
  if (
    plan.release !== rotation.release ||
    plan.network !== rotation.network ||
    plan.chainId !== rotation.chainId ||
    plan.foundryProfile !== "deploy" ||
    plan.expectedExecutor !== rotation.expectedExecutor
  ) {
    throw new Error("Plan identity differs from the rotation config");
  }
  assertEqual(
    plan.transactions.map(({ id }) => id),
    EXPECTED_IDS,
    "Activation transaction order"
  );
  if (
    plan.transactions.filter(({ kind }) => kind === "deploy").length !== 12 ||
    plan.transactions.filter(({ kind }) => kind === "call").length !== 10
  ) {
    throw new Error(
      "Rotation must contain exactly 12 deployments and 10 calls"
    );
  }
  if (
    plan.transactions.some((transaction) =>
      [
        ARTIFACTS.identityRegistry.artifactName,
        ARTIFACTS.accessListFactory.artifactName,
      ].includes(transaction.artifactName)
    )
  ) {
    throw new Error(
      "Rotation must reuse the identity registry and access-list factory"
    );
  }

  const expectedEntries = buildEntries(rotation, artifacts);
  for (let index = 0; index < plan.transactions.length; index += 1) {
    const transaction = plan.transactions[index];
    const expected = expectedEntries[index];
    assertEqual(transaction.kind, expected.kind, `${transaction.id} kind`);
    assertEqual(
      transaction.description,
      expected.description,
      `${transaction.id} description`
    );
    assertEqual(
      transaction.predicate,
      expected.predicate,
      `${transaction.id} predicate`
    );
    if (transaction.kind === "deploy") {
      assertEqual(
        transaction.artifactName,
        expected.artifactName,
        `${transaction.id} artifact`
      );
      assertEqual(
        transaction.output,
        expected.output,
        `${transaction.id} output`
      );
      assertEqual(
        transaction.constructorArgs.decoded,
        expected.constructorArgs.decoded,
        `${transaction.id} constructor arguments`
      );
    } else {
      const call = logicalCall(transaction);
      assertEqual(call.target, expected.to, `${transaction.id} logical target`);
      assertEqual(
        call.functionSignature,
        expected.functionSignature,
        `${transaction.id} logical function`
      );
      assertEqual(
        call.args,
        expected.args,
        `${transaction.id} logical arguments`
      );

      const mustForward = [
        "registerControllerFactory(address)",
        "addHooksTemplate(address,string,address,address,uint80,uint16)",
      ].includes(expected.functionSignature);
      if (mustForward) {
        if (
          transaction.functionSignature !==
            AUTHORITY_HELPER_FORWARD_SIGNATURE ||
          transaction.to !== rotation.authority.helper ||
          !transaction.forwardedCall
        ) {
          throw new Error(
            `${transaction.id} is not forwarded through the fixed helper`
          );
        }
      } else if (
        transaction.forwardedCall ||
        transaction.functionSignature !== expected.functionSignature ||
        JSON.stringify(transaction.args) !== JSON.stringify(expected.args) ||
        JSON.stringify(transaction.to) !== JSON.stringify(expected.to)
      ) {
        throw new Error(
          `${transaction.id} differs from its canonical direct call`
        );
      }
    }
  }

  const currentBytecode = new Map(
    Object.values(artifacts)
      .filter(({ artifactName }) => artifactName)
      .map(({ artifactName, bytecode }) => [
        artifactName,
        bytecode.toLowerCase(),
      ])
  );
  for (const transaction of plan.transactions.filter(
    ({ kind }) => kind === "deploy"
  )) {
    if (transaction.artifactName.includes("InitCodeStorage")) continue;
    if (
      transaction.initCode.toLowerCase() !==
      currentBytecode.get(transaction.artifactName)
    ) {
      throw new Error(
        `${transaction.id} does not use the frozen deploy artifact`
      );
    }
  }
}

function stripMetadata(bytecode) {
  const raw = bytecode.slice(2);
  if (raw.length < 4) return bytecode;
  const metadataBytes = Number.parseInt(raw.slice(-4), 16) + 2;
  const metadataNibbles = metadataBytes * 2;
  return metadataNibbles <= raw.length
    ? `0x${raw.slice(0, raw.length - metadataNibbles)}`
    : bytecode;
}

function writeImpactReport(rotation, artifacts) {
  const previousPlan = readJson(PREVIOUS_PLAN_PATH);
  const previousById = new Map(
    previousPlan.transactions.map((transaction) => [
      transaction.id,
      transaction,
    ])
  );
  const components = Object.entries(artifacts).map(([component, artifact]) => {
    const previousTransaction = previousById.get(artifact.previousId);
    if (!previousTransaction) {
      throw new Error(`Previous plan omits ${artifact.previousId}`);
    }
    const previousBytecode = artifact.storedInitCode
      ? previousTransaction.constructorArgs.decoded[0]
      : previousTransaction.initCode;
    const exactChanged =
      artifact.bytecode.toLowerCase() !== previousBytecode.toLowerCase();
    const semanticChanged =
      stripMetadata(artifact.bytecode).toLowerCase() !==
      stripMetadata(previousBytecode).toLowerCase();
    return {
      component,
      decision: artifact.decision,
      reason: artifact.reason,
      previousAddress: artifact.previousAddressKey
        ? rotation.superseded[artifact.previousAddressKey]
        : component === "identityRegistry"
        ? rotation.reused.borrowerIdentityRegistry
        : rotation.reused.accessListRoleProviderFactory,
      previousCreationCodeHash: keccak256(previousBytecode),
      replacementCreationCodeHash: keccak256(artifact.bytecode),
      previousCreationCodeBytes: (previousBytecode.length - 2) / 2,
      replacementCreationCodeBytes: (artifact.bytecode.length - 2) / 2,
      exactChanged,
      semanticChanged,
    };
  });
  writeJson(
    path.join(REPO_ROOT, `deployments/sepolia/impact-${rotation.release}.json`),
    {
      schemaVersion: "1.0.0",
      release: rotation.release,
      protocolVersion: rotation.protocolVersion,
      comparedAgainst: "v2-5",
      contractSourceCommit: rotation.contractSourceCommit,
      components,
    }
  );
}

function writeSourcePin(rotation) {
  const currentHead = git("rev-parse", "HEAD");
  const submodules = git("submodule", "status", "--recursive");
  const value = [
    `protocol_version=${rotation.protocolVersion}`,
    `contract_source_commit=${rotation.contractSourceCommit}`,
    `generated_from_head=${currentHead}`,
    "deployment_profile=deploy",
    "solc=0.8.25",
    "evm_version=cancun",
    "optimizer_runs=44",
    "via_ir=true",
    "submodules:",
    submodules,
    "",
  ].join("\n");
  fs.writeFileSync(
    path.join(REPO_ROOT, `deployments/sepolia/source-${rotation.release}.txt`),
    value,
    "utf8"
  );
}

function cleanGeneratedDirectory(directory) {
  fs.mkdirSync(directory, { recursive: true });
  for (const fileName of fs.readdirSync(directory)) {
    if (!/^\d{2}-[a-z0-9-]+\.json$/.test(fileName)) {
      throw new Error(
        `Refusing to replace unexpected generated file: ${fileName}`
      );
    }
    fs.unlinkSync(path.join(directory, fileName));
  }
}

function generate() {
  const rotation = config();
  assertContractSourceBoundary(rotation);
  execFileSync("forge", ["build"], {
    cwd: REPO_ROOT,
    env: { ...process.env, FOUNDRY_PROFILE: "deploy" },
    stdio: "inherit",
  });
  const artifacts = loadArtifacts();
  const entries = buildEntries(rotation, artifacts);
  const entriesName = `plan-entries-${rotation.release}`;
  const entriesDirectory = path.join(
    REPO_ROOT,
    "deployments/sepolia",
    entriesName
  );
  cleanGeneratedDirectory(entriesDirectory);
  entries.forEach((entry, index) => {
    writeJson(
      path.join(
        entriesDirectory,
        `${String(index + 1).padStart(2, "0")}-${entry.id}.json`
      ),
      entry
    );
  });

  execFileSync(
    process.execPath,
    [
      "scripts/plan.js",
      "assemble",
      "--network",
      rotation.network,
      "--release",
      rotation.release,
      "--entries",
      entriesName,
    ],
    {
      cwd: REPO_ROOT,
      env: { ...process.env, FOUNDRY_PROFILE: "deploy" },
      stdio: "inherit",
    }
  );
  const planPath = path.join(
    REPO_ROOT,
    `deployments/sepolia/plan-${rotation.release}.json`
  );
  const plan = readJson(planPath);
  assertRotationPlan(plan, rotation, artifacts);
  writeImpactReport(rotation, artifacts);
  writeSourcePin(rotation);

  const packagePath = path.join(
    REPO_ROOT,
    `deployments/sepolia/ceremony-${rotation.release}-eoa.json`
  );
  const packageOutput = execFileSync(
    process.execPath,
    [
      "scripts/plan.js",
      "ceremony-package",
      "--plan",
      planPath,
      "--mode",
      "eoa",
      "--out",
      packagePath,
    ],
    { cwd: REPO_ROOT, encoding: "utf8" }
  );
  process.stdout.write(packageOutput);
  fs.writeFileSync(
    packagePath.replace(/\.json$/, ".digest.txt"),
    packageOutput,
    "utf8"
  );
  console.log(
    `Sepolia v${rotation.protocolVersion} factory replacement generated: 12 deploys, 10 activation calls, 0 authority changes`
  );
}

function validate() {
  const rotation = config();
  assertContractSourceBoundary(rotation);
  const artifacts = loadArtifacts();
  const planPath = path.join(
    REPO_ROOT,
    `deployments/sepolia/plan-${rotation.release}.json`
  );
  assertRotationPlan(readJson(planPath), rotation, artifacts);
  console.log(
    `Sepolia v${
      rotation.protocolVersion
    } factory-replacement plan valid with fixed authority: ${path.relative(
      REPO_ROOT,
      planPath
    )}`
  );
}

function sameAddress(actual, expected, context) {
  if (getAddress(actual) !== getAddress(expected)) {
    throw new Error(`${context}: expected ${expected}, got ${actual}`);
  }
}

function resolveOutputPath(value, fallback) {
  if (
    value !== undefined &&
    (typeof value !== "string" || value.length === 0)
  ) {
    throw new Error("Output path must be a non-empty string");
  }
  return path.resolve(REPO_ROOT, value || fallback);
}

async function authoritySnapshot(provider, rotation) {
  const arch = new Contract(
    rotation.authority.archController,
    [
      "function owner() view returns (address)",
      "function sphereXEngine() view returns (address)",
      "function sphereXAdmin() view returns (address)",
      "function sphereXOperator() view returns (address)",
      "function pendingSphereXAdmin() view returns (address)",
    ],
    provider
  );
  const helper = new Contract(
    rotation.authority.helper,
    [
      "function version() view returns (string)",
      "function archController() view returns (address)",
      "function authorizedAccounts(address) view returns (bool)",
      "function getAuthorizedAccounts() view returns (address[])",
    ],
    provider
  );

  const [
    owner,
    helperVersion,
    helperArchController,
    authorizedAccounts,
    executorAuthorized,
    sphereXEngine,
    sphereXAdmin,
    sphereXOperator,
    pendingSphereXAdmin,
  ] = await Promise.all([
    arch.owner(),
    helper.version(),
    helper.archController(),
    helper.getAuthorizedAccounts(),
    helper.authorizedAccounts(rotation.expectedExecutor),
    arch.sphereXEngine(),
    arch.sphereXAdmin(),
    arch.sphereXOperator(),
    arch.pendingSphereXAdmin(),
  ]);

  sameAddress(owner, rotation.authority.helper, "ArchController owner");
  if (helperVersion !== "2") {
    throw new Error(`Authority helper version is ${helperVersion}, expected 2`);
  }
  sameAddress(
    helperArchController,
    rotation.authority.archController,
    "Authority helper ArchController"
  );
  if (!executorAuthorized) {
    throw new Error(
      "Expected executor is not authorized by the existing helper"
    );
  }
  sameAddress(
    pendingSphereXAdmin,
    ZERO_ADDRESS,
    "Pending ArchController SphereX admin"
  );
  if ((await provider.getCode(sphereXEngine)) === "0x") {
    throw new Error(`SphereX engine has no code at ${sphereXEngine}`);
  }

  const engine = new Contract(
    sphereXEngine,
    [
      "function defaultAdmin() view returns (address)",
      "function pendingDefaultAdmin() view returns (address,uint48)",
    ],
    provider
  );
  const [engineDefaultAdmin, pendingDefaultAdmin] = await Promise.all([
    engine.defaultAdmin(),
    engine.pendingDefaultAdmin(),
  ]);
  sameAddress(
    pendingDefaultAdmin[0],
    ZERO_ADDRESS,
    "Pending SphereX engine default admin"
  );
  if (Number(pendingDefaultAdmin[1]) !== 0) {
    throw new Error(
      `Pending SphereX engine admin schedule is ${pendingDefaultAdmin[1]}, expected 0`
    );
  }

  return {
    policy: rotation.authorityPolicy,
    archController: rotation.authority.archController,
    owner: getAddress(owner),
    helper: rotation.authority.helper,
    helperVersion,
    helperArchController: getAddress(helperArchController),
    authorizedAccounts: Array.from(authorizedAccounts, getAddress),
    expectedExecutor: rotation.expectedExecutor,
    executorAuthorized: true,
    sphereXEngine: getAddress(sphereXEngine),
    sphereXAdmin: getAddress(sphereXAdmin),
    sphereXOperator: getAddress(sphereXOperator),
    pendingSphereXAdmin: getAddress(pendingSphereXAdmin),
    engineDefaultAdmin: getAddress(engineDefaultAdmin),
    pendingEngineDefaultAdmin: getAddress(pendingDefaultAdmin[0]),
    pendingEngineDefaultAdminAt: Number(pendingDefaultAdmin[1]),
  };
}

async function preflight(args) {
  const rotation = config();
  assertContractSourceBoundary(rotation);
  const rpcUrl = args["rpc-url"] || process.env.RPC_URL || DEFAULT_RPC_URL;
  const provider = new JsonRpcProvider(rpcUrl, rotation.chainId);
  const network = await provider.getNetwork();
  if (Number(network.chainId) !== rotation.chainId) {
    throw new Error(
      `RPC chain ID is ${network.chainId}, expected ${rotation.chainId}`
    );
  }
  const block = await provider.getBlock("latest");
  if (!block) throw new Error("Could not read the latest Sepolia block");

  const arch = new Contract(
    rotation.authority.archController,
    [
      "function owner() view returns (address)",
      "function isRegisteredControllerFactory(address) view returns (bool)",
      "function isRegisteredController(address) view returns (bool)",
    ],
    provider
  );
  const fixedAuthority = await authoritySnapshot(provider, rotation);

  const codeTargets = {
    ...rotation.authority,
    ...rotation.reused,
    ...rotation.superseded,
  };
  for (const [label, address] of Object.entries(codeTargets)) {
    if ((await provider.getCode(address)) === "0x") {
      throw new Error(`${label} has no code at ${address}`);
    }
  }

  const factoryAbi = [
    "function archController() view returns (address)",
    "function sanctionsSentinel() view returns (address)",
    "function wrapperFactory() view returns (address)",
    "function borrowerIdentityRegistry() view returns (address)",
    "function getHooksTemplates() view returns (address[])",
    "function getHooksTemplateDetails(address) view returns ((address,uint80,uint16,bool,bool,uint24,address,string))",
  ];
  const factories = [
    ["standard", rotation.superseded.standardHooksFactory],
    ["revolving", rotation.superseded.revolvingHooksFactory],
  ];
  const factoryState = [];
  for (const [marketType, address] of factories) {
    if (!(await arch.isRegisteredControllerFactory(address))) {
      throw new Error(
        `${marketType} predecessor is not a registered controller factory`
      );
    }
    if (!(await arch.isRegisteredController(address))) {
      throw new Error(
        `${marketType} predecessor is not a registered controller`
      );
    }
    const factory = new Contract(address, factoryAbi, provider);
    sameAddress(
      await factory.archController(),
      rotation.authority.archController,
      `${marketType} factory ArchController`
    );
    sameAddress(
      await factory.sanctionsSentinel(),
      rotation.authority.sanctionsSentinel,
      `${marketType} factory sanctions sentinel`
    );
    sameAddress(
      await factory.wrapperFactory(),
      rotation.superseded.wrapperFactory,
      `${marketType} factory wrapper factory`
    );
    sameAddress(
      await factory.borrowerIdentityRegistry(),
      rotation.reused.borrowerIdentityRegistry,
      `${marketType} factory identity registry`
    );
    const templates = await factory.getHooksTemplates();
    if (templates.length !== 3) {
      throw new Error(
        `${marketType} predecessor has ${templates.length} templates`
      );
    }
    const templateState = [];
    for (const template of templates) {
      const details = await factory.getHooksTemplateDetails(template);
      sameAddress(
        details[0],
        rotation.templateFees.originationFeeAsset,
        `${marketType} ${template} origination-fee asset`
      );
      sameAddress(
        details[6],
        rotation.templateFees.feeRecipient,
        `${marketType} ${template} fee recipient`
      );
      if (
        Number(details[1]) !== rotation.templateFees.originationFeeAmount ||
        Number(details[2]) !== rotation.templateFees.protocolFeeBips ||
        details[3] !== true ||
        details[4] !== true
      ) {
        throw new Error(
          `${marketType} ${template} fee or enabled state differs`
        );
      }
      templateState.push({
        address: getAddress(template),
        name: details[7],
        feeRecipient: getAddress(details[6]),
        protocolFeeBips: Number(details[2]),
      });
    }
    factoryState.push({
      marketType,
      address,
      controllerFactoryRegistered: true,
      controllerRegistered: true,
      templates: templateState,
    });
  }

  const wrapper = new Contract(
    rotation.superseded.wrapperFactory,
    [
      "function archController() view returns (address)",
      "function v1Factory() view returns (address)",
    ],
    provider
  );
  sameAddress(
    await wrapper.archController(),
    rotation.authority.archController,
    "Predecessor wrapper ArchController"
  );
  sameAddress(
    await wrapper.v1Factory(),
    rotation.reused.v1WrapperFactory,
    "Predecessor v1 wrapper factory"
  );

  execFileSync(
    process.execPath,
    ["scripts/check-eip1153.js", "--rpc-url", rpcUrl, "--quiet"],
    { cwd: REPO_ROOT, stdio: "inherit" }
  );
  const report = {
    schemaVersion: "1.0.0",
    release: rotation.release,
    protocolVersion: rotation.protocolVersion,
    network: rotation.network,
    chainId: rotation.chainId,
    checkedAt: new Date(Number(block.timestamp) * 1000).toISOString(),
    blockNumber: block.number,
    blockHash: block.hash,
    status: "green",
    authority: fixedAuthority,
    executor: {
      nonce: await provider.getTransactionCount(
        rotation.expectedExecutor,
        "pending"
      ),
      balanceWei: (
        await provider.getBalance(rotation.expectedExecutor)
      ).toString(),
    },
    factories: factoryState,
    authorityPolicy: rotation.authorityPolicy,
    noAuthorityRotation: true,
  };
  const outputPath = resolveOutputPath(
    args.out,
    `deployments/sepolia/preflight-${rotation.release}.json`
  );
  writeJson(outputPath, report);
  console.log(
    `Sepolia factory-replacement preflight GREEN at block ${
      block.number
    }: ${path.relative(REPO_ROOT, outputPath)}`
  );
}

function requiredPathArg(args, name) {
  const value = args[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Missing --${name} <path>`);
  }
  return path.resolve(REPO_ROOT, value);
}

function deploymentOutputs(plan, runState) {
  const outputs = new Map();
  for (const transaction of plan.transactions) {
    const entry = runState[transaction.id];
    if (!entry || entry.status !== "verified") {
      throw new Error(`Run-state entry ${transaction.id} is not verified`);
    }
    if (transaction.kind !== "deploy") continue;
    if (!entry.resolvedAddress) {
      throw new Error(`Run-state deployment ${transaction.id} has no address`);
    }
    outputs.set(transaction.output, getAddress(entry.resolvedAddress));
  }
  return outputs;
}

function outputAddress(outputs, name) {
  const value = outputs.get(name);
  if (!value) throw new Error(`Missing deployment output ${name}`);
  return value;
}

async function verifyReplacementFactory({
  provider,
  arch,
  rotation,
  artifacts,
  outputs,
  marketType,
}) {
  const factoryAddress = outputAddress(outputs, `hooks-factory-${marketType}`);
  const wrapperFactory = outputAddress(outputs, "wildcat-4626-wrapper-factory");
  const marketStore = outputAddress(
    outputs,
    marketType === "standard"
      ? "wildcat-market-init-code-storage"
      : "wildcat-market-revolving-init-code-storage"
  );
  const marketHash = keccak256(
    marketType === "standard"
      ? artifacts.standardMarket.bytecode
      : artifacts.revolvingMarket.bytecode
  );
  const templateSpecs = [
    ["open-term-hooks-init-code-storage", "OpenTermHooks"],
    ["fixed-term-hooks-init-code-storage", "FixedTermHooks"],
    ["periodic-term-hooks-init-code-storage", "PeriodicTermHooks"],
  ];
  const factory = new Contract(
    factoryAddress,
    [
      "function archController() view returns (address)",
      "function sanctionsSentinel() view returns (address)",
      "function wrapperFactory() view returns (address)",
      "function borrowerIdentityRegistry() view returns (address)",
      "function marketInitCodeStorage() view returns (address)",
      "function marketInitCodeHash() view returns (uint256)",
      "function getHooksTemplates() view returns (address[])",
      "function getHooksTemplateDetails(address) view returns ((address,uint80,uint16,bool,bool,uint24,address,string))",
    ],
    provider
  );

  if (!(await arch.isRegisteredControllerFactory(factoryAddress))) {
    throw new Error(`${marketType} replacement is not a controller factory`);
  }
  if (!(await arch.isRegisteredController(factoryAddress))) {
    throw new Error(`${marketType} replacement is not a controller`);
  }
  sameAddress(
    await factory.archController(),
    rotation.authority.archController,
    `${marketType} replacement ArchController`
  );
  sameAddress(
    await factory.sanctionsSentinel(),
    rotation.authority.sanctionsSentinel,
    `${marketType} replacement sanctions sentinel`
  );
  sameAddress(
    await factory.wrapperFactory(),
    wrapperFactory,
    `${marketType} replacement wrapper factory`
  );
  sameAddress(
    await factory.borrowerIdentityRegistry(),
    rotation.reused.borrowerIdentityRegistry,
    `${marketType} replacement identity registry`
  );
  sameAddress(
    await factory.marketInitCodeStorage(),
    marketStore,
    `${marketType} replacement market store`
  );
  if ((await factory.marketInitCodeHash()) !== BigInt(marketHash)) {
    throw new Error(`${marketType} replacement market init-code hash differs`);
  }

  const templates = Array.from(await factory.getHooksTemplates(), getAddress);
  const expectedTemplates = templateSpecs.map(([name]) =>
    outputAddress(outputs, name)
  );
  assertEqual(
    templates,
    expectedTemplates,
    `${marketType} replacement templates`
  );
  const verifiedTemplates = [];
  for (let index = 0; index < templateSpecs.length; index += 1) {
    const [output, expectedName] = templateSpecs[index];
    const address = outputAddress(outputs, output);
    const details = await factory.getHooksTemplateDetails(address);
    sameAddress(
      details[0],
      rotation.templateFees.originationFeeAsset,
      `${marketType} ${expectedName} origination-fee asset`
    );
    sameAddress(
      details[6],
      rotation.templateFees.feeRecipient,
      `${marketType} ${expectedName} fee recipient`
    );
    if (
      Number(details[1]) !== rotation.templateFees.originationFeeAmount ||
      Number(details[2]) !== rotation.templateFees.protocolFeeBips ||
      details[3] !== true ||
      details[4] !== true ||
      Number(details[5]) !== index ||
      details[7] !== expectedName
    ) {
      throw new Error(`${marketType} ${expectedName} template state differs`);
    }
    verifiedTemplates.push({ address, name: expectedName });
  }

  return {
    marketType,
    address: factoryAddress,
    controllerFactoryRegistered: true,
    controllerRegistered: true,
    wrapperFactory,
    marketInitCodeStorage: marketStore,
    marketInitCodeHash: marketHash,
    borrowerIdentityRegistry: rotation.reused.borrowerIdentityRegistry,
    templates: verifiedTemplates,
  };
}

async function verifyActivation(args) {
  const rotation = config();
  assertContractSourceBoundary(rotation);
  const artifacts = loadArtifacts();
  const planPath = path.join(
    REPO_ROOT,
    `deployments/sepolia/plan-${rotation.release}.json`
  );
  const plan = readJson(planPath);
  assertRotationPlan(plan, rotation, artifacts);

  const runStatePath = requiredPathArg(args, "run-state");
  const preflightPath = resolveOutputPath(
    args.preflight,
    `deployments/sepolia/preflight-${rotation.release}.json`
  );
  if (!fs.existsSync(runStatePath)) {
    throw new Error(`Run state not found: ${runStatePath}`);
  }
  if (!fs.existsSync(preflightPath)) {
    throw new Error(`Preflight not found: ${preflightPath}`);
  }
  const runState = readJson(runStatePath);
  const preflightReport = readJson(preflightPath);
  if (
    preflightReport.release !== rotation.release ||
    preflightReport.status !== "green" ||
    preflightReport.authority?.policy !== "fixed"
  ) {
    throw new Error("Preflight is not a green fixed-authority baseline");
  }

  const rpcUrl = args["rpc-url"] || process.env.RPC_URL || DEFAULT_RPC_URL;
  const provider = new JsonRpcProvider(rpcUrl, rotation.chainId);
  const network = await provider.getNetwork();
  if (Number(network.chainId) !== rotation.chainId) {
    throw new Error(
      `RPC chain ID is ${network.chainId}, expected ${rotation.chainId}`
    );
  }

  execFileSync(
    process.execPath,
    [
      "scripts/plan.js",
      "verify",
      "--plan",
      planPath,
      "--run-state",
      runStatePath,
      "--rpc",
      rpcUrl,
    ],
    { cwd: REPO_ROOT, env: process.env, stdio: "inherit" }
  );
  execFileSync(
    process.execPath,
    [
      "scripts/plan.js",
      "verify-eoa-run-state",
      "--plan",
      planPath,
      "--run-state",
      runStatePath,
      "--rpc",
      rpcUrl,
    ],
    { cwd: REPO_ROOT, env: process.env, stdio: "inherit" }
  );

  const outputs = deploymentOutputs(plan, runState);
  for (const [name, address] of outputs) {
    if ((await provider.getCode(address)) === "0x") {
      throw new Error(`Replacement output ${name} has no code at ${address}`);
    }
  }

  const currentAuthority = await authoritySnapshot(provider, rotation);
  assertEqual(
    currentAuthority,
    preflightReport.authority,
    "Authority state changed during factory replacement"
  );

  const arch = new Contract(
    rotation.authority.archController,
    [
      "function isRegisteredControllerFactory(address) view returns (bool)",
      "function isRegisteredController(address) view returns (bool)",
    ],
    provider
  );
  for (const [marketType, predecessor] of [
    ["standard", rotation.superseded.standardHooksFactory],
    ["revolving", rotation.superseded.revolvingHooksFactory],
  ]) {
    if (
      !(await arch.isRegisteredControllerFactory(predecessor)) ||
      !(await arch.isRegisteredController(predecessor))
    ) {
      throw new Error(
        `${marketType} predecessor was retired during activation`
      );
    }
  }

  const wrapperAddress = outputAddress(outputs, "wildcat-4626-wrapper-factory");
  const wrapper = new Contract(
    wrapperAddress,
    [
      "function archController() view returns (address)",
      "function v1Factory() view returns (address)",
    ],
    provider
  );
  sameAddress(
    await wrapper.archController(),
    rotation.authority.archController,
    "Replacement wrapper ArchController"
  );
  sameAddress(
    await wrapper.v1Factory(),
    rotation.reused.v1WrapperFactory,
    "Replacement wrapper v1 factory"
  );

  const factories = [];
  for (const marketType of ["standard", "revolving"]) {
    factories.push(
      await verifyReplacementFactory({
        provider,
        arch,
        rotation,
        artifacts,
        outputs,
        marketType,
      })
    );
  }

  const standardFactory = outputAddress(outputs, "hooks-factory-standard");
  const lensSpecs = [
    ["market-lens-core", []],
    ["market-lens-aggregator", []],
    ["market-lens-live", []],
    [
      "market-lens",
      [
        ["coreHelper", "market-lens-core"],
        ["aggregationHelper", "market-lens-aggregator"],
        ["liveHelper", "market-lens-live"],
      ],
    ],
  ];
  const lenses = [];
  for (const [output, helperSpecs] of lensSpecs) {
    const address = outputAddress(outputs, output);
    const abi = [
      "function archController() view returns (address)",
      "function hooksFactory() view returns (address)",
      ...helperSpecs.map(
        ([getter]) => `function ${getter}() view returns (address)`
      ),
    ];
    const lens = new Contract(address, abi, provider);
    sameAddress(
      await lens.archController(),
      rotation.authority.archController,
      `${output} ArchController`
    );
    sameAddress(
      await lens.hooksFactory(),
      standardFactory,
      `${output} hooks factory`
    );
    const helpers = {};
    for (const [getter, helperOutput] of helperSpecs) {
      const expected = outputAddress(outputs, helperOutput);
      sameAddress(await lens[getter](), expected, `${output} ${getter}`);
      helpers[getter] = expected;
    }
    lenses.push({
      name: output,
      address,
      hooksFactory: standardFactory,
      ...helpers,
    });
  }

  const block = await provider.getBlock("latest");
  if (!block)
    throw new Error("Could not read the activation verification block");
  const report = {
    schemaVersion: "1.0.0",
    release: rotation.release,
    protocolVersion: rotation.protocolVersion,
    network: rotation.network,
    chainId: rotation.chainId,
    verifiedAt: new Date(Number(block.timestamp) * 1000).toISOString(),
    blockNumber: block.number,
    blockHash: block.hash,
    status: "green",
    authority: currentAuthority,
    authorityChanged: false,
    wrapperFactory: wrapperAddress,
    factories,
    lenses,
    predecessorsRemainRegistered: true,
    retirementExecuted: false,
  };
  const outputPath = resolveOutputPath(
    args.out,
    `deployments/sepolia/post-activation-${rotation.release}.json`
  );
  writeJson(outputPath, report);
  console.log(
    `Sepolia factory-replacement activation GREEN with fixed authority at block ${
      block.number
    }: ${path.relative(REPO_ROOT, outputPath)}`
  );
}

async function main() {
  const [command, ...argv] = process.argv.slice(2);
  if (!command || command === "--help" || command === "-h") {
    usage();
    return;
  }
  const args = parseArgs(argv);
  if (command === "generate") return generate();
  if (command === "validate") return validate();
  if (command === "preflight") return preflight(args);
  if (command === "verify-activation") return verifyActivation(args);
  throw new Error(`Unknown command: ${command}`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}

module.exports = {
  ARTIFACTS,
  EXPECTED_IDS,
  assertRotationPlan,
  buildEntries,
  stripMetadata,
};
