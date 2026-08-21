# V2.5 Gas Optimization Sweep

Status: experimental branch work. Nothing in this document is deployment approval.

## Baseline

- Source: `5e1de3b5ecbb6a430acae1c765ed44b11d9a04ca`
- Compiler: Solc `0.8.25+commit.b61c2a91`
- EVM: Cancun
- Pipeline: optimized IR, optimizer enabled, 44 runs
- Metadata: bytecode hash disabled, CBOR metadata disabled
- Gas seed: `0x5eed`
- Gas cases: 1,771 total; 1,352 unit, 388 fuzz, 31 invariant
- Snapshot SHA-256: `62cedf2c9e8452a19368c74670e69560a1c634ff0e2c974a4abbb3a329b51ce0`
- Snapshot wall time: 37.31 seconds
- Production artifact targets: 115

Largest release artifacts at baseline:

| Contract                 | Initcode bytes | Runtime bytes | EIP-170 margin |
| ------------------------ | -------------: | ------------: | -------------: |
| `WildcatMarketRevolving` |         23,175 |        21,664 |          2,912 |
| `WildcatMarket`          |         22,557 |        21,133 |          3,443 |
| `MarketLensAggregator`   |         20,788 |        20,520 |          4,056 |
| `MarketLensCore`         |         19,896 |        19,726 |          4,850 |
| `PeriodicTermHooks`      |         22,332 |        19,502 |          5,074 |

The earlier optimizer sweep already tested every run count from 1 through 200, plus 50,000
and the maximum `uint32`. This sweep keeps the selected 44-run release profile and focuses on
source and architecture instead of repeating compiler folklore.

## Measurement Contract

Every accepted candidate must be measured against the exact baseline or the immediately prior
accepted commit. The comparison includes:

- fixed-seed Forge gas snapshots and focused gas reports;
- initcode and runtime byte counts for the optimized release artifacts;
- exact ABI hashes;
- normalized storage-layout hashes; and
- focused tests first, followed by the full suite before handoff.

Generate the manifest with:

```bash
FOUNDRY_PROFILE=deploy forge build --skip test --skip script --extra-output storageLayout
node scripts/gas-sweep-metrics.js \
  --artifacts deploy-out \
  --snapshot /tmp/wildcat-v25-gas-baseline.snap
```

The raw baseline files stay outside the repository under `/tmp`; this report records their
reproducible inputs and hashes instead of committing a 160 KiB snapshot.

## Tooling Notes

The documented `docs/coverage-spherex.patch` clears Forge and Slither's named-return-value issue
in `SphereXProtectedRegisteredBase`. Repository-wide Slither then stops on a separate unsupported
pattern: the overloaded dynamic library-function casts used by the market constructor. Targeted
Slither passes work and are used as leads, but the release artifact, tests, and source review are
the actual evidence.

## Candidate Ledger

