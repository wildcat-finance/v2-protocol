# v2.5 Sepolia-fork Anvil ceremony rehearsal

This is the required from-scratch rehearsal before a live Sepolia deployment. It forks current Sepolia state, generates activation from the source under review, executes it through the locked EOA UI, finalizes and validates the new generation, then generates and executes retirement as a separate ceremony.

The default fork RPC is `https://eth-sep.hinterlight.net`. This walkthrough does not mutate Sepolia. It does replace local `deployments/anvil/`, stops an Anvil process using the selected port, writes Foundry outputs, and stores browser progress. Preserve anything useful before starting.

`rehearse.sh --full` runs the same activation, finalization, retirement-generation, retirement, and reconciliation sequence headlessly. That proves the engine, but it does not prove wallet connection, package fingerprint review, card presentation, browser resume, or exported run-state handling. The locked-UI run remains the release gate.

## Acceptance criteria

The rehearsal passes only when all of the following are true:

- the full deploy-profile protocol test suite passes;
- release source and deployment scripts build with the deploy profile and production contracts fit EIP-170;
- activation has 27 cards on the Sepolia-shaped fork: 15 deployments and 12 calls;
- activation reclaims ownership first, restores it last, registers six templates and two factories, and removes no factory role or market;
- every activation predicate passes through the locked UI and a reload resumes only after on-chain re-verification;
- the unedited activation run-state passes independent verification and inventory finalization;
- the standard and revolving canaries pass and the downstream handoff passes `--check` before retirement is generated;
- retirement is generated from the finalized post-activation inventory and has two ordered removals per superseded factory, with no market removal;
- every retirement predicate passes through a separate locked package and run-state;
- retirement finalization and inventory reconciliation are green; and
- `MockArchControllerOwner` owns the ArchController after both ceremonies.

The current Sepolia inventory produces nine retirement targets. That means 18 removals plus reclaim and return, or 20 retirement cards. This count is evidence from the current inventory, not a hardcoded release assumption.

## Stop conditions

Stop and preserve the fork if the source revision is wrong, either RPC reports an unexpected chain ID, archive reads fail, a build or test fails, plan validation fails, the connected wallet is not the exact executor, a transaction reverts, a predicate stays red, the package digest changes, inventory reconciliation fails, or ownership is not returned to the helper.

Do not skip a card, edit a plan or run-state, clear browser storage, or create a new fork to hide a failure. Record the failure against the existing fork first.

## 1. Prepare and verify source

```bash
cd /Users/kethcode/wildcat/mono/v2-protocol

export REPO_ROOT="$(pwd -P)"
export FOUNDRY_PROFILE=deploy
export FORK_NETWORK=sepolia
export FORK_RPC_URL=https://eth-sep.hinterlight.net
unset FORK_FALLBACK_RPC_URL
export ANVIL_PORT=8547
export ANVIL_STARTUP_TIMEOUT=120
export RPC_URL="http://127.0.0.1:${ANVIL_PORT}"
export DEPLOYMENTS_NETWORK=anvil
export RELEASE_TAG=v2-5
export OWNER_MODE=plan

export PLAN="$REPO_ROOT/deployments/anvil/plan-v2-5.json"
export PACKAGE="$REPO_ROOT/deployments/anvil/ceremony-v2-5-eoa.json"
export RUN_STATE="$REPO_ROOT/deployments/anvil/run-state-v2-5.json"
export RETIREMENT_PLAN="$REPO_ROOT/deployments/anvil/plan-v2-5-retirement.json"
export RETIREMENT_PACKAGE="$REPO_ROOT/deployments/anvil/ceremony-v2-5-retirement-eoa.json"
export RETIREMENT_RUN_STATE="$REPO_ROOT/deployments/anvil/run-state-v2-5-retirement.json"
```

Record the source before running the launcher:

```bash
git branch --show-current
git rev-parse HEAD
git status --short
```

If `deployments/anvil/` contains useful evidence, move it to an operator-selected directory now. The launcher deliberately replaces it.

Confirm tools and run the cold gates:

```bash
forge --version
cast --version
anvil --version
node --version
npm --version
jq --version

FOUNDRY_PROFILE=deploy forge test
FOUNDRY_PROFILE=deploy forge build --sizes src script/common script/deploy/v2-5

(
  cd deploy-ui
  npm ci
  npm test
)
```

Do not use `forge fmt` as part of this ceremony. Formatting is not a release gate and the repository intentionally preserves its existing Solidity style.

## 2. Start the pinned fork and generate activation

```bash
FORK_NETWORK="$FORK_NETWORK" \
FORK_RPC_URL="$FORK_RPC_URL" \
ANVIL_PORT="$ANVIL_PORT" \
bash script/deploy/v2-5/rehearse.sh
```

Wait for the explicit RPC-ready message. The launcher verifies the Sepolia chain ID, proves historical storage access, pins one block, seeds `deployments/anvil/`, authorizes disposable Anvil account 1 in the helper, generates steps 01 through 07, and leaves Anvil running.

