# v2.5 Sepolia first-deployment checklist

This is the operator walkthrough for the first real v2.5 deployment. It uses
the same generated plan and locked release-site shape intended for mainnet, but
executes each card from the Sepolia developer EOA instead of a Safe.

Before beginning this public-network walkthrough, complete the current-source
locked-UI rehearsal in
[`anvil-v2-5-rehearsal.md`](./anvil-v2-5-rehearsal.md). That rehearsal must
pass all 38 predicates, reload/resume, independent run-state verification,
inventory finalization/reconciliation, canaries, and handoff `--check`. An
older headless or pre-refactor fork run is not sufficient release evidence.

The recommended first run is a local production build served from
`deploy-ui/dist/`. That exercises the embedded, immutable ceremony package and
avoids adding Git/Vercel state to the first live run. The Vercel alternative is
documented below.

Sections 1–5 are the safe test-drive boundary: they compile, generate, validate,
package, and display the ceremony, but do not sign or broadcast anything. Stop
after section 5 if you only want to inspect the operator experience. Section 6
starts the live deployment when card 1 is sent; after that point, either finish
the ceremony or use the documented emergency ownership return.

The generated plan entries, pending inventory, assembled plan, ceremony package,
and eventual run-state are local release outputs. They do not need to be staged
or committed to perform the local test drive.

The live run must use the same deployment-affecting source and Sepolia inventory
inputs that passed the Anvil rehearsal. Documentation-only changes do not
invalidate that rehearsal. Any contract, deployment-script, plan-tooling,
inventory, or deploy-UI change does: stop and repeat the Anvil walkthrough
before broadcasting.

## Fixed deployment identity

| Role | Expected value |
| --- | --- |
| Network | Sepolia, chain ID `11155111` |
| Executing EOA | `0xca732651410E915090d7A7D889A1E44eF4575fcE` |
| Template fee recipient | `0xca732651410E915090d7A7D889A1E44eF4575fcE` |
| ArchController | `0xC003f20F2642c76B81e5e1620c6D8cdEE826408f` |
| Mock owner helper | `0xa476920af80B587f696734430227869795E2Ea78` |
| Release | `v2-5` |
| Foundry profile | `deploy` |
| Expected ceremony length | 38 transactions |

Do not rely on an earlier balance, nonce, authorization, or ownership check.
Repeat every live preflight below immediately before deploying.

The deployment passes only when all 38 predicates verify, the helper owns the
ArchController again, the exported run-state passes independent verification,
inventory finalization and reconciliation are green, all 12 release contracts
are explorer-verified, both canary markets close and settle, and the downstream
handoff passes `--check`.

## Stop conditions

Do not start or continue the ceremony if any of these is true:

- The RPC or wallet is not on chain `11155111`.
- The connected account is not the exact executing EOA above.
- The helper does not own the ArchController before card 1.
- `authorizedAccounts(executing EOA)` is not `true` on the helper.
- the deployment-affecting tree differs from the successful Anvil rehearsal,
  or any clean build, test, or script syntax check fails.
- inventory reconciliation is not green.
- the generated plan is not profile `deploy`, executor-matched, and exactly 38
  cards with reclaim first and restore last.
- there is an unresolved pending transaction from the executing EOA.
- the UI reports a fatal halt, a reverted receipt, or a failed predicate.

There is intentionally no skip path. A failed predicate is a deployment
incident, not a prompt to move to the next card.

## 1. Prepare the release shell

Open a terminal at the repository root. Set `REHEARSED_COMMIT` to the full commit
printed during the successful Anvil rehearsal; do not derive it from the live
checkout just to make the comparison pass.

