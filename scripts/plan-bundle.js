const fs = require("fs");
const path = require("path");
const {
  Interface,
  TypedDataEncoder,
  Wallet,
  concat,
  dataLength,
  getAddress,
  getCreate2Address,
  hexlify,
  id,
  keccak256,
  toBeHex,
  toUtf8Bytes,
  zeroPadValue,
} = require("ethers");

const SAFE_VERSION = "1.4.1";
const TX_BUILDER_VERSION = "2.0.1";
const CREATE_CALL = getAddress("0x9b35Af71d77eaf8d7e40252370304687390A1A52");
const MULTI_SEND = getAddress("0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526");
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const DEFAULT_MAX_GAS = 20_000_000n;
const STATIC_BUNDLE_OVERHEAD = 120_000n;
const STATIC_DEPLOY_OVERHEAD = 120_000n;
const STATIC_CALL_OVERHEAD = 75_000n;
const THRESHOLD_STORAGE_SLOT = 4n;
const RECENT_LOG_BLOCKS = 100_000n;

const createCallInterface = new Interface([
  "function performCreate2(uint256 value, bytes deploymentData, bytes32 salt) returns (address newContract)",
]);
const multiSendInterface = new Interface([
  "function multiSend(bytes transactions)",
]);
const safeInterface = new Interface([
  "function VERSION() view returns (string)",
  "function getOwners() view returns (address[])",
  "function getThreshold() view returns (uint256)",
  "function nonce() view returns (uint256)",
  "function approveHash(bytes32 hashToApprove)",
  "function getTransactionHash(address to, uint256 value, bytes data, uint8 operation, uint256 safeTxGas, uint256 baseGas, uint256 gasPrice, address gasToken, address refundReceiver, uint256 nonce) view returns (bytes32)",
  "function execTransaction(address to, uint256 value, bytes data, uint8 operation, uint256 safeTxGas, uint256 baseGas, uint256 gasPrice, address gasToken, address payable refundReceiver, bytes signatures) payable returns (bool success)",
  "event ExecutionSuccess(bytes32 txHash, uint256 payment)",
  "event ExecutionFailure(bytes32 txHash, uint256 payment)",
]);

function requiredArg(args, name) {
  const value = args[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Missing --${name}.`);
  }
  return value;
}

function parsePositiveGas(value, context) {
  if (value === undefined) return DEFAULT_MAX_GAS;
  if (
    typeof value !== "string" ||
    !/^(?:[1-9][0-9]*|0x[1-9a-fA-F][0-9a-fA-F]*)$/.test(value)
  ) {
    throw new Error(`${context}: expected a positive integer gas quantity`);
  }
  return BigInt(value);
}

function parseNonce(value, context) {
  if (typeof value !== "string" || !/^(?:0|[1-9][0-9]*)$/.test(value)) {
    throw new Error(`${context}: expected a non-negative decimal Safe nonce`);
  }
  const nonce = BigInt(value);
  if (nonce > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new Error(`${context}: nonce exceeds JavaScript's safe integer range`);
  }
  return nonce;
}

function rpcQuantity(value) {
  return `0x${BigInt(value).toString(16)}`;
}

function resolvePath(repoRoot, value) {
  return path.isAbsolute(value) ? value : path.resolve(repoRoot, value);
}

function planFileHash(planPath) {
  return keccak256(fs.readFileSync(planPath));
}

function hexByteLength(value) {
  return BigInt(dataLength(value));
}

function calldataGas(value) {
  const bytes = Buffer.from(value.slice(2), "hex");
  let gas = 0n;
  for (const byte of bytes) gas += byte === 0 ? 4n : 16n;
  return gas;
}

function packInnerTransaction(entry) {
  return hexlify(
    concat([
      toBeHex(entry.operation, 1),
      entry.to,
      zeroPadValue(toBeHex(entry.value), 32),
      zeroPadValue(toBeHex(dataLength(entry.data)), 32),
      entry.data,
    ])
  );
}

function packMultiSend(entries) {
  const packedTransactions = hexlify(
    concat(entries.map((entry) => packInnerTransaction(entry)))
  );
  return {
    packedTransactions,
    data: multiSendInterface.encodeFunctionData("multiSend", [
      packedTransactions,
    ]),
  };
}

function staticGasEstimate(transaction, innerData, loadedArtifact = null) {
  const base = 21_000n + calldataGas(innerData);
  if (transaction.kind === "call") return base + STATIC_CALL_OVERHEAD;
  const runtimeCode = loadedArtifact?.artifact?.deployedBytecode?.object;
  const runtimeBytes =
    typeof runtimeCode === "string" &&
    /^0x(?:[a-fA-F0-9]{2})*$/.test(runtimeCode)
      ? hexByteLength(runtimeCode)
      : 0n;
  return base + STATIC_DEPLOY_OVERHEAD + runtimeBytes * 200n;
}

function compilePlanEntries(plan, safe, dependencies) {
  const outputs = new Map();
  const expectedAddresses = {};
  const entries = [];

  for (const [index, transaction] of plan.transactions.entries()) {
    if (transaction.reverifyUntil) {
      throw new Error(
        `${transaction.id}: Safe bundling does not support transient predicates; use the EOA ceremony path for temporary ownership steps.`
      );
    }
    const payload = dependencies.transactionPayload(transaction, outputs);
    if (transaction.kind === "deploy") {
      const salt = keccak256(toUtf8Bytes(`${plan.release}:${transaction.id}`));
      const precomputedAddress = getCreate2Address(
        safe,
        salt,
        keccak256(payload.data)
      );
      outputs.set(transaction.output, precomputedAddress);
      expectedAddresses[transaction.id] = precomputedAddress;
      const data = createCallInterface.encodeFunctionData("performCreate2", [
        payload.value,
        payload.data,
        salt,
      ]);
      const loadedArtifact = dependencies.loadArtifact(
        transaction.artifactName
      );
      entries.push({
        index,
        id: transaction.id,
        kind: transaction.kind,
        description: transaction.description,
        operation: 1,
        to: CREATE_CALL,
        logicalTarget: precomputedAddress,
        value: 0n,
        data,
        decodedArgs: dependencies.resolveReferences(
          transaction.constructorArgs.decoded,
          outputs
        ),
        predicate: dependencies.resolveReferences(
          transaction.predicate,
          outputs
        ),
        precomputedAddress,
        salt,
        initCodeHash: keccak256(payload.data),
        staticGasEstimate: staticGasEstimate(transaction, data, loadedArtifact),
        simulatedGas: null,
      });
      continue;
    }

    entries.push({
      index,
      id: transaction.id,
      kind: transaction.kind,
      description: transaction.description,
      operation: 0,
      to: getAddress(payload.to),
      logicalTarget: getAddress(payload.to),
      value: payload.value,
      data: payload.data,
      decodedArgs: dependencies.resolveReferences(transaction.args, outputs),
      predicate: dependencies.resolveReferences(transaction.predicate, outputs),
      precomputedAddress: null,
      salt: null,
      initCodeHash: null,
      staticGasEstimate: staticGasEstimate(transaction, payload.data),
      simulatedGas: null,
    });
  }

  if (outputs.size !== Object.keys(expectedAddresses).length) {
    throw new Error("Bundle compilation left unresolved deployment outputs.");
  }
  return { entries, expectedAddresses, outputs };
}

