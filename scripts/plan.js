#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const readline = require("readline/promises");
const {
  AbiCoder,
  Interface,
  Wallet,
  getAddress,
  keccak256,
} = require("ethers");

const PLAN_SCHEMA_VERSION = "1.1.0";
const REQUIRED_FOUNDRY_PROFILE = "deploy";
const SCHEMA_PATH = path.resolve(
  __dirname,
  "../deployments/deployment-plan.schema-1-1.json"
);
const REPO_ROOT = path.resolve(__dirname, "..");
const FOUNDRY_CONFIG = JSON.parse(
  execFileSync("forge", ["config", "--basic", "--json"], {
    cwd: REPO_ROOT,
    encoding: "utf8",
  })
);
const OUT_DIR = path.resolve(REPO_ROOT, FOUNDRY_CONFIG.out);
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;
const SAFE_ID_REGEX = /^[^.]+$/;
const HEX_DATA_REGEX = /^0x(?:[a-fA-F0-9]{2})*$/;
const AUTHORITY_HELPER_FORWARD_SIGNATURE =
  "executeProtocolAction(address,bytes)";
const NETWORK_CHAIN_IDS = {
  mainnet: 1,
  sepolia: 11155111,
  anvil: 31337,
};

function printUsage() {
  console.log(`Usage:
  node scripts/plan.js assemble --network <name> --release <tag>
    [--entries <directory-name>]
  node scripts/plan.js validate --plan <path>
  node scripts/plan.js execute --plan <path> --rpc <url>
    [--private-key <key> | --impersonate <address>] [--run-state <path>] [--yes]
  node scripts/plan.js verify --plan <path> --run-state <path> --rpc <url>
  node scripts/plan.js verify-eoa-run-state --plan <path> --run-state <path>
    --rpc <url>
  node scripts/plan.js render-safe --plan <path>
  node scripts/plan.js bundle --plan <path> --safe <address>
    --start-nonce <n> [--max-gas <n>] [--out-dir <dir>]
  node scripts/plan.js bundle-simulate --plan <path> --bundles <dir>
    --rpc <fork-url> --safe <address> [--private-key <key>]
  node scripts/plan.js bundle-verify --plan <path> --bundles <dir>
    --rpc <url> [--tx-hashes <json>]
  node scripts/plan.js ceremony-package --plan <path> --mode <eoa|safe>
    [--bundles <dir>] [--out <path>]

assemble reads deployments/<network>/<entries>/*.json and writes
deployments/<network>/plan-<release>.json.
`);
}

const KNOWN_FLAGS = {
  assemble: ["network", "release", "entries"],
  validate: ["plan"],
  execute: ["plan", "rpc", "private-key", "impersonate", "run-state", "yes"],
  verify: ["plan", "run-state", "rpc"],
  "verify-eoa-run-state": ["plan", "run-state", "rpc"],
  "render-safe": ["plan"],
  bundle: ["plan", "safe", "start-nonce", "max-gas", "out-dir"],
  "bundle-simulate": ["plan", "bundles", "rpc", "safe", "private-key"],
  "bundle-verify": ["plan", "bundles", "rpc", "tx-hashes"],
  "ceremony-package": ["plan", "mode", "bundles", "out"],
};

function assertKnownFlags(command, args) {
  const known = KNOWN_FLAGS[command];
  if (!known) return;
  for (const key of Object.keys(args)) {
    if (!known.includes(key)) {
      throw new Error(
        `Unknown flag --${key} for ${command}. Known: ${known
          .map((flag) => `--${flag}`)
          .join(", ")}`
      );
    }
  }
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) {
      throw new Error(`Unexpected argument: ${token}`);
    }
    const key = token.slice(2);
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

function ensureDirForFile(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
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

function jsonEqual(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function schemaTypeMatches(value, expectedType) {
  if (expectedType === "null") return value === null;
  if (expectedType === "array") return Array.isArray(value);
  if (expectedType === "object") {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }
  if (expectedType === "integer") return Number.isInteger(value);
  return typeof value === expectedType;
}

function resolveSchemaReference(rootSchema, reference) {
  if (!reference.startsWith("#/")) {
    throw new Error(`Unsupported schema reference: ${reference}`);
  }
  return reference
    .slice(2)
    .split("/")
    .map((part) => part.replace(/~1/g, "/").replace(/~0/g, "~"))
    .reduce((value, part) => value?.[part], rootSchema);
}

function validateJsonSchema(
  value,
  schema,
  rootSchema,
  valuePath = "$",
  errors = []
) {
  if (!schema || typeof schema !== "object") return errors;

  if (schema.$ref) {
    const referencedSchema = resolveSchemaReference(rootSchema, schema.$ref);
    if (!referencedSchema) {
      errors.push(`${valuePath}: unresolved schema reference ${schema.$ref}`);
      return errors;
    }
    validateJsonSchema(value, referencedSchema, rootSchema, valuePath, errors);
  }

  if (schema.allOf) {
    for (const part of schema.allOf) {
      validateJsonSchema(value, part, rootSchema, valuePath, errors);
    }
  }

  if (schema.anyOf) {
    const matched = schema.anyOf.some((part) => {
      const branchErrors = [];
      validateJsonSchema(value, part, rootSchema, valuePath, branchErrors);
      return branchErrors.length === 0;
    });
    if (!matched)
      errors.push(`${valuePath}: must match at least one allowed schema`);
  }

  if (schema.oneOf) {
    const matchCount = schema.oneOf.filter((part) => {
      const branchErrors = [];
      validateJsonSchema(value, part, rootSchema, valuePath, branchErrors);
      return branchErrors.length === 0;
    }).length;
    if (matchCount !== 1) {
      errors.push(`${valuePath}: must match exactly one allowed schema`);
    }
  }

  if (schema.if) {
    const conditionErrors = [];
    validateJsonSchema(
      value,
      schema.if,
      rootSchema,
      valuePath,
      conditionErrors
    );
    if (conditionErrors.length === 0 && schema.then) {
      validateJsonSchema(value, schema.then, rootSchema, valuePath, errors);
    } else if (conditionErrors.length > 0 && schema.else) {
      validateJsonSchema(value, schema.else, rootSchema, valuePath, errors);
    }
  }

  if (schema.const !== undefined && !jsonEqual(value, schema.const)) {
    errors.push(`${valuePath}: must equal ${JSON.stringify(schema.const)}`);
  }
  if (schema.enum && !schema.enum.some((entry) => jsonEqual(value, entry))) {
    errors.push(`${valuePath}: must be one of ${schema.enum.join(", ")}`);
  }

  if (schema.type) {
    const expectedTypes = Array.isArray(schema.type)
      ? schema.type
      : [schema.type];
    if (!expectedTypes.some((type) => schemaTypeMatches(value, type))) {
      errors.push(`${valuePath}: must be ${expectedTypes.join(" or ")}`);
      return errors;
    }
  }

  if (typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) {
      errors.push(`${valuePath}: must have length >= ${schema.minLength}`);
    }
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) {
      errors.push(`${valuePath}: must match pattern ${schema.pattern}`);
    }
  }

  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) {
      errors.push(`${valuePath}: must be >= ${schema.minimum}`);
    }
  }

  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      errors.push(
        `${valuePath}: must contain at least ${schema.minItems} item(s)`
      );
    }
    if (schema.uniqueItems) {
      const keys = value.map((entry) => JSON.stringify(entry));
      if (new Set(keys).size !== keys.length) {
        errors.push(`${valuePath}: items must be unique`);
      }
    }
    if (schema.items) {
      value.forEach((entry, index) => {
        validateJsonSchema(
          entry,
          schema.items,
          rootSchema,
          `${valuePath}[${index}]`,
          errors
        );
      });
    }
  }

  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    if (schema.required) {
      for (const key of schema.required) {
        if (!Object.prototype.hasOwnProperty.call(value, key)) {
          errors.push(`${valuePath}: missing required property ${key}`);
        }
      }
    }
    if (schema.properties) {
      for (const [key, propertySchema] of Object.entries(schema.properties)) {
        if (Object.prototype.hasOwnProperty.call(value, key)) {
          validateJsonSchema(
            value[key],
            propertySchema,
            rootSchema,
            `${valuePath}.${key}`,
            errors
          );
        }
      }
    }
    if (schema.additionalProperties !== undefined) {
      const knownProperties = new Set(Object.keys(schema.properties || {}));
      for (const [key, entry] of Object.entries(value)) {
        if (knownProperties.has(key)) continue;
        if (schema.additionalProperties === false) {
          errors.push(`${valuePath}: unexpected property ${key}`);
        } else if (typeof schema.additionalProperties === "object") {
          validateJsonSchema(
            entry,
            schema.additionalProperties,
            rootSchema,
            `${valuePath}.${key}`,
            errors
          );
        }
      }
    }
  }

  return errors;
}

