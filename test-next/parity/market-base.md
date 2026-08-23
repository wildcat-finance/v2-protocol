# Market base parity

Status: all direct standard/fixed-term `WildcatMarketBaseTest` properties replaced.

## Family boundary

The legacy base suite declares 17 entries, then `FixedTermWildcatMarketBaseTest` recompiles all 17
through inheritance solely to change the mature hook implementation. The replacement runs both
production hook kinds from seven properties on the existing `WildcatMarketTest` artifact.

The fixture deploys production `WildcatMarket`, OpenTerm/FixedTerm hooks, ArchController, and
borrower identity registry artifacts. A small parameter-serving factory, sanctions sentinel, and
underlying asset isolate the market behavior. The production factory and CREATE2 deployment path
remain covered by `hooks-factory-templates.md`; this slice directly verifies the market constructor
against the exact 22-word parameter layout that factory path supplies.

| Shared behavior slice                                                  | Legacy entries | Replacement entries |
| ---------------------------------------------------------------------- | -------------: | ------------------: |
| Distinct operational borrower/principal and raw parameter layout       |              2 |                   1 |
| Invalid registry, zero borrower, and unregistered/zero principal       |              6 |                   1 |
| Constructor configuration, initial state, assets, supply, and balances |             16 |                   1 |
| Accrued current-state reads, borrowable assets, and ordinary fee reads |              4 |                   1 |
| Zero-supply interest and delinquency-grace scale-factor behavior       |              2 |                   1 |
| Pending-withdrawal fee cap before and after excess-liquidity donation  |              2 |                   1 |
| State-changing reentrancy rejection from a deposit hook                |              2 |                   1 |
| **Total**                                                              |         **34** |               **7** |

The constructor matrix asserts every market dependency and economic immutable, the complete
initial `MarketState`, and all reserved borrower/wrapper fields. The identity cases preserve both
invalid-registry shapes and the zero-principal case even after address zero is registered on the
controller. The distinct-identity case also reads the factory's raw ABI response and checks the
hooks, principal, and registry words at their exact offsets.

The current-state property strengthens the legacy getter-only entries with exact one-year values:
stored state remains unchanged, current scale factor and protocol fees accrue, supply/debt,
coverage, borrowable assets, and withdrawable fees agree, and raw assets do not mutate. The
scale-factor property separately preserves accrual at zero supply and the delinquency grace
boundary. Fee coverage keeps the ordinary, pending-withdrawal, excess-liquidity, and protected
reentrant-read cases.

Both runtime variants begin at the same explicit fixture timestamp. Time is read through
`vm.getBlockTimestamp()` before using `vm.warp`: via-IR may correctly treat the EVM
`block.timestamp` opcode as transaction-invariant, while Foundry cheatcodes deliberately violate
that assumption inside a test transaction.

## Coverage and canonical result

The fixed-seed legacy oracle passes all 34 entries, and the replacement passes all 14 cumulative
market properties. Focused accurate coverage reports 66.57% lines, 62.32% statements, 22.73%
branches, and 78.00% functions for `WildcatMarketBase`; the remainder belongs to the still-pending
configuration, lifecycle, borrower-transfer, and withdrawal slices. `WildcatMarketToken` remains
at 100% across all four measures.

The incremental comparison below measures the seven base properties added to the committed
token-only checkpoint, including the one dedicated reentrancy-hook support artifact.

| Market-base artifact delta                              | Initcode bytes | Runtime bytes | Test entries |
| ------------------------------------------------------- | -------------: | ------------: | -----------: |
| Legacy `WildcatMarketBaseTest`                          |        223,542 |       103,245 |           17 |
| Legacy `FixedTermWildcatMarketBaseTest`                 |        224,844 |       104,547 |           17 |
| **Legacy total**                                        |    **448,386** |   **207,792** |       **34** |
| Replacement market growth plus reentrancy-hook artifact |         20,697 |        20,651 |            7 |
| **Difference**                                          |   **-427,689** |  **-187,141** |      **-27** |
| **Reduction**                                           |     **95.38%** |    **90.06%** |   **79.41%** |

The cumulative base-plus-token comparison is 800,034/318,848 legacy bytes and 74 entries versus
36,637/36,565 replacement bytes and 14 entries: a 95.42% initcode reduction, 88.53% runtime
reduction, and no inherited entries.

The full replacement checkpoint is 520 tests across 35 suites, with 624,366 bytes of test-side
initcode and 615,229 bytes of runtime bytecode. A forced canonical compile-to-green took 1m43.85s,
including 101.24s in solc, peaked at 2,877,928 KiB RSS, and executed all tests in 1.43s.
