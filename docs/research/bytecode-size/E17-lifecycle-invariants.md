# E17: repayment and default invariants

Source parent: `95e6f0c` (E16). Status: complete. Both compiler configurations,
additional seeds, longer sequences, and fault controls are qualified below.

Expand stateful coverage of the V2.5 repayment and default features before the
deployment rehearsal. The user has confirmed that an Anvil-fork rehearsal is
required, with the ceremony update and release-build gates handled afterward
or alongside it. A second execution client is optional and is not a gate for
this work. No compiler-profile or deployment-ceremony changes are part of E17.

The behavior contract is the accepted
[repayment/default specification](../../specs/v2.5-tranching-preparation.md),
including inclusive cutoffs and automatic funded closure. Do not reopen those
decisions or introduce tranche policy. FastLZ remains the selected research
candidate; the normal compiler configuration remains runs 44.

## Starting coverage

[E16](./E16-hook-artifact-commitment.md) passes 463 focused tests under runs 44
and runs 1/no F. Its existing invariant campaign retains nine properties,
2,000 runs, depth 30, 17 actions, and 60,000 handler calls with zero reverts.

The six invariant cells cover standard/revolving markets with open, fixed,
and periodic hooks, but all have disabled repayment terms. The revolving
cells also have zero delinquency fees. The separate
[repayment scenarios](../../../test/integration/RepaymentPrototype.t.sol)
exercise important boundaries, including same-block cures, late repayment,
donations, and closure. They do not replace randomized lifecycle sequences.

The existing [handler](../../../test/invariants/MarketMatrixHandler.sol)
needs deliberate extension:

- Deposit success currently assumes the market remains open for deposits until
  closure. Repayment also closes admission while debt can remain outstanding.
- Withdrawal admission currently follows the term hook or closure. Repayment
  independently bypasses queue restrictions.
- `warp` advances time and immediately updates every market. It cannot exercise
  a long idle interval followed by repayment as the first state-changing call.
- The revolving oracle currently splits at batch expiry, without repayment or
  historical funded-closure boundaries.
- The final unwind uses manual closure. Scheduled campaigns also need to prove
  automatic completion and bounded batch settlement without that shortcut.

## Test structure

Preserve the existing no-date campaign, budgets, assertions, and final unwind
as regression evidence. Add concrete lifecycle suites rather than inheriting
test entrypoints. Share action execution, accounting checks, and fixtures where
the semantics match; avoid a copied second general-purpose handler.

Use real market and hook implementations across both models and all three term
policies. Reuse the current fixtures. Keep factory-created scenarios where
creation/configuration is what the assertion depends on; the existing factory
and compression matrix remains part of broader qualification.

Add independent test bookkeeping for observed funding, timestamps, pending
claims, and expected lifecycle outcomes. Do not use `MarketLifecycleLib` or the
production transition calculator to produce expected default/closure results.
View/write agreement is a separate property, not an independent accounting
oracle. Exact arithmetic helpers may be shared where their behavior is already
qualified; the timeline and expected outcomes must remain independent.

Keep expectations readable. Use explicit boundary scenarios to establish the
oracle, then apply randomized actions and delays around them. If the model and
market disagree, reduce the trace before deciding which one is wrong.

## Required properties