function isReference(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.keys(value).length === 1 &&
    typeof value.$ref === "string"
  );
}

function collectReferences(value, references = []) {
  if (isReference(value)) {
    references.push(value.$ref);
    return references;
  }
  if (Array.isArray(value)) {
    for (const entry of value) collectReferences(entry, references);
    return references;
  }
  if (value !== null && typeof value === "object") {
    for (const entry of Object.values(value))
      collectReferences(entry, references);
  }
  return references;
}

function validateReferenceObjects(value, valuePath, errors) {
  if (Array.isArray(value)) {
    value.forEach((entry, index) =>
      validateReferenceObjects(entry, `${valuePath}[${index}]`, errors)
    );
    return;
  }
  if (value === null || typeof value !== "object") return;
  if (Object.prototype.hasOwnProperty.call(value, "$ref")) {
    if (!isReference(value)) {
      errors.push(`${valuePath}: a $ref object may contain only $ref`);
    } else if (!SAFE_ID_REGEX.test(value.$ref)) {
      errors.push(`${valuePath}.$ref: reference ids must not contain dots`);
    }
    return;
  }
  for (const [key, entry] of Object.entries(value)) {
    validateReferenceObjects(entry, `${valuePath}.${key}`, errors);
  }
}

function resolveReferences(value, outputs) {
  if (isReference(value)) {
    if (!outputs.has(value.$ref)) {
      throw new Error(`Unresolved output reference: ${value.$ref}`);
    }
    return outputs.get(value.$ref);
  }
  if (Array.isArray(value)) {
    return value.map((entry) => resolveReferences(entry, outputs));
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [
        key,
        resolveReferences(entry, outputs),
      ])
    );
  }
  return value;
}

function replaceReferencesWithZero(value) {
  if (isReference(value)) return ZERO_ADDRESS;
  if (Array.isArray(value)) return value.map(replaceReferencesWithZero);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [
        key,
        replaceReferencesWithZero(entry),
      ])
    );
  }
  return value;
}

let artifactFiles;

function assertDeployProfile() {
  const profile = process.env.FOUNDRY_PROFILE || "default";
  if (profile !== REQUIRED_FOUNDRY_PROFILE) {
    throw new Error(
      `Deployment artifacts require FOUNDRY_PROFILE=${REQUIRED_FOUNDRY_PROFILE}; current profile is ${profile}`
    );
  }
}

function listArtifactFiles(directory) {
  if (!fs.existsSync(directory)) return [];
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...listArtifactFiles(entryPath));
    } else if (entry.name.endsWith(".json")) {
      files.push(entryPath);
    }
  }
  return files;
}

function artifactIdentity(artifact) {
  const compilationTarget =
    artifact.metadata?.settings?.compilationTarget || {};
  const entries = Object.entries(compilationTarget);
  if (entries.length !== 1) return null;
  return { sourceName: entries[0][0], contractName: entries[0][1] };
}

function artifactDeploymentSurface(artifact) {
  return {
    abi: artifact.abi,
    bytecode: artifact.bytecode,
    deployedBytecode: artifact.deployedBytecode,
    rawMetadata: artifact.rawMetadata,
  };
}

function collapseDuplicateArtifactCandidates(candidates, artifactName) {
  const byIdentity = new Map();
  for (const candidate of candidates) {
    const identity = `${candidate.sourceName}:${candidate.contractName}`;
    const existing = byIdentity.get(identity);
    if (!existing) {
      byIdentity.set(identity, candidate);
      continue;
    }
    if (
      !jsonEqual(
        artifactDeploymentSurface(existing.artifact),
        artifactDeploymentSurface(candidate.artifact)
      )
    ) {
      const paths = [existing.filePath, candidate.filePath]
        .map((filePath) => path.relative(REPO_ROOT, filePath))
        .join(", ");
      throw new Error(
        `Artifact "${artifactName}" has conflicting compiled copies for ${identity} (${paths}); run FOUNDRY_PROFILE=deploy forge clean and rebuild`
      );
    }
  }
  return [...byIdentity.values()];
}

function loadArtifact(artifactName) {
  assertDeployProfile();
  const separator = artifactName.lastIndexOf(":");
  const requestedSource =
    separator === -1 ? null : artifactName.slice(0, separator);
  const requestedContract =
    separator === -1 ? artifactName : artifactName.slice(separator + 1);
  if (!requestedContract)
    throw new Error(`Invalid artifact name: ${artifactName}`);

  artifactFiles ||= listArtifactFiles(OUT_DIR);
  const discoveredCandidates = [];
  for (const filePath of artifactFiles) {
    if (path.basename(filePath) !== `${requestedContract}.json`) continue;
    let artifact;
    try {
      artifact = readJson(filePath);
    } catch (_error) {
      continue;
    }
    const identity = artifactIdentity(artifact);
    if (!identity || identity.contractName !== requestedContract) continue;
    if (requestedSource && identity.sourceName !== requestedSource) continue;
    discoveredCandidates.push({ artifact, filePath, ...identity });
  }

  const candidates = collapseDuplicateArtifactCandidates(
    discoveredCandidates,
    artifactName
  );

  if (candidates.length === 0) {
    throw new Error(`Artifact "${artifactName}" was not found in out/`);
  }

  if (!requestedSource) {
    const conventionalPath = path.join(
      OUT_DIR,
      `${requestedContract}.sol`,
      `${requestedContract}.json`
    );
    const conventional = candidates.find(
      (candidate) => path.resolve(candidate.filePath) === conventionalPath
    );
    if (conventional) return conventional;
  }

  if (candidates.length > 1) {
    const names = candidates
      .map((candidate) => candidate.sourceName)
      .join(", ");
    throw new Error(
      `Artifact "${artifactName}" is ambiguous; use source.sol:ContractName (${names})`
    );
  }
  return candidates[0];
}

function assertArtifactFresh(loadedArtifact) {
  const { artifact, filePath } = loadedArtifact;
  if (typeof artifact.rawMetadata !== "string") {
    throw new Error(
      `Artifact lacks rawMetadata: ${path.relative(REPO_ROOT, filePath)}`
    );
  }
  let rawMetadata;
  try {
    rawMetadata = JSON.parse(artifact.rawMetadata);
  } catch (error) {
    throw new Error(
      `Artifact rawMetadata is invalid in ${path.relative(
        REPO_ROOT,
        filePath
      )}: ${error.message}`
    );
  }

  for (const [sourceName, sourceMetadata] of Object.entries(
    rawMetadata.sources || {}
  )) {
    const sourcePath = path.resolve(REPO_ROOT, sourceName);
    if (!fs.existsSync(sourcePath)) {
      throw new Error(
        `Artifact is stale: source ${sourceName} recorded by ${path.relative(
          REPO_ROOT,
          filePath
        )} is missing`
      );
    }
    const actualHash = keccak256(fs.readFileSync(sourcePath));
    if (actualHash.toLowerCase() !== sourceMetadata.keccak256?.toLowerCase()) {
      throw new Error(
        `Artifact is stale: source hash changed for ${sourceName}; run forge build`
      );
    }
  }
}

function artifactInitCode(loadedArtifact) {
  const bytecode = loadedArtifact.artifact.bytecode?.object;
  if (!HEX_DATA_REGEX.test(bytecode || "")) {
    throw new Error(
      `Artifact has missing, invalid, or unlinked bytecode: ${path.relative(
        REPO_ROOT,
        loadedArtifact.filePath
      )}`
    );
  }
  const linkReferences = loadedArtifact.artifact.bytecode?.linkReferences || {};
  const unresolvedLinks = Object.values(linkReferences).some((contracts) =>
    Object.values(contracts).some((locations) => locations.length > 0)
  );
  if (unresolvedLinks) {
    throw new Error(
      `Artifact bytecode has unresolved library links: ${path.relative(
        REPO_ROOT,
        loadedArtifact.filePath
      )}`
    );
  }
  return bytecode;
}

function constructorInputs(loadedArtifact) {
  const contractInterface = new Interface(loadedArtifact.artifact.abi || []);
  return contractInterface.deploy.inputs;
}

function constructorTypes(loadedArtifact) {
  return constructorInputs(loadedArtifact).map((input) =>
    input.format("sighash")
  );
}

