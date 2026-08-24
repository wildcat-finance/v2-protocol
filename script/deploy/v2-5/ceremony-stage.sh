#!/usr/bin/env bash
# Canonical user-driven stages for the v2.5 Anvil rehearsal and live Sepolia ceremony.
#
# This script never signs, broadcasts, or executes a deployment transaction. It
# verifies completed run-state, prepares the next locked package, finalizes local
# inventory, and mutates time only when the selected target is disposable Anvil.
set -euo pipefail
cd "$(dirname "$0")/../../.."

readonly OLD_EXECUTOR='0xca732651410E915090d7A7D889A1E44eF4575fcE'
readonly NEW_EXECUTOR='0xca7007a75296b532ce1606d9e130eaa849800ca7'
readonly HELPER_RUNTIME_HASH='0x71813272287ef573f8a2f96101f1a9ba6982761ad9de14a3e65e88c236a8a6fa'

stage="${1:-}"
if [[ "$stage" == 'advance-delay' ]]; then
  # Compatibility for the accepted pre-generalization rehearsal command.
  stage='delay'
fi
case "$stage" in
  phase-1|phase-2|delay|phase-3|activation|finalize-activation|status) ;;
  *)
    echo 'usage: ceremony-stage.sh <phase-1|phase-2|delay|phase-3|activation|finalize-activation|status>' >&2
    exit 1
    ;;
esac

ANVIL_PORT="${ANVIL_PORT:-8547}"
DEPLOYMENTS_NETWORK="${DEPLOYMENTS_NETWORK:-anvil}"
case "$DEPLOYMENTS_NETWORK" in
  anvil)
    RPC_URL="${RPC_URL:-http://127.0.0.1:${ANVIL_PORT}}"
    RPC_DISPLAY="$RPC_URL"
    EXPECTED_CHAIN_ID=31337
    DELAY_MODE=advance
    export SKIP_EIP1153_CHECK=1
    ;;
  sepolia)
    : "${RPC_URL:?RPC_URL is required for live Sepolia}"
    RPC_DISPLAY='[reviewed live Sepolia RPC; redacted]'
    EXPECTED_CHAIN_ID=11155111
    DELAY_MODE=observe
    unset SKIP_EIP1153_CHECK
    ;;
  *)
    echo 'DEPLOYMENTS_NETWORK must be anvil or sepolia' >&2
    exit 1
    ;;
esac

export RPC_URL DEPLOYMENTS_NETWORK
export FOUNDRY_PROFILE=deploy
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export TEMPLATE_FEE_RECIPIENT="$OLD_EXECUTOR"

readonly NETWORK_DIR="$PWD/deployments/$DEPLOYMENTS_NETWORK"
readonly PHASE_1_PLAN="$NETWORK_DIR/plan-authority-helper-phase-1.json"
readonly PHASE_1_PACKAGE="$NETWORK_DIR/ceremony-authority-helper-phase-1.json"
readonly PHASE_1_STATE="$NETWORK_DIR/run-state-authority-helper-phase-1.json"
readonly PHASE_2_PLAN="$NETWORK_DIR/plan-authority-helper-phase-2.json"
readonly PHASE_2_PACKAGE="$NETWORK_DIR/ceremony-authority-helper-phase-2.json"
readonly PHASE_2_STATE="$NETWORK_DIR/run-state-authority-helper-phase-2.json"
readonly PHASE_3_PLAN="$NETWORK_DIR/plan-authority-helper-phase-3.json"
readonly PHASE_3_PACKAGE="$NETWORK_DIR/ceremony-authority-helper-phase-3.json"
readonly PHASE_3_STATE="$NETWORK_DIR/run-state-authority-helper-phase-3.json"
readonly ACTIVATION_PLAN="$NETWORK_DIR/plan-v2-5.json"
readonly ACTIVATION_PACKAGE="$NETWORK_DIR/ceremony-v2-5-eoa.json"
readonly ACTIVATION_STATE="$NETWORK_DIR/run-state-v2-5.json"
readonly DELAY_EVIDENCE="$NETWORK_DIR/authority-delay-v2-5.json"

lower_address() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

same_address() {
  [[ "$(lower_address "$1")" == "$(lower_address "$2")" ]]
}

