# E18: closure isolation and review corrections

Source parent: `f56c30e` (E17). Status: in progress.

The September 26 external review found that automatic closure sends excess
underlying assets to the borrower inside ordinary state updates. A token that
rejects that recipient can therefore block funded lender withdrawals. E17's
tokens did not exercise recipient-specific failures.

The user selected these changes on September 27:

- Automatic closure retains surplus. The operational borrower can recover only
  assets above all lender and protocol-fee liabilities after closure, through
  the existing `rescueTokens` surface if practical.
- Factory protocol-fee pushes skip closed markets, including effective closure
  visible before a state write. Unexpected failures still revert the batch.
- Compiler selection remains a final release decision. Keep the normal runs-44
  configuration and measure the existing runs-1/no-F candidate separately.

Keep FastLZ and one initcode storage contract per artifact. No new closure
mechanism, tranche policy, repayment terms, or default rules are part of E18.

## Plan and tracker

| Task | Required evidence | Status |
| --- | --- | --- |
| E18-01 | Reproduce recipient rejection, isolate automatic closure from surplus collection, and test borrower-only recovery against every liability category on both models. | Complete; final campaign budgets remain in E18-04. |
| E18-02 | Skip closed markets in both fee-update loops; retain pagination, whole-batch rollback for unexpected failures, and existing setter errors. | Complete; 209 hook/factory tests pass. |
| E18-03 | Compare the transition allocator with Solidity-created structs; pin field layout, zeroing, and non-aliasing. Retain the existing accrual-event encoding test. | Pending |
| E18-04 | Requalify focused suites and E17 campaigns under both compiler configurations; measure runtime/storage sizes and record ABI/storage compatibility. | Pending |

Each completed task gets a signed kethcode checkpoint. Do not push. Keep the
external review handoff, source PDFs, old sketch, and voice guide uncommitted.
Use the established research receipt workflow; large output stays outside the
repository, under `/home/kethcode/wildcat/bytecode-research/2026-09-27/`.

## Fix boundary and validation

Remove the borrower transfer from `_commitAutomaticClosure` and preserve the
actual retained cash in `_writeState`'s checkpoint. Keep revolving principal
clearing, closure events, batch handling, and historical close timestamps.
Recovery must reserve `totalDebts()`: outstanding shares, paid unclaimed
withdrawals, and accrued protocol fees. Unpaid batches remain part of outstanding
shares. A failed recovery transaction cannot affect other participants' calls.

Test rejecting and false-returning transfers, historical and current-action
closure, positive and zero rates, exact and excess funding, donation recovery,
unauthorized/open-market recovery, and bounded settlement of old batches.
Update old surplus-push assertions explicitly as a selected behavior change.

The reviewer correctly identified the allocator-test gap. The accrual event
already has a Solidity-encoding comparison in `MarketEvents.t.sol`. The old
empty `expiry = 0` withdrawal quote also reverted (`MulDivFailed`); its new
error is not a zero-return-to-revert regression.

Gas measurements, compiler adoption, ceremony updates, the Anvil-fork rehearsal,
and final release qualification remain separately identified follow-up work.

## E18-01: closure and recovery

`e18-before` runs the new tests against the unchanged production source: exact
funding passes, while historical closure with surplus and closure during an
excess repayment both fail with `TransferFailed`. The fix removes the borrower
payout from both automatic closure callers and keeps the retained cash in the
checkpoint. `rescueTokens(asset)` updates state, requires closure, transfers
only `assets - totalDebts`, then writes state with the actual retained assets.
The public ABI and storage layout do not change.

`e18-f1-market-v2` passes 161 focused market/library/repayment tests. The final
new recovery suite additionally covers a rejected recovery while effective
closure is still uncommitted, authority transfer, and donations after manual
closure without repayment terms. Both models exercise ten lender/maintenance
entry paths, false-return and reverting recipients, every liability category,
bounded FIFO processing, and complete claim/fee collection after recovery.
Independent source review found no surviving F1 bypass or regression.

The lifecycle campaigns now have 26 selectors, adding `recoverSurplus`, and
also allow donations after closure. Successful nonzero recoveries have their
own exploration counter. Their final drain explicitly recovers borrower
surplus before applying the unchanged cash/dust bound. The initial development
run (`e18-f1-invariants-dev`) failed that old final-drain assumption, as expected
when closure stops pushing surplus. No accounting assertion was weakened.
`e18-f1-development` passes all 32 selected tests, including the ten recovery
tests and all three campaigns at a development budget of 64 runs/depth 30 with
zero handler reverts. Final qualification retains the original 2,000-run budget.

| Compiler | Market | Runtime bytes | Change from E17 | Headroom |
| --- | --- | ---: | ---: | ---: |
| Runs 44 | Standard | 24,474 | -14 | 102 |
| Runs 44 | Revolving | 25,050 | -11 | -474 |
| Runs 1/no F | Standard | 23,778 | -13 | 798 |
| Runs 1/no F | Revolving | 24,334 | -10 | 242 |

Native receipts: `e18-f1-native-default` and `e18-f1-native-noF`, compared with
the E17 receipts. All ten measured ABIs and storage layouts are unchanged;
factories, hooks, and composition targets are byte-identical at this checkpoint.

## E18-02: fee pushes

Both factory loops read the live `isClosed()` result before calling the setter.
The bounded read requires a full, canonical bool; short/dirty returns and
reverting queries use the existing `SetProtocolFeeBipsFailed` error. Closed
markets are skipped without committing their pending closure. Other failures
still revert every prior update in that page. The selector `0xc2b6b58c` was
checked against `cast sig 'isClosed()'`.

`e18-f5-before` fails the new closed-market and query-failure tests against the
old loops, with all 27 previous factory tests passing. `e18-f5-hooks` passes all
209 hook/factory tests after the change. New cases cover both factories, mixed
open/stored-closed/effectively-closed markets, closed-only pages, later pages,
failed and malformed queries, failed setters, whole-page rollback, and valid
bool returns with trailing data. Interface comments now state the skip rule;
function signatures and errors remain unchanged.
