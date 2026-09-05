#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOYMENTS_NETWORK:?DEPLOYMENTS_NETWORK is required}"
: "${BORROWER:?BORROWER is required}"
: "${RPC_URL:?RPC_URL is required}"
export FOUNDRY_PROFILE=deploy

script='script/deploy/v2-5/09-canary-market.s.sol:CanaryMarketsV25'
network_upper="$(printf '%s' "$DEPLOYMENTS_NETWORK" | tr '[:lower:]-' '[:upper:]_')"
private_key_var="PVT_KEY_${network_upper}"
forge_args=(--rpc-url "$RPC_URL" --broadcast --non-interactive)
if [[ -z "${!private_key_var:-}" ]]; then
  forge_args+=(--unlocked --sender "$BORROWER")
fi

CANARY_PHASE=prepare forge script "$script" "${forge_args[@]}"
CANARY_PHASE=finalize forge script "$script" "${forge_args[@]}"
