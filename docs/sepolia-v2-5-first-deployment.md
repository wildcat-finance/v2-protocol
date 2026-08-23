# v2.5 Sepolia first-deployment checklist

This is the operator walkthrough for the first live v2.5 deployment. It has
three distinct ceremonies:

1. rotate the Sepolia authority helper;
2. activate and validate the new v2.5 generation; and
3. retire superseded factory authority after the validation window.

Do not combine them. Complete
[anvil-v2-5-rehearsal.md](./anvil-v2-5-rehearsal.md) from the exact source
revision first.

## Fixed identity

| Role | Expected value |
| --- | --- |
| Network | Sepolia, chain ID `11155111` |
| Old executor, retained temporarily | `0xca732651410E915090d7A7D889A1E44eF4575fcE` |
| New executor | `0xca7007a75296b532ce1606d9e130eaa849800ca7` |
| Template fee recipient | `0xca732651410E915090d7A7D889A1E44eF4575fcE` |
| ArchController | `0xC003f20F2642c76B81e5e1620c6D8cdEE826408f` |
| Legacy helper | `0xa476920af80B587f696734430227869795E2Ea78` |
| SphereX engine | `0xCc65C2Ad8ab5b5c63489cfC77F782175E0c6A36e` |
| Activation release | `v2-5` |
| Retirement release | `v2-5-retirement` |
| Foundry profile | `deploy` |
| Production Solidity baseline | `49f891c93768f9986f985204c2f533c77c5e6f60` |
| Activation shape | 24 cards: 14 deployments and 10 calls |
| Current retirement shape | 18 calls for nine superseded factories |

The retirement count is state-dependent. Regenerate it from finalized live
inventory and review every address.

## Stop conditions

Stop if the source revision differs from rehearsal, the RPC or wallet is on the
wrong chain, the selected wallet is not the phase's exact executor, a package
digest changes, a transaction reverts, a predicate stays red, a pending nonce
is unresolved, or any authority preflight fails.

There is no skip path. Preserve the exact package, browser state, run-state,
transaction hash, and error before changing anything. Never edit a generated
plan or run-state.

## 1. Prepare source and environment

```bash
cd /home/kethcode/wildcat/mono/v2-protocol

export REPO_ROOT="$(pwd -P)"
export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=sepolia
export RPC_URL='<reviewed Sepolia RPC URL>'
export OLD_EXECUTOR=0xca732651410E915090d7A7D889A1E44eF4575fcE
export NEW_EXECUTOR=0xca7007a75296b532ce1606d9e130eaa849800ca7
export ARCH_CONTROLLER=0xC003f20F2642c76B81e5e1620c6D8cdEE826408f
export LEGACY_HELPER=0xa476920af80B587f696734430227869795E2Ea78
export PRODUCTION_SOLIDITY_BASELINE=49f891c93768f9986f985204c2f533c77c5e6f60
export REHEARSED_COMMIT='<full commit from the successful Anvil rehearsal>'
```

Record source and run the cold gates:

```bash
git branch --show-current
git rev-parse HEAD
git status --short
test "$(git rev-parse HEAD)" = "$REHEARSED_COMMIT"
git diff --quiet "$PRODUCTION_SOLIDITY_BASELINE" -- src
test "$(cast chain-id --rpc-url "$RPC_URL")" = 11155111

FOUNDRY_PROFILE=deploy forge test
FOUNDRY_PROFILE=deploy forge build --sizes src script/common script/deploy/v2-5

(
  cd deploy-ui
  npm ci
  npm test
  npm run build
)
```

Before phase 1, independently confirm the live baseline documented in
[sepolia-authority-helper-rotation.md](./sepolia-authority-helper-rotation.md).
The legacy helper must own the ArchController. The old executor must still be
the ArchController SphereX admin/operator and the SphereX engine default
admin/operator.

## 2. Authority phase 1 — old executor

Phase 1 deploys the replacement helper from the old wallet with both executors
authorized, transfers ArchController ownership, and starts both SphereX admin
transfers.

