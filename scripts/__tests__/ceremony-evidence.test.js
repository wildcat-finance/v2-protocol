const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { execFileSync, spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "../..");
const script = "scripts/archive-ceremony-evidence.py";
const stagePath = "script/deploy/v2-5/sepolia-fix-1-stage.sh";
const stage = fs.readFileSync(path.join(root, stagePath), "utf8");
const configPath = "deployments/sepolia/v2.5.6.json";
const session = "deployments/sepolia/ceremony-evidence/v2.5.6.T8rqiv";
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");

function readArchive(filename) {
  const files = JSON.parse(execFileSync("python3", ["-c", `
import base64, json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None
    print(json.dumps({name: base64.b64encode(archive.read(name)).decode() for name in archive.namelist()}))
`, filename], { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 }));
  return Object.fromEntries(Object.entries(files).map(([name, bytes]) => [name, Buffer.from(bytes, "base64")]));
}

// Original, receipt-backed operator evidence supplies both inputs and byte-for-byte expectations.
const original = readArchive(path.join(root,
  "deployments/sepolia/ceremony-evidence/wildcat-v2.5.6-evidence-20261004T081346Z.zip"));

function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "ceremony-evidence-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const write = (name, bytes) => {
    const filename = path.join(directory, name);
    fs.mkdirSync(path.dirname(filename), { recursive: true });
    fs.writeFileSync(filename, bytes);
  };
  for (const [name, bytes] of Object.entries(original)) {
    assert.ok(!path.isAbsolute(name) && !name.split("/").includes(".."));
    write(name, bytes);
  }
  for (const name of [script, stagePath]) write(name, fs.readFileSync(path.join(root, name)));
  write("deployments/sepolia/ceremony-evidence/v2.5.6-active-session", `${session}\n`);
  write(".env", "DO_NOT_ARCHIVE\n");
  write(`${session}/operator-private-note.txt`, "DO_NOT_ARCHIVE\n");
  const modify = (name, update) => {
    const value = JSON.parse(fs.readFileSync(path.join(directory, name)));
    update(value);
    write(name, JSON.stringify(value, null, 2) + "\n");
  };
  const run = () => spawnSync("python3", [script, "--config", configPath, "--session", session], {
    cwd: directory, encoding: "utf8",
  });
  const archives = () => fs.readdirSync(path.join(directory, "deployments/sepolia/ceremony-evidence"))
    .filter((name) => name.endsWith(".zip"));
  return { directory, write, modify, run, archives };
}

test("archive preserves the live evidence bytes, original source and portable checksum", (t) => {
  const f = fixture(t);
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  const filename = path.join(f.directory, "deployments/sepolia/ceremony-evidence", f.archives()[0]);
  const archived = readArchive(filename);
  assert.deepEqual(Object.keys(archived).sort(), [...Object.keys(original), "manifest.json"].sort());
  for (const [name, bytes] of Object.entries(original)) assert.deepEqual(archived[name], bytes, name);
  const manifest = JSON.parse(archived["manifest.json"]);
  assert.equal(manifest.sourceCommit, "26c5209dec2421884d30fdeab4217744abe0c846");
  assert.equal(manifest.files.length, 17);
  assert.ok(!archived["manifest.json"].toString().includes(f.directory));
  for (const entry of manifest.files) {
    assert.equal(entry.sha256, hash(original[entry.path]));
    assert.equal(entry.bytes, original[entry.path].length);
  }
  const bytes = fs.readFileSync(filename);
  assert.equal(fs.readFileSync(`${filename}.sha256`, "utf8"), `${hash(bytes)}  ${path.basename(filename)}\n`);
  assert.equal(f.run().status, 0, "archiving can be repeated without replaying finalization");
  assert.equal(f.archives().length, 2);
  assert.deepEqual(fs.readFileSync(filename), bytes, "existing ZIP is never overwritten");
});

for (const [label, alter, message] of [
  ["missing final handoff", (f) => fs.unlinkSync(path.join(f.directory, "deployments/sepolia/template-update-v2.5.6.json")), /Missing evidence/],
  ["changed plan", (f) => f.modify("deployments/sepolia/plan-v2.5.6.json", (value) => value.transactions.reverse()), /Plan or locked package differs/],
  ["different run-state copy", (f) => f.write("deployments/sepolia/run-state-v2.5.6.json", "{}\n"), /Stable run-state differs/],
  ["incomplete transactions", (f) => {
    for (const name of [`${session}/run-state.json`, "deployments/sepolia/run-state-v2.5.6.json"]) {
      f.modify(name, (value) => Object.values(value)[0].status = "submitted");
    }
  }, /Run-state is not complete/],
  ["wrong cold gate", (f) => f.modify("deployments/anvil/v2.5.6-cold-gate.json", (value) => value.sourceCommit = "another-commit"), /Cold gate differs/],
  ["failed reconciliation", (f) => f.modify("deployments/sepolia/reconcile-report.json", (value) => value.status = "red"), /reconciliation is not green/],
  ["changed baseline handoff", (f) => f.modify("deployments/sepolia/handoff-v2.5.5.json", (value) => value.release = "wrong"), /Base handoff differs/],
  ["unfinalized aliases", (f) => f.modify("deployments/sepolia/deployments.json", (value) => delete value.OpenTermHooks_initCodeStorage), /deployment records differ/],
]) {
  test(`archive refuses ${label} without writing a ZIP`, (t) => {
    const f = fixture(t);
    alter(f);
    const result = f.run();
    assert.equal(result.status, 1);
    assert.match(result.stderr, message);
    assert.deepEqual(f.archives(), []);
  });
}

