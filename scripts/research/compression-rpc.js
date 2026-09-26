#!/usr/bin/env node
// Local transaction qualification with actual code-size and per-transaction gas limits.
const fs = require("node:fs");
const path = require("node:path");
const net = require("node:net");
const { spawn, execFileSync } = require("node:child_process");
const {
  AbiCoder,
  Interface,
  ZeroAddress,
  concat,
  getCreate2Address,
  keccak256,
  toBeHex,
} = require("ethers");

const ROOT = path.resolve(__dirname, "../..");
const CAP = 16_777_216;
const abi = AbiCoder.defaultAbiCoder();
if (!process.argv[2])
  throw new Error(
    "usage: node scripts/research/compression-rpc.js <new-receipt-directory>"
  );
const receiptDirectory = path.resolve(process.argv[2]);
fs.mkdirSync(receiptDirectory, { recursive: false });
const record = {
  anvil: execFileSync("anvil", ["--version"], { encoding: "utf8" }).trim(),
  hardfork: "osaka",
  transactionGasCap: CAP,
  transactions: [],
};
const artifacts = new Map();

function artifact(file, name) {
  const key = `${file}:${name}`;
  if (artifacts.has(key)) return artifacts.get(key);
  const location = path.join(ROOT, "deploy-out", file + ".sol", name + ".json");
  const value = JSON.parse(fs.readFileSync(location));
  fs.copyFileSync(location, path.join(receiptDirectory, name + ".json"));
  artifacts.set(key, value);
  return value;
}

function storageCreation(runtime) {
  const size = (runtime.length - 2) / 2;
  if (size > 24_576) throw new Error("storage exceeds EIP-170");
  return concat([
    `0x61${size.toString(16).padStart(4, "0")}5f81600a5f39f3`,
    runtime,
  ]);
}

// Constructors patch immutable slots. Compare the rest of the runtime byte for byte;
// constructor context and configured terms are checked through the deployed interfaces.
function runtimeMatches(compiled, code) {
  const expected = Buffer.from(
    compiled.deployedBytecode.object.slice(2),
    "hex"
  );
  const actual = Buffer.from(code.slice(2), "hex");
  if (expected.length !== actual.length || actual.length > 24_576) return false;
  for (const references of Object.values(
    compiled.deployedBytecode.immutableReferences
  )) {
    for (const { start, length } of references) {
      expected.fill(0, start, start + length);
      actual.fill(0, start, start + length);
    }
  }
  return actual.equals(expected);
}

