#!/usr/bin/env bash
# Rehearse the Sepolia v2.5 fix-1 factory replacement against one pinned fork.
# The existing helper, executor authorization, and SphereX authority stay fixed.
set -euo pipefail

cd "$(dirname "$0")/../../.."

: "${FORK_RPC_URL:?FORK_RPC_URL is required}"

readonly RELEASE='v2-5-sepolia-fix-1'
readonly PLAN="deployments/sepolia/plan-${RELEASE}.json"
readonly EXECUTOR='0xCa7007a75296b532Ce1606d9e130eAa849800Ca7'
readonly EXPECTED_CHAIN_ID='11155111'

ANVIL_PORT="${ANVIL_PORT:-8548}"
if [[ ! "$ANVIL_PORT" =~ ^[1-9][0-9]*$ ]] || (( ANVIL_PORT > 65535 )); then
  echo 'ANVIL_PORT must be an integer from 1 through 65535' >&2
  exit 1
fi
readonly RPC="http://127.0.0.1:${ANVIL_PORT}"

if cast chain-id --rpc-url "$RPC" --rpc-timeout 1 >/dev/null 2>&1; then
  echo "Refusing to use occupied Anvil port ${ANVIL_PORT}" >&2
  exit 1
fi

if [[ -z "${FORK_BLOCK_NUMBER:-}" ]]; then
  FORK_BLOCK_NUMBER="$(cast block-number --rpc-url "$FORK_RPC_URL")"
fi
if [[ ! "$FORK_BLOCK_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo 'FORK_BLOCK_NUMBER must be a positive integer' >&2
  exit 1
fi

remote_chain_id="$(cast chain-id --rpc-url "$FORK_RPC_URL")"
if [[ "$remote_chain_id" != "$EXPECTED_CHAIN_ID" ]]; then
  echo "Fork RPC chain ID ${remote_chain_id}; expected ${EXPECTED_CHAIN_ID}" >&2
  exit 1
fi
cast block "$FORK_BLOCK_NUMBER" --rpc-url "$FORK_RPC_URL" >/dev/null

mkdir -p deployments/anvil
evidence_dir="$(mktemp -d "deployments/anvil/${RELEASE}-rehearsal.XXXXXX")"
readonly evidence_dir
readonly anvil_log="${evidence_dir}/anvil.log"
readonly preflight="${evidence_dir}/preflight.json"
readonly run_state="${evidence_dir}/run-state.json"
readonly post_activation="${evidence_dir}/post-activation.json"

anvil_pid=''
cleanup() {
  if [[ -n "$anvil_pid" ]] && kill -0 "$anvil_pid" 2>/dev/null; then
    kill "$anvil_pid" 2>/dev/null || true
    wait "$anvil_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

export FOUNDRY_PROFILE=deploy
node scripts/sepolia-v2-5-fix-rotation.js validate

anvil \
  --fork-url "$FORK_RPC_URL" \
  --fork-block-number "$FORK_BLOCK_NUMBER" \
  --chain-id "$EXPECTED_CHAIN_ID" \
  --host 127.0.0.1 \
  --port "$ANVIL_PORT" \
  --silent \
  >"$anvil_log" 2>&1 &
anvil_pid="$!"

for _ in {1..60}; do
  if ! kill -0 "$anvil_pid" 2>/dev/null; then
    echo "Anvil exited during startup; see ${anvil_log}" >&2
    exit 1
  fi
  if [[ "$(cast chain-id --rpc-url "$RPC" --rpc-timeout 1 2>/dev/null || true)" == "$EXPECTED_CHAIN_ID" ]]; then
    break
  fi
  sleep 1
done
if [[ "$(cast chain-id --rpc-url "$RPC" --rpc-timeout 1 2>/dev/null || true)" != "$EXPECTED_CHAIN_ID" ]]; then
  echo "Anvil did not serve chain ${EXPECTED_CHAIN_ID}; see ${anvil_log}" >&2
  exit 1
fi

cast rpc anvil_setBalance "$EXECUTOR" 0x56BC75E2D63100000 --rpc-url "$RPC" >/dev/null

node scripts/sepolia-v2-5-fix-rotation.js preflight \
  --rpc-url "$RPC" \
  --out "$preflight"

node scripts/plan.js execute \
  --plan "$PLAN" \
  --rpc "$RPC" \
  --impersonate "$EXECUTOR" \
  --run-state "$run_state" \
  --yes

node scripts/sepolia-v2-5-fix-rotation.js verify-activation \
  --rpc-url "$RPC" \
  --run-state "$run_state" \
  --preflight "$preflight" \
  --out "$post_activation"

echo "Pinned Sepolia fork rehearsal GREEN at block ${FORK_BLOCK_NUMBER}"
echo "Evidence retained in ${evidence_dir}"
