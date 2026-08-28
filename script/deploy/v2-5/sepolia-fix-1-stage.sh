#!/usr/bin/env bash
# Human-driven stages for the v2.5.3 Sepolia factory replacement.
#
# This script derives ceremony identity from the reviewed config and generated
# plan. It never signs or broadcasts. The operator signs every transaction in
# the locked deployment UI.
set -euo pipefail

cd "$(dirname "$0")/../../.."

readonly RELEASE='v2-5-sepolia-fix-1'
readonly REHEARSAL_RELEASE="${RELEASE}-rehearsal"
readonly ROTATION_SCRIPT='scripts/sepolia-v2-5-fix-rotation.js'
readonly CONFIG='deployments/sepolia/v2-5-sepolia-fix-1.json'
readonly LIVE_PLAN="deployments/sepolia/plan-${RELEASE}.json"
readonly LIVE_PACKAGE="deployments/sepolia/ceremony-${RELEASE}-eoa.json"
readonly REHEARSAL_PLAN="deployments/anvil/plan-${REHEARSAL_RELEASE}.json"
readonly REHEARSAL_PACKAGE="deployments/anvil/ceremony-${REHEARSAL_RELEASE}-eoa.json"
readonly COLD_GATE="deployments/anvil/${RELEASE}-cold-gate.json"
readonly REHEARSAL_ACCEPTANCE="deployments/anvil/${RELEASE}-accepted-rehearsal.json"
readonly ANVIL_SESSION_FILE="deployments/anvil/${RELEASE}-active-session"
readonly LIVE_SESSION_FILE="deployments/sepolia/ceremony-evidence/${RELEASE}-active-session"
readonly PENDING_INVENTORY="deployments/sepolia/inventory-pending-${RELEASE}"
readonly DEFAULT_SEPOLIA_RPC='https://eth-sep.hinterlight.net'

stage="${1:-}"
case "$stage" in
  check|activation|finalize-activation|finalize-inventory|status) ;;
  *)
    echo 'usage: sepolia-fix-1-stage.sh <check|activation|finalize-activation|finalize-inventory|status>' >&2
    exit 1
    ;;
esac

DEPLOYMENTS_NETWORK="${DEPLOYMENTS_NETWORK:-anvil}"
case "$DEPLOYMENTS_NETWORK" in
  anvil)
    RPC_URL="${RPC_URL:-http://127.0.0.1:${ANVIL_PORT:-8548}}"
    EXPECTED_CHAIN_ID='31337'
    PLAN="$REHEARSAL_PLAN"
    PACKAGE="$REHEARSAL_PACKAGE"
    PLAN_RELEASE="$REHEARSAL_RELEASE"
    ;;
  sepolia)
    RPC_URL="${RPC_URL:-$DEFAULT_SEPOLIA_RPC}"
    EXPECTED_CHAIN_ID='11155111'
    PLAN="$LIVE_PLAN"
    PACKAGE="$LIVE_PACKAGE"
    PLAN_RELEASE="$RELEASE"
    ;;
  *)
    echo 'DEPLOYMENTS_NETWORK must be anvil or sepolia' >&2
    exit 1
    ;;
esac

export DEPLOYMENTS_NETWORK RPC_URL
export FOUNDRY_PROFILE=deploy

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

package_fingerprint() {
  jq -er '.digest' "$1" |
    sed -E 's/^0x(.{4})(.{4})(.{4}).*$/\1-\2-\3/' |
    tr '[:lower:]' '[:upper:]'
}

assert_clean_pushed_source() {
  local upstream_head status
  git rev-parse '@{upstream}' >/dev/null
  upstream_head="$(git rev-parse '@{upstream}')"
  if [[ "$(git rev-parse HEAD)" != "$upstream_head" ]]; then
    echo "HEAD is not pushed to the configured upstream ($upstream_head)" >&2
    exit 1
  fi
  status="$(git status --porcelain --untracked-files=all)"
  if [[ -n "$status" ]]; then
    echo 'Working tree is not clean:' >&2
    printf '%s\n' "$status" >&2
    exit 1
  fi
}