function packByGas(entries, maxGas, gasField) {
  const bundles = [];
  let current = [];
  let currentGas = STATIC_BUNDLE_OVERHEAD;
  for (const entry of entries) {
    const entryGas = BigInt(entry[gasField]);
    if (entryGas + STATIC_BUNDLE_OVERHEAD > maxGas) {
      throw new Error(
        `${entry.id}: ${gasField} ${entryGas} exceeds max gas ${maxGas}`
      );
    }
    if (current.length > 0 && currentGas + entryGas > maxGas) {
      bundles.push(current);
      current = [];
      currentGas = STATIC_BUNDLE_OVERHEAD;
    }
    current.push(entry);
    currentGas += entryGas;
  }
  if (current.length > 0) bundles.push(current);
  return bundles;
}

function safeTransactionForEntries(entries) {
  const packed = packMultiSend(entries);
  return {
    to: MULTI_SEND,
    value: "0",
    data: packed.data,
    operation: 1,
    packedTransactions: packed.packedTransactions,
  };
}

const SAFE_TX_TYPES = {
  SafeTx: [
    { name: "to", type: "address" },
    { name: "value", type: "uint256" },
    { name: "data", type: "bytes" },
    { name: "operation", type: "uint8" },
    { name: "safeTxGas", type: "uint256" },
    { name: "baseGas", type: "uint256" },
    { name: "gasPrice", type: "uint256" },
    { name: "gasToken", type: "address" },
    { name: "refundReceiver", type: "address" },
    { name: "nonce", type: "uint256" },
  ],
};

function safeTransactionHash(chainId, safe, safeTransaction, nonce) {
  return TypedDataEncoder.hash(
    { chainId, verifyingContract: safe },
    SAFE_TX_TYPES,
    safeTxFields(safeTransaction, nonce)
  );
}

function serializeJsonValue(value) {
  if (Array.isArray(value)) {
    return `[${value.map((entry) => serializeJsonValue(entry)).join(",")}]`;
  }
  if (value !== null && typeof value === "object") {
    const keys = Object.keys(value).sort();
    return `{${keys
      .map(
        (key) => `${JSON.stringify(key)}:${serializeJsonValue(value[key])}`
      )
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

function txBuilderChecksum(batch) {
  const { checksum: _checksum, ...metaWithoutChecksum } = batch.meta;
  return keccak256(
    toUtf8Bytes(
      serializeJsonValue({
        ...batch,
        meta: { ...metaWithoutChecksum, name: null },
      })
    )
  );
}

function txBuilderFile(plan, safe, bundleNumber, safeTransaction) {
  const output = {
    version: "1.0",
    chainId: String(plan.chainId),
    createdAt: Date.now(),
    meta: {
      name: `Wildcat ${plan.release} bundle ${bundleNumber}`,
      description:
        "One encoded MultiSend transaction. The Safe operation MUST be DELEGATECALL (1); Transaction Builder single-row submission defaults to CALL and must not be used to submit this row directly.",
      txBuilderVersion: TX_BUILDER_VERSION,
      safeVersion: SAFE_VERSION,
      requiredSafeOperation: "1",
      createdFromSafeAddress: safe,
      createdFromOwnerAddress: "",
      checksum: "",
    },
    transactions: [
      {
        to: safeTransaction.to,
        value: safeTransaction.value,
        data: safeTransaction.data,
        contractMethod: {
          inputs: [
            { internalType: "bytes", name: "transactions", type: "bytes" },
          ],
          name: "multiSend",
          payable: false,
        },
        contractInputsValues: {
          transactions: safeTransaction.packedTransactions,
        },
      },
    ],
  };
  output.meta.checksum = txBuilderChecksum(output);
  return output;
}

function jsonSafeEntry(entry) {
  return {
    planIndex: entry.index,
    planId: entry.id,
    kind: entry.kind,
    description: entry.description,
    operation: entry.operation,
    to: entry.to,
    logicalTarget: entry.logicalTarget,
    value: entry.value.toString(),
    data: entry.data,
    decodedArgs: entry.decodedArgs,
    predicate: entry.predicate,
    precomputedAddress: entry.precomputedAddress,
    salt: entry.salt,
    initCodeHash: entry.initCodeHash,
    staticGasEstimate: entry.staticGasEstimate.toString(),
    simulatedGas:
      entry.simulatedGas === null ? null : entry.simulatedGas.toString(),
  };
}

function manifestFile(
  plan,
  safe,
  planHash,
  maxGas,
  bundleNumber,
  safeNonce,
  entries,
  actualGas
) {
  const safeTransaction = safeTransactionForEntries(entries);
  const fields = safeTxFields(safeTransaction, safeNonce);
  return {
    schemaVersion: "1.1.0",
    plan: {
      release: plan.release,
      network: plan.network,
      chainId: plan.chainId,
      fileHash: planHash,
    },
    safe: { address: safe, version: SAFE_VERSION },
    bundle: {
      number: bundleNumber,
      safeNonce: safeNonce.toString(),
      maxGas: maxGas.toString(),
      staticGasEstimate: (
        STATIC_BUNDLE_OVERHEAD +
        entries.reduce((total, entry) => total + entry.staticGasEstimate, 0n)
      ).toString(),
      simulatedGas: actualGas === null ? null : actualGas.toString(),
    },
    safeTransaction: {
      to: safeTransaction.to,
      value: safeTransaction.value,
      data: safeTransaction.data,
      operation: safeTransaction.operation,
      safeTxGas: fields.safeTxGas.toString(),
      baseGas: fields.baseGas.toString(),
      gasPrice: fields.gasPrice.toString(),
      gasToken: fields.gasToken,
      refundReceiver: fields.refundReceiver,
      nonce: fields.nonce.toString(),
      safeTxHash: safeTransactionHash(
        plan.chainId,
        safe,
        safeTransaction,
        safeNonce
      ),
    },
    innerTransactions: entries.map(jsonSafeEntry),
  };
}

function oneLine(value) {
  return String(value).replace(/\s+/g, " ").replace(/\|/g, "\\|").trim();
}

function reviewMarkdown(
  plan,
  safe,
  startNonce,
  maxGas,
  bundles,
  actualGasByBundle
) {
  const lines = [
    `# ${plan.release} Safe bundle review`,
    "",
    `- Network: ${plan.network} (chain ID ${plan.chainId})`,
    `- Safe: ${safe}`,
    `- Safe version: ${SAFE_VERSION}`,
    `- Starting Safe nonce: ${startNonce}`,
    `- MultiSend: ${MULTI_SEND}`,
    `- CreateCall: ${CREATE_CALL}`,
    `- Gas ceiling per bundle: ${maxGas}`,
    "- Required outer Safe operation: DELEGATECALL (1)",
    "",
    "> Transaction Builder imports do not preserve a single transaction's Safe operation. Use the manifest's raw Safe transaction with operation 1 when proposing; do not submit the imported single row as a CALL.",
    "",
  ];

  bundles.forEach((entries, index) => {
    const nonce = startNonce + BigInt(index);
    const safeTransaction = safeTransactionForEntries(entries);
    const safeTxHash = safeTransactionHash(
      plan.chainId,
      safe,
      safeTransaction,
      nonce
    );
    const actualGas = actualGasByBundle[index] ?? null;
    const staticGas =
      STATIC_BUNDLE_OVERHEAD +
      entries.reduce((total, entry) => total + entry.staticGasEstimate, 0n);
    lines.push(`## Bundle ${index + 1}`);
    lines.push("");
    lines.push(`Safe nonce: ${nonce}`);
    lines.push("");
    lines.push(`Safe transaction hash: \`${safeTxHash}\``);
    lines.push("");
    lines.push(
      `Gas: ${
        actualGas === null
          ? `static estimate ${staticGas}`
          : `simulated ${actualGas}`
      } / ceiling ${maxGas}`
    );
    lines.push("");
    lines.push(
      "| # | Plan ID | What / why | Target | Result address | Gas | Salt |"
    );
    lines.push("| ---: | --- | --- | --- | --- | ---: | --- |");
    entries.forEach((entry) => {
      const gas = entry.simulatedGas ?? entry.staticGasEstimate;
      lines.push(
        `| ${entry.index + 1} | ${entry.id} | ${oneLine(entry.description)} | ${
          entry.logicalTarget
        } | ${entry.precomputedAddress || "-"} | ${gas} | ${
          entry.salt || "-"
        } |`
      );
    });
    lines.push("");
  });
  return `${lines.join("\n")}\n`;
}

