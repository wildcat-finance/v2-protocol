const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { Interface } = require("ethers");

test("bundle review escapes descriptions without changing payloads", (context) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "wildcat-bundle-"));
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const safe = "0x0000000000000000000000000000000000000001";
  const target = "0x0000000000000000000000000000000000000002";
  const descriptions = [
    ["Record plain labels.", "Record plain labels."],
    [String.raw`Record left\|right.`, String.raw`Record left\\\|right.`],
    [
      String.raw`Record left\\|right|tail.`,
      String.raw`Record left\\\\\|right\|tail.`,
    ],
    ["  Record \tspaced\\|labels.", String.raw`Record spaced\\\|labels.`],
  ];
  const contractInterface = new Interface(["function setValue(uint256)"]);
  const plan = {
    schemaVersion: "1.1.0",
    foundryProfile: "deploy",
    network: "anvil",
    chainId: 31337,
    release: "markdown-test",
    expectedExecutor: safe,
    onFailure: "halt",
    resume: "re-verify all prior predicates before continuing",
    transactions: descriptions.map(([description], index) => ({
      id: `set-value-${index}`,
      kind: "call",
      description,
      to: target,
      functionSignature: "setValue(uint256)",
      args: [index],
      calldata: contractInterface.encodeFunctionData("setValue", [index]),
      envelope: {
        chainId: 31337,
        expectedExecutor: safe,
        to: target,
        value: "0",
        data: "functionSignature+args",
        gasLimitPolicy: "estimate*1.3",
        nonceCheck: "display-and-confirm",
      },
      predicate: { type: "codePresent", target },
    })),
  };
  const planPath = path.join(directory, "plan.json");
  fs.writeFileSync(planPath, JSON.stringify(plan));
  execFileSync(
    process.execPath,
    [
      require.resolve("../plan"),
      "bundle",
      "--plan",
      planPath,
      "--safe",
      safe,
      "--start-nonce",
      "0",
      "--out-dir",
      directory,
    ],
    { encoding: "utf8", timeout: 10_000 }
  );
  const markdown = fs.readFileSync(
    path.join(directory, `review-${plan.release}.md`),
    "utf8"
  );
  const manifest = JSON.parse(
    fs.readFileSync(path.join(directory, "bundle-1.manifest.json"))
  );
  descriptions.forEach(([description, escaped], index) => {
    assert.ok(
      markdown.includes(`| ${index + 1} | set-value-${index} | ${escaped} |`),
      escaped
    );
    const transaction = manifest.innerTransactions[index];
    assert.equal(transaction.description, description);
    assert.equal(transaction.to, target);
    assert.equal(transaction.data, plan.transactions[index].calldata);
    assert.equal(transaction.value, "0");
    assert.equal(transaction.operation, 0);
  });
});
