const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync, spawnSync } = require("node:child_process");
const { changedSourceFiles, loadArtifacts } = require("../sepolia-v2-5-fix-rotation");

const stage = fs.readFileSync(
  path.resolve(__dirname, "../../script/deploy/v2-5/sepolia-fix-1-stage.sh"),
  "utf8"
);
const checks = ["sha256_file", "signing_inputs_digest", "recorded_inputs_digest", "assert_recorded_inputs",
  "assert_cold_gate", "assert_rehearsal_accepted"].map((name) => {
  const source = stage.match(new RegExp(`^${name}\\(\\) \\{[\\s\\S]*?^\\}`, "m"));
  assert.ok(source, `${name} must exist in the stage script`);
  return source[0];
}).join("\n");

function git(directory, ...args) {
  return execFileSync(
    "git",
    [
      "-c",
      "user.name=Ceremony Test",
      "-c",
      "user.email=ceremony-test@example.invalid",
      "-c",
      "commit.gpgsign=false",
      "-c",
      `core.hooksPath=${os.devNull}`,
      ...args,
    ],
    {
      cwd: directory,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        GIT_CONFIG_GLOBAL: os.devNull,
        GIT_CONFIG_NOSYSTEM: "1",
      },
    }
  ).trim();
}

function writeFile(directory, filename, contents = "local file\n") {
  const target = path.join(directory, filename);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, contents);
}

const configFile = "deployments/sepolia/release.json";
const planFile = "deployments/sepolia/plan-release.json";
const packageFile = "deployments/sepolia/ceremony-release-eoa.json";
const coldGate = "deployments/anvil/cold-gate.json";
const acceptance = "deployments/anvil/accepted.json";

function repository(context) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "ceremony-source-"));
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  git(directory, "init", "--quiet", "--initial-branch=ceremony");
  for (const file of [configFile, planFile, "deploy-ui/src/main.ts", "README.md"]) {
    writeFile(directory, file);
  }
  writeFile(directory, "package.json", '{"version":"2.5.9"}\n');
  writeFile(directory, packageFile, JSON.stringify({ digest: "package-digest" }));
  writeFile(directory, "scripts/ceremony-input-digest.js",
    fs.readFileSync(path.join(__dirname, "../ceremony-input-digest.js")));
  writeFile(directory, ".gitignore", "deploy-ui/dist/\ndeployments/anvil/\n");
  git(directory, "add", "--", ".");
  git(directory, "commit", "--quiet", "-m", "Reviewed signing inputs");
  return directory;
}

function run(directory, command) {
  return spawnSync(
    "bash",
    ["-c", `set -euo pipefail\n${checks}\n${command}`],
    { cwd: directory, encoding: "utf8", env: { ...process.env, CONFIG: configFile, LIVE_PLAN: planFile,
      LIVE_PACKAGE: packageFile, COLD_GATE: coldGate, REHEARSAL_ACCEPTANCE: acceptance } }
  );
}

