#!/usr/bin/env node
// execute and resume the actual storage plan emitted by the Solidity planner.
const fs = require("node:fs");
const path = require("node:path");
const net = require("node:net");
const { spawn, execFileSync } = require("node:child_process");
const { keccak256 } = require("ethers");
const ROOT = path.resolve(__dirname, "../..");
if (!process.argv[2])
  throw new Error("usage: split-plan-rpc.js <new-receipt-directory>");
const receiptDirectory = path.resolve(process.argv[2]);
fs.mkdirSync(receiptDirectory, { recursive: false });
const network = `split-adoption-${process.pid}`;
const working = path.join(ROOT, "deployments", network);
fs.mkdirSync(working);
const env = { ...process.env, FOUNDRY_PROFILE: "deploy" };
const result = {
  head: execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: ROOT,
    encoding: "utf8",
  }).trim(),
};
fs.writeFileSync(
  path.join(receiptDirectory, "working.patch"),
  execFileSync("git", ["diff", "HEAD"], { cwd: ROOT })
);
for (const file of [
  "foundry.toml",
  "script/common/PreparedInitCodeStorage.sol",
  "scripts/research/split-plan-rpc.js",
]) {
  fs.copyFileSync(
    path.join(ROOT, file),
    path.join(receiptDirectory, path.basename(file))
  );
}
function command(label, args, expectedFailure = false) {
  let output;
  let failed = false;
  try {
    output = execFileSync("node", ["scripts/plan.js", ...args], {
      cwd: ROOT,
      env,
      encoding: "utf8",
      maxBuffer: 4 * 1024 * 1024,
    });
  } catch (error) {
    failed = true;
    output = String(error.stdout || "") + String(error.stderr || "");
    if (!expectedFailure) throw error;
  }
  fs.writeFileSync(path.join(receiptDirectory, label + ".log"), output);
  if (failed !== expectedFailure)
    throw new Error(`${label}: unexpected exit status`);
  if (
    expectedFailure &&
    !/predicate failed|predicate-failed|code mismatch/.test(output)
  )
    throw new Error(`${label}: unrelated failure: ${output}`);
}
async function main() {
  const server = net.createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  const url = `http://127.0.0.1:${port}`;
  const node = spawn(
    "anvil",
    [
      "--host",
      "127.0.0.1",
      "--port",
      String(port),
      "--chain-id",
      "31337",
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
    const response = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
    });
    const data = await response.json();
    if (data.error) throw new Error(JSON.stringify(data.error));
    return data.result;
  }
  try {
    let ready = false;
    for (let i = 0; i < 100; i++) {
      try {
        await rpc("eth_chainId");
        ready = true;
        break;
      } catch {
        await new Promise((r) => setTimeout(r, 50));
      }
    }
    if (!ready) throw new Error("Anvil failed to start");
    fs.cpSync(
      path.join(ROOT, "deploy-out/split-storage-plan-test/plan-entries"),
      path.join(working, "plan-entries"),
      { recursive: true }
    );
    command("assemble", ["assemble", "--network", network, "--release", "e24"]);
    const planPath = path.join(working, "plan-e24.json");
    const plan = JSON.parse(fs.readFileSync(planPath));
    if (
      plan.transactions.length !== 2 ||
      plan.transactions[1].predicate.type !== "splitCodeHash"
    )
      throw new Error("unexpected storage plan");
    fs.copyFileSync(planPath, path.join(receiptDirectory, "plan.json"));
    const executor = plan.expectedExecutor;
    await rpc("anvil_setBalance", [executor, "0x3635c9adc5dea00000"]);
    const statePath = path.join(receiptDirectory, "run-state.json");
    const partial = path.join(receiptDirectory, "secondary-only-plan.json");
    fs.writeFileSync(
      partial,
      JSON.stringify(
        { ...plan, transactions: plan.transactions.slice(0, 1) },
        null,
        2
      )
    );
    const execute = (p) => [
      "execute",
      "--plan",
      p,
      "--rpc",
      url,
      "--impersonate",
      executor,
      "--run-state",
      statePath,
      "--yes",
    ];
    command("install-secondary", execute(partial));
    const secondaryState = JSON.parse(fs.readFileSync(statePath));
    fs.copyFileSync(
      statePath,
      path.join(receiptDirectory, "secondary-only-state.json")
    );
    const secondary = secondaryState[plan.transactions[0].id].resolvedAddress;
    if (!secondary) throw new Error("missing secondary deployment address");
    const secondaryCode = await rpc("eth_getCode", [secondary, "latest"]);
    const nonceAfterSecondary = await rpc("eth_getTransactionCount", [
      executor,
      "latest",
    ]);
    await rpc("anvil_setCode", [secondary, "0x00"]);
    command("reject-corrupted-secondary-on-resume", execute(planPath), true);
    if (
      nonceAfterSecondary !==
      (await rpc("eth_getTransactionCount", [executor, "latest"]))
    )
      throw new Error("failed resume sent a transaction");
    await rpc("anvil_setCode", [secondary, secondaryCode]);
    command("resume-primary", execute(planPath));
    const completed = JSON.parse(fs.readFileSync(statePath));
    const primary = completed[plan.transactions[1].id].resolvedAddress;
    const primaryCode = await rpc("eth_getCode", [primary, "latest"]);
    const original = await rpc("eth_call", [
      { to: primary, data: "0x" },
      "latest",
    ]);
    if (
      keccak256(original) !==
      plan.transactions[1].predicate.initCodeHash.toLowerCase()
    )
      throw new Error("wrong recovered creation code");
    const completedNonce = await rpc("eth_getTransactionCount", [
      executor,
      "latest",
    ]);
    command("resume-complete-no-transactions", execute(planPath));
    command("verify-complete", [
      "verify",
      "--plan",
      planPath,
      "--run-state",
      statePath,
      "--rpc",
      url,
    ]);
    await rpc("anvil_setCode", [
      primary,
      primaryCode.slice(0, -48) + "00".repeat(20) + primaryCode.slice(-8),
    ]);
    command("reject-corrupted-link-on-resume", execute(planPath), true);
    if (
      completedNonce !==
      (await rpc("eth_getTransactionCount", [executor, "latest"]))
    )
      throw new Error("completed resume changed nonce");
    await rpc("anvil_setCode", [primary, primaryCode]);
    result.transactions = [];
    for (const [transactionId, state] of Object.entries(completed)) {
      const receipt = await rpc("eth_getTransactionReceipt", [state.txHash]);
      if (receipt.status !== "0x1")
        throw new Error("failed installation receipt");
      fs.writeFileSync(
        path.join(receiptDirectory, transactionId + ".json"),
        JSON.stringify(receipt, null, 2)
      );
      result.transactions.push({
        id: transactionId,
        gasUsed: Number(receipt.gasUsed),
        address: receipt.contractAddress,
      });
    }
    result.installationGas = result.transactions.reduce(
      (sum, tx) => sum + tx.gasUsed,
      0
    );
    result.primaryBytes = (primaryCode.length - 2) / 2;
    result.secondaryBytes = (secondaryCode.length - 2) / 2;
    result.reconstructedHash = keccak256(original);
    result.partialResumePassed = true;
    result.completedResumeSentNoTransactions = true;
    result.corruptedSecondaryAndLinkRejectedBeforeSending = true;
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    result.error = error.message;
    throw error;
  } finally {
    fs.writeFileSync(
      path.join(receiptDirectory, "results.json"),
      JSON.stringify(result, null, 2) + "\n"
    );
    if (node.exitCode === null && node.signalCode === null) {
      node.kill("SIGTERM");
      await new Promise((resolve) => node.once("exit", resolve));
    }
    // this directory was created exclusively by this run; the full plan is archived above.
    fs.rmSync(working, { recursive: true });
  }
}
main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
