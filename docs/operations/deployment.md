# Deployment

Wildcat deployments are versioned, receipt-backed state transitions. Release
scripts describe what should happen; plans lock the transaction sequence;
run-state records prove what happened; inventories and handoffs describe the
result.

The current release implementation is under
[`script/deploy/v2-5/`](../../script/deploy/v2-5/). It is release-specific code,
not a reusable checklist. Read the scripts and generated plan for the exact
contracts, authority path, and ordering of a deployment.

## Machine-readable authority

| Artifact | Authority |
| --- | --- |
| `deployments/<network>/deployments.json` | Deployed addresses, release-labelled history, and current aliases. |
| `factory-inventory.json` | Append-only factory generations, lifecycle, registration, and indexing policy. |
| `plan-<release>.json` | Reviewed transaction order, executor, calldata, dependencies, and postconditions. |
| `run-state-<release>.json` | Transaction receipts and verified execution progress. |
| `handoff-<release>.json` | Final release contracts, ABI sources, routing, and downstream indexing state. |

The JSON schemas live in [`deployments/`](../../deployments/). Generated
Markdown handoffs are reading aids; the matching JSON remains the integration
artifact. A predicted address or generated plan is not deployment evidence
without a verified receipt.

## Runtime Requirements

Wildcat V2 bytecode uses EIP-1153 transient storage. A target chain must support
`TSTORE` and `TLOAD` on every execution path; successful bytecode deployment is
not sufficient evidence. The release tooling probes this capability, and manual
or third-party deployments must enforce the same Cancun-compatible boundary.

SphereX-protected factories cache an engine and pass it into newly deployed
markets. An engine rotation must prevent market creation while the
ArchController and market-deploying factories disagree. Keep the prior engine
operational, update the controller and factories as one cutover, then migrate
existing registered contracts in bounded batches.

## Release workflow

1. **Prepare.** Freeze the source commit and `deploy` Foundry profile. Build and
   test that source. Validate, lint, and reconcile the existing inventory
   against the target chain before generating a new state transition.
2. **Assemble.** Run the numbered release scripts in plan mode. Assemble their
   entries with [`plan.js`](../../scripts/plan.js), then validate both the plan
   schema and the activation or retirement boundary.
3. **Rehearse.** Execute the same plan and executor mode on a pinned target-chain
   fork. For Safe execution, build and simulate the exact bundles. Build the
   deployment UI from the reviewed ceremony package and publish its digest
   through an independent channel.
4. **Execute and verify.** Use the executor named by the plan. Halt on any
   failed predicate or identity mismatch. Export the unedited run-state, verify
   its receipt provenance, and re-check every completed postcondition on-chain.
5. **Finalize.** Apply the verified run-state to the inventory, then validate,
   lint, and reconcile again. Generate and check the release handoff. Downstream
   consumers adopt addresses and indexing policy from that handoff.

The plan schema fixes `foundryProfile` to `deploy`, `onFailure` to `halt`, and
resume behavior to re-verification of prior predicates. Plan entries also bind
the chain, expected executor, artifact, constructor types or call data,
dependencies, and on-chain completion predicate.

## Factory lifecycle

- Inventory records are append-only. Do not delete a generation or change its
  label to make the current state look simpler.
- `canonical` is selected for new deployments. `live` is superseded but still
  indexed for existing markets. `retired` remains recorded and is excluded
  from indexing.
- Keep exactly one canonical hooks factory per market type and one canonical
  wrapper factory. Canonical hooks factories must be registered and indexed.
- Release-labelled `deployments.json` keys are history. Plain aliases identify
  the current selection and must agree with canonical inventory records.
- Activation and factory deactivation are separate ceremonies. The release
  tooling calls deactivation a retirement, but it removes only controller
  factory and controller registrations. It does not remove markets or
  automatically change lifecycle and indexing records.

Before any registry write, verify deployed code, expected interfaces, and the
factory/controller/market relationship. The deployed ArchController singleton
does not use registry insertion as full runtime interface validation.

Registry pagination uses half-open ranges. Callers must ensure
`start <= min(end, count)`; malformed ranges on the deployed singleton can
revert with arithmetic panic.

[`factory-inventory.js`](../../scripts/factory-inventory.js) owns validation,
linting, live reconciliation, activation finalization, retirement generation,
and retirement finalization. Reconciliation checks controller registrations,
deployed code, wrapper-factory links, canonical aliases, and recorded start
blocks where receipts are available.

## Executor and ceremony boundary

Generational activation and retirement use plan mode. Plan generation does not
require a private key. Network-specific ownership or forwarding rules belong in
the reviewed `deployments/<network>/ceremony-config.json` and are applied while
assembling the plan.

[`plan.js`](../../scripts/plan.js) has native chain mappings for mainnet,
Sepolia, and Anvil. Another network must supply a consistent chain ID in its
plan-entry envelopes and provide reviewed authority configuration.

The [deployment UI](../../deploy-ui/README.md) is a disposable executor for a
locked ceremony package. Production builds embed one package and expose no
editable calldata. EOA mode executes and verifies one plan transaction at a
time. Safe mode rebuilds bundle payloads from the plan, pins Safe nonces and
transaction hashes, and verifies execution against the reviewed manifests.

Direct Forge broadcasting is suitable only for explicitly reviewed component
maintenance or isolated development. It is not a substitute for generational
finalization because it does not provide the plan/run-state provenance required
to move canonical inventory.

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

Do not repair a live ceremony in place. Halt, preserve the evidence, correct
the source or state inputs, regenerate the affected artifacts, and rehearse the
new package.

## Handoff and downstream use

[`generate-handoff.js`](../../scripts/generate-handoff.js) combines the final
inventory and deployment addresses with the release contract list, ABI
artifacts, routing rules, and available plan/run-state provenance. Its `--check`
mode validates the JSON and Markdown pair against current deployment state.

Indexers should retain every generation with `indexAll == true`, including
superseded live factories. SDKs and deployment interfaces should route new
activity through canonical records. Neither should infer lifecycle from a
version string, address age, or source ancestry.

## Extending the deployment set

1. Add a numbered release script with unique plan IDs, explicit dependencies,
   typed constructor or call inputs, and an on-chain predicate for every step.
2. Add the generation or component to inventory validation without weakening
   append-only or canonical-count constraints.
3. Define applicable hook templates and reviewed fees in
   [`template-fee-parameters.json`](../../deployments/template-fee-parameters.json).
4. Add its contract, ABI, routing, and indexing semantics to the handoff
   generator.
5. Rehearse and verify both activation and eventual retirement on target-chain
   forks before proposing a public-network ceremony.

## Command reference

Use the tools' live help instead of copied option tables:

```sh
node scripts/plan.js --help
node scripts/factory-inventory.js --help
node scripts/generate-handoff.js --help
node scripts/validate-factory-inventory.js --help
```