| ID   | Surface            | Candidate                                                              | Risk      | Status                                        |
| ---- | ------------------ | ---------------------------------------------------------------------- | --------- | --------------------------------------------- |
| G-01 | Standard factory   | Preserve `hooksData` as calldata through deployment and event emission | Low       | Accepted in factory batch                     |
| G-02 | Both factories     | Avoid copying the template's dynamic name on fee and deployment paths  | Low       | Accepted in factory batch                     |
| G-03 | Both factories     | Resolve borrower principals with an exact fixed-size staticcall        | Low       | Accepted in factory batch                     |
| G-04 | Access controls    | Keep read-only batch inputs in calldata                                | Low       | Accepted                                      |
| G-05 | Withdrawal queue   | Pack eight `uint32` expiries into each queue word                      | Medium    | Accepted for new deployments                  |
| G-06 | Both factories     | Pack transient constructor parameters instead of ABI-encoding 16 words | Medium    | Accepted                                      |
| G-07 | Markets            | Reuse exact post-transition balances already loaded by the same path   | Low       | Accepted                                      |
| G-08 | Markets            | Dirty-slot writes instead of four unconditional state writes           | Medium    | Rejected from EVM cost analysis               |
| G-09 | Fleet architecture | Clone or singleton markets/hooks                                       | Very high | Break-even analysis only                      |
| G-10 | Markets            | Remove balance reads across hooks or token transfers                   | High      | Report only; semantics can change             |
| G-11 | Markets            | Reuse the sender already validated by `onlyBorrower`                    | Low       | Accepted with G-07                            |
| G-12 | ERC-4626 wrapper   | Cache principal checks and reuse measured scaled backing               | Low       | Accepted with explicit break-even             |
| G-13 | Access controls    | Short-circuit known-lender checks and reuse provider mapping reads     | Low       | Accepted with G-04                            |
| G-14 | Provider factories | Reuse CREATE2 initcode and hash deterministic addresses in scratch     | Medium    | Accepted                                      |
| G-15 | Market lens        | Keep core helper batch inputs in calldata                              | Low       | Accepted                                      |
| G-16 | Market lens        | Read only the first byte needed from the dynamic market version        | Medium    | Accepted                                      |
| G-17 | Market lens        | Read fixed optional fields and reserve tuples directly into scratch    | Low       | Accepted                                      |
| G-18 | Market lens        | Reuse hook kind and hash bounded hook versions without string decoding | Medium    | Accepted                                      |
| G-19 | Market lens        | Skip pending-administrator probes for unmanaged role providers         | Low       | Accepted                                      |

## Accepted Batches

### Factory deployment and fee paths (G-01 through G-03)

This batch keeps standard-factory hook data in calldata, avoids loading the dynamic template
name when only fee fields are needed, and replaces dynamic borrower-registry call encoding with
an exact 36-byte staticcall. Fee fields are snapshotted before any callback, so the deployment
continues to use one coherent template configuration even if an external call mutates storage.

Measured against the baseline with seed `0x5eed`:

- all focused factory tests pass;
- successful market-deployment cases are 1,981 to 3,777 gas cheaper;
- the tested protocol-fee update batches are 7,669 and 8,117 gas cheaper;
- common validation failures are 545 to 7,251 gas cheaper;
- `HooksFactory` runtime and initcode are 310 bytes smaller, saving roughly 62,000 gas when the
  factory itself is deployed;
- `HooksFactoryRevolving` runtime is 221 bytes smaller and initcode is 207 bytes smaller, saving
  roughly 44,200 gas in runtime code deposit; and
- every ABI and normalized storage-layout hash is unchanged.

The exact production artifact build completed in 1:59.66 using 3,380,368 KiB peak RSS after the
baseline cache had been populated.

### Market balance and borrower reuse (G-07 and G-11)

Several market paths already load the exact asset balance after their final hook and token
transfer, then immediately ask the token for the same balance again while writing delinquency
state. This batch passes the loaded value into `_writeState` for queue withdrawal, batch
repayment, revolving repayment, and APR/reserve changes. It does not carry a balance across a
hook or token transfer. Borrower-only paths also reuse `msg.sender` after `onlyBorrower` has
validated it instead of loading the borrower slot again.

Measured against the baseline with seed `0x5eed`:

- all 467 focused market snapshot cases pass;
- queue-withdrawal cases are generally 803 to 1,062 gas cheaper per call;
- APR/reserve changes are generally 612 to 765 gas cheaper per execution;
- batch-repayment cases are 753 to 2,554 gas cheaper depending on the number of calls made;
- ordinary repayment is 914 gas cheaper in the direct test, with revolving repayment cases
  saving 830 to 1,660 gas;
- borrower-only storage reuse saves 78 gas on the direct borrow cases and roughly 1,005 gas in
  the tested excess-asset close path;
- runtime changes are effectively flat: `WildcatMarket` is 2 bytes larger,
  `WildcatMarketRevolving` is 7 bytes smaller, and `WildcatMarketWithdrawals` is 29 bytes
  smaller; and
- public ABIs are unchanged. No storage declaration or storage struct changed; exact normalized
  layout hashes remain queued for the final forced build because Forge left incremental
  post-test `storageLayout` artifacts null.

The focused market compile and test took 9:34.22. The incremental production build took 1:58.91
and used 3,333,764 KiB peak RSS.