```bash
cd /Users/kethcode/wildcat/mono/v2-protocol

export REPO_ROOT="$(pwd -P)"
export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=sepolia
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export RPC_URL='<your Sepolia RPC URL>'
export REHEARSED_COMMIT='<full commit from the successful Anvil rehearsal>'

export EXPECTED_EXECUTOR=0xca732651410E915090d7A7D889A1E44eF4575fcE
export TEMPLATE_FEE_RECIPIENT=0xca732651410E915090d7A7D889A1E44eF4575fcE
export ARCH_CONTROLLER=0xC003f20F2642c76B81e5e1620c6D8cdEE826408f
export EXPECTED_HELPER_OWNER=0xa476920af80B587f696734430227869795E2Ea78

export PLAN="$REPO_ROOT/deployments/$DEPLOYMENTS_NETWORK/plan-$RELEASE_TAG.json"
export PACKAGE="$REPO_ROOT/deployments/$DEPLOYMENTS_NETWORK/ceremony-$RELEASE_TAG-eoa.json"
export RUN_STATE="$REPO_ROOT/deployments/$DEPLOYMENTS_NETWORK/run-state-$RELEASE_TAG.json"
export CHECKPOINT_DIR="$REPO_ROOT/deployments/$DEPLOYMENTS_NETWORK/run-state-checkpoints"
```

Do not export a private key for plan generation or put one in the frontend or
Vercel. Steps 01–07 need the executor address and RPC URL, but no key. The
browser wallet signs the live transactions later.

- [ ] Record the exact source revision and review local changes:

  ```bash
  git branch --show-current
  git rev-parse HEAD
  git status --short
  ```

- [ ] Prove that the deployment-affecting tree still matches the successful
  rehearsal. This deliberately ignores this documentation directory while
  comparing contracts, dependencies, ceremony tooling, UI source, and canonical
  Sepolia inputs:

  ```bash
  test -n "$REHEARSED_COMMIT"
  git cat-file -e "$REHEARSED_COMMIT^{commit}"
  git diff --quiet "$REHEARSED_COMMIT" -- \
    foundry.toml remappings.txt lib src script scripts deploy-ui \
    deployments/deployment-plan.schema-1-1.json \
    deployments/sepolia/ceremony-config.json \
    deployments/sepolia/deployments.json \
    deployments/sepolia/factory-inventory.json
  ```

  If the final command exits nonzero, inspect the path-limited diff and rerun
  the Anvil rehearsal. Do not waive this because the full commit differs only
  due to walkthrough edits.

- [ ] Confirm the required tools resolve:

  ```bash
  forge --version
  cast --version
  node --version
  npm --version
  jq --version
  ```

- [ ] Start this test drive from a fresh generation. First prove there is no
  run-state from a partial live ceremony:

  ```bash
  test ! -e "$RUN_STATE"
  ```

  If that command fails, stop. Do not regenerate or overwrite anything until
  the partial run has been reconciled. If it succeeds, preserve any earlier
  generation-only outputs outside the repository before continuing:

  ```bash
  SEPOLIA_BACKUP_ROOT="${SEPOLIA_BACKUP_ROOT:-${TMPDIR:-/tmp}}"
  export ARTIFACT_BACKUP="${SEPOLIA_BACKUP_ROOT%/}/wildcat-v2-5-sepolia-before-$(date -u +%Y%m%dT%H%M%SZ)"
  test ! -e "$ARTIFACT_BACKUP"
  mkdir -p "$ARTIFACT_BACKUP"
  for artifact in \
    deployments/sepolia/plan-entries \
    deployments/sepolia/inventory-pending \
    "$CHECKPOINT_DIR" \
    "$PLAN" \
    "$PACKAGE"
  do
    if [[ -e "$artifact" ]]; then
      mv "$artifact" "$ARTIFACT_BACKUP"/
    fi
  done
  test -d "$ARTIFACT_BACKUP"
  echo "Preserved prior Sepolia generation outputs at $ARTIFACT_BACKUP"
  ```

  This avoids mixing stale entries into the new plan without deleting the
  previous output. Do not run `plan.js execute`, add `--broadcast`, or export a
  private key for this walkthrough; the browser is the executor in section 6.
  On macOS, `TMPDIR` normally resolves under `/var/folders`; that is expected.
  Set `SEPOLIA_BACKUP_ROOT=/tmp` or another explicit directory before this block
  if that location is not desired.

## 2. Run the live preflight

- [ ] Confirm the RPC is on chain `11155111` and record the preflight block:

  ```bash
  test "$(cast chain-id --rpc-url "$RPC_URL")" = "11155111"
  export SEPOLIA_PREFLIGHT_BLOCK="$(cast block-number --rpc-url "$RPC_URL")"
  echo "Sepolia preflight block: $SEPOLIA_PREFLIGHT_BLOCK"
  ```

