const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  REGISTRATION_SIGNATURE,
  HASH_GETTER,
  assertActivationTemplateCommitments,
} = require("../template-commitments");
const { assertActivationPlan } = require("../factory-inventory");
const { keccak256 } = require("ethers");
const {
  normalizeTemplate,
  diffTemplateDetails,
  fetchTemplates,
  preflightCommitments,
} = require("../rcf-template-sync");

const HASH_A = `0x${"ab".repeat(32)}`;
const HASH_B = `0x${"cd".repeat(32)}`;
const ZERO_HASH = `0x${"00".repeat(32)}`;
const ADDRESS = "0x0000000000000000000000000000000000000001";
const SECOND = "0x0000000000000000000000000000000000000002";
const RAW = "script/common/DeployScriptBase.sol:InitCodeStorage";
const COMPRESSED =
  "script/common/DeployScriptBase.sol:CompressedInitCodeStorage";
const ref = ($ref) => ({ $ref });

function activationPlan(compressed = false) {
  const transactions = [];
  const deploy = (output, artifactName) =>
    transactions.push({
      id: `deploy-${output}`,
      output,
      artifactName,
      kind: "deploy",
    });
  const store = (output) => {
    deploy(output, compressed ? COMPRESSED : RAW);
    transactions.at(-1).predicate = {
      type: "codeHash",
      target: ref(output),
      expect: HASH_B,
      initCodeHash: HASH_A,
    };
  };
  const call = (id, to, functionSignature, args = []) =>
    transactions.push({ id, to, functionSignature, args, kind: "call" });
  deploy(
    "wildcat-4626-wrapper-factory",
    "src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory"
  );
  deploy(
    "borrower-identity-registry",
    "src/WildcatBorrowerIdentityRegistry.sol:WildcatBorrowerIdentityRegistry"
  );
  deploy(
    "access-list-role-provider-factory",
    "src/providers/AccessListRoleProviderFactory.sol:AccessListRoleProviderFactory"
  );
  store("wildcat-market-init-code-storage");
  deploy("hooks-factory-standard", "src/HooksFactory.sol:HooksFactory");
  store("wildcat-market-revolving-init-code-storage");
  deploy(
    "hooks-factory-revolving",
    "src/HooksFactoryRevolving.sol:HooksFactoryRevolving"
  );
  for (const [id, name] of [
    ["core", "Core"],
    ["aggregator", "Aggregator"],
    ["live", "Live"],
    ["", ""],
  ]) {
    deploy(
      `market-lens${id ? `-${id}` : ""}`,
      `src/lens/MarketLens${name}.sol:MarketLens${name}`
    );
  }
  const terms = [
    ["open", "Open"],
    ["fixed", "Fixed"],
    ["periodic", "Periodic"],
  ];
  for (const [term] of terms) store(`${term}-term-hooks-init-code-storage`);
  for (const model of ["standard", "revolving"]) {
    call(
      `register-controller-factory-${model}`,
      ADDRESS,
      "registerControllerFactory(address)",
      [ref(`hooks-factory-${model}`)]
    );
  }
  for (const model of ["standard", "revolving"]) {
    for (const [term, name] of terms) {
      const factory = ref(`hooks-factory-${model}`);
      const storage = ref(`${term}-term-hooks-init-code-storage`);
      call(
        `add-${model}-${term}-term-template`,
        factory,
        REGISTRATION_SIGNATURE,
        [storage, `${name}TermHooks`, ADDRESS, ADDRESS, 0, 0, HASH_A]
      );
      transactions.at(-1).predicate = {
        type: "callEq",
        target: factory,
        call: { sig: HASH_GETTER, args: [storage] },
        expect: HASH_A,
      };
    }
  }
  for (const model of ["standard", "revolving"]) {
    call(
      `register-hooks-factory-${model}`,
      ref(`hooks-factory-${model}`),
      "registerWithArchController()"
    );
  }
  return { network: "commitment-test", release: "v2-5", transactions };
}

function firstRegistration(plan) {
  return plan.transactions.find(
    (tx) => tx.id === "add-standard-open-term-template"
  );
}

test("activation accepts raw and prepared compressed storage with matching commitments", () => {
  for (const compressed of [false, true])
    assertActivationPlan(activationPlan(compressed), "commitment-test");
});