### Wrapper call caching (G-12)

Wrapper executions now reuse the scaled backing measured after each market-token transfer for
the final solvency check. Sanctions checks also fetch the current borrower principal once within
each uninterrupted precheck or share-transfer hook. The principal is deliberately fetched again
after a market-token transfer, so the optimization does not carry identity state across an
external state-changing boundary.

Measured against the baseline with seed `0x5eed`:

- all 168 focused wrapper snapshot cases pass;
- direct deposit and mint cases are 2,613 to 2,616 gas cheaper;
- direct withdraw and redeem cases are 4,931 to 6,167 gas cheaper;
- common share-transfer sanctions paths are 4,194 to 4,529 gas cheaper;
- `Wildcat4626Wrapper` runtime grows by 807 bytes and initcode grows by 835 bytes;
- `Wildcat4626WrapperFactory` grows by 835 bytes because it embeds the wrapper creation code;
  deploying a wrapper costs about 161,900 more gas in the measured factory test; and
- the per-wrapper deployment increase breaks even after roughly 62 deposits, 27 withdrawals,
  or 36 share transfers, before amortizing the one-time factory deployment increase.

This is a lifecycle optimization rather than a universal win. It belongs in the experimental
stack because active wrappers should clear the break-even, but a production decision should use
expected wrapper activity and deployment count.

### Access-control calldata and lookup reuse (G-04 and G-13)

Read-only administrative batches now remain in calldata, hooks-data validation reuses the role
provider value already loaded for the selected address, and the known-lender update uses actual
short-circuit evaluation. The last change matters on withdrawal paths: they cannot mark a lender
known, so they no longer perform the second mapping lookup merely to feed an eager boolean helper.

Measured against the baseline with seed `0x5eed`:

- the full access-hook suite and the focused controller/provider suites pass;
- `grantRoles` is 2,040 gas cheaper in open, fixed, and periodic hooks;
- `setName` is 276 gas cheaper and the tested hooks-data validation path is 196 gas cheaper;
- restricted withdrawal validation cases save 234 to 425 gas;
- access-list batch mutation saves 285 gas in its direct test;
- the successful SphereX controller update batch saves 1,348 gas, with failure and null-engine
  cases saving 431 to 1,043 gas; and
- runtime shrinks by 210 bytes for open/fixed hooks, 218 bytes for periodic hooks, 31 bytes for
  `WildcatArchController`, and 52 bytes for both the access-list provider and its factory.

Every public ABI is unchanged and no storage declaration changed.

### Packed unpaid-withdrawal queue (G-05)

The unpaid-batch FIFO now stores eight `uint32` expiries per mapping word. Consumed full words
are deleted, while the current partial word stays allocated so the next batch can reuse it. The
queue can therefore retain one word while empty, but stale storage cannot grow without bound.

This is intentionally a new-deployment-only change: the mapping value type and encoding changed,
even though the queue's top-level slot did not. It must not be applied to an existing market.

Measured against the preceding accepted commit with seed `0x5eed`:

- all 18 focused queue tests pass, including a 1,000-run reference-model fuzz test covering zero
  values, partial shifts, appends, empty-queue reuse, and packed-word boundaries;
- all 62 ordinary withdrawal tests, the fixed-term equivalence suite, and the public lens unpaid-
  expiry regression test pass;
- `WildcatMarket`, `WildcatMarketRevolving`, and `WildcatMarketWithdrawals` each grow by 78 runtime
  and initcode bytes, adding roughly 15,600 gas to each market deployment;
- a separate-transaction Anvil benchmark puts the first packed push 72 gas above baseline, then
  saves 17,028 gas on each of pushes two through eight into the same word;
- consuming a partial word saves 254 gas per shift, while the eighth shift that deletes the full
  word costs 53 gas more; and
- consuming eight queued entries with `shiftN` drops from 54,429 to 27,054 gas.

The deployment increase is recovered by the second unpaid batch. Forge's single-transaction test
snapshots exaggerate delete refunds, so the lifecycle conclusion uses the separate-transaction
benchmark rather than treating aggregate test gas as production transaction gas.

### Packed transient constructor handoff (G-06)