- [ ] Resolve the current owner. It must exactly equal
  `0xa476920af80B587f696734430227869795E2Ea78` before card 1:

  ```bash
  export HELPER_OWNER="$(cast call "$ARCH_CONTROLLER" \
    'owner()(address)' --rpc-url "$RPC_URL")"
  echo "$HELPER_OWNER"
  echo "$EXPECTED_HELPER_OWNER"
  test "$HELPER_OWNER" = "$EXPECTED_HELPER_OWNER"
  ```

- [ ] Confirm the executing EOA is authorized. The check must pass:

  ```bash
  test "$(cast call "$HELPER_OWNER" \
    'authorizedAccounts(address)(bool)' \
    "$EXPECTED_EXECUTOR" \
    --rpc-url "$RPC_URL")" = "true"
  ```

- [ ] Confirm the EOA is funded, and record its latest and pending nonces:

  ```bash
  cast balance "$EXPECTED_EXECUTOR" --ether --rpc-url "$RPC_URL"
  export EXECUTOR_LATEST_NONCE="$(cast nonce \
    "$EXPECTED_EXECUTOR" --block latest --rpc-url "$RPC_URL")"
  export EXECUTOR_PENDING_NONCE="$(cast nonce \
    "$EXPECTED_EXECUTOR" --block pending --rpc-url "$RPC_URL")"
  echo "Latest nonce: $EXECUTOR_LATEST_NONCE"
  echo "Pending nonce: $EXECUTOR_PENDING_NONCE"
  test "$EXECUTOR_LATEST_NONCE" = "$EXECUTOR_PENDING_NONCE"
  ```

  If the final test fails, wait for or resolve the pending transaction first.
  Do not use this EOA for any unrelated transaction until all 38 cards are
  complete.

- [ ] Validate the local inventory and reconcile it against Sepolia. The last
  command must print `Reconcile GREEN for sepolia`:

  ```bash
  node scripts/factory-inventory.js validate \
    --network "$DEPLOYMENTS_NETWORK"
  node scripts/factory-inventory.js lint \
    --network "$DEPLOYMENTS_NETWORK"
  node scripts/factory-inventory.js reconcile \
    --network "$DEPLOYMENTS_NETWORK" \
    --rpc-url "$RPC_URL"
  ```

- [ ] Rebuild and test from clean IR and deploy caches. This is intentionally
  the same source gate used by the Anvil walkthrough:

  ```bash
  FOUNDRY_PROFILE=ir forge clean
  FOUNDRY_PROFILE=deploy forge clean

  FOUNDRY_PROFILE=ir forge test
  FOUNDRY_PROFILE=deploy forge build --sizes \
    src script/common script/deploy/v2-5
  ```

  A cold IR test/build can take roughly ten minutes. The final command must use
  the `deploy` profile. Do not fall back to default artifacts:
  `HooksFactoryRevolving` exceeds EIP-170 there, while the ceremony and plan
  validator require `deploy-out` artifacts. The deploy build is scoped because
  several test harnesses intentionally exceed EIP-3860 initcode limits and are
  never deployed by the release ceremony.

- [ ] Install and test the deploy UI from its lockfile, then syntax-check the
  post-ceremony scripts that this walkthrough will use:

  ```bash
  (
    cd "$REPO_ROOT/deploy-ui"
    npm ci
    npm test
  )

  bash -n script/deploy/v2-5/08-finalize-inventory.sh
  bash -n script/deploy/v2-5/09-canary-market.sh
  ```

## 3. Generate plan entries without broadcasting

Run these in order. None of them should display a wallet prompt or broadcast a
transaction.

- [ ] Generate steps 01–06:

  ```bash
  forge script \
    script/deploy/v2-5/01-deploy-wrapper-factory.s.sol:DeployWrapperFactoryV25 \
    --rpc-url "$RPC_URL"

  forge script \
    script/deploy/v2-5/02-deploy-hooks-factory-standard.s.sol:DeployHooksFactoryStandardV25 \
    --rpc-url "$RPC_URL"

  forge script \
    script/deploy/v2-5/03-deploy-hooks-factory-revolving.s.sol:DeployHooksFactoryRevolvingV25 \
    --rpc-url "$RPC_URL"

  forge script \
    script/deploy/v2-5/04-deploy-market-lens.s.sol:DeployMarketLensV25 \
    --rpc-url "$RPC_URL"

  forge script \
    script/deploy/v2-5/05-owner-actions.s.sol:OwnerActionsV25 \
    --rpc-url "$RPC_URL"

  forge script \
    script/deploy/v2-5/06-register-factories.s.sol:RegisterFactoriesV25 \
    --rpc-url "$RPC_URL"
  ```

  Plan mode does not broadcast or require a private key, but it still requires
  the target RPC so each entry records the correct chain ID and read-only source
  configuration is resolved from the intended network.

