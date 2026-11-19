const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "../..");
const stagePath = path.join(root, "script/deploy/v2-5/sepolia-fix-1-stage.sh");
const stage = fs.readFileSync(stagePath, "utf8");
const rehearsal = fs.readFileSync(
  path.join(root, "script/deploy/v2-5/rehearse-sepolia-fix-1.sh"),
  "utf8"
);
const stageSetup = stage.slice(0, stage.indexOf("sha256_file() {"));
const rehearsalSetup = rehearsal.match(
  /^readonly CEREMONY_HOST=[\s\S]*?^readonly RPC=.*$/m
)?.[0];
assert.ok(rehearsalSetup, "rehearsal networking setup must exist");

function stageFunction(name) {
  const body = stage.match(
    new RegExp(`^${name}\\(\\) \\{[\\s\\S]*?^\\}`, "m")
  )?.[0];
  assert.ok(body, `stage function ${name} must exist`);
  return body;
}

function shell(source, overrides = {}) {
  const environment = { ...process.env };
  for (const variable of ["CEREMONY_HOST", "ANVIL_PORT", "RPC_URL"]) {
    delete environment[variable];
  }
  const result = spawnSync("bash", ["-c", source, stagePath, "status"], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...environment,
      SEPOLIA_REPLACEMENT_CONFIG: "deployments/sepolia/v2.5.5.json",
      DEPLOYMENTS_NETWORK: "anvil",
      ...overrides,
    },
  });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

for (const [label, overrides, expected] of [
  ["default", {}, "http://127.0.0.1:8548"],
  ["LAN", { CEREMONY_HOST: "192.0.2.10" }, "http://192.0.2.10:8548"],
  [
    "custom port",
    { CEREMONY_HOST: "192.0.2.10", ANVIL_PORT: "18548" },
    "http://192.0.2.10:18548",
  ],
]) {
  test(`stage and rehearsal agree on the ${label} RPC URL`, () => {
    assert.equal(
      shell(`${stageSetup}\nprintf '%s' "$RPC_URL"`, overrides),
      expected
    );
    assert.equal(
      shell(
        `set -euo pipefail\n${rehearsalSetup}\nprintf '%s' "$RPC"`,
        overrides
      ),
      expected
    );
  });
}

test("Anvil binds the selected ceremony host", () => {
  assert.match(rehearsal, /^  --host "\$CEREMONY_HOST" \\$/m);
});

test("LAN RPC is embedded in the locked rehearsal UI build", () => {
  const output = shell(
    `${stageSetup}\n${stageFunction("build_ui")}\n` +
      `npm() { printf '%s\\n%s\\n' "$VITE_ANVIL_RPC_URL" "$CEREMONY_PACKAGE"; }\n` +
      "build_ui",
    { CEREMONY_HOST: "192.0.2.10" }
  );
  assert.equal(
    output,
    "http://192.0.2.10:8548\n../deployments/anvil/ceremony-v2.5.5-rehearsal-eoa.json"
  );
});

test("LAN UI hosting does not replace the live Sepolia RPC", () => {
  assert.equal(
    shell(`${stageSetup}\nprintf '%s' "$RPC_URL"`, {
      CEREMONY_HOST: "192.0.2.10",
      DEPLOYMENTS_NETWORK: "sepolia",
    }),
    "https://eth-sep.hinterlight.net"
  );
});

test("ready output includes the LAN UI and wallet endpoints", (context) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "ceremony-network-"));
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  fs.writeFileSync(path.join(directory, "identity.json"), "{}\n");
  const output = shell(
    `${stageSetup}\n${stageFunction(
      "print_ready"
    )}\nprint_ready "$EVIDENCE_DIR"`,
    { CEREMONY_HOST: "192.0.2.10", EVIDENCE_DIR: directory }
  );
  assert.match(output, /RPC URL: http:\/\/192\.0\.2\.10:8548/);
  assert.match(output, /--host "192\.0\.2\.10" --port 4173 --strictPort/);
  assert.match(output, /Then open http:\/\/192\.0\.2\.10:4173/);
});
