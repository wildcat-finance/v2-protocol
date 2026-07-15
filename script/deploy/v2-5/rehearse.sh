#!/usr/bin/env bash
# One-command fork rehearsal setup for the v2.5 release.
#
#   FORK_NETWORK=sepolia bash script/deploy/v2-5/rehearse.sh
#   FORK_NETWORK=mainnet bash script/deploy/v2-5/rehearse.sh --full
#
# Default: fork the network, seed deployments/anvil/, generate the plan
# (steps 01-07), then leave anvil RUNNING and print how to drive the plan
# from deploy-ui (EOA mode) or the CLI.
#
# --full: additionally execute the plan (impersonated owner), finalize
# inventory (08), and verify — the headless end-to-end rehearsal.
#
# Env:
#   FORK_NETWORK   sepolia | mainnet (required)
#   FORK_RPC_URL   archive RPC to fork from (default: public endpoint; use
#                  your own archive node for speed)
#   ANVIL_PORT     default 8547
#   RELEASE_TAG    default v2-5
set -euo pipefail
cd "$(dirname "$0")/../../.."

: "${FORK_NETWORK:?FORK_NETWORK is required (sepolia|mainnet)}"
ANVIL_PORT="${ANVIL_PORT:-8547}"
RPC="http://127.0.0.1:${ANVIL_PORT}"
case "$FORK_NETWORK" in
  sepolia) DEFAULT_FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com ;;
  mainnet) DEFAULT_FORK_RPC=https://ethereum-rpc.publicnode.com ;;
  *) echo "FORK_NETWORK must be sepolia or mainnet" >&2; exit 1 ;;
esac
FORK_RPC_URL="${FORK_RPC_URL:-$DEFAULT_FORK_RPC}"

export FOUNDRY_PROFILE=deploy DEPLOYMENTS_NETWORK=anvil SKIP_EIP1153_CHECK=1
export RELEASE_TAG="${RELEASE_TAG:-v2-5}"

echo "== Seeding deployments/anvil/ from deployments/${FORK_NETWORK}/"
rm -rf deployments/anvil && mkdir -p deployments/anvil
cp "deployments/${FORK_NETWORK}/deployments.json" deployments/anvil/deployments.json
cp "deployments/${FORK_NETWORK}/factory-inventory.json" deployments/anvil/factory-inventory.json
if [[ -f "deployments/${FORK_NETWORK}/ceremony-config.json" ]]; then
  cp "deployments/${FORK_NETWORK}/ceremony-config.json" deployments/anvil/ceremony-config.json
fi
python3 - <<'PY'
import json
p = 'deployments/anvil/factory-inventory.json'
d = json.load(open(p)); d['network'] = 'anvil'; d['chainId'] = 31337
json.dump(d, open(p, 'w'), indent=2)
PY

echo "== Starting anvil fork of ${FORK_NETWORK} on port ${ANVIL_PORT}"
pkill -f "anvil.*--port ${ANVIL_PORT}" 2>/dev/null || true; sleep 1
anvil --fork-url "$FORK_RPC_URL" --chain-id 31337 --port "$ANVIL_PORT" \
  --auto-impersonate --silent & ANVIL_PID=$!
sleep 8

AC=$(python3 -c "import json;print(json.load(open('deployments/anvil/deployments.json'))['WildcatArchController'])")
OWNER=$(cast call "$AC" 'owner()(address)' --rpc-url "$RPC")
cast rpc anvil_setBalance "$OWNER" 0x8AC7230489E80000 --rpc-url "$RPC" >/dev/null
echo "== ArchController: ${AC}"
echo "== Current owner: ${OWNER}"

if [[ "${1:-}" == "--full" && "$FORK_NETWORK" == "mainnet" ]]; then
  # Headless mode executes as the impersonated real owner.
  EXECUTOR="$OWNER"
else
  # Sepolia uses the same EOA path as the live ceremony. The test account is
  # authorized in the helper's mapping on this disposable fork, then the
  # plan's first and last cards perform the real reclaim/restore calls.
  EXECUTOR="${TEST_ACCOUNT:-0x70997970C51812dc3A010C7d01b50e0d17dc79C8}"
  cast rpc anvil_setBalance "$EXECUTOR" 0x8AC7230489E80000 --rpc-url "$RPC" >/dev/null
  if [[ "$FORK_NETWORK" == "sepolia" ]]; then
    HELPER=$(python3 -c "import json;print(json.load(open('deployments/anvil/deployments.json'))['MockArchControllerOwner'])")
    AUTHORIZED_SLOT=$(cast index address "$EXECUTOR" 0)
    cast rpc anvil_setStorageAt "$HELPER" "$AUTHORIZED_SLOT" \
      0x0000000000000000000000000000000000000000000000000000000000000001 \
      --rpc-url "$RPC" >/dev/null
    echo "== Test executor authorized in helper; the plan will reclaim and restore ownership: ${EXECUTOR}"
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
done
bash script/deploy/v2-5/07-generate-plan.sh

PLAN="deployments/anvil/plan-${RELEASE_TAG}.json"

if [[ "${1:-}" == "--full" ]]; then
  echo "== --full: executing plan as impersonated owner"
  node scripts/plan.js execute --plan "$PLAN" --rpc "$RPC" \
    --impersonate "$EXECUTOR" --yes | tail -2
  RUN_STATE="deployments/anvil/run-state-${RELEASE_TAG}.json" RPC_URL="$RPC" \
    bash script/deploy/v2-5/08-finalize-inventory.sh | tail -3
  node scripts/plan.js verify --plan "$PLAN" \
    --run-state "deployments/anvil/run-state-${RELEASE_TAG}.json" --rpc "$RPC" | tail -1
  kill "$ANVIL_PID" 2>/dev/null || true
  echo "== Full rehearsal complete. Clean up with: rm -rf deployments/anvil"
  exit 0
fi

FUNDED_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
KEY_NOTE="(anvil account #1 — matches the default test executor)"
if [[ -n "${TEST_ACCOUNT:-}" ]]; then
  FUNDED_KEY="<the private key for ${EXECUTOR}>"
  KEY_NOTE=""
fi
cat <<NEXT

================================================================
Fork is RUNNING (pid ${ANVIL_PID}).  Plan: ${PLAN}
Plan executor: ${EXECUTOR}

Drive it from the frontend (EOA mode):
  1. cd deploy-ui && npm run dev
  2. Wallet: add network  RPC ${RPC}  chainId 31337
     Import the executor key ${KEY_NOTE}:
       ${FUNDED_KEY}
  3. Load ${PLAN} in the page (EOA mode), walk the cards.
  4. Export run-state, then:
       RUN_STATE=<exported file> RPC_URL=${RPC} \\
         bash script/deploy/v2-5/08-finalize-inventory.sh

Or headless: rerun with --full.
Stop fork: kill ${ANVIL_PID}    Clean up: rm -rf deployments/anvil
================================================================
NEXT