test("archive-only stage works offline without Git, a source gate or a session pointer", (t) => {
  const f = fixture(t);
  fs.unlinkSync(path.join(f.directory, "deployments/sepolia/ceremony-evidence/v2.5.6-active-session"));
  const result = spawnSync("bash", [stagePath, "archive-evidence"], {
    cwd: f.directory, encoding: "utf8",
    env: { ...process.env, SEPOLIA_REPLACEMENT_CONFIG: configPath, DEPLOYMENTS_NETWORK: "sepolia",
      CEREMONY_EVIDENCE_DIR: session, RPC_URL: "http://127.0.0.1:1" },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.archives().length, 1);
});

function stageFunction(name) {
  const source = stage.match(new RegExp(`^${name}\\(\\) \\{[\\s\\S]*?^\\}`, "m"))?.[0];
  assert.ok(source, `${name} must exist`);
  return source;
}

for (const mode of ["templates", "factories", "failed-reconcile"]) {
  test(`finalization archives only after successful reconciliation: ${mode}`, (t) => {
    const f = fixture(t);
    if (mode === "factories") {
      f.modify(configPath, (value) => value.activationScope = "factories");
      const handoff = JSON.parse(original["deployments/sepolia/handoff-v2.5.5.json"]);
      handoff.release = "v2.5.6";
      f.write("deployments/sepolia/handoff-v2.5.6.json", JSON.stringify(handoff));
    }
    fs.mkdirSync(path.join(f.directory, "deployments/sepolia/inventory-pending-v2.5.6"));
    const source = `set -euo pipefail
CONFIG=deployments/sepolia/v2.5.6.json
RELEASE=v2.5.6
DEPLOYMENTS_NETWORK=sepolia
LIVE_PLAN=deployments/sepolia/plan-v2.5.6.json
LIVE_PACKAGE=deployments/sepolia/ceremony-v2.5.6-eoa.json
PENDING_INVENTORY=deployments/sepolia/inventory-pending-v2.5.6
ROTATION_SCRIPT=scripts/sepolia-v2-5-fix-rotation.js
RPC_URL=http://127.0.0.1:1
assert_clean_pushed_source() { :; }
assert_rpc() { :; }
current_session() { printf '%s\\n' '${session}'; }
node() {
  if [[ "$1" == scripts/factory-inventory.js && "$2" == reconcile ]]; then
    if [[ "$TEST_MODE" == failed-reconcile ]]; then return 1; fi
    printf 'RECONCILE_COMPLETE\\n'
  fi
}
${["sha256_file", "assert_archive_tool", "archive_evidence", "finalize_inventory"].map(stageFunction).join("\n")}
finalize_inventory
`;
    const env = { ...process.env, TEST_MODE: mode };
    delete env.CEREMONY_EVIDENCE_DIR;
    const result = spawnSync("bash", ["-c", source], { cwd: f.directory, encoding: "utf8", env });
    if (mode === "failed-reconcile") {
      assert.equal(result.status, 1);
      assert.deepEqual(f.archives(), []);
    } else {
      assert.equal(result.status, 0, result.stderr);
      assert.equal(f.archives().length, 1);
      assert.ok(result.stdout.indexOf("Ceremony evidence ZIP:") > result.stdout.indexOf("RECONCILE_COMPLETE"));
    }
  });
}

test("ceremony archives and checksums are trackable while loose evidence stays ignored", () => {
  for (const network of ["sepolia", "mainnet"]) {
    for (const [filename, ignored] of [
      ["new-evidence.zip", false],
      ["new-evidence.zip.sha256", false],
      ["new-evidence.sha256", false],
      ["new-session/run-state.json", true],
      ["new-session/preflight.json", true],
      ["new-session/ui-started", true],
      ["v2.5.6-active-session", true],
      ["preparation.log", true],
    ]) {
      const evidencePath = `deployments/${network}/ceremony-evidence/${filename}`;
      assert.equal(spawnSync("git", ["check-ignore", "--no-index", evidencePath], { cwd: root }).status,
        ignored ? 0 : 1, evidencePath);
    }
  }
});

test("factory evidence ZIP carries original reuse sources and rejects altered receipts", (t) => {
  const f = fixture(t);
  const rotation = require("../../deployments/sepolia/v2.5.7.json");
  const reused = require("../reused-deployments").loadReusedDeployments(rotation);
  f.modify(configPath, (config) => {
    config.activationScope = "factories";
    config.inventoryBaselineCommit = rotation.inventoryBaselineCommit;
    config.reusedDeployments = rotation.reusedDeployments;
  });
  const handoff = { release: "v2.5.6", chain: { network: "sepolia", chainId: 11155111 },
    releaseContracts: Array.from(reused.values(), (record) => ({ reused: true,
      address: record.address, startBlock: record.startBlock, deployTxHash: record.txHash,
      provenance: record.provenance })) };
  for (const record of reused.values()) {
    for (const source of [record.provenance.handoff, record.provenance.plan]) {
      f.write(source, fs.readFileSync(path.join(root, source)));
    }
  }
  const finalPath = "deployments/sepolia/handoff-v2.5.6.json";
  f.write(finalPath, JSON.stringify(handoff));
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  const archive = readArchive(path.join(f.directory, "deployments/sepolia/ceremony-evidence", f.archives()[0]));
  for (const record of reused.values()) {
    for (const source of [record.provenance.handoff, record.provenance.plan]) {
      assert.deepEqual(archive[source], fs.readFileSync(path.join(root, source)));
    }
  }
  for (const index of [0, 1, 2, 3]) {
    f.write(finalPath, JSON.stringify(handoff));
    f.modify(finalPath, (value) => { value.releaseContracts[index].startBlock += 1; });
    const failure = f.run();
    assert.equal(failure.status, 1);
    assert.match(failure.stderr, /receipt differs from its original handoff/);
  }
  assert.equal(f.archives().length, 1);
});
