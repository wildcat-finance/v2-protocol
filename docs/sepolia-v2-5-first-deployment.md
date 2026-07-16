# v2.5 Sepolia first-deployment checklist

This is the operator walkthrough for the first real v2.5 deployment. It uses
the same generated plan and locked release-site shape intended for mainnet, but
executes each card from the Sepolia developer EOA instead of a Safe.

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
| Expected ceremony length | 24 transactions |

Do not rely on an earlier balance, nonce, authorization, or ownership check.
Repeat every live preflight below immediately before deploying.

## Stop conditions

Do not start or continue the ceremony if any of these is true:

- The RPC or wallet is not on chain `11155111`.
- The connected account is not the exact executing EOA above.
- The helper does not own the ArchController before card 1.
- `authorizedAccounts(executing EOA)` is not `true` on the helper.
- inventory reconciliation is not green.
- the generated plan is not profile `deploy`, executor-matched, and exactly 24
  cards with reclaim first and restore last.
- there is an unresolved pending transaction from the executing EOA.
- the UI reports a fatal halt, a reverted receipt, or a failed predicate.

There is intentionally no skip path. A failed predicate is a deployment
incident, not a prompt to move to the next card.

## 1. Prepare the release shell

All commands in this document assume the repository root.

```bash
export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=sepolia
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export RPC_URL='<your Sepolia RPC URL>'

export EXPECTED_EXECUTOR=0xca732651410E915090d7A7D889A1E44eF4575fcE
export TEMPLATE_FEE_RECIPIENT=0xca732651410E915090d7A7D889A1E44eF4575fcE
export ARCH_CONTROLLER=0xC003f20F2642c76B81e5e1620c6D8cdEE826408f
export EXPECTED_HELPER_OWNER=0xa476920af80B587f696734430227869795E2Ea78

export PLAN="deployments/$DEPLOYMENTS_NETWORK/plan-$RELEASE_TAG.json"
export PACKAGE="deployments/$DEPLOYMENTS_NETWORK/ceremony-$RELEASE_TAG-eoa.json"
export RUN_STATE="deployments/$DEPLOYMENTS_NETWORK/run-state-$RELEASE_TAG.json"
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
  export ARTIFACT_BACKUP="${TMPDIR:-/tmp}/wildcat-v2-5-sepolia-$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$ARTIFACT_BACKUP"
  for artifact in \
    deployments/sepolia/plan-entries \
    deployments/sepolia/inventory-pending \
    "$PLAN" \
    "$PACKAGE"
  do
    if [[ -e "$artifact" ]]; then
      mv "$artifact" "$ARTIFACT_BACKUP"/
    fi
  done
  echo "$ARTIFACT_BACKUP"
  ```

  This avoids mixing stale entries into the new plan without deleting the
  previous output. Do not run `plan.js execute`, add `--broadcast`, or export a
  private key for this walkthrough; the browser is the executor in section 6.

## 2. Run the live preflight

- [ ] Confirm the RPC chain. The output must be `11155111`:

  ```bash
  cast chain-id --rpc-url "$RPC_URL"
  ```

- [ ] Resolve the current owner. It must exactly equal
  `0xa476920af80B587f696734430227869795E2Ea78` before card 1:

  ```bash
  export HELPER_OWNER="$(cast call "$ARCH_CONTROLLER" \
    'owner()(address)' --rpc-url "$RPC_URL")"
  echo "$HELPER_OWNER"
  echo "$EXPECTED_HELPER_OWNER"
  ```

- [ ] Confirm the executing EOA is authorized. The output must be `true`:

  ```bash
  cast call "$HELPER_OWNER" \
    'authorizedAccounts(address)(bool)' \
    "$EXPECTED_EXECUTOR" \
    --rpc-url "$RPC_URL"
  ```

- [ ] Confirm the EOA is funded, and record its latest and pending nonces:

  ```bash
  cast balance "$EXPECTED_EXECUTOR" --ether --rpc-url "$RPC_URL"
  cast nonce "$EXPECTED_EXECUTOR" --block latest --rpc-url "$RPC_URL"
  cast nonce "$EXPECTED_EXECUTOR" --block pending --rpc-url "$RPC_URL"
  ```

  The two nonces must match before opening the ceremony. If they differ, wait
  for or resolve the pending transaction first. Do not use this EOA for any
  unrelated transaction until all 24 cards are complete.

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

- [ ] Compile once with the mandatory deploy profile:

  ```bash
  forge build --sizes src script/common script/deploy/v2-5
  ```

  A cold build can take roughly ten minutes. Do not fall back to the default
  profile: `HooksFactoryRevolving` exceeds EIP-170 there, and the resulting
  creation code would not be the reviewed deployment artifact. The command is
  scoped to production contracts and the v2.5 deployment scripts because
  several test harnesses intentionally exceed EIP-3860 initcode limits and are
  never deployed by the release ceremony.

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

  The wrapper should report `24 tx (12 deploy, 12 call)` for Sepolia.

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
  - 24 transactions;
  - first ID `reclaim-arch-controller-ownership`, calling
    `returnOwnership()` on the mock owner helper; and
  - last ID `restore-arch-controller-ownership`, calling
    `transferOwnership(address)` on the ArchController with the helper as its
    argument.

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

  It must print exactly six rows. For this Sepolia pass, every fee recipient
  must be the configured developer EOA, every origination fee asset must be the
  zero address, every origination fee amount must be `0`, and every protocol
  fee must be `500` bips. The fee-recipient role is independent of the
  transaction-executor role even though both deliberately use the same address
  here.