function removeStaleBundleFiles(outDir) {
  if (!fs.existsSync(outDir)) return;
  for (const fileName of fs.readdirSync(outDir)) {
    if (/^bundle-[0-9]+\.(?:txbuilder|manifest)\.json$/.test(fileName)) {
      fs.unlinkSync(path.join(outDir, fileName));
    }
  }
}

function validateTxBuilderFile(value, dependencies) {
  const schemaPath = path.join(
    dependencies.REPO_ROOT,
    "deployments/safe-txbuilder-bundle.schema-1-0.json"
  );
  const schema = dependencies.readJson(schemaPath);
  const errors = dependencies.validateJsonSchema(value, schema, schema);
  if (value.transactions?.length !== 1) {
    errors.push("$.transactions: must contain exactly one transaction");
  }
  if (
    value.meta?.checksum &&
    value.meta.checksum.toLowerCase() !== txBuilderChecksum(value).toLowerCase()
  ) {
    errors.push("$.meta.checksum: does not match the Transaction Builder payload");
  }
  if (errors.length > 0) {
    throw new Error(
      `Generated Transaction Builder file failed schema validation:\n${errors
        .map((error) => `- ${error}`)
        .join("\n")}`
    );
  }
}

function writeBundleArtifacts(context, dependencies) {
  const {
    plan,
    safe,
    planHash,
    startNonce,
    maxGas,
    outDir,
    expectedAddresses,
    bundles,
    actualGasByBundle,
  } = context;
  fs.mkdirSync(outDir, { recursive: true });
  removeStaleBundleFiles(outDir);
  const indexBundles = [];

  bundles.forEach((entries, index) => {
    const bundleNumber = index + 1;
    const safeTransaction = safeTransactionForEntries(entries);
    const txBuilder = txBuilderFile(plan, safe, bundleNumber, safeTransaction);
    validateTxBuilderFile(txBuilder, dependencies);
    const manifest = manifestFile(
      plan,
      safe,
      planHash,
      maxGas,
      bundleNumber,
      startNonce + BigInt(index),
      entries,
      actualGasByBundle[index] ?? null
    );
    const txBuilderName = `bundle-${bundleNumber}.txbuilder.json`;
    const manifestName = `bundle-${bundleNumber}.manifest.json`;
    dependencies.writeJson(path.join(outDir, txBuilderName), txBuilder);
    dependencies.writeJson(path.join(outDir, manifestName), manifest);
    indexBundles.push({
      bundle: bundleNumber,
      txBuilder: txBuilderName,
      manifest: manifestName,
      planIds: entries.map((entry) => entry.id),
      safeTransaction: manifest.safeTransaction,
      safeNonce: manifest.bundle.safeNonce,
      safeTxHash: manifest.safeTransaction.safeTxHash,
      simulatedGas: manifest.bundle.simulatedGas,
    });
  });

  dependencies.writeJson(
    path.join(outDir, "expected-addresses.json"),
    expectedAddresses
  );
  dependencies.writeJson(path.join(outDir, "bundle-index.json"), {
    schemaVersion: "1.1.0",
    planHash,
    release: plan.release,
    network: plan.network,
    chainId: plan.chainId,
    safe,
    safeVersion: SAFE_VERSION,
    startNonce: startNonce.toString(),
    multiSend: MULTI_SEND,
    createCall: CREATE_CALL,
    maxGas: maxGas.toString(),
    bundles: indexBundles,
  });
  fs.writeFileSync(
    path.join(outDir, `review-${plan.release}.md`),
    reviewMarkdown(
      plan,
      safe,
      startNonce,
      maxGas,
      bundles,
      actualGasByBundle
    ),
    "utf8"
  );
}

function assertSafeMatchesPlan(plan, safe) {
  if (safe.toLowerCase() !== plan.expectedExecutor.toLowerCase()) {
    throw new Error(
      `Safe mismatch: plan expects ${plan.expectedExecutor}, selected ${safe}. Regenerate the plan for this Safe before bundling.`
    );
  }
}

function loadBundleContext(args, dependencies) {
  const planPath = resolvePath(
    dependencies.REPO_ROOT,
    requiredArg(args, "plan")
  );
  const plan = dependencies.assertValidPlan(dependencies.readJson(planPath));
  const safe = getAddress(requiredArg(args, "safe"));
  assertSafeMatchesPlan(plan, safe);
  const maxGas = parsePositiveGas(args["max-gas"], "--max-gas");
  const startNonce = parseNonce(
    requiredArg(args, "start-nonce"),
    "--start-nonce"
  );
  const outDir = args["out-dir"]
    ? resolvePath(dependencies.REPO_ROOT, args["out-dir"])
    : path.join(
        dependencies.REPO_ROOT,
        "deployments",
        plan.network,
        `bundles-${plan.release}`
      );
  const compiled = compilePlanEntries(plan, safe, dependencies);
  return {
    planPath,
    planHash: planFileHash(planPath),
    plan,
    safe,
    maxGas,
    startNonce,
    outDir,
    ...compiled,
  };
}