| Area | Property and cases |
| --- | --- |
| Immutable terms | Repayment date, period, and deadline remain fixed across actions. Distinguish disabled `(0,0)` from enabled `(futureDate,0)`. Include zero, ordinary positive, and maximum permitted periods. |
| Repayment admission | From the date, deposits and borrowing fail and their live capacity views report zero. A rejected call cannot commit a partial lifecycle transition. Earlier activity retains ordinary hook restrictions. |
| Reserve and APR | Repayment requires 100% reserves without borrower cooperation. Both APR routes retain their funding checks and cannot restore a lower reserve ratio. Pending periodic proposals cannot change a closed market's effective economics. |
| Penalty and cure | Underfunding at repayment starts penalty without unused ordinary grace. An earlier penalty episode continues. Observed cures reset the separate default run, without forgiving accrued amounts or resetting the economic timer. Zero penalty rate still permits default tracking. |
| Inclusive cutoffs | A cure at the deadline or 90-day cutoff counts, including a later transaction at the same timestamp after an earlier update. One second later is late. Zero-period terms obey the same rule. |
| Historical funding | Explicit repayment and direct transfers arriving after a cutoff cannot rewrite historical funding. Include a first update long after the date/deadline and transfers made earlier but first observed later. |
| Permanent default | Record the effective historical timestamp once. Cure, later causes, authority transfer, and closure cannot clear or replace it. Default alone does not close, accelerate repayment, change rates/reserves, or open withdrawals. Include default before the scheduled date. |
| Automatic completion | Full backing at/after the date closes permanently; partial funding or a one-unit shortfall does not. A late full repayment may close while retaining default. Full backing before the date or without terms does not itself close the market. |
| Closed economics | APR/accrual stop at the effective close time, revolving drawn principal clears through closure, and surplus handling preserves all lender and fee liabilities. Repeated maintenance cannot close or emit the transition again. |
| Withdrawal admission | Repayment bypasses queue-hook restrictions while direct queueing retains sanctions checks. Existing batch durations and keys remain intact until the selected funded-close handling applies. |
| Withdrawal collection | Accepted payable claims have no execution-hook veto, including no-date markets. The new core rejects effective configurations enabling that reserved callback bit. Sanctioned collection still routes to escrow. |
| Batch fairness and liveness | Preserve pro-rata entitlements, FIFO processing of old unpaid batches, and bounded maintenance. No duplicate claims or reopened consumed batch keys. Funded closure may release the current batch early; views and execution agree. |
| Conservation | Retain scaled-supply, withdrawal-liability, and protocol-fee conservation through boundary transitions and closure, with explicit rounding bounds. Donations add liquidity without becoming repayment events or principal repayments; closure independently settles principal. |
| Views, writes, and events | Repeated views do not write state or emit events. An explicit update agrees with the appropriate preview at the same timestamp and assets. `defaultedAt()` remains a stored marker until a successful write. Transition events are unique and chronologically correct. |

Collection is deliberately broader than a repayment-only bypass. The selected
spec removes `onExecuteWithdrawal` dispatch from every new market and rejects
that effective configuration bit at construction. Tests must not restore the
older callback expectation or require a callback before the repayment date.

## Generated sequences and coverage

Add time advancement that can leave state untouched, along with explicit update
actions. Bias timestamps around date, deadline, penalty cutoff, batch expiry,
fixed maturity, periodic windows, and pending APR execution: one second before,
exactly at, and one second after. Include ties and intervals crossing several
boundaries without a market call. Never warp backward.

Exercise partial/exact/excess repayment through both repayment entrypoints,
direct transfers, all queue/collection routes, bounded unpaid-batch processing,
fee collection, APR changes, and sanctions. Include the same-timestamp
update-then-cure sequence explicitly. Probe forbidden actions too; skipping
every action once repayment begins would hide broken admission rules.

Add controlled borrower/principal and hook-administrator transfer interleavings
to check that immutable terms and an already recorded default survive authority
changes. Reuse the existing authority fixtures and checks for those scenarios.

Use separate scenarios/campaigns for outcomes that cannot coexist on one
permanently closed market. Maintain coverage counters for actual transitions
and successful actions, including timely cure, missed deadline, continuous
penalty default, observed cure/re-entry, late closure, partial batch payment,
and completed collection. Report counts per model/policy. Seeded prerequisites
and randomized exploration must be distinguishable in the report.

Expected protocol reverts are caught and checked. Unexpected results must
survive in failure counters or fail the campaign; an outer handler revert must
not silently erase the evidence. Retain the existing zero-handler-revert
qualification requirement. Coverage checks must also demonstrate that closed
or empty cells did not turn a campaign into mostly skipped actions.

Finish scheduled campaigns by satisfying the obligation, completing FIFO
allocation, and collecting every actor's entitlement (or sanctioned escrow
entitlement), within the defined rounding bounds. Use the scheduled completion
path rather than forcing manual closure to rescue an otherwise broken state.

## Tasks and tracker

| Task | Work | Completion evidence | Status |
| --- | --- | --- | --- |
| E17-01 | Map accepted behavior and current handler assumptions; record sequencing. | This plan names the untested transitions and preserves the existing campaign. | Complete |
| E17-02 | Add lifecycle fixtures, shared handler extension points, independent bookkeeping, and coverage counters. | Shared matrix fixture, independent boundary oracle, per-cell seed/exploration counters, and initial scenario checks. Original campaign qualification below. | Complete |
| E17-03 | Add stateful date/deadline/default, funding, admission, and APR properties. | Two six-cell campaigns, independent boundary scenarios, real-factory authority checks, and active APR/admission probes. Development qualification: 15 tests, including 64 runs/depth 30 for each new campaign. | Complete |
| E17-04 | Extend conservation and revolving expectations through automatic closure; prove batch collection and sanctions behavior. | Event-derived batch ledger, FIFO/bounded processing checks, single/bulk collection, sanctions escrow, tied deadline/expiry cases, and scheduled drain pass development qualification. | Complete |
| E17-05 | Qualify both compiler configurations, varied seeds, and negative controls. | 483 focused tests under each configuration; 523,840 qualification handler calls with zero reverts; nine protocol fault types detected; all ten target artifacts unchanged. | Complete |
| E17-06 | Record results, any regressions/fixes, and the subsequent rehearsal scope. | Signed implementation checkpoints, this report, machine-readable results, and updated catalogue/candidate review distinguish invariant completion from the remaining rehearsal/release work. | Complete |

