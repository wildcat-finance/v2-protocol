# v2.5 Sepolia first-deployment checklist

This is the operator walkthrough for the first live v2.5 deployment. It uses the same plan and locked release-site model as mainnet, but each card is signed by the Sepolia developer EOA instead of being bundled through a Safe.

Complete [anvil-v2-5-rehearsal.md](./anvil-v2-5-rehearsal.md) from the exact deployment-affecting source before starting. The live process has two ceremonies:

1. Activation deploys and registers the new v2.5 generation while every existing preview factory remains registered.
2. Retirement is generated later, after the activated contracts, subgraph, SDK, app, and canary paths have been validated.

Do not combine them. The helper owns the ArchController between ceremonies.

Sections 1 through 4 generate and inspect activation without sending a transaction. Section 5 begins the live activation. Retirement begins in section 9 only after the validation window is complete.

## Fixed deployment identity

| Role | Expected value |
| --- | --- |
| Network | Sepolia, chain ID `11155111` |
| Executing EOA | `0xca732651410E915090d7A7D889A1E44eF4575fcE` |
| Template fee recipient | `0xca732651410E915090d7A7D889A1E44eF4575fcE` |
| ArchController | `0xC003f20F2642c76B81e5e1620c6D8cdEE826408f` |
| Mock owner helper | `0xa476920af80B587f696734430227869795E2Ea78` |
| Activation release | `v2-5` |
| Retirement release | `v2-5-retirement` |
| Foundry profile | `deploy` |
| Activation shape | 27 cards: 15 deployments and 12 calls |
| Current retirement shape | 20 calls for nine superseded factories, including helper reclaim and return |

The retirement count is state-dependent. Regenerate it from the finalized live inventory and review every address.

## Stop conditions

Do not start or continue if the RPC or wallet is on the wrong chain, the account is not the exact executor, the helper does not own the ArchController before card 1, the executor is not authorized by the helper, source differs from the successful rehearsal, a build or test failed, inventory reconciliation is not green, the plan shape differs from the reviewed shape, the UI reports a digest or executor mismatch, a receipt reverts, a predicate stays red, or the EOA has an unresolved pending transaction.

There is no skip path. A failed predicate is a deployment incident. Preserve the exact site, browser state, run-state export, transaction hash, and error before changing anything.

## 1. Prepare activation

```bash
cd /Users/kethcode/wildcat/mono/v2-protocol

export REPO_ROOT="$(pwd -P)"
export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=sepolia
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export RPC_URL='<reviewed Sepolia RPC URL>'
export REHEARSED_COMMIT='<full commit from the successful Anvil rehearsal>'

export EXPECTED_EXECUTOR=0xca732651410E915090d7A7D889A1E44eF4575fcE
export TEMPLATE_FEE_RECIPIENT=0xca732651410E915090d7A7D889A1E44eF4575fcE
export ARCH_CONTROLLER=0xC003f20F2642c76B81e5e1620c6D8cdEE826408f
export EXPECTED_HELPER_OWNER=0xa476920af80B587f696734430227869795E2Ea78

export PLAN="$REPO_ROOT/deployments/sepolia/plan-v2-5.json"
export PACKAGE="$REPO_ROOT/deployments/sepolia/ceremony-v2-5-eoa.json"
export RUN_STATE="$REPO_ROOT/deployments/sepolia/run-state-v2-5.json"
export RETIREMENT_PLAN="$REPO_ROOT/deployments/sepolia/plan-v2-5-retirement.json"
export RETIREMENT_PACKAGE="$REPO_ROOT/deployments/sepolia/ceremony-v2-5-retirement-eoa.json"
export RETIREMENT_RUN_STATE="$REPO_ROOT/deployments/sepolia/run-state-v2-5-retirement.json"
```

Record and compare source:

```bash
git branch --show-current
git rev-parse HEAD
git status --short
test "$(git rev-parse HEAD)" = "$REHEARSED_COMMIT"
```

Documentation-only changes do not invalidate the rehearsal. Any contract, dependency, deployment script, plan engine, inventory input, or deployment UI change does. If one changed after rehearsal, stop and repeat the Anvil run.

Run the live read-only preflight:

```bash
test "$(cast chain-id --rpc-url "$RPC_URL")" = "11155111"
test "$(jq -r '.WildcatArchController' deployments/sepolia/deployments.json | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$ARCH_CONTROLLER" | tr '[:upper:]' '[:lower:]')"

node scripts/factory-inventory.js validate --network sepolia
node scripts/factory-inventory.js lint --network sepolia
node scripts/factory-inventory.js reconcile --network sepolia --rpc-url "$RPC_URL"

test "$(cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$EXPECTED_HELPER_OWNER" | tr '[:upper:]' '[:lower:]')"
test "$(cast call "$EXPECTED_HELPER_OWNER" 'authorizedAccounts(address)(bool)' "$EXPECTED_EXECUTOR" --rpc-url "$RPC_URL")" = "true"
```

Confirm the executing EOA has enough Sepolia ETH and no unresolved pending transaction. Record its pending nonce immediately before the live section.

## 2. Generate activation without a key

Plan generation needs the expected executor and RPC reads. It does not need a private key.

```bash
forge script script/deploy/v2-5/01-deploy-wrapper-factory.s.sol:DeployWrapperFactoryV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/02-deploy-hooks-factory-standard.s.sol:DeployHooksFactoryStandardV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/03-deploy-hooks-factory-revolving.s.sol:DeployHooksFactoryRevolvingV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/04-deploy-market-lens.s.sol:DeployMarketLensV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/05-owner-actions.s.sol:OwnerActionsV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/06-register-factories.s.sol:RegisterFactoriesV25 --rpc-url "$RPC_URL"
bash script/deploy/v2-5/07-generate-plan.sh
```

`07-generate-plan.sh` validates the complete activation allowlist and six-entry template matrix. It must print `27 tx (15 deploy, 12 call)` on Sepolia.

## 3. Review the activation plan

```bash
node scripts/plan.js validate --plan "$PLAN"
node scripts/factory-inventory.js validate-activation-plan --network sepolia --plan "$PLAN"

jq -e \
  --arg executor "$EXPECTED_EXECUTOR" \
  --arg helper "$EXPECTED_HELPER_OWNER" '
  ($executor | ascii_downcase) as $executor_lc |
  ($helper | ascii_downcase) as $helper_lc |
  .schemaVersion == "1.1.0" and
  .foundryProfile == "deploy" and
  .network == "sepolia" and
  .chainId == 11155111 and
  .release == "v2-5" and
  ((.expectedExecutor | ascii_downcase) == $executor_lc) and
  (.transactions | length) == 27 and
  ([.transactions[] | select(.kind == "deploy")] | length) == 15 and
  ([.transactions[] | select(.kind == "call")] | length) == 12 and
  .transactions[0].id == "reclaim-arch-controller-ownership" and
  .transactions[-1].id == "restore-arch-controller-ownership" and
  ((.transactions[-1].args[0] | ascii_downcase) == $helper_lc) and
  ([.transactions[] | select(.functionSignature == "addHooksTemplate(address,string,address,address,uint80,uint16)")] | length) == 6 and
  ([.transactions[] | select(.functionSignature == "registerControllerFactory(address)")] | length) == 2 and
  ([.transactions[] | select(.functionSignature == "registerWithArchController()")] | length) == 2 and
  all(.transactions[]; (.functionSignature // "") != "removeControllerFactory(address)") and
  all(.transactions[]; (.functionSignature // "") != "removeController(address)") and
  all(.transactions[]; (.functionSignature // "") != "removeMarket(address)")
' "$PLAN"
```

Print the card ledger and review every target, artifact, argument, and predicate:

```bash
jq -r '.transactions | to_entries[] | [(.key + 1), .value.kind, .value.id, (.value.functionSignature // "deploy")] | @tsv' "$PLAN"
```

The 15 deployments must include the wrapper factory, borrower identity registry, AccessList role-provider factory, standard market init-code storage and factory, two revolving market init-code storage contracts and its factory, four lens contracts, and three hook-template init-code storage contracts.

Review the six template fee tuples:

```bash
jq '[.transactions[] | select(.functionSignature == "addHooksTemplate(address,string,address,address,uint80,uint16)") | {id, feeRecipient: .args[2], originationFeeAsset: .args[3], originationFeeAmount: .args[4], protocolFeeBips: .args[5]}]' "$PLAN"
```