function encodeTypedConstructorArgs(types, decodedArgs, outputs = null) {
  const args = outputs
    ? resolveReferences(decodedArgs, outputs)
    : replaceReferencesWithZero(decodedArgs);
  if (types.length !== decodedArgs.length) {
    throw new Error(
      `constructor expects ${types.length} argument(s), got ${decodedArgs.length}`
    );
  }
  return AbiCoder.defaultAbiCoder().encode(types, args);
}

function encodeConstructorArgs(loadedArtifact, decodedArgs, outputs = null) {
  return encodeTypedConstructorArgs(
    constructorTypes(loadedArtifact),
    decodedArgs,
    outputs
  );
}

function functionInterface(signature) {
  const declaration = signature.trim().startsWith("function ")
    ? signature.trim()
    : `function ${signature.trim()}`;
  const contractInterface = new Interface([declaration]);
  const fragment = contractInterface.fragments.find(
    (entry) => entry.type === "function"
  );
  if (!fragment) throw new Error(`Invalid function signature: ${signature}`);
  return { contractInterface, fragment };
}

function encodeFunctionCall(signature, args, outputs = null) {
  const resolvedArgs = outputs
    ? resolveReferences(args, outputs)
    : replaceReferencesWithZero(args);
  const { contractInterface, fragment } = functionInterface(signature);
  return contractInterface.encodeFunctionData(fragment, resolvedArgs);
}

function encodeForwardedCall(transaction, outputs = null) {
  const forwardedCall = transaction.forwardedCall;
  if (!forwardedCall || typeof forwardedCall !== "object") {
    throw new Error("Missing forwarded call");
  }
  const target = outputs
    ? resolveReferences(forwardedCall.target, outputs)
    : replaceReferencesWithZero(forwardedCall.target);
  if (!ADDRESS_REGEX.test(target || "")) {
    throw new Error(`Resolved invalid forwarded target ${target}`);
  }
  const data = encodeFunctionCall(
    forwardedCall.functionSignature,
    forwardedCall.args,
    outputs
  );
  return encodeFunctionCall(transaction.functionSignature, [target, data]);
}

function transactionReferenceFields(transaction) {
  const values = [transaction.envelope?.to];
  if (transaction.kind === "deploy") {
    values.push(transaction.constructorArgs?.decoded);
  } else if (transaction.kind === "call") {
    values.push(transaction.to);
    if (transaction.forwardedCall) {
      values.push(
        transaction.forwardedCall.target,
        transaction.forwardedCall.args
      );
    } else {
      values.push(transaction.args);
    }
  }
  return values;
}

function predicateReferenceFields(transaction) {
  const values = [transaction.predicate?.target];
  if (
    transaction.predicate?.type === "callEq" ||
    transaction.predicate?.type === "callResultEq"
  ) {
    values.push(transaction.predicate.call?.args, transaction.predicate.expect);
  }
  return values;
}

function validateEnvelope(plan, transaction, index, errors) {
  const valuePath = `$.transactions[${index}].envelope`;
  const envelope = transaction.envelope;
  if (!envelope || typeof envelope !== "object") return;
  if (envelope.chainId !== plan.chainId) {
    errors.push(
      `${valuePath}.chainId: must equal plan chainId ${plan.chainId}`
    );
  }
  if (
    typeof envelope.expectedExecutor === "string" &&
    typeof plan.expectedExecutor === "string" &&
    envelope.expectedExecutor.toLowerCase() !==
      plan.expectedExecutor.toLowerCase()
  ) {
    errors.push(
      `${valuePath}.expectedExecutor: must equal plan expectedExecutor`
    );
  }
  const expectedTo = transaction.kind === "deploy" ? null : transaction.to;
  if (!jsonEqual(envelope.to, expectedTo)) {
    errors.push(`${valuePath}.to: must match the transaction destination`);
  }
  const expectedData = transaction.kind === "deploy"
    ? "initCode+constructorArgs"
    : transaction.forwardedCall
      ? "forwardedCall"
      : "functionSignature+args";
  if (envelope.data !== expectedData) {
    errors.push(`${valuePath}.data: must equal ${expectedData}`);
  }
  try {
    parseQuantity(envelope.value, `${valuePath}.value`);
  } catch (error) {
    errors.push(error.message);
  }
}

function validatePlan(plan, options = {}) {
  const errors = [];
  const schema = readJson(SCHEMA_PATH);
  validateJsonSchema(plan, schema, schema, "$", errors);
  validateReferenceObjects(plan, "$", errors);

  const configuredChainId = NETWORK_CHAIN_IDS[plan?.network];
  if (configuredChainId !== undefined && plan.chainId !== configuredChainId) {
    errors.push(
      `$.chainId: network ${plan.network} requires chain ID ${configuredChainId}, got ${plan.chainId}`
    );
  }

  if (!Array.isArray(plan.transactions)) {
    const uniqueErrors = [...new Set(errors)];
    return { ok: false, errors: uniqueErrors };
  }

  const ids = new Set();
  const availableOutputs = new Set();
  for (let index = 0; index < plan.transactions.length; index += 1) {
    const transaction = plan.transactions[index];
    const transactionPath = `$.transactions[${index}]`;
    if (!transaction || typeof transaction !== "object") continue;

    if (ids.has(transaction.id)) {
      errors.push(
        `${transactionPath}.id: duplicate transaction id ${transaction.id}`
      );
    }
    ids.add(transaction.id);

    for (const value of transactionReferenceFields(transaction)) {
      for (const reference of collectReferences(value)) {
        if (!availableOutputs.has(reference)) {
          errors.push(
            `${transactionPath}: references output "${reference}" before it is available`
          );
        }
      }
    }

    validateEnvelope(plan, transaction, index, errors);

    if (transaction.kind === "deploy") {
      for (const callOnlyField of [
        "to",
        "functionSignature",
        "args",
        "forwardedCall",
        "calldata",
      ]) {
        if (Object.prototype.hasOwnProperty.call(transaction, callOnlyField)) {
          errors.push(
            `${transactionPath}: deploy must not contain ${callOnlyField}`
          );
        }
      }
      if (availableOutputs.has(transaction.output)) {
        errors.push(
          `${transactionPath}.output: duplicate output id ${transaction.output}`
        );
      }
      if (typeof transaction.output === "string") {
        availableOutputs.add(transaction.output);
      }
      if (
        options.checkArtifacts !== false &&
        typeof transaction.artifactName === "string"
      ) {
        try {
          const loadedArtifact = loadArtifact(transaction.artifactName);
          assertArtifactFresh(loadedArtifact);
          const expectedTypes = constructorTypes(loadedArtifact);
          if (!jsonEqual(transaction.constructorArgs?.types, expectedTypes)) {
            errors.push(
              `${transactionPath}.constructorArgs.types: does not match current ${transaction.artifactName} artifact`
            );
          }
          const expectedInitCode = artifactInitCode(loadedArtifact);
          if (
            typeof transaction.initCode === "string" &&
            transaction.initCode.toLowerCase() !==
              expectedInitCode.toLowerCase()
          ) {
            errors.push(
              `${transactionPath}.initCode: does not match current ${transaction.artifactName} artifact`
            );
          }
          if (Array.isArray(transaction.constructorArgs?.decoded)) {
            const expectedEncoding = encodeTypedConstructorArgs(
              transaction.constructorArgs.types,
              transaction.constructorArgs.decoded
            );
            if (
              typeof transaction.constructorArgs.encoded === "string" &&
              transaction.constructorArgs.encoded.toLowerCase() !==
                expectedEncoding.toLowerCase()
            ) {
              errors.push(
                `${transactionPath}.constructorArgs.encoded: does not match decoded arguments`
              );
            }
          }
        } catch (error) {
          errors.push(`${transactionPath}.artifactName: ${error.message}`);
        }
      }
    } else if (transaction.kind === "call") {
      for (const deployOnlyField of [
        "artifactName",
        "initCode",
        "constructorArgs",
        "output",
      ]) {
        if (
          Object.prototype.hasOwnProperty.call(transaction, deployOnlyField)
        ) {
          errors.push(
            `${transactionPath}: call must not contain ${deployOnlyField}`
          );
        }
      }
      const hasArgs = Array.isArray(transaction.args);
      const hasForwardedCall =
        transaction.forwardedCall !== undefined &&
        transaction.forwardedCall !== null;
      if (hasArgs === hasForwardedCall) {
        errors.push(
          `${transactionPath}: call must contain exactly one of args or forwardedCall`
        );
      }
      if (
        hasForwardedCall &&
        transaction.functionSignature !== AUTHORITY_HELPER_FORWARD_SIGNATURE
      ) {
        errors.push(
          `${transactionPath}.functionSignature: forwarded calls must use ${AUTHORITY_HELPER_FORWARD_SIGNATURE}`
        );
      }
      if (
        typeof transaction.functionSignature === "string" &&
        (hasArgs || hasForwardedCall)
      ) {
        try {
          const expectedCalldata = hasForwardedCall
            ? encodeForwardedCall(transaction)
            : encodeFunctionCall(
                transaction.functionSignature,
                transaction.args
              );
          if (
            typeof transaction.calldata === "string" &&
            transaction.calldata.toLowerCase() !==
              expectedCalldata.toLowerCase()
          ) {
            errors.push(
              `${transactionPath}.calldata: does not match functionSignature and args`
            );
          }
        } catch (error) {
          errors.push(`${transactionPath}.functionSignature: ${error.message}`);
        }
      }
    }

    // A deployment predicate is evaluated after its receipt, so it may refer
    // to that transaction's own output. Transaction inputs remain prior-only.
    for (const value of predicateReferenceFields(transaction)) {
      for (const reference of collectReferences(value)) {
        if (!availableOutputs.has(reference)) {
          errors.push(
            `${transactionPath}.predicate: references output "${reference}" before it is available`
          );
        }
      }
    }

    if (transaction.predicate?.type === "codePresent") {
      if (Object.prototype.hasOwnProperty.call(transaction.predicate, "call")) {
        errors.push(
          `${transactionPath}.predicate: codePresent must not contain call`
        );
      }
      if (
        Object.prototype.hasOwnProperty.call(transaction.predicate, "expect")
      ) {
        errors.push(
          `${transactionPath}.predicate: codePresent must not contain expect`
        );
      }
    } else if (
      transaction.predicate?.type === "callEq" &&
      typeof transaction.predicate.call?.sig === "string" &&
      Array.isArray(transaction.predicate.call?.args)
    ) {
      try {
        const { fragment } = functionInterface(transaction.predicate.call.sig);
        encodeFunctionCall(
          transaction.predicate.call.sig,
          transaction.predicate.call.args
        );
        if (fragment.outputs.length === 0) {
          errors.push(
            `${transactionPath}.predicate.call.sig: callEq requires output types`
          );
        }
      } catch (error) {
        errors.push(`${transactionPath}.predicate.call.sig: ${error.message}`);
      }
    }
  }

  const transactionPositions = new Map(
    plan.transactions.map((transaction, index) => [transaction.id, index])
  );
  plan.transactions.forEach((transaction, index) => {
    if (transaction.reverifyUntil === undefined) return;
    const untilIndex = transactionPositions.get(transaction.reverifyUntil);
    if (untilIndex === undefined) {
      errors.push(
        `$.transactions[${index}].reverifyUntil: unknown transaction id ${transaction.reverifyUntil}`
      );
    } else if (untilIndex <= index) {
      errors.push(
        `$.transactions[${index}].reverifyUntil: compensating transaction must come later in the plan`
      );
    }
  });

  const uniqueErrors = [...new Set(errors)];
  return { ok: uniqueErrors.length === 0, errors: uniqueErrors };
}