assert_target() {
  test -d "$NETWORK_DIR" || {
    echo "Missing deployments/$DEPLOYMENTS_NETWORK" >&2
    exit 1
  }
  local chain_id
  chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
  if [[ "$chain_id" != "$EXPECTED_CHAIN_ID" ]]; then
    echo "Refusing to continue: $RPC_DISPLAY reports chain ID $chain_id, expected $EXPECTED_CHAIN_ID for $DEPLOYMENTS_NETWORK" >&2
    exit 1
  fi
  if [[ "$DEPLOYMENTS_NETWORK" == 'anvil' && -f "$NETWORK_DIR/anvil.pid" ]]; then
    local anvil_pid
    anvil_pid="$(<"$NETWORK_DIR/anvil.pid")"
    if ! kill -0 "$anvil_pid" 2>/dev/null; then
      echo "Recorded Anvil process $anvil_pid is not running. Resume the fork before continuing." >&2
      exit 1
    fi
  fi

  local inventory_network inventory_chain_id
  inventory_network="$(jq -er '.network' "$NETWORK_DIR/factory-inventory.json")"
  inventory_chain_id="$(jq -er '.chainId' "$NETWORK_DIR/factory-inventory.json")"
  if [[ "$inventory_network" != "$DEPLOYMENTS_NETWORK" || "$inventory_chain_id" != "$EXPECTED_CHAIN_ID" ]]; then
    echo "Inventory identity is $inventory_network/$inventory_chain_id; expected $DEPLOYMENTS_NETWORK/$EXPECTED_CHAIN_ID" >&2
    exit 1
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
    --arg network "$DEPLOYMENTS_NETWORK" \
    --arg executor "$(lower_address "$executor")" \
    --argjson chain_id "$EXPECTED_CHAIN_ID" \
    --argjson transaction_count "$transaction_count" '
      .network == $network and
      .chainId == $chain_id and
      ((.expectedExecutor | ascii_downcase) == $executor) and
      ((.transactions | length) == $transaction_count) and
      all(.transactions[]; ((.envelope.expectedExecutor | ascii_downcase) == $executor))
    ' "$plan_path" >/dev/null
}

prepare_package() {
  local label="$1" plan_path="$2" package_path="$3" state_path="$4" expected_executor="$5"
  node scripts/plan.js validate --plan "$plan_path"
  node scripts/plan.js ceremony-package \
    --plan "$plan_path" \
    --mode eoa \
    --out "$package_path" | tee "${package_path%.json}.digest.txt"
  (
    cd deploy-ui
    if [[ "$DEPLOYMENTS_NETWORK" == 'anvil' ]]; then
      export VITE_ANVIL_RPC_URL="$RPC_URL"
    else
      unset VITE_ANVIL_RPC_URL
    fi
    CEREMONY_PACKAGE="$package_path" npm run build
  )
  cat <<EOF

================================================================
$label is ready in the locked deployment UI.
Expected wallet: $expected_executor
Package: $package_path

Serve this exact build in a separate terminal:
  (cd deploy-ui && npm exec -- vite preview --host 127.0.0.1 --port 4173 --strictPort)

Connect the expected real wallet to:
  RPC:      $RPC_DISPLAY
  chain ID: $EXPECTED_CHAIN_ID

After every predicate is green, export the unedited run-state to:
  $state_path
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
    if [[ "$DEPLOYMENTS_NETWORK" == 'anvil' ]]; then
      echo "$label has no ETH at the pinned fork block. Fund it on Sepolia, then start a fresh fork." >&2
    else
      echo "$label has no Sepolia ETH. Fund it before preparing phase 1." >&2
    fi
    exit 1
  fi
}

replacement_helper() {
  jq -er '."deploy-replacement-authority-helper" | select(.status == "verified") | .resolvedAddress' \
    "$PHASE_1_STATE"
}

