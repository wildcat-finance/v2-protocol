# Deployment

Wildcat deployments are versioned, receipt-backed state transitions.

- Release scripts describe the intended changes.
- Plans lock the transaction sequence.
- Run-state records prove what happened.
- Inventories and handoffs describe the result.

The current release implementation lives in
[`script/deploy/v2-5/`](../../script/deploy/v2-5/). This is release-specific
code, not a generic checklist. Read the scripts and generated plan for the exact
contracts, authority path, and transaction order.

Use the [operator checklist](../../script/deploy/CEREMONY_CHECKLIST.md) with the
runbook and frozen plan for the release being executed. Sepolia runbooks cover:

- [v2.5.7](./sepolia-v2.5.7.md): delegated-transfer sanctions patch and
  replacement factories.
- [v2.5.6](./sepolia-v2.5.6.md): hook-template update.
- [v2.5.5](./sepolia-v2.5.5.md): factory-replacement activation.
- [v2.5.3 fix-1](./sepolia-v2-5-fix-1.md): historical factory activation.

## Machine-readable authority

- `deployments/<network>/deployments.json`: Deployed addresses,
  release-labelled history, and current aliases.
- `factory-inventory.json`: Append-only factory generations, lifecycle,
  registration, and indexing policy.
- `plan-<release>.json`: Reviewed transaction order, executor, calldata,
  dependencies, and postconditions.
- `run-state-<release>.json`: Transaction receipts and verified progress.
- `handoff-<release>.json`: Final release contracts, ABI sources, routing, and
  downstream indexing state.

The JSON schemas live in [`deployments/`](../../deployments/). Generated
Markdown handoffs are reading aids. The matching JSON is the integration
artifact.

A predicted address or generated plan is not deployment evidence. It needs a
verified receipt.

## Runtime requirements

The `deploy` profile inherits the compiler settings in
[`foundry.toml`](../../foundry.toml): Solidity `0.8.25`, Cancun, via-IR,
optimizer runs `1`, and the pinned Yul sequence without FunctionSpecializer.
Use the complete settings for artifact reproduction and source verification;
the run count alone does not reproduce the deployment bytecode. Both market
runtimes fit EIP-170 with this configuration. Split storage addresses
creation-code storage size and does not change that runtime limit.

Wildcat V2 bytecode uses EIP-1153 transient storage. The target chain must
support `TSTORE` and `TLOAD` on every execution path. Successful bytecode
deployment does not prove this.

Release tooling probes the capability. Manual and third-party deployments must
enforce the same Cancun-compatible boundary.

SphereX-protected factories cache an engine for registered-contract migration.
V2.5 factories source the engine assigned to new markets directly from the
ArchController. During an engine rotation:

1. Prevent market creation while the ArchController and factories disagree.
2. Keep the previous engine operational.
3. Update the controller and factories as one cutover.
4. Migrate existing registered contracts in bounded batches.

## Stored creation code

The factory deploys markets and hook instances from reviewed creation-code
artifacts. Hook policies are compiled into each concrete template before this
step; the factory does not assemble policies during deployment.

[`LibDeployment`](../../script/common/LibDeployment.sol) keeps the raw
`STOP || creation code` format when the artifact fits its 24,575-byte payload
limit. Larger artifacts use [two storage contracts](../../src/libraries/LibSplitInitCode.sol).
The primary holds a small reader and the first bytes; the secondary holds
`STOP || remaining bytes`. The factory receives the primary address, whose
reader copies and returns the original creation code. There is no compression.
Each storage runtime must fit 24,576 bytes. The current reader leaves room for
49,013 original bytes across the pair; total creation code including constructor
arguments must also fit the separate 49,152-byte limit.

Plan generation prepares both images locally. The
[`PreparedInitCodeStorage` and `LinkedInitCodeStorage` constructors](../../script/common/PreparedInitCodeStorage.sol)
install the secondary first, then bind its address into the primary's prepared
footer. The reader, payload and lengths are copied unchanged. Each secondary
gets its own plan output, transaction, inventory record and deployment label;
the label appends `_secondary` to its primary's label. Original template and
factory references continue to use the primary.

