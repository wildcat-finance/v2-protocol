# v2.5 Sepolia-fork Anvil rehearsal

This rehearsal forks current Sepolia state, migrates to the replacement
authority-helper model, generates the v2.5 activation plan, and leaves a pinned
Anvil process for the locked-UI walkthrough. `--full` also executes activation,
finalizes inventory, runs the standard and revolving canaries, validates the
handoff, executes retirement, refreshes the handoff, and reconciles the result.

It never mutates Sepolia. It deliberately replaces local
`deployments/anvil/` and stops any Anvil process on the selected port.

## Acceptance criteria

- authority migration phases contain 5, 3, and 3 verified transactions;
- both the old wallet and disposable test executor remain authorized on the
  replacement helper;
- the helper owns the ArchController and holds its SphereX admin/operator
  roles;
- the helper is the SphereX engine default admin and operator;
- the old wallet no longer has a direct engine operator role;
- the ArchController retains the engine sender-adder role;
- activation has 24 cards: 14 deployments and 10 calls;
- eight activation owner calls are forwarded through the helper;
- the helper remains ArchController owner throughout activation;
- the standard and revolving canaries both deposit, queue, close, and finalize;
- the activation and post-retirement handoffs both pass `--check`;
- retirement contains two ordered forwarded removals per superseded factory,
  with no market removal or ownership handoff; and
- all plan predicates, inventory finalization, and reconciliation checks pass.

The current Sepolia inventory produces nine retirement targets, or 18 calls.
That count is live-state evidence, not a hardcoded release assumption.

## 1. Cold gates

```bash
cd /home/kethcode/wildcat/mono/v2-protocol

export FOUNDRY_PROFILE=deploy
export FORK_NETWORK=sepolia
export FORK_RPC_URL=https://eth-sep.hinterlight.net
unset FORK_FALLBACK_RPC_URL
export ANVIL_PORT=8547
export ANVIL_STARTUP_TIMEOUT=120
export RELEASE_TAG=v2-5
export PRODUCTION_SOLIDITY_BASELINE=49f891c93768f9986f985204c2f533c77c5e6f60

git branch --show-current
git rev-parse HEAD
git status --short
git diff --quiet "$PRODUCTION_SOLIDITY_BASELINE" -- src

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
  npm run build
)
```

Do not use `forge fmt` as a ceremony step. Formatting is not a release gate.

## 2. Start the pinned fork

Interactive locked-UI rehearsal:

```bash
FORK_NETWORK="$FORK_NETWORK" \
FORK_RPC_URL="$FORK_RPC_URL" \
ANVIL_PORT="$ANVIL_PORT" \
bash script/deploy/v2-5/rehearse.sh
```

Headless end-to-end proof:

```bash
FORK_NETWORK="$FORK_NETWORK" \
FORK_RPC_URL="$FORK_RPC_URL" \
ANVIL_PORT="$ANVIL_PORT" \
bash script/deploy/v2-5/rehearse.sh --full
```

The launcher:

1. pins one archive-readable Sepolia block;
2. seeds `deployments/anvil/`;
3. creates and executes the three authority-migration plans;
4. time-warps only the disposable fork through the one-hour SphereX delay;
5. finalizes the helper alias after the complete authority preflight;
6. generates and validates the 24-card activation plan; and
7. either leaves Anvil running or completes activation, canaries, handoff
   validation, retirement, and the final handoff refresh in `--full` mode.

The disposable new executor is Anvil account 1:
`0x70997970C51812dc3A010C7d01b50e0d17dc79C8`.

## 3. Inspect authority evidence

For an interactive run:

```bash
export RPC_URL="http://127.0.0.1:${ANVIL_PORT}"
export DEPLOYMENTS_NETWORK=anvil
export PLAN="$(pwd -P)/deployments/anvil/plan-v2-5.json"
export PACKAGE="$(pwd -P)/deployments/anvil/ceremony-v2-5-eoa.json"
export RUN_STATE="$(pwd -P)/deployments/anvil/run-state-v2-5.json"
export RETIREMENT_PLAN="$(pwd -P)/deployments/anvil/plan-v2-5-retirement.json"
export RETIREMENT_PACKAGE="$(pwd -P)/deployments/anvil/ceremony-v2-5-retirement-eoa.json"
export RETIREMENT_RUN_STATE="$(pwd -P)/deployments/anvil/run-state-v2-5-retirement.json"

export ARCH_CONTROLLER="$(jq -r '.WildcatArchController' deployments/anvil/deployments.json)"
export HELPER_OWNER="$(jq -r '.MockArchControllerOwner' deployments/anvil/deployments.json)"
export LEGACY_HELPER="$(jq -r '.MockArchControllerOwnerLegacy' deployments/anvil/deployments.json)"
export EXPECTED_EXECUTOR="$(jq -r '.expectedExecutor' "$PLAN")"

for phase in 1 2 3; do
  node scripts/plan.js verify \
    --plan "deployments/anvil/plan-authority-helper-phase-${phase}.json" \
    --run-state "deployments/anvil/run-state-authority-helper-phase-${phase}.json" \
    --rpc "$RPC_URL"
done

node scripts/authority-helper.js preflight \
  --network anvil \
  --rpc-url "$RPC_URL" \
  --expected-executor "$EXPECTED_EXECUTOR"
```

Confirm `LEGACY_HELPER` is the original Sepolia helper and is not equal to the
replacement helper. Do not remove the old wallet from the replacement helper.

## 4. Review activation

