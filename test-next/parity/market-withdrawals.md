# Market withdrawals parity

Status: complete, including the closed-market drain and borrower-principal escrow handoffs from
the lifecycle and borrower-transfer families.

## Family boundary

The legacy `WithdrawalsTest` has 62 entries and `FixedTermWithdrawalsTest` recompiles all 62 through
inheritance. Eighteen replacement properties run OpenTerm and FixedTerm as runtime variants on the
shared artifact-backed market fixture. One production-Sentinel property in the borrower-transfer
suite owns the two principal-migration escrow entries, while completed access-hook suites own the
duplicated credential gates.

| Behavior slice                                                     | Legacy entries | Replacement ownership          |
| ------------------------------------------------------------------ | -------------: | ------------------------------ |
| Known-lender and credential withdrawal access                      |              8 | access-hook families           |
| Normalized, scaled, and full queueing and batch accounting         |             42 | 5 market properties            |
| Single withdrawal execution, closure, and duplicate claims         |             12 | 3 market properties            |
| Batched execution, atomic rollback, and sanctions routing          |              8 | 2 market properties            |
| Unpaid-batch one-wei, large-liquidity, dust, and progress paths    |             10 | 3 market properties            |
| Repay processing, liquidity, limits, multiple batches, and closure |             20 | 2 market properties            |
| Batch, account-status, available-amount, and pending views         |             24 | 4 market properties            |
| Randomized closed-market drain from the lifecycle family           |              2 | 1 market property              |
| Principal withdrawal escrow namespace and post-migration release   |              2 | 1 production-Sentinel property |
| **Total**                                                          |        **128** | **128 mapped**                 |

Queueing preserves each public denomination rather than testing aliases. Normalized queueing floors
through the live scale factor, scaled queueing retains the caller's exact scaled amount, and full
queueing consumes the stored balance. They share pending batches, add account status independently,
apply available liquidity immediately, preserve rollback on overdraw and width overflow, and drain
across fresh zero-duration batches after closure.

Execution covers pending rejection, permissionless payout, duplicate claims, pre-expiry payout
after closure, multi-batch ordering, array validation, and whole-call rollback when a later entry
fails. Sanctioned claims use the configured escrow while ordinary claims in the same batch still
pay the lender. The production-Sentinel integration proves that borrower accounts use their
principal's escrow namespace and that an old escrow stays releasable after the market migrates to a
new principal.

Unpaid batches cover no liquidity, the one-wei maximum-settleable boundary above `RAY`, a large
donation that previously risked intermediate overflow, liquidity too small to burn one scaled unit,
partial progression, completion, FIFO processing, zero/one/many batch limits, direct repayment,
and closed-market rollback. Views are checked both before state persistence and after expiry,
partial claims, later repayment, and completion.

## Coverage and canonical result

The fixed-seed legacy oracle passes all 124 standard and inherited withdrawal entries. The two
closed-market drain and two principal-escrow legacy entries also pass in their original suites. All
18 shared market properties and the production-Sentinel escrow property pass in the replacement.
Focused accurate coverage reports 100% lines, statements, branches, and functions for
`WildcatMarketWithdrawals` (132/132 lines, 158/158 statements, 21/21 branches, and 13/13 functions).

The comparison charges growth of the already-shared market and borrower-transfer artifacts. The
two legacy withdrawal artifacts total 463,643 bytes of initcode and 223,049 bytes of runtime
bytecode. Replacement growth is 43,271 bytes for both measures, including the escrow handoff. That
reduces initcode by 90.67% and runtime bytecode by 80.60%; the comparison is conservative because it
does not add the four handed-off legacy entries to the legacy side.

The full replacement checkpoint is 579 tests across 36 suites with zero inherited entries,
761,906 bytes of test-side initcode, and 752,695 bytes of runtime bytecode. A forced canonical
via-IR compile-to-green takes 2m08.40s, including 125.23s in solc, with a 3,233,724 KiB RSS peak;
execution takes 1.88s.