function bundlePlan(args, dependencies) {
  const context = loadBundleContext(args, dependencies);
  const bundles = packByGas(
    context.entries,
    context.maxGas,
    "staticGasEstimate"
  );
  writeBundleArtifacts(
    { ...context, bundles, actualGasByBundle: [] },
    dependencies
  );
  console.log(`Bundle compilation complete: ${context.outDir}`);
  console.log(
    `Precomputed addresses: ${
      Object.keys(context.expectedAddresses).length
    }; unresolved refs: 0.`
  );
  bundles.forEach((entries, index) => {
    const gas =
      STATIC_BUNDLE_OVERHEAD +
      entries.reduce((total, entry) => total + entry.staticGasEstimate, 0n);
    console.log(
      `Bundle ${index + 1}: ${entries
        .map((entry) => entry.id)
        .join(", ")} (static gas ${gas})`
    );
  });
}

async function callFunction(rpc, target, contractInterface, name, args = []) {
  const data = contractInterface.encodeFunctionData(name, args);
  const result = await rpc("eth_call", [{ to: target, data }, "latest"]);
  return contractInterface.decodeFunctionResult(name, result);
}

async function assertRpcChain(rpc, chainId) {
  const actualChainId = Number(BigInt(await rpc("eth_chainId")));
  if (actualChainId !== chainId) {
    throw new Error(
      `RPC chain id mismatch: plan=${chainId}, rpc=${actualChainId}`
    );
  }
}

async function assertBundleContracts(rpc, safe) {
  for (const [label, address] of [
    ["Safe", safe],
    ["CreateCall", CREATE_CALL],
    ["MultiSend", MULTI_SEND],
  ]) {
    const code = await rpc("eth_getCode", [address, "latest"]);
    if (typeof code !== "string" || /^0x0*$/.test(code)) {
      throw new Error(`${label} code is absent at ${address}`);
    }
  }
  const [version] = await callFunction(rpc, safe, safeInterface, "VERSION");
  if (version !== SAFE_VERSION) {
    throw new Error(
      `Safe version mismatch: expected ${SAFE_VERSION}, got ${version}`
    );
  }
}

function preapprovedSignature(owner) {
  return hexlify(
    concat([zeroPadValue(owner, 32), zeroPadValue("0x00", 32), "0x01"])
  );
}

function safeTxFields(safeTransaction, nonce) {
  return {
    to: safeTransaction.to,
    value: 0n,
    data: safeTransaction.data,
    operation: 1,
    safeTxGas: 0n,
    baseGas: 0n,
    gasPrice: 0n,
    gasToken: ZERO_ADDRESS,
    refundReceiver: ZERO_ADDRESS,
    nonce,
  };
}

async function eip712Signature(wallet, chainId, safe, fields) {
  return wallet.signTypedData(
    { chainId, verifyingContract: safe },
    {
      SafeTx: [
        { name: "to", type: "address" },
        { name: "value", type: "uint256" },
        { name: "data", type: "bytes" },
        { name: "operation", type: "uint8" },
        { name: "safeTxGas", type: "uint256" },
        { name: "baseGas", type: "uint256" },
        { name: "gasPrice", type: "uint256" },
        { name: "gasToken", type: "address" },
        { name: "refundReceiver", type: "address" },
        { name: "nonce", type: "uint256" },
      ],
    },
    fields
  );
}

async function safeExecutionData(
  rpc,
  chainId,
  safe,
  owner,
  wallet,
  safeTransaction
) {
  const [nonce] = await callFunction(rpc, safe, safeInterface, "nonce");
  const fields = safeTxFields(safeTransaction, nonce);
  const signature = wallet
    ? await eip712Signature(wallet, chainId, safe, fields)
    : preapprovedSignature(owner);
  const data = safeInterface.encodeFunctionData("execTransaction", [
    fields.to,
    fields.value,
    fields.data,
    fields.operation,
    fields.safeTxGas,
    fields.baseGas,
    fields.gasPrice,
    fields.gasToken,
    fields.refundReceiver,
    signature,
  ]);
  const [safeTxHash] = await callFunction(
    rpc,
    safe,
    safeInterface,
    "getTransactionHash",
    [
      fields.to,
      fields.value,
      fields.data,
      fields.operation,
      fields.safeTxGas,
      fields.baseGas,
      fields.gasPrice,
      fields.gasToken,
      fields.refundReceiver,
      fields.nonce,
    ]
  );
  return { data, fields, safeTxHash };
}

async function sendTransaction(rpc, chainId, wallet, request) {
  if (!wallet) return rpc("eth_sendTransaction", [request]);
  const nonce = BigInt(
    await rpc("eth_getTransactionCount", [wallet.address, "pending"])
  );
  const gasPrice = BigInt(await rpc("eth_gasPrice"));
  const signed = await wallet.signTransaction({
    chainId,
    nonce,
    gasPrice,
    gasLimit: BigInt(request.gas),
    to: request.to,
    value: BigInt(request.value || "0x0"),
    data: request.data,
  });
  return rpc("eth_sendRawTransaction", [signed]);
}

function successfulSafeExecution(receipt, safe, safeTxHash) {
  const successTopic = id("ExecutionSuccess(bytes32,uint256)");
  const failureTopic = id("ExecutionFailure(bytes32,uint256)");
  for (const log of receipt.logs || []) {
    if (log.address?.toLowerCase() !== safe.toLowerCase()) continue;
    if (log.topics?.[1]?.toLowerCase() !== safeTxHash.toLowerCase()) continue;
    if (log.topics[0]?.toLowerCase() === successTopic.toLowerCase())
      return true;
    if (log.topics[0]?.toLowerCase() === failureTopic.toLowerCase())
      return false;
  }
  throw new Error(`Safe receipt has no execution event for ${safeTxHash}`);
}

async function approveSafeHash(rpc, safe, owner, safeTxHash, dependencies) {
  const data = safeInterface.encodeFunctionData("approveHash", [safeTxHash]);
  const gas = BigInt(
    await rpc("eth_estimateGas", [{ from: owner, to: safe, data }])
  );
  const txHash = await rpc("eth_sendTransaction", [
    {
      from: owner,
      to: safe,
      data,
      gas: rpcQuantity((gas * 12n + 9n) / 10n),
    },
  ]);
  const receipt = await dependencies.waitForReceipt(rpc, txHash);
  if (receipt.status !== "0x1") {
    throw new Error(`Safe approveHash reverted: ${txHash}`);
  }
}

async function estimateSafeBundle(rpc, chainId, safe, owner, wallet, entries) {
  const safeTransaction = safeTransactionForEntries(entries);
  const execution = await safeExecutionData(
    rpc,
    chainId,
    safe,
    owner,
    wallet,
    safeTransaction
  );
  return BigInt(
    await rpc("eth_estimateGas", [
      { from: owner, to: safe, data: execution.data },
    ])
  );
}

