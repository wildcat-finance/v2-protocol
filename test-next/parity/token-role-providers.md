# Token role-provider parity

Status: provider truth and constructor behavior complete; hook/market integration remains.

## Family boundary

The ERC20, ERC721, ERC1155, ERC4626-assets, ERC5192, and ERC5484 legacy files contain 87 tests
across 12 suites. They mix three different concerns:

| Concern                                    | Legacy entries | Status                                          |
| ------------------------------------------ | -------------: | ----------------------------------------------- |
| Provider credentials and constructor gates |             42 | Replaced here                                   |
| Shared hook/market access behavior         |             42 | Next provider checkpoint                        |
| Wildcat debt-token and wrapper interest    |              3 | Retained for the market/vault integration slice |

Keeping those concerns separate lets the provider truth tests run without inheriting the full
controller, hooks factory, market, sentinel, wrapper, and role-provider fixture.

## Property disposition

The 21 replacement properties cover the 42 provider-level legacy entries:

- Eight pull-provider properties cover current balances, exact thresholds, configured ERC1155
  IDs, ERC4626 asset conversion, balance/share movement, `getCredential`, and
  `validateCredential`.
- Six push-provider properties cover ERC5192 ownership/lock rules and ERC5484 burn-authorization
  masks, ownership changes, malformed data, undefined authorization values, and failed token
  reads.
- Seven constructor properties cover all six no-code guards, ERC20/ERC4626 zero minimums,
  missing interfaces, invalid ERC165 implementations, reverting ERC165 reads, interface-check
  bypasses, and invalid ERC5484 masks.

The ERC721 property now fuzzes the balance observed by the provider rather than a token ID that
the provider never receives. ERC transfer semantics belong to the token implementation; the
protected Wildcat property is that credentials follow the current collection balance. The
ERC1155 and push-provider properties retain token-ID fuzzing because those IDs are provider
inputs.

A single artifact-backed token/vault mock supplies only the read surfaces these providers use.
Provider constructors still execute from canonical production creation artifacts. The shared
test kernel now bubbles constructor revert data so exact production selectors remain observable
without embedding six provider creation binaries in the test contract.

## Coverage and canonical result

| Production contracts                      |  Lines | Statements | Branches | Functions |
| ----------------------------------------- | -----: | ---------: | -------: | --------: |
| ERC20 / ERC721 / ERC1155 / ERC4626-assets |   100% |       100% |     100% |      100% |
| ERC5192                                   | 94.74% |     93.94% |     100% |      100% |
| ERC5484                                   | 95.35% |     95.12% |     100% |      100% |
| **Combined six-provider slice**           | 97.45% |     97.40% |     100% |      100% |

Forge does not mark the source lines containing ERC5192/ERC5484's constant `return false` and
`return 0` statements, although its function counters record both functions and the tests assert
both results. Those four lines account for the entire reported gap.

All 21 properties pass at the fixed timestamp and seed with 1,000 runs per parameterized entry.
The suite and its dedicated mock emit 21,780 bytes of initcode and 21,708 bytes of runtime
bytecode. A fair legacy bytecode comparison waits for the hook integration and three cross-feature
properties: the 42 core entries are mixed into six 168-177 KB full-fixture contracts.

The complete replacement checkpoint now has 275 tests across 18 suites, zero inherited entries,
and 241,186 bytes of test-side initcode. A forced canonical AST compile-to-green took 62.46
seconds, including 61.00 seconds in solc, and peaked at 1,931,452 KiB RSS.
