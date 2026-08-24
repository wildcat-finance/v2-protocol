#!/usr/bin/env bash
# User-driven continuation steps for the v2.5 Sepolia-fork rehearsal.
#
# The fresh fork is created by rehearse.sh. Every transaction is then signed
# through the locked deployment UI by the same wallet that will sign on live
# Sepolia. This script only verifies completed run-state, advances disposable
# Anvil time when explicitly requested, and prepares the next locked package.
set -euo pipefail
cd "$(dirname "$0")/../../.."

readonly OLD_EXECUTOR='0xca732651410E915090d7A7D889A1E44eF4575fcE'
readonly NEW_EXECUTOR='0xca7007a75296b532ce1606d9e130eaa849800ca7'

stage="${1:-}"
case "$stage" in
  phase-1|phase-2|advance-delay|phase-3|activation|finalize-activation|status) ;;
  *)
    echo 'usage: rehearse-stage.sh <phase-1|phase-2|advance-delay|phase-3|activation|finalize-activation|status>' >&2
    exit 1
    ;;
esac

ANVIL_PORT="${ANVIL_PORT:-8547}"
export RPC_URL="http://127.0.0.1:${ANVIL_PORT}"
export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=anvil
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export SKIP_EIP1153_CHECK=1
export TEMPLATE_FEE_RECIPIENT="$OLD_EXECUTOR"

readonly ANVIL_DIR="$PWD/deployments/anvil"
readonly PHASE_1_PLAN="$ANVIL_DIR/plan-authority-helper-phase-1.json"
readonly PHASE_1_PACKAGE="$ANVIL_DIR/ceremony-authority-helper-phase-1.json"
readonly PHASE_1_STATE="$ANVIL_DIR/run-state-authority-helper-phase-1.json"
readonly PHASE_2_PLAN="$ANVIL_DIR/plan-authority-helper-phase-2.json"
readonly PHASE_2_PACKAGE="$ANVIL_DIR/ceremony-authority-helper-phase-2.json"
readonly PHASE_2_STATE="$ANVIL_DIR/run-state-authority-helper-phase-2.json"
readonly PHASE_3_PLAN="$ANVIL_DIR/plan-authority-helper-phase-3.json"
readonly PHASE_3_PACKAGE="$ANVIL_DIR/ceremony-authority-helper-phase-3.json"
readonly PHASE_3_STATE="$ANVIL_DIR/run-state-authority-helper-phase-3.json"
readonly ACTIVATION_PLAN="$ANVIL_DIR/plan-v2-5.json"
readonly ACTIVATION_PACKAGE="$ANVIL_DIR/ceremony-v2-5-eoa.json"
readonly ACTIVATION_STATE="$ANVIL_DIR/run-state-v2-5.json"
readonly DELAY_EVIDENCE="$ANVIL_DIR/authority-delay-rehearsal.json"

same_address() {
  [[ "${1,,}" == "${2,,}" ]]
}

assert_local_fork() {
  test -d "$ANVIL_DIR" || {
    echo 'Missing deployments/anvil. Start the rehearsal with rehearse.sh first.' >&2
    exit 1
  }
  local chain_id
  chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
  if [[ "$chain_id" != '31337' ]]; then
    echo "Refusing to continue: $RPC_URL reports chain ID $chain_id, expected disposable Anvil chain 31337" >&2
    exit 1
  fi
  if [[ -f "$ANVIL_DIR/anvil.pid" ]]; then
    local anvil_pid
    anvil_pid="$(<"$ANVIL_DIR/anvil.pid")"
    if ! kill -0 "$anvil_pid" 2>/dev/null; then
      echo "Recorded Anvil process $anvil_pid is not running. Resume the fork before continuing." >&2
      exit 1
    fi
  fi
}

assert_no_state() {
  local state_path="$1" label="$2"
  if [[ -e "$state_path" ]]; then
    echo "$label already has a run-state at $state_path; refusing to regenerate it" >&2
    exit 1
  fi
}