- [ ] Inspect the generated file set before assembly:

  ```bash
  find deployments/sepolia/plan-entries \
    -maxdepth 1 -type f -name '*.json' -print | sort
  git status --short deployments/sepolia
  ```

- [ ] Assemble and validate step 07:

  ```bash
  bash script/deploy/v2-5/07-generate-plan.sh
  node scripts/plan.js validate --plan "$PLAN"
  ```

  The wrapper should report `38 tx (12 deploy, 26 call)` for the currently
  reconciled Sepolia inventory: 22 base rollout transactions, 14 factory-role
  removals, and two temporary-ownership calls.

- [ ] Review the plan identity:

  ```bash
  jq '{
    schemaVersion,
    foundryProfile,
    network,
    chainId,
    release,
    expectedExecutor,
    transactionCount: (.transactions | length),
    first: (.transactions[0] | {id, kind, to, functionSignature}),
    last: (.transactions[-1] | {id, kind, to, functionSignature, args})
  }' "$PLAN"
  ```

  It must show all of the following:

  - schema `1.1.0`, profile `deploy`, network `sepolia`, chain `11155111`, and
    release `v2-5`;
  - expected executor `0xca732651410E915090d7A7D889A1E44eF4575fcE`;
  - 38 transactions;
  - first ID `reclaim-arch-controller-ownership`, calling
    `returnOwnership()` on the mock owner helper; and
  - last ID `restore-arch-controller-ownership`, calling
    `transferOwnership(address)` on the ArchController with the helper as its
    argument.

  Assert that complete shape mechanically instead of relying on the summary
  alone:

  ```bash
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
    (.transactions | length) == 38 and
    ([.transactions[] | select(.kind == "deploy")] | length) == 12 and
    ([.transactions[] | select(.kind == "call")] | length) == 26 and
    .transactions[0].id == "reclaim-arch-controller-ownership" and
    .transactions[0].functionSignature == "returnOwnership()" and
    .transactions[-1].id == "restore-arch-controller-ownership" and
    .transactions[-1].functionSignature == "transferOwnership(address)" and
    ((.transactions[-1].args[0] | ascii_downcase) == $helper_lc) and
    ([.transactions[] |
      select(.id | test("^add-(standard|revolving)-(open|fixed|periodic)-term-template$"))
    ] | length) == 6 and
    ([.transactions[] |
      select(.id | startswith("remove-superseded-"))
    ] | length) == 14 and
    all(.transactions[]; (.functionSignature // "") != "removeMarket(address)")
  ' "$PLAN"
  ```

- [ ] Review the six template-registration calls separately:

  ```bash
  jq '[
    .transactions[]
    | select(.functionSignature == "addHooksTemplate(address,string,address,address,uint80,uint16)")
    | {
        id,
        feeRecipient: .args[2],
        originationFeeAsset: .args[3],
        originationFeeAmount: .args[4],
        protocolFeeBips: .args[5]
      }
  ]' "$PLAN"
  ```

  Assert the reviewed fee tuple:

  ```bash
  jq -e --arg recipient "$TEMPLATE_FEE_RECIPIENT" '
    ($recipient | ascii_downcase) as $recipient_lc |
    [.transactions[] |
      select(.functionSignature == "addHooksTemplate(address,string,address,address,uint80,uint16)")
    ] as $registrations |
    ($registrations | length) == 6 and
    all($registrations[];
      ((.args[2] | ascii_downcase) == $recipient_lc) and
      ((.args[3] | ascii_downcase) == "0x0000000000000000000000000000000000000000") and
      .args[4] == 0 and
      .args[5] == 500
    )
  ' "$PLAN"
  ```

  It must print exactly six rows. For this Sepolia pass, every fee recipient
  must be the configured developer EOA, every origination fee asset must be the
  zero address, every origination fee amount must be `0`, and every protocol
  fee must be `500` bips. The fee-recipient role is independent of the
  transaction-executor role even though both deliberately use the same address
  here.