async function executeSafeBundle(
  rpc,
  chainId,
  safe,
  owner,
  wallet,
  entries,
  gasLimit,
  dependencies
) {
  const safeTransaction = safeTransactionForEntries(entries);
  const execution = await safeExecutionData(
    rpc,
    chainId,
    safe,
    owner,
    wallet,
    safeTransaction
  );
  if (!wallet) {
    await approveSafeHash(rpc, safe, owner, execution.safeTxHash, dependencies);
  }
  const txHash = await sendTransaction(rpc, chainId, wallet, {
    from: owner,
    to: safe,
    data: execution.data,
    value: "0x0",
    gas: rpcQuantity(gasLimit),
  });
  const receipt = await dependencies.waitForReceipt(rpc, txHash);
  if (receipt.status !== "0x1") {
    throw new Error(`Safe execTransaction reverted: ${txHash}`);
  }
  if (!successfulSafeExecution(receipt, safe, execution.safeTxHash)) {
    throw new Error(`Safe inner transaction failed: ${txHash}`);
  }
  return {
    txHash,
    receipt,
    gasUsed: BigInt(receipt.gasUsed),
    safeTxHash: execution.safeTxHash,
  };
}

async function prepareSafeSimulation(rpc, chainId, safe, privateKey) {
  const [ownersResult, thresholdResult] = await Promise.all([
    callFunction(rpc, safe, safeInterface, "getOwners"),
    callFunction(rpc, safe, safeInterface, "getThreshold"),
  ]);
  const owners = ownersResult[0].map(getAddress);
  const thresholdBefore = BigInt(thresholdResult[0]);
  const rawBefore = await rpc("eth_getStorageAt", [
    safe,
    rpcQuantity(THRESHOLD_STORAGE_SLOT),
    "latest",
  ]);
  if (BigInt(rawBefore) !== thresholdBefore) {
    throw new Error(
      `Safe threshold slot verification failed: slot ${THRESHOLD_STORAGE_SLOT} contains ${BigInt(
        rawBefore
      )}, getThreshold() returned ${thresholdBefore}`
    );
  }

  const wallet = privateKey ? new Wallet(privateKey) : null;
  const owner = wallet ? getAddress(wallet.address) : owners[0];
  if (
    !owners.some((candidate) => candidate.toLowerCase() === owner.toLowerCase())
  ) {
    throw new Error(`${owner} is not an owner of Safe ${safe}`);
  }
  if (wallet && thresholdBefore !== 1n) {
    throw new Error(
      `EIP-712 private-key simulation requires a 1-of-N Safe; threshold is ${thresholdBefore}`
    );
  }

  await rpc("anvil_setBalance", [owner, rpcQuantity(100n * 10n ** 18n)]);
  if (!wallet) {
    await rpc("anvil_impersonateAccount", [owner]);
    if (thresholdBefore > 1n) {
      await rpc("anvil_setStorageAt", [
        safe,
        rpcQuantity(THRESHOLD_STORAGE_SLOT),
        zeroPadValue("0x01", 32),
      ]);
    }
    const [thresholdAfterResult, rawAfter] = await Promise.all([
      callFunction(rpc, safe, safeInterface, "getThreshold"),
      rpc("eth_getStorageAt", [
        safe,
        rpcQuantity(THRESHOLD_STORAGE_SLOT),
        "latest",
      ]),
    ]);
    const thresholdAfter = BigInt(thresholdAfterResult[0]);
    if (thresholdAfter !== 1n || BigInt(rawAfter) !== 1n) {
      throw new Error(
        `Safe threshold override failed: getThreshold=${thresholdAfter}, slot=${BigInt(
          rawAfter
        )}`
      );
    }
    console.log(
      `Safe threshold slot ${THRESHOLD_STORAGE_SLOT} verified: ${thresholdBefore} -> ${thresholdAfter}.`
    );
  } else {
    console.log(
      `Safe threshold slot ${THRESHOLD_STORAGE_SLOT} verified at 1; using owner ${owner} EIP-712 signature.`
    );
  }
  return { owner, owners, thresholdBefore, wallet, chainId };
}

function loadExistingBundleContext(args, dependencies) {
  const bundlesDir = resolvePath(
    dependencies.REPO_ROOT,
    requiredArg(args, "bundles")
  );
  const indexPath = path.join(bundlesDir, "bundle-index.json");
  if (!fs.existsSync(indexPath)) {
    throw new Error(`Bundle index not found: ${indexPath}`);
  }
  const index = dependencies.readJson(indexPath);
  if (index.schemaVersion !== "1.1.0") {
    throw new Error(
      `Unsupported bundle index schema ${index.schemaVersion}; expected 1.1.0.`
    );
  }
  const context = loadBundleContext(
    {
      plan: requiredArg(args, "plan"),
      safe: requiredArg(args, "safe"),
      "max-gas": String(index.maxGas),
      "start-nonce": String(index.startNonce),
      "out-dir": bundlesDir,
    },
    dependencies
  );
  if (index.planHash !== context.planHash) {
    throw new Error(
      `Bundle plan hash mismatch: index=${index.planHash}, plan=${context.planHash}`
    );
  }
  if (index.safe?.toLowerCase() !== context.safe.toLowerCase()) {
    throw new Error(
      `Bundle Safe mismatch: index=${index.safe}, selected=${context.safe}`
    );
  }
  return context;
}

async function checkEntryPredicate(rpc, plan, entry, outputs, dependencies) {
  const transaction = plan.transactions[entry.index];
  const result = await dependencies.checkPredicate(
    rpc,
    transaction.predicate,
    outputs
  );
  if (!result.ok) {
    throw new Error(`Predicate failed for ${entry.id}: ${result.detail}`);
  }
  return result.detail;
}

async function largestExecutablePrefix(rpc, context, simulation, startIndex) {
  let lastError = null;
  for (
    let endIndex = context.entries.length;
    endIndex > startIndex;
    endIndex -= 1
  ) {
    const entries = context.entries.slice(startIndex, endIndex);
    try {
      const estimate = await estimateSafeBundle(
        rpc,
        context.plan.chainId,
        context.safe,
        simulation.owner,
        simulation.wallet,
        entries
      );
      if (estimate <= context.maxGas) return { entries, estimate };
      lastError = new Error(
        `${entries[0].id}..${
          entries[entries.length - 1].id
        } estimates ${estimate}, above ${context.maxGas}`
      );
    } catch (error) {
      lastError = error;
    }
  }
  throw new Error(
    `No executable bundle prefix starting at ${
      context.entries[startIndex].id
    }: ${lastError?.message || "unknown estimation error"}`
  );
}