For this Sepolia release, all six entries must use the reviewed developer EOA as fee recipient, zero origination-fee asset, zero origination-fee amount, and protocol fee `500` bips.

## 4. Build the locked activation site

```bash
node scripts/plan.js ceremony-package --plan "$PLAN" --mode eoa --out "$PACKAGE"

(
  cd "$REPO_ROOT/deploy-ui"
  CEREMONY_PACKAGE="$PACKAGE" npm run build
)
```

Record the full digest and short fingerprint. Serve the existing build without rebuilding it:

```bash
cd /Users/kethcode/wildcat/mono/v2-protocol/deploy-ui
npm exec -- vite preview --host 127.0.0.1 --port 4173 --strictPort
```

Open `http://127.0.0.1:4173/` in the browser profile containing the exact executor. The page must open in locked EOA mode with no plan picker or mode switch. Confirm release, network, chain, executor, 27-card count, full digest, and fingerprint before connecting the wallet.

Do not place a private key in the site, environment, generated package, or hosting configuration. The browser wallet signs live transactions.

## 5. Execute live activation

Sending card 1 is the live boundary. It temporarily moves ArchController ownership from the helper to the developer EOA.

1. Put the wallet on Sepolia and select the exact executor.
2. Review card 1, `returnOwnership()` on the helper. Send it and wait for its receipt and predicate.
3. Confirm `ArchController.owner()` is the expected executor.
4. Walk cards 2 through 26 in order. For every card, review the plain-English action and technical details, send only the active transaction, and wait for a verified predicate before continuing.
5. Review card 27, `ArchController.transferOwnership(helper)`. Send it and wait for the predicate.
6. Confirm the helper owns the ArchController again.

If the browser or RPC disconnects after submission, do not resend. Restore the endpoint, reopen the exact same site origin, reconnect the same account, and let the page recover the stored transaction hash and on-chain receipt.

Export the final unedited activation run-state to `$RUN_STATE`:

```bash
test "$(jq 'length' "$RUN_STATE")" = "27"
node scripts/plan.js verify --plan "$PLAN" --run-state "$RUN_STATE" --rpc "$RPC_URL"
```

## Emergency ownership return

This is an abort procedure, not a skip path. Preserve the page, browser storage, run-state export, last transaction hash, error, and pending nonce. Check `owner()` first. If the helper already owns the ArchController, send nothing. If the executor still owns it, return ownership using the existing reviewed signer, record the recovery transaction, and stop. Do not edit the run-state or finalize inventory after an out-of-plan recovery.

## 6. Finalize and verify activation

```bash
RUN_STATE="$RUN_STATE" RPC_URL="$RPC_URL" bash script/deploy/v2-5/08-finalize-inventory.sh

node scripts/factory-inventory.js validate --network sepolia
node scripts/factory-inventory.js lint --network sepolia
node scripts/factory-inventory.js reconcile --network sepolia --rpc-url "$RPC_URL"
```

Finalization must append the new standard, revolving, and wrapper generations, move canonical aliases, record all supporting components, and leave every superseded hooks factory registered. Reconciliation must be green.

## 7. Explorer, canary, and downstream validation

List all 15 deployment artifacts and resolved addresses from the plan and run-state:

```bash
jq -r --slurpfile state "$RUN_STATE" '.transactions[] | select(.kind == "deploy") | [.id, .artifactName, $state[0][.id].resolvedAddress] | @tsv' "$PLAN"
```

Preserve the deploy-profile standard JSON input for each contract and verify its recovered constructor arguments against the resolved plan before submitting explorer verification.

Run the standard and revolving canaries with the reviewed Sepolia borrower and mock asset:

```bash
export BORROWER="$EXPECTED_EXECUTOR"
export CANARY_ASSET="$(jq -r '."MockERC20:Token"' deployments/sepolia/deployments.json)"

test "$CANARY_ASSET" != "null"
test "$(cast code "$CANARY_ASSET" --rpc-url "$RPC_URL")" != "0x"
test "$(cast call "$ARCH_CONTROLLER" 'isRegisteredBorrower(address)(bool)' "$BORROWER" --rpc-url "$RPC_URL")" = "true"

export OWNER_MODE=direct
bash script/deploy/v2-5/09-canary-market.sh
export OWNER_MODE=plan
```