verify_replacement_helper() {
  local helper arch_controller helper_arch runtime_hash old_authorized new_authorized
  helper="$(replacement_helper)"
  arch_controller="$(jq -er '.WildcatArchController' "$NETWORK_DIR/deployments.json")"
  helper_arch="$(cast call "$helper" 'archController()(address)' --rpc-url "$RPC_URL")"
  runtime_hash="$(cast codehash "$helper" --rpc-url "$RPC_URL")"
  old_authorized="$(cast call "$helper" 'authorizedAccounts(address)(bool)' "$OLD_EXECUTOR" --rpc-url "$RPC_URL")"
  new_authorized="$(cast call "$helper" 'authorizedAccounts(address)(bool)' "$NEW_EXECUTOR" --rpc-url "$RPC_URL")"

  if ! same_address "$helper_arch" "$arch_controller"; then
    echo "Replacement helper $helper points to $helper_arch, expected $arch_controller" >&2
    exit 1
  fi
  if [[ "$runtime_hash" != "$HELPER_RUNTIME_HASH" ]]; then
    echo "Replacement helper runtime hash is $runtime_hash, expected $HELPER_RUNTIME_HASH" >&2
    exit 1
  fi
  if [[ "$old_authorized" != 'true' || "$new_authorized" != 'true' ]]; then
    echo "Unexpected replacement helper authorization: old=$old_authorized new=$new_authorized" >&2
    exit 1
  fi
  echo "Replacement helper verified: $helper (runtime $runtime_hash; both wallets authorized)"
}

prepare_phase_1() {
  assert_no_state "$PHASE_1_STATE" 'Authority phase 1'

  local arch_controller legacy_helper owner old_authorized new_authorized
  local engine arch_admin arch_operator pending_arch_admin engine_admin
  local pending_engine pending_engine_admin pending_engine_time operator_role sender_adder_role
  arch_controller="$(jq -er '.WildcatArchController' "$NETWORK_DIR/deployments.json")"
  legacy_helper="$(jq -er '.MockArchControllerOwner' "$NETWORK_DIR/deployments.json")"
  owner="$(cast call "$arch_controller" 'owner()(address)' --rpc-url "$RPC_URL")"
  if ! same_address "$owner" "$legacy_helper"; then
    echo "Legacy helper $legacy_helper does not own the $DEPLOYMENTS_NETWORK ArchController; found $owner" >&2
    exit 1
  fi
  old_authorized="$(cast call "$legacy_helper" 'authorizedAccounts(address)(bool)' "$OLD_EXECUTOR" --rpc-url "$RPC_URL")"
  new_authorized="$(cast call "$legacy_helper" 'authorizedAccounts(address)(bool)' "$NEW_EXECUTOR" --rpc-url "$RPC_URL")"
  if [[ "$old_authorized" != 'true' || "$new_authorized" != 'false' ]]; then
    echo "Unexpected legacy helper authorization: old=$old_authorized new=$new_authorized" >&2
    exit 1
  fi

  engine="$(cast call "$arch_controller" 'sphereXEngine()(address)' --rpc-url "$RPC_URL")"
  arch_admin="$(cast call "$arch_controller" 'sphereXAdmin()(address)' --rpc-url "$RPC_URL")"
  arch_operator="$(cast call "$arch_controller" 'sphereXOperator()(address)' --rpc-url "$RPC_URL")"
  pending_arch_admin="$(cast call "$arch_controller" 'pendingSphereXAdmin()(address)' --rpc-url "$RPC_URL")"
  engine_admin="$(cast call "$engine" 'defaultAdmin()(address)' --rpc-url "$RPC_URL")"
  pending_engine="$(cast call "$engine" 'pendingDefaultAdmin()(address,uint48)' --rpc-url "$RPC_URL")"
  pending_engine_admin="$(printf '%s\n' "$pending_engine" | sed -n '1p')"
  pending_engine_time="$(printf '%s\n' "$pending_engine" | sed -n '2p' | awk '{print $1}')"
  operator_role="$(cast keccak 'OPERATOR_ROLE')"
  sender_adder_role="$(cast keccak 'SENDER_ADDER_ROLE')"

  if ! same_address "$arch_admin" "$OLD_EXECUTOR" ||
    ! same_address "$arch_operator" "$OLD_EXECUTOR" ||
    ! same_address "$pending_arch_admin" '0x0000000000000000000000000000000000000000' ||
    ! same_address "$engine_admin" "$OLD_EXECUTOR" ||
    ! same_address "$pending_engine_admin" '0x0000000000000000000000000000000000000000' ||
    [[ "$pending_engine_time" != '0' ]]; then
    echo 'Unexpected ArchController or SphereX admin baseline' >&2
    exit 1
  fi
  if [[ "$(cast call "$engine" 'hasRole(bytes32,address)(bool)' "$operator_role" "$OLD_EXECUTOR" --rpc-url "$RPC_URL")" != 'true' ||
    "$(cast call "$engine" 'hasRole(bytes32,address)(bool)' "$sender_adder_role" "$arch_controller" --rpc-url "$RPC_URL")" != 'true' ||
    "$(cast call "$arch_controller" 'isRegisteredBorrower(address)(bool)' "$NEW_EXECUTOR" --rpc-url "$RPC_URL")" != 'false' ]]; then
    echo 'Unexpected SphereX role or new-executor borrower baseline' >&2
    exit 1
  fi

  print_identity "$OLD_EXECUTOR" 'old executor'
  print_identity "$NEW_EXECUTOR" 'new executor'

  node scripts/authority-migration.js phase-one \
    --network "$DEPLOYMENTS_NETWORK" \
    --rpc-url "$RPC_URL" \
    --old-executor "$OLD_EXECUTOR" \
    --new-executor "$NEW_EXECUTOR"
  assert_plan_shape "$PHASE_1_PLAN" "$OLD_EXECUTOR" 5
  prepare_package 'Authority phase 1' "$PHASE_1_PLAN" "$PHASE_1_PACKAGE" "$PHASE_1_STATE" "$OLD_EXECUTOR"
}

