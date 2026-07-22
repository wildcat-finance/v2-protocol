# v2.5 Sepolia-fork Anvil ceremony rehearsal

This is the canonical from-scratch rehearsal for the v2.5 Sepolia EOA
ceremony. It rebuilds the protocol and deployment artifacts, forks current
Sepolia state, regenerates the 38-card plan, executes it through a
digest-locked production build of `deploy-ui`, finalizes the local inventory,
and exercises the canary and handoff paths.

The fork RPC used here is `https://eth-sep.hinterlight.net`.

This walkthrough does not mutate Sepolia. It does mutate local Foundry build
outputs, browser state, and `deployments/anvil/`. The rehearsal script removes
any existing `deployments/anvil/` directory and kills an Anvil process matching
the selected port before it starts. Preserve anything valuable and use an
otherwise-unused port.

At the time this walkthrough was written, the reviewed protocol source was
`v2-protocol@bcab762` and the expected Sepolia-shaped plan was:

- 38 transactions: 12 deployments and 26 calls;
- card 1: helper `returnOwnership()`;
- cards 16-21: OpenTerm, FixedTerm, and PeriodicTerm registered on both the
  standard and revolving factories;
- cards 24-37: paired controller-factory/controller removal for seven
  superseded factories;
- card 38: `transferOwnership(helper)`; and
- no market-removal call.

Do not reuse those facts as a substitute for inspecting the newly generated
plan. If source or inventory changed, review the new shape before executing it.

## Acceptance criteria

The rehearsal passes only when all of the following are true:

- the full protocol test suite passes from a clean IR build;
- the deploy-profile release source builds from a clean deploy cache;
- the generated Anvil plan validates and has the reviewed 38-card shape;
- the locked UI accepts the embedded package and all 38 predicates turn green;
- a page reload resumes from verified on-chain state;
- the exported run-state passes independent CLI verification;
- inventory finalization, validation, lint, and reconciliation are green;
- ArchController ownership is restored to the Sepolia helper;
- both standard and revolving canary markets deploy, close, and settle; and
- the local handoff generates and passes `--check`.

Prior fork runs are historical evidence only. A fresh pass against the source
being proposed for Sepolia is the release gate.

## Stop conditions

Stop and preserve the fork if any of these occurs:

- either upstream or local RPC reports an unexpected chain ID;
- a build, test, plan validator, inventory check, or reconciliation fails;
- the plan shape differs from the reviewed shape without an explained source
  change;
- the connected wallet is not the exact plan executor;
- a transaction reverts or a predicate remains red;
- the UI reports a package/hash mismatch or a fatal halt;
- ownership is not back with the helper after card 38; or
- independent run-state verification fails.

Do not skip a card, edit the plan/package/run-state, clear browser storage, or
restart the fork to make a failure disappear. Record the failure against the
same fork state first.

## 1. Prepare the release shell

Open a terminal at the `v2-protocol` repository root:

```bash
cd /Users/kethcode/wildcat/mono/v2-protocol

export REPO_ROOT="$(pwd -P)"
export FOUNDRY_PROFILE=deploy
export FORK_NETWORK=sepolia
export FORK_RPC_URL=https://eth-sep.hinterlight.net
export ANVIL_PORT=8547
export RPC_URL="http://127.0.0.1:${ANVIL_PORT}"
export DEPLOYMENTS_NETWORK=anvil
export RELEASE_TAG=v2-5
export OWNER_MODE=plan

export PLAN="$REPO_ROOT/deployments/anvil/plan-$RELEASE_TAG.json"
export PACKAGE="$REPO_ROOT/deployments/anvil/ceremony-$RELEASE_TAG-eoa.json"
export RUN_STATE="$REPO_ROOT/deployments/anvil/run-state-$RELEASE_TAG.json"
```

Record the source and worktree before doing anything destructive:

```bash
git branch --show-current
git rev-parse HEAD
git status --short
```

The source revision is an operator input. If it is not the reviewed revision,
stop long enough to understand the delta; do not blindly reset a dirty tree.
Generated Sepolia plan entries or pending inventory are not inputs to this
Anvil run and must not be staged as source.

Confirm the required tools resolve:

```bash
forge --version
cast --version
anvil --version
node --version
npm --version
jq --version
lsof -v >/dev/null
```