test("activation accepts split markets and future split templates with their companion entries", () => {
  for (const includeHooks of [false, true]) {
    const candidate = activationPlan();
    const selected = candidate.transactions.filter((tx) =>
      tx.artifactName === RAW && (includeHooks || tx.output.startsWith("wildcat-market"))
    );
    for (const primary of selected) {
      const output = `${primary.output}-secondary`;
      const image = "0x600060005260206000f3abcd" + "00".repeat(20) + "00020001";
      const tail = "0x00ef";
      const hash = keccak256("0xabcdef");
      primary.artifactName = "script/common/PreparedInitCodeStorage.sol:LinkedInitCodeStorage";
      primary.constructorArgs = { decoded: [image, ref(output)] };
      primary.predicate = { type: "splitCodeHash", target: ref(primary.output), expect: keccak256(image),
        secondary: ref(output), secondaryCodeHash: keccak256(tail), initCodeHash: hash };
      candidate.transactions.splice(candidate.transactions.indexOf(primary), 0, {
        id: `${primary.id}-secondary`, kind: "deploy", output,
        artifactName: "script/common/PreparedInitCodeStorage.sol:PreparedInitCodeStorage",
        constructorArgs: { decoded: [tail] },
        predicate: { type: "codeHash", target: ref(output), expect: keccak256(tail) },
      });
      for (const registration of candidate.transactions.filter((tx) =>
        tx.functionSignature === REGISTRATION_SIGNATURE && tx.args[0].$ref === primary.output
      )) {
        registration.args[6] = hash;
        registration.predicate.expect = hash;
      }
    }
    assertActivationPlan(candidate, "commitment-test");
    const malformed = structuredClone(candidate);
    malformed.transactions.find((tx) => tx.predicate?.type === "splitCodeHash").predicate.secondaryCodeHash = HASH_B;
    assert.throws(() => assertActivationPlan(malformed, "commitment-test"), /split storage/);
  }
});

test("commitment matrix follows authorized-helper logical calls", () => {
  const plan = activationPlan();
  for (const tx of plan.transactions.filter(
    (entry) => entry.functionSignature === REGISTRATION_SIGNATURE
  )) {
    tx.forwardedCall = {
      target: tx.to,
      functionSignature: tx.functionSignature,
      args: tx.args,
    };
    tx.to = ADDRESS;
    tx.functionSignature = "executeProtocolAction(address,bytes)";
    delete tx.args;
  }
  assertActivationTemplateCommitments(plan);
  firstRegistration(plan).forwardedCall.args[6] = HASH_B;
  assert.throws(
    () => assertActivationTemplateCommitments(plan),
    /hashes do not match/
  );
});

test("Sepolia ceremony forwards the new registration selector through its configured owner", () => {
  const directory = path.resolve(__dirname, "../../deployments/sepolia");
  const config = JSON.parse(
    fs.readFileSync(path.join(directory, "ceremony-config.json"))
  );
  const addresses = JSON.parse(
    fs.readFileSync(path.join(directory, "deployments.json"))
  );
  const plan = activationPlan(true);
  plan.network = "sepolia";
  plan.expectedExecutor = ADDRESS;
  const signatures = config.ownership.forwardedFunctionSignatures;
  assert.ok(signatures.includes(REGISTRATION_SIGNATURE));
  for (const tx of plan.transactions.filter((entry) =>
    signatures.includes(entry.functionSignature)
  )) {
    tx.forwardedCall = {
      target: tx.to,
      functionSignature: tx.functionSignature,
      args: tx.args,
    };
    tx.to = addresses[config.ownership.helperOwnerKey];
    tx.functionSignature = "executeProtocolAction(address,bytes)";
    delete tx.args;
  }
  assertActivationPlan(plan, "sepolia");
});