prepare_phase_2() {
  verify_phase 'authority phase 1' "$PHASE_1_PLAN" "$PHASE_1_STATE"
  verify_replacement_helper
  assert_no_state "$PHASE_2_STATE" 'Authority phase 2'
  node scripts/authority-migration.js phase-two \
    --network "$DEPLOYMENTS_NETWORK" \
    --phase-one-run-state "$PHASE_1_STATE" \
    --new-executor "$NEW_EXECUTOR"
  assert_plan_shape "$PHASE_2_PLAN" "$NEW_EXECUTOR" 3
  prepare_package 'Authority phase 2' "$PHASE_2_PLAN" "$PHASE_2_PACKAGE" "$PHASE_2_STATE" "$NEW_EXECUTOR"
}

handle_delay() {
  verify_recorded_phase 'authority phase 1' "$PHASE_1_PLAN" "$PHASE_1_STATE"
  verify_phase 'authority phase 2' "$PHASE_2_PLAN" "$PHASE_2_STATE"
  verify_replacement_helper
  assert_no_state "$PHASE_3_STATE" 'Authority phase 3'
  if [[ -e "$DELAY_EVIDENCE" ]]; then
    if [[ "$DELAY_MODE" == 'advance' ]]; then
      echo "Delay evidence already exists at $DELAY_EVIDENCE; refusing to advance Anvil time again" >&2
      exit 1
    fi
    echo "Live delay evidence already exists at $DELAY_EVIDENCE; preserving it unchanged"
    cat "$DELAY_EVIDENCE"
    return
  fi
  local helper
  helper="$(replacement_helper)"
  RPC_URL="$RPC_URL" HELPER="$helper" EVIDENCE_PATH="$DELAY_EVIDENCE" \
    CEREMONY_NETWORK_DIR="$NETWORK_DIR" DELAY_MODE="$DELAY_MODE" \
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
  if (!block) throw new Error('Could not read the current block');
  return {
    number: Number(BigInt(block.number)),
    timestamp: Number(BigInt(block.timestamp)),
  };
}

