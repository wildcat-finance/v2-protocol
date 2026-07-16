#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOYMENTS_NETWORK:?DEPLOYMENTS_NETWORK is required}"
export FOUNDRY_PROFILE=deploy

release="${RELEASE_TAG:-v2-5}"
plan="deployments/${DEPLOYMENTS_NETWORK}/plan-${release}.json"

node scripts/plan.js assemble --network "$DEPLOYMENTS_NETWORK" --release "$release"
node scripts/plan.js validate --plan "$plan"
node - "$plan" <<'NODE'
const fs = require("fs");

const planPath = process.argv[2];
const plan = JSON.parse(fs.readFileSync(planPath, "utf8"));
const signature = "addHooksTemplate(address,string,address,address,uint80,uint16)";
const factories = [
  ["standard", "hooks-factory-standard"],
  ["revolving", "hooks-factory-revolving"],
];
const templates = [
  ["open-term", "open-term-hooks-init-code-storage", "OpenTermHooks"],
  ["fixed-term", "fixed-term-hooks-init-code-storage", "FixedTermHooks"],
  ["periodic-term", "periodic-term-hooks-init-code-storage", "PeriodicTermHooks"],
];
const expected = new Map(
  factories.flatMap(([factoryId, factoryRef]) =>
    templates.map(([templateId, storageRef, name]) => [
      `add-${factoryId}-${templateId}-template`,
      [factoryRef, storageRef, name],
    ]),
  ),
);
const registrations = plan.transactions.filter(
  (transaction) => transaction.functionSignature === signature,
);

if (registrations.length !== expected.size) {
  throw new Error(
    `Expected ${expected.size} v2.5 template registrations, found ${registrations.length}`,
  );
}

for (const [id, [factory, storage, name]] of expected) {
  const transaction = registrations.find((candidate) => candidate.id === id);
  if (
    !transaction ||
    transaction.to?.$ref !== factory ||
    transaction.args?.[0]?.$ref !== storage ||
    transaction.args?.[1] !== name
  ) {
    throw new Error(
      `Invalid v2.5 template registration ${id}; expected ${name} from ${storage} on ${factory}`,
    );
  }
}

console.log("Template matrix valid: 6 registrations across 2 factories");
NODE
node -e '
const plan = require("./" + process.argv[1]);
const deploys = plan.transactions.filter((entry) => entry.kind === "deploy").length;
const calls = plan.transactions.filter((entry) => entry.kind === "call").length;
console.log(`Ceremony summary: ${plan.transactions.length} tx (${deploys} deploy, ${calls} call)`);
' "$plan"
