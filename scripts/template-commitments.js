const REGISTRATION_SIGNATURE =
  "addHooksTemplate(address,string,address,address,uint80,uint16,bytes32)";
const HASH_GETTER =
  "getHooksTemplateInitCodeHash(address) view returns (bytes32)";
const HASH = /^0x[0-9a-fA-F]{64}$/;
const ZERO_HASH = `0x${"00".repeat(32)}`;

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
        store?.predicate?.type !== "codeHash" ||
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
};