verify_recorded_phase() {
  local label="$1" plan_path="$2" state_path="$3"
  test -f "$plan_path" || {
    echo "Missing $label plan: $plan_path" >&2
    exit 1
  }
  test -f "$state_path" || {
    echo "Export the completed $label run-state to $state_path before continuing" >&2
    exit 1
  }
  node scripts/plan.js verify-eoa-run-state \
    --plan "$plan_path" \
    --run-state "$state_path" \
    --rpc "$RPC_URL"
}

verify_phase() {
  local label="$1" plan_path="$2" state_path="$3"
  verify_recorded_phase "$label" "$plan_path" "$state_path"
  node scripts/plan.js verify \
    --plan "$plan_path" \
    --run-state "$state_path" \
    --rpc "$RPC_URL"
}

assert_plan_shape() {
  local plan_path="$1" executor="$2" transaction_count="$3"
  jq -e \
    --arg executor "${executor,,}" \
    --argjson transaction_count "$transaction_count" '
      .network == "anvil" and
      .chainId == 31337 and
      ((.expectedExecutor | ascii_downcase) == $executor) and
      ((.transactions | length) == $transaction_count) and
      all(.transactions[]; ((.envelope.expectedExecutor | ascii_downcase) == $executor))
    ' "$plan_path" >/dev/null
}

prepare_package() {
  local label="$1" plan_path="$2" package_path="$3" expected_executor="$4"
  node scripts/plan.js validate --plan "$plan_path"
  node scripts/plan.js ceremony-package \
    --plan "$plan_path" \
    --mode eoa \
    --out "$package_path"
  (
    cd deploy-ui
    VITE_ANVIL_RPC_URL="$RPC_URL" CEREMONY_PACKAGE="$package_path" npm run build
  )
  cat <<EOF

================================================================
$label is ready in the locked deployment UI.
Expected wallet: $expected_executor
Package: $package_path

Serve this exact build in a separate terminal:
  (cd deploy-ui && npm exec -- vite preview --host 127.0.0.1 --port 4173 --strictPort)

Connect the expected real wallet to:
  RPC:      $RPC_URL
  chain ID: 31337

After every predicate is green, export the run-state using the filename shown
by the UI and place it in deployments/anvil before running the next stage.
================================================================
EOF
}

print_identity() {
  local address="$1" label="$2"
  local balance nonce
  balance="$(cast balance "$address" --rpc-url "$RPC_URL")"
  nonce="$(cast nonce "$address" --rpc-url "$RPC_URL")"
  printf '%s: %s  balance=%s wei  nonce=%s\n' "$label" "$address" "$balance" "$nonce"
  if [[ "$balance" == '0' ]]; then
    echo "$label has no ETH at the pinned fork block. Fund it on Sepolia, then start a fresh fork." >&2
    exit 1
  fi
}

replacement_helper() {
  jq -er '."deploy-replacement-authority-helper" | select(.status == "verified") | .resolvedAddress' \
    "$PHASE_1_STATE"
}

prepare_phase_1() {
  assert_no_state "$PHASE_1_STATE" 'Authority phase 1'

  local arch_controller legacy_helper owner old_authorized new_authorized
  arch_controller="$(jq -er '.WildcatArchController' "$ANVIL_DIR/deployments.json")"
  legacy_helper="$(jq -er '.MockArchControllerOwner' "$ANVIL_DIR/deployments.json")"
  owner="$(cast call "$arch_controller" 'owner()(address)' --rpc-url "$RPC_URL")"
  if ! same_address "$owner" "$legacy_helper"; then
    echo "Legacy helper $legacy_helper does not own the forked ArchController; found $owner" >&2
    exit 1
  fi
  old_authorized="$(cast call "$legacy_helper" 'authorizedAccounts(address)(bool)' "$OLD_EXECUTOR" --rpc-url "$RPC_URL")"
  new_authorized="$(cast call "$legacy_helper" 'authorizedAccounts(address)(bool)' "$NEW_EXECUTOR" --rpc-url "$RPC_URL")"
  if [[ "$old_authorized" != 'true' || "$new_authorized" != 'false' ]]; then
    echo "Unexpected legacy helper authorization: old=$old_authorized new=$new_authorized" >&2
    exit 1
  fi

  print_identity "$OLD_EXECUTOR" 'old executor'
  print_identity "$NEW_EXECUTOR" 'new executor'

  node scripts/authority-migration.js phase-one \
    --network anvil \
    --rpc-url "$RPC_URL" \
    --old-executor "$OLD_EXECUTOR" \
    --new-executor "$NEW_EXECUTOR"
  assert_plan_shape "$PHASE_1_PLAN" "$OLD_EXECUTOR" 5
  prepare_package 'Authority phase 1' "$PHASE_1_PLAN" "$PHASE_1_PACKAGE" "$OLD_EXECUTOR"
}