```bash
node scripts/authority-migration.js phase-one \
  --network sepolia \
  --rpc-url "$RPC_URL" \
  --old-executor "$OLD_EXECUTOR" \
  --new-executor "$NEW_EXECUTOR"

export AUTHORITY_PHASE_1="$REPO_ROOT/deployments/sepolia/plan-authority-helper-phase-1.json"
export AUTHORITY_PHASE_1_PACKAGE="$REPO_ROOT/deployments/sepolia/ceremony-authority-helper-phase-1.json"
export AUTHORITY_PHASE_1_STATE="$REPO_ROOT/deployments/sepolia/run-state-authority-helper-phase-1.json"

node scripts/plan.js ceremony-package \
  --plan "$AUTHORITY_PHASE_1" --mode eoa --out "$AUTHORITY_PHASE_1_PACKAGE"
```

Build the locked UI with that package. Confirm five cards and the old executor:

1. deploy the replacement helper;
2. reclaim ArchController ownership from the legacy helper;
3. transfer ArchController ownership to the replacement helper;
4. start the ArchController SphereX admin transfer; and
5. start the SphereX engine default-admin transfer.

The temporary owner predicate on card 2 is compensated by card 3. Stop between
those cards only if necessary, preserve the run-state, and complete the already
reviewed ownership transfer before ending the session.

After all five predicates pass, export the unedited run-state and verify it:

```bash
node scripts/plan.js verify \
  --plan "$AUTHORITY_PHASE_1" \
  --run-state "$AUTHORITY_PHASE_1_STATE" \
  --rpc "$RPC_URL"

export REPLACEMENT_HELPER="$(jq -er '."deploy-replacement-authority-helper".resolvedAddress' "$AUTHORITY_PHASE_1_STATE")"
cast call "$REPLACEMENT_HELPER" 'version()(string)' --rpc-url "$RPC_URL"
cast call "$REPLACEMENT_HELPER" 'getAuthorizedAccounts()(address[])' --rpc-url "$RPC_URL"
```

Record the replacement address, constructor arguments, runtime code hash,
transaction hashes, and package digest. Fund the new executor for the remaining
ceremonies without using it to deploy another contract.

Do not generate or reuse phase 2 or phase 3 before this run-state is verified.
Both generators require either this exact phase-1 run-state or an explicitly
reviewed replacement-helper address, and reject the current legacy helper.

## 3. Authority phase 2 — new executor

Phase 2 proves the new wallet can operate the helper, accepts ArchController
SphereX administration, moves the ArchController SphereX operator, and registers
the new wallet as a testnet borrower.

```bash
node scripts/authority-migration.js phase-two \
  --network sepolia \
  --phase-one-run-state "$AUTHORITY_PHASE_1_STATE" \
  --new-executor "$NEW_EXECUTOR"

export AUTHORITY_PHASE_2="$REPO_ROOT/deployments/sepolia/plan-authority-helper-phase-2.json"
export AUTHORITY_PHASE_2_PACKAGE="$REPO_ROOT/deployments/sepolia/ceremony-authority-helper-phase-2.json"
export AUTHORITY_PHASE_2_STATE="$REPO_ROOT/deployments/sepolia/run-state-authority-helper-phase-2.json"

node scripts/plan.js ceremony-package \
  --plan "$AUTHORITY_PHASE_2" --mode eoa --out "$AUTHORITY_PHASE_2_PACKAGE"
```

Build a fresh locked UI. Confirm three cards, the new executor, and the
replacement helper transport target. The UI must show each logical
ArchController call and its decoded arguments, not only nested calldata.

Execute, export, and verify:

```bash
node scripts/plan.js verify \
  --plan "$AUTHORITY_PHASE_2" \
  --run-state "$AUTHORITY_PHASE_2_STATE" \
  --rpc "$RPC_URL"
```

## 4. Authority phase 3 — after the SphereX delay

