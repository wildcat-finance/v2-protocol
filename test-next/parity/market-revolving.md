# Revolving market parity

Status: direct market behavior and deterministic differential anchors complete. Stateful matrix
invariants remain in the dedicated invariant migration.

## Family boundary

The legacy `WildcatMarketRevolvingTest` has 22 direct entries, and
`RevolvingDifferentialTest` adds four standard-versus-revolving anchors. The replacement keeps
those 26 behaviors on the existing production market artifact instead of compiling another full
controller, factory, hooks, and market fixture.

| Behavior slice                                       | Legacy entries | Replacement properties |
| ---------------------------------------------------- | -------------: | ---------------------: |
| Construction, immutable fee, and borrower identity   |              2 |                      1 |
| Borrow, repay, surplus, and drawn-principal tracking |              9 |                      3 |
| Borrower-transfer storage preservation               |              1 |                      1 |
| Close and post-close accrual                         |              2 |                      1 |
| Interest, protocol fees, dust, and differential math |             12 |                      5 |
| Added delinquency-fee branch                         |              0 |                      1 |
| **Total**                                            |         **26** |                 **12** |

## Property disposition

The constructor property checks the immutable commitment fee, zero drawn amount, principal
identity, and the full low-level fee-read boundary. Valid `uint16` values, short return data, dirty
upper bits, and bubbled factory reverts all execute against production creation bytecode. The
legacy suite covered only the successful constructor path.

Three principal-accounting properties cover ordinary borrowing, partial and saturating repayment,
interest-first repayment through both repay entrypoints, over-repayment, re-borrowing borrower-
supplied liquidity, and the maximum-value donation regression. Every meaningful drawn-amount
transition checks the production event as well as storage. Borrower transfer separately proves
that the live drawn amount and its storage word survive the identity handoff.

The accrual properties preserve both sides of the revolving formula:

- commitment fee accrues over the complete supply while utilization APR applies only to drawn
  principal, and protocol fees use that combined base rate;
- zero supply and zero elapsed time accrue nothing, while an undrawn market accrues only its
  commitment fee;
- utilization is capped at 100%, and raw-unit dust boundaries are checked at observed six-decimal
  sizes and an 18-decimal stress size;
- a fully drawn zero-fee revolving market exactly matches a standard market for the first segment,
  then accrues strictly less after supply grows above fixed drawn principal;
- after a full repay, drawn principal is zero and subsequent accrual returns to commitment-fee
  only; and
- revolving delinquency executes the same penalty path as the standard market rather than leaving
  the override's duplicated branch untested.

The defensive `drawn > supply` case writes storage slot 10 directly. The production storage layout
places `_drawnAmount` there, and the public getter is asserted immediately after the write. A layout
change therefore fails the test instead of silently exercising the wrong word.

## Coverage and canonical result

The fixed-seed legacy oracle passes all 22 direct entries and all four differential entries. All
12 replacement properties pass under canonical via-IR settings. Focused accurate coverage reports
100% lines, statements, branches, and functions for `WildcatMarketRevolving`.

The two legacy runnable artifacts emit 324,097 bytes of initcode and 203,754 bytes of runtime
bytecode. Extending the shared market artifact and configurable factory mock adds 32,913 bytes of
initcode and 32,902 bytes of runtime bytecode, reductions of 89.84% and 83.85%, respectively.

The complete replacement checkpoint has 629 tests across 39 suites with zero inherited entries,
935,779 bytes of test-side initcode, and 925,540 bytes of runtime bytecode. A forced canonical
via-IR AST compile-to-green took 2m43.33s, including 159.56s in solc, and peaked at 4,046,644 KiB
RSS. Execution remains about two seconds.