async function simulateBundles(args, dependencies) {
  const context = loadExistingBundleContext(args, dependencies);
  const rpc = dependencies.createRpcClient(requiredArg(args, "rpc"));
  await assertRpcChain(rpc, context.plan.chainId);
  await assertBundleContracts(rpc, context.safe);
  const [onChainNonce] = await callFunction(
    rpc,
    context.safe,
    safeInterface,
    "nonce"
  );
  if (onChainNonce !== context.startNonce) {
    throw new Error(
      `Safe nonce mismatch before simulation: artifacts start at ${context.startNonce}, fork Safe is at ${onChainNonce}`
    );
  }
  const simulation = await prepareSafeSimulation(
    rpc,
    context.plan.chainId,
    context.safe,
    args["private-key"]
  );
  const snapshot = await rpc("evm_snapshot", []);

  console.log(
    "Measuring every plan entry through a one-entry real Safe execution."
  );
  for (const entry of context.entries) {
    const result = await executeSafeBundle(
      rpc,
      context.plan.chainId,
      context.safe,
      simulation.owner,
      simulation.wallet,
      [entry],
      context.maxGas,
      dependencies
    );
    entry.simulatedGas = result.gasUsed;
    const predicate = await checkEntryPredicate(
      rpc,
      context.plan,
      entry,
      context.outputs,
      dependencies
    );
    console.log(
      `[${entry.id}] simulated gas ${result.gasUsed}; predicate green: ${predicate}`
    );
  }

  const reverted = await rpc("evm_revert", [snapshot]);
  if (reverted !== true) {
    throw new Error(
      "Anvil failed to revert the per-entry measurement snapshot."
    );
  }

  console.log(
    `Packing the largest executable plan-order prefixes under ${context.maxGas} gas.`
  );
  const bundles = [];
  const actualGasByBundle = [];
  const bundleReceipts = {};
  let startIndex = 0;
  while (startIndex < context.entries.length) {
    const candidate = await largestExecutablePrefix(
      rpc,
      context,
      simulation,
      startIndex
    );
    const result = await executeSafeBundle(
      rpc,
      context.plan.chainId,
      context.safe,
      simulation.owner,
      simulation.wallet,
      candidate.entries,
      context.maxGas,
      dependencies
    );
    if (result.gasUsed > context.maxGas) {
      throw new Error(
        `Bundle used ${result.gasUsed}, above ceiling ${context.maxGas}`
      );
    }
    for (const entry of candidate.entries) {
      const predicate = await checkEntryPredicate(
        rpc,
        context.plan,
        entry,
        context.outputs,
        dependencies
      );
      console.log(`[${entry.id}] predicate green: ${predicate}`);
    }
    bundles.push(candidate.entries);
    actualGasByBundle.push(result.gasUsed);
    const bundleName = `bundle-${bundles.length}`;
    bundleReceipts[bundleName] = result.txHash;
    console.log(
      `${bundleName}: ${candidate.entries
        .map((entry) => entry.id)
        .join(", ")} (estimated ${candidate.estimate}, used ${result.gasUsed})`
    );
    startIndex += candidate.entries.length;
  }

  writeBundleArtifacts(
    { ...context, bundles, actualGasByBundle },
    dependencies
  );
  dependencies.writeJson(
    path.join(context.outDir, "bundle-receipts.json"),
    bundleReceipts
  );
  if (!simulation.wallet) {
    await rpc("anvil_stopImpersonatingAccount", [simulation.owner]);
  }
  console.log(
    `Bundle simulation passed: ${bundles.length} bundle(s), ${context.entries.length} predicates green.`
  );
}

