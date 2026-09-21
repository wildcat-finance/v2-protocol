#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../../../.."

: "${DEPLOYMENTS_NETWORK:?DEPLOYMENTS_NETWORK is required}"
: "${EXPECTED_EXECUTOR:?EXPECTED_EXECUTOR is required}"
export FOUNDRY_PROFILE=deploy

release="${RELEASE_TAG:-v2-5}"
retirement_release="${release}-retirement"
plan="deployments/${DEPLOYMENTS_NETWORK}/plan-${retirement_release}.json"

node scripts/factory-inventory.js retirement-entries \
  --network "$DEPLOYMENTS_NETWORK" \
  --expected-executor "$EXPECTED_EXECUTOR"
node scripts/plan.js assemble \
  --network "$DEPLOYMENTS_NETWORK" \
  --release "$retirement_release" \
  --entries retirement-plan-entries
node scripts/plan.js validate --plan "$plan"
node scripts/factory-inventory.js validate-retirement-plan \
  --network "$DEPLOYMENTS_NETWORK" \
  --plan "$plan"
# shellcheck disable=SC2016
node -e '
const plan = require("./" + process.argv[1]);
console.log(`Retirement ceremony summary: ${plan.transactions.length} calls`);
' "$plan"
