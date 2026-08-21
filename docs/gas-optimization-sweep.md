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
| G-04 | Access controls    | Keep read-only batch inputs in calldata                                | Low       | Pending benchmark                             |
| G-05 | Withdrawal queue   | Pack eight `uint32` expiries into each queue word                      | Medium    | Pending benchmark                             |
| G-06 | Both factories     | Pack transient constructor parameters instead of ABI-encoding 16 words | Medium    | Pending investigation                         |
| G-07 | Markets            | Reuse exact post-transition balances already loaded by the same path   | Low       | Accepted                                      |
| G-08 | Markets            | Dirty-slot writes instead of four unconditional state writes           | Medium    | Rejected from EVM cost analysis               |
| G-09 | Fleet architecture | Clone or singleton markets/hooks                                       | Very high | Break-even analysis only                      |
| G-10 | Markets            | Remove balance reads across hooks or token transfers                   | High      | Report only; semantics can change             |
| G-11 | Markets            | Reuse the sender already validated by `onlyBorrower`                    | Low       | Accepted with G-07                            |
| G-12 | ERC-4626 wrapper   | Cache principal checks and reuse measured scaled backing               | Low       | Accepted with explicit break-even             |

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

## Rejected Candidates

### Conditional packed-state writes (G-08)

The market reads its four packed state slots before every write. Writing an unchanged warm slot
already costs 100 gas. Adding a fresh warm `SLOAD`, comparison, and branch to avoid that write
does not remove meaningful EVM work, and modified slots still need the `SSTORE`. This is not a
useful optimization unless the state-loading API is redesigned to retain the original raw words,
which is disproportionate to the upper bound.

Rejected candidates and further benchmark results will be added here as the sweep progresses.
