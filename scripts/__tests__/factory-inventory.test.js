const { test } = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { createInventory, lintDeployments } = require("../factory-inventory");

const ADDRESS = "0x0000000000000000000000000000000000000001";

function lintKey(key) {
  return lintDeployments({
    inventory: createInventory({ network: "anvil", chainId: 31337 }),
    deployments: { [key]: ADDRESS },
  });
}

test("inventory lint preserves supported deployment key shapes", () => {
  for (const key of [
    "A",
    "a0",
    "HooksFactory",
    "WildcatMarket_initCodeStorage_v2-5",
    "WildcatMarket_initCodeStorage_v2.5.5_secondary",
    "HooksFactory_v2.5.5",
    "src:WildcatMarket",
    "A:B-C_D:E",
    "A-0",
    "A--",
    "A:-",
    "A_-",
    "A--_B",
    "A:--_B",
    "A:" + "-".repeat(100_000),
  ]) {
    assert.equal(lintKey(key).ok, true, key);
  }
});

test("inventory lint rejects malformed deployment key shapes", () => {
  for (const key of [
    "",
    "0A",
    ":A",
    "A:",
    "A_",
    "A-",
    "A::B",
    "A:_B",
    "A_:B",
    "A-_B",
    "A__B",
    "A/B",
    "A B",
    "A\\B",
    "A:--!",
    "A..B",
    "A.",
    ".A",
    "A_../B",
  ]) {
    const result = lintKey(key);
    assert.equal(result.ok, false, key);
    assert.deepEqual(result.errors, [
      `deployments.json key ${key} has an unknown key shape`,
    ]);
  }
});

test("inventory lint rejects long ambiguous keys without stalling", () => {
  const result = spawnSync(
    process.execPath,
    [
      "-e",
      `
        const assert = require("node:assert/strict");
        const { createInventory, lintDeployments } = require(process.argv[1]);
        const key = "A:" + "-".repeat(100_000) + "!";
        const result = lintDeployments({
          inventory: createInventory({ network: "anvil", chainId: 31337 }),
          deployments: { [key]: "${ADDRESS}" },
        });
        assert.equal(result.ok, false);
        assert.deepEqual(result.errors, [
          "deployments.json key " + key + " has an unknown key shape",
        ]);
      `,
      require.resolve("../factory-inventory"),
    ],
    { encoding: "utf8", timeout: 5_000 }
  );
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
});