assert_rpc() {
  local actual_chain_id
  actual_chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
  if [[ "$actual_chain_id" != "$EXPECTED_CHAIN_ID" ]]; then
    echo "RPC chain ID $actual_chain_id; expected $EXPECTED_CHAIN_ID for $DEPLOYMENTS_NETWORK" >&2
    exit 1
  fi
}

assert_anvil_session() {
  if [[ ! -f "$ANVIL_SESSION_FILE" ]]; then
    echo 'No recorded UI rehearsal. Start one with rehearse-sepolia-fix-1.sh --ui.' >&2
    exit 1
  fi
  local evidence_dir pid_file anvil_pid command_line
  evidence_dir="$(<"$ANVIL_SESSION_FILE")"
  case "$evidence_dir" in
    deployments/anvil/${RELEASE}-rehearsal.*) ;;
    *) echo "Unexpected rehearsal directory: $evidence_dir" >&2; exit 1 ;;
  esac
  pid_file="$evidence_dir/anvil.pid"
  test -f "$pid_file" || { echo "Missing Anvil PID: $pid_file" >&2; exit 1; }
  test -f "$evidence_dir/source-commit" || {
    echo "Missing rehearsal source commit: $evidence_dir/source-commit" >&2
    exit 1
  }
  if [[ "$(<"$evidence_dir/source-commit")" != "$(git rev-parse HEAD)" ]]; then
    echo 'The active Anvil fork was started from a different source commit.' >&2
    exit 1
  fi
  anvil_pid="$(<"$pid_file")"
  if [[ ! "$anvil_pid" =~ ^[1-9][0-9]*$ ]] || ! kill -0 "$anvil_pid" 2>/dev/null; then
    echo "Recorded Anvil process is not running: $anvil_pid" >&2
    exit 1
  fi
  command_line="$(ps -p "$anvil_pid" -o command= 2>/dev/null || true)"
  if [[ "$command_line" != *anvil* ]]; then
    echo "Recorded PID $anvil_pid is not Anvil" >&2
    exit 1
  fi
  printf '%s\n' "$evidence_dir"
}

assert_cold_gate() {
  test -f "$COLD_GATE" || {
    echo 'Cold gate evidence is missing. Run stage check first.' >&2
    exit 1
  }
  jq -e \
    --arg source_commit "$(git rev-parse HEAD)" \
    '.status == "green" and .sourceCommit == $source_commit' \
    "$COLD_GATE" >/dev/null || {
      echo 'Cold gate evidence does not match the current source commit.' >&2
      exit 1
  }
}

assert_rehearsed_input_unchanged() {
  local rehearsal_source="$1" tracked_path="$2" rehearsal_object current_object
  rehearsal_object="$(git rev-parse "${rehearsal_source}:${tracked_path}" 2>/dev/null)" || {
    echo "Accepted rehearsal source does not contain $tracked_path." >&2
    exit 1
  }
  current_object="$(git rev-parse "HEAD:${tracked_path}")"
  if [[ "$rehearsal_object" != "$current_object" ]]; then
    echo "Accepted rehearsal does not match the current $tracked_path." >&2
    exit 1
  fi
}

assert_rehearsal_accepted() {
  local rehearsal_source current_source tracked_path
  test -f "$REHEARSAL_ACCEPTANCE" || {
    echo 'Accepted real-wallet rehearsal evidence is missing.' >&2
    exit 1
  }
  rehearsal_source="$(jq -er '.sourceCommit' "$REHEARSAL_ACCEPTANCE")" || {
    echo 'Accepted rehearsal is missing its source commit.' >&2
    exit 1
  }
  git cat-file -e "${rehearsal_source}^{commit}" 2>/dev/null || {
    echo "Accepted rehearsal source commit is unavailable: $rehearsal_source" >&2
    exit 1
  }
  jq -e \
    --arg plan_sha256 "$(sha256_file "$LIVE_PLAN")" \
    --arg package_digest "$(jq -er '.digest' "$LIVE_PACKAGE")" \
    '.status == "green" and
     .livePlanSha256 == $plan_sha256 and
     .livePackageDigest == $package_digest' \
    "$REHEARSAL_ACCEPTANCE" >/dev/null || {
      echo 'Accepted rehearsal does not match the current plan or live package.' >&2
      exit 1
    }
  for tracked_path in "$CONFIG" "$LIVE_PLAN" package.json deploy-ui; do
    assert_rehearsed_input_unchanged "$rehearsal_source" "$tracked_path"
  done
  current_source="$(git rev-parse HEAD)"
  if [[ "$rehearsal_source" != "$current_source" ]]; then
    echo "Accepted rehearsal carried forward from $rehearsal_source."
    echo 'Config, plan, package digest, protocol version, and deploy-ui tree are unchanged.'
  fi
}

