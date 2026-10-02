#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOYMENTS_NETWORK:?DEPLOYMENTS_NETWORK is required}"
export FOUNDRY_PROFILE=deploy

release="${RELEASE_TAG:-v2-5}"
plan="deployments/${DEPLOYMENTS_NETWORK}/plan-${release}.json"

ceremony_config="deployments/${DEPLOYMENTS_NETWORK}/ceremony-config.json"
if [[ -f "$ceremony_config" ]] && \
  jq -e '.ownership.type == "authorized-helper"' "$ceremony_config" >/dev/null; then
  : "${RPC_URL:?RPC_URL is required for the authorized-helper preflight}"
  : "${EXPECTED_EXECUTOR:?EXPECTED_EXECUTOR is required for the authorized-helper preflight}"
  node scripts/authority-helper.js preflight \
    --network "$DEPLOYMENTS_NETWORK" \
    --rpc-url "$RPC_URL" \
    --expected-executor "$EXPECTED_EXECUTOR"
fi

node scripts/plan.js assemble --network "$DEPLOYMENTS_NETWORK" --release "$release"
node scripts/plan.js validate --plan "$plan"
node scripts/factory-inventory.js validate-activation-plan \
  --network "$DEPLOYMENTS_NETWORK" \
  --plan "$plan"
node - "$plan" <<'NODE'
const fs = require("fs");

const planPath = process.argv[2];
const plan = JSON.parse(fs.readFileSync(planPath, "utf8"));
const { assertActivationTemplateCommitments } = require("./scripts/template-commitments");
assertActivationTemplateCommitments(plan);

console.log("Template matrix valid: 6 artifact-bound registrations across 2 factories");
NODE
# shellcheck disable=SC2016
node -e '
const plan = require("./" + process.argv[1]);
const deploys = plan.transactions.filter((entry) => entry.kind === "deploy").length;
const calls = plan.transactions.filter((entry) => entry.kind === "call").length;
console.log(`Ceremony summary: ${plan.transactions.length} tx (${deploys} deploy, ${calls} call)`);
' "$plan"
