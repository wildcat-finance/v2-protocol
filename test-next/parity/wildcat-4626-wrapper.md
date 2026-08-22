# Wildcat 4626 wrapper parity

Status: core wrapper complete; production market and sanctions-escrow composition remains in the
wrapper integration checkpoint.

## Family boundary

The four non-factory legacy vault files expose 160 entries across five concrete test artifacts.
Nineteen replacement properties exercise the production `Wildcat4626Wrapper` from one concrete
suite. A configurable floor-rounding market mock isolates the wrapper's arithmetic and defensive
reads without reproducing the protocol deployment graph inside every property.

| Legacy suite                          | Entries | Replacement ownership                    |
| ------------------------------------- | ------: | ---------------------------------------- |
| `Wildcat4626WrapperTest`              |      47 | shared wrapper properties                |
| `Wildcat4626WrapperGuardsTest`        |      58 | shared wrapper properties                |
| `Wildcat4626WrapperRoundingTest`      |      15 | conversion and rate property             |
| `Wildcat4626WrapperExecutionFuzzTest` |      13 | execution, round-trip, and sweep fuzzing |
| `Wildcat4626WrapperStandardTest`      |      27 | ERC-4626 surface and round trips         |
| **Total**                             | **160** | **160 mapped**                           |

The conversion property checks floor and ceiling behavior for every preview and conversion over
scale factors from 1x through 11x. Execution fuzzing separately proves exact scaled backing for
deposit, mint, withdraw, and redeem; all four entrypoint pairings restore the holder's scaled
ownership. Fixed regressions retain the one-share and tiny-offset cases that originally exposed
`maxWithdraw` rounding failures.

Capacity tests cover full vaults, sub-share dust, fractional-scale maximum deposits and mints, and
every zero-input error. Exact, infinite, and insufficient share allowances are checked for both
withdrawal entrypoints. Multi-lender accrual, direct market-token donations, and the inflation
scenario prove that shares remain scaled claims rather than pro-rata claims on stranded assets.

The guard properties validate short, dirty, reverting, and overlong return data for market words,
market addresses, sanctions, recipient policy, and escrow discovery. They cover caller, receiver,
owner, sender, recipient, wrapper-wide sanctions, insolvency, spoofed escrows, atomic market-call
failure, idempotent quarantine, current-borrower sweep authority, unrelated-token sweep, scaled
surplus sweep, and every `SharesMismatch` rollback. Deposit, withdrawal, sweep, and quarantine
events are asserted on their respective execution paths.

## Coverage and canonical result

The fixed-seed legacy oracle passes all 176 vault entries, including the separately completed
16-entry factory suite. All 19 core replacement properties pass with 1,000 fuzz runs. Focused
accurate coverage reports 98.42% lines, 98.52% statements, 94.29% branches, and 95.92% functions for
`Wildcat4626Wrapper` (312/317 lines, 400/406 statements, 66/70 branches, and 47/49 functions).

The five uncovered lines are deliberate boundaries:

- `_useVirtualShares` and `_underlyingDecimals` are shadowed by the wrapper's public `decimals` and
  conversion overrides, leaving no production call path.
- the mint round-trip mismatch, zero-asset redeem, and zero-asset market-sweep guards are
  unreachable while the market preserves its required `scaleFactor >= RAY`; successful fuzzing
  directly proves each corresponding ceil/floor identity.
- the canonical sanctions-escrow release branch belongs to the production Sentinel integration
  checkpoint and is not simulated with a privileged mock.

The legacy non-factory suites and their support artifacts total 304,837 bytes of initcode and
303,649 bytes of runtime bytecode. The replacement suite and its three dedicated support artifacts
total 81,822 and 81,323 bytes, reducing initcode by 73.16% and runtime bytecode by 73.22%.

The full replacement checkpoint is 607 tests across 38 suites with zero inherited entries,
862,458 bytes of test-side initcode, and 852,256 bytes of runtime bytecode. A forced canonical
via-IR compile-to-green takes 2m18.95s, including 135.52s in solc, with a 3,476,168 KiB RSS peak;
execution takes 2.08s.