Both factories now hand market constructors ten fixed transient words instead of ABI-encoding a
16-word temporary struct into a transient byte array. The scalar parameters fill one exact 256-bit
word, asset shares a word with decimals, and borrower principal shares a word with the revolving
commitment fee. The borrower word is the active marker; clearing it makes both public constructor
getters revert outside deployment, while every later deployment overwrites all remaining words
before restoring the marker.

Measured against the preceding accepted commit with seed `0x5eed`:

- a 1,000-run codec fuzz test round-trips every field, including arbitrary hook words and all
  integer widths; explicit tests cover dirty-word overwrite, clear, and inactive reads;
- all 40 standard-factory tests and 47 revolving-factory tests pass;
- standard `deployMarket` and `deployMarketAndHooks` are each 6,117 gas cheaper;
- the measured revolving deployment paths are 7,368 to 7,369 gas cheaper;
- the standard factory grows by 59 runtime/initcode bytes, adding roughly 11,800 gas to its
  one-time deployment, so its deployment cost breaks even with the second market;
- the revolving factory shrinks by 347 runtime/initcode bytes, saving roughly 69,400 gas when the
  factory itself is deployed; and
- public ABIs and persistent storage layouts are unchanged. The internal transient encoding is
  deliberately different and exists only during market construction.

### Role-provider CREATE2 deployment (G-14)

The six role-provider factories now build each provider's initcode once, use that same buffer
for both the deterministic-address check and `CREATE2`, and hash the caller namespace and CREATE2
preimage in scratch memory. The collision check still runs before `CREATE2`; omitting it makes a
duplicate deployment consume nearly all forwarded gas because an EIP-684 collision is an
exceptional creation failure. Constructor revert data is copied through unchanged.

Measured against the preceding accepted commit with seed `0x5eed`:

- all 55 existing provider-factory tests pass, including constructor failures, duplicate salts,
  generic factory calls, caller namespaces, and deployment events;
- six independent regression tests compare every factory's result against the canonical CREATE2
  formula built from the provider creation code and constructor arguments;
- successful typed deployments save 1,427 to 2,003 gas across the five fixed-size providers;
- their generic `createRoleProvider(bytes)` path saves 1,199 to 1,780 gas;
- access-list provider creation saves 1,581 to 1,685 gas in the direct cases, and deploying two
  caller-namespaced instances saves 3,082 gas;
- the five fixed-size factory runtimes shrink by 98 to 132 bytes;
- the access-list factory grows by 59 bytes relative to the preceding accepted commit, adding
  roughly 11,800 gas to its one-time deployment and breaking even after about eight provider
  deployments; and
- public ABIs and storage declarations are unchanged. Provider addresses remain byte-for-byte
  compatible because both the constructor encoding and caller-namespaced salt are unchanged.

### Lens core calldata reads (G-15)

Dynamic batch inputs to the core lens helper now stay in calldata until each item is consumed.
This covers token and market lists, lender lists, withdrawal expiries, and nested lender-account
queries. The aggregation helper keeps its memory-based internals because those arrays are built
from other contract calls rather than supplied by the RPC caller.

Measured against the preceding accepted commit with seed `0x5eed`:

- both complete lens suites pass: 68 tests across the core, live, facade, aggregation, legacy,
  revolving, periodic, and multi-factory paths;
- a single-market `getMarketsData` call saves 726 gas;
- the bundled facade parity checks save 2,143 gas across token/market reads and 5,686 gas across
  account/withdrawal reads;
- `MarketLensCore` runtime and initcode shrink by 351 bytes;
- the `MarketLens` facade runtime and initcode shrink by 415 bytes, increasing its EIP-170 margin
  without changing delegation behavior; and
- canonical ABI hashes for the facade and all three helpers are unchanged. No storage
  declaration changed.

### Bounded market-version probe (G-16)

Market-data reads used to ABI-decode the complete dynamic `version()` string and then inspect
only its first byte. The lens now performs one bounded staticcall, validates the standard dynamic
offset and minimum result shape, and reads that byte directly. Failed version calls still bubble
their revert data; V1 and empty versions remain non-V2, and truncated dynamic data still reverts.

