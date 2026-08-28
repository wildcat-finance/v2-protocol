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

The Sepolia post-release factory replacement has its own
[`v2.5.3 fix-1 runbook`](./sepolia-v2-5-fix-1.md). It does not repeat the original
V2.5 authority ceremony.

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

Wildcat V2 bytecode uses EIP-1153 transient storage. The target chain must
support `TSTORE` and `TLOAD` on every execution path. Successful bytecode
deployment does not prove this.

Release tooling probes the capability. Manual and third-party deployments must
enforce the same Cancun-compatible boundary.

SphereX-protected factories cache an engine and pass it to new markets. During
an engine rotation:

1. Prevent market creation while the ArchController and factories disagree.
2. Keep the previous engine operational.
3. Update the controller and factories as one cutover.
4. Migrate existing registered contracts in bounded batches.

## Release workflow

1. **Prepare.** Freeze the source commit and `deploy` Foundry profile. Build and
   test that source. Validate, lint, and reconcile the inventory against the
   target chain.
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

Its `--check` mode validates the JSON and Markdown pair against current
deployment state.

Indexers should retain every generation with `indexAll == true`, including
superseded live factories. SDKs and deployment interfaces should route new
activity through canonical records.

Do not infer lifecycle from a version string, address age, or source ancestry.

## Extending the deployment set

1. Add a numbered release script. Give every step a unique plan ID, explicit
   dependencies, typed constructor or call inputs, and an onchain predicate.
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