create_live_session() {
  mkdir -p deployments/sepolia/ceremony-evidence
  if [[ -f "$LIVE_SESSION_FILE" ]]; then
    echo 'A live ceremony session already exists. Finalize it or preserve and remove its pointer after review.' >&2
    echo "Session: $(<"$LIVE_SESSION_FILE")" >&2
    exit 1
  fi
  local evidence_dir
  evidence_dir="$(mktemp -d "deployments/sepolia/ceremony-evidence/${RELEASE}.XXXXXX")"
  printf '%s\n' "$evidence_dir"
}

current_session() {
  if [[ "$DEPLOYMENTS_NETWORK" == 'anvil' ]]; then
    assert_anvil_session
    return
  fi
  test -f "$LIVE_SESSION_FILE" || {
    echo 'No recorded live ceremony session. Run stage activation first.' >&2
    exit 1
  }
  local evidence_dir
  evidence_dir="$(<"$LIVE_SESSION_FILE")"
  case "$evidence_dir" in
    deployments/sepolia/ceremony-evidence/${RELEASE}.*) ;;
    *) echo "Unexpected live ceremony directory: $evidence_dir" >&2; exit 1 ;;
  esac
  test -d "$evidence_dir" || { echo "Missing session directory: $evidence_dir" >&2; exit 1; }
  printf '%s\n' "$evidence_dir"
}

generate_artifacts() {
  node "$ROTATION_SCRIPT" validate
  node scripts/plan.js ceremony-package \
    --plan "$LIVE_PLAN" \
    --mode eoa \
    --out "$LIVE_PACKAGE" |
    tee "${LIVE_PACKAGE%.json}.digest.txt"
  if [[ "$DEPLOYMENTS_NETWORK" == 'anvil' ]]; then
    node "$ROTATION_SCRIPT" generate-rehearsal
  fi
}

write_identity() {
  local evidence_dir="$1" package_digest fingerprint
  package_digest="$(jq -er '.digest' "$PACKAGE")"
  fingerprint="$(package_fingerprint "$PACKAGE")"
  jq -n \
    --arg status ready \
    --arg network "$DEPLOYMENTS_NETWORK" \
    --argjson chain_id "$EXPECTED_CHAIN_ID" \
    --arg release "$(jq -er '.release' "$PLAN")" \
    --arg protocol_version "$(jq -er '.version' package.json)" \
    --arg source_commit "$(git rev-parse HEAD)" \
    --arg contract_source_commit "$(jq -er '.contractSourceCommit' "$CONFIG")" \
    --arg foundry_profile "$FOUNDRY_PROFILE" \
    --arg plan "$PLAN" \
    --arg plan_sha256 "$(sha256_file "$PLAN")" \
    --arg package "$PACKAGE" \
    --arg package_digest "$package_digest" \
    --arg fingerprint "$fingerprint" \
    --arg executor "$(jq -er '.expectedExecutor' "$PLAN")" \
    --argjson transaction_count "$(jq -er '.transactions | length' "$PLAN")" \
    '{schemaVersion:"1.0.0", status:$status, network:$network,
      chainId:$chain_id, release:$release, protocolVersion:$protocol_version,
      sourceCommit:$source_commit, contractSourceCommit:$contract_source_commit,
      foundryProfile:$foundry_profile, plan:$plan, planSha256:$plan_sha256,
      package:$package, packageDigest:$package_digest, fingerprint:$fingerprint,
      expectedExecutor:$executor, transactionCount:$transaction_count}' \
    >"$evidence_dir/identity.json"
  touch "$evidence_dir/ui-started"
}

