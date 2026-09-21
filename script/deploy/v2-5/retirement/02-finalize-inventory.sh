#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../../../.."

: "${DEPLOYMENTS_NETWORK:?DEPLOYMENTS_NETWORK is required}"
: "${RUN_STATE:?RUN_STATE is required}"
export FOUNDRY_PROFILE=deploy

args=(apply-retirement --network "$DEPLOYMENTS_NETWORK" --run-state "$RUN_STATE")
if [[ -n "${RPC_URL:-}" ]]; then
  args+=(--rpc-url "$RPC_URL")
fi

node scripts/factory-inventory.js "${args[@]}"