Raw storage uses `codeHash`, with `expect` for its runtime and `initCodeHash`
for the original creation code. Split storage uses `splitCodeHash`: `expect`
commits the primary runtime with its secondary-address field zeroed;
`secondary` identifies that deployment, and `secondaryCodeHash` commits its
complete runtime. The CLI and UI check the embedded link, both complete images,
and then the reader's output against `initCodeHash`. They authenticate the
reader before calling it. Resume repeats all checks.

Direct deployment verifies and reuses a recorded secondary if installation
stopped before the primary. Reusing a complete primary verifies both images
and their link; a conflicting recorded secondary fails. Build the plan, CLI,
and UI from the same reviewed source; older executors do not support the split
predicate. The historical compression experiment remains available for research
but is not accepted by the current direct-deployment verifier.

Both factories additionally check the decoded market creation-code hash before
`CREATE2`, using the same bytes for hashing and deployment. Hook registration
requires the original artifact's `initCodeHash` as the last `addHooksTemplate`
argument. Each factory checks the decoded bytes, records that commitment, and
checks it again before every hook deployment. A mismatch reverts before the
constructor runs. This covers both hook-only and combined market/hook creation.
Constructor arguments are appended after this check.

The commitment is readable through `getHooksTemplateInitCodeHash` and emitted
in `HooksTemplateInitCodeHashRecorded`. Fee changes and disabling a template
cannot change it. Registration plan predicates check the recorded hash, and
activation validation requires it to match the storage entry's artifact hash.
There is no registration overload without a hash. An arbitrary executable
store still fails canonical runtime verification in the supplied tools; a
hash reported by that same store is not an independent reference.

[`rcf-template-sync.js`](../../scripts/rcf-template-sync.js) requires these
commitments before applying any changes to a new factory. An export from an
older factory has `initCodeHash: null`; populate it from the reviewed original
creation artifacts before using `--input`. The tool does not hash live decoder
output to invent a commitment. Historical factories and the Sepolia fix-1
ceremony require their pinned historical tooling; do not regenerate their
plans with the current interface.

## Release workflow

1. **Prepare.** Freeze the source commit and `deploy` Foundry profile. Build and
   test that source. Finalize network parameters, including the fixed-term
   maximum, repayment-date and period caps, and the periodic policy's
   `TODO FOR MAINNET` constants. Validate, lint, and reconcile the inventory
   against the target chain.
2. **Assemble.** Run the numbered release scripts in plan mode. Assemble them
   with [`plan.js`](../../scripts/plan.js). Validate the plan schema and the
   activation or retirement boundary.
3. **Rehearse.** Execute the same plan and executor mode on a pinned target-chain
   fork. For Safe execution, build and simulate the exact bundles. Build the UI
   from the reviewed package. Publish its digest through an independent channel.
4. **Execute and verify.** Use the executor named by the plan. Halt on any failed
   predicate or identity mismatch. Export the unedited run-state. Verify its
   receipts and re-check every completed postcondition onchain.
5. **Finalize.** Apply the verified run-state to the inventory. Validate, lint,
   and reconcile again. Generate and check the handoff. Downstream consumers
   take addresses and indexing policy from that handoff.

The plan schema fixes:

- `foundryProfile` to `deploy`.
- `onFailure` to `halt`.
- Resume behavior to re-verification of prior predicates.

Each entry also binds the chain, executor, artifact, constructor types or
calldata, dependencies, and onchain completion predicate.

## Factory lifecycle

- Inventory records are append-only. Do not delete a generation or relabel it
  to simplify the current state.
- `canonical` serves new deployments. `live` is superseded but stays indexed
  for existing markets. `retired` stays recorded and is excluded from indexing.
- Keep exactly one canonical hooks factory per market type and one canonical
  wrapper factory. Canonical hooks factories must be registered and indexed.
- Release-labelled `deployments.json` keys are history. Plain aliases identify
  the current selection and must agree with canonical inventory records.
- Activation and factory deactivation are separate ceremonies. Release tooling
  calls deactivation a retirement. It removes only controller-factory and
  controller registrations. It does not remove markets or automatically change
  lifecycle and indexing records.