assert_identity_unchanged() {
  local evidence_dir="$1"
  jq -e \
    --arg network "$DEPLOYMENTS_NETWORK" \
    --argjson chain_id "$EXPECTED_CHAIN_ID" \
    --arg source_commit "$(git rev-parse HEAD)" \
    --arg plan_sha256 "$(sha256_file "$PLAN")" \
    --arg package_digest "$(jq -er '.digest' "$PACKAGE")" \
    --arg executor "$(jq -er '.expectedExecutor' "$PLAN")" \
    --argjson transaction_count "$(jq -er '.transactions | length' "$PLAN")" \
    '.status == "ready" and
     .network == $network and
     .chainId == $chain_id and
     .sourceCommit == $source_commit and
     .planSha256 == $plan_sha256 and
     .packageDigest == $package_digest and
     .expectedExecutor == $executor and
     .transactionCount == $transaction_count' \
    "$evidence_dir/identity.json" >/dev/null || {
      echo 'Ceremony identity changed after the locked UI was built.' >&2
      exit 1
    }
}

build_ui() {
  if [[ "$DEPLOYMENTS_NETWORK" == 'anvil' ]]; then
    (
      cd deploy-ui
      CEREMONY_PACKAGE="../$PACKAGE" \
        VITE_ANVIL_RPC_URL="$RPC_URL" \
        npm run build
    )
  else
    (
      cd deploy-ui
      CEREMONY_PACKAGE="../$PACKAGE" \
        VITE_SEPOLIA_RPC_URL="$RPC_URL" \
        npm run build
    )
  fi
}

print_ready() {
  local evidence_dir="$1"
  jq -r '
    "READY\n" +
    "network:     \(.network) (\(.chainId))\n" +
    "release:     \(.release) / protocol \(.protocolVersion)\n" +
    "source:      \(.sourceCommit)\n" +
    "executor:    \(.expectedExecutor)\n" +
    "cards:       \(.transactionCount)\n" +
    "digest:      \(.packageDigest)\n" +
    "fingerprint: \(.fingerprint)\n" +
    "evidence:    '"$evidence_dir"'"
  ' "$evidence_dir/identity.json"
  if [[ "$DEPLOYMENTS_NETWORK" == 'anvil' ]]; then
    cat <<EOF

Wallet network:
  name:    Anvil
  RPC URL: $RPC_URL
  chain:   $EXPECTED_CHAIN_ID
EOF
  else
    cat <<EOF

Wallet network:
  name:  Sepolia
  chain: $EXPECTED_CHAIN_ID
EOF
  fi
  cat <<'EOF'

In a second terminal:
  (cd deploy-ui && npm exec -- vite preview --host 127.0.0.1 --port 4173 --strictPort)

Then open http://127.0.0.1:4173, connect the displayed executor, confirm the
identity above, execute every card, and click Export run state.
EOF
}

find_exported_run_state() {
  local evidence_dir="$1" explicit_path="${RUN_STATE:-}" downloads_dir candidates count
  if [[ -n "$explicit_path" ]]; then
    test -f "$explicit_path" || { echo "RUN_STATE not found: $explicit_path" >&2; exit 1; }
    printf '%s\n' "$explicit_path"
    return
  fi
  downloads_dir="${DOWNLOADS_DIR:-${HOME}/Downloads}"
  candidates="$(find "$downloads_dir" -maxdepth 1 -type f \
    -name "run-state-${PLAN_RELEASE}*.json" \
    -newer "$evidence_dir/ui-started" -print 2>/dev/null || true)"
  count="$(printf '%s\n' "$candidates" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" != '1' ]]; then
    echo "Expected one new run-state-${PLAN_RELEASE}*.json in $downloads_dir; found $count." >&2
    if [[ -n "$candidates" ]]; then printf '%s\n' "$candidates" >&2; fi
    echo 'Set RUN_STATE to the exported file and rerun finalize-activation.' >&2
    exit 1
  fi
  printf '%s\n' "$candidates"
}