## 2. Protect local artifacts and the selected port

The setup script will run `rm -rf deployments/anvil` and a port-specific
`pkill`. Move an existing Anvil artifact directory out of the way first:

```bash
if [[ -e deployments/anvil ]]; then
  export ANVIL_ARTIFACT_BACKUP="${TMPDIR:-/tmp}/wildcat-anvil-before-$(date -u +%Y%m%dT%H%M%SZ)"
  mv deployments/anvil "$ANVIL_ARTIFACT_BACKUP"
  echo "Preserved prior Anvil artifacts at $ANVIL_ARTIFACT_BACKUP"
fi
```

Confirm the chosen port is unused. If this prints a listener, choose another
port and recompute `RPC_URL`; do not let the script kill an unrelated process.

```bash
lsof -nP -iTCP:"$ANVIL_PORT" -sTCP:LISTEN
```

## 3. Rebuild and test from the top

Clear both profiles used by the release gate, then run the complete protocol
suite and the release-specific deploy build:

```bash
FOUNDRY_PROFILE=ir forge clean
FOUNDRY_PROFILE=deploy forge clean

FOUNDRY_PROFILE=ir forge test
FOUNDRY_PROFILE=deploy forge build --sizes \
  src script/common script/deploy/v2-5
```

The final command must use the `deploy` profile. Do not substitute default
artifacts: the default-profile revolving factory exceeds EIP-170, while the
ceremony and its plan validator require `deploy-out` artifacts.

Install and test the ceremony UI from its lockfile:

```bash
(
  cd deploy-ui
  npm ci
  npm test
)
```

Run the static local release checks before creating the fork:

```bash
node scripts/factory-inventory.js validate --network sepolia
node scripts/factory-inventory.js lint --network sepolia
bash -n script/deploy/v2-5/rehearse.sh
bash -n script/deploy/v2-5/08-finalize-inventory.sh
bash -n script/deploy/v2-5/09-canary-market.sh
```

## 4. Preflight the upstream RPC

Confirm the supplied endpoint is Sepolia and record its current head:

```bash
test "$(cast chain-id --rpc-url "$FORK_RPC_URL")" = "11155111"
export UPSTREAM_BLOCK="$(cast block-number --rpc-url "$FORK_RPC_URL")"
echo "Upstream Sepolia head before fork: $UPSTREAM_BLOCK"
```

This walkthrough forks current head rather than a pinned block because
`rehearse.sh` does not currently expose `--fork-block-number`. Record the
actual local fork block after startup. For a byte-for-byte rerun, add explicit
fork-block support to the script and review that change before relying on it.

## 5. Start the fork and generate a fresh plan

Run the setup path without `--full`; the browser, not the CLI, is the ceremony
executor for this rehearsal:

```bash
FORK_NETWORK="$FORK_NETWORK" \
FORK_RPC_URL="$FORK_RPC_URL" \
ANVIL_PORT="$ANVIL_PORT" \
RELEASE_TAG="$RELEASE_TAG" \
  bash script/deploy/v2-5/rehearse.sh
```

The script does the following:

1. seeds `deployments/anvil/` from the current Sepolia deployment files;
2. rewrites the seeded inventory identity to Anvil chain `31337`;
3. starts Anvil with `--auto-impersonate`;
4. funds the helper owner and Anvil account 1;
5. authorizes Anvil account 1 in the forked helper storage; and
6. regenerates steps 01-07 and assembles a fresh plan.

Ignore the script footer's raw-plan development-UI shortcut. Continue below
with an embedded ceremony package and a production build, which is the shape
that matters for Sepolia.

Capture and verify the exact listener process so cleanup does not rely on
another pattern match:

```bash
export ANVIL_PID="$(lsof -tiTCP:"$ANVIL_PORT" -sTCP:LISTEN)"
test -n "$ANVIL_PID"
ps -p "$ANVIL_PID" -o pid=,command=
```

Re-export the execution context because environment changes inside the script
do not propagate back to this shell:

```bash
export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=anvil
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export RPC_URL="http://127.0.0.1:${ANVIL_PORT}"
export EXPECTED_EXECUTOR="$(jq -r '.expectedExecutor' "$PLAN")"
export ARCH_CONTROLLER="$(jq -r '.WildcatArchController' deployments/anvil/deployments.json)"
export HELPER_OWNER="$(jq -r '.MockArchControllerOwner' deployments/anvil/deployments.json)"
export FORK_BLOCK="$(cast block-number --rpc-url "$RPC_URL")"

echo "Anvil pid: $ANVIL_PID"
echo "Fork block: $FORK_BLOCK"
echo "Plan executor: $EXPECTED_EXECUTOR"
echo "ArchController: $ARCH_CONTROLLER"
echo "Helper owner: $HELPER_OWNER"
```

Expected executor: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`.

## 6. Verify fork state and plan shape

Confirm chain, ownership, helper authorization, and inventory before any card
is sent:

```bash
test "$(cast chain-id --rpc-url "$RPC_URL")" = "31337"

cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL"
cast call "$HELPER_OWNER" \
  'authorizedAccounts(address)(bool)' \
  "$EXPECTED_EXECUTOR" \
  --rpc-url "$RPC_URL"

node scripts/factory-inventory.js validate --network anvil
node scripts/factory-inventory.js lint --network anvil
node scripts/factory-inventory.js reconcile \
  --network anvil \
  --rpc-url "$RPC_URL"
```

The owner must be `HELPER_OWNER`, authorization must be `true`, and reconcile
must be green.

Validate the newly generated plan and assert the reviewed shape mechanically:

```bash
node scripts/plan.js validate --plan "$PLAN"