The canary script needs the testnet signer through the existing secure operator method. Do not paste a private key into command history or documentation.

Generate and validate the downstream handoff:

```bash
node scripts/generate-handoff.js --network sepolia --release v2-5
node scripts/generate-handoff.js --network sepolia --release v2-5 --check
```

Confirm the subgraph can index the new events and all new factories, the SDK resolves the new data shape, the app can deploy and administer a standard and revolving market with an attached AccessList provider, and lens reads agree with indexed state where block-precise data matters.

Retirement remains blocked until the team accepts this validation. The preview markets and factories are disposable, but leaving their origination authority in place during validation gives a clean recovery path if the new generation has a problem.

## 8. Freeze post-activation state

Commit the finalized inventory and handoff through the normal review process before generating retirement. Preserve the activation plan, package, run-state, transaction hashes, explorer inputs, canary output, source revision, and package fingerprint in the release evidence directory. Generated ceremony files remain ignored unless the team deliberately chooses to archive them elsewhere.

Immediately before retirement, repeat live inventory reconciliation and confirm the helper owns the ArchController.

## 9. Generate and review retirement

```bash
cd /Users/kethcode/wildcat/mono/v2-protocol
export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=sepolia
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export RPC_URL='<reviewed Sepolia RPC URL>'
export EXPECTED_EXECUTOR=0xca732651410E915090d7A7D889A1E44eF4575fcE

node scripts/factory-inventory.js reconcile --network sepolia --rpc-url "$RPC_URL"
bash script/deploy/v2-5/retirement/01-generate-plan.sh
```

The generator writes `plan-v2-5-retirement.json` from the current post-activation inventory. Validate and review it:

```bash
node scripts/plan.js validate --plan "$RETIREMENT_PLAN"
node scripts/factory-inventory.js validate-retirement-plan --network sepolia --plan "$RETIREMENT_PLAN"
node scripts/factory-inventory.js deactivation-targets --network sepolia | jq .
jq -r '.transactions | to_entries[] | [(.key + 1), .value.id, .value.functionSignature, (.value.args[0] // "")] | @tsv' "$RETIREMENT_PLAN"
```

The current inventory produces nine targets and 20 cards. Card 1 reclaims ownership, cards 2 through 19 remove two roles per superseded factory, and card 20 returns ownership. For every target, `removeControllerFactory(address)` must immediately precede `removeController(address)`. There must be no deployment, registration, or `removeMarket(address)` call.

If target count or addresses changed, reconcile the reason before proceeding. Do not edit the generated plan to force the old count.

## 10. Execute and finalize live retirement

Create a separate package and rebuild the locked UI:

```bash
node scripts/plan.js ceremony-package --plan "$RETIREMENT_PLAN" --mode eoa --out "$RETIREMENT_PACKAGE"

(
  cd "$REPO_ROOT/deploy-ui"
  CEREMONY_PACKAGE="$RETIREMENT_PACKAGE" npm run build
)
```

Record the retirement digest and fingerprint. Confirm the page says `v2-5-retirement`, uses the correct executor, and has its own card count. Activation browser progress is not valid retirement progress.

Walk retirement as a new ceremony. Card 1 reclaims ownership and the final card returns it. Wait for every receipt and predicate. Export the unedited retirement run-state to `$RETIREMENT_RUN_STATE`, then verify and finalize:

```bash
node scripts/plan.js verify --plan "$RETIREMENT_PLAN" --run-state "$RETIREMENT_RUN_STATE" --rpc "$RPC_URL"

RUN_STATE="$RETIREMENT_RUN_STATE" RPC_URL="$RPC_URL" bash script/deploy/v2-5/retirement/02-finalize-inventory.sh

node scripts/factory-inventory.js validate --network sepolia
node scripts/factory-inventory.js lint --network sepolia
node scripts/factory-inventory.js reconcile --network sepolia --rpc-url "$RPC_URL"
```

Confirm the helper owns the ArchController, every retired factory is absent from both authority registries, and all existing markets remain registered. Retirement disables new origination through the old factories; it does not delete or disable their markets.

The Sepolia release is complete when both run-states verify, ownership is back with the helper after each ceremony, inventory reconciliation is green, all release deployments are verified, both canaries pass, and the downstream handoff and app validation are accepted.
