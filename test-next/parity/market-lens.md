# Market Lens parity

Status: complete.

## Family boundary

The legacy Lens family has 74 entries across `MarketDataTest` and
`MarketLensMultiFactoryTest`. The replacement follows the deployed contract boundary instead of
rebuilding the old shared protocol fixture:

| Production boundary                                           |            Legacy entries | Replacement properties |
| ------------------------------------------------------------- | ------------------------: | ---------------------: |
| Facade routing, probes, flags, and exact revert bubbling      | shared across both suites |                      9 |
| Core and live market, account, identity, and withdrawal reads |                        45 |                      5 |
| Factory discovery, aggregation, deduplication, and pagination |                        29 |                      6 |
| **Total**                                                     |                    **74** |                 **20** |

The old suite remains the fixed-seed reference oracle. It does not need to be retrofitted into the
new fixture model: the replacement properties preserve its meaningful behavior while removing the
old inheritance and deployment graph.

## Property disposition

The facade suite calls every public facade selector as raw calldata. That proves exact helper
routing without constructing a full market graph for each alias. It also checks constructor
immutables, exact delegatecall revert bubbling, every `HooksConfigData` flag, optional-uint
presence versus fallback, and the complete version and hook-kind probe boundary, including empty,
long, malformed, and reverting return data. A V1-shaped market is routed through the production
core helper and proves that the facade bubbles the canonical `NotV2Market` selector.

The core/live suite uses production standard, revolving, and periodic markets. Five composed
properties cover token metadata; scalar and list market reads; V2 optional fields; live/full-data
parity; pending and accepted borrower identity; hook administration; lender balances, allowance,
and deposit blocking; account-query aliases; and every withdrawal-batch endpoint across Pending,
Expired, Unpaid, Complete, and unknown batches. Existing borrower-transfer, managed-provider,
market, and withdrawal suites own the underlying state transitions; the Lens suite proves that
the read model reports them correctly.

The aggregator suite uses focused configurable factories so discovery behavior is independent of
market setup. It covers direct and factory-parameterized aliases, invalid controller filtering,
default-factory insertion, empty and single-factory cases, isolated factory reverts, stable
first-seen ordering, template and instance deduplication, factory-scoped metadata, borrower
origination fees, and standard/revolving legacy and V2 market reads through direct, paginated, and
aggregated endpoints.

## Coverage and canonical result

The fixed-seed legacy oracle passes all 74 entries. All 20 replacement properties pass under the
canonical via-IR profile. Focused accurate coverage reports 100% line, statement, branch, and
function coverage for all four shipped Lens contracts:

- `MarketLens`: 115/115 lines, 63/63 statements, 1/1 branch, and 52/52 functions
- `MarketLensCore`: 61/61 lines, 63/63 statements, and 19/19 functions
- `MarketLensLive`: 11/11 lines, 12/12 statements, and 3/3 functions
- `MarketLensAggregator`: 228/228 lines, 279/279 statements, 26/26 branches, and 42/42 functions

The coverage lane uses one `FOUNDRY_TEST` root at a time. Broad Lens discovery imports a factory
graph that Forge's non-IR coverage compiler cannot lower; canonical via-IR compilation and test
execution are unaffected.

The legacy Lens artifacts emit 684,250 bytes of initcode and 439,184 bytes of runtime bytecode.
The replacement checkpoint grows by 79,205 and 77,968 bytes respectively, including all three
runnable Lens suites, Lens-specific mocks, and the shared factory-mock additions. That reduces
family initcode by 88.42% and runtime bytecode by 82.25%.

The complete replacement checkpoint has 648 tests across 42 suites with zero inherited entries,
1,014,984 bytes of test-side initcode, and 1,003,508 bytes of runtime bytecode. A forced canonical
via-IR AST build took 3m22.89s, including 202.12s in solc, and peaked at 5,601,176 KiB RSS. Warm
execution remains about two seconds.