Implement and commit in task-sized increments, signed as `kethcode`. The user
has authorized incremental research refinements; do not push. Keep the supplied
reference documents and voice guide uncommitted. Follow the
[test maintenance rules](../../../test/README.md).

## Qualification and stopping conditions

- Retain the original 2,000-run/depth-30 campaign under runs 44 and the complete
  runs-1/no-F configuration. Give the new campaigns explicit recorded budgets;
  do not shrink the old campaign to make room for them.
- Run the new lifecycle campaign with multiple recorded seeds and a longer
  sequence stress pass. Select depth from demonstrated boundary/action coverage,
  not a target passing-test count. Save minimized counterexamples.
- In isolated copies, remove representative behavior (inclusive cutoff, reserve
  floor, historical-funding protection, permanent default, or closure/batch
  accounting) and require the corresponding property to fail. Restore source
  afterward. These controls establish that the oracle can detect regressions.
- Run relevant scenario, market, hook, factory, and invariant qualification
  after handler changes. Preserve the distinction between focused qualification
  and the full canonical release suite, including known pending integration
  callback expectations. Do not weaken assertions to absorb those differences.
- Compare fresh production artifacts with E16. A test-only change should not
  change the measured production binaries, ABIs, or layouts. If a protocol bug
  is found, capture a failing regression, explain the fix, and remeasure and
  requalify the affected artifacts before calling that checkpoint complete.

E17 finishes when the new lifecycle transitions have independently checked,
non-vacuous stateful coverage and the old campaign retains its guarantees.
Then update the deployment ceremony and rehearse the actual plan on an Anvil
fork, including ownership routing, interruption/resume, artifact readback, and
bundle gas limits. Build reproducibility and release gates belong alongside
that work, as directed by the user.

## Implementation checkpoints

### E17-02: shared fixture and independent oracle

The original suite retains all nine properties, 17 selectors, and its final
unwind. Its market setup now lives in `MarketMatrixFixture`, with optional
repayment terms added to the existing `MarketFixture.Options`. Defaults remain
zero, so existing fixtures retain their terms.

`LifecycleOracle` sorts date, deadline, batch expiry, and current timestamp,
then calculates expected accrual, default and closure from the last observed
state and cash. It does not import production lifecycle helpers. A test-only
reference contract keeps this calculation outside the inherited action bodies.
`LifecycleHandler` consumes the same recorded calls as the original accounting
checks, keeping seed coverage separate from randomized coverage.

Returning a second `Vm.Log[]` through the original handler caused a solc Yul
stack error. The shared handler instead exposes a post-call bookkeeping hook;
its original return shape and fee checks are retained. This required no
production or compiler changes.

Development evidence: both initial lifecycle scenarios and the original
campaign pass at 16 runs/depth 30. This reduced development run is not the
qualification budget. The full original campaign passed at 2,000 runs/depth 30: 60,000 calls, zero
handler reverts (`e17-fixtures-default`). Later handler changes are requalified
at the same budget before E17 completion.

### E17-03: lifecycle actions and boundary scenarios

`e17-actions-dev8` passes 15 tests under runs 44. The two new campaigns each
completed 64 runs/depth 30 (1,920 calls, zero handler reverts), with strict
`fail_on_revert` enabled. This is development evidence; the final budgets remain
larger and include both compiler configurations.

The first randomized failures reduced to advancing time and queuing a
withdrawal. The oracle had treated `getWithdrawalBatch()` as a raw stored batch.
That getter includes a simulated payment, and floor rounding can permit one
more scaled unit immediately after a write. `test_idleQueueAllocationMatchesOracle`
reproduced the one-unit discrepancy. The oracle now reconstructs committed
batch totals from queue/payment events; the regression and both generated
campaigns pass. No production change was needed.