- [ ] Review the superseded-factory deactivation matrix:

  ```bash
  node scripts/factory-inventory.js deactivation-targets \
    --network sepolia | jq .

  test "$(node scripts/factory-inventory.js deactivation-targets \
    --network sepolia | jq 'length')" = "7"

  jq '[
    .transactions[]
    | select(
        .functionSignature == "removeControllerFactory(address)" or
        .functionSignature == "removeController(address)"
      )
    | {id, functionSignature, factory: .args[0], expect: .predicate.expect}
  ]' "$PLAN"
  ```

  The inventory command must print the seven factories confirmed by the live
  reconciliation. The plan must print exactly 14 rows: for each address,
  `removeControllerFactory(address)` first and `removeController(address)`
  second, both expecting `false`. There must be no `removeMarket(address)`
  call. Disabling factory authority does not deregister existing markets, and
  finalization must preserve each old factory's `indexed` flag.

  Four of those seven records are intentionally `retired` and `indexed: false`:
  the abandoned revolving preview plus the August, September, and November 2024
  legacy test factories. Their five disposable dev markets remain on-chain but
  are deliberately omitted from the next subgraph. Do not turn indexing back on
  or add market-removal calls during this protocol deployment.

## 4. Package the exact EOA ceremony

- [ ] Generate the immutable browser package:

  ```bash
  node scripts/plan.js ceremony-package \
    --plan "$PLAN" \
    --mode eoa \
    --out "$PACKAGE"
  ```

  This writes `deployments/sepolia/ceremony-v2-5-eoa.json` and prints a full
  ceremony digest plus a short call-time fingerprint.

- [ ] Record the digest and fingerprint in the deployment notes. Inspect the
  package envelope:

  ```bash
  jq '{
    schemaVersion,
    digest,
    mode: .payload.mode,
    release: .payload.release,
    network: .payload.network,
    chainId: .payload.chainId,
    planName: .payload.artifacts.plan.name,
    planHash: .payload.artifacts.plan.hash,
    manifestCount: (.payload.artifacts.manifests | length),
    expectedAddresses: .payload.artifacts.expectedAddresses
  }' "$PACKAGE"
  ```

  Mode must be `eoa`, chain ID must be `11155111`, manifest count must be
  zero, and expected-addresses must be `null`.

## 5A. Recommended: build and serve the locked site locally

This is not `npm run dev`. A dev server has the debug file picker and mode
switch; the production build below embeds one exact package and removes both.

- [ ] Build the locked package using the absolute package path already
  validated above:

  ```bash
  (
    cd "$REPO_ROOT/deploy-ui"
    CEREMONY_PACKAGE="$PACKAGE" npm run build
  )
  ```

- [ ] In a second terminal, serve the built `dist/` without rebuilding it:

  ```bash
  cd /Users/kethcode/wildcat/mono/v2-protocol/deploy-ui
  npm exec -- vite preview \
    --host 127.0.0.1 \
    --port 4173 \
    --strictPort
  ```

- [ ] Keep that terminal open and visit `http://127.0.0.1:4173/` in the
  browser profile containing the executing EOA. Keep the original release
  shell open for plan checks, live ownership checks, run-state verification,
  and finalization; shell variables are not inherited by the preview terminal.

  Building and serving locally does not require any generated deployment file
  to be tracked by Git. The package bytes are embedded into `deploy-ui/dist/`
  during the build.

  If this origin already has progress for the exact package digest, the page
  must label it **not verified** and show zero green checks until the connected
  wallet re-verifies the receipts and predicates on Sepolia. A live-network
  package does not expose the Anvil-only **Start new rehearsal** control. Stop
  and reconcile the stored state with the prior attempt rather than clearing
  it casually.

## 5B. Optional: host the already built site through Vercel