run_check() {
  assert_clean_pushed_source
  local fork_rpc_url
  fork_rpc_url="${FORK_RPC_URL:-$DEFAULT_SEPOLIA_RPC}"
  if [[ "$(cast chain-id --rpc-url "$fork_rpc_url")" != '11155111' ]]; then
    echo 'FORK_RPC_URL is not Sepolia.' >&2
    exit 1
  fi
  forge test
  yarn test:fixed
  FOUNDRY_PROFILE=deploy forge test
  FOUNDRY_PROFILE=deploy forge build --sizes
  (
    cd deploy-ui
    npm ci
    npm audit
    npm test
    npm run build
    SEPOLIA_RPC_URL="$fork_rpc_url" npm run test:fork
  )
  assert_clean_pushed_source
  mkdir -p deployments/anvil
  jq -n \
    --arg status green \
    --arg source_commit "$(git rev-parse HEAD)" \
    --arg checked_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{schemaVersion:"1.0.0", status:$status,
      sourceCommit:$source_commit, checkedAt:$checked_at}' >"$COLD_GATE"
  echo "Cold gates GREEN for $(git rev-parse HEAD)"
}

prepare_activation() {
  assert_clean_pushed_source
  assert_cold_gate
  assert_rpc
  local evidence_dir
  if [[ "$DEPLOYMENTS_NETWORK" == 'anvil' ]]; then
    evidence_dir="$(assert_anvil_session)"
    generate_artifacts
  else
    generate_artifacts
    assert_rehearsal_accepted
    evidence_dir="$(create_live_session)"
  fi
  assert_clean_pushed_source
  if [[ "$DEPLOYMENTS_NETWORK" == 'anvil' ]]; then
    node "$ROTATION_SCRIPT" preflight \
      --rehearsal --rpc-url "$RPC_URL" --out "$evidence_dir/preflight.json"
  else
    node "$ROTATION_SCRIPT" preflight \
      --rpc-url "$RPC_URL" --out "$evidence_dir/preflight.json"
  fi
  write_identity "$evidence_dir"
  build_ui
  if [[ "$DEPLOYMENTS_NETWORK" == 'sepolia' ]]; then
    printf '%s\n' "$evidence_dir" >"$LIVE_SESSION_FILE"
  fi
  print_ready "$evidence_dir"
}

finalize_activation() {
  assert_clean_pushed_source
  assert_rpc
  local evidence_dir exported_run_state retained_run_state post_activation
  evidence_dir="$(current_session)"
  assert_identity_unchanged "$evidence_dir"
  exported_run_state="$(find_exported_run_state "$evidence_dir")"
  retained_run_state="$evidence_dir/run-state.json"
  cp "$exported_run_state" "$retained_run_state"
  if [[ "$(sha256_file "$exported_run_state")" != "$(sha256_file "$retained_run_state")" ]]; then
    echo 'Run-state copy differs from the browser export.' >&2
    exit 1
  fi
  post_activation="$evidence_dir/post-activation.json"
  if [[ "$DEPLOYMENTS_NETWORK" == 'anvil' ]]; then
    node "$ROTATION_SCRIPT" verify-activation \
      --rehearsal \
      --plan "$PLAN" \
      --rpc-url "$RPC_URL" \
      --run-state "$retained_run_state" \
      --preflight "$evidence_dir/preflight.json" \
      --out "$post_activation"
    jq -n \
      --arg status green \
      --arg accepted_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      --arg source_commit "$(git rev-parse HEAD)" \
      --arg live_plan_sha256 "$(sha256_file "$LIVE_PLAN")" \
      --arg live_package_digest "$(jq -er '.digest' "$LIVE_PACKAGE")" \
      --arg rehearsal_package_digest "$(jq -er '.digest' "$REHEARSAL_PACKAGE")" \
      --arg fork_block "$(<"$evidence_dir/fork-block")" \
      --arg run_state_sha256 "$(sha256_file "$retained_run_state")" \
      '{schemaVersion:"1.0.0", status:$status, acceptedAt:$accepted_at,
        sourceCommit:$source_commit, livePlanSha256:$live_plan_sha256,
        livePackageDigest:$live_package_digest,
        rehearsalPackageDigest:$rehearsal_package_digest,
        forkBlock:$fork_block, runStateSha256:$run_state_sha256}' \
      >"$REHEARSAL_ACCEPTANCE"
    echo "Real-wallet Anvil rehearsal ACCEPTED: $REHEARSAL_ACCEPTANCE"
  else
    node "$ROTATION_SCRIPT" verify-activation \
      --rpc-url "$RPC_URL" \
      --run-state "$retained_run_state" \
      --preflight "$evidence_dir/preflight.json" \
      --out "$post_activation"
    cp "$retained_run_state" "deployments/sepolia/run-state-${RELEASE}.json"
    echo "Live Sepolia activation VERIFIED: $post_activation"
  fi
}