## 4. Package the exact EOA ceremony

- [ ] Generate the immutable browser package:

  ```bash
  node scripts/plan.js ceremony-package \
    --plan "$PLAN" \
    --mode eoa
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

- [ ] Install from the lockfile and build:

  ```bash
  cd deploy-ui
  npm ci
  CEREMONY_PACKAGE=../deployments/sepolia/ceremony-v2-5-eoa.json \
    npm run build
  ```

- [ ] Serve the built `dist/` without rebuilding it:

  ```bash
  npm exec -- vite preview \
    --host 127.0.0.1 \
    --port 4173 \
    --strictPort
  ```

- [ ] Keep that terminal open and visit `http://127.0.0.1:4173/` in the
  browser profile containing the executing EOA. For live checks during the
  ceremony, open a second terminal at the repository root and repeat the
  exports in section 1; shell variables are not inherited by a new terminal.
  After the ceremony, you can instead stop the preview with `Ctrl-C`, run
  `cd ..`, and keep using the original shell and its exports.

  Building and serving locally does not require any generated deployment file
  to be tracked by Git. The package bytes are embedded into `deploy-ui/dist/`
  during the build.

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

## 6. Walk the live 24-card EOA ceremony

This is the live boundary. Nothing in sections 1–5 changed Sepolia. Clicking
**Send transaction 1** below temporarily moves ArchController ownership from
the helper to the developer EOA.

- [ ] Open the locked site and confirm, before connecting:

  - release `v2-5`, network `sepolia`, chain `11155111`;
  - exactly 24 transactions;
  - expected executor `0xca732651410E915090d7A7D889A1E44eF4575fcE`;
  - the recorded digest and fingerprint;
  - EOA mode; and
  - no plan file picker and no EOA/Safe mode switch.

- [ ] Put the browser wallet on Sepolia, select the exact executing EOA, then
  click **Connect wallet**. The page must not show a chain or executor
  mismatch.

- [ ] Review card 1. It must call `returnOwnership()` on
  `0xa476920af80B587f696734430227869795E2Ea78`. Send it, wait for the receipt,
  and wait for the predicate to become `verified` before touching card 2.

- [ ] Confirm the temporary ownership transition after card 1:

  ```bash
  cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL"
  ```

  It must now return the executing EOA.

- [ ] Walk cards 2–23 in order. For every card:

  1. Review the description, target/artifact, decoded arguments, pending nonce,
     estimated gas, and gas limit shown by the page.
  2. Click the single active **Send transaction N** button.
  3. Confirm the wallet transaction is from the expected EOA on Sepolia.
  4. Wait for the receipt and a `verified` predicate before continuing.

- [ ] Export a progress run-state after card 1 and at sensible checkpoints.
  Keep the newest copy. Browser storage is the resume mechanism; exported
  copies are incident evidence and an additional backup.

- [ ] If the browser or RPC disconnects after submission, do not resend the
  transaction. Reopen the exact same site origin, reconnect the same account,
  and let the page recover the stored transaction hash and receipt.

- [ ] Review card 24. It must call
  `ArchController.transferOwnership(helper)` with
  `0xa476920af80B587f696734430227869795E2Ea78`. Send it and wait for its
  predicate to become `verified`.

- [ ] Confirm the final ownership state:

  ```bash
  cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL"
  ```

  It must return the helper, not the developer EOA.

- [ ] Confirm the page says all plan predicates are green, then click
  **Export run state**. Save the unedited download at:
  `deployments/sepolia/run-state-v2-5.json`.

## Emergency ownership return

This is an abort procedure, not a way to continue past a failed card. Use it
only if the ceremony has halted after card 1 and before card 24.

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

  It must print `24`.

- [ ] Independently re-run every on-chain predicate. The final line must be
  `Verification passed: 24 predicate(s).`:

  ```bash
  node scripts/plan.js verify \
    --plan "$PLAN" \
    --run-state "$RUN_STATE" \
    --rpc "$RPC_URL"
  ```

- [ ] Apply the receipt-proven run to the inventory:

  ```bash
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

- [ ] Generate and check the downstream handoff:

  ```bash
  node scripts/generate-handoff.js \
    --network "$DEPLOYMENTS_NETWORK" \
    --release "$RELEASE_TAG"
  node scripts/generate-handoff.js \
    --network "$DEPLOYMENTS_NETWORK" \
    --release "$RELEASE_TAG" \
    --check
  ```

- [ ] Review the final repository diff and generated outputs separately. The
  plan, package, pending inventory, and run-state remain untracked local release
  artifacts unless the team deliberately chooses to preserve them after the
  successful run. The finalized tracked inventory/deployment aliases and
  handoff are durable repository changes. Never bulk-stage credentials, RPC
  URLs, browser state, ignored reconcile reports, or unrelated generated files.

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

- [ ] Do not run `09-canary-market.sh` until both unresolved operator inputs are
  deliberately selected: a registered `BORROWER` and the Sepolia
  `CANARY_ASSET`. The canary is a separate direct-broadcast phase, not one of
  the 24 ceremony cards. Once those values are reviewed, follow
  [deployment.md](./deployment.md#09--canary-markets).

The deployment ceremony is complete when all 24 predicates verify, ownership
is back with the helper, step 08 has finalized the inventory, and reconciliation
is green. The Sepolia release is ready to bless for mainnet only after explorer
verification, the canary run, and downstream handoff review are also complete.