function checked(directory, command) {
  const result = run(directory, command);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

test("checking a local packet needs neither a clean checkout nor an upstream", (context) => {
  const directory = repository(context);
  writeFile(directory, configFile, "candidate config\n");
  git(directory, "add", configFile);
  writeFile(directory, "deploy-ui/src/new.ts");
  writeFile(directory, coldGate, JSON.stringify({ status: "green", inputsSha256: checked(directory, "signing_inputs_digest") }));
  writeFile(directory, "README.md", "updated notes\n");
  writeFile(directory, "scripts/local-fix.js");
  git(directory, "add", "scripts/local-fix.js");
  writeFile(directory, "deployments/sepolia/other-release.json");
  writeFile(directory, "deploy-ui/dist/index.html");
  const unused = path.join(directory, "lib/old-dependency");
  fs.mkdirSync(unused, { recursive: true });
  git(unused, "init", "--quiet");
  writeFile(unused, "Library.sol");
  checked(directory, "assert_cold_gate");
  git(directory, "add", "deploy-ui/src/new.ts");
  git(directory, "commit", "--quiet", "-m", "Commit the same signing inputs");
  checked(directory, "assert_cold_gate");
});

test("artifact checks skip unused sources and enforce deployed sources and dependencies", () => {
  const rotation = { schemaVersion: "1.1.0" };
  assert.doesNotThrow(() => loadArtifacts(rotation, ["lib/old-dependency", "src/Unused.sol"]));
  assert.throws(() => loadArtifacts(rotation, ["src/IHooksFactory.sol"]), /src\/IHooksFactory\.sol/);
  assert.throws(() => loadArtifacts(rotation, ["lib/solady"]), /Deployment source differs.*lib\/solady\//);
});

test("dirty submodules report just their changed files", (context) => {
  const directory = repository(context);
  const library = path.join(directory, "lib/active");
  fs.mkdirSync(library, { recursive: true });
  git(library, "init", "--quiet");
  writeFile(library, "Source.sol");
  writeFile(library, "README.md");
  git(library, "add", ".");
  git(library, "commit", "--quiet", "-m", "Pin dependency");
  git(directory, "add", "lib/active");
  git(directory, "commit", "--quiet", "-m", "Use dependency");
  const pinned = git(directory, "rev-parse", "HEAD");
  writeFile(library, "README.md", "edited dependency notes\n");
  writeFile(library, "Extra.sol");
  assert.deepEqual(changedSourceFiles(directory, pinned, ["lib"]).sort(),
    ["lib/active/Extra.sol", "lib/active/README.md"]);
  writeFile(library, "Source.sol", "edited code\n");
  assert.ok(changedSourceFiles(directory, pinned, ["lib"]).includes("lib/active/Source.sol"));
});

test("a change to an input after check or rehearsal invalidates the recorded evidence", (context) => {
  const directory = repository(context);
  const evidence = { status: "green", inputsSha256: checked(directory, "signing_inputs_digest"),
    livePlanSha256: checked(directory, 'sha256_file "$LIVE_PLAN"'), livePackageDigest: "package-digest" };
  for (const record of [coldGate, acceptance]) writeFile(directory, record, JSON.stringify(evidence));
  checked(directory, "assert_rehearsal_accepted");
  for (const file of [configFile, planFile, "package.json", "deploy-ui/src/main.ts", "deploy-ui/src/new.ts"]) {
    const fullPath = path.join(directory, file);
    const previous = fs.existsSync(fullPath) ? fs.readFileSync(fullPath) : null;
    writeFile(directory, file, file === "package.json" ? '{"version":"2.5.10"}\n' : "new content\n");
    assert.equal(run(directory, "assert_cold_gate").status, 1, file);
    assert.equal(run(directory, "assert_rehearsal_accepted").status, 1, file);
    if (previous) fs.writeFileSync(fullPath, previous);
    else fs.unlinkSync(fullPath);
  }
  writeFile(directory, packageFile, JSON.stringify({ digest: "other-package" }));
  assert.equal(run(directory, "assert_cold_gate").status, 1);
  assert.equal(run(directory, "assert_rehearsal_accepted").status, 1);
  writeFile(directory, packageFile, JSON.stringify({ digest: evidence.livePackageDigest }));
  fs.unlinkSync(path.join(directory, "deploy-ui/src/main.ts"));
  assert.equal(run(directory, "assert_cold_gate").status, 1);
  checked(directory, "signing_inputs_digest");
});

test("legacy checks still match the working files to the recorded commit", (context) => {
  const directory = repository(context);
  writeFile(directory, coldGate, JSON.stringify({ status: "green", sourceCommit: git(directory, "rev-parse", "HEAD") }));
  writeFile(directory, "README.md", "updated notes\n");
  git(directory, "commit", "--quiet", "-am", "Update notes");
  checked(directory, "assert_cold_gate");
  writeFile(directory, "deploy-ui/src/new.ts");
  assert.equal(run(directory, "assert_cold_gate").status, 1);
});
