#!/usr/bin/env bash
# One-command fork rehearsal setup for the v2.5 release.
#
#   FORK_NETWORK=sepolia FORK_RPC_URL=https://eth-sep.hinterlight.net \
#     bash script/deploy/v2-5/rehearse.sh
#   FORK_NETWORK=mainnet FORK_RPC_URL="$MAINNET_ARCHIVE_RPC_URL" \
#     bash script/deploy/v2-5/rehearse.sh --full
#   FORK_NETWORK=sepolia FORK_RPC_URL=https://eth-sep.hinterlight.net \
#     bash script/deploy/v2-5/rehearse.sh --resume
#
# Default Sepolia mode: fork the network, seed deployments/anvil/, then leave
# Anvil running without generating a package. The operator uses the same shared
# stage commands as live Sepolia, and signs every transaction through deploy-ui.
#
# --full: impersonate and execute the complete flow headlessly. This proves the
# automation engine and state transitions, but is not release acceptance for
# the user-driven Sepolia ceremony.
#
# --resume: restart a crashed Anvil process from the periodically persisted
# state without reseeding deployments/anvil or regenerating the plan.
#
# Env:
#   FORK_NETWORK   sepolia | mainnet (required)
#   FORK_RPC_URL   archive RPC to fork from (required; no implicit provider)
#   FORK_FALLBACK_RPC_URL  optional second archive RPC. Anvil actively
#                          round-robins across every supplied URL; this is not
#                          passive failover and has no default.
#   FORK_BLOCK_NUMBER      block to pin (default: lowest current provider head)
#   ANVIL_PORT     default 8547
#   ANVIL_STATE_FILE       periodic state snapshot path
#   ANVIL_LOG_FILE         Anvil output log path
#   ANVIL_PID_FILE         Anvil PID record path
#   ANVIL_STATE_INTERVAL   snapshot interval in seconds (default: 1)
#   ANVIL_STARTUP_TIMEOUT  seconds to wait for the RPC after launch (default: 120)
#   RELEASE_TAG    default v2-5
set -euo pipefail
cd "$(dirname "$0")/../../.."

: "${FORK_NETWORK:?FORK_NETWORK is required (sepolia|mainnet)}"
RUN_MODE="${1:-}"
case "$RUN_MODE" in
  ""|--full|--resume) ;;
  *) echo "usage: rehearse.sh [--full|--resume]" >&2; exit 1 ;;
esac
ANVIL_PORT="${ANVIL_PORT:-8547}"
RPC="http://127.0.0.1:${ANVIL_PORT}"
export RPC_URL="$RPC"
readonly SEPOLIA_OLD_EXECUTOR='0xca732651410E915090d7A7D889A1E44eF4575fcE'
case "$FORK_NETWORK" in
  sepolia)
    EXPECTED_FORK_CHAIN_ID=11155111
    ;;
  mainnet)
    EXPECTED_FORK_CHAIN_ID=1
    ;;
  *) echo "FORK_NETWORK must be sepolia or mainnet" >&2; exit 1 ;;
esac
: "${FORK_RPC_URL:?FORK_RPC_URL is required and must be archive-capable}"
FORK_FALLBACK_RPC_URL="${FORK_FALLBACK_RPC_URL:-}"
if [[ "$FORK_FALLBACK_RPC_URL" == "$FORK_RPC_URL" ]]; then
  FORK_FALLBACK_RPC_URL=""
fi
if [[ -n "$FORK_FALLBACK_RPC_URL" ]]; then
  echo "WARNING: Anvil will actively round-robin fork reads across both explicitly supplied RPC URLs; both must be archive-capable." >&2
