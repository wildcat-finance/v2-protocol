# E13: restore invariant parity

Source parent: `b2b91a0` (E12).

FastLZ remains the assumed deployment candidate, subject to further verification.
This experiment restores the existing invariant coverage before any further size
work. A fitting bytecode measurement does not replace the invariant suite.

## Diagnosis

The handler and invariant contract are unchanged between the research baseline
`7b47eec` and E12. A detached baseline checkout passes all nine invariant properties
at the existing 2,000 runs and depth 30: 60,000 handler calls, zero reverts, all 17
actions exercised, and the `afterInvariant` unwind retained.

Compiling the handler independently gives the following controls:

| Sources | Runs 44 | Runs 1 | Runs 1/no F |
| --- | --- | --- | --- |
| Research baseline | Pass | Pass | Pass |
| E12 | Stack failure | Stack failure | Stack failure |
| E12 without the MathUtils/SafeCastLib annotations | Pass | Not run | Pass |
| E12 with the checked MarketState additions restored | Pass | Not run | Stack failure |

The E12 annotations are valid, but their effect on compiler optimization exposes
stack pressure in the handler. The earlier description of this as only a no-F
limitation was incomplete: runs 44 fails too. Restoring the checked additions
only fixes the default optimizer; it does not fix the complete candidate.

Optimized IR locates the no-F failure in `deposit` and the default failure in the
nested `Vm.Log[]` decoding in `_callAs`. A real Forge run reproduces the no-F
failure before the fix.

## Refinement

- Move each deposit's existing body into `_depositCell`, following `_repayCell`.
  The caller still visits every market. Each previous `continue` becomes a return
  from that cell's helper; the input bounds, external calls and checks are intact.
- Keep `_callAs` bookkeeping and its call result in a memory `CallRecord` while
  decoding logs. The snapshot, log recording, caller prank, target call, fee
  accounting, panic counter and returned result retain their order and meaning.
- Add an `invariants` scope to the research runner and include that suite in `all`.
  Invariant sources are now required by the broader focused qualification.

No production source, invariant assertion, target selector, input bound, matrix
cell, run count or depth changes. `MarketMatrixInvariant.t.sol` is untouched.

The deposit extraction alone fixes the no-F handler build. Moving log retrieval
into a helper is inlined away and does not fix runs 44. A result-only memory
bundle fails both settings; a bookkeeping-only bundle still fails runs 44.
The complete `CallRecord` plus deposit extraction compiles under both settings.
All intermediate compiler inputs and failures remain in the external receipts.

## Qualification

The candidate's broader run passes all 436 reported tests at runs 1/no F.
Foundry 1.8.3 groups the nine invariant properties into one reported test, in
addition to the existing 435 focused tests. All nine properties pass at the
original 2,000 runs and depth 30, with 60,000 calls and zero reverts. Each of the
17 action counts matches the baseline campaign at seed `0x5eed`.

All nine invariants also pass at canonical runs 44 with the same campaign
parameters and action counts. The broader canonical run has **435 passes and
one failure**: `test_onSetApr_UpdatesActiveReductionAndPreservesOrExtendsExpiry`
expects expiry 1,726,099,200 while the hook emits 1,725,494,400. That independent
APR-test failure remains recorded for follow-up; this is not a claim that the
whole canonical suite is green.

Both strict deployment tests pass again, covering 12 factory/market/hook
combinations under the real 24,576-byte limit. Their ten fresh artifacts match
the independent native creation/runtime bytes, complete ABIs and normalized
layouts. The independent native binaries are unchanged from E12. The markets
remain at 23,791 / 24,344 runtime bytes under the candidate settings.

Both broader builds also match the seven production artifacts exactly. Their
focused graph omits `PeriodicBorrowHooks`, leaving an old file at that artifact
path; the runs-44 comparison exposed the stale no-F artifact. That unused file
is not counted as a fresh measurement. The strict deployment graph does compile
and qualify all ten targets. The runner's artifact freshness needs follow-up.

The handler's public ABI and normalized storage layout match the baseline.
Formatting, lint and whitespace checks pass. No production source or normal
compiler setting changes. [Concise results](./results/e13.json).

Decision: retain the handler refactor and include invariants in broader research
qualification. This restores the existing six-cell invariant suite. Those cells
have no scheduled repayment dates; this does not add a stateful repayment-date
lifecycle model or complete FastLZ/release verification.

Follow-up: [E14](./E14-qualification-fixtures.md) resolves the APR test's cached
time expectation and the runner's artifact freshness. Both broader campaigns
then pass all 436 reported tests, with fresh matches for all ten targets under
each compiler configuration. The original E13 receipts above remain unchanged.

Evidence is under `/home/kethcode/wildcat/bytecode-research/2026-09-26/`:

- `e13-baseline-invariants/` and `e13-baseline-worktree/`;
- `e13-handler-{baseline,candidate}-{44,1,noF}/`;
- `e13-isolate-{before-annotations,checked-liabilities,ir}-{44,noF}/`;
- `e13-candidate-invariants-before/`;
- `e13-handler-deposit-*/` for the intermediate and final refinements;
- `e13-all-noF/`, `e13-all-default/`, `e13-native-noF/` and `e13-deployment-noF/`.
