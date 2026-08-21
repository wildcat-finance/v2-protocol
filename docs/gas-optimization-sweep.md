# V2.5 Reviewed Gas Optimization Result

This is the final measurement of the reviewed optimization branch, not the full experimental
ledger. It compares the code we kept with the reproducible baseline and records enough detail to
audit the decision later.

## Final state

- Baseline: `df688a94` (`chore(gas): add reproducible optimization baseline`). Its production
  Solidity is identical to `5e1de3b5`; that commit only added the original measurement tooling
  and report.
- Reviewed head: `6c2cbfb` (`perf(withdrawals): [G-05] pack unpaid batch queue`).
- Retained work: 15 commits covering 17 candidate IDs.
- Compiler settings match exactly: Solidity `0.8.25`, Cancun, IR enabled, optimizer enabled with
  44 runs, no CBOR metadata, and no bytecode hash.
- No existing public ABI changed.
- No `WildcatArchController`, `HooksFactory`, or `HooksFactoryRevolving` source changed.
- The only persistent storage-layout change is G-05's unpaid-batch queue representation in the
  market family. It is intentionally limited to markets deployed by new factory bytecode.
- All 1,797 fixed-seed Forge cases pass at the reviewed head.

The useful runtime gains are concentrated in wrappers, common market accounting paths, access
checks, sanctions/identity calls, and Lens reads. The one meaningful tradeoff is G-05: the first
unpaid batch is slightly more expensive, while every later batch in the packed word is much
cheaper. That is a good lifecycle trade for new markets and is not safe to retrofit into existing
market storage.

## Runtime result

| Surface | Runtime difference |
| --- | ---: |
| Market operations (G-07/G-11) | -78 to -2,554 gas |
| Unpaid-batch loop (G-30) | -55 to -151 gas; closed-market revert +2 |
| Access controls (G-04/G-13/G-22) | -196 to -2,040 gas |
| Wrapper deposit/mint (G-12/G-37/G-38) | -5.97k to -6.15k gas |
| Wrapper withdraw/redeem (G-12/G-37/G-38) | -10.2k to -13.0k gas |
| Wrapper share transfer (G-12/G-37/G-38) | -8.7k to -9.3k gas |
| Sanctions paths (G-35) | -187 to -550 gas |
| Identity registry paths (G-36) | -241 to -1,939 gas |
| Lens complete market row (G-15–G-19) | -5.75k to -5.83k gas-equivalent (`eth_call` only) |
| G-05 first queue push | +72 gas |
| G-05 queue pushes 2–8 | -17,028 gas each |
| G-05 shift eight entries | 54,429 → 27,054 (-27,375 gas) |
| Comparable snapshot cases | 7,530,471,337 → 7,501,798,833 (-0.381%) |

G-05 breaks even on the second unpaid batch and only applies to newly deployed markets. Snapshot
result: 958 cases cheaper, 313 costlier, 469 unchanged, and no baseline cases removed.

## Code size and deployment

Across the 115 production targets present in both builds:

- total initcode falls from 326,558 to 317,041 bytes: -9,517 (-2.91%); and
- total runtime falls from 299,468 to 290,596 bytes: -8,872 (-2.96%).

Those totals double-count inherited and embedded code, so they describe the artifact set rather
than the cost of one deployment ceremony. Selected deployable targets are more useful:

| Target | Runtime bytes | Delta | Approx. code-deposit component |
| --- | ---: | ---: | ---: |
| `FixedTermHooks` | 16,530 | -310 | -62.0k gas |
| `OpenTermHooks` | 15,233 | -310 | -62.0k gas |
| `PeriodicTermHooks` | 19,193 | -309 | -61.8k gas |
| Lens facade/core/live/aggregator, combined | — | -1,151 | -230.2k gas |
| `WildcatMarket` | 21,197 | +64 | +12.8k gas |
| `WildcatMarketRevolving` | 21,719 | +55 | +11.0k gas |
| `Wildcat4626Wrapper` | 8,664 | -2,756 | -551.2k gas per wrapper |
| `Wildcat4626WrapperFactory` | 12,352 | -3,071 | -614.2k gas |
| `WildcatBorrowerIdentityRegistry` | 4,496 | -628 | -125.6k gas |
| `WildcatSanctionsSentinel` | 3,184 | -99 | -19.8k gas |