prepare_phase_2() {
  verify_phase 'authority phase 1' "$PHASE_1_PLAN" "$PHASE_1_STATE"
  assert_no_state "$PHASE_2_STATE" 'Authority phase 2'
  node scripts/authority-migration.js phase-two \
    --network anvil \
    --phase-one-run-state "$PHASE_1_STATE" \
    --new-executor "$NEW_EXECUTOR"
  assert_plan_shape "$PHASE_2_PLAN" "$NEW_EXECUTOR" 3
  prepare_package 'Authority phase 2' "$PHASE_2_PLAN" "$PHASE_2_PACKAGE" "$NEW_EXECUTOR"
}

advance_delay() {
  verify_recorded_phase 'authority phase 1' "$PHASE_1_PLAN" "$PHASE_1_STATE"
  verify_phase 'authority phase 2' "$PHASE_2_PLAN" "$PHASE_2_STATE"
  assert_no_state "$PHASE_3_STATE" 'Authority phase 3'
  if [[ -e "$DELAY_EVIDENCE" ]]; then
    echo "Delay evidence already exists at $DELAY_EVIDENCE; refusing to advance Anvil time again" >&2
    exit 1
  fi
  local helper
  helper="$(replacement_helper)"
  RPC_URL="$RPC_URL" HELPER="$helper" EVIDENCE_PATH="$DELAY_EVIDENCE" \
    node <<'NODE'
const fs = require('fs');
const { Interface, JsonRpcProvider, getAddress } = require('ethers');

async function read(provider, target, signature) {
  const iface = new Interface([`function ${signature}`]);
  const fragment = iface.fragments[0];
  const result = await provider.call({
    to: target,
    data: iface.encodeFunctionData(fragment, []),
  });
  return iface.decodeFunctionResult(fragment, result);
}

async function latestBlock(provider) {
  const block = await provider.send('eth_getBlockByNumber', ['latest', false]);
  if (!block) throw new Error('Could not read the current Anvil block');
  return {
    number: Number(BigInt(block.number)),
    timestamp: Number(BigInt(block.timestamp)),
  };
}

async function main() {
  const provider = new JsonRpcProvider(process.env.RPC_URL);
  const helper = getAddress(process.env.HELPER);
  const deployments = JSON.parse(fs.readFileSync('deployments/anvil/deployments.json', 'utf8'));
  const archController = getAddress(deployments.WildcatArchController);
  const [engineValue] = await read(provider, archController, 'sphereXEngine() view returns (address)');
  const engine = getAddress(engineValue);
  const pending = await read(
    provider,
    engine,
    'pendingDefaultAdmin() view returns (address,uint48)',
  );
  const pendingAdmin = getAddress(pending[0]);
  const acceptanceTime = Number(pending[1]);
  if (pendingAdmin !== helper) {
    throw new Error(`Pending SphereX admin is ${pendingAdmin}; expected ${helper}`);
  }
  if (acceptanceTime === 0) throw new Error('SphereX engine has no pending acceptance time');

  const before = await latestBlock(provider);
  const secondsAdvanced = Math.max(0, acceptanceTime - before.timestamp + 1);
  if (secondsAdvanced > 0) {
    await provider.send('evm_increaseTime', [secondsAdvanced]);
    await provider.send('evm_mine', []);
  }
  const after = await latestBlock(provider);
  if (after.timestamp < acceptanceTime) {
    throw new Error(`Anvil timestamp ${after.timestamp} has not reached ${acceptanceTime}`);
  }
  fs.writeFileSync(
    process.env.EVIDENCE_PATH,
    `${JSON.stringify({
      action: 'user-requested-anvil-time-advance',
      engine,
      pendingAdmin,
      acceptanceTime,
      beforeBlockNumber: before.number,
      beforeTimestamp: before.timestamp,
      afterBlockNumber: after.number,
      afterTimestamp: after.timestamp,
      secondsAdvanced,
    }, null, 2)}\n`,
  );
  console.log(`Anvil time advanced by ${secondsAdvanced}s to ${after.timestamp}; phase 3 is now eligible.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
NODE
  echo 'Prepare phase 3 with: bash script/deploy/v2-5/rehearse-stage.sh phase-3'
}

assert_delay_ready() {
  local helper
  helper="$(replacement_helper)"
  RPC_URL="$RPC_URL" HELPER="$helper" node <<'NODE'
const fs = require('fs');
const { Interface, JsonRpcProvider, getAddress } = require('ethers');

async function read(provider, target, signature) {
  const iface = new Interface([`function ${signature}`]);
  const fragment = iface.fragments[0];
  const result = await provider.call({ to: target, data: iface.encodeFunctionData(fragment, []) });
  return iface.decodeFunctionResult(fragment, result);
}

async function latestBlock(provider) {
  const block = await provider.send('eth_getBlockByNumber', ['latest', false]);
  if (!block) throw new Error('Could not read the current Anvil block');
  return { timestamp: Number(BigInt(block.timestamp)) };
}

async function main() {
  const provider = new JsonRpcProvider(process.env.RPC_URL);
  const helper = getAddress(process.env.HELPER);
  const deployments = JSON.parse(fs.readFileSync('deployments/anvil/deployments.json', 'utf8'));
  const [engineValue] = await read(
    provider,
    getAddress(deployments.WildcatArchController),
    'sphereXEngine() view returns (address)',
  );
  const pending = await read(
    provider,
    getAddress(engineValue),
    'pendingDefaultAdmin() view returns (address,uint48)',
  );
  const block = await latestBlock(provider);
  if (getAddress(pending[0]) !== helper) throw new Error('Unexpected pending SphereX admin');
  if (block.timestamp < Number(pending[1])) {
    throw new Error('SphereX delay has not elapsed. Run the explicit advance-delay stage first.');
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
NODE
}

prepare_phase_3() {
  verify_recorded_phase 'authority phase 1' "$PHASE_1_PLAN" "$PHASE_1_STATE"
  verify_phase 'authority phase 2' "$PHASE_2_PLAN" "$PHASE_2_STATE"
  assert_no_state "$PHASE_3_STATE" 'Authority phase 3'
  assert_delay_ready
  node scripts/authority-migration.js phase-three \
    --network anvil \
    --rpc-url "$RPC_URL" \
    --phase-one-run-state "$PHASE_1_STATE" \
    --old-executor "$OLD_EXECUTOR" \
    --new-executor "$NEW_EXECUTOR"
  assert_plan_shape "$PHASE_3_PLAN" "$NEW_EXECUTOR" 3
  prepare_package 'Authority phase 3' "$PHASE_3_PLAN" "$PHASE_3_PACKAGE" "$NEW_EXECUTOR"
}

finalize_helper_alias() {
  local helper recorded_helper legacy_helper
  helper="$(replacement_helper)"
  recorded_helper="$(jq -er '.MockArchControllerOwner' "$ANVIL_DIR/deployments.json")"
  legacy_helper="$(jq -r '.MockArchControllerOwnerLegacy // empty' "$ANVIL_DIR/deployments.json")"
  if same_address "$recorded_helper" "$helper"; then
    if [[ -z "$legacy_helper" ]] || same_address "$legacy_helper" "$helper"; then
      echo 'Replacement helper alias is already finalized but the legacy alias is missing or invalid' >&2
      exit 1
    fi
    node scripts/authority-helper.js preflight \
      --network anvil \
      --rpc-url "$RPC_URL" \
      --expected-executor "$NEW_EXECUTOR"
    return
  fi
  node scripts/authority-helper.js finalize \
    --network anvil \
    --rpc-url "$RPC_URL" \
    --expected-executor "$NEW_EXECUTOR" \
    --helper "$helper"
}

prepare_activation() {
  verify_recorded_phase 'authority phase 1' "$PHASE_1_PLAN" "$PHASE_1_STATE"
  verify_phase 'authority phase 2' "$PHASE_2_PLAN" "$PHASE_2_STATE"
  verify_phase 'authority phase 3' "$PHASE_3_PLAN" "$PHASE_3_STATE"
  assert_no_state "$ACTIVATION_STATE" 'Activation'
  finalize_helper_alias

  export EXPECTED_EXECUTOR="$NEW_EXECUTOR"
  for script_name in \
    01-deploy-wrapper-factory \
    02-deploy-hooks-factory-standard \
    03-deploy-hooks-factory-revolving \
    04-deploy-market-lens \
    05-owner-actions \
    06-register-factories; do
    echo "== generate: $script_name"
    forge script "script/deploy/v2-5/${script_name}.s.sol" --rpc-url "$RPC_URL" >/dev/null
  done
  bash script/deploy/v2-5/07-generate-plan.sh
  assert_plan_shape "$ACTIVATION_PLAN" "$NEW_EXECUTOR" 24
  jq -e '
    ([.transactions[] | select(.kind == "deploy")] | length) == 14 and
    ([.transactions[] | select(.kind == "call")] | length) == 10 and
    ([.transactions[] | select(.forwardedCall != null)] | length) == 8 and
    all(.transactions[]; .id != "reclaim-arch-controller-ownership") and
    all(.transactions[]; .id != "restore-arch-controller-ownership")
  ' "$ACTIVATION_PLAN" >/dev/null
  prepare_package 'v2.5 activation' "$ACTIVATION_PLAN" "$ACTIVATION_PACKAGE" "$NEW_EXECUTOR"
}

finalize_activation() {
  verify_phase 'v2.5 activation' "$ACTIVATION_PLAN" "$ACTIVATION_STATE"
  export EXPECTED_EXECUTOR="$NEW_EXECUTOR"
  RUN_STATE="$ACTIVATION_STATE" RPC_URL="$RPC_URL" \
    bash script/deploy/v2-5/08-finalize-inventory.sh
  node scripts/factory-inventory.js validate --network anvil
  node scripts/factory-inventory.js lint \
    --network anvil \
    --allowlist "$ANVIL_DIR/factory-inventory-lint-allowlist.json"
  node scripts/factory-inventory.js reconcile --network anvil --rpc-url "$RPC_URL"
  node scripts/authority-helper.js preflight \
    --network anvil \
    --rpc-url "$RPC_URL" \
    --expected-executor "$NEW_EXECUTOR"
  node scripts/generate-handoff.js --network anvil --release v2-5
  node scripts/generate-handoff.js --network anvil --release v2-5 --check
  cat <<EOF

Activation is finalized and the handoff is valid. Standard and revolving
canaries are optional supplemental checks on this disposable fork; they are not
part of the wallet ceremony or a live deployment requirement. Retirement is a
separate ceremony prepared later from finalized post-activation Sepolia state.
EOF
}

show_status() {
  local arch_controller owner helper
  arch_controller="$(jq -er '.WildcatArchController' "$ANVIL_DIR/deployments.json")"
  owner="$(cast call "$arch_controller" 'owner()(address)' --rpc-url "$RPC_URL")"
  helper="$(jq -er '.MockArchControllerOwner' "$ANVIL_DIR/deployments.json")"
  printf 'RPC: %s\nArchController: %s\nOwner: %s\nRecorded helper: %s\n' \
    "$RPC_URL" "$arch_controller" "$owner" "$helper"
  print_identity "$OLD_EXECUTOR" 'old executor'
  print_identity "$NEW_EXECUTOR" 'new executor'
  for path in \
    "$PHASE_1_STATE" "$PHASE_2_STATE" "$PHASE_3_STATE" "$ACTIVATION_STATE"; do
    if [[ -f "$path" ]]; then
      echo "run-state present: $path"
    fi
  done
}

assert_local_fork
case "$stage" in
  phase-1) prepare_phase_1 ;;
  phase-2) prepare_phase_2 ;;
  advance-delay) advance_delay ;;
  phase-3) prepare_phase_3 ;;
  activation) prepare_activation ;;
  finalize-activation) finalize_activation ;;
  status) show_status ;;
esac