function assertValidPlan(plan) {
  const result = validatePlan(plan);
  if (!result.ok) {
    throw new Error(
      `Invalid deployment plan:\n${result.errors
        .map((error) => `- ${error}`)
        .join("\n")}`
    );
  }
  return plan;
}

function normalizeAfter(after, entryPath) {
  if (after === undefined) return [];
  if (typeof after === "string") return [after];
  if (
    Array.isArray(after) &&
    after.every((entry) => typeof entry === "string")
  ) {
    return after;
  }
  throw new Error(
    `${entryPath}: after must be a transaction id or array of ids`
  );
}

function orderEntries(entries) {
  const byId = new Map();
  for (const entry of entries) {
    if (typeof entry.transaction.id !== "string") {
      throw new Error(`${entry.filePath}: missing transaction id`);
    }
    if (byId.has(entry.transaction.id)) {
      throw new Error(`Duplicate plan entry id: ${entry.transaction.id}`);
    }
    byId.set(entry.transaction.id, entry);
  }
  for (const entry of entries) {
    for (const dependency of entry.after) {
      if (!byId.has(dependency)) {
        throw new Error(
          `${entry.filePath}: unknown after dependency ${dependency}`
        );
      }
    }
  }

  const ordered = [];
  const emitted = new Set();
  while (ordered.length < entries.length) {
    const next = entries.find(
      (entry) =>
        !emitted.has(entry.transaction.id) &&
        entry.after.every((dependency) => emitted.has(dependency))
    );
    if (!next) {
      const remaining = entries
        .filter((entry) => !emitted.has(entry.transaction.id))
        .map((entry) => entry.transaction.id)
        .join(", ");
      throw new Error(`Plan entry dependency cycle involving: ${remaining}`);
    }
    ordered.push(next.transaction);
    emitted.add(next.transaction.id);
  }
  return ordered;
}

function uniqueEnvelopeValue(transactions, field) {
  const values = [
    ...new Set(
      transactions
        .map((transaction) => transaction.envelope?.[field])
        .filter((value) => value !== undefined)
        .map((value) =>
          typeof value === "string"
            ? value.toLowerCase()
            : JSON.stringify(value)
        )
    ),
  ];
  if (values.length > 1) {
    throw new Error(`Plan entries disagree on envelope.${field}`);
  }
  return transactions.find(
    (transaction) => transaction.envelope?.[field] !== undefined
  )?.envelope[field];
}

function authorizedHelperTransactions(
  transactions,
  helperOwner,
  forwardedFunctionSignatures
) {
  const helper = getAddress(helperOwner);
  const forwardedSignatures = new Set(forwardedFunctionSignatures);
  return transactions.map((transaction) => {
    if (
      transaction.kind !== "call" ||
      !forwardedSignatures.has(transaction.functionSignature)
    ) {
      return transaction;
    }
    if (transaction.forwardedCall || !Array.isArray(transaction.args)) {
      throw new Error(
        `${transaction.id}: owner action is already forwarded or has no decoded arguments`
      );
    }
    const forwardedCall = {
      target: transaction.to,
      functionSignature: transaction.functionSignature,
      args: transaction.args,
    };
    const wrapped = {
      ...transaction,
      to: helper,
      functionSignature: AUTHORITY_HELPER_FORWARD_SIGNATURE,
      forwardedCall,
    };
    delete wrapped.args;
    delete wrapped.calldata;
    return wrapped;
  });
}

function applyCeremonyConfig(network, transactions) {
  const configPath = path.join(
    REPO_ROOT,
    "deployments",
    network,
    "ceremony-config.json"
  );
  if (!fs.existsSync(configPath)) return transactions;
  const config = readJson(configPath);
  if (
    config.schemaVersion !== "2.0.0" ||
    config.ownership?.type !== "authorized-helper" ||
    typeof config.ownership.archControllerKey !== "string" ||
    typeof config.ownership.helperOwnerKey !== "string" ||
    typeof config.ownership.legacyHelperOwnerKey !== "string" ||
    typeof config.ownership.helperVersion !== "string" ||
    !Array.isArray(config.ownership.retainedAuthorizedAccounts) ||
    config.ownership.retainedAuthorizedAccounts.some(
      (account) => !ADDRESS_REGEX.test(account || "")
    ) ||
    new Set(
      config.ownership.retainedAuthorizedAccounts.map((account) =>
        account.toLowerCase()
      )
    ).size !== config.ownership.retainedAuthorizedAccounts.length ||
    !Array.isArray(config.ownership.revokedSphereXEngineOperators) ||
    config.ownership.revokedSphereXEngineOperators.some(
      (account) => !ADDRESS_REGEX.test(account || "")
    ) ||
    new Set(
      config.ownership.revokedSphereXEngineOperators.map((account) =>
        account.toLowerCase()
      )
    ).size !== config.ownership.revokedSphereXEngineOperators.length ||
    !Array.isArray(config.ownership.forwardedFunctionSignatures) ||
    config.ownership.forwardedFunctionSignatures.length === 0 ||
    new Set(config.ownership.forwardedFunctionSignatures).size !==
      config.ownership.forwardedFunctionSignatures.length ||
    config.ownership.forwardedFunctionSignatures.some(
      (signature) => typeof signature !== "string" || signature.length === 0
    )
  ) {
    throw new Error(`Invalid authorized-helper ceremony config: ${configPath}`);
  }
  const deploymentsPath = path.join(
    REPO_ROOT,
    "deployments",
    network,
    "deployments.json"
  );
  const deployments = readJson(deploymentsPath);
  const helperOwner = deployments[config.ownership.helperOwnerKey];
  const archController = deployments[config.ownership.archControllerKey];
  if (!ADDRESS_REGEX.test(archController || "")) {
    throw new Error(
      `${configPath}: missing deployment address ${config.ownership.archControllerKey}`
    );
  }
  if (!ADDRESS_REGEX.test(helperOwner || "")) {
    throw new Error(
      `${configPath}: missing deployment address ${config.ownership.helperOwnerKey}`
    );
  }
  return authorizedHelperTransactions(
    transactions,
    helperOwner,
    config.ownership.forwardedFunctionSignatures
  );
}

