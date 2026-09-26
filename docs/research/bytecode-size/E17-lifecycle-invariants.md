# E17: repayment and default invariants

Source parent: `95e6f0c` (E16). Status: lifecycle campaigns and boundary scenarios implemented. Final coverage
refinements and qualification are in progress.

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
| E17-04 | Extend conservation and revolving expectations through automatic closure; prove batch collection and sanctions behavior. | Generated traces and final unwind cover partially funded FIFO batches, closure, surplus, and every lender's exit. | Pending |
| E17-05 | Qualify both compiler configurations, varied seeds, and negative controls. | Existing/new campaigns and the relevant broader tests pass; transition counts, failures, traces, and artifact comparisons are archived. | Pending |
| E17-06 | Record results, any regressions/fixes, and the subsequent rehearsal scope. | Signed checkpoints and a reviewable report distinguish completed invariant coverage from outstanding ceremony/release work. | Pending |

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