Additional checks cover exact deadline and penalty cures, one-unit shortfalls,
late-observed donations, observed cure/re-entry, ready periodic APR proposals,
replacement APR policy output, reserved execution-hook rejection, sanctions
collection, FIFO ordering, and borrower/principal/hook-admin transfers through
the real factory stack. The original final unwind now uses the shared recorded
calls so the new oracle follows its accounting too. Scheduled markets close by
funding their repayment obligation; only no-date cells retain manual closure.

Some test-only call and donation bookkeeping uses self-call helpers to keep
large struct and log-array decodes out of inherited action locals. Helpers
reject callers other than their handler and are excluded from fuzz selectors.
No compiler setting or production contract was changed to address stack limits.

### E17-04: collection, conservation, and coverage receipts

`e17-collection-dev` passes 16 tests under runs 44, including 128 runs/depth 30
for each new campaign (3,840 calls each, zero handler reverts). There are now
25 lifecycle selectors. Single and bulk collection check pro-rata amounts and
actual recipient/escrow balances; repeat claims cannot collect twice. A
separate scenario ties batch expiry to the inclusive deadline for all six cells,
including zero-period date/deadline ties and both repayment routes.

A new claim queued after a market has already closed still belongs to its
current batch. The collection driver respects that pending key; it distinguishes
those claims from an existing batch released early by automatic closure.

Coverage receipts now count actual payment/collection events for every action,
not just the new collection selector. They are captured before the final unwind,
with seed counters separate. A fixture latch avoids counting a repeated final
hook invocation as another sequence. `--lifecycle-coverage` archives the raw
receipts and per-cell aggregates; Forge's reported run/call budget remains the
authoritative campaign size.

### Qualification counterexamples

The first full runs exposed three more assumptions in the test model and final
drain. Each has a minimized, deterministic regression; production code is
unchanged.

- Processing old batches can reduce debt by a rounding unit and complete
  funding after repayment accounting runs. Closure then clears the remaining
  revolving principal. The model now checks post-action closure before requiring
  that principal balance, while retaining independent backing and liability checks.
- A sanctioned forced withdrawal can create a batch and complete funding in
  the same call. Closure clears `pendingWithdrawalExpiry`, so the handler must
  retain the key from `WithdrawalQueued`, even though `nukeFromOrbit` returns
  nothing. Every released claim remains in conservation and final collection.
- `totalDebts()` includes a simulated pending payment. Allocating once during
  repayment instead of splitting that allocation across the preview and the
  payment can leave one unit outstanding against the quote. The scheduled drain
  permits exactly one additional unit, requires automatic closure afterward,
  and rejects any larger deficit. A regression checks the shortfall explicitly.

The no-F failures and minimized sequences are retained in `e17-all-noF` and
`e17-counterexamples/noF`; deterministic failing replays and traces are in
`e17-noF-regressions-v2`. The earlier principal trace is in
`e17-counterexamples/principal-model`. These are test-model corrections, not
permission to reduce the campaign budgets or accounting assertions.

## Qualification results

Both runs 44 and the candidate runs-1/no-F configuration pass 483 focused tests.
The original nine invariant properties remain grouped by Forge as one campaign, with the
same 17 selectors and 2,000-run/depth-30 budget. Each new lifecycle campaign
uses 25 selectors across six standard/revolving and open/fixed/periodic cells.
Both new campaigns reject outer handler reverts; expected protocol reverts are
caught and checked inside the actions.

| Configuration | Scope | Seed | Runs per campaign | Depth | Handler calls | Handler reverts |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Runs 44 | All three campaigns; 483 focused tests | `0x5eed` | 2,000 | 30 | 180,000 | 0 |
| Runs 1/no F | All three campaigns; 483 focused tests | `0x5eed` | 2,000 | 30 | 180,000 | 0 |
| Runs 44 | Both lifecycle campaigns | `0x2601` | 256 | 96 | 49,152 | 0 |
| Runs 1/no F | Both lifecycle campaigns | `0x2602` | 256 | 96 | 49,152 | 0 |
| Runs 1/no F | Both lifecycle campaigns | `0xc0ffee` | 128 | 256 | 65,536 | 0 |

The five qualification runs total 523,840 handler calls with zero handler
reverts. All assertions and final drains pass. The normal-profile full rebuild
took about 4.2 minutes to compile and 3 minutes to test on this machine; the
cached longer-sequence runs took roughly 1–1.6 minutes each.

These are the research runner's market, hook, factory, compression, arithmetic,
and invariant checks. They do not claim a full canonical release run or repeat
E16's strict deployment checks. Scenario fuzz tests retain 1,000 cases. The
normal release compiler configuration remains unchanged at runs 44.

