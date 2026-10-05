#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const {
  Interface,
  JsonRpcProvider,
  getAddress,
  id,
  keccak256,
} = require("ethers");

const REPO_ROOT = path.resolve(__dirname, "..");
const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) throw new Error(`Unexpected argument: ${token}`);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      args[token.slice(2)] = true;
    } else {
      args[token.slice(2)] = value;
      index += 1;
    }
  }
  return args;
}

function required(args, name) {
  const value = args[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Missing --${name}`);
  }
  return value;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJsonAtomic(filePath, value) {
  const temporaryPath = `${filePath}.${process.pid}.tmp`;
  fs.writeFileSync(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  fs.renameSync(temporaryPath, filePath);
}

function sameAddress(left, right) {
  return getAddress(left) === getAddress(right);
}

function assertAddress(value, label) {
  if (!ADDRESS_REGEX.test(value || "")) throw new Error(`${label} is not an address`);
  return getAddress(value);
}

async function readCall(provider, target, signature, args = []) {
  const contractInterface = new Interface([`function ${signature}`]);
  const fragment = contractInterface.fragments[0];
  const data = contractInterface.encodeFunctionData(fragment, args);
  const result = await provider.call({ to: target, data });
  const decoded = contractInterface.decodeFunctionResult(fragment, result);
  return decoded.length === 1 ? decoded[0] : decoded;
}

async function preflight(args) {
  const network = required(args, "network");
  const rpcUrl = required(args, "rpc-url");
  const expectedExecutor = assertAddress(
    required(args, "expected-executor"),
    "Expected executor"
  );
  const networkDir = path.join(REPO_ROOT, "deployments", network);
  const config = readJson(path.join(networkDir, "ceremony-config.json"));
  const deployments = readJson(path.join(networkDir, "deployments.json"));
  const inventory = readJson(path.join(networkDir, "factory-inventory.json"));
  if (
    config.schemaVersion !== "2.0.0" ||
    config.ownership?.type !== "authorized-helper" ||
    typeof config.ownership.helperVersion !== "string" ||
    typeof config.ownership.legacyHelperOwnerKey !== "string" ||
    !Array.isArray(config.ownership.retainedAuthorizedAccounts) ||
    !Array.isArray(config.ownership.revokedSphereXEngineOperators)
  ) {
    throw new Error("Ceremony config does not define the authorized-helper preflight");
  }

  const archController = assertAddress(
    deployments[config.ownership.archControllerKey],
    "ArchController deployment"
  );
  const helper = assertAddress(
    args.helper || deployments[config.ownership.helperOwnerKey],
    "Authority helper deployment"
  );
  const provider = new JsonRpcProvider(rpcUrl);
  const rpcNetwork = await provider.getNetwork();
  if (Number(rpcNetwork.chainId) !== inventory.chainId) {
    throw new Error(
      `RPC chain ID ${rpcNetwork.chainId} does not match ${network} inventory ${inventory.chainId}`
    );
  }

  const helperCode = await provider.getCode(helper);
  if (helperCode === "0x") throw new Error("Authority helper has no runtime code");
  const version = await readCall(provider, helper, "version() view returns (string)");
  if (version !== config.ownership.helperVersion) {
    throw new Error(`Authority helper version ${version}; expected ${config.ownership.helperVersion}`);
  }
  const helperArch = await readCall(
    provider,
    helper,
    "archController() view returns (address)"
  );
  if (!sameAddress(helperArch, archController)) {
    throw new Error("Authority helper points at a different ArchController");
  }
  const owner = await readCall(provider, archController, "owner() view returns (address)");
  if (!sameAddress(owner, helper)) throw new Error("Authority helper does not own ArchController");

  const requiredExecutors = [
    expectedExecutor,
    ...config.ownership.retainedAuthorizedAccounts.map((account, index) =>
      assertAddress(account, `Retained authorized account ${index}`)
    ),
  ];
  const requiredExecutorSet = new Set(requiredExecutors);
  if (requiredExecutorSet.size !== requiredExecutors.length) {
    throw new Error("Expected and retained executor lists contain a duplicate");
  }
  const enumeratedExecutors = await readCall(
    provider,
    helper,
    "getAuthorizedAccounts() view returns (address[])"
  );
  const enumerated = new Set(enumeratedExecutors.map((account) => getAddress(account)));
  const reportedExecutorCount = await readCall(
    provider,
    helper,
    "getAuthorizedAccountsCount() view returns (uint256)"
  );
  if (
    enumerated.size !== enumeratedExecutors.length ||
    BigInt(reportedExecutorCount) !== BigInt(enumeratedExecutors.length)
  ) {
    throw new Error("Authority helper executor enumeration is inconsistent");
  }
  if (enumerated.size !== requiredExecutorSet.size) {
    throw new Error(
      `Authority helper has ${enumerated.size} executors; expected exactly ${requiredExecutorSet.size}`
    );
  }
  for (const executor of enumerated) {
    if (!requiredExecutorSet.has(executor)) {
      throw new Error(`Authority helper has unexpected executor ${executor}`);
    }
  }
  for (const executor of requiredExecutors) {
    const authorized = await readCall(
      provider,
      helper,
      "authorizedAccounts(address) view returns (bool)",
      [executor]
    );
    if (!authorized || !enumerated.has(executor)) {
      throw new Error(`Required executor ${executor} is not fully recorded by the helper`);
    }
  }

  const sphereXEngine = await readCall(
    provider,
    archController,
    "sphereXEngine() view returns (address)"
  );
  assertAddress(sphereXEngine, "SphereX engine");
  const engineCode = await provider.getCode(sphereXEngine);
  if (engineCode === "0x") throw new Error("SphereX engine has no runtime code");
  const sphereXAdmin = await readCall(
    provider,
    archController,
    "sphereXAdmin() view returns (address)"
  );
  const pendingSphereXAdmin = await readCall(
    provider,
    archController,
    "pendingSphereXAdmin() view returns (address)"
  );
  const sphereXOperator = await readCall(
    provider,
    archController,
    "sphereXOperator() view returns (address)"
  );
  if (!sameAddress(sphereXAdmin, helper) || !sameAddress(sphereXOperator, helper)) {
    throw new Error("Authority helper does not hold ArchController SphereX admin and operator roles");
  }
  if (BigInt(pendingSphereXAdmin) !== 0n) {
    throw new Error("ArchController still has a pending SphereX admin transfer");
  }

  const defaultAdmin = await readCall(
    provider,
    sphereXEngine,
    "defaultAdmin() view returns (address)"
  );
  const pendingDefaultAdmin = await readCall(
    provider,
    sphereXEngine,
    "pendingDefaultAdmin() view returns (address,uint48)"
  );
  if (!sameAddress(defaultAdmin, helper)) {
    throw new Error("Authority helper is not the SphereX engine default admin");
  }
  if (BigInt(pendingDefaultAdmin[0]) !== 0n || BigInt(pendingDefaultAdmin[1]) !== 0n) {
    throw new Error("SphereX engine still has a pending default-admin transfer");
  }

  const operatorRole = id("OPERATOR_ROLE");
  const senderAdderRole = id("SENDER_ADDER_ROLE");
  if (
    !(await readCall(
      provider,
      sphereXEngine,
      "hasRole(bytes32,address) view returns (bool)",
      [operatorRole, helper]
    ))
  ) {
    throw new Error("Authority helper does not have the SphereX engine operator role");
  }
  for (const accountValue of config.ownership.revokedSphereXEngineOperators) {
    const account = assertAddress(accountValue, "Revoked SphereX engine operator");
    if (
      await readCall(
        provider,
        sphereXEngine,
        "hasRole(bytes32,address) view returns (bool)",
        [operatorRole, account]
      )
    ) {
      throw new Error(`Former SphereX engine operator ${account} still has the role`);
    }
  }
  if (
    !(await readCall(
      provider,
      sphereXEngine,
      "hasRole(bytes32,address) view returns (bool)",
      [senderAdderRole, archController]
    ))
  ) {
    throw new Error("ArchController lost the SphereX engine sender-adder role");
  }

  console.log(`Authority helper preflight GREEN for ${network}`);
  console.log(`Helper: ${helper} (runtime ${keccak256(helperCode)})`);
  console.log(`Executor: ${expectedExecutor}; retained: ${requiredExecutors.length - 1}`);
  console.log(`SphereX engine: ${getAddress(sphereXEngine)}`);
  return { config, deployments, helper, networkDir };
}

async function finalize(args) {
  const helperOverride = assertAddress(required(args, "helper"), "Replacement helper");
  const result = await preflight({ ...args, helper: helperOverride });
  const { config, deployments, networkDir, helper } = result;
  const currentHelper = assertAddress(
    deployments[config.ownership.helperOwnerKey],
    "Current helper deployment"
  );
  const legacyKey = config.ownership.legacyHelperOwnerKey;
  if (
    deployments[legacyKey] &&
    !sameAddress(deployments[legacyKey], currentHelper)
  ) {
    throw new Error(`${legacyKey} already records a different helper`);
  }
  deployments[legacyKey] = currentHelper;
  deployments[config.ownership.helperOwnerKey] = helper;
  const deploymentsPath = path.join(networkDir, "deployments.json");
  writeJsonAtomic(deploymentsPath, deployments);
  console.log(`Authority helper deployment alias finalized: ${helper}`);
}

async function main() {
  const [command, ...argv] = process.argv.slice(2);
  if (command === "preflight") return preflight(parseArgs(argv));
  if (command === "finalize") return finalize(parseArgs(argv));
  {
    throw new Error(
      "Usage: node scripts/authority-helper.js <preflight|finalize> --network <name> --rpc-url <url> --expected-executor <address> [--helper <address>]"
    );
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}

module.exports = { preflight };
