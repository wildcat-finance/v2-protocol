#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { Interface, JsonRpcProvider, ZeroAddress, getAddress, id } = require("ethers");

const REPO_ROOT = path.resolve(__dirname, "..");
const FORWARD_SIGNATURE = "executeProtocolAction(address,bytes)";

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) throw new Error(`Unexpected argument: ${token}`);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) throw new Error(`Missing value for ${token}`);
    args[token.slice(2)] = value;
    index += 1;
  }
  return args;
}

function required(args, name) {
  const value = args[name];
  if (typeof value !== "string" || value.length === 0) throw new Error(`Missing --${name}`);
  return value;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function ref(output) {
  return { $ref: output };
}

function envelope(chainId, expectedExecutor, to, data) {
  return {
    chainId,
    expectedExecutor,
    to,
    value: "0",
    data,
    gasLimitPolicy: "estimate*1.3",
    nonceCheck: "display-and-confirm",
  };
}

function callEq(target, sig, args, expect) {
  return { type: "callEq", target, call: { sig, args }, expect };
}

function directCall({
  id: entryId,
  chainId,
  executor,
  to,
  signature,
  args,
  description,
  predicate,
  after,
  reverifyUntil,
}) {
  return {
    id: entryId,
    kind: "call",
    to,
    functionSignature: signature,
    args,
    description,
    ...(reverifyUntil ? { reverifyUntil } : {}),
    envelope: envelope(chainId, executor, to, "functionSignature+args"),
    predicate,
    after,
  };
}

function forwardedCall({
  id: entryId,
  chainId,
  executor,
  helper,
  target,
  signature,
  args,
  description,
  predicate,
  after,
}) {
  return {
    id: entryId,
    kind: "call",
    to: helper,
    functionSignature: FORWARD_SIGNATURE,
    forwardedCall: { target, functionSignature: signature, args },
    description,
    envelope: envelope(chainId, executor, helper, "forwardedCall"),
    predicate,
    after,
  };
}

async function readAddress(provider, target, signature) {
  const contractInterface = new Interface([`function ${signature}`]);
  const fragment = contractInterface.fragments[0];
  const result = await provider.call({
    to: target,
    data: contractInterface.encodeFunctionData(fragment, []),
  });
  return getAddress(contractInterface.decodeFunctionResult(fragment, result)[0]);
}

function context(args) {
  const network = required(args, "network");
  const networkDir = path.join(REPO_ROOT, "deployments", network);
  const deployments = readJson(path.join(networkDir, "deployments.json"));
  const inventory = readJson(path.join(networkDir, "factory-inventory.json"));
  const config = readJson(path.join(networkDir, "ceremony-config.json"));
  if (config.schemaVersion !== "2.0.0" || config.ownership?.type !== "authorized-helper") {
    throw new Error(`${network} does not use the authorized-helper ceremony config`);
  }
  return {
    network,
    networkDir,
    deployments,
    chainId: inventory.chainId,
    config,
    archController: getAddress(deployments[config.ownership.archControllerKey]),
    currentHelper: getAddress(deployments[config.ownership.helperOwnerKey]),
  };
}

function replacementHelper(args, contextValue) {
  const helperOverride = args.helper;
  const runStatePath = args["phase-one-run-state"];
  if (helperOverride && runStatePath) {
    throw new Error("Use --helper or --phase-one-run-state, not both");
  }
  if (!helperOverride && !runStatePath) {
    throw new Error(
      "Phase two and phase three require --phase-one-run-state or an explicit --helper"
    );
  }

  let helper;
  if (helperOverride) {
    helper = getAddress(helperOverride);
  } else {
    const runState = readJson(runStatePath);
    const replacementState = runState["deploy-replacement-authority-helper"];
    if (replacementState?.status !== "verified" || !replacementState.resolvedAddress) {
      throw new Error(`Phase-one run state has no verified replacement helper: ${runStatePath}`);
    }
    helper = getAddress(replacementState.resolvedAddress);
  }

  if (helper === ZeroAddress) {
    throw new Error("Replacement helper cannot be the zero address");
  }

  if (helper === contextValue.currentHelper) {
    throw new Error(
      "Replacement helper resolves to the current legacy helper; use the verified phase-one run state"
    );
  }
  return helper;
}

function assemble(contextValue, release, entries) {
  const entriesName = `${release}-entries`;
  const entriesDirectory = path.join(contextValue.networkDir, entriesName);
  fs.rmSync(entriesDirectory, { recursive: true, force: true });
  fs.mkdirSync(entriesDirectory, { recursive: true });
  entries.forEach((entry, index) => {
    writeJson(
      path.join(entriesDirectory, `${String(index + 1).padStart(2, "0")}-${entry.id}.json`),
      entry
    );
  });
  execFileSync(
    process.execPath,
    [
      path.join(REPO_ROOT, "scripts", "plan.js"),
      "assemble",
      "--network",
      contextValue.network,
      "--release",
      release,
      "--entries",
      entriesName,
    ],
    {
      cwd: REPO_ROOT,
      env: { ...process.env, FOUNDRY_PROFILE: "deploy" },
      stdio: "inherit",
    }
  );
  const planPath = path.join(contextValue.networkDir, `plan-${release}.json`);
  execFileSync(
    process.execPath,
    [path.join(REPO_ROOT, "scripts", "plan.js"), "validate", "--plan", planPath],
    {
      cwd: REPO_ROOT,
      env: { ...process.env, FOUNDRY_PROFILE: "deploy" },
      stdio: "inherit",
    }
  );
  console.log(`Authority migration phase ready: ${path.relative(REPO_ROOT, planPath)}`);
}

async function phaseOne(args) {
  const value = context(args);
  const rpcUrl = required(args, "rpc-url");
  const oldExecutor = getAddress(required(args, "old-executor"));
  const newExecutor = getAddress(required(args, "new-executor"));
  if (
    !value.config.ownership.retainedAuthorizedAccounts.some(
      (account) => getAddress(account) === oldExecutor
    )
  ) {
    throw new Error("Old executor is not recorded as a retained authorized account");
  }
  const provider = new JsonRpcProvider(rpcUrl);
  const engine = await readAddress(
    provider,
    value.archController,
    "sphereXEngine() view returns (address)"
  );
  const replacement = ref("replacement-authority-helper");
  const transferOwnershipId = "transfer-arch-controller-to-replacement-helper";
  const entries = [
    {
      id: "deploy-replacement-authority-helper",
      kind: "deploy",
      artifactName: "script/mock/MockArchControllerOwner.sol:MockArchControllerOwner",
      constructorArgs: {
        decoded: [value.archController, [oldExecutor, newExecutor]],
      },
      output: "replacement-authority-helper",
      description: "Deploy the replacement Sepolia authority helper with both executors authorized.",
      envelope: envelope(value.chainId, oldExecutor, null, "initCode+constructorArgs"),
      predicate: { type: "codePresent", target: replacement },
      after: [],
    },
    directCall({
      id: "reclaim-arch-controller-from-legacy-helper",
      chainId: value.chainId,
      executor: oldExecutor,
      to: value.currentHelper,
      signature: "returnOwnership()",
      args: [],
      description: "Return ArchController ownership from the legacy helper to the old executor.",
      reverifyUntil: transferOwnershipId,
      predicate: callEq(
        value.archController,
        "owner() view returns (address)",
        [],
        oldExecutor
      ),
      after: ["deploy-replacement-authority-helper"],
    }),
    directCall({
      id: transferOwnershipId,
      chainId: value.chainId,
      executor: oldExecutor,
      to: value.archController,
      signature: "transferOwnership(address)",
      args: [replacement],
      description: "Transfer ArchController ownership to the replacement authority helper.",
      predicate: callEq(
        value.archController,
        "owner() view returns (address)",
        [],
        replacement
      ),
      after: ["reclaim-arch-controller-from-legacy-helper"],
    }),
    directCall({
      id: "start-arch-controller-spherex-admin-transfer",
      chainId: value.chainId,
      executor: oldExecutor,
      to: value.archController,
      signature: "transferSphereXAdminRole(address)",
      args: [replacement],
      description: "Start the ArchController SphereX admin transfer to the replacement helper.",
      predicate: callEq(
        value.archController,
        "pendingSphereXAdmin() view returns (address)",
        [],
        replacement
      ),
      after: [transferOwnershipId],
    }),
    directCall({
      id: "start-spherex-engine-default-admin-transfer",
      chainId: value.chainId,
      executor: oldExecutor,
      to: engine,
      signature: "beginDefaultAdminTransfer(address)",
      args: [replacement],
      description: "Start the SphereX engine default-admin transfer to the replacement helper.",
      predicate: {
        type: "callResultEq",
        target: engine,
        call: { sig: "pendingDefaultAdmin() view returns (address,uint48)", args: [] },
        resultIndex: 0,
        expect: replacement,
      },
      after: ["start-arch-controller-spherex-admin-transfer"],
    }),
  ];
  assemble(value, "authority-helper-phase-1", entries);
  console.log(`SphereX engine: ${engine}`);
}

function phaseTwo(args) {
  const value = context(args);
  const helper = replacementHelper(args, value);
  const newExecutor = getAddress(required(args, "new-executor"));
  const entries = [
    forwardedCall({
      id: "accept-arch-controller-spherex-admin",
      chainId: value.chainId,
      executor: newExecutor,
      helper,
      target: value.archController,
      signature: "acceptSphereXAdminRole()",
      args: [],
      description: "Accept the ArchController SphereX admin role through the replacement helper.",
      predicate: callEq(
        value.archController,
        "sphereXAdmin() view returns (address)",
        [],
        helper
      ),
      after: [],
    }),
    forwardedCall({
      id: "change-arch-controller-spherex-operator",
      chainId: value.chainId,
      executor: newExecutor,
      helper,
      target: value.archController,
      signature: "changeSphereXOperator(address)",
      args: [helper],
      description: "Move the ArchController SphereX operator role to the replacement helper.",
      predicate: callEq(
        value.archController,
        "sphereXOperator() view returns (address)",
        [],
        helper
      ),
      after: ["accept-arch-controller-spherex-admin"],
    }),
    directCall({
      id: "register-new-executor-as-borrower",
      chainId: value.chainId,
      executor: newExecutor,
      to: helper,
      signature: "registerBorrower(address)",
      args: [newExecutor],
      description: "Register the new executor through the permissionless testnet borrower path.",
      predicate: callEq(
        value.archController,
        "isRegisteredBorrower(address) view returns (bool)",
        [newExecutor],
        true
      ),
      after: ["change-arch-controller-spherex-operator"],
    }),
  ];
  assemble(value, "authority-helper-phase-2", entries);
}

async function phaseThree(args) {
  const value = context(args);
  const rpcUrl = required(args, "rpc-url");
  const helper = replacementHelper(args, value);
  const oldExecutor = getAddress(required(args, "old-executor"));
  const newExecutor = getAddress(required(args, "new-executor"));
  const provider = new JsonRpcProvider(rpcUrl);
  const engine = await readAddress(
    provider,
    value.archController,
    "sphereXEngine() view returns (address)"
  );
  const operatorRole = id("OPERATOR_ROLE");
  const entries = [
    forwardedCall({
      id: "accept-spherex-engine-default-admin",
      chainId: value.chainId,
      executor: newExecutor,
      helper,
      target: engine,
      signature: "acceptDefaultAdminTransfer()",
      args: [],
      description: "Accept the SphereX engine default-admin role through the replacement helper.",
      predicate: callEq(engine, "defaultAdmin() view returns (address)", [], helper),
      after: [],
    }),
    forwardedCall({
      id: "grant-helper-spherex-engine-operator",
      chainId: value.chainId,
      executor: newExecutor,
      helper,
      target: engine,
      signature: "grantRole(bytes32,address)",
      args: [operatorRole, helper],
      description: "Grant the SphereX engine operator role to the replacement helper.",
      predicate: callEq(
        engine,
        "hasRole(bytes32,address) view returns (bool)",
        [operatorRole, helper],
        true
      ),
      after: ["accept-spherex-engine-default-admin"],
    }),
    forwardedCall({
      id: "revoke-old-spherex-engine-operator",
      chainId: value.chainId,
      executor: newExecutor,
      helper,
      target: engine,
      signature: "revokeRole(bytes32,address)",
      args: [operatorRole, oldExecutor],
      description: "Remove the old wallet's direct SphereX engine operator role.",
      predicate: callEq(
        engine,
        "hasRole(bytes32,address) view returns (bool)",
        [operatorRole, oldExecutor],
        false
      ),
      after: ["grant-helper-spherex-engine-operator"],
    }),
  ];
  assemble(value, "authority-helper-phase-3", entries);
  console.log(`SphereX engine: ${engine}`);
}

async function main() {
  const [command, ...argv] = process.argv.slice(2);
  const args = parseArgs(argv);
  if (command === "phase-one") return phaseOne(args);
  if (command === "phase-two") return phaseTwo(args);
  if (command === "phase-three") return phaseThree(args);
  throw new Error(
    "Usage: authority-migration.js <phase-one|phase-two|phase-three> [phase arguments]"
  );
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}

module.exports = { directCall, forwardedCall };
