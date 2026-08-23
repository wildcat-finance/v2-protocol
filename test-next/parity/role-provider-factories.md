# Role-provider factory parity

Status: all six factory suites replaced; provider credential behavior remains separate.

## Property disposition

The six legacy suites contain 55 tests. Most of those are copies of the same factory contract:
typed and generic creation, deterministic CREATE2 addresses, caller-namespaced salts, deployment
events, duplicate guards, malformed input, and construction through a hooks instance.

The replacement keeps one concrete suite and runs shared behavior across all six factories at
runtime. The production factories still perform every provider deployment through their real
CREATE2 paths.

| Legacy behavior                                        | Legacy entries | Replacement entries |
| ------------------------------------------------------ | -------------: | ------------------: |
| Typed creation and exact computed address              |              6 |                   6 |
| Generic `IRoleProviderFactory` creation                |              6 |                   1 |
| Exact deployment events                                |              6 |                   1 |
| Caller-namespaced salts                                |              6 |                   1 |
| Duplicate deployment guards                            |              6 |                   1 |
| Malformed generic input                                |              6 |                   1 |
| Invalid token, vault, or administrator                 |              6 |                   1 |
| Provider creation and attachment in a hook constructor |              5 |                   1 |
| ERC20 / ERC4626 zero minimum                           |              2 |                   1 |
| ERC721 / ERC1155 interface rejection                   |              2 |                   1 |
| ERC721 / ERC1155 interface-check bypass remains usable |              2 |                   1 |
| Merkle zero root and factory authority isolation       |              2 |                   2 |
| **Total**                                              |         **55** |              **18** |

Each single replacement entry in the shared rows loops over every applicable factory; it does not
sample one representative implementation. The six typed creation properties retain the five
legacy fuzz surfaces and also fuzz the AccessList salt. The hook-constructor matrix adds
AccessList as a sixth runtime case; the equivalent legacy behavior previously lived in the
separate AccessList integration suite.

Real production code remains on the path under test:

- factories compute and deploy the providers with CREATE2
- constructor reverts and immutable provider configuration are checked directly
- events are checked against the specific factory emitter
- alternate callers use a separate deployed contract
- `OpenTermHooks` creates and classifies pull/push providers through its real constructor

Only fixture infrastructure—the factories before each test, balance/interface token mocks, the
alternate caller, and the hooks instance itself—is loaded from canonical artifacts so its
creation code is not copied into the test contract.

## Canonical-profile result

| Measure                                                 |   Legacy factory family | Replacement family |              Delta |
| ------------------------------------------------------- | ----------------------: | -----------------: | -----------------: |
| Runnable suites                                         |                       6 |                  1 |                 -5 |
| Test entries                                            |                      55 |                 18 |                -37 |
| Parameterized entries                                   |                       5 |                  6 |                 +1 |
| Inherited entries                                       |                       0 |                  0 |                  0 |
| Initcode, including dedicated support artifacts         |           190,018 bytes |       18,598 bytes | -171,420 (-90.21%) |
| Runtime bytecode, including dedicated support artifacts |           189,580 bytes |       18,392 bytes | -171,188 (-90.30%) |
| Factory line / statement / branch / function coverage   | legacy coverage blocked |               100% |                n/a |

All 18 properties pass at the fixed timestamp and seed with 1,000 runs per parameterized entry.
The coverage claim applies to the six factory contracts. Provider credential behavior,
AccessList membership/administration, Merkle proof handling, and hook behavior are intentionally
left to their own migration slices.

The complete replacement suite now has 254 tests across 17 suites and emits 219,157 bytes of
test-side initcode. A forced canonical AST compile-to-green took 59.64 seconds, including 58.23
seconds in solc, and peaked at 1,860,904 KiB RSS. That is 1.87 seconds and 61,512 KiB above the
236-test first checkpoint.