Record the process and fork identity:

```bash
export ANVIL_PID="$(cat deployments/anvil/anvil.pid)"
export FORK_BLOCK="$(cat deployments/anvil/anvil-fork-block)"
export ARCH_CONTROLLER="$(jq -r '.WildcatArchController' deployments/anvil/deployments.json)"
export HELPER_OWNER="$(jq -r '.MockArchControllerOwner' deployments/anvil/deployments.json)"
export EXPECTED_EXECUTOR="$(jq -r '.expectedExecutor' "$PLAN")"

test "$(cast chain-id --rpc-url "$RPC_URL")" = "31337"
test -s deployments/anvil/anvil-state.json
test -f deployments/anvil/anvil.log
kill -0 "$ANVIL_PID"
```

The expected executor is Anvil account 1, `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`.

## 3. Review activation before signing

Validate inventory and plan:

```bash
node scripts/factory-inventory.js validate --network anvil
node scripts/factory-inventory.js lint --network anvil
node scripts/factory-inventory.js reconcile --network anvil --rpc-url "$RPC_URL"
node scripts/plan.js validate --plan "$PLAN"
node scripts/factory-inventory.js validate-activation-plan --network anvil --plan "$PLAN"
```

Assert the exact activation shape:

```bash
jq -e '
  .foundryProfile == "deploy" and
  .network == "anvil" and
  .chainId == 31337 and
  .release == "v2-5" and
  (.transactions | length) == 27 and
  ([.transactions[] | select(.kind == "deploy")] | length) == 15 and
  ([.transactions[] | select(.kind == "call")] | length) == 12 and
  .transactions[0].id == "reclaim-arch-controller-ownership" and
  .transactions[-1].id == "restore-arch-controller-ownership" and
  ([.transactions[] | select(.functionSignature == "addHooksTemplate(address,string,address,address,uint80,uint16)")] | length) == 6 and
  ([.transactions[] | select(.functionSignature == "registerControllerFactory(address)")] | length) == 2 and
  ([.transactions[] | select(.functionSignature == "registerWithArchController()")] | length) == 2 and
  all(.transactions[]; (.functionSignature // "") != "removeControllerFactory(address)") and
  all(.transactions[]; (.functionSignature // "") != "removeController(address)") and
  all(.transactions[]; (.functionSignature // "") != "removeMarket(address)")
' "$PLAN"
```

Print and review every card:

```bash
jq -r '.transactions | to_entries[] | [(.key + 1), .value.kind, .value.id, (.value.functionSignature // "deploy")] | @tsv' "$PLAN"
```

The deployment list must include `WildcatBorrowerIdentityRegistry`, `AccessListRoleProviderFactory`, `WildcatMarketRevolving` init-code storage part 1, and init-code storage part 2. The full activation plan must contain 15 deployments.

## 4. Build the locked activation site

```bash
node scripts/plan.js ceremony-package --plan "$PLAN" --mode eoa --out "$PACKAGE"

(
  cd deploy-ui
  CEREMONY_PACKAGE="$PACKAGE" npm run build
)
```

Record the printed digest and short fingerprint. Serve the built site without rebuilding it:

```bash
cd /Users/kethcode/wildcat/mono/v2-protocol/deploy-ui
npm exec -- vite preview --host 127.0.0.1 --port 4173 --strictPort
```

Open `http://127.0.0.1:4173/`. It must open in locked EOA mode with no plan picker or mode switch. The displayed digest and fingerprint must match the independently recorded values.

Configure the browser wallet for RPC `http://127.0.0.1:8547`, chain ID `31337`, and import the public Anvil account 1 key:

```text
0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

This key is public and disposable. Never fund or use it on a public network.

## 5. Execute and finalize activation

Before card 1, confirm the helper owns the ArchController and the executor is authorized:

```bash
test "$(cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$HELPER_OWNER" | tr '[:upper:]' '[:lower:]')"
cast call "$HELPER_OWNER" 'authorizedAccounts(address)(bool)' "$EXPECTED_EXECUTOR" --rpc-url "$RPC_URL"
```

Walk all 27 cards in order. Review the plain-English action, target, decoded arguments, and predicate before sending. Wait for the receipt and green predicate before advancing. Card 1 reclaims ownership for the test executor. Card 27 returns ownership to the helper.

At a reviewed midpoint, export a checkpoint, reload the exact same page and fork, reconnect the same account, and choose the resume path. Stored progress must remain unverified until receipts and predicates are reread from the connected fork.

After card 27, confirm ownership has returned:

```bash
test "$(cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$HELPER_OWNER" | tr '[:upper:]' '[:lower:]')"
```

Export the final unedited activation run-state to `$RUN_STATE` and verify it independently:

```bash
test "$(jq 'length' "$RUN_STATE")" = "27"
node scripts/plan.js verify --plan "$PLAN" --run-state "$RUN_STATE" --rpc "$RPC_URL"

