# Market-constraint hooks parity

Status: shared parameter constraints and temporary-reserve-ratio behavior replaced.

## Family boundary

The legacy suite does not have a dedicated `MarketConstraintHooks` contract. Its ten direct
hook-state properties are embedded in `test/market/WildcatMarketConfig.t.sol`, where every case
inherits and deploys the full protocol fixture. The remaining 34 properties in that file cover
market authority, liquidity checks, sanctions, capacity, closure, protocol fees, and the market's
public pending-APR entrypoint; they remain assigned to the market slice.

The replacement calls the production `MarketConstraintHooks` implementation through the real
`OpenTermHooks` delegate. The hook is loaded from its canonical artifact, and the test contract
supplies only the factory call used for deployment-parameter validation. No legacy fixture,
Wildcat market, ArchController, sentinel, or hooks factory is imported.

| Shared behavior slice                                            | Legacy entries | Replacement entries |
| ---------------------------------------------------------------- | -------------: | ------------------: |
| Advertised/deployment constraints and APR range                  |              1 |                   1 |
| Reduction formula, quarter boundary, rounding, and maximum ratio |              4 |                   2 |
| Further reduction and partial recovery during an active period   |              2 |                   1 |
| Cancellation and expiry                                          |              2 |                   1 |
| Increase/equality without temporary state                        |              1 |                   1 |
| **Mapped-property total**                                        |         **10** |               **6** |
| Further reduction after expiry                                   |              0 |                   1 |
| **Replacement total**                                            |         **10** |               **7** |

The formula property runs 1,000 fixed-seed cases across the original APR, requested APR, original
reserve ratio, and ignored requested reserve ratio. It verifies the exact 25% boundary before
integer rounding, proportional doubling, the 100% cap, the existing-reserve floor, activation
events, stored original values, and two-week expiry.

Explicit transition properties preserve both active-period branches: a further reduction resets
the two-week timer, while a partial recovery below the original APR preserves the existing
expiry. Cancellation by restoring the original APR and expiry at the exact boundary both restore
the original reserve ratio and clear storage. The added post-expiry property proves that a further
reduction extends the response period instead of incorrectly expiring it.

The deployment property strengthens the legacy slice by checking the advertised minimum and
maximum for all five parameters, accepting both boundary tuples, and asserting the exact error for
APR, delinquency fee, withdrawal duration, reserve ratio, and delinquency grace-period overflow.

## Coverage and canonical result

Focused accurate coverage reports 100% lines, statements, branches, and functions for
`MarketConstraintHooks`. All seven properties pass at the fixed timestamp and seed; the formula
and increase/equality properties each run 1,000 cases.

The replacement test artifact is 13,389 bytes of initcode and 13,363 bytes of runtime bytecode.
The legacy `WildcatMarketConfigTest` artifact is 222,255/101,958 bytes, but it also owns 34
unmigrated market properties and the full protocol fixture, so no standalone bytecode reduction is
claimed for this shared slice.

The full replacement checkpoint is 506 tests across 34 suites with zero inherited entries,
587,729 bytes of test-side initcode, and 578,664 bytes of runtime bytecode. A forced canonical
compile-to-green took 98.97 seconds, including 96.77 seconds in solc, and peaked at 2,784,556 KiB
RSS.