jq -e '
  .foundryProfile == "deploy" and
  .network == "anvil" and
  .chainId == 31337 and
  .release == "v2-5" and
  (.transactions | length) == 38 and
  ([.transactions[] | select(.kind == "deploy")] | length) == 12 and
  ([.transactions[] | select(.kind == "call")] | length) == 26 and
  .transactions[0].id == "reclaim-arch-controller-ownership" and
  .transactions[0].functionSignature == "returnOwnership()" and
  .transactions[-1].id == "restore-arch-controller-ownership" and
  .transactions[-1].functionSignature == "transferOwnership(address)" and
  ([.transactions[] |
    select(.id | test("^add-(standard|revolving)-(open|fixed|periodic)-term-template$"))
  ] | length) == 6 and
  ([.transactions[] | select(.id | startswith("remove-superseded-"))] | length) == 14 and
  all(.transactions[]; (.functionSignature // "") != "removeMarket(address)")
' "$PLAN"

test "$(node scripts/factory-inventory.js deactivation-targets \
  --network anvil | jq 'length')" = "7"
```

Print the card ledger for human review:

```bash
jq -r '
  .transactions | to_entries[] |
  [(.key + 1), .value.kind, .value.id, (.value.functionSignature // "deploy")] |
  @tsv
' "$PLAN"
```

Review the seven deactivation target addresses against the seeded inventory.
Passing a count alone is not sufficient:

```bash
node scripts/factory-inventory.js deactivation-targets --network anvil | jq .
```

## 7. Build the locked rehearsal site

Generate the digest-bound EOA package from the fresh plan:

```bash
node scripts/plan.js ceremony-package \
  --plan "$PLAN" \
  --mode eoa \
  --out "$PACKAGE"

jq '{
  digest,
  mode: .payload.mode,
  network: .payload.network,
  chainId: .payload.chainId,
  release: .payload.release,
  planHash: .payload.artifacts.plan.hash
}' "$PACKAGE"
```

Record the full digest and call-time fingerprint printed by the command. Build
from the UI lockfile installation with the absolute package path:

```bash
(
  cd deploy-ui
  CEREMONY_PACKAGE="$PACKAGE" npm run build
)
```

Start the production preview in a second terminal and leave it open:

```bash
cd /Users/kethcode/wildcat/mono/v2-protocol/deploy-ui
npm exec -- vite preview --host 127.0.0.1 --port 4173 --strictPort
```

Open `http://127.0.0.1:4173/`. The page must open directly in locked EOA mode;
there must be no plan picker or mode switch. Confirm the displayed package
digest/fingerprint matches the output recorded above.

## 8. Connect the disposable Anvil executor

Configure the browser wallet for:

| Field | Value |
| --- | --- |
| Network | Anvil v2.5 rehearsal |
| RPC URL | `http://127.0.0.1:8547` |
| Chain ID | `31337` |
| Currency symbol | `ETH` |

If you selected a different `ANVIL_PORT`, use the corresponding `RPC_URL`
instead of the table's `8547` default.

If the wallet already has a chain-31337 localhost entry, temporarily point
that entry at the selected `RPC_URL` rather than creating a conflicting
duplicate.

Import Anvil account 1 using its public development key:

```text
0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

It must resolve to:

```text
0x70997970C51812dc3A010C7d01b50e0d17dc79C8
```

This is a universally known Anvil key. Use it only on the disposable local
fork; never fund it or use it on a public network.

Before connecting, confirm the account has no pending/local nonce divergence:

```bash
cast nonce "$EXPECTED_EXECUTOR" --block latest --rpc-url "$RPC_URL"
cast nonce "$EXPECTED_EXECUTOR" --block pending --rpc-url "$RPC_URL"
```

The values must match. Do not send unrelated wallet transactions during the
ceremony.

## 9. Walk all 38 cards

Connect the exact executor and confirm the UI shows:

- EOA mode;
- network `anvil`, chain `31337`;
- release `v2-5`;
- the recorded package fingerprint; and
- 38 plan transactions.

Then execute one card at a time. For every card:

1. read the description, target, value, decoded arguments, and predicate;
2. confirm the wallet is still on chain `31337` with the expected executor;
3. send exactly the UI-prepared transaction;
4. wait for the receipt; and
5. require the predicate to turn green before advancing.

Use these checkpoints:

| After card | Expected state | Operator action |
| --- | --- | --- |
| 1 | Executor temporarily owns ArchController | Export and rename a checkpoint run-state. |
| 13 | All 12 release contracts deployed | Export, rename, then reload the page and prove resume. |
| 23 | Six templates added and both new factories registered | Export and rename a checkpoint. |
| 37 | Seven superseded factories removed from both roles | Export before the compensating ownership return. |
| 38 | Helper owns ArchController again | Export the final run-state. |

The browser always downloads `run-state-v2-5.json`; rename intermediate files
with their card number so they do not overwrite or obscure the final export.

The reload after card 13 is part of acceptance. The page must re-read prior
receipts/predicates and resume at card 14 without asking for a different plan.

The current fatal screen does not expose the export button. That makes the
checkpoint exports operationally important. If a fatal halt occurs, preserve
the most recent checkpoint, capture the displayed error and browser console,
and leave Anvil running. Do not clear local storage or rebuild the site before
diagnosis.

## 10. Save and independently verify the final run-state

Copy the final browser download into the exact release path without editing
its JSON. Replace the placeholder with the real download path:

```bash
test ! -e "$RUN_STATE"
cp /absolute/path/to/downloaded/run-state-v2-5.json "$RUN_STATE"
```

Verify cardinality and receipt provenance through the independent CLI:

```bash
test "$(jq 'length' "$RUN_STATE")" = "38"

node scripts/plan.js verify \
  --plan "$PLAN" \
  --run-state "$RUN_STATE" \
  --rpc "$RPC_URL"
```

Confirm the final owner is the helper:

```bash
cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL"
echo "$HELPER_OWNER"
```

Do not continue if those addresses differ.

## 11. Finalize and reconcile the local inventory

Step 08 applies the receipt-derived addresses and creation blocks to the local
Anvil deployment files:

```bash
RUN_STATE="$RUN_STATE" RPC_URL="$RPC_URL" \
  bash script/deploy/v2-5/08-finalize-inventory.sh
```

Then run all post-finalization checks explicitly:

```bash
node scripts/factory-inventory.js validate --network anvil
node scripts/factory-inventory.js lint --network anvil
node scripts/factory-inventory.js reconcile \
  --network anvil \
  --rpc-url "$RPC_URL"
```

Reconciliation must be green. Inspect the final aliases and lifecycle records;
the seven superseded factories must be unregistered but their historical
`indexed` policy must remain unchanged.

## 12. Run the standard and revolving canaries

This phase is separate from the 38-card ceremony. It uses direct mode only
after inventory finalization.

Use the disposable executor as the borrower and the seeded Sepolia mock token
as the canary asset:

```bash
export BORROWER="$EXPECTED_EXECUTOR"
export CANARY_ASSET="$(jq -r '.["MockERC20:Token"]' deployments/anvil/deployments.json)"

cast send "$ARCH_CONTROLLER" \
  'registerBorrower(address)' \
  "$BORROWER" \
  --from "$HELPER_OWNER" \
  --unlocked \
  --rpc-url "$RPC_URL"

cast call "$ARCH_CONTROLLER" \
  'isRegisteredBorrower(address)(bool)' \
  "$BORROWER" \
  --rpc-url "$RPC_URL"
```

The last call must return `true`. Run the canary with no Anvil private-key
environment override so Foundry uses the unlocked borrower:

```bash
export OWNER_MODE=direct
unset PVT_KEY_ANVIL

bash script/deploy/v2-5/09-canary-market.sh
```

Require output for both standard and revolving markets showing a nonzero
deposit, closure, and nonzero finalized withdrawal. A canary failure does not
invalidate already completed ceremony receipts, but it does fail the rehearsal
acceptance gate.

## 13. Exercise the downstream handoff path

Generate and validate an Anvil-only handoff:

```bash
node scripts/generate-handoff.js \
  --network anvil \
  --release "$RELEASE_TAG"

node scripts/generate-handoff.js \
  --network anvil \
  --release "$RELEASE_TAG" \
  --check
```

Review `deployments/anvil/handoff-v2-5.{json,md}` for the 12 release contracts,
canonical standard/revolving/wrapper addresses, receipt-derived start blocks,
and every historical factory generation. This fork handoff proves tooling; it
is not a Sepolia address source and must not be propagated downstream.

Finish with one more independent plan verification and reconciliation:

```bash
node scripts/plan.js verify \
  --plan "$PLAN" \
  --run-state "$RUN_STATE" \
  --rpc "$RPC_URL"

node scripts/factory-inventory.js reconcile \
  --network anvil \
  --rpc-url "$RPC_URL"
```

## 14. Preserve evidence and clean up safely

Record the evidence before stopping anything:

```bash
git rev-parse HEAD
echo "Fork block: $FORK_BLOCK"
echo "Package digest: $(jq -r '.digest' "$PACKAGE")"
git status --short
```

Preserve the complete Anvil artifact directory outside the repository instead
of deleting it immediately:

```bash
ANVIL_EVIDENCE_ROOT="${TMPDIR:-/tmp}"
export ANVIL_RESULT_DIR="${ANVIL_EVIDENCE_ROOT%/}/wildcat-v2-5-anvil-result-$(date -u +%Y%m%dT%H%M%SZ)"
test ! -e "$ANVIL_RESULT_DIR" &&
  mv deployments/anvil "$ANVIL_RESULT_DIR" &&
  test -d "$ANVIL_RESULT_DIR" &&
  test ! -e deployments/anvil &&
  echo "Rehearsal evidence: $ANVIL_RESULT_DIR"
```

`mv` is silent on success. The chained checks ensure the success message is
printed only after the result directory exists and the repository copy no
longer does. `${ANVIL_EVIDENCE_ROOT%/}` also removes the trailing slash that
macOS normally includes in `TMPDIR`.

Stop the Vite preview with `Ctrl-C` in its terminal. Stop only the Anvil PID
captured above:

```bash
kill "$ANVIL_PID"
sleep 1
test -z "$(lsof -tiTCP:"$ANVIL_PORT" -sTCP:LISTEN)"
```

If a prior `deployments/anvil/` directory was preserved in section 2, restore
it only after the new result directory has been moved away:

```bash
if [[ -n "${ANVIL_ARTIFACT_BACKUP:-}" && -e "$ANVIL_ARTIFACT_BACKUP" ]]; then
  test ! -e deployments/anvil
  mv "$ANVIL_ARTIFACT_BACKUP" deployments/anvil
fi
```

The canary creates Foundry broadcast records. Keep them with the rehearsal
evidence until review is complete; do not bulk-delete a shared `broadcast/` or
cache directory. The pre-existing generated Sepolia outputs must remain
untouched.

## Handoff to the live Sepolia walkthrough

After this rehearsal passes, continue with
[`sepolia-v2-5-first-deployment.md`](./sepolia-v2-5-first-deployment.md). Start
that run from a fresh Sepolia plan generation: Anvil addresses, run-state,
inventory, and handoff files are never inputs to the public deployment.