RUN_STATE="$RUN_STATE" RPC_URL="$RPC_URL" bash script/deploy/v2-5/08-finalize-inventory.sh

node scripts/factory-inventory.js validate --network anvil
node scripts/factory-inventory.js lint --network anvil
node scripts/factory-inventory.js reconcile --network anvil --rpc-url "$RPC_URL"
```

Do not generate retirement until this reconciliation is green.

## 6. Validate the activated generation

Run both canaries with deliberately selected inputs. On the Sepolia-shaped fork, use the seeded mock token and the disposable executor only after confirming the borrower is registered and funded:

```bash
export BORROWER="$EXPECTED_EXECUTOR"
export CANARY_ASSET="$(jq -r '."MockERC20:Token"' deployments/anvil/deployments.json)"
export OWNER_MODE=direct
bash script/deploy/v2-5/09-canary-market.sh
export OWNER_MODE=plan
```

Require both standard and revolving canaries to deploy, accept a deposit, close, and finalize a withdrawal.

Generate and check the handoff:

```bash
node scripts/generate-handoff.js --network anvil --release v2-5
node scripts/generate-handoff.js --network anvil --release v2-5 --check
```

Confirm the handoff includes the identity registry, AccessList role-provider factory, both hooks factories, both revolving init-code storage addresses, all four lens components, and all supported templates.

## 7. Generate retirement from finalized state

```bash
export EXPECTED_EXECUTOR
bash script/deploy/v2-5/retirement/01-generate-plan.sh

node scripts/plan.js validate --plan "$RETIREMENT_PLAN"
node scripts/factory-inventory.js validate-retirement-plan --network anvil --plan "$RETIREMENT_PLAN"
```

Review the dynamic target list and plan ledger:

```bash
node scripts/factory-inventory.js deactivation-targets --network anvil | jq .
jq -r '.transactions | to_entries[] | [(.key + 1), .value.id, .value.functionSignature, .value.args[0]] | @tsv' "$RETIREMENT_PLAN"
```

The current inventory should produce nine targets and 20 cards. Card 1 reclaims ownership, cards 2 through 19 remove two roles from nine factories, and card 20 returns ownership. For each address, `removeControllerFactory(address)` must appear immediately before `removeController(address)`. There must be no deployment, registration, or `removeMarket(address)` call.

## 8. Build and execute the separate retirement site

```bash
node scripts/plan.js ceremony-package --plan "$RETIREMENT_PLAN" --mode eoa --out "$RETIREMENT_PACKAGE"

(
  cd deploy-ui
  CEREMONY_PACKAGE="$RETIREMENT_PACKAGE" npm run build
)
```

Restart the production preview only after the activation package is no longer being used. Record and compare the new retirement digest and fingerprint. The release must read `v2-5-retirement`. Browser progress from activation is not retirement progress.

Walk every retirement card, waiting for its receipt and predicate. Confirm the helper owns the ArchController after the final card. Export the unedited retirement run-state to `$RETIREMENT_RUN_STATE`, then verify and finalize it:

```bash
test "$(jq 'length' "$RETIREMENT_RUN_STATE")" = "20"
node scripts/plan.js verify --plan "$RETIREMENT_PLAN" --run-state "$RETIREMENT_RUN_STATE" --rpc "$RPC_URL"

RUN_STATE="$RETIREMENT_RUN_STATE" RPC_URL="$RPC_URL" bash script/deploy/v2-5/retirement/02-finalize-inventory.sh

node scripts/factory-inventory.js validate --network anvil
node scripts/factory-inventory.js lint --network anvil
node scripts/factory-inventory.js reconcile --network anvil --rpc-url "$RPC_URL"
```

Inspect the ArchController registries and confirm no market was removed. Existing markets from retired factories remain registered and usable; only new origination through those factories is disabled.

## 9. Preserve evidence and stop the fork

Preserve the reviewed source revision, fork block, plans, package digests, UI fingerprints, activation and retirement run-states, transaction hashes, Anvil log and state, finalized inventory, canary output, and handoff results in an operator-selected evidence directory.

Stop only the process recorded by the launcher:

```bash
kill "$(cat deployments/anvil/anvil.pid)"
```

If Anvil crashes before the run is complete, use the preserved state instead of generating a new plan:

```bash
FORK_NETWORK=sepolia FORK_RPC_URL=https://eth-sep.hinterlight.net ANVIL_PORT=8547 bash script/deploy/v2-5/rehearse.sh --resume
```

## Emergency ownership return

This is an abort procedure, not a way to continue after a failed card. First preserve the page, browser state, run-state export, last transaction hash, logs, and exact error. Check `owner()` before sending anything. If the disposable executor still owns the ArchController, return it to the helper using the reviewed Anvil signing path, record the recovery hash, and stop the ceremony. Do not fabricate a completed run-state or finalize inventory after out-of-plan recovery.