fi
ANVIL_STATE_INTERVAL="${ANVIL_STATE_INTERVAL:-1}"
ANVIL_STARTUP_TIMEOUT="${ANVIL_STARTUP_TIMEOUT:-120}"
ANVIL_FORK_RETRIES="${ANVIL_FORK_RETRIES:-10}"
ANVIL_FORK_RETRY_BACKOFF="${ANVIL_FORK_RETRY_BACKOFF:-1000}"
if [[ ! "$ANVIL_STARTUP_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "ANVIL_STARTUP_TIMEOUT must be a positive integer" >&2
  exit 1
fi

export FOUNDRY_PROFILE=deploy DEPLOYMENTS_NETWORK=anvil SKIP_EIP1153_CHECK=1
export RELEASE_TAG="${RELEASE_TAG:-v2-5}"

ANVIL_DIR="$PWD/deployments/anvil"
ANVIL_STATE_FILE="${ANVIL_STATE_FILE:-$ANVIL_DIR/anvil-state.json}"
ANVIL_LOG_FILE="${ANVIL_LOG_FILE:-$ANVIL_DIR/anvil.log}"
ANVIL_PID_FILE="${ANVIL_PID_FILE:-$ANVIL_DIR/anvil.pid}"
FORK_BLOCK_FILE="$ANVIL_DIR/anvil-fork-block"
SOURCE_COMMIT_FILE="$ANVIL_DIR/source-commit"
ARCHIVE_PROBE_ADDRESS="$(jq -er '.WildcatArchController' "deployments/${FORK_NETWORK}/deployments.json")"

preflight_rpc() {
  local label="$1" url="$2" chain_id
  chain_id="$(cast chain-id --rpc-url "$url")"
  if [[ "$chain_id" != "$EXPECTED_FORK_CHAIN_ID" ]]; then
    echo "$label RPC chain ID $chain_id; expected $EXPECTED_FORK_CHAIN_ID" >&2
    exit 1
  fi
  cast block "$FORK_BLOCK_NUMBER" --rpc-url "$url" >/dev/null
  if ! cast storage "$ARCHIVE_PROBE_ADDRESS" 0 \
    --block "$ARCHIVE_PROBE_BLOCK" --rpc-url "$url" >/dev/null; then
    echo "$label RPC failed a historical storage read at block $ARCHIVE_PROBE_BLOCK; an archive-capable endpoint is required" >&2
    exit 1
  fi
}

if [[ "$RUN_MODE" == "--resume" ]]; then
  test -f "$ANVIL_STATE_FILE" || {
    echo "Cannot resume: missing Anvil state snapshot $ANVIL_STATE_FILE" >&2
    exit 1
  }
  test -f "$FORK_BLOCK_FILE" || {
    echo "Cannot resume: missing pinned fork block $FORK_BLOCK_FILE" >&2
    exit 1
  }
  test -f "$SOURCE_COMMIT_FILE" || {
    echo "Cannot resume: missing source commit $SOURCE_COMMIT_FILE" >&2
    exit 1
  }
  test -f "$ANVIL_DIR/deployments.json" || {
    echo "Cannot resume: missing seeded deployment state $ANVIL_DIR/deployments.json" >&2
    exit 1
  }
  SAVED_FORK_BLOCK="$(<"$FORK_BLOCK_FILE")"
  SAVED_SOURCE_COMMIT="$(<"$SOURCE_COMMIT_FILE")"
  CURRENT_SOURCE_COMMIT="$(git rev-parse HEAD)"
  if [[ "$CURRENT_SOURCE_COMMIT" != "$SAVED_SOURCE_COMMIT" ]]; then
    echo "Cannot resume: current commit $CURRENT_SOURCE_COMMIT differs from saved $SAVED_SOURCE_COMMIT" >&2
    exit 1
  fi
  REHEARSAL_SOURCE_COMMIT="$SAVED_SOURCE_COMMIT"
  if [[ -n "${FORK_BLOCK_NUMBER:-}" && "$FORK_BLOCK_NUMBER" != "$SAVED_FORK_BLOCK" ]]; then
    echo "Cannot resume: requested fork block $FORK_BLOCK_NUMBER differs from saved $SAVED_FORK_BLOCK" >&2
    exit 1
  fi
  FORK_BLOCK_NUMBER="$SAVED_FORK_BLOCK"
else
  PRIMARY_HEAD="$(cast block-number --rpc-url "$FORK_RPC_URL")"
  if [[ -z "${FORK_BLOCK_NUMBER:-}" ]]; then
    FORK_BLOCK_NUMBER="$PRIMARY_HEAD"
    if [[ -n "$FORK_FALLBACK_RPC_URL" ]]; then
      FALLBACK_HEAD="$(cast block-number --rpc-url "$FORK_FALLBACK_RPC_URL")"
      if (( FALLBACK_HEAD < FORK_BLOCK_NUMBER )); then
        FORK_BLOCK_NUMBER="$FALLBACK_HEAD"
      fi
    fi
  fi
fi

# A block-header lookup does not prove archive-state access. Probe far enough
# behind the selected head to reject endpoints that only expose current state.
ARCHIVE_PROBE_BLOCK=$((FORK_BLOCK_NUMBER > 1024 ? FORK_BLOCK_NUMBER - 1024 : 0))
preflight_rpc "primary" "$FORK_RPC_URL"
if [[ -n "$FORK_FALLBACK_RPC_URL" ]]; then
  preflight_rpc "fallback" "$FORK_FALLBACK_RPC_URL"
fi

assert_anvil_alive() {
  local chain_id
  if ! kill -0 "$ANVIL_PID" 2>/dev/null; then
    echo "Anvil exited. Last log lines:" >&2
    tail -40 "$ANVIL_LOG_FILE" >&2
    exit 1
  fi
  if ! chain_id="$(cast chain-id --rpc-url "$RPC" --rpc-timeout 2 2>/dev/null)" || [[ "$chain_id" != "31337" ]]; then
    echo "Anvil process $ANVIL_PID is not serving chain 31337 at $RPC. Last log lines:" >&2
    tail -40 "$ANVIL_LOG_FILE" >&2
    exit 1
  fi
}

assert_helper_owns_arch_controller() {
  if [[ "$FORK_NETWORK" != "sepolia" ]]; then
    return
  fi
  local helper current_owner normalized_helper normalized_owner
  helper="$(python3 -c "import json;print(json.load(open('deployments/anvil/deployments.json'))['MockArchControllerOwner'])")"
  current_owner="$(cast call "$AC" 'owner()(address)' --rpc-url "$RPC")"
  normalized_helper="$(printf '%s' "$helper" | tr '[:upper:]' '[:lower:]')"
  normalized_owner="$(printf '%s' "$current_owner" | tr '[:upper:]' '[:lower:]')"
  if [[ "$normalized_owner" != "$normalized_helper" ]]; then
    echo "Sepolia authority helper does not own the ArchController" >&2
    echo "Expected: $helper" >&2
    echo "Actual:   $current_owner" >&2
    exit 1
  fi
  echo "== ArchController remains owned by the Sepolia authority helper"
}

headless_migrate_sepolia_authority_helper() {
  local old_executor new_helper phase_one phase_two phase_three
  old_executor="$SEPOLIA_OLD_EXECUTOR"
  cast rpc anvil_setBalance "$old_executor" 0x8AC7230489E80000 --rpc-url "$RPC" >/dev/null

  node scripts/authority-migration.js phase-one \
    --network anvil \
    --rpc-url "$RPC" \
    --old-executor "$old_executor" \
    --new-executor "$EXECUTOR"
  phase_one="deployments/anvil/plan-authority-helper-phase-1.json"
  node scripts/plan.js execute --plan "$phase_one" --rpc "$RPC" \
    --impersonate "$old_executor" --yes | tail -2
  node scripts/plan.js verify --plan "$phase_one" \
    --run-state deployments/anvil/run-state-authority-helper-phase-1.json \
    --rpc "$RPC" | tail -1
  new_helper="$(jq -er '."deploy-replacement-authority-helper".resolvedAddress' \
    deployments/anvil/run-state-authority-helper-phase-1.json)"

  node scripts/authority-migration.js phase-two \
    --network anvil \
    --phase-one-run-state deployments/anvil/run-state-authority-helper-phase-1.json \
    --new-executor "$EXECUTOR"
  phase_two="deployments/anvil/plan-authority-helper-phase-2.json"
  node scripts/plan.js execute --plan "$phase_two" --rpc "$RPC" \
    --impersonate "$EXECUTOR" --yes | tail -2
  node scripts/plan.js verify --plan "$phase_two" \
    --run-state deployments/anvil/run-state-authority-helper-phase-2.json \
    --rpc "$RPC" | tail -1

  cast rpc evm_increaseTime 3601 --rpc-url "$RPC" >/dev/null
  cast rpc evm_mine --rpc-url "$RPC" >/dev/null
  node scripts/authority-migration.js phase-three \
    --network anvil \
    --rpc-url "$RPC" \
    --phase-one-run-state deployments/anvil/run-state-authority-helper-phase-1.json \
    --old-executor "$old_executor" \
    --new-executor "$EXECUTOR"
  phase_three="deployments/anvil/plan-authority-helper-phase-3.json"
  node scripts/plan.js execute --plan "$phase_three" --rpc "$RPC" \
    --impersonate "$EXECUTOR" --yes | tail -2
  node scripts/plan.js verify --plan "$phase_three" \
    --run-state deployments/anvil/run-state-authority-helper-phase-3.json \
    --rpc "$RPC" | tail -1

  node scripts/authority-helper.js finalize \
    --network anvil \
    --rpc-url "$RPC" \
    --expected-executor "$EXECUTOR" \
    --helper "$new_helper"
  echo "== Rehearsed authority migration to helper: ${new_helper}"
  assert_helper_owns_arch_controller
}

wait_for_anvil() {
  local started_at="$SECONDS" deadline=$((SECONDS + ANVIL_STARTUP_TIMEOUT)) chain_id
  echo "== Waiting up to ${ANVIL_STARTUP_TIMEOUT}s for Anvil RPC readiness"
  while (( SECONDS < deadline )); do
    if ! kill -0 "$ANVIL_PID" 2>/dev/null; then
      echo "Anvil exited during startup. Last log lines:" >&2
      tail -40 "$ANVIL_LOG_FILE" >&2
      return 1
    fi
    if chain_id="$(cast chain-id --rpc-url "$RPC" --rpc-timeout 2 2>/dev/null)"; then
      if [[ "$chain_id" == "31337" ]]; then
        echo "== Anvil RPC ready after $((SECONDS - started_at))s"
        return 0
      fi
      echo "Anvil RPC reported chain ID $chain_id; expected 31337" >&2
      kill "$ANVIL_PID" 2>/dev/null || true
      wait "$ANVIL_PID" 2>/dev/null || true
      return 1
    fi
    sleep 1
  done

  echo "Anvil did not become ready within ${ANVIL_STARTUP_TIMEOUT}s. Last log lines:" >&2
  tail -40 "$ANVIL_LOG_FILE" >&2
  kill "$ANVIL_PID" 2>/dev/null || true
  wait "$ANVIL_PID" 2>/dev/null || true
  return 1
}

start_anvil() {
  local state_mode="$1"
  local -a args=(
    --fork-url "$FORK_RPC_URL"
    --fork-block-number "$FORK_BLOCK_NUMBER"
    --fork-retry-backoff "$ANVIL_FORK_RETRY_BACKOFF"
    --retries "$ANVIL_FORK_RETRIES"
    --chain-id 31337
    --port "$ANVIL_PORT"
    --silent
    --state-interval "$ANVIL_STATE_INTERVAL"
  )
  if [[ "$RUN_MODE" == "--full" || "$FORK_NETWORK" == "mainnet" ]]; then
    args+=(--auto-impersonate)
  fi
  if [[ -n "$FORK_FALLBACK_RPC_URL" ]]; then
    args+=(--fork-url "$FORK_FALLBACK_RPC_URL")
  fi
  if [[ "$state_mode" == "resume" ]]; then
    args+=(--state "$ANVIL_STATE_FILE")
  else
    args+=(--dump-state "$ANVIL_STATE_FILE")
  fi

  pkill -f "anvil.*--port ${ANVIL_PORT}" 2>/dev/null || true
  sleep 1
  touch "$ANVIL_LOG_FILE"
  anvil "${args[@]}" > >(tee -a "$ANVIL_LOG_FILE") 2>&1 &
  ANVIL_PID=$!
  printf '%s\n' "$ANVIL_PID" > "$ANVIL_PID_FILE"
  wait_for_anvil
}

if [[ "$RUN_MODE" == "--resume" ]]; then
  echo "== Restoring anvil at pinned ${FORK_NETWORK} block ${FORK_BLOCK_NUMBER}"
  start_anvil resume
  cat <<RESUMED

================================================================
Anvil state restored (pid ${ANVIL_PID}) at fork block ${FORK_BLOCK_NUMBER}.
Existing packages, run-state, and browser progress, if any, were not changed.
Source commit: ${REHEARSAL_SOURCE_COMMIT}
State snapshot: ${ANVIL_STATE_FILE}
Anvil log: ${ANVIL_LOG_FILE}

In deploy-ui choose "Resume same Anvil fork". The page must re-verify every
stored receipt and predicate before it enables another transaction.
================================================================
RESUMED
  exit 0
fi

echo "== Seeding deployments/anvil/ from deployments/${FORK_NETWORK}/"
rm -rf deployments/anvil && mkdir -p deployments/anvil
cp "deployments/${FORK_NETWORK}/deployments.json" deployments/anvil/deployments.json
cp "deployments/${FORK_NETWORK}/factory-inventory.json" deployments/anvil/factory-inventory.json
if [[ -f "deployments/${FORK_NETWORK}/ceremony-config.json" ]]; then
  cp "deployments/${FORK_NETWORK}/ceremony-config.json" deployments/anvil/ceremony-config.json
fi
jq --arg source_network "$FORK_NETWORK" \
  '{networks: {anvil: .networks[$source_network]}}' \
  deployments/factory-inventory-lint-allowlist.json \
  > deployments/anvil/factory-inventory-lint-allowlist.json
python3 - <<'PY'
import json
p = 'deployments/anvil/factory-inventory.json'
d = json.load(open(p)); d['network'] = 'anvil'; d['chainId'] = 31337
json.dump(d, open(p, 'w'), indent=2)
PY

printf '%s\n' "$FORK_BLOCK_NUMBER" > "$FORK_BLOCK_FILE"
REHEARSAL_SOURCE_COMMIT="$(git rev-parse HEAD)"
printf '%s\n' "$REHEARSAL_SOURCE_COMMIT" > "$SOURCE_COMMIT_FILE"

echo "== Starting anvil fork of ${FORK_NETWORK} block ${FORK_BLOCK_NUMBER} on port ${ANVIL_PORT}"
start_anvil fresh

AC=$(python3 -c "import json;print(json.load(open('deployments/anvil/deployments.json'))['WildcatArchController'])")
OWNER=$(cast call "$AC" 'owner()(address)' --rpc-url "$RPC")
echo "== ArchController: ${AC}"
echo "== Current owner: ${OWNER}"

if [[ -z "$RUN_MODE" && "$FORK_NETWORK" == "sepolia" ]]; then
  cat <<STAGED

================================================================
Fork is RUNNING (pid ${ANVIL_PID}) at pinned Sepolia block ${FORK_BLOCK_NUMBER}.
No account was impersonated or funded, no package was generated, and no
transaction was executed.
Source commit: ${REHEARSAL_SOURCE_COMMIT}
State snapshot: ${ANVIL_STATE_FILE}
Anvil log: ${ANVIL_LOG_FILE}

Begin the same operator sequence used on live Sepolia:
  DEPLOYMENTS_NETWORK=anvil RPC_URL=${RPC} bash script/deploy/v2-5/ceremony-stage.sh phase-1

After an Anvil crash: rerun with --resume; do not run fresh setup first.
Stop fork: kill ${ANVIL_PID}
================================================================
STAGED
  exit 0
fi

cast rpc anvil_setBalance "$OWNER" 0x8AC7230489E80000 --rpc-url "$RPC" >/dev/null

if [[ "$RUN_MODE" == "--full" && "$FORK_NETWORK" == "mainnet" ]]; then
  # Headless mode executes as the impersonated real owner.
  EXECUTOR="$OWNER"
else
  # Sepolia uses the same authorized-helper shape as the live ceremony.
  EXECUTOR="${TEST_ACCOUNT:-0x70997970C51812dc3A010C7d01b50e0d17dc79C8}"
  cast rpc anvil_setBalance "$EXECUTOR" 0x8AC7230489E80000 --rpc-url "$RPC" >/dev/null
  if [[ "$FORK_NETWORK" == "sepolia" ]]; then
    headless_migrate_sepolia_authority_helper
    echo "== Test executor authorized on the replacement helper: ${EXECUTOR}"
  else
    cast send "$AC" 'transferOwnership(address)' "$EXECUTOR" \
      --from "$OWNER" --unlocked --rpc-url "$RPC" >/dev/null
    echo "== Fork ownership transferred to test executor: ${EXECUTOR}"
  fi
fi

export EXPECTED_EXECUTOR="$EXECUTOR" OWNER_MODE=plan
for s in 01-deploy-wrapper-factory 02-deploy-hooks-factory-standard \
         03-deploy-hooks-factory-revolving 04-deploy-market-lens 05-owner-actions \
         06-register-factories; do
  echo "== generate: ${s}"
  forge script "script/deploy/v2-5/${s}.s.sol" --rpc-url "$RPC" >/dev/null
  assert_anvil_alive
done
bash script/deploy/v2-5/07-generate-plan.sh
assert_anvil_alive

PLAN="deployments/anvil/plan-${RELEASE_TAG}.json"
PACKAGE="$PWD/deployments/anvil/ceremony-${RELEASE_TAG}-eoa.json"
RETIREMENT_PLAN="deployments/anvil/plan-${RELEASE_TAG}-retirement.json"
RETIREMENT_PACKAGE="$PWD/deployments/anvil/ceremony-${RELEASE_TAG}-retirement-eoa.json"

if [[ "$RUN_MODE" == "--full" ]]; then
  echo "== --full: executing activation plan as impersonated owner"
  node scripts/plan.js execute --plan "$PLAN" --rpc "$RPC" \
    --impersonate "$EXECUTOR" --yes | tail -2
  RUN_STATE="deployments/anvil/run-state-${RELEASE_TAG}.json" RPC_URL="$RPC" \
    bash script/deploy/v2-5/08-finalize-inventory.sh | tail -3
  node scripts/plan.js verify --plan "$PLAN" \
    --run-state "deployments/anvil/run-state-${RELEASE_TAG}.json" --rpc "$RPC" | tail -1
  assert_helper_owns_arch_controller

  if [[ "$FORK_NETWORK" == "sepolia" ]]; then
    echo "== --full: running standard and revolving canaries"
    BORROWER="$EXECUTOR" OWNER_MODE=direct \
      bash script/deploy/v2-5/09-canary-market.sh | tail -24
    assert_anvil_alive
  fi

  echo "== --full: generating and validating the activation handoff"
  node scripts/generate-handoff.js --network anvil --release "$RELEASE_TAG" | tail -4
  node scripts/generate-handoff.js --network anvil --release "$RELEASE_TAG" --check | tail -3

  echo "== --full: generating the separate retirement plan"
  bash script/deploy/v2-5/retirement/01-generate-plan.sh
  RETIREMENT_RUN_STATE="deployments/anvil/run-state-${RELEASE_TAG}-retirement.json"
  echo "== --full: executing retirement plan as impersonated owner"
  node scripts/plan.js execute --plan "$RETIREMENT_PLAN" --rpc "$RPC" \
    --impersonate "$EXECUTOR" --yes | tail -2
  RUN_STATE="$RETIREMENT_RUN_STATE" RPC_URL="$RPC" \
    bash script/deploy/v2-5/retirement/02-finalize-inventory.sh | tail -3
  node scripts/plan.js verify --plan "$RETIREMENT_PLAN" \
    --run-state "$RETIREMENT_RUN_STATE" --rpc "$RPC" | tail -1
  assert_helper_owns_arch_controller
  echo "== --full: refreshing and validating the post-retirement handoff"
  node scripts/generate-handoff.js --network anvil --release "$RELEASE_TAG" | tail -4
  node scripts/generate-handoff.js --network anvil --release "$RELEASE_TAG" --check | tail -3
  kill "$ANVIL_PID" 2>/dev/null || true
  wait "$ANVIL_PID" 2>/dev/null || true
  echo "== Full rehearsal complete. Clean up with: rm -rf deployments/anvil"
  exit 0
fi

FUNDED_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
KEY_NOTE="(anvil account #1, which matches the default test executor)"
if [[ -n "${TEST_ACCOUNT:-}" ]]; then
  FUNDED_KEY="<the private key for ${EXECUTOR}>"
  KEY_NOTE=""
fi
cat <<NEXT

================================================================
Fork is RUNNING (pid ${ANVIL_PID}).  Plan: ${PLAN}
Plan executor: ${EXECUTOR}
Pinned fork block: ${FORK_BLOCK_NUMBER}
Source commit: ${REHEARSAL_SOURCE_COMMIT}
State snapshot: ${ANVIL_STATE_FILE}
Anvil log: ${ANVIL_LOG_FILE}

Drive it from the frontend (EOA mode):
  1. node scripts/plan.js ceremony-package --plan ${PLAN} --mode eoa --out ${PACKAGE}
  2. (cd deploy-ui && CEREMONY_PACKAGE=${PACKAGE} npm run build)
     Then serve deploy-ui/dist with the reviewed production-preview command.
  3. Wallet: add network  RPC ${RPC}  chainId 31337
     Import the executor key ${KEY_NOTE}:
       ${FUNDED_KEY}
  4. Open the locked page, choose fresh or resume if prompted, and walk the cards.
  5. Export run-state, then:
       RUN_STATE=<exported file> RPC_URL=${RPC} \\
         bash script/deploy/v2-5/08-finalize-inventory.sh

Validate the new deployment before retiring anything. When it is accepted:
  1. EXPECTED_EXECUTOR=${EXECUTOR} \\
      bash script/deploy/v2-5/retirement/01-generate-plan.sh
  2. node scripts/plan.js ceremony-package --plan ${RETIREMENT_PLAN} \\
      --mode eoa --out ${RETIREMENT_PACKAGE}
  3. Rebuild deploy-ui with CEREMONY_PACKAGE=${RETIREMENT_PACKAGE}.
  4. Walk the retirement cards and export their separate run-state.
  5. RUN_STATE=<retirement run-state> RPC_URL=${RPC} \\
      bash script/deploy/v2-5/retirement/02-finalize-inventory.sh

Or headless: rerun with --full.
After an Anvil crash: rerun with --resume; do not run fresh setup first.
Stop fork: kill ${ANVIL_PID}    Clean up: rm -rf deployments/anvil
================================================================
NEXT