finalize_inventory() {
  if [[ "$DEPLOYMENTS_NETWORK" != 'sepolia' ]]; then
    echo 'Inventory finalization is only valid for the live Sepolia activation.' >&2
    exit 1
  fi
  assert_clean_pushed_source
  assert_rpc
  local evidence_dir run_state post_activation handoff
  evidence_dir="$(current_session)"
  run_state="$evidence_dir/run-state.json"
  post_activation="$evidence_dir/post-activation.json"
  handoff="deployments/sepolia/handoff-${RELEASE}.json"
  test -f "$run_state" || { echo "Missing verified run-state: $run_state" >&2; exit 1; }
  test -d "$PENDING_INVENTORY" || {
    echo "Missing release inventory records: $PENDING_INVENTORY" >&2
    exit 1
  }
  jq -e \
    --arg plan_sha256 "$(sha256_file "$LIVE_PLAN")" \
    --arg package_digest "$(jq -er '.digest' "$LIVE_PACKAGE")" \
    '.status == "ready" and
     .network == "sepolia" and
     .chainId == 11155111 and
     .planSha256 == $plan_sha256 and
     .packageDigest == $package_digest and
     .transactionCount == 22' \
    "$evidence_dir/identity.json" >/dev/null || {
      echo 'Live evidence does not match the reviewed plan and package.' >&2
      exit 1
    }
  jq -e \
    '.status == "green" and
     .network == "sepolia" and
     .chainId == 11155111 and
     .authorityChanged == false and
     .predecessorsRemainRegistered == true and
     .retirementExecuted == false' \
    "$post_activation" >/dev/null || {
      echo 'Live activation has not passed the expected postconditions.' >&2
      exit 1
    }
  node scripts/factory-inventory.js apply-run \
    --network sepolia \
    --run-state "$run_state" \
    --plan "$LIVE_PLAN" \
    --pending-directory "$PENDING_INVENTORY" \
    --rpc-url "$RPC_URL"
  node scripts/generate-handoff.js \
    --network sepolia \
    --release "$RELEASE" \
    --run-state "$run_state" \
    --plan "$LIVE_PLAN"
  node scripts/generate-handoff.js \
    --network sepolia \
    --release "$RELEASE" \
    --run-state "$run_state" \
    --plan "$LIVE_PLAN" \
    --check
  node scripts/factory-inventory.js reconcile \
    --network sepolia \
    --rpc-url "$RPC_URL" \
    --handoff "$handoff"
  echo "Sepolia inventory and handoff finalized from block $(jq -er '.blockNumber' "$post_activation")."
}

print_status() {
  assert_rpc
  local evidence_dir
  evidence_dir="$(current_session)"
  jq . "$evidence_dir/identity.json"
  if [[ -f "$evidence_dir/post-activation.json" ]]; then
    jq '{status,network,chainId,release,blockNumber,authorityChanged,
      predecessorsRemainRegistered,retirementExecuted}' \
      "$evidence_dir/post-activation.json"
  else
    echo 'post-activation verification: pending'
  fi
}

case "$stage" in
  check) run_check ;;
  activation) prepare_activation ;;
  finalize-activation) finalize_activation ;;
  finalize-inventory) finalize_inventory ;;
  status) print_status ;;
esac
