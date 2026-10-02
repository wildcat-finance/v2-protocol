const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync, spawnSync } = require("node:child_process");

const stage = fs.readFileSync(
  path.resolve(__dirname, "../../script/deploy/v2-5/sepolia-fix-1-stage.sh"),
  "utf8"
);
const sourceGate = stage.match(
  /^assert_clean_pushed_source\(\) \{[\s\S]*?^\}/m
)?.[0];
assert.ok(sourceGate, "source gate must exist in the stage script");

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

function repository(context) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "ceremony-source-"));
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  git(directory, "init", "--quiet", "--initial-branch=ceremony");
  writeFile(directory, "src/Contract.sol", "reviewed source\n");
  writeFile(directory, "README.md", "reviewed documentation\n");
  writeFile(directory, ".gitignore", "deploy-ui/dist/\n");
  git(directory, "add", "--", ".");
  git(directory, "commit", "--quiet", "-m", "Reviewed fixture");
  git(directory, "remote", "add", "origin", ".");
  git(directory, "update-ref", "refs/remotes/origin/ceremony", "HEAD");
  git(directory, "branch", "--set-upstream-to=origin/ceremony");
  return directory;
}

function runGate(directory) {
  return spawnSync(
    "bash",
    ["-c", `set -euo pipefail\n${sourceGate}\nassert_clean_pushed_source`],
    { cwd: directory, encoding: "utf8" }
  );
}

test("source gate permits unrelated local files and ignored build output", (context) => {
  const directory = repository(context);
  assert.equal(runGate(directory).status, 0);
  writeFile(directory, "notes.md");
  writeFile(directory, "machine-local/settings.json");
  writeFile(directory, "docs/local-notes.md");
  writeFile(directory, "deploy-ui/dist/index.html");
  const result = runGate(directory);
  assert.equal(result.status, 0, result.stderr);
});

for (const state of ["unstaged", "staged", "deleted"]) {
  test(`source gate rejects ${state} tracked changes`, (context) => {
    const directory = repository(context);
    if (state === "deleted") {
      fs.unlinkSync(path.join(directory, "src/Contract.sol"));
    } else {
      writeFile(directory, "src/Contract.sol", "unreviewed source\n");
      if (state === "staged") git(directory, "add", "src/Contract.sol");
    }
    const result = runGate(directory);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Tracked files or submodules differ/);
  });
}

test("source gate still rejects staged additions outside build inputs", (context) => {
  const directory = repository(context);
  writeFile(directory, "notes.md");
  git(directory, "add", "notes.md");
  const result = runGate(directory);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Tracked files or submodules differ/);
});

for (const filename of [
  "src/Unreviewed.sol",
  "lib/unreviewed/Library.sol",
  "script/Deploy.sol",
  "scripts/helper.js",
  "test/NewTest.t.sol",
  "deploy-ui/src/local.ts",
  "deployments/sepolia/local.json",
  ".npmrc",
  "npm-shrinkwrap.json",
  "package-lock.json",
]) {
  test(`source gate rejects untracked input ${filename}`, (context) => {
    const directory = repository(context);
    writeFile(directory, filename);
    const result = runGate(directory);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Untracked build or ceremony inputs/);
    assert.ok(result.stderr.includes(filename), result.stderr);
  });
}

test("source gate rejects a commit not present at the configured upstream", (context) => {
  const directory = repository(context);
  writeFile(directory, "README.md", "another revision\n");
  git(directory, "commit", "--quiet", "-am", "Unpushed fixture");
  const result = runGate(directory);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /HEAD is not pushed/);
});

test("source gate requires an upstream", (context) => {
  const directory = repository(context);
  git(directory, "branch", "--unset-upstream");
  const result = runGate(directory);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /upstream/i);
});

test("source gate still rejects an untracked file inside a recorded submodule", (context) => {
  const directory = repository(context);
  const dependency = path.join(directory, "lib/dependency");
  writeFile(directory, "lib/dependency/Library.sol", "reviewed dependency\n");
  git(dependency, "init", "--quiet", "--initial-branch=dependency");
  git(dependency, "add", "Library.sol");
  git(dependency, "commit", "--quiet", "-m", "Dependency fixture");
  git(directory, "add", "lib/dependency");
  git(directory, "commit", "--quiet", "-m", "Reviewed dependency");
  git(directory, "update-ref", "refs/remotes/origin/ceremony", "HEAD");
  assert.equal(runGate(directory).status, 0);
  writeFile(dependency, "Unreviewed.sol");
  const result = runGate(directory);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Tracked files or submodules differ/);
});