async function main() {
  const server = net.createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  const node = spawn(
    "anvil",
    [
      "--host",
      "127.0.0.1",
      "--port",
      String(port),
      "--hardfork",
      "osaka",
      "--enable-tx-gas-limit",
      "--gas-limit",
      "30000000",
      "--quiet",
    ],
    { stdio: "ignore" }
  );
  let id = 0;
  async function rpc(method, params = []) {
    const response = await fetch(`http://127.0.0.1:${port}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
    });
    const result = await response.json();
    if (result.error) throw new Error(JSON.stringify(result.error));
    return result.result;
  }
  async function receipt(hash) {
    for (let attempt = 0; attempt < 200; ++attempt) {
      const result = await rpc("eth_getTransactionReceipt", [hash]);
      if (result) return result;
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    throw new Error("local transaction was not mined");
  }
  try {
    let account;
    for (let attempt = 0; attempt < 100; ++attempt) {
      try {
        [account] = await rpc("eth_accounts");
        break;
      } catch {
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
    }
    if (!account) throw new Error("local node did not start");
    // prove the node enforces the cap; a relaxed node is not qualification.
    let rejected = false;
    try {
      await rpc("eth_sendTransaction", [
        { from: account, to: account, gas: toBeHex(CAP + 1) },
      ]);
    } catch (error) {
      rejected = /gas.*(cap|limit)|limit.*gas/i.test(error.message);
    }
    if (!rejected)
      throw new Error("node did not reject an over-cap transaction");
    record.overCapRejected = true;
    const reader = artifact("LibCompressedInitCode", "CompressedInitCodeReader")
      .deployedBytecode.object;
    const planned = artifact("DeployScriptBase", "CompressedInitCodeStorage")
      .bytecode.object;
    const fixtures = JSON.parse(
      fs.readFileSync(path.join(ROOT, "deploy-out/compression-rpc.json"))
    );
    fs.copyFileSync(
      path.join(ROOT, "deploy-out/compression-rpc.json"),
      path.join(receiptDirectory, "compression-rpc.json")
    );
    async function send(label, transaction) {
      const request = { from: account, ...transaction };
      const estimatedGas = Number(
        await rpc("eth_estimateGas", [{ ...request, gas: toBeHex(CAP) }])
      );
      const bufferedGas = Math.ceil(estimatedGas * 1.3);
      if (bufferedGas > CAP)
        throw new Error(
          `${label}: the normal gas buffer exceeds the transaction cap`
        );
      const hash = await rpc("eth_sendTransaction", [
        { ...request, gas: toBeHex(bufferedGas) },
      ]);
      const mined = await receipt(hash);
      fs.writeFileSync(
        path.join(receiptDirectory, `${hash}.json`),
        JSON.stringify(
          { request, gasLimit: bufferedGas, receipt: mined },
          null,
          2
        ) + "\n"
      );
      const entry = {
        label,
        hash,
        status: Number(mined.status),
        gasUsed: Number(mined.gasUsed),
        estimatedGas,
        bufferedGas,
      };
      record.transactions.push(entry);
      if (entry.status !== 1) throw new Error(`${label}: transaction reverted`);
      return { mined, entry };
    }
    const marketStores = {};
    for (const name of ["WildcatMarket", "WildcatMarketRevolving"]) {
      const original = artifact(name, name).bytecode.object;
      if (fixtures[name + "_creation"] !== original)
        throw new Error("stale compression fixture");
      const runtime = fixtures[name + "_runtime"];
      const plannedData = concat([planned, abi.encode(["bytes"], [runtime])]);
      if (!runtime.startsWith(reader))
        throw new Error("unexpected reader prefix");
      const storeSize = (runtime.length - 2) / 2;
      for (const [route, data] of [
        ["direct", storageCreation(runtime)],
        ["plan", plannedData],
      ]) {
        const { mined, entry } = await send(`${name} ${route} store`, { data });
        Object.assign(entry, {
          artifact: name,
          route,
          creationHash: keccak256(original),
          runtimeHash: keccak256(runtime),
          storedBytes: storeSize,
        });
        const code = await rpc("eth_getCode", [
          mined.contractAddress,
          "latest",
        ]);
        const decoded = await rpc("eth_call", [
          { to: mined.contractAddress, data: "0x" },
          "latest",
        ]);
        entry.storedRuntimeMatches = keccak256(code) === entry.runtimeHash;
        entry.decodedArtifactMatches =
          keccak256(decoded) === entry.creationHash;
        if (!entry.storedRuntimeMatches || !entry.decodedArtifactMatches)
          throw new Error("artifact mismatch");
        marketStores[name] = mined.contractAddress;
        console.log(JSON.stringify(entry));
      }
    }

    async function deploy(name, args = [], file = name) {
      const compiled = artifact(file, name);
      const contract = new Interface(compiled.abi);
      const { mined } = await send(`deploy ${name}`, {
        data: concat([compiled.bytecode.object, contract.encodeDeploy(args)]),
      });
      return { address: mined.contractAddress, contract };
    }
    async function call(target, name, args = []) {
      return send(name, {
        to: target.address,
        data: target.contract.encodeFunctionData(name, args),
      });
    }
    async function read(target, name, args = []) {
      const result = await rpc("eth_call", [
        {
          to: target.address,
          data: target.contract.encodeFunctionData(name, args),
        },
        "latest",
      ]);
      return target.contract.decodeFunctionResult(name, result)[0];
    }
    function equal(actual, expected, label) {
      if (String(actual).toLowerCase() !== String(expected).toLowerCase())
        throw new Error(`${label}: ${actual} != ${expected}`);
    }

    const arch = await deploy("WildcatArchController");
    const registry = await deploy("WildcatBorrowerIdentityRegistry", [
      arch.address,
    ]);
    const sanctions = await deploy("SanctionsListMock", [], "SanctionsMocks");
    const sentinel = await deploy("WildcatSanctionsSentinel", [
      arch.address,
      sanctions.address,
    ]);
    const wrapper = await deploy("Wildcat4626WrapperFactory", [
      arch.address,
      ZeroAddress,
    ]);
    const asset = await deploy(
      "MockERC20",
      ["Matrix Token", "MTRX", 18],
      "mocks/MockERC20"
    );
    await call(arch, "registerBorrower", [account]);
    const templates = [];
    for (const name of [
      "OpenTermHooks",
      "FixedTermHooks",
      "PeriodicTermHooks",
    ]) {
      const compiled = artifact(name, name);
      // These templates fit raw storage. The Forge matrix separately compresses all templates.
      const runtime = concat(["0x00", compiled.bytecode.object]);
      const { mined } = await send(`${name} raw store`, {
        data: storageCreation(runtime),
      });
      equal(
        await rpc("eth_getCode", [mined.contractAddress, "latest"]),
        runtime,
        "template storage"
      );
      templates.push({ name, compiled, store: mined.contractAddress });
    }
    record.markets = [];
    for (const [model, marketName] of [
      "WildcatMarket",
      "WildcatMarketRevolving",
    ].entries()) {
      const compiled = artifact(marketName, marketName);
      const marketHash = keccak256(compiled.bytecode.object);
      const factory = await deploy(
        model ? "HooksFactoryRevolving" : "HooksFactory",
        [
          arch.address,
          sentinel.address,
          wrapper.address,
          marketStores[marketName],
          marketHash,
          registry.address,
        ]
      );
      await call(arch, "registerControllerFactory", [factory.address]);
      await call(factory, "registerWithArchController");
      for (const [policy, template] of templates.entries()) {
        await call(factory, "addHooksTemplate", [
          template.store,
          template.name,
          ZeroAddress,
          ZeroAddress,
          0,
          0,
        ]);
        const nonce = await read(factory, "getHooksInstanceDeploymentNonce", [
          account,
        ]);
        const hookSalt = toBeHex((BigInt(account) << 96n) | nonce, 32);
        const hookHash = keccak256(
          concat([
            template.compiled.bytecode.object,
            abi.encode(["address", "bytes"], [account, "0x"]),
          ])
        );
        const hookAddress = getCreate2Address(
          factory.address,
          hookSalt,
          hookHash
        );
        const hook = {
          address: hookAddress,
          contract: new Interface(template.compiled.abi),
        };
        const hookTx = await call(factory, "deployHooksInstance", [
          template.store,
          "0x",
        ]);
        if (
          !runtimeMatches(
            template.compiled,
            await rpc("eth_getCode", [hookAddress, "latest"])
          )
        )
          throw new Error("hook runtime mismatch");
        equal(await read(hook, "administrator"), account, "hook administrator");
        const config = await read(hook, "config");
        const hooks =
          (BigInt(hookAddress) << 96n) |
          (((config & 0xffffn) | ((config >> 16n) & 0xffffn)) << 80n);
        const now = Number(
          (await rpc("eth_getBlockByNumber", ["latest", false])).timestamp
        );
        const day = 86400;
        const inputs = {
          asset: asset.address,
          namePrefix: "Wildcat ",
          symbolPrefix: "wc",
          maxTotalSupply: 10n ** 24n,
          annualInterestBips: 1000,
          delinquencyFeeBips: 1000,
          withdrawalBatchDuration: day,
          reserveRatioBips: 2000,
          delinquencyGracePeriod: day,
          hooks,
          repaymentDate: now + 90 * day,
          repaymentPeriod: 7 * day,
        };
        const hooksData =
          policy === 0
            ? abi.encode(["uint128", "bool"], [0, false])
            : policy === 1
            ? abi.encode(
                ["uint32", "uint128", "bool", "bool", "bool"],
                [now + 60 * day, 0, false, true, true]
              )
            : abi.encode(
                ["uint32", "uint32", "uint32", "uint128", "bool"],
                [now + 30 * day, 30 * day, 7 * day, 0, false]
              );
        const salt = toBeHex(
          (BigInt(account) << 96n) | BigInt(100 + policy),
          32
        );
        const expected = getCreate2Address(factory.address, salt, marketHash);
        const args = model
          ? [
              inputs,
              hooksData,
              abi.encode(["uint8", "uint16"], [1, 200]),
              salt,
              ZeroAddress,
              0,
            ]
          : [inputs, hooksData, salt, ZeroAddress, 0];
        const { entry } = await call(factory, "deployMarket", args);
        const code = await rpc("eth_getCode", [expected, "latest"]);
        if (!runtimeMatches(compiled, code))
          throw new Error("market runtime mismatch");
        const market = {
          address: expected,
          contract: new Interface(compiled.abi),
        };
        for (const [name, value] of Object.entries({
          factory: factory.address,
          borrower: account,
          asset: asset.address,
          repaymentDate: inputs.repaymentDate,
          repaymentPeriod: inputs.repaymentPeriod,
        })) {
          equal(await read(market, name), value, `market ${name}`);
        }
        const result = {
          market: marketName,
          policy: template.name,
          address: expected,
          hookAddress,
          creationHash: marketHash,
          runtimeBytes: (code.length - 2) / 2,
          runtimeMatchesExceptImmutables: true,
          checkedContextAndTerms: true,
          hookGasUsed: hookTx.entry.gasUsed,
          marketGasUsed: entry.gasUsed,
          marketBufferedGas: entry.bufferedGas,
        };
        record.markets.push(result);
        console.log(JSON.stringify(result));
      }
    }
  } catch (error) {
    record.error = error.message;
    throw error;
  } finally {
    fs.writeFileSync(
      path.join(receiptDirectory, "results.json"),
      JSON.stringify(record, null, 2) + "\n"
    );
    if (node.exitCode === null && node.signalCode === null) {
      node.kill("SIGTERM");
      await new Promise((resolve) => node.once("exit", resolve));
    }
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