function jsonEqual(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function loadAndValidateBundles(args, dependencies) {
  const bundlesDir = resolvePath(
    dependencies.REPO_ROOT,
    requiredArg(args, "bundles")
  );
  const indexPath = path.join(bundlesDir, "bundle-index.json");
  if (!fs.existsSync(indexPath)) {
    throw new Error(`Bundle index not found: ${indexPath}`);
  }
  const index = dependencies.readJson(indexPath);
  if (index.schemaVersion !== "1.1.0") {
    throw new Error(
      `Unsupported bundle index schema ${index.schemaVersion}; expected 1.1.0.`
    );
  }
  const planPath = resolvePath(
    dependencies.REPO_ROOT,
    requiredArg(args, "plan")
  );
  const context = loadBundleContext(
    {
      plan: planPath,
      safe: index.safe,
      "max-gas": String(index.maxGas),
      "start-nonce": String(index.startNonce),
      "out-dir": bundlesDir,
    },
    dependencies
  );
  if (context.planHash !== index.planHash) {
    throw new Error(
      `Bundle plan hash mismatch: index=${index.planHash}, plan=${context.planHash}`
    );
  }
  if (String(context.startNonce) !== String(index.startNonce)) {
    throw new Error(
      `Bundle start nonce mismatch: index=${index.startNonce}, compiled=${context.startNonce}`
    );
  }
  const records = [];
  const seenPlanIds = [];
  for (const indexedBundle of index.bundles || []) {
    const txBuilderPath = path.join(bundlesDir, indexedBundle.txBuilder);
    const manifestPath = path.join(bundlesDir, indexedBundle.manifest);
    const txBuilder = dependencies.readJson(txBuilderPath);
    const manifest = dependencies.readJson(manifestPath);
    validateTxBuilderFile(txBuilder, dependencies);
    const entries = indexedBundle.planIds.map((planId) => {
      const entry = context.entries.find(
        (candidate) => candidate.id === planId
      );
      if (!entry)
        throw new Error(`Bundle references unknown plan id ${planId}`);
      return entry;
    });
    const safeTransaction = safeTransactionForEntries(entries);
    const expectedBundleNumber = records.length + 1;
    if (indexedBundle.bundle !== expectedBundleNumber) {
      throw new Error(
        `Bundle index numbers must be contiguous from 1; found ${indexedBundle.bundle}.`
      );
    }
    const expectedSafeTransaction = {
      to: safeTransaction.to,
      value: safeTransaction.value,
      data: safeTransaction.data,
      operation: safeTransaction.operation,
      safeTxGas: "0",
      baseGas: "0",
      gasPrice: "0",
      gasToken: ZERO_ADDRESS,
      refundReceiver: ZERO_ADDRESS,
      nonce: (context.startNonce + BigInt(records.length)).toString(),
      safeTxHash: safeTransactionHash(
        context.plan.chainId,
        context.safe,
        safeTransaction,
        context.startNonce + BigInt(records.length)
      ),
    };
    if (
      manifest.schemaVersion !== "1.1.0" ||
      manifest.bundle.number !== expectedBundleNumber ||
      manifest.bundle.safeNonce !== expectedSafeTransaction.nonce
    ) {
      throw new Error(
        `Bundle ${indexedBundle.bundle} manifest does not pin the expected Safe nonce ${expectedSafeTransaction.nonce}.`
      );
    }
    if (
      manifest.plan.release !== context.plan.release ||
      manifest.plan.network !== context.plan.network ||
      manifest.plan.chainId !== context.plan.chainId ||
      manifest.plan.fileHash !== context.planHash ||
      manifest.safe.address.toLowerCase() !== context.safe.toLowerCase() ||
      manifest.safe.version !== SAFE_VERSION ||
      manifest.bundle.maxGas !== context.maxGas.toString()
    ) {
      throw new Error(
        `Bundle ${indexedBundle.bundle} manifest identity does not match the bundle index and plan.`
      );
    }
    if (
      indexedBundle.safeNonce !== expectedSafeTransaction.nonce ||
      indexedBundle.safeTxHash?.toLowerCase() !==
        expectedSafeTransaction.safeTxHash.toLowerCase()
    ) {
      throw new Error(
        `Bundle ${indexedBundle.bundle} index nonce/hash does not match the compiled Safe transaction.`
      );
    }
    if (!jsonEqual(manifest.safeTransaction, expectedSafeTransaction)) {
      throw new Error(
        `Bundle ${indexedBundle.bundle} manifest Safe transaction does not match the plan.`
      );
    }
    const imported = txBuilder.transactions[0];
    if (
      txBuilder.chainId !== String(context.plan.chainId) ||
      txBuilder.meta.createdFromSafeAddress.toLowerCase() !==
        context.safe.toLowerCase() ||
      imported.to.toLowerCase() !== safeTransaction.to.toLowerCase() ||
      imported.value !== safeTransaction.value ||
      imported.data.toLowerCase() !== safeTransaction.data.toLowerCase() ||
      imported.contractInputsValues.transactions.toLowerCase() !==
        safeTransaction.packedTransactions.toLowerCase()
    ) {
      throw new Error(
        `Bundle ${indexedBundle.bundle} Transaction Builder payload does not match the manifest.`
      );
    }
    const expectedStaticGas = (
      STATIC_BUNDLE_OVERHEAD +
      entries.reduce((total, entry) => total + entry.staticGasEstimate, 0n)
    ).toString();
    if (
      manifest.bundle.staticGasEstimate !== expectedStaticGas ||
      manifest.bundle.simulatedGas !== indexedBundle.simulatedGas
    ) {
      throw new Error(
        `Bundle ${indexedBundle.bundle} gas metadata does not match the compiled bundle index.`
      );
    }
    if (manifest.bundle.simulatedGas !== null) {
      const simulatedGas = parsePositiveGas(
        manifest.bundle.simulatedGas,
        `Bundle ${indexedBundle.bundle} simulatedGas`
      );
      if (simulatedGas > context.maxGas) {
        throw new Error(
          `Bundle ${indexedBundle.bundle} simulated gas exceeds its ceiling.`
        );
      }
    }
    if (
      !jsonEqual(
        manifest.innerTransactions.map((entry) => entry.planId),
        indexedBundle.planIds
      )
    ) {
      throw new Error(
        `Bundle ${indexedBundle.bundle} manifest plan ids do not match its index.`
      );
    }
    const manifestFields = [
      "planIndex",
      "planId",
      "kind",
      "description",
      "operation",
      "to",
      "logicalTarget",
      "value",
      "data",
      "decodedArgs",
      "predicate",
      "precomputedAddress",
      "salt",
      "initCodeHash",
      "staticGasEstimate",
    ];
    manifest.innerTransactions.forEach((manifestEntry, entryIndex) => {
      const expectedEntry = jsonSafeEntry(entries[entryIndex]);
      for (const field of manifestFields) {
        if (!jsonEqual(manifestEntry[field], expectedEntry[field])) {
          throw new Error(
            `Bundle ${indexedBundle.bundle} ${manifestEntry.planId}.${field} does not match the compiled plan.`
          );
        }
      }
      if (
        context.plan.chainId === 1 &&
        (manifestEntry.simulatedGas === null ||
          !/^[1-9][0-9]*$/.test(manifestEntry.simulatedGas))
      ) {
        throw new Error(
          `Bundle ${indexedBundle.bundle} ${manifestEntry.planId} lacks mainnet-fork simulated gas.`
        );
      }
    });
    if (
      context.plan.chainId === 1 &&
      (manifest.bundle.simulatedGas === null ||
        !/^[1-9][0-9]*$/.test(manifest.bundle.simulatedGas))
    ) {
      throw new Error(
        `Bundle ${indexedBundle.bundle} lacks mainnet-fork simulated gas.`
      );
    }
    seenPlanIds.push(...indexedBundle.planIds);
    records.push({
      name: `bundle-${indexedBundle.bundle}`,
      txBuilderName: indexedBundle.txBuilder,
      manifestName: indexedBundle.manifest,
      entries,
      safeTransaction: expectedSafeTransaction,
    });
  }
  if (
    !jsonEqual(
      seenPlanIds,
      context.entries.map((entry) => entry.id)
    )
  ) {
    throw new Error(
      "Bundles do not cover every plan entry exactly in plan order."
    );
  }
  const expectedAddresses = dependencies.readJson(
    path.join(bundlesDir, "expected-addresses.json")
  );
  if (!jsonEqual(expectedAddresses, context.expectedAddresses)) {
    throw new Error(
      "expected-addresses.json does not match the compiled plan."
    );
  }
  return { ...context, records };
}

function matchingExecTransaction(transaction, safe, record) {
  if (!transaction || transaction.to?.toLowerCase() !== safe.toLowerCase()) {
    return false;
  }
  let parsed;
  try {
    parsed = safeInterface.parseTransaction({ data: transaction.input });
  } catch (_error) {
    return false;
  }
  if (!parsed || parsed.name !== "execTransaction") return false;
  return (
    parsed.args[0].toLowerCase() === record.safeTransaction.to.toLowerCase() &&
    BigInt(parsed.args[1]) === 0n &&
    parsed.args[2].toLowerCase() ===
      record.safeTransaction.data.toLowerCase() &&
    BigInt(parsed.args[3]) === 1n
  );
}

function hasSafeExecutionSuccess(receipt, safe, safeTxHash) {
  const successTopic = id("ExecutionSuccess(bytes32,uint256)").toLowerCase();
  return (receipt.logs || []).some(
    (log) =>
      log.address?.toLowerCase() === safe.toLowerCase() &&
      log.topics?.[0]?.toLowerCase() === successTopic &&
      log.topics?.[1]?.toLowerCase() === safeTxHash.toLowerCase()
  );
}

function txHashForRecord(mapping, record, index) {
  return (
    mapping[record.name] ||
    mapping[String(index + 1)] ||
    mapping[record.txBuilderName] ||
    mapping[record.manifestName]
  );
}

async function scanRecentBundleTransactions(rpc, context) {
  const matches = {};
  const latest = BigInt(await rpc("eth_blockNumber"));
  const earliest = latest > RECENT_LOG_BLOCKS ? latest - RECENT_LOG_BLOCKS : 0n;
  for (
    let blockNumber = latest;
    blockNumber >= earliest &&
    Object.keys(matches).length < context.records.length;
    blockNumber -= 1n
  ) {
    const block = await rpc("eth_getBlockByNumber", [
      rpcQuantity(blockNumber),
      true,
    ]);
    for (const transaction of (block?.transactions || []).reverse()) {
      for (const record of context.records) {
        if (matches[record.name]) continue;
        if (matchingExecTransaction(transaction, context.safe, record)) {
          matches[record.name] = transaction.hash;
        }
      }
    }
  }
  return matches;
}

async function resolveBundleReceipts(rpc, context, mapping) {
  const receipts = new Map();
  for (const [index, record] of context.records.entries()) {
    const txHash = txHashForRecord(mapping, record, index);
    if (typeof txHash !== "string" || !/^0x[a-fA-F0-9]{64}$/.test(txHash)) {
      throw new Error(`Missing valid transaction hash for ${record.name}`);
    }
    const [transaction, receipt] = await Promise.all([
      rpc("eth_getTransactionByHash", [txHash]),
      rpc("eth_getTransactionReceipt", [txHash]),
    ]);
    if (!receipt || receipt.status !== "0x1") {
      throw new Error(`${record.name} does not have a successful receipt.`);
    }
    if (!matchingExecTransaction(transaction, context.safe, record)) {
      throw new Error(
        `${record.name} receipt transaction does not execute the expected Safe payload.`
      );
    }
    if (
      !hasSafeExecutionSuccess(
        receipt,
        context.safe,
        record.safeTransaction.safeTxHash
      )
    ) {
      throw new Error(
        `${record.name} receipt lacks ExecutionSuccess for ${record.safeTransaction.safeTxHash}.`
      );
    }
    receipts.set(record.name, { txHash, receipt });
  }
  return receipts;
}

async function verifyBundles(args, dependencies) {
  const context = loadAndValidateBundles(args, dependencies);
  const rpc = dependencies.createRpcClient(requiredArg(args, "rpc"));
  await assertRpcChain(rpc, context.plan.chainId);
  await assertBundleContracts(rpc, context.safe);
  let mapping;
  if (args["tx-hashes"]) {
    mapping = dependencies.readJson(
      resolvePath(dependencies.REPO_ROOT, args["tx-hashes"])
    );
  } else {
    console.log(
      `Scanning the Safe's most recent ${RECENT_LOG_BLOCKS} blocks for matching execTransaction calls.`
    );
    mapping = await scanRecentBundleTransactions(rpc, context);
  }
  const receipts = await resolveBundleReceipts(rpc, context, mapping);
  const runState = {};
  for (const record of context.records) {
    const bundleReceipt = receipts.get(record.name);
    for (const entry of record.entries) {
      const predicate = await checkEntryPredicate(
        rpc,
        context.plan,
        entry,
        context.outputs,
        dependencies
      );
      const stateEntry = {
        txHash: bundleReceipt.txHash,
        blockNumber: dependencies.receiptBlockNumber(bundleReceipt.receipt),
        status: "verified",
      };
      if (entry.kind === "deploy") {
        stateEntry.resolvedAddress = entry.precomputedAddress;
      }
      runState[entry.id] = stateEntry;
      console.log(`VERIFIED ${entry.id}: ${predicate}`);
    }
  }
  const statePath = dependencies.runStatePath(context.plan);
  dependencies.writeJsonAtomic(statePath, runState);
  console.log(
    `Bundle verification passed: ${context.entries.length} predicates. Run state: ${statePath}`
  );
}

function packageArtifact(filePath) {
  const json = fs.readFileSync(filePath, "utf8");
  JSON.parse(json);
  return {
    name: path.basename(filePath),
    hash: keccak256(Buffer.from(json, "utf8")),
    json,
  };
}

function ceremonyFingerprint(digest) {
  return digest
    .slice(2, 14)
    .toUpperCase()
    .match(/.{1,4}/g)
    .join("-");
}

function writeCeremonyPackage(args, dependencies) {
  const mode = requiredArg(args, "mode");
  if (mode !== "eoa" && mode !== "safe") {
    throw new Error(`--mode must be eoa or safe; received ${mode}`);
  }
  const planPath = resolvePath(
    dependencies.REPO_ROOT,
    requiredArg(args, "plan")
  );
  const plan = dependencies.assertValidPlan(dependencies.readJson(planPath));
  if (mode === "eoa" && plan.chainId === 1) {
    throw new Error("Ethereum mainnet ceremony packages must use Safe mode.");
  }
  if (mode === "eoa" && args.bundles !== undefined) {
    throw new Error("--bundles is not valid for an EOA ceremony package.");
  }

  let manifests = [];
  let expectedAddresses = null;
  if (mode === "safe") {
    const context = loadAndValidateBundles(
      { plan: planPath, bundles: requiredArg(args, "bundles") },
      dependencies
    );
    manifests = context.records.map((record) =>
      packageArtifact(path.join(context.outDir, record.manifestName))
    );
    expectedAddresses = packageArtifact(
      path.join(context.outDir, "expected-addresses.json")
    );
  }

  const payload = {
    mode,
    release: plan.release,
    network: plan.network,
    chainId: plan.chainId,
    artifacts: {
      plan: packageArtifact(planPath),
      manifests,
      expectedAddresses,
    },
  };
  const digest = keccak256(toUtf8Bytes(serializeJsonValue(payload)));
  const ceremonyPackage = {
    schemaVersion: "1.0.0",
    digest,
    payload,
  };
  const schemaPath = path.join(
    dependencies.REPO_ROOT,
    "deployments/ceremony-package.schema-1-0.json"
  );
  const schema = dependencies.readJson(schemaPath);
  const errors = dependencies.validateJsonSchema(
    ceremonyPackage,
    schema,
    schema
  );
  if (errors.length > 0) {
    throw new Error(
      `Ceremony package failed schema validation:\n${errors
        .map((error) => `- ${error}`)
        .join("\n")}`
    );
  }
  const outPath = args.out
    ? resolvePath(dependencies.REPO_ROOT, args.out)
    : path.join(
        dependencies.REPO_ROOT,
        "deployments",
        plan.network,
        `ceremony-${plan.release}-${mode}.json`
      );
  dependencies.writeJson(outPath, ceremonyPackage);
  console.log(`Ceremony package written: ${outPath}`);
  console.log(`Ceremony digest: ${digest}`);
  console.log(`Call-time fingerprint: ${ceremonyFingerprint(digest)}`);
}

module.exports = function createBundleCommands(dependencies) {
  return {
    bundlePlan: (args) => bundlePlan(args, dependencies),
    simulateBundles: (args) => simulateBundles(args, dependencies),
    verifyBundles: (args) => verifyBundles(args, dependencies),
    writeCeremonyPackage: (args) => writeCeremonyPackage(args, dependencies),
  };
};