The estimates use the 200-gas-per-runtime-byte code-deposit component only. They exclude initcode
metering and constructor execution, so they are directional rather than full deployment quotes.
The tighter reviewed contracts remain below EIP-170: `WildcatMarketRevolving` has 2,857 bytes of
headroom, `PeriodicTermHooks` 5,383, and `MarketLensCore` 5,334.

Four ABI-empty internal helper-library artifacts become independently reachable in the build.
Each is only 31 bytes of initcode and 3 bytes of runtime:

- `LibFixedCall`;
- `ERC165QueryLib`;
- `TokenQueryLib`; and
- `LibTransientMarketParameters`.

## Compatibility boundary

- Existing markets and factories keep their current initcode and storage layout. Old and new
  markets can coexist, and both expose the same `getUnpaidBatchExpiries` ABI.
- Only the six market-family artifact layouts change: `WildcatMarket`, `WildcatMarketBase`,
  `WildcatMarketConfig`, `WildcatMarketRevolving`, `WildcatMarketToken`, and
  `WildcatMarketWithdrawals`.
- Wrapper, sentinel, registry, hooks, access-control, and Lens changes do not change public ABIs or
  persistent storage layouts. Their effect begins when the relevant implementation is deployed.
- Lens specialization is intentionally acceptable here because Lens is replaceable. G-15–G-19 do
  not constrain future factories, hooks types, role providers, or markets.
- The reviewed branch deliberately omits experimental ArchController changes, factory-association
  packing, transient factory handoffs, the Merkle half of G-22, and the broader `LibFixedCall`
  conversions that did not justify their integration cost.

## Retained catalogue

| IDs | Commit | What was kept |
| --- | --- | --- |
| G-07/G-11 | `49613fb` | Reuse current market asset balances and the already-validated borrower. |
| G-30 | `59eb8bb` | Proved unchecked increment in the unpaid-batch processing loop. |
| G-04/G-13 | `1da7392` | Calldata batch inputs, short-circuited lender checks, and reused provider reads. No ArchController change. |
| G-12 | `2300cba` | Cache wrapper state and reuse measured scaled backing. |
| G-37 | `9bcb8c2` | Bounded wrapper policy, sanctions, and escrow probes. |
| G-38 | `7d030c1` | Shared bounded one-word wrapper market readers. |
| G-35 | `4df1aed` | Bounded Chainalysis probes. |
| G-36 | `bca7c75` | Bounded identity-registry controller probes. |
| G-22 | `afc2753` | Only the generic `BaseAccessControls` pull-provider classification. Merkle changes omitted. |
| G-15 | `d782001` | Keep Lens batch-read inputs in calldata. |
| G-16 | `2fec297` | Bound the Lens market-version read to the byte it needs. |
| G-17 | `11f4a04` | Use fixed output buffers for optional Lens probes. |
| G-18 | `b0e064f` | Reuse resolved hooks kind and hash bounded version output. |
| G-19 | `16d66c9` | Skip unused administrator reads for unmanaged providers. |
| G-05 | `6c2cbfb` | Pack eight unpaid-batch expiries into each FIFO word for new markets. |

## Verification

Both revisions were built from exact release artifacts with:

```sh
FOUNDRY_PROFILE=deploy forge build --skip test --skip script --extra-output storageLayout
```

The reviewed head was then exercised with:

```sh
forge snapshot --fuzz-seed 0x5eed --snap /tmp/wildcat-v25-gas-reviewed-final.snap
node scripts/gas-sweep-metrics.js \
  --artifacts deploy-out \
  --snapshot /tmp/wildcat-v25-gas-reviewed-final.snap
```

- Result: 1,797 tests across 94 suites; zero failures.
- Baseline snapshot SHA-256:
  `62cedf2c9e8452a19368c74670e69560a1c634ff0e2c974a4abbb3a329b51ce0`.
- Reviewed snapshot SHA-256:
  `1ab2a2556023de92e75441d66d6a1c2ed131277d686f0faf9674e50f094ba081`.
- The successful full run took 20m37s including a 1,197-second compile and peaked around 23.7 GB
  RSS. The familiar non-fatal SphereX parser diagnostic appeared after Forge completed; it did
  not affect the build, test results, or exit status.