```bash
node scripts/factory-inventory.js validate --network anvil
node scripts/factory-inventory.js lint --network anvil
node scripts/factory-inventory.js reconcile --network anvil --rpc-url "$RPC_URL"
node scripts/plan.js validate --plan "$PLAN"
node scripts/factory-inventory.js validate-activation-plan \
  --network anvil --plan "$PLAN"

jq -e '
  def logical: (.forwardedCall // {target: .to, functionSignature, args});
  .network == "anvil" and
  .chainId == 31337 and
  .release == "v2-5" and
  (.transactions | length) == 24 and
  ([.transactions[] | select(.kind == "deploy")] | length) == 14 and
  ([.transactions[] | select(.kind == "call")] | length) == 10 and
  ([.transactions[] | select(.forwardedCall != null)] | length) == 8 and
  ([.transactions[] | logical | select(.functionSignature == "addHooksTemplate(address,string,address,address,uint80,uint16)")] | length) == 6 and
  ([.transactions[] | logical | select(.functionSignature == "registerControllerFactory(address)")] | length) == 2 and
  all(.transactions[]; .id != "reclaim-arch-controller-ownership") and
  all(.transactions[]; .id != "restore-arch-controller-ownership")
' "$PLAN"
```

Print every logical action:

```bash
jq -r '
  .transactions | to_entries[] |
  (.value.forwardedCall // {target: .value.to, functionSignature: .value.functionSignature}) as $call |
  [(.key + 1), .value.kind, .value.id, ($call.functionSignature // "deploy"), ($call.target // "")] | @tsv
' "$PLAN"
```

## 5. Locked-UI activation

```bash
node scripts/plan.js ceremony-package --plan "$PLAN" --mode eoa --out "$PACKAGE"
(
  cd deploy-ui
  CEREMONY_PACKAGE="$PACKAGE" npm run build
  npm exec -- vite preview --host 127.0.0.1 --port 4173 --strictPort
)
```

Use Anvil account 1's public disposable key:

```text
0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

Never fund or use that key on a public network.

Confirm the locked page shows the exact package digest, executor, chain, and 24
cards. Forwarded cards must display the logical ArchController or factory
target, inner selector, and decoded arguments, with the helper shown separately
as the transport.

Walk all 24 cards. At a reviewed midpoint, export a checkpoint, reload the same
site and fork, and prove resume rechecks receipts and predicates before enabling
the next transaction.

The helper must own the ArchController before, during, and after the plan.
Export the unedited run-state and finalize:

```bash
test "$(jq 'length' "$RUN_STATE")" = 24
node scripts/plan.js verify --plan "$PLAN" --run-state "$RUN_STATE" --rpc "$RPC_URL"
RUN_STATE="$RUN_STATE" RPC_URL="$RPC_URL" bash script/deploy/v2-5/08-finalize-inventory.sh

node scripts/factory-inventory.js validate --network anvil
node scripts/factory-inventory.js lint --network anvil
node scripts/factory-inventory.js reconcile --network anvil --rpc-url "$RPC_URL"
```

## 6. Canaries and handoff

```bash
export BORROWER="$EXPECTED_EXECUTOR"
export CANARY_ASSET="$(jq -r '."MockERC20:Token"' deployments/anvil/deployments.json)"
export OWNER_MODE=direct
bash script/deploy/v2-5/09-canary-market.sh
export OWNER_MODE=plan

node scripts/generate-handoff.js --network anvil --release v2-5
node scripts/generate-handoff.js --network anvil --release v2-5 --check
```

Require both standard and revolving canaries to deploy, accept a deposit,
close, and finalize a withdrawal. Do not generate retirement until the
activation, canaries, handoff, and reconciliation are accepted.

## 7. Separate retirement rehearsal

```bash
export EXPECTED_EXECUTOR
bash script/deploy/v2-5/retirement/01-generate-plan.sh

node scripts/plan.js validate --plan "$RETIREMENT_PLAN"
node scripts/factory-inventory.js validate-retirement-plan \
  --network anvil --plan "$RETIREMENT_PLAN"
```

The current inventory should produce 18 calls for nine targets. Every logical
`removeControllerFactory(address)` must immediately precede the matching
`removeController(address)`. All 18 calls go through the helper; there are no
reclaim, return, deployment, registration, or market-removal cards.

Build a separate locked retirement package, execute it, export its own
run-state, verify, and finalize:

```bash
node scripts/plan.js ceremony-package \
  --plan "$RETIREMENT_PLAN" --mode eoa --out "$RETIREMENT_PACKAGE"

test "$(jq 'length' "$RETIREMENT_RUN_STATE")" = 18
node scripts/plan.js verify \
  --plan "$RETIREMENT_PLAN" \
  --run-state "$RETIREMENT_RUN_STATE" \
  --rpc "$RPC_URL"

RUN_STATE="$RETIREMENT_RUN_STATE" RPC_URL="$RPC_URL" \
  bash script/deploy/v2-5/retirement/02-finalize-inventory.sh

node scripts/factory-inventory.js reconcile --network anvil --rpc-url "$RPC_URL"
node scripts/authority-helper.js preflight \
  --network anvil --rpc-url "$RPC_URL" --expected-executor "$EXPECTED_EXECUTOR"
```

## Resume and cleanup

After an Anvil crash, use `rehearse.sh --resume`. It restores the pinned state
without regenerating plans or changing browser progress.

After preserving evidence:

```bash
kill "$(cat deployments/anvil/anvil.pid)" 2>/dev/null || true
rm -rf deployments/anvil
```