async function main() {
  const provider = new JsonRpcProvider(process.env.RPC_URL);
  const helper = getAddress(process.env.HELPER);
  const deployments = JSON.parse(
    fs.readFileSync(`${process.env.CEREMONY_NETWORK_DIR}/deployments.json`, 'utf8'),
  );
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
  if (process.env.DELAY_MODE === 'advance') {
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
        readyBlockNumber: after.number,
        readyTimestamp: after.timestamp,
        secondsAdvanced,
      }, null, 2)}\n`,
    );
    console.log(
      `Anvil time advanced by ${secondsAdvanced}s to ${after.timestamp}; phase 3 is eligible.`,
    );
    return;
  }

  const secondsRemaining = Math.max(0, acceptanceTime - before.timestamp);
  fs.writeFileSync(
    process.env.EVIDENCE_PATH,
    `${JSON.stringify({
      action: 'live-delay-observation',
      engine,
      pendingAdmin,
      acceptanceTime,
      acceptanceTimeUtc: new Date(acceptanceTime * 1000).toISOString(),
      observedBlockNumber: before.number,
      observedTimestamp: before.timestamp,
      secondsRemaining,
      eligibleAtObservation: secondsRemaining === 0,
    }, null, 2)}\n`,
  );
  if (secondsRemaining === 0) {
    console.log(`Sepolia timestamp ${before.timestamp} is eligible for phase 3.`);
  } else {
    console.log(
      `Sepolia must wait ${secondsRemaining}s, until ${new Date(acceptanceTime * 1000).toISOString()}.`,
    );
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
NODE
}

assert_delay_ready() {
  test -f "$DELAY_EVIDENCE" || {
    echo "Missing delay evidence at $DELAY_EVIDENCE. Run the delay stage first." >&2
    exit 1
  }
  local helper
  helper="$(replacement_helper)"
  RPC_URL="$RPC_URL" HELPER="$helper" CEREMONY_NETWORK_DIR="$NETWORK_DIR" \
    EVIDENCE_PATH="$DELAY_EVIDENCE" DELAY_MODE="$DELAY_MODE" node <<'NODE'
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
  if (!block) throw new Error('Could not read the current block');
  return {
    number: Number(BigInt(block.number)),
    timestamp: Number(BigInt(block.timestamp)),
  };
}

async function main() {
  const provider = new JsonRpcProvider(process.env.RPC_URL);
  const helper = getAddress(process.env.HELPER);
  const deployments = JSON.parse(
    fs.readFileSync(`${process.env.CEREMONY_NETWORK_DIR}/deployments.json`, 'utf8'),
  );
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
  const acceptanceTime = Number(pending[1]);
  if (block.timestamp < acceptanceTime) {
    throw new Error(
      `SphereX delay has not elapsed. Current ${block.timestamp}; eligible ${acceptanceTime} (${new Date(acceptanceTime * 1000).toISOString()}).`,
    );
  }
  if (process.env.DELAY_MODE === 'observe') {
    const evidence = JSON.parse(fs.readFileSync(process.env.EVIDENCE_PATH, 'utf8'));
    if (evidence.acceptanceTime !== acceptanceTime) {
      throw new Error('Recorded delay schedule differs from the live pending schedule');
    }
    evidence.readyBlockNumber = block.number;
    evidence.readyTimestamp = block.timestamp;
    evidence.readyTimestampUtc = new Date(block.timestamp * 1000).toISOString();
    fs.writeFileSync(process.env.EVIDENCE_PATH, `${JSON.stringify(evidence, null, 2)}\n`);
  }
  console.log(`SphereX delay ready at block ${block.number}, timestamp ${block.timestamp}.`);
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
  verify_replacement_helper
  assert_no_state "$PHASE_3_STATE" 'Authority phase 3'
  assert_delay_ready
  node scripts/authority-migration.js phase-three \
    --network "$DEPLOYMENTS_NETWORK" \
    --rpc-url "$RPC_URL" \
    --phase-one-run-state "$PHASE_1_STATE" \
    --old-executor "$OLD_EXECUTOR" \
    --new-executor "$NEW_EXECUTOR"
  assert_plan_shape "$PHASE_3_PLAN" "$NEW_EXECUTOR" 3
  prepare_package 'Authority phase 3' "$PHASE_3_PLAN" "$PHASE_3_PACKAGE" "$PHASE_3_STATE" "$NEW_EXECUTOR"
}

finalize_helper_alias() {
  local helper recorded_helper legacy_helper
  helper="$(replacement_helper)"
  recorded_helper="$(jq -er '.MockArchControllerOwner' "$NETWORK_DIR/deployments.json")"
  legacy_helper="$(jq -r '.MockArchControllerOwnerLegacy // empty' "$NETWORK_DIR/deployments.json")"
  if same_address "$recorded_helper" "$helper"; then
    if [[ -z "$legacy_helper" ]] || same_address "$legacy_helper" "$helper"; then
      echo 'Replacement helper alias is already finalized but the legacy alias is missing or invalid' >&2
      exit 1
    fi
    node scripts/authority-helper.js preflight \
      --network "$DEPLOYMENTS_NETWORK" \
      --rpc-url "$RPC_URL" \
      --expected-executor "$NEW_EXECUTOR"
    return
  fi
  node scripts/authority-helper.js finalize \
    --network "$DEPLOYMENTS_NETWORK" \
    --rpc-url "$RPC_URL" \
    --expected-executor "$NEW_EXECUTOR" \
    --helper "$helper"
}

prepare_activation() {
  verify_recorded_phase 'authority phase 1' "$PHASE_1_PLAN" "$PHASE_1_STATE"
  verify_phase 'authority phase 2' "$PHASE_2_PLAN" "$PHASE_2_STATE"
  verify_phase 'authority phase 3' "$PHASE_3_PLAN" "$PHASE_3_STATE"
  verify_replacement_helper
  assert_no_state "$ACTIVATION_STATE" 'Activation'
  finalize_helper_alias

  export EXPECTED_EXECUTOR="$NEW_EXECUTOR"
  node scripts/factory-inventory.js reconcile \
    --network "$DEPLOYMENTS_NETWORK" \
    --rpc-url "$RPC_URL"
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
  prepare_package 'v2.5 activation' "$ACTIVATION_PLAN" "$ACTIVATION_PACKAGE" "$ACTIVATION_STATE" "$NEW_EXECUTOR"
}

finalize_activation() {
  verify_phase 'v2.5 activation' "$ACTIVATION_PLAN" "$ACTIVATION_STATE"
  export EXPECTED_EXECUTOR="$NEW_EXECUTOR"
  RUN_STATE="$ACTIVATION_STATE" RPC_URL="$RPC_URL" \
    bash script/deploy/v2-5/08-finalize-inventory.sh
  node scripts/factory-inventory.js validate --network "$DEPLOYMENTS_NETWORK"
  if [[ "$DEPLOYMENTS_NETWORK" == 'anvil' ]]; then
    node scripts/factory-inventory.js lint \
      --network anvil \
      --allowlist "$NETWORK_DIR/factory-inventory-lint-allowlist.json"
  else
    node scripts/factory-inventory.js lint --network sepolia
  fi
  node scripts/factory-inventory.js reconcile \
    --network "$DEPLOYMENTS_NETWORK" \
    --rpc-url "$RPC_URL"
  node scripts/authority-helper.js preflight \
    --network "$DEPLOYMENTS_NETWORK" \
    --rpc-url "$RPC_URL" \
    --expected-executor "$NEW_EXECUTOR" | \
    tee "$NETWORK_DIR/authority-preflight-v2-5.txt"
  node scripts/generate-handoff.js --network "$DEPLOYMENTS_NETWORK" --release v2-5
  node scripts/generate-handoff.js --network "$DEPLOYMENTS_NETWORK" --release v2-5 --check
  cat <<EOF

Activation is finalized and the handoff is valid. Standard and revolving
canaries are optional supplemental checks on this disposable fork; they are not
part of the wallet ceremony or a live deployment requirement. Retirement is a
separate ceremony prepared later from finalized post-activation Sepolia state.
EOF
}

show_status() {
  local arch_controller owner helper
  arch_controller="$(jq -er '.WildcatArchController' "$NETWORK_DIR/deployments.json")"
  owner="$(cast call "$arch_controller" 'owner()(address)' --rpc-url "$RPC_URL")"
  helper="$(jq -er '.MockArchControllerOwner' "$NETWORK_DIR/deployments.json")"
  printf 'Target: %s (chain %s)\nRPC: %s\nArchController: %s\nOwner: %s\nRecorded helper: %s\n' \
    "$DEPLOYMENTS_NETWORK" "$EXPECTED_CHAIN_ID" "$RPC_DISPLAY" "$arch_controller" "$owner" "$helper"
  print_identity "$OLD_EXECUTOR" 'old executor'
  print_identity "$NEW_EXECUTOR" 'new executor'
  for path in \
    "$PHASE_1_STATE" "$PHASE_2_STATE" "$PHASE_3_STATE" "$ACTIVATION_STATE"; do
    if [[ -f "$path" ]]; then
      echo "run-state present: $path"
    fi
  done
}

assert_target
case "$stage" in
  phase-1) prepare_phase_1 ;;
  phase-2) prepare_phase_2 ;;
  delay) handle_delay ;;
  phase-3) prepare_phase_3 ;;
  activation) prepare_activation ;;
  finalize-activation) finalize_activation ;;
  status) show_status ;;
esac
