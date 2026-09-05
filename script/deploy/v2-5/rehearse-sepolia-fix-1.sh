#!/usr/bin/env bash
# Rehearse the configured Sepolia factory replacement against one pinned fork.
# With no argument, execute the engine check headlessly. --ui leaves a chain
# 31337 fork running for the real-wallet locked-UI ceremony. --stop stops only
# the recorded --ui Anvil process.
set -euo pipefail

cd "$(dirname "$0")/../../.."

readonly CONFIG="${SEPOLIA_REPLACEMENT_CONFIG:-deployments/sepolia/v2-5-sepolia-fix-1.json}"
export SEPOLIA_REPLACEMENT_CONFIG="$CONFIG"
readonly RELEASE="$(jq -er '.release' "$CONFIG")"
readonly PLAN="deployments/sepolia/plan-${RELEASE}.json"
readonly EXECUTOR="$(jq -er '.expectedExecutor' "$CONFIG")"
readonly EXPECTED_CHAIN_ID='11155111'
readonly ANVIL_CHAIN_ID='31337'
readonly ACTIVE_SESSION_FILE="deployments/anvil/${RELEASE}-active-session"

mode="${1:---full}"
case "$mode" in
  --full|--ui|--stop) ;;
  *) echo 'usage: rehearse-sepolia-fix-1.sh [--full|--ui|--stop]' >&2; exit 1 ;;
esac

if [[ "$mode" == '--stop' ]]; then
  if [[ ! -f "$ACTIVE_SESSION_FILE" ]]; then
    echo "No recorded $RELEASE UI rehearsal is running."
    exit 0
  fi
  evidence_dir="$(<"$ACTIVE_SESSION_FILE")"
  case "$evidence_dir" in
    deployments/anvil/${RELEASE}-rehearsal.*) ;;
    *) echo "Refusing unexpected rehearsal directory: $evidence_dir" >&2; exit 1 ;;
  esac
  pid_file="$evidence_dir/anvil.pid"
  if [[ -f "$pid_file" ]]; then
    anvil_pid="$(<"$pid_file")"
    if [[ "$anvil_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$anvil_pid" 2>/dev/null; then
      command_line="$(ps -p "$anvil_pid" -o command= 2>/dev/null || true)"
      if [[ "$command_line" != *anvil* ]]; then
        echo "Refusing to stop PID $anvil_pid; it is not Anvil" >&2
        exit 1
      fi
      kill "$anvil_pid"
      echo "Stopped recorded Anvil process $anvil_pid."
    fi
  fi
  rm -f "$ACTIVE_SESSION_FILE"
  echo "Rehearsal evidence retained in $evidence_dir"
  exit 0
fi

: "${FORK_RPC_URL:?FORK_RPC_URL is required}"

if [[ "$mode" == '--ui' && -f "$ACTIVE_SESSION_FILE" ]]; then
  echo 'A UI rehearsal session is already recorded. Resume it or run --stop after preserving its evidence.' >&2
  echo "Session: $(<"$ACTIVE_SESSION_FILE")" >&2
  exit 1
fi

ANVIL_PORT="${ANVIL_PORT:-8548}"
if [[ ! "$ANVIL_PORT" =~ ^[1-9][0-9]*$ ]] || (( ANVIL_PORT > 65535 )); then
  echo 'ANVIL_PORT must be an integer from 1 through 65535' >&2
  exit 1
fi
readonly RPC="http://127.0.0.1:${ANVIL_PORT}"
local_chain_id="$EXPECTED_CHAIN_ID"
if [[ "$mode" == '--ui' ]]; then
  local_chain_id="$ANVIL_CHAIN_ID"
fi

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
keep_anvil_running='false'
cleanup() {
  if [[ "$keep_anvil_running" != 'true' && -n "$anvil_pid" ]] && kill -0 "$anvil_pid" 2>/dev/null; then
    kill "$anvil_pid" 2>/dev/null || true
    wait "$anvil_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

export FOUNDRY_PROFILE=deploy
node scripts/sepolia-v2-5-fix-rotation.js validate

anvil_command=(anvil
  --fork-url "$FORK_RPC_URL" \
  --fork-block-number "$FORK_BLOCK_NUMBER" \
  --chain-id "$local_chain_id" \
  --host 127.0.0.1 \
  --port "$ANVIL_PORT" \
  --silent)
if [[ "$mode" == '--ui' ]]; then
  nohup "${anvil_command[@]}" >"$anvil_log" 2>&1 &
else
  "${anvil_command[@]}" >"$anvil_log" 2>&1 &
fi
anvil_pid="$!"

for _ in {1..60}; do
  if ! kill -0 "$anvil_pid" 2>/dev/null; then
    echo "Anvil exited during startup; see ${anvil_log}" >&2
    exit 1
  fi
  if [[ "$(cast chain-id --rpc-url "$RPC" --rpc-timeout 1 2>/dev/null || true)" == "$local_chain_id" ]]; then
    break
  fi
  sleep 1
done
if [[ "$(cast chain-id --rpc-url "$RPC" --rpc-timeout 1 2>/dev/null || true)" != "$local_chain_id" ]]; then
  echo "Anvil did not serve chain ${local_chain_id}; see ${anvil_log}" >&2
  exit 1
fi

cast rpc anvil_setBalance "$EXECUTOR" 0x56BC75E2D63100000 --rpc-url "$RPC" >/dev/null

if [[ "$mode" == '--ui' ]]; then
  printf '%s\n' "$anvil_pid" >"$evidence_dir/anvil.pid"
  printf '%s\n' "$FORK_BLOCK_NUMBER" >"$evidence_dir/fork-block"
  git rev-parse HEAD >"$evidence_dir/source-commit"
  node scripts/sepolia-v2-5-fix-rotation.js preflight \
    --rehearsal \
    --rpc-url "$RPC" \
    --out "$preflight"
  printf '%s\n' "$evidence_dir" >"$ACTIVE_SESSION_FILE"
  keep_anvil_running='true'
  echo "Pinned Sepolia fork ready for the locked UI at block ${FORK_BLOCK_NUMBER}"
  echo "RPC: ${RPC} (chain ${ANVIL_CHAIN_ID})"
  echo "Evidence: ${evidence_dir}"
  echo "Next: SEPOLIA_REPLACEMENT_CONFIG=$CONFIG DEPLOYMENTS_NETWORK=anvil bash script/deploy/v2-5/sepolia-fix-1-stage.sh activation"
  exit 0
fi

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
