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

## Rejected Candidates

### Conditional packed-state writes (G-08)

The market reads its four packed state slots before every write. Writing an unchanged warm slot
already costs 100 gas. Adding a fresh warm `SLOAD`, comparison, and branch to avoid that write
does not remove meaningful EVM work, and modified slots still need the `SSTORE`. This is not a
useful optimization unless the state-loading API is redesigned to retain the original raw words,
which is disproportionate to the upper bound.

Rejected candidates and further benchmark results will be added here as the sweep progresses.