function assemblePlan(args) {
  const network = requiredArg(args, "network");
  const release = requiredArg(args, "release");
  if (!SAFE_ID_REGEX.test(network) || !SAFE_ID_REGEX.test(release)) {
    throw new Error("Network and release must not contain dots.");
  }
  const entriesName = args.entries || "plan-entries";
  if (!/^[A-Za-z0-9_-]+$/.test(entriesName)) {
    throw new Error(
      "Plan entries directory must contain only letters, digits, dashes, and underscores."
    );
  }
  const entriesDirectory = path.join(
    REPO_ROOT,
    "deployments",
    network,
    entriesName
  );
  if (!fs.existsSync(entriesDirectory)) {
    throw new Error(`Plan entries directory not found: ${entriesDirectory}`);
  }
  const entryFiles = fs
    .readdirSync(entriesDirectory)
    .filter((fileName) => fileName.endsWith(".json"))
    .sort((left, right) => left.localeCompare(right));
  if (entryFiles.length === 0) {
    throw new Error(`No JSON plan entries found in ${entriesDirectory}`);
  }
  const entries = entryFiles.map((fileName) => {
    const filePath = path.join(entriesDirectory, fileName);
    const transaction = readJson(filePath);
    const after = normalizeAfter(transaction.after, filePath);
    delete transaction.after;
    return { filePath, transaction, after };
  });
  let transactions = orderEntries(entries);
  const chainId =
    uniqueEnvelopeValue(transactions, "chainId") || NETWORK_CHAIN_IDS[network];
  if (!Number.isSafeInteger(chainId) || chainId <= 0) {
    throw new Error(
      `Could not infer chain id for ${network}; include envelope.chainId in an entry`
    );
  }
  const expectedExecutor = uniqueEnvelopeValue(
    transactions,
    "expectedExecutor"
  );
  if (!ADDRESS_REGEX.test(expectedExecutor || "")) {
    throw new Error(
      "Could not infer expected executor; include envelope.expectedExecutor in an entry"
    );
  }
  transactions = applyCeremonyConfig(network, transactions);

  for (const transaction of transactions) {
    if (transaction.kind === "deploy") {
      const loadedArtifact = loadArtifact(transaction.artifactName);
      assertArtifactFresh(loadedArtifact);
      transaction.initCode = artifactInitCode(loadedArtifact);
      transaction.constructorArgs ||= { decoded: [] };
      transaction.constructorArgs.types = constructorTypes(loadedArtifact);
      transaction.constructorArgs.encoded = encodeTypedConstructorArgs(
        transaction.constructorArgs.types,
        transaction.constructorArgs.decoded || []
      );
    } else if (transaction.kind === "call") {
      transaction.calldata = transaction.forwardedCall
        ? encodeForwardedCall(transaction)
        : encodeFunctionCall(
            transaction.functionSignature,
            transaction.args || []
          );
    }
    const existingEnvelope = transaction.envelope || {};
    transaction.envelope = {
      chainId,
      expectedExecutor: getAddress(expectedExecutor),
      to: transaction.kind === "deploy" ? null : transaction.to,
      value: existingEnvelope.value ?? "0",
      data:
        transaction.kind === "deploy"
          ? "initCode+constructorArgs"
          : transaction.forwardedCall
            ? "forwardedCall"
            : "functionSignature+args",
      gasLimitPolicy: existingEnvelope.gasLimitPolicy ?? "estimate*1.3",
      nonceCheck: "display-and-confirm",
    };
  }

  const plan = {
    schemaVersion: PLAN_SCHEMA_VERSION,
    foundryProfile: REQUIRED_FOUNDRY_PROFILE,
    network,
    chainId,
    release,
    expectedExecutor: getAddress(expectedExecutor),
    onFailure: "halt",
    resume: "re-verify all prior predicates before continuing",
    transactions,
  };
  assertValidPlan(plan);
  const outputPath = path.join(
    REPO_ROOT,
    "deployments",
    network,
    `plan-${release}.json`
  );
  writeJson(outputPath, plan);
  console.log(
    `Deployment plan assembled: ${path.relative(REPO_ROOT, outputPath)}`
  );
  console.log(`Transactions: ${transactions.length}`);
}

function parseQuantity(value, context) {
  if (
    typeof value !== "string" ||
    !/^(?:0|[1-9][0-9]*|0x[0-9a-fA-F]+)$/.test(value)
  ) {
    throw new Error(`${context}: invalid non-negative integer quantity`);
  }
  return BigInt(value);
}

function rpcQuantity(value) {
  return `0x${BigInt(value).toString(16)}`;
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
    if (!response.ok) throw new Error(`${method} HTTP ${response.status}`);
    const payload = await response.json();
    if (payload.error) {
      const detail = payload.error.data
        ? ` (${JSON.stringify(payload.error.data)})`
        : "";
      throw new Error(
        `${method} RPC ${payload.error.code}: ${payload.error.message}${detail}`
      );
    }
    return payload.result;
  };
}

function canonicalValue(value) {
  if (typeof value === "bigint" || typeof value === "number") {
    return value.toString();
  }
  if (typeof value === "string") {
    if (ADDRESS_REGEX.test(value) || /^0x[a-fA-F0-9]*$/.test(value)) {
      return value.toLowerCase();
    }
    return value;
  }
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => !/^\d+$/.test(key))
        .map(([key, entry]) => [key, canonicalValue(entry)])
    );
  }
  return value;
}

async function codePresent(rpc, address) {
  const code = await rpc("eth_getCode", [address, "latest"]);
  const ok = typeof code === "string" && !/^0x0*$/.test(code);
  return {
    ok,
    detail: ok ? `code present at ${address}` : `no code at ${address}`,
  };
}

async function callEq(
  rpc,
  target,
  signature,
  args,
  expected,
  resultIndex = null
) {
  const { contractInterface, fragment } = functionInterface(signature);
  const data = contractInterface.encodeFunctionData(fragment, args);
  const encodedResult = await rpc("eth_call", [{ to: target, data }, "latest"]);
  const decodedResult = contractInterface.decodeFunctionResult(
    fragment,
    encodedResult
  );
  if (
    resultIndex !== null &&
    (!Number.isInteger(resultIndex) || resultIndex < 0 || resultIndex >= fragment.outputs.length)
  ) {
    throw new Error(`${signature} has no result at index ${resultIndex}`);
  }
  const actual = resultIndex !== null
    ? canonicalValue(decodedResult[resultIndex])
    : fragment.outputs.length === 1
      ? canonicalValue(decodedResult[0])
      : canonicalValue(Array.from(decodedResult));
  const normalizedExpected = canonicalValue(expected);
  const ok = jsonEqual(actual, normalizedExpected);
  return {
    ok,
    detail: ok
      ? `${signature} returned ${JSON.stringify(actual)}`
      : `${signature} expected ${JSON.stringify(
          normalizedExpected
        )}, got ${JSON.stringify(actual)}`,
  };
}

async function checkPredicate(rpc, predicate, outputs) {
  const target = resolveReferences(predicate.target, outputs);
  if (!ADDRESS_REGEX.test(target || "")) {
    throw new Error(`Predicate resolved to invalid target: ${target}`);
  }
  if (predicate.type === "codePresent") {
    return codePresent(rpc, target);
  }
  if (predicate.type === "callEq" || predicate.type === "callResultEq") {
    const args = resolveReferences(predicate.call.args, outputs);
    const expected = resolveReferences(predicate.expect, outputs);
    return callEq(
      rpc,
      target,
      predicate.call.sig,
      args,
      expected,
      predicate.type === "callResultEq" ? predicate.resultIndex : null
    );
  }
  throw new Error(`Unsupported predicate type: ${predicate.type}`);
}

