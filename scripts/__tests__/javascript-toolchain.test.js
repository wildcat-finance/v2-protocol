const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const protocolPackage = require("../../package.json");
const uiPackage = require("../../deploy-ui/package.json");
const uiLock = require("../../deploy-ui/package-lock.json");

test("JavaScript packages use the pinned Node and package manager versions", () => {
  const nodeVersion = fs
    .readFileSync(path.join(root, ".node-version"), "utf8")
    .trim();
  assert.match(nodeVersion, /^\d+\.\d+\.\d+$/);
  for (const [manifest, manager] of [
    [protocolPackage, "yarn"],
    [uiPackage, "npm"],
  ]) {
    assert.equal(manifest.engines.node, nodeVersion);
    assert.match(manifest.engines[manager], /^\d+\.\d+\.\d+$/);
    assert.equal(
      manifest.packageManager,
      `${manager}@${manifest.engines[manager]}`
    );
  }
  assert.deepEqual(uiLock.packages[""].engines, uiPackage.engines);
});

test("package managers disable lifecycle scripts by default", () => {
  const yarnConfig = fs.readFileSync(path.join(root, ".yarnrc"), "utf8");
  const npmConfig = fs.readFileSync(
    path.join(root, "deploy-ui/.npmrc"),
    "utf8"
  );
  assert.match(yarnConfig, /^ignore-scripts true$/m);
  assert.match(npmConfig, /^ignore-scripts=true$/m);
  assert.match(npmConfig, /^engine-strict=true$/m);
});

test("ceremony installs use frozen dependencies without lifecycle scripts", () => {
  const stage = fs.readFileSync(
    path.join(root, "script/deploy/v2-5/sepolia-fix-1-stage.sh"),
    "utf8"
  );
  assert.match(
    stage,
    /^  corepack yarn install --frozen-lockfile --ignore-scripts --non-interactive$/m
  );
  assert.match(stage, /^    npm ci --ignore-scripts$/m);
});

test("lint commands keep Forge formatting and disable Solhint update checks", () => {
  assert.match(protocolPackage.devDependencies.solhint, /^\d+\.\d+\.\d+$/);
  for (const command of ["lint:check", "lint:fix"]) {
    assert.match(protocolPackage.scripts[command], /^forge fmt /);
    assert.match(
      protocolPackage.scripts[command],
      /&& solhint --disc --noPoster /
    );
    assert.doesNotMatch(
      protocolPackage.scripts[command],
      /\bsolhint\b.*--fix\b/
    );
  }
});