Measured against the preceding accepted commit with seed `0x5eed`:

- both complete lens suites pass with 71 tests, including new V2, V1, empty-string, short-return,
  and revert-bubbling cases for the version probe;
- ordinary market-data fills save roughly 530 to 575 gas per market across direct, paginated,
  aggregated, legacy, and revolving reads;
- the one-market batch parity test, which fills the same market twice, saves 1,131 gas;
- `MarketLensCore` and `MarketLensAggregator` each grow by eight runtime/initcode bytes, adding
  roughly 1,600 gas to each one-time helper deployment; and
- public ABIs and storage declarations are unchanged.

### Fixed-output lens probes (G-17)

The optional revolving getters and temporary excess-reserve getter now return directly into a
fixed scratch buffer. The old paths allocated dynamic `bytes` values and decoded them even though
the lens only accepts one 32-byte word or one 96-byte tuple. Missing methods, call failures, and
short results still leave the optional data absent, matching the previous fail-soft behavior.

Measured against the preceding accepted commit with seed `0x5eed`:

- all existing malformed, reverting, missing, zero-valued, legacy, revolving, and live-data
  probe cases pass;
- the temporary-reserve probe saves about 815 gas per ordinary market-data fill;
- the two optional revolving probes save about 544 gas per live-market row;
- full V2 market-data cases save roughly 1,660 to 1,690 gas per call depending on which optional
  getter is absent or malformed;
- runtime and initcode shrink by 148 bytes for `MarketLensCore`, 153 bytes for
  `MarketLensAggregator`, and 88 bytes for `MarketLensLive`; and
- public ABIs and storage declarations are unchanged.

### Hook-kind reuse and bounded version hashing (G-18)

Full market reads used to fetch and decode the same hooks-instance version twice: once while
classifying the market hooks and again while filling hooks-instance metadata. The second fill now
uses the already-resolved enum. Direct hooks-instance reads still resolve their own kind, but do
so by hashing a validated bounded return buffer instead of ABI-decoding a dynamic string. Valid
unknown versions longer than one word remain `Unknown`; failed calls still bubble, and malformed
dynamic returns still revert.

Measured against the preceding accepted commit with seed `0x5eed`:

- both complete lens suites pass with 74 tests, including new known, empty, long, truncated, and
  reverting hook-version cases;
- common full market-data fills save about 2,170 gas per market;
- the periodic-term market regression saves 5,278 gas because it performs multiple related
  market-data reads;
- a direct periodic hooks-instance read saves 805 gas even though it cannot reuse a market's
  already-resolved kind;
- `MarketLensCore` grows by 19 runtime/initcode bytes and `MarketLensAggregator` grows by five,
  adding roughly 4,800 gas across both one-time helper deployments; and
- public ABIs and storage declarations are unchanged.

### Unmanaged role-provider short circuit (G-19)

Role-provider metadata now asks for `pendingAdministrator()` only when the provider first returns
a valid `administrator()`. A provider cannot be classified as managed without both values, so the
second capped staticcall was dead work for every ordinary token, Merkle-proof, or other unmanaged
provider.

Measured against the preceding accepted commit with seed `0x5eed`:

- unmanaged-provider hook-instance and market-data cases save 664 gas per metadata fill;
- the one-market batch parity test fills the same market twice and saves 1,328 gas;
- the managed-provider administration regression still passes and remains semantically complete;
- `MarketLensCore`, `MarketLensAggregator`, and `MarketLensLive` each shrink by 12 runtime/initcode
  bytes; and
- public ABIs and storage declarations are unchanged.

## Rejected Candidates

### Conditional packed-state writes (G-08)

The market reads its four packed state slots before every write. Writing an unchanged warm slot
already costs 100 gas. Adding a fresh warm `SLOAD`, comparison, and branch to avoid that write
does not remove meaningful EVM work, and modified slots still need the `SSTORE`. This is not a
useful optimization unless the state-loading API is redesigned to retain the original raw words,
which is disproportionate to the upper bound.

Rejected candidates and further benchmark results will be added here as the sweep progresses.
