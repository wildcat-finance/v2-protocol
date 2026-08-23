# Token role-provider parity

Status: complete.

## Family boundary

The ERC20, ERC721, ERC1155, ERC4626-assets, ERC5192, and ERC5484 legacy files contain 87 tests
across 12 suites. They mix three different concerns:

| Concern                                    | Legacy entries | Status                                          |
| ------------------------------------------ | -------------: | ----------------------------------------------- |
| Provider credentials and constructor gates |             42 | Replaced by 21 focused properties               |
| Shared hook/market access behavior         |             42 | Replaced by 9 runtime-matrix properties         |
| Wildcat debt-token and wrapper interest    |              3 | Replaced by 3 production-composition properties |

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

## Hook integration disposition

The 42 legacy integration entries repeated the same full controller/factory/market fixture for
each provider. The replacement deploys production `OpenTermHooks` and production provider
artifacts, registers a lightweight market identity through `onCreateMarket`, and calls the real
`onDeposit` path as that market. This keeps provider discovery, credential caching, hooks-data
decoding, lender-status writes, first-deposit state, blocking, and `NotApprovedLender` behavior in
scope without embedding the rest of the protocol six times.

| Legacy behavior group                          | Entries | Replacement disposition                                                                                     |
| ---------------------------------------------- | ------: | ----------------------------------------------------------------------------------------------------------- |
| Pull-provider admission and rejection          |       9 | Four-provider current-credential matrix; configured ERC1155 ID is also proven in the provider-truth suite   |
| Zero-TTL recheck and moved eligibility         |       7 | Four-provider matrix checks old-account rejection and new-account admission in the same block               |
| Positive-TTL delayed removal                   |       4 | Four-provider cache/expiry matrix                                                                           |
| Hook-local block overrides eligibility         |       4 | One real-hook property composed with the shared block/status properties in `BaseAccessControlsTest`         |
| Reverting reads and later-provider fallthrough |       9 | Four-provider failed-read/fallthrough matrix plus the ERC4626 conversion-failure path                       |
| Push-provider policy and admission             |       8 | ERC5192/ERC5484 packed-data hook matrix composed with the provider-truth lock and burn-authorization matrix |
| Push credential expiry after ownership change  |       1 | Both push-provider variants must revalidate after expiry; this strengthens the ERC5192-only legacy property |

Malformed packed data is also rejected through the real deposit hook for both push variants. It
was previously asserted only against the providers directly.

The focused provider matrix deliberately does not pretend that a lightweight market identity
proves ERC20 movement, accounting, or market state. Three production-composition properties now
close that boundary through real `WildcatMarket.depositUpTo -> OpenTermHooks.onDeposit` calls:

- A debt-token provider reports the lender's balance outside a market call, but cannot authorize
  deposits back into its own source market. The recursive debt-token balance read reaches the
  source market's view reentrancy guard and the provider fails closed.
- Interest on a source-market debt-token balance can cross the configured threshold and authorize
  a deposit into a different production market.
- Interest on a wrapper's underlying market claim can cross the configured asset threshold and
  authorize a deposit into a different production market.

The latter two properties first prove rejection below the threshold, accrue a year of production
market interest, and then prove admission through the target market's real deposit entrypoint.

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

The 30 focused replacement properties pass at the fixed timestamp and seed with 1,000 runs per
parameterized entry. The two suites and their shared token mock emit 30,482 bytes of initcode and
30,384 bytes of runtime bytecode. The comparable 84-property legacy provider slice emits
1,110,784 bytes of initcode and 387,022 bytes of runtime bytecode after excluding the two suites
that own the three cross-feature scenarios. That is a 97.26% initcode reduction and a
92.15% runtime-bytecode reduction for the migrated behavior.

All 33 mapped properties are now closed. The two legacy cross-feature artifacts emit 335,492 bytes
of initcode and 94,900 bytes of runtime bytecode for their three entries. Adding the three
production-composition properties and the shared memory-safe artifact deploy path grew the full
replacement suite by 12,271 bytes in both measures, a conservative 96.34% initcode and 87.07%
runtime-bytecode reduction for that final slice.

The complete replacement checkpoint now has 617 tests across 39 suites, zero inherited entries,
902,866 bytes of test-side initcode, and 892,638 bytes of runtime bytecode. A forced canonical
via-IR AST compile-to-green took 2m32.40s, including 148.68s in solc, and peaked at 3,965,736 KiB
RSS. All tests passed at the fixed timestamp and seed.