For this uncommitted test drive, do not connect a Git branch and ask Vercel to
rebuild the source: that build would not contain the intentionally untracked
ceremony package. Complete section 5A locally, then upload only the finished
`deploy-ui/dist/` directory as a static site through
[Vercel Drop](https://vercel.com/drop). The directory already contains the
locked package; Vercel must serve it as-is with no build step.

- [ ] Do not add `PVT_KEY_SEPOLIA`, wallet credentials, or other signing
  material to the hosted site. This static Sepolia build needs none.
- [ ] After upload, use the unique URL for that exact static deployment. Record
  the source revision and local diff used to build it, then compare the
  displayed ceremony digest and fingerprint with the independently recorded
  values.
- [ ] Use the same origin for the whole run because progress is stored in
  origin-scoped browser storage. Do not switch between a Vercel deployment
  URL, project alias, and localhost mid-ceremony.
- [ ] If access should be restricted, configure
  [Vercel Deployment Protection](https://vercel.com/docs/deployment-protection)
  before sharing the URL. Confirm its behavior on the production domain for
  the selected Vercel plan.

Do not connect this one-off project to a branch or replace the hosted files
while the ceremony is in progress. Use the exact recorded deployment URL for
the whole run.

## 6. Walk the live 38-card EOA ceremony

This is the live boundary. Nothing in sections 1–5 changed Sepolia. Clicking
**Send transaction 1** below temporarily moves ArchController ownership from
the helper to the developer EOA.

- [ ] Open the locked site and confirm, before connecting:

  - release `v2-5`, network `sepolia`, chain `11155111`;
  - exactly 38 transactions;
  - expected executor `0xca732651410E915090d7A7D889A1E44eF4575fcE`;
  - the recorded digest and fingerprint;
  - EOA mode; and
  - no plan file picker and no EOA/Safe mode switch.

- [ ] Put the browser wallet on Sepolia, select the exact executing EOA, then
  click **Connect wallet**. The page must not show a chain or executor
  mismatch.

- [ ] Create the empty checkpoint directory before card 1:

  ```bash
  mkdir -p "$CHECKPOINT_DIR"
  test -z "$(find "$CHECKPOINT_DIR" -mindepth 1 -maxdepth 1 -print -quit)"
  ```

- [ ] Review card 1. It must call `returnOwnership()` on
  `0xa476920af80B587f696734430227869795E2Ea78`. Send it, wait for the receipt,
  and wait for the predicate to become `verified` before touching card 2.

- [ ] Confirm the temporary ownership transition after card 1:

  ```bash
  test "$(cast call "$ARCH_CONTROLLER" \
    'owner()(address)' --rpc-url "$RPC_URL")" = "$EXPECTED_EXECUTOR"
  ```

  The check must pass before card 2.

- [ ] Walk cards 2–37 in order. For every card:

  1. Review the plain-language change and expected result. Expand
     **Technical Details** to review the target/artifact, decoded arguments,
     pending nonce, estimated gas, and gas limit shown by the page.
  2. Click the single active **Send transaction N** button.
  3. Confirm the wallet transaction is from the expected EOA on Sepolia.
  4. Wait for the receipt and a `verified` predicate before continuing.

  Clicking another rail row pins that transaction for review; the page shows
  which transaction the ceremony is actually waiting at. Use **Return to
  current** to follow execution again. After a successful transaction, the
  pane must advance to the next active card automatically. On desktop, the
  divider beside the rail can be dragged or adjusted with the arrow keys.

  Use the rehearsal-proven checkpoints below:

  | After card | Expected state | Evidence action |
  | --- | --- | --- |
  | 1 | Developer EOA temporarily owns the ArchController | Export and rename a checkpoint. |
  | 13 | All 12 release contracts are deployed | Export and rename a checkpoint. |
  | 23 | Six templates are added and both v2.5 factories are registered | Export and rename a checkpoint. |
  | 37 | Seven superseded factories are removed from both authority roles | Export before returning ownership. |
  | 38 | Helper owns the ArchController again | Export the final run-state. |

  The browser uses `run-state-v2-5.json` for every download. Immediately move
  each intermediate download into `$CHECKPOINT_DIR` with its card number, for
  example `run-state-v2-5-card-13.json`, so it cannot be confused with the
  final export. Browser storage remains the resume mechanism; checkpoints are
  incident evidence and an additional backup.

- [ ] If the browser or RPC disconnects after submission, do not resend the
  transaction. The page must identify the RPC outage explicitly and disable
  further preparation. Restore the endpoint, use **Retry RPC**, or reopen the
  exact same site origin; reconnect the same account and let the page recover
  the stored transaction hash and receipt.

  If a fatal halt occurs, use **Export run state** on the halt screen when it
  is enabled before changing anything. Preserve that export alongside the
  newest checkpoint, exact site build and origin, browser storage, displayed
  error, wallet transaction hash, and browser console. Do not clear storage,
  rebuild the site, switch origins, or skip the failed card.

- [ ] Review card 38. It must call
  `ArchController.transferOwnership(helper)` with
  `0xa476920af80B587f696734430227869795E2Ea78`. Send it and wait for its
  predicate to become `verified`.

- [ ] Confirm the final ownership state:

  ```bash
  test "$(cast call "$ARCH_CONTROLLER" \
    'owner()(address)' --rpc-url "$RPC_URL")" = "$EXPECTED_HELPER_OWNER"
  ```

  The check must pass before exporting the final run-state.

- [ ] Confirm the page says all plan predicates are green, then click
  **Export run state**. Copy the unedited download into the exact release path,
  replacing the placeholder with the real download path:

  ```bash
  test ! -e "$RUN_STATE"
  cp /absolute/path/to/downloaded/run-state-v2-5.json "$RUN_STATE"
  test "$(jq 'length' "$RUN_STATE")" = "38"
  ```

## Emergency ownership return

This is an abort procedure, not a way to continue past a failed card. Use it
only if the ceremony has halted after card 1 and before card 38.

1. Stop normal execution and preserve the exact URL/build, browser profile,
   browser storage, exported run-state, last transaction hash, and error text.
2. Check `owner()` first. If the helper already owns the ArchController, do not
   send another ownership transaction.
3. If the executing EOA still owns it, submit exactly
   `ArchController.transferOwnership(helper)` from that EOA using the reviewed
   signing method. If the key is already loaded securely into the current
   shell, the repository's cast form is:

   ```bash
   export HELPER_OPERATOR_KEY="${HELPER_OPERATOR_KEY:-$PVT_KEY_SEPOLIA}"
   cast send "$ARCH_CONTROLLER" \
     'transferOwnership(address)' \
     "$EXPECTED_HELPER_OWNER" \
     --rpc-url "$RPC_URL" \
     --private-key "$HELPER_OPERATOR_KEY"

   cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL"
   ```

4. Record the recovery transaction hash. Do not run step 08 or improvise a
   run-state edit. Reconcile the external recovery receipt and partial run with
   a developer before deciding whether the original plan can be resumed or a
   new plan is required.

Do not paste a private key into terminal history merely to make this command
convenient. A configured hardware wallet, keystore, or other reviewed signer is
preferable when available.

## 7. Verify and finalize the recorded run

Return to the repository root before running these commands.

- [ ] Confirm the run-state is valid JSON and contains one entry per plan card:

  ```bash
  jq 'length' "$RUN_STATE"
  ```

  It must print `38`.

- [ ] Independently re-run every on-chain predicate. The final line must be
  `Verification passed: 38 predicate(s).`:

  ```bash
  node scripts/plan.js verify \
    --plan "$PLAN" \
    --run-state "$RUN_STATE" \
    --rpc "$RPC_URL"
  ```

- [ ] Apply the receipt-proven run to the inventory:

  ```bash
  RUN_STATE="$RUN_STATE" RPC_URL="$RPC_URL" \
    bash script/deploy/v2-5/08-finalize-inventory.sh
  ```

- [ ] Validate, lint, and reconcile the finalized inventory:

  ```bash
  node scripts/factory-inventory.js validate \
    --network "$DEPLOYMENTS_NETWORK"
  node scripts/factory-inventory.js lint \
    --network "$DEPLOYMENTS_NETWORK"
  node scripts/factory-inventory.js reconcile \
    --network "$DEPLOYMENTS_NETWORK" \
    --rpc-url "$RPC_URL"
  ```

  Reconciliation must be green.

## 8. Explorer verification and canary gate

Explorer verification remains required before treating the public rollout as
complete.

- [ ] List the 12 deployment receipts and artifact names:

  ```bash
  jq -r --slurpfile state "$RUN_STATE" '
    .transactions[]
    | select(.kind == "deploy")
    | [.id, .artifactName, $state[0][.id].resolvedAddress]
    | @tsv
  ' "$PLAN"
  ```

- [ ] For every row, preserve the deploy-profile standard JSON input and verify
  the contract with the matching explorer. Compare recovered constructor
  arguments with the plan before accepting `--guess-constructor-args`. See
  [deployment.md](./deployment.md#explorer-verification) for the command form.

- [ ] Select and verify the Sepolia canary inputs. The current intended borrower
  is the developer EOA, which is already registered, and the intended asset is
  the deployed Sepolia mock token. Resolve both from reviewed inputs rather than
  relying on the script's fallback:

  ```bash
  export BORROWER="$EXPECTED_EXECUTOR"
  export CANARY_ASSET="$(jq -r '."MockERC20:Token"' \
    "$REPO_ROOT/deployments/sepolia/deployments.json")"

  test "$CANARY_ASSET" != "null"
  test "$CANARY_ASSET" != "0x0000000000000000000000000000000000000000"
  test "$(cast code "$CANARY_ASSET" --rpc-url "$RPC_URL")" != "0x"
  test "$(cast call "$ARCH_CONTROLLER" \
    'isRegisteredBorrower(address)(bool)' \
    "$BORROWER" --rpc-url "$RPC_URL")" = "true"
  cast call "$CANARY_ASSET" \
    'balanceOf(address)(uint256)' \
    "$BORROWER" --rpc-url "$RPC_URL"
  ```

  The balance must be at least `2000000000000000`. If any check fails, stop;
  do not register a different borrower or substitute an arbitrary asset during
  the release run.

- [ ] Run both canaries. This is a separate direct-broadcast phase after the
  ceremony, not one of its 38 cards. The current script does not use the browser
  wallet on a public RPC, so load the developer testnet key into
  `PVT_KEY_SEPOLIA` using the existing secure operator method. Do not paste it
  into this document or a command line:

  ```bash
  : "${PVT_KEY_SEPOLIA:?Load the Sepolia developer key securely}"
  export OWNER_MODE=direct
  bash script/deploy/v2-5/09-canary-market.sh
  unset PVT_KEY_SEPOLIA
  export OWNER_MODE=plan
  ```

  Require output for both `Standard` and `Revolving` showing a nonzero deposit,
  closure, and a nonzero finalized withdrawal. The script rejects a key whose
  derived address is not `BORROWER`.

- [ ] Finish with another independent verification and reconciliation, then
  generate and check the downstream handoff:

  ```bash
  node scripts/plan.js verify \
    --plan "$PLAN" \
    --run-state "$RUN_STATE" \
    --rpc "$RPC_URL"

  node scripts/factory-inventory.js validate \
    --network "$DEPLOYMENTS_NETWORK"
  node scripts/factory-inventory.js lint \
    --network "$DEPLOYMENTS_NETWORK"
  node scripts/factory-inventory.js reconcile \
    --network "$DEPLOYMENTS_NETWORK" \
    --rpc-url "$RPC_URL"

  node scripts/generate-handoff.js \
    --network "$DEPLOYMENTS_NETWORK" \
    --release "$RELEASE_TAG"
  node scripts/generate-handoff.js \
    --network "$DEPLOYMENTS_NETWORK" \
    --release "$RELEASE_TAG" \
    --check
  ```

- [ ] Preserve the live evidence in a durable operator-selected directory, not
  in `TMPDIR`. At minimum retain the exact plan, package, checkpoints, final
  run-state, finalized deployment/inventory files, handoff, source revision,
  preflight block, package digest, transaction hashes, and explorer-verification
  inputs/results.

- [ ] Review tracked changes and generated outputs separately. The plan,
  package, pending inventory, checkpoints, and run-state remain local release
  artifacts unless the team deliberately chooses to preserve them in Git. The
  finalized tracked inventory/deployment aliases and handoff are durable
  repository changes. Never bulk-stage credentials, RPC URLs, browser storage,
  ignored reconcile reports, or unrelated generated files.

The deployment ceremony is complete when all 38 predicates verify, ownership
is back with the helper, step 08 has finalized the inventory, and reconciliation
is green. The Sepolia release is ready to bless for mainnet only after explorer
verification, the canary run, and downstream handoff review are also complete.