Read the engine schedule and wait until it has passed:

```bash
cast call 0xCc65C2Ad8ab5b5c63489cfC77F782175E0c6A36e \
  'pendingDefaultAdmin()(address,uint48)' --rpc-url "$RPC_URL"
```

Do not estimate or send the acceptance transaction early. After the timestamp:

```bash
node scripts/authority-migration.js phase-three \
  --network sepolia \
  --rpc-url "$RPC_URL" \
  --phase-one-run-state "$AUTHORITY_PHASE_1_STATE" \
  --old-executor "$OLD_EXECUTOR" \
  --new-executor "$NEW_EXECUTOR"

export AUTHORITY_PHASE_3="$REPO_ROOT/deployments/sepolia/plan-authority-helper-phase-3.json"
export AUTHORITY_PHASE_3_PACKAGE="$REPO_ROOT/deployments/sepolia/ceremony-authority-helper-phase-3.json"
export AUTHORITY_PHASE_3_STATE="$REPO_ROOT/deployments/sepolia/run-state-authority-helper-phase-3.json"

node scripts/plan.js ceremony-package \
  --plan "$AUTHORITY_PHASE_3" --mode eoa --out "$AUTHORITY_PHASE_3_PACKAGE"
```

Build a fresh locked UI, execute the three cards with the new wallet, export the
run-state, and verify it. The cards accept engine default administration, grant
the helper the engine operator role, and remove the old wallet's direct engine
operator role. They do **not** remove the old wallet from the helper's executor
list.

Only after all three phases are verified, finalize the local deployment alias:

```bash
node scripts/authority-helper.js finalize \
  --network sepolia \
  --rpc-url "$RPC_URL" \
  --expected-executor "$NEW_EXECUTOR" \
  --helper "$REPLACEMENT_HELPER"

node scripts/authority-helper.js preflight \
  --network sepolia \
  --rpc-url "$RPC_URL" \
  --expected-executor "$NEW_EXECUTOR"
```

Review and commit the `deployments.json` alias change normally. It preserves the
old address under `MockArchControllerOwnerLegacy`.

## 5. Generate v2.5 activation

```bash
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export EXPECTED_EXECUTOR="$NEW_EXECUTOR"
export TEMPLATE_FEE_RECIPIENT=0xca732651410E915090d7A7D889A1E44eF4575fcE
export PLAN="$REPO_ROOT/deployments/sepolia/plan-v2-5.json"
export PACKAGE="$REPO_ROOT/deployments/sepolia/ceremony-v2-5-eoa.json"
export RUN_STATE="$REPO_ROOT/deployments/sepolia/run-state-v2-5.json"

forge script script/deploy/v2-5/01-deploy-wrapper-factory.s.sol:DeployWrapperFactoryV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/02-deploy-hooks-factory-standard.s.sol:DeployHooksFactoryStandardV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/03-deploy-hooks-factory-revolving.s.sol:DeployHooksFactoryRevolvingV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/04-deploy-market-lens.s.sol:DeployMarketLensV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/05-owner-actions.s.sol:OwnerActionsV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/06-register-factories.s.sol:RegisterFactoriesV25 --rpc-url "$RPC_URL"
bash script/deploy/v2-5/07-generate-plan.sh
```

The generator runs the authority preflight first. It must print `24 tx (14
deploy, 10 call)`. Eight owner actions must be forwarded through the helper;
the two permissionless `registerWithArchController()` calls remain direct.

Review the logical calls rather than only the transport calls:

```bash
jq -e '
  def logical: (.forwardedCall // {target: .to, functionSignature, args});
  (.transactions | length) == 24 and
  ([.transactions[] | select(.kind == "deploy")] | length) == 14 and
  ([.transactions[] | select(.kind == "call")] | length) == 10 and
  ([.transactions[] | select(.forwardedCall != null)] | length) == 8 and
  ([.transactions[] | logical | select(.functionSignature == "addHooksTemplate(address,string,address,address,uint80,uint16)")] | length) == 6 and
  ([.transactions[] | logical | select(.functionSignature == "registerControllerFactory(address)")] | length) == 2 and
  all(.transactions[]; .id != "reclaim-arch-controller-ownership") and
  all(.transactions[]; .id != "restore-arch-controller-ownership")
' "$PLAN"

jq -r '
  .transactions | to_entries[] |
  (.value.forwardedCall // {target: .value.to, functionSignature: .value.functionSignature, args: .value.args}) as $call |
  [(.key + 1), .value.kind, .value.id, ($call.functionSignature // "deploy"), ($call.target // "")] | @tsv
' "$PLAN"
```

## 6. Execute and finalize activation

Build a fresh locked package and site:

```bash
node scripts/plan.js ceremony-package --plan "$PLAN" --mode eoa --out "$PACKAGE"
(
  cd deploy-ui
  CEREMONY_PACKAGE="$PACKAGE" npm run build
)
```

Confirm the new executor, Sepolia chain ID, package digest, and 24-card count.
Walk every card in order. The helper remains ArchController owner throughout;
there is no reclaim or return card. Export and independently verify the final
run-state:

```bash
test "$(jq 'length' "$RUN_STATE")" = 24
node scripts/plan.js verify --plan "$PLAN" --run-state "$RUN_STATE" --rpc "$RPC_URL"
RUN_STATE="$RUN_STATE" RPC_URL="$RPC_URL" bash script/deploy/v2-5/08-finalize-inventory.sh

node scripts/factory-inventory.js validate --network sepolia
node scripts/factory-inventory.js lint --network sepolia
node scripts/factory-inventory.js reconcile --network sepolia --rpc-url "$RPC_URL"
node scripts/authority-helper.js preflight \
  --network sepolia --rpc-url "$RPC_URL" --expected-executor "$NEW_EXECUTOR"
```

Run both canaries, generate the downstream handoff, deploy and validate the
subgraph, SDK, and app, and preserve all ceremony evidence. Do not generate
retirement until the activated generation is accepted.

## 7. Retirement after validation

```bash
export EXPECTED_EXECUTOR="$NEW_EXECUTOR"
export RETIREMENT_PLAN="$REPO_ROOT/deployments/sepolia/plan-v2-5-retirement.json"
export RETIREMENT_PACKAGE="$REPO_ROOT/deployments/sepolia/ceremony-v2-5-retirement-eoa.json"
export RETIREMENT_RUN_STATE="$REPO_ROOT/deployments/sepolia/run-state-v2-5-retirement.json"

node scripts/factory-inventory.js reconcile --network sepolia --rpc-url "$RPC_URL"
bash script/deploy/v2-5/retirement/01-generate-plan.sh
node scripts/plan.js validate --plan "$RETIREMENT_PLAN"
node scripts/factory-inventory.js validate-retirement-plan \
  --network sepolia --plan "$RETIREMENT_PLAN"
```

The current inventory produces nine targets and 18 forwarded calls. For every
target, `removeControllerFactory(address)` must immediately precede
`removeController(address)`. There is no ownership handoff and no
`removeMarket(address)` call.

Build a separate locked retirement site, execute every card, export the
unedited retirement run-state, verify it, and finalize:

```bash
node scripts/plan.js ceremony-package \
  --plan "$RETIREMENT_PLAN" --mode eoa --out "$RETIREMENT_PACKAGE"

node scripts/plan.js verify \
  --plan "$RETIREMENT_PLAN" \
  --run-state "$RETIREMENT_RUN_STATE" \
  --rpc "$RPC_URL"

RUN_STATE="$RETIREMENT_RUN_STATE" RPC_URL="$RPC_URL" \
  bash script/deploy/v2-5/retirement/02-finalize-inventory.sh
```

Re-run inventory reconciliation and the authority-helper preflight. Removing
the old executor from the helper is a later, separately reviewed operation
after the contracts, subgraph, SDK, and app have been stable for several days.