function outputsFromRunState(plan, runState) {
  const outputs = new Map();
  for (const transaction of plan.transactions) {
    if (transaction.kind !== "deploy") continue;
    const resolvedAddress = runState[transaction.id]?.resolvedAddress;
    if (resolvedAddress) outputs.set(transaction.output, resolvedAddress);
  }
  return outputs;
}

function runStatePath(plan) {
  return path.join(
    REPO_ROOT,
    "deployments",
    plan.network,
    `run-state-${plan.release}.json`
  );
}

function readRunState(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const state = readJson(filePath);
  if (!state || typeof state !== "object" || Array.isArray(state)) {
    throw new Error(`Run state must be an object: ${filePath}`);
  }
  return state;
}

function transactionPayload(transaction, outputs) {
  const value = parseQuantity(
    transaction.envelope.value,
    `${transaction.id}.envelope.value`
  );
  if (transaction.kind === "deploy") {
    const encodedArgs = encodeTypedConstructorArgs(
      transaction.constructorArgs.types,
      transaction.constructorArgs.decoded,
      outputs
    );
    return {
      to: null,
      data: `${transaction.initCode}${encodedArgs.slice(2)}`,
      value,
    };
  }
  const to = resolveReferences(transaction.to, outputs);
  if (!ADDRESS_REGEX.test(to || "")) {
    throw new Error(`${transaction.id}: resolved invalid destination ${to}`);
  }
  return {
    to,
    data: transaction.forwardedCall
      ? encodeForwardedCall(transaction, outputs)
      : encodeFunctionCall(
          transaction.functionSignature,
          transaction.args,
          outputs
        ),
    value,
  };
}

async function gasLimitForTransaction(rpc, transaction, executor, payload) {
  const policy = transaction.envelope.gasLimitPolicy;
  if (policy !== "estimate*1.3") {
    return parseQuantity(
      policy.gasLimit,
      `${transaction.id}.envelope.gasLimitPolicy.gasLimit`
    );
  }
  const request = {
    from: executor,
    data: payload.data,
    value: rpcQuantity(payload.value),
  };
  if (payload.to) request.to = payload.to;
  const estimate = BigInt(await rpc("eth_estimateGas", [request]));
  return (estimate * 13n + 9n) / 10n;
}

async function confirmNonce(transaction, executor, nonce, autoConfirm) {
  console.log(
    `[${transaction.id}] Expected executor ${executor}; current pending nonce ${nonce}.`
  );
  if (autoConfirm) {
    console.log(`[${transaction.id}] Nonce confirmed (--yes).`);
    return;
  }
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error(
      "Nonce confirmation requires an interactive terminal; pass --yes for an attended automated rehearsal"
    );
  }
  const prompt = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  const answer = await prompt.question(
    `[${transaction.id}] Confirm this executor nonce? [y/N] `
  );
  prompt.close();
  if (!/^y(?:es)?$/i.test(answer.trim())) {
    throw new Error(`Nonce was not confirmed for ${transaction.id}`);
  }
}

async function sendTransaction({
  rpc,
  wallet,
  executor,
  chainId,
  nonce,
  gasLimit,
  payload,
}) {
  if (wallet) {
    const gasPrice = BigInt(await rpc("eth_gasPrice"));
    const unsignedTransaction = {
      chainId,
      nonce,
      gasLimit,
      gasPrice,
      data: payload.data,
      value: payload.value,
    };
    if (payload.to) unsignedTransaction.to = payload.to;
    const signedTransaction = await wallet.signTransaction(unsignedTransaction);
    return rpc("eth_sendRawTransaction", [signedTransaction]);
  }
  const request = {
    from: executor,
    data: payload.data,
    value: rpcQuantity(payload.value),
    gas: rpcQuantity(gasLimit),
  };
  if (payload.to) request.to = payload.to;
  return rpc("eth_sendTransaction", [request]);
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForReceipt(rpc, transactionHash) {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const receipt = await rpc("eth_getTransactionReceipt", [transactionHash]);
    if (receipt) return receipt;
    await delay(1_000);
  }
  throw new Error(`Timed out waiting for receipt ${transactionHash}`);
}

function receiptBlockNumber(receipt) {
  const blockNumber = Number(BigInt(receipt.blockNumber));
  return Number.isSafeInteger(blockNumber)
    ? blockNumber
    : BigInt(receipt.blockNumber).toString();
}

async function recoverCompensatingTransactions(
  rpc,
  plan,
  runState,
  outputs,
  statePath
) {
  const transactions = new Map(
    plan.transactions.map((transaction) => [transaction.id, transaction])
  );
  for (const transaction of plan.transactions) {
    if (!transaction.reverifyUntil) continue;
    const compensation = transactions.get(transaction.reverifyUntil);
    if (!compensation) continue;
    const existing = runState[compensation.id];
    if (!existing?.txHash || existing.status === "verified") continue;

    const receipt = await rpc("eth_getTransactionReceipt", [existing.txHash]);
    if (!receipt) {
      throw new Error(
        `Resume halted: compensating transaction ${compensation.id} has no receipt yet; do not resend it`
      );
    }
    existing.blockNumber = receiptBlockNumber(receipt);
    existing.status = receipt.status === "0x1" ? "mined" : "reverted";
    if (receipt.status !== "0x1") {
      writeJsonAtomic(statePath, runState);
      throw new Error(
        `Resume halted: compensating transaction ${compensation.id} reverted`
      );
    }
    if (compensation.kind === "deploy") {
      if (!receipt.contractAddress) {
        existing.status = "predicate-failed";
        writeJsonAtomic(statePath, runState);
        throw new Error(
          `Deployment receipt lacks contractAddress: ${compensation.id}`
        );
      }
      const resolvedAddress = getAddress(receipt.contractAddress);
      if (
        existing.resolvedAddress &&
        existing.resolvedAddress.toLowerCase() !== resolvedAddress.toLowerCase()
      ) {
        throw new Error(
          `Stored deployment address for ${compensation.id} does not match its receipt`
        );
      }
      existing.resolvedAddress = resolvedAddress;
      outputs.set(compensation.output, resolvedAddress);
    }
    writeJsonAtomic(statePath, runState);

    let predicate;
    try {
      predicate = await checkPredicate(rpc, compensation.predicate, outputs);
    } catch (error) {
      existing.status = "predicate-failed";
      writeJsonAtomic(statePath, runState);
      throw new Error(
        `Predicate error for compensating transaction ${compensation.id}: ${error.message}`
      );
    }
    if (!predicate.ok) {
      existing.status = "predicate-failed";
      writeJsonAtomic(statePath, runState);
      throw new Error(
        `Resume halted: compensating transaction ${compensation.id} fails its predicate: ${predicate.detail}`
      );
    }
    existing.status = "verified";
    writeJsonAtomic(statePath, runState);
    console.log(
      `[${compensation.id}] Compensating transaction recovered and verified before prior predicate checks: ${predicate.detail}`
    );
  }
}

