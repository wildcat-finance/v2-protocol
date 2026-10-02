const REGISTRATION_SIGNATURE =
  "addHooksTemplate(address,string,address,address,uint80,uint16,bytes32)";
const HASH_GETTER =
  "getHooksTemplateInitCodeHash(address) view returns (bytes32)";
const HASH = /^0x[0-9a-fA-F]{64}$/;
const ZERO_HASH = `0x${"00".repeat(32)}`;
const { keccak256 } = require("ethers");

function assertSplitStorageCommitments(plan) {
  for (const [index, primary] of plan.transactions.entries()) {
    if (primary.artifactName !== "script/common/PreparedInitCodeStorage.sol:LinkedInitCodeStorage") continue;
    const output = `${primary.output}-secondary`;
    const secondary = plan.transactions.slice(0, index).find((entry) => entry.output === output);
    const args = primary.constructorArgs?.decoded;
    const tailArgs = secondary?.constructorArgs?.decoded;
    const predicate = primary.predicate;
    const image = args?.[0];
    const tail = tailArgs?.[0];
    if (args?.length !== 2 || args[1]?.$ref !== output ||
        typeof image !== "string" || !/^0x(?:[a-fA-F0-9]{2}){32,24576}$/.test(image) ||
        image.slice(-48, -8) !== "00".repeat(20) ||
        secondary?.id !== `${primary.id}-secondary` || secondary?.kind !== "deploy" ||
        secondary?.artifactName !== "script/common/PreparedInitCodeStorage.sol:PreparedInitCodeStorage" ||
        tailArgs?.length !== 1 || typeof tail !== "string" || !/^0x00(?:[a-fA-F0-9]{2}){0,24575}$/.test(tail) ||
        predicate?.type !== "splitCodeHash" || predicate.target?.$ref !== primary.output ||
        predicate.secondary?.$ref !== output || secondary.predicate?.type !== "codeHash" ||
        secondary.predicate.target?.$ref !== output ||
        requireArtifactHash(predicate.expect, primary.id) !== keccak256(image) ||
        requireArtifactHash(predicate.secondaryCodeHash, primary.id) !== keccak256(tail) ||
        requireArtifactHash(secondary.predicate.expect, secondary.id) !== keccak256(tail)) {
      throw new Error(`${primary.id}: split storage artifacts or secondary link do not match`);
    }
    const firstLength = parseInt(image.slice(-8, -4), 16);
    const secondLength = parseInt(image.slice(-4), 16);
    const imageLength = (image.length - 2) / 2;
    if (firstLength + 24 >= imageLength || secondLength !== (tail.length - 4) / 2) {
      throw new Error(`${primary.id}: split storage lengths do not match`);
    }
    const first = firstLength ? image.slice(-48 - firstLength * 2, -48) : "";
    if (requireArtifactHash(predicate.initCodeHash, primary.id) !== keccak256(`0x${first}${tail.slice(4)}`)) {
      throw new Error(`${primary.id}: split storage creation artifact hash does not match`);
    }
  }
}

function requireArtifactHash(hash, label) {
  if (typeof hash !== "string" || !HASH.test(hash) || hash === ZERO_HASH) {
    throw new Error(
      `${label}: provide a nonzero initCodeHash from the reviewed creation artifact`
    );
  }
  return hash.toLowerCase();
}

function assertActivationTemplateCommitments(plan) {
  const transactions = plan.transactions;
  const logicalCall = (transaction) =>
    transaction.forwardedCall || {
      target: transaction.to,
      functionSignature: transaction.functionSignature,
      args: transaction.args,
    };
  const templates = [
    ["open-term", "OpenTermHooks"],
    ["fixed-term", "FixedTermHooks"],
    ["periodic-term", "PeriodicTermHooks"],
  ];
  const registrations = transactions.filter(
    (transaction) =>
      logicalCall(transaction).functionSignature === REGISTRATION_SIGNATURE
  );
  if (registrations.length !== 6)
    throw new Error("Expected six artifact-bound template registrations");
  for (const factory of ["standard", "revolving"]) {
    for (const [term, name] of templates) {
      const id = `add-${factory}-${term}-template`;
      const transaction = registrations.find((entry) => entry.id === id);
      if (!transaction) throw new Error(`Missing template registration ${id}`);
      const call = logicalCall(transaction);
      const storeOutput = `${term}-hooks-init-code-storage`;
      const factoryOutput = `hooks-factory-${factory}`;
      if (
        call.target?.$ref !== factoryOutput ||
        call.args?.length !== 7 ||
        call.args[0]?.$ref !== storeOutput ||
        call.args[1] !== name
      ) {
        throw new Error(
          `${id}: template, factory, or registration arguments do not match`
        );
      }
      const expectedHash = requireArtifactHash(call.args[6], id);
      const store = transactions.find((entry) => entry.output === storeOutput);
      if (
        !["codeHash", "splitCodeHash"].includes(store?.predicate?.type) ||
        store.predicate.target?.$ref !== storeOutput ||
        requireArtifactHash(store.predicate.initCodeHash, storeOutput) !==
          expectedHash
      ) {
        throw new Error(
          `${id}: registration and storage artifact hashes do not match`
        );
      }
      const predicate = transaction.predicate;
      if (
        predicate?.type !== "callEq" ||
        predicate.target?.$ref !== factoryOutput ||
        predicate.call?.sig !== HASH_GETTER ||
        predicate.call.args?.length !== 1 ||
        predicate.call.args[0]?.$ref !== storeOutput ||
        requireArtifactHash(predicate.expect, `${id} predicate`) !==
          expectedHash
      ) {
        throw new Error(
          `${id}: registration must verify the committed artifact hash`
        );
      }
    }
  }
}

module.exports = {
  REGISTRATION_SIGNATURE,
  HASH_GETTER,
  requireArtifactHash,
  assertActivationTemplateCommitments,
  assertSplitStorageCommitments,
};
