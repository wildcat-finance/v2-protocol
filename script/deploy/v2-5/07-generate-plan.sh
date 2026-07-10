#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOYMENTS_NETWORK:?DEPLOYMENTS_NETWORK is required}"
export FOUNDRY_PROFILE=deploy

release="${RELEASE_TAG:-v2-5}"
plan="deployments/${DEPLOYMENTS_NETWORK}/plan-${release}.json"

node scripts/plan.js assemble --network "$DEPLOYMENTS_NETWORK" --release "$release"
node scripts/plan.js validate --plan "$plan"
node -e '
const plan = require("./" + process.argv[1]);
const deploys = plan.transactions.filter((entry) => entry.kind === "deploy").length;
const calls = plan.transactions.filter((entry) => entry.kind === "call").length;
console.log(`Ceremony summary: ${plan.transactions.length} tx (${deploys} deploy, ${calls} call)`);
' "$plan"
