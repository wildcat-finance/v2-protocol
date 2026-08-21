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
| G-07 | Markets            | Reuse exact post-transition balances already loaded by the same path   | Low       | Pending benchmark                             |
| G-08 | Markets            | Dirty-slot writes instead of four unconditional state writes           | Medium    | Pending IR and gas proof                      |
| G-09 | Fleet architecture | Clone or singleton markets/hooks                                       | Very high | Break-even analysis only                      |
| G-10 | Markets            | Remove balance reads across hooks or token transfers                   | High      | Report only; semantics can change             |

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

Rejected candidates and further benchmark results will be added here as the sweep progresses.