async function executePlan(args) {
  const planPath = requiredArg(args, "plan");
  const rpcUrl = requiredArg(args, "rpc");
  const privateKey = args["private-key"];
  const impersonatedAddress = args.impersonate;
  if ((privateKey ? 1 : 0) + (impersonatedAddress ? 1 : 0) !== 1) {
    throw new Error("Choose exactly one of --private-key or --impersonate.");
  }
  const plan = assertValidPlan(readJson(planPath));
  const rpc = createRpcClient(rpcUrl);
  const actualChainId = Number(BigInt(await rpc("eth_chainId")));
  if (actualChainId !== plan.chainId) {
    throw new Error(
      `RPC chain id mismatch: plan=${plan.chainId}, rpc=${actualChainId}`
    );
  }

  const wallet = privateKey ? new Wallet(privateKey) : null;
  const executor = wallet ? wallet.address : getAddress(impersonatedAddress);
  if (executor.toLowerCase() !== plan.expectedExecutor.toLowerCase()) {
    throw new Error(
      `Executor mismatch: plan expects ${plan.expectedExecutor}, selected ${executor}`
    );
  }

  const statePath = args["run-state"] || runStatePath(plan);
  const runState = readRunState(statePath);
  const transactionIds = new Set(
    plan.transactions.map((transaction) => transaction.id)
  );
  for (const transactionId of Object.keys(runState)) {
    if (!transactionIds.has(transactionId)) {
      throw new Error(
        `Run state contains unknown transaction id: ${transactionId}`
      );
    }
  }
  const outputs = outputsFromRunState(plan, runState);

  let impersonating = false;
  try {
    if (impersonatedAddress) {
      await rpc("anvil_impersonateAccount", [executor]);
      impersonating = true;
    }

    await recoverCompensatingTransactions(
      rpc,
      plan,
      runState,
      outputs,
      statePath
    );

    let foundIncomplete = false;
    for (const transaction of plan.transactions) {
      const existing = runState[transaction.id];
      if (existing?.status === "verified") {
        if (foundIncomplete) {
          throw new Error(
            `Run state is non-contiguous: ${transaction.id} is verified after an incomplete entry`
          );
        }
        if (
          transaction.reverifyUntil &&
          runState[transaction.reverifyUntil]?.status === "verified"
        ) {
          console.log(
            `[${transaction.id}] Prior predicate retired after verified compensation ${transaction.reverifyUntil}.`
          );
          continue;
        }
        const predicate = await checkPredicate(rpc, transaction.predicate, outputs);
        if (!predicate.ok) {
          throw new Error(
            `Resume halted: prior predicate failed for ${transaction.id}: ${
              predicate.detail
            }. If this is a fresh fork or new rehearsal, the run state is from a previous chain instance — delete ${path.relative(
              REPO_ROOT,
              statePath
            )} and re-run.`
          );
        }
        console.log(
          `[${transaction.id}] Prior predicate re-verified: ${predicate.detail}`
        );
        continue;
      }

      foundIncomplete = true;
      if (existing?.txHash) {
        const receipt = await rpc("eth_getTransactionReceipt", [
          existing.txHash,
        ]);
        if (!receipt) {
          throw new Error(
            `Resume halted: submitted transaction ${transaction.id} has no receipt yet; do not resend it`
          );
        }
        existing.blockNumber = receiptBlockNumber(receipt);
        existing.status = receipt.status === "0x1" ? "mined" : "reverted";
        if (receipt.status !== "0x1") {
          writeJsonAtomic(statePath, runState);
          throw new Error(
            `Resume halted: stored transaction ${transaction.id} reverted`
          );
        }
        if (transaction.kind === "deploy") {
          if (!receipt.contractAddress) {
            existing.status = "predicate-failed";
            writeJsonAtomic(statePath, runState);
            throw new Error(
              `Deployment receipt lacks contractAddress: ${transaction.id}`
            );
          }
          const resolvedAddress = getAddress(receipt.contractAddress);
          if (
            existing.resolvedAddress &&
            existing.resolvedAddress.toLowerCase() !==
              resolvedAddress.toLowerCase()
          ) {
            throw new Error(
              `Stored deployment address for ${transaction.id} does not match its receipt`
            );
          }
          existing.resolvedAddress = resolvedAddress;
          outputs.set(transaction.output, existing.resolvedAddress);
        }
        writeJsonAtomic(statePath, runState);
        const predicate = await checkPredicate(
          rpc,
          transaction.predicate,
          outputs
        );
        if (!predicate.ok) {
          throw new Error(
            `Resume halted: mined transaction ${transaction.id} still fails its predicate: ${predicate.detail}`
          );
        }
        runState[transaction.id].status = "verified";
        writeJsonAtomic(statePath, runState);
        console.log(
          `[${transaction.id}] Mined transaction predicate now verifies; no resend: ${predicate.detail}`
        );
        continue;
      }

      const payload = transactionPayload(transaction, outputs);
      const nonce = BigInt(
        await rpc("eth_getTransactionCount", [executor, "pending"])
      );
      await confirmNonce(transaction, executor, nonce, args.yes === true);
      const gasLimit = await gasLimitForTransaction(
        rpc,
        transaction,
        executor,
        payload
      );
      console.log(
        `[${transaction.id}] Gas limit ${gasLimit} (${JSON.stringify(
          transaction.envelope.gasLimitPolicy
        )}).`
      );
      const txHash = await sendTransaction({
        rpc,
        wallet,
        executor,
        chainId: plan.chainId,
        nonce,
        gasLimit,
        payload,
      });
      runState[transaction.id] = { txHash, status: "submitted" };
      writeJsonAtomic(statePath, runState);

      let receipt;
      try {
        receipt = await waitForReceipt(rpc, txHash);
      } catch (error) {
        throw new Error(
          `${transaction.id} was submitted as ${txHash}, but receipt waiting failed: ${error.message}. Resume instead of resending.`
        );
      }
      const stateEntry = {
        txHash,
        blockNumber: receiptBlockNumber(receipt),
        status: receipt.status === "0x1" ? "mined" : "reverted",
      };
      if (transaction.kind === "deploy" && receipt.contractAddress) {
        stateEntry.resolvedAddress = getAddress(receipt.contractAddress);
        outputs.set(transaction.output, stateEntry.resolvedAddress);
      }
      runState[transaction.id] = stateEntry;
      writeJsonAtomic(statePath, runState);
      console.log(
        `[${transaction.id}] Mined ${txHash} in block ${stateEntry.blockNumber}.`
      );

      if (receipt.status !== "0x1") {
        throw new Error(`Transaction reverted: ${transaction.id}`);
      }
      if (transaction.kind === "deploy" && !stateEntry.resolvedAddress) {
        stateEntry.status = "predicate-failed";
        writeJsonAtomic(statePath, runState);
        throw new Error(
          `Deployment receipt lacks contractAddress: ${transaction.id}`
        );
      }

      let predicate;
      try {
        predicate = await checkPredicate(rpc, transaction.predicate, outputs);
      } catch (error) {
        stateEntry.status = "predicate-failed";
        writeJsonAtomic(statePath, runState);
        throw new Error(
          `Predicate error for ${transaction.id}: ${error.message}`
        );
      }
      if (!predicate.ok) {
        stateEntry.status = "predicate-failed";
        writeJsonAtomic(statePath, runState);
        throw new Error(
          `Predicate failed for ${transaction.id}: ${predicate.detail}`
        );
      }
      stateEntry.status = "verified";
      writeJsonAtomic(statePath, runState);
      console.log(
        `[${transaction.id}] Predicate verified: ${predicate.detail}`
      );
    }
  } finally {
    if (impersonating) {
      try {
        await rpc("anvil_stopImpersonatingAccount", [executor]);
      } catch (_error) {
        // The executor result is already durable; cleanup failure must not mask it.
      }
    }
  }

  console.log(
    `Execution complete. Run state: ${path.relative(REPO_ROOT, statePath)}`
  );
}

async function verifyPlan(args) {
  const planPath = requiredArg(args, "plan");
  const statePath = requiredArg(args, "run-state");
  const rpcUrl = requiredArg(args, "rpc");
  const plan = assertValidPlan(readJson(planPath));
  if (!fs.existsSync(statePath)) {
    throw new Error(`Run state not found: ${statePath}`);
  }
  const runState = readRunState(statePath);
  const rpc = createRpcClient(rpcUrl);
  const actualChainId = Number(BigInt(await rpc("eth_chainId")));
  if (actualChainId !== plan.chainId) {
    throw new Error(
      `RPC chain id mismatch: plan=${plan.chainId}, rpc=${actualChainId}`
    );
  }
  const outputs = outputsFromRunState(plan, runState);
  let failed = 0;
  for (const transaction of plan.transactions) {
    if (
      transaction.reverifyUntil &&
      runState[transaction.reverifyUntil]?.status === "verified"
    ) {
      console.log(
        `HISTORICAL ${transaction.id}: superseded by verified compensation ${transaction.reverifyUntil}`
      );
      continue;
    }
    try {
      const result = await checkPredicate(rpc, transaction.predicate, outputs);
      if (result.ok) {
        console.log(`VERIFIED ${transaction.id}: ${result.detail}`);
      } else {
        failed += 1;
        console.error(`FAILED ${transaction.id}: ${result.detail}`);
      }
    } catch (error) {
      failed += 1;
      console.error(`FAILED ${transaction.id}: ${error.message}`);
    }
  }
  if (failed > 0) {
    console.error(
      `Verification failed: ${failed} predicate(s) did not verify.`
    );
    process.exitCode = 1;
    return;
  }
  console.log(`Verification passed: ${plan.transactions.length} predicate(s).`);
}

function recordedBlockNumber(entry, transactionId) {
  try {
    const blockNumber = BigInt(entry.blockNumber);
    if (blockNumber <= 0n) throw new Error("not positive");
    return blockNumber;
  } catch (_error) {
    throw new Error(
      `Run state entry ${transactionId} has invalid blockNumber ${entry.blockNumber}`
    );
  }
}