Before a registry write, verify:

- Deployed code.
- Expected interfaces.
- The factory, controller, and market relationship.

The deployed ArchController singleton does not treat registry insertion as full
runtime interface validation.

Registry pagination uses half-open ranges. Callers must ensure:

```text
start <= min(end, count)
```

Malformed ranges on the deployed singleton can revert with an arithmetic panic.

[`factory-inventory.js`](../../scripts/factory-inventory.js) handles:

- Validation and linting.
- Live reconciliation.
- Activation finalization.
- Retirement generation and finalization.

Reconciliation checks controller registrations, deployed code, wrapper-factory
links, canonical aliases, and receipt-backed start blocks.

## Executor and ceremony boundary

Generational activation and retirement use plan mode. Plan generation does not
need a private key.

Network-specific ownership and forwarding rules belong in the reviewed
`deployments/<network>/ceremony-config.json`. Plan assembly applies them.

[`plan.js`](../../scripts/plan.js) has native mappings for mainnet, Sepolia, and
Anvil. Any other network must provide:

- A consistent chain ID in every plan-entry envelope.
- Reviewed authority configuration.

The [deployment UI](../../deploy-ui/README.md) is a disposable executor for one
locked ceremony package. Production builds embed that package and expose no
editable calldata.

- EOA mode executes and verifies one plan transaction at a time.
- Safe mode rebuilds bundles from the plan, pins Safe nonces and transaction
  hashes, and verifies execution against the reviewed manifests.

Direct Forge broadcasting is only suitable for reviewed component maintenance
or isolated development. It does not replace generational finalization. It
lacks the plan and run-state provenance needed to move canonical inventory.

## Stop conditions

- The source commit, compiler profile, artifacts, plan, package digest, chain,
  or executor differs from the reviewed set.
- A computed address, constructor encoding, calldata fingerprint, Safe nonce,
  or transaction hash differs from the plan.
- A precondition or postcondition fails, a prior completed step no longer
  verifies, or the exported run-state was edited.
- Inventory validation, append-only checks, live reconciliation, or handoff
  validation fails.
- The proposed retirement targets a canonical generation or any existing
  market.

Do not repair a live ceremony in place.

1. Halt.
2. Preserve the evidence.
3. Correct the source or state inputs.
4. Regenerate the affected artifacts.
5. Rehearse the new package.

## Handoff and downstream use

[`generate-handoff.js`](../../scripts/generate-handoff.js) combines:

- Final inventory and deployment addresses.
- The release contract list and ABI artifacts.
- Routing and indexing rules.
- Available plan and run-state provenance.

Storage records require verified plan metadata to identify their actual
installer. Split companions appear as separate release contracts, using the
primary deployment key with `_secondary` appended. Preserve both receipts
and addresses when exporting the handoff.

Its `--check` mode validates the JSON and Markdown pair against current
deployment state.

Indexers should retain every generation with `indexAll == true`, including
superseded live factories. SDKs and deployment interfaces should route new
activity through canonical records.

Do not infer lifecycle from a version string, address age, or source ancestry.

## Extending the deployment set

1. Add a numbered release script. Give every step a unique plan ID, explicit
   dependencies, typed constructor or call inputs, and an onchain predicate.
   Name IDs `verb-subject[-qualifier]` in lowercase kebab case, reusing the
   existing verbs and subjects, for example `deploy-open-term-hooks-init-code-storage`
   or `add-standard-open-term-template`. The ceremony UI builds its step labels
   from the ID, so keep each description to one plain sentence.
2. Add the generation or component to inventory validation without weakening
   append-only or canonical-count constraints.
3. Define applicable hook templates and reviewed fees in
   [`template-fee-parameters.json`](../../deployments/template-fee-parameters.json).
4. Add its contract, ABI, routing, and indexing semantics to the handoff
   generator.
5. Rehearse and verify activation and eventual retirement on target-chain forks
   before proposing a public-network ceremony.

## Command reference

Use live help instead of copied option tables:

```sh
node scripts/plan.js --help
node scripts/factory-inventory.js --help
node scripts/generate-handoff.js --help
node scripts/validate-factory-inventory.js --help
```