Coverage receipts separate fixture setup from exploration and are captured
before the forced final unwind. The longer sequences exercise sanctioned
collection and partial batch allocation in every model/policy cell, including
the less frequently reached fixed and periodic exits. A no-date open cell in
the penalty campaign intentionally never activates repayment or auto-closes.
Its continuous-penalty default and collection coverage remain nonzero.

Aggregating exploration receipts across both lifecycle campaigns and compiler
configurations gives the following counts. Setup and final drains are excluded;
archived counterexample replays can contribute exploration counts.

| Model / policy | Deadline defaults | Penalty defaults | Automatic closures | Collections | To sanctions escrow |
| --- | ---: | ---: | ---: | ---: | ---: |
| Standard / open | 1,890 | 1,643 | 737 | 4,007 | 1,150 |
| Standard / fixed | 1,758 | 1,133 | 905 | 585 | 334 |
| Standard / periodic | 605 | 1,364 | 1,010 | 581 | 323 |
| Revolving / open | 1,963 | 1,246 | 653 | 1,448 | 626 |
| Revolving / fixed | 1,734 | 1,094 | 1,039 | 564 | 326 |
| Revolving / periodic | 588 | 1,395 | 906 | 575 | 317 |

The [machine-readable results](./results/e17.json) retain counts per campaign
and cell, receipt hashes, compiler settings, and artifact comparisons. Receipt
sequence counts can include a framework check or cached counterexample replay;
the table uses Forge's reported run and call counts.

### Fault detection

Nine deliberately broken protocol behaviors fail their corresponding checks:

1. Recording penalty default at the exact cutoff instead of after it.
2. Activating repayment with a reserve below 100%.
3. Letting current cash rewrite historical funding.
4. Clearing a recorded default after cure or closure.
5. Retaining a nonzero APR at closure.
6. Adding an unearned unit to withdrawal liabilities.
7. Accepting a replacement APR policy's lower repayment reserve without the core guard.
8. Accepting the reserved execution-hook bit at construction.
9. Allowing the queue hook to veto repayment-date withdrawal admission.

Three additional controls undo the principal, released-batch, and bounded-drain
model corrections. Their specific regressions fail, and restoring the test
model passes. The batch-liability mutation was also repeated against the final
model and fails the withdrawal-conservation assertion directly. Restoring the
production source passes all 17 selected scenario/configuration tests.

The initial queue-veto control used an invalid access configuration and failed
before reaching the mutation. Its restored baseline failed too, so that receipt
is rejected as evidence. The corrected test enables the required deposit and
transfer access checks, authorizes the lender through a real role provider,
then observes `PolicyVeto()` only before repayment. The corrected negative
control reintroduces that veto after the date and fails as intended.

### Artifact boundary and next work

No production contract, ABI, storage layout, or release compiler setting changes
in E17. All ten independently compiled targets have byte-identical creation
and runtime code to E16 under both configurations. The fresh Forge artifacts
are compared against those independent builds; the target set includes both
markets, both factories, three templates, and three composition examples.

The remaining work is the deployment ceremony update and the required Anvil-fork
rehearsal, including ownership routing, interruption/resume, artifact readback,
and transaction/bundle gas limits. Reproducible release-build gates belong
alongside that work. Full release qualification, pending integration callback
updates, and audit/refreeze work remain separate. A second execution client is
not a requirement.

## Reproduction

Use a new directory for each receipt. The runner restores `foundry.toml` after
each command; do not run two copies against the same checkout concurrently.

```sh
size_yul_steps='dhfoDgvulfnTUtnIf[xa[r]EscLMcCTUtTOntnfDIulLculVcul [j]Tpeulxa[rul]xa[r]cLgvifCTUca[r]LSsTOtfDnca[r]Iulc]jmul[jul] VcTOcul jmul'
python3 scripts/research/check.py /tmp/e17-default --scope all --runs 44 --lifecycle-coverage
python3 scripts/research/check.py /tmp/e17-noF --scope all --runs 1 --yul-steps "$size_yul_steps" --lifecycle-coverage
python3 scripts/research/check.py /tmp/e17-stress --scope invariants --runs 1 --yul-steps "$size_yul_steps" --match-contract '(RepaymentLifecycleInvariantTest|PenaltyLifecycleInvariantTest)' --seed 0xc0ffee --invariant-runs 128 --invariant-depth 256 --lifecycle-coverage
```

Logs, exact tested source snapshots, minimized traces, native compiler products,
and mutation controls are archived under
`/home/kethcode/wildcat/bytecode-research/2026-09-26/` with the `e17-` prefix.