async function verifyEoaRunState(args) {
  const planPath = requiredArg(args, "plan");
  const statePath = requiredArg(args, "run-state");
  const rpcUrl = requiredArg(args, "rpc");
  const plan = assertValidPlan(readJson(planPath));
  if (!fs.existsSync(statePath)) {
    throw new Error(`Run state not found: ${statePath}`);
  }
  const runState = readRunState(statePath);
  const expectedIds = new Set(
    plan.transactions.map((transaction) => transaction.id)
  );
  for (const transactionId of Object.keys(runState)) {
    if (!expectedIds.has(transactionId)) {
      throw new Error(
        `Run state contains unknown transaction id ${transactionId}`
      );
    }
  }
  for (const transaction of plan.transactions) {
    const entry = runState[transaction.id];
    if (!entry || entry.status !== "verified") {
      throw new Error(`Run state entry ${transaction.id} is not verified`);
    }
    if (!/^0x[a-fA-F0-9]{64}$/.test(entry.txHash || "")) {
      throw new Error(`Run state entry ${transaction.id} has invalid txHash`);
    }
    recordedBlockNumber(entry, transaction.id);
    if (
      transaction.kind === "deploy" &&
      !ADDRESS_REGEX.test(entry.resolvedAddress || "")
    ) {
      throw new Error(
        `Run state deployment ${transaction.id} has invalid resolvedAddress`
      );
    }
  }

  const rpc = createRpcClient(rpcUrl);
  const actualChainId = Number(BigInt(await rpc("eth_chainId")));
  if (actualChainId !== plan.chainId) {
    throw new Error(
      `RPC chain id mismatch: plan=${plan.chainId}, rpc=${actualChainId}`
    );
  }
  const outputs = outputsFromRunState(plan, runState);
  for (const transaction of plan.transactions) {
    const entry = runState[transaction.id];
    const [receipt, actualTransaction] = await Promise.all([
      rpc("eth_getTransactionReceipt", [entry.txHash]),
      rpc("eth_getTransactionByHash", [entry.txHash]),
    ]);
    if (!receipt || !actualTransaction) {
      throw new Error(
        `Run state transaction ${transaction.id} is not present on the RPC`
      );
    }
    if (BigInt(receipt.status) !== 1n) {
      throw new Error(
        `Run state transaction ${transaction.id} did not succeed`
      );
    }
    if (
      BigInt(receipt.blockNumber) !== recordedBlockNumber(entry, transaction.id)
    ) {
      throw new Error(
        `Run state transaction ${transaction.id} has a different block number`
      );
    }
    const expectedExecutor = getAddress(transaction.envelope.expectedExecutor);
    if (
      getAddress(receipt.from) !== expectedExecutor ||
      getAddress(actualTransaction.from) !== expectedExecutor
    ) {
      throw new Error(
        `Run state transaction ${transaction.id} has the wrong executor`
      );
    }

    const payload = transactionPayload(transaction, outputs);
    const actualTo = actualTransaction.to
      ? getAddress(actualTransaction.to)
      : null;
    const expectedTo = payload.to ? getAddress(payload.to) : null;
    if (actualTo !== expectedTo) {
      throw new Error(
        `Run state transaction ${transaction.id} has the wrong destination`
      );
    }
    if (
      (actualTransaction.input || "").toLowerCase() !==
      payload.data.toLowerCase()
    ) {
      throw new Error(
        `Run state transaction ${transaction.id} has different calldata`
      );
    }
    if (BigInt(actualTransaction.value) !== payload.value) {
      throw new Error(
        `Run state transaction ${transaction.id} has a different value`
      );
    }
    if (transaction.kind === "deploy") {
      if (
        !receipt.contractAddress ||
        getAddress(receipt.contractAddress) !==
          getAddress(entry.resolvedAddress)
      ) {
        throw new Error(
          `Run state deployment ${transaction.id} has a different receipt address`
        );
      }
    }
    console.log(`PROVENANCE ${transaction.id}: ${entry.txHash}`);
  }
  console.log(
    `EOA run-state provenance passed: ${plan.transactions.length} transaction(s).`
  );
}

function safeInputValue(value) {
  if (isReference(value)) return `$ref:${value.$ref}`;
  if (Array.isArray(value) || (value !== null && typeof value === "object")) {
    return JSON.stringify(value, (_key, entry) =>
      isReference(entry) ? `$ref:${entry.$ref}` : entry
    );
  }
  return String(value);
}

function renderSafe(args) {
  const plan = assertValidPlan(readJson(requiredArg(args, "plan")));

  // Secondary output only: deployments are intentionally excluded because
  // Safe Transaction Builder MultiSend entries cannot express contract
  // creation. Later call targets created by the plan are also unresolved, so
  // refs use the zero address plus explicit metadata and must be resolved
  // before importing or signing.
  const transactions = plan.transactions
    .filter((transaction) => transaction.kind === "call")
    .map((transaction) => {
      const { fragment } = functionInterface(transaction.functionSignature);
      const unresolvedReferences = [];
      for (const value of transaction.forwardedCall
        ? [
            transaction.to,
            transaction.forwardedCall.target,
            transaction.forwardedCall.args,
          ]
        : [transaction.to, transaction.args]) {
        collectReferences(value, unresolvedReferences);
      }
      const displayArgs = transaction.forwardedCall
        ? [
            transaction.forwardedCall.target,
            encodeFunctionCall(
              transaction.forwardedCall.functionSignature,
              transaction.forwardedCall.args
            ),
          ]
        : transaction.args;
      const names = new Set();
      const inputs = fragment.inputs.map((input, index) => {
        let name = input.name || `arg${index}`;
        while (names.has(name)) name = `${name}_${index}`;
        names.add(name);
        return { internalType: input.type, name, type: input.type };
      });
      const contractInputsValues = Object.fromEntries(
        inputs.map((input, index) => [
          input.name,
          safeInputValue(displayArgs[index]),
        ])
      );
      return {
        to: isReference(transaction.to) ? ZERO_ADDRESS : transaction.to,
        value: parseQuantity(
          transaction.envelope.value,
          `${transaction.id}.envelope.value`
        ).toString(),
        data: transaction.calldata,
        contractMethod: {
          inputs,
          name: fragment.name,
          payable: fragment.stateMutability === "payable",
        },
        contractInputsValues,
        description: `[${transaction.id}] ${transaction.description}`,
        unresolvedReferences: [...new Set(unresolvedReferences)],
      };
    });

  const output = {
    version: "1.0",
    chainId: String(plan.chainId),
    createdAt: Date.now(),
    meta: {
      name: `Wildcat ${plan.release} owner calls (secondary rendering)`,
      description:
        "Secondary call-only rendering. Resolve every unresolvedReferences entry before importing into Safe.",
      txBuilderVersion: "1.18.0",
      createdFromSafeAddress: plan.expectedExecutor,
      createdFromOwnerAddress: "",
      checksum: "",
    },
    transactions,
  };
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
}

function runValidate(args) {
  const planPath = requiredArg(args, "plan");
  const result = validatePlan(readJson(planPath));
  if (!result.ok) {
    for (const error of result.errors) console.error(`Error: ${error}`);
    process.exitCode = 1;
    return;
  }
  console.log(`Deployment plan valid: ${planPath}`);
}

function bundleCommands() {
  return require("./plan-bundle")({
    REPO_ROOT,
    assertValidPlan,
    checkPredicate,
    createRpcClient,
    loadArtifact,
    readJson,
    receiptBlockNumber,
    resolveReferences,
    runStatePath,
    transactionPayload,
    validateJsonSchema,
    waitForReceipt,
    writeJson,
    writeJsonAtomic,
  });
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv.includes("--help") || argv.includes("-h")) {
    printUsage();
    return;
  }
  const command = argv[0];
  const args = parseArgs(argv.slice(1));
  assertKnownFlags(command, args);
  if (command === "assemble") return assemblePlan(args);
  if (command === "validate") return runValidate(args);
  if (command === "execute") return executePlan(args);
  if (command === "verify") return verifyPlan(args);
  if (command === "verify-eoa-run-state") return verifyEoaRunState(args);
  if (command === "render-safe") return renderSafe(args);
  if (command === "bundle") return bundleCommands().bundlePlan(args);
  if (command === "bundle-simulate") {
    return bundleCommands().simulateBundles(args);
  }
  if (command === "bundle-verify") {
    return bundleCommands().verifyBundles(args);
  }
  if (command === "ceremony-package") {
    return bundleCommands().writeCeremonyPackage(args);
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
  PLAN_SCHEMA_VERSION,
  callEq,
  checkPredicate,
  collapseDuplicateArtifactCandidates,
  codePresent,
  encodeConstructorArgs,
  encodeFunctionCall,
  encodeForwardedCall,
  validatePlan,
  authorizedHelperTransactions,
};
