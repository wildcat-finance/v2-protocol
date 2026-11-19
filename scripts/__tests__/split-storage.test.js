const { test } = require("node:test");
const assert = require("node:assert/strict");
const { keccak256 } = require("ethers");
const { assertSplitStorageCommitments } = require("../template-commitments");
const ref = ($ref) => ({ $ref });
const PREPARED =
  "script/common/PreparedInitCodeStorage.sol:PreparedInitCodeStorage";
const LINKED =
  "script/common/PreparedInitCodeStorage.sol:LinkedInitCodeStorage";

function fixture() {
  const image = "0x600060005260206000f3abcd" + "00".repeat(20) + "00020001";
  const tail = "0x00ef";
  return {
    transactions: [
      {
        id: "deploy-store-secondary",
        kind: "deploy",
        output: "store-secondary",
        artifactName: PREPARED,
        constructorArgs: { decoded: [tail] },
        predicate: {
          type: "codeHash",
          target: ref("store-secondary"),
          expect: keccak256(tail),
        },
      },
      {
        id: "deploy-store",
        kind: "deploy",
        output: "store",
        artifactName: LINKED,
        constructorArgs: { decoded: [image, ref("store-secondary")] },
        predicate: {
          type: "splitCodeHash",
          target: ref("store"),
          expect: keccak256(image),
          secondary: ref("store-secondary"),
          secondaryCodeHash: keccak256(tail),
          initCodeHash: keccak256("0xabcdef"),
        },
      },
    ],
  };
}

test("split activation binds constructor inputs, both images, original bytes and deployment order", () => {
  assertSplitStorageCommitments(fixture());
});
for (const [name, mutate] of [
  ["missing secondary", (p) => p.transactions.shift()],
  ["forward secondary", (p) => p.transactions.reverse()],
  [
    "wrong link",
    (p) => (p.transactions[1].constructorArgs.decoded[1] = ref("other")),
  ],
  [
    "wrong primary runtime hash",
    (p) => (p.transactions[1].predicate.expect = keccak256("0x00")),
  ],
  [
    "wrong secondary commitment",
    (p) => (p.transactions[1].predicate.secondaryCodeHash = keccak256("0x00")),
  ],
  [
    "wrong secondary predicate",
    (p) => (p.transactions[0].predicate.expect = keccak256("0x00")),
  ],
  [
    "wrong original artifact",
    (p) => (p.transactions[1].predicate.initCodeHash = keccak256("0x00")),
  ],
  [
    "weakened predicate",
    (p) => (p.transactions[1].predicate.type = "codeHash"),
  ],
  [
    "unreviewed installer",
    (p) => (p.transactions[0].artifactName = "Unreviewed.sol:Installer"),
  ],
  [
    "nonempty address placeholder",
    (p) =>
      (p.transactions[1].constructorArgs.decoded[0] =
        p.transactions[1].constructorArgs.decoded[0].replace(
          "abcd00",
          "abcd01"
        )),
  ],
  [
    "mismatched lengths",
    (p) => {
      const tx = p.transactions[1];
      tx.constructorArgs.decoded[0] =
        tx.constructorArgs.decoded[0].slice(0, -4) + "0002";
      tx.predicate.expect = keccak256(tx.constructorArgs.decoded[0]);
    },
  ],
]) {
  test(`split activation rejects ${name}`, () => {
    const plan = fixture();
    mutate(plan);
    assert.throws(() => assertSplitStorageCommitments(plan), /split storage/);
  });
}
