#!/usr/bin/env node
// Prepared images, real transactions, identical market artifacts and factory interfaces.
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
  throw new Error("usage: storage-comparison-rpc.js <new-receipt-directory>");
const directory = path.resolve(process.argv[2]);
fs.mkdirSync(directory, { recursive: false });
for (const file of [
  "foundry.toml",
  "src/libraries/LibSplitInitCode.sol",
  "test/libraries/SplitInitCode.t.sol",
  "test/research/SplitStorageDeployment.t.sol",
  "scripts/research/storage-comparison-rpc.js",
]) {
  fs.copyFileSync(
    path.join(ROOT, file),
    path.join(directory, path.basename(file))
  );
}
const record = {
  head: execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: ROOT,
    encoding: "utf8",
  }).trim(),
  anvil: execFileSync("anvil", ["--version"], { encoding: "utf8" }).trim(),
  hardfork: "osaka",
  transactionGasCap: CAP,
  transactions: [],
  stores: {},
  variants: {},
};
const fixtures = JSON.parse(
  fs.readFileSync(path.join(ROOT, "deploy-out/split-comparison.json"))
);
fs.copyFileSync(
  path.join(ROOT, "deploy-out/split-comparison.json"),
  path.join(directory, "prepared-images.json")
);
const cache = JSON.parse(
  fs.readFileSync(path.join(ROOT, "deploy-cache/solidity-files-cache.json"))
);
const artifacts = new Map();

function artifact(source, name) {
  if (artifacts.has(name)) return artifacts.get(name);
  const versions = cache.files[source]?.artifacts[name];
  const paths = new Set(
    Object.values(versions || {}).flatMap((profiles) =>
      Object.values(profiles).map((entry) => entry.path)
    )
  );
  if (paths.size !== 1) throw new Error(`ambiguous artifact ${source}:${name}`);
  const file = path.join(ROOT, "deploy-out", [...paths][0]);
  const data = JSON.parse(fs.readFileSync(file));
  if (data.metadata.settings.compilationTarget[source] !== name)
    throw new Error("artifact source mismatch");
  fs.copyFileSync(file, path.join(directory, name + ".json"));
  artifacts.set(name, data);
  return data;
}