for (const [name, mutate] of [
  ["missing hash", (tx) => tx.args.pop()],
  ["zero hash", (tx) => (tx.args[6] = ZERO_HASH)],
  ["wrong hash", (tx) => (tx.args[6] = HASH_B)],
  [
    "wrong storage",
    (tx) => (tx.args[0] = ref("fixed-term-hooks-init-code-storage")),
  ],
  [
    "old selector",
    (tx) =>
      (tx.functionSignature =
        "addHooksTemplate(address,string,address,address,uint80,uint16)"),
  ],
  [
    "boolean-only readback",
    (tx) => {
      tx.predicate.call.sig = "isHooksTemplate(address) view returns (bool)";
      tx.predicate.expect = true;
    },
  ],
  ["wrong hash readback", (tx) => (tx.predicate.expect = HASH_B)],
  [
    "wrong factory readback",
    (tx) => (tx.predicate.target = ref("hooks-factory-revolving")),
  ],
]) {
  test(`activation rejects ${name}`, () => {
    const plan = activationPlan();
    mutate(firstRegistration(plan));
    assert.throws(() => assertActivationPlan(plan, "commitment-test"));
  });
}

test("activation rejects missing storage attestation and arbitrary storage blueprints", () => {
  for (const change of [
    (tx) => delete tx.predicate.initCodeHash,
    (tx) => (tx.predicate.initCodeHash = HASH_B),
    (tx) => (tx.artifactName = "arbitrary.sol:Reader"),
  ]) {
    const plan = activationPlan(true);
    change(
      plan.transactions.find(
        (tx) => tx.output === "open-term-hooks-init-code-storage"
      )
    );
    assert.throws(() => assertActivationPlan(plan, "commitment-test"));
  }
});

const details = {
  name: "fixture",
  feeRecipient: ADDRESS,
  originationFeeAsset: ADDRESS,
  originationFeeAmount: 0n,
  protocolFeeBips: 0,
  enabled: true,
};
const template = (address = ADDRESS, hash = HASH_A) =>
  normalizeTemplate(address, details, hash);

test("sync preflight checks all supplied hashes before making target calls", async () => {
  const factory = {
    getHooksTemplateInitCodeHash: () =>
      assert.fail("must reject before any target calls"),
  };
  for (const hash of [null, ZERO_HASH, "0x1234"]) {
    await assert.rejects(
      preflightCommitments(factory, [template(), template(SECOND, hash)]),
      /reviewed creation artifact/
    );
  }
  await assert.rejects(
    preflightCommitments(factory, [template(), template()]),
    /Duplicate template/
  );
});

test("sync permits new registration and matching existing commitments", async () => {
  const factory = {
    getHooksTemplateInitCodeHash: async (address) =>
      address === ADDRESS ? HASH_A : ZERO_HASH,
    isHooksTemplate: async (address) => address === ADDRESS,
  };
  const result = await preflightCommitments(factory, [
    template(),
    template(SECOND),
  ]);
  assert.equal(result.get(ADDRESS).exists, true);
  assert.equal(result.get(SECOND).exists, false);
});

test("sync rejects a different existing commitment or an old target interface", async () => {
  await assert.rejects(
    preflightCommitments(
      {
        getHooksTemplateInitCodeHash: async () => HASH_B,
        isHooksTemplate: async () => true,
      },
      [template()]
    ),
    /different immutable initCodeHash/
  );
  await assert.rejects(
    preflightCommitments(
      {
        getHooksTemplateInitCodeHash: async () => {
          throw new Error("missing selector");
        },
      },
      [template()]
    ),
    /new factory interface/
  );
  assert.deepEqual(diffTemplateDetails(template(), template(ADDRESS, HASH_B)), [
    "initCodeHash",
  ]);
});

test("legacy source exports remain readable but cannot silently supply a commitment", async () => {
  const factory = {
    getHooksTemplates: async () => [ADDRESS],
    getHooksTemplateDetails: async () => details,
    getHooksTemplateInitCodeHash: async () => {
      throw Object.assign(new Error("missing selector"), {
        code: "CALL_EXCEPTION",
        data: "0x",
      });
    },
  };
  const exported = await fetchTemplates(factory, true);
  assert.equal(exported[0].initCodeHash, null);
  await assert.rejects(
    preflightCommitments({}, exported),
    /reviewed creation artifact/
  );
  await assert.rejects(fetchTemplates(factory), /missing selector/);
  factory.getHooksTemplateInitCodeHash = async () => {
    throw Object.assign(new Error("RPC unavailable"), {
      code: "NETWORK_ERROR",
    });
  };
  await assert.rejects(fetchTemplates(factory, true), /RPC unavailable/);
});