function equal(actual, expected, label) {
  if (String(actual).toLowerCase() !== String(expected).toLowerCase())
    throw new Error(`${label}: ${actual} != ${expected}`);
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
      "--timestamp",
      "1800000000",
      "--quiet",
    ],
    { stdio: "ignore" }
  );
  let id = 0;
  let clock = 1800000000;
  let account;
  async function rpc(method, params = []) {
    const response = await fetch(`http://127.0.0.1:${port}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
    });
    const data = await response.json();
    if (data.error) throw new Error(JSON.stringify(data.error));
    return data.result;
  }
  async function send(label, transaction) {
    await rpc("evm_setNextBlockTimestamp", [++clock]);
    const request = { from: account, ...transaction };
    const estimate = Number(
      await rpc("eth_estimateGas", [{ ...request, gas: toBeHex(CAP) }])
    );
    const limit = Math.ceil(estimate * 1.3);
    if (limit > CAP)
      throw new Error(`${label}: buffered gas exceeds transaction cap`);
    const hash = await rpc("eth_sendTransaction", [
      { ...request, gas: toBeHex(limit) },
    ]);
    let receipt;
    for (let attempt = 0; attempt < 200; ++attempt) {
      receipt = await rpc("eth_getTransactionReceipt", [hash]);
      if (receipt) break;
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    if (!receipt || Number(receipt.status) !== 1)
      throw new Error(`${label}: failed transaction`);
    const entry = {
      label,
      gasUsed: Number(receipt.gasUsed),
      estimatedGas: estimate,
      bufferedGas: limit,
      hash,
    };
    record.transactions.push(entry);
    fs.writeFileSync(
      path.join(
        directory,
        `${String(record.transactions.length).padStart(3, "0")}.json`
      ),
      JSON.stringify({ request, receipt }, null, 2) + "\n"
    );
    return { entry, receipt };
  }
  async function deploy(source, name, args = [], label = name) {
    const data = artifact(source, name);
    const contract = new Interface(data.abi);
    const tx = await send(`deploy ${label}`, {
      data: concat([data.bytecode.object, contract.encodeDeploy(args)]),
    });
    return {
      address: tx.receipt.contractAddress,
      contract,
      gasUsed: tx.entry.gasUsed,
    };
  }
  async function call(target, name, args = [], label = name) {
    return send(label, {
      to: target.address,
      data: target.contract.encodeFunctionData(name, args),
    });
  }
  async function read(target, name, args = []) {
    const data = await rpc("eth_call", [
      {
        to: target.address,
        data: target.contract.encodeFunctionData(name, args),
      },
      "latest",
    ]);
    return target.contract.decodeFunctionResult(name, data)[0];
  }
  async function code(address) {
    return rpc("eth_getCode", [address, "latest"]);
  }
  async function image(label, runtime) {
    if ((runtime.length - 2) / 2 > 24576)
      throw new Error(`${label}: oversized image`);
    // This existing artifact is a generic prepared-runtime constructor despite its name.
    const deployed = await deploy(
      "script/common/DeployScriptBase.sol",
      "CompressedInitCodeStorage",
      [runtime],
      label
    );
    equal(
      await code(deployed.address),
      runtime,
      `${label}: runtime attestation`
    );
    return deployed;
  }
  try {
    for (let attempt = 0; attempt < 100; ++attempt) {
      try {
        [account] = await rpc("eth_accounts");
        break;
      } catch {
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
    }
    if (!account) throw new Error("local node did not start");
    let overCapRejected = false;
    try {
      await rpc("eth_sendTransaction", [
        { from: account, to: account, gas: toBeHex(CAP + 1) },
      ]);
    } catch (error) {
      overCapRejected = /gas.*(cap|limit)|limit.*gas/i.test(error.message);
    }
    if (!overCapRejected) throw new Error("transaction cap not enforced");
    record.overCapRejected = true;
    // Code consisting only of STOP is valid; rejection must be the runtime-size cap.
    let oversizedRejected = false;
    try {
      await rpc("eth_estimateGas", [
        {
          from: account,
          data: "0x6160015f81600a5f39f3" + "00".repeat(24577),
          gas: toBeHex(CAP),
        },
      ]);
    } catch (error) {
      oversizedRejected = /size|limit|CreateContractSizeLimit/i.test(
        error.message
      );
    }
    if (!oversizedRejected) throw new Error("runtime-size cap not enforced");
    record.oversizedRuntimeRejected = true;

    const sources = {
      WildcatMarket: "src/market/WildcatMarket.sol",
      WildcatMarketRevolving: "src/market/WildcatMarketRevolving.sol",
      PeriodicTransferHooks: "test/mocks/TransferFeatureHooks.sol",
      PeriodicBorrowHooks: "test/mocks/BorrowFeatureHooks.sol",
      PeriodicAprReplacementHooks: "test/mocks/AprReplacementHooks.sol",
    };
    const reader = artifact(
      "src/libraries/LibSplitInitCode.sol",
      "SplitInitCodeReader"
    ).deployedBytecode.object;
    const probe = await deploy(
      "test/research/SplitStorageDeployment.t.sol",
      "StoredInitCodeReadProbe"
    );
    for (const [name, source] of Object.entries(sources)) {
      const compiled = artifact(source, name);
      const original = compiled.bytecode.object;
      equal(original, fixtures[name + "_creation"], "fresh prepared artifact");
      const compressedRuntime = fixtures[name + "_compressed"];
      const compressed = await image(`${name} compressed`, compressedRuntime);
      const secondaryRuntime = fixtures[name + "_secondary"];
      const secondary = await image(
        `${name} split secondary`,
        secondaryRuntime
      );
      const blank = fixtures[name + "_primaryZeroAddress"];
      if (!blank.startsWith(reader))
        throw new Error("split reader prefix mismatch");
      equal("0x" + blank.slice(-48, -8), ZeroAddress, "unbound primary footer");
      const primaryRuntime =
        blank.slice(0, -48) +
        secondary.address.slice(2).toLowerCase() +
        blank.slice(-8);
      const primary = await image(`${name} split primary`, primaryRuntime);
      const formats = {
        compressed: {
          primary: compressed.address,
          installationGas: compressed.gasUsed,
          contracts: 1,
          storedBytes: (compressedRuntime.length - 2) / 2,
        },
        split: {
          primary: primary.address,
          secondary: secondary.address,
          installationGas: primary.gasUsed + secondary.gasUsed,
          contracts: 2,
          storedBytes:
            (primaryRuntime.length + secondaryRuntime.length - 4) / 2,
        },
      };
      if ((original.length - 2) / 2 <= 24575) {
        const raw = await image(
          `${name} raw control`,
          concat(["0x00", original])
        );
        formats.raw = {
          primary: raw.address,
          installationGas: raw.gasUsed,
          contracts: 1,
          storedBytes: (original.length - 2) / 2 + 1,
        };
      }
      for (const [format, store] of Object.entries(formats)) {
        equal(
          await read(probe, "readHash", [store.primary]),
          keccak256(original),
          `${name} ${format} exact creation bytes`
        );
        store.readAndHashGas = (
          await call(
            probe,
            "readHash",
            [store.primary],
            `${name} ${format} read and hash`
          )
        ).entry.gasUsed;
      }
      record.stores[name] = {
        creationBytes: (original.length - 2) / 2,
        creationHash: keccak256(original),
        ...formats,
      };
    }

    const arch = await deploy(
      "src/WildcatArchController.sol",
      "WildcatArchController"
    );
    const registry = await deploy(
      "src/WildcatBorrowerIdentityRegistry.sol",
      "WildcatBorrowerIdentityRegistry",
      [arch.address]
    );
    const sanctions = await deploy(
      "test/mocks/SanctionsMocks.sol",
      "SanctionsListMock"
    );
    const sentinel = await deploy(
      "src/WildcatSanctionsSentinel.sol",
      "WildcatSanctionsSentinel",
      [arch.address, sanctions.address]
    );
    const wrapper = await deploy(
      "src/vault/Wildcat4626WrapperFactory.sol",
      "Wildcat4626WrapperFactory",
      [arch.address, ZeroAddress]
    );
    const asset = await deploy(
      "lib/solmate/src/test/utils/mocks/MockERC20.sol",
      "MockERC20",
      ["Comparison Token", "CMP", 18]
    );
    await call(arch, "registerBorrower", [account]);
    const templates = [];
    for (const name of [
      "OpenTermHooks",
      "FixedTermHooks",
      "PeriodicTermHooks",
    ]) {
      const compiled = artifact(`src/access/${name}.sol`, name);
      const store = await image(
        `${name} common raw template`,
        concat(["0x00", compiled.bytecode.object])
      );
      templates.push({ name, compiled, store: store.address });
    }
    const baseClock = clock;
    const snapshot = await rpc("evm_snapshot");
    for (const mode of ["compressed", "split"]) {
      if (mode === "split") {
        equal(
          await rpc("evm_revert", [snapshot]),
          true,
          "restore comparison state"
        );
        clock = baseClock;
      }
      const observations = { factories: [], markets: [], composedHooks: [] };
      for (const [model, marketName] of [
        "WildcatMarket",
        "WildcatMarketRevolving",
      ].entries()) {
        const factoryName = model ? "HooksFactoryRevolving" : "HooksFactory";
        const compiled = artifacts.get(marketName);
        const hash = keccak256(compiled.bytecode.object);
        const factory = await deploy(
          `src/${factoryName}.sol`,
          factoryName,
          [
            arch.address,
            sentinel.address,
            wrapper.address,
            record.stores[marketName][mode].primary,
            hash,
            registry.address,
          ],
          `${mode} ${factoryName}`
        );
        observations.factories.push({
          name: factoryName,
          address: factory.address,
          gasUsed: factory.gasUsed,
        });
        await call(arch, "registerControllerFactory", [factory.address]);
        await call(factory, "registerWithArchController");
        async function deployHook(template, label) {
          await call(
            factory,
            "addHooksTemplate",
            [
              template.store,
              template.name,
              ZeroAddress,
              ZeroAddress,
              0,
              0,
              keccak256(template.compiled.bytecode.object),
            ],
            `${mode} register ${label}`
          );
          const nonce = await read(factory, "getHooksInstanceDeploymentNonce", [
            account,
          ]);
          const salt = toBeHex((BigInt(account) << 96n) | nonce, 32);
          const initHash = keccak256(
            concat([
              template.compiled.bytecode.object,
              abi.encode(["address", "bytes"], [account, "0x"]),
            ])
          );
          const address = getCreate2Address(factory.address, salt, initHash);
          const tx = await call(
            factory,
            "deployHooksInstance",
            [template.store, "0x"],
            `${mode} deploy ${label}`
          );
          const hook = {
            address,
            contract: new Interface(template.compiled.abi),
          };
          equal(await read(hook, "administrator"), account, "administrator");
          return {
            ...hook,
            gasUsed: tx.entry.gasUsed,
            runtimeHash: keccak256(await code(address)),
          };
        }
        for (const [policy, template] of templates.entries()) {
          const hook = await deployHook(template, template.name);
          const config = await read(hook, "config");
          const hooks =
            (BigInt(hook.address) << 96n) |
            (((config & 0xffffn) | ((config >> 16n) & 0xffffn)) << 80n);
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
            repaymentDate: baseClock + 90 * day,
            repaymentPeriod: 7 * day,
          };
          const hooksData =
            policy === 0
              ? abi.encode(["uint128", "bool"], [0, false])
              : policy === 1
              ? abi.encode(
                  ["uint32", "uint128", "bool", "bool", "bool"],
                  [baseClock + 60 * day, 0, false, true, true]
                )
              : abi.encode(
                  ["uint32", "uint32", "uint32", "uint128", "bool"],
                  [baseClock + 30 * day, 30 * day, 7 * day, 0, false]
                );
          const salt = toBeHex(
            (BigInt(account) << 96n) | BigInt(100 + policy),
            32
          );
          const expected = getCreate2Address(factory.address, salt, hash);
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
          const tx = await call(
            factory,
            "deployMarket",
            args,
            `${mode} ${marketName} ${template.name}`
          );
          const runtime = await code(expected);
          if ((runtime.length - 2) / 2 > 24576)
            throw new Error("market runtime exceeds limit");
          const market = {
            address: expected,
            contract: new Interface(compiled.abi),
          };
          equal(
            await read(market, "factory"),
            factory.address,
            "factory context"
          );
          equal(await read(market, "borrower"), account, "borrower context");
          equal(
            await read(market, "repaymentDate"),
            inputs.repaymentDate,
            "repayment terms"
          );
          const logs = tx.receipt.logs.map(({ address, topics, data }) => ({
            address,
            topics,
            data,
          }));
          observations.markets.push({
            name: marketName,
            policy: template.name,
            address: expected,
            gasUsed: tx.entry.gasUsed,
            runtimeHash: keccak256(runtime),
            state: Array.from(await read(market, "previousState"), (x) =>
              String(x)
            ),
            logsHash: keccak256(Buffer.from(JSON.stringify(logs))),
          });
        }
        for (const name of [
          "PeriodicTransferHooks",
          "PeriodicBorrowHooks",
          "PeriodicAprReplacementHooks",
        ]) {
          const hook = await deployHook(
            {
              name,
              compiled: artifacts.get(name),
              store: record.stores[name][mode].primary,
            },
            name
          );
          observations.composedHooks.push({
            factory: factoryName,
            name,
            address: hook.address,
            gasUsed: hook.gasUsed,
            runtimeHash: hook.runtimeHash,
          });
        }
      }
      record.variants[mode] = observations;
    }
    for (const kind of ["markets", "composedHooks"]) {
      record.variants.compressed[kind].forEach((a, i) => {
        const b = record.variants.split[kind][i];
        for (const field of kind === "markets"
          ? ["address", "runtimeHash", "logsHash"]
          : ["address", "runtimeHash"])
          equal(a[field], b[field], `${kind} ${i} ${field}`);
        if (kind === "markets")
          equal(
            JSON.stringify(a.state),
            JSON.stringify(b.state),
            "initial market state"
          );
      });
    }
    record.exactMarketDeploymentParity = true;
    record.exactComposedHookDeploymentParity = true;
    console.log(
      JSON.stringify(
        {
          transactions: record.transactions.length,
          stores: record.stores,
          variants: record.variants,
        },
        null,
        2
      )
    );
  } catch (error) {
    record.error = error.message;
    throw error;
  } finally {
    fs.writeFileSync(
      path.join(directory, "results.json"),
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
