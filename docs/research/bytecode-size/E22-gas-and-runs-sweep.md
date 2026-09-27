# E22: gas qualification and optimizer runs 1–44

Source parent: `63f80d4`, production source unchanged from `04cfbd0`.
Status: complete. The user requested gas measurements and a complete runs
sweep before deciding whether to change the adopted compiler configuration.

## Hypothesis and controls

Some higher runs settings may still fit and reduce hot-path gas. Measure every
integer from 1 through 44; size is not assumed to increase monotonically. Hold
the adopted Yul sequence, Solidity 0.8.25, Cancun, viaIR, and metadata settings
fixed. Archive the exact inputs and compiler outputs outside the repository.
Check both markets, factories, hooks, composition examples, and lenses. The
runs-1 point must reproduce the qualified production artifacts byte-for-byte.
Do not edit production source or `foundry.toml` during the experiment.

Use matched, deterministic transactions on both market families and all three
hook templates. Measure deposits, borrowing, repayment, withdrawal queue and
collection, state updates, transfers, and APR changes. Separately measure
scheduled-repayment paths that do not exist in the release baseline.

Compare current source at runs 1 with the adopted Yul sequence against:

- current source at useful runs settings selected from the size sweep;
- current source at runs 44 with the default Yul sequence;
- `release/v2.5` at `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`, runs 44 and
  default Yul, through the same common scenarios.

The same-source comparisons identify compiler effects. The release comparison
includes the combined hook/lifecycle/source changes, not just one storage slot.
Keep call isolation enabled and separate setup, transaction execution, and
deployment measurements. A raised limit for oversized benchmark controls does
not qualify those controls for deployment. Any newly selected production
settings need ordinary tests and strict deployment checks before adoption.

## Tracker

- [x] Reproduce runs 1, compile all 44 points, record exact size boundaries.
- [x] Run identical common gas scenarios across selected compiler/source builds.
- [x] Measure current-only repayment and penalty paths separately.
- [x] Record results, limitations, and a compiler recommendation; signed kethcode
  checkpoint. Do not push or silently change production settings.

## Size result

With the adopted Yul sequence, both market runtimes fit at every runs value
from **1 through 14**. Revolving fails at every value from **15 through 44**;
it never returns below the limit. All other measured runtimes fit throughout.
The independent runs-1 build matches all fourteen qualified artifacts exactly.
ABI and normalized storage layout remain identical across the sweep.

| Runs | Standard runtime | Revolving runtime | Revolving headroom |
| ---: | ---: | ---: | ---: |
| 1 | 23,778 | 24,334 | 242 |
| 2 | 23,788 | 24,344 | 232 |
| 3–4 | 23,785 | 24,341 | 235 |
| 5–13 | 23,802 | 24,358 | 218 |
| 14 | 23,891 | 24,447 | 129 |
| 15–16 | 24,059 | 24,628 | −52 |
| 17–18 | 24,057 | 24,626 | −50 |
| 19–25 | 24,041 | 24,610 | −34 |
| 26–33 | 24,046 | 24,615 | −39 |
| 34–44 | 24,044 | 24,613 | −37 |

These are runtime bytes against 24,576, not raw-initcode store sizes. Compression
remains necessary. Equal sizes do not mean equal bytecode or gas: runs 5 and 13
have different binaries. The full fourteen-target table is in
[e22-sizes.tsv](./results/e22-sizes.tsv).

The former runs-44 **default** Yul sequence produces 24,474 / 25,050 bytes on
current market source. Its revolving overage is 474 bytes. That control is
different from the runs-44 **adopted** sequence in the table above.

## Gas method and validation

The identical common fixture runs six scenarios: standard/revolving crossed
with open/fixed/periodic hooks, deployed through their production factories.
Each scenario measures first and repeat deposits, accrued deposits, first and
repeat borrowing, accrued repayment, new/existing transfer recipients, APR
increases, same-timestamp/accrued updates, new/existing withdrawal batches,
expiry processing, collection, and manual closure. Open/fixed scenarios also
reduce APR; periodic scenarios propose and execute their delayed reduction.
The rates, balances, terms, amounts, and timestamps are identical across builds.

Four further current-source scenarios cover both market models in scheduled
repayment and ordinary penalty. Repayment includes date activation, partial
payment, deadline/default plus coincident expiry, final repayment with automatic
closure, collection, and surplus recovery. These new-feature samples have no
release-baseline comparison.

Five current-source builds run ten scenarios each: adopted Yul at runs 1, 5,
13, and 14, plus default Yul at runs 44. The release baseline runs the six common
scenarios at default Yul/runs 44. All **56 scenarios pass**, producing **774
call snapshots**. Every comparable scenario ends with an identical fingerprint
of market accounting and lender/borrower asset balances. The common fixture's
source hash is identical in all six builds. Both market and all three hook
artifacts in each adopted-sequence gas build match the independent size sweep
byte-for-byte, including creation code.

Measurements use Foundry 1.8.3's
[`snapshotGasLastFrame`](https://github.com/foundry-rs/foundry/blob/v1.8.3/crates/cheatcodes/spec/src/vm.rs)
immediately after the target call. `isolate = true` gives each top-level call a
separate transaction context, including storage warmth. Same-timestamp samples
therefore do not reuse the previous call's warmed storage. Setup, assertions,
fixture dispatch, and deployment are outside the recorded call. Values use
Foundry's isolated-call receipt/refund accounting under Cancun, not a subtraction
of `gasleft()` around the Solidity body. They are not a mainnet fee quote: this
is a deterministic mock-token workload, and dependencies are compiled under each
build's settings. It does not characterize every asset, access-provider path,
batch backlog, or warm multicall.

The 200,000-byte test limit permits oversized reference runtimes and test harnesses.
It is applied uniformly and is not deployment qualification. Runs 5/13/14 have
these scenario checks, not the full E20/E21 release qualification. The production
configuration remains at the already-qualified runs 1.

## Compiler cost versus source cost

On the 104 common call samples, current runs 1/adopted Yul costs **371–1,966 gas**
more than current runs 44/default Yul: **0.60–2.16%**, with a 1.31% median across
these samples. The compiler setting is a modest part of the total change.

Comparing source at the same runs-44/default-Yul settings adds **2,424–11,017
gas**, or **4.10–16.51%**. The smallest difference is the direct periodic
proposal call; many market actions add about 7,000–11,000 gas. This is the combined
source delta, including hook/lifecycle logic and code-size changes. It does not
attribute the entire difference to the new lifecycle storage slot.

Representative open-hook samples:

| Market / operation | Release, default 44 | Current, default 44 | Current, adopted 1 | Source delta at 44 | Compiler delta |
| --- | ---: | ---: | ---: | ---: | ---: |
| Standard accrued deposit | 103,594 | 112,178 | 113,498 | +8,584 | +1,320 |
| Standard borrow | 71,310 | 78,351 | 79,375 | +7,041 | +1,024 |
| Standard accrued repay | 64,647 | 72,295 | 73,329 | +7,648 | +1,034 |
| Standard new withdrawal batch | 179,233 | 187,184 | 188,821 | +7,951 | +1,637 |
| Standard collection | 77,828 | 84,818 | 85,868 | +6,990 | +1,050 |
| Standard accrued update | 49,684 | 57,682 | 58,825 | +7,998 | +1,143 |
| Revolving accrued deposit | 106,030 | 114,572 | 115,916 | +8,542 | +1,344 |
| Revolving existing borrow | 79,127 | 86,124 | 87,107 | +6,997 | +983 |
| Revolving accrued repay | 72,510 | 80,072 | 81,160 | +7,562 | +1,088 |
| Revolving expiry processing | 73,572 | 84,438 | 86,250 | +10,866 | +1,812 |

At adopted runs 1, the scheduled date-activation call costs 83,808 / 86,729 gas
for standard/revolving in this scenario. Final repayment plus automatic closure
costs 83,060 / 85,339; surplus recovery costs 61,817 on both. These are complete
operation costs, not incremental overhead. The separate lifecycle rows and all
common rows are in [e22-gas.tsv](./results/e22-gas.tsv).

## Decision

The user confirmed retaining runs 1 on 2026-09-27 after reviewing these results.
The adopted Yul sequence and `foundry.toml` remain unchanged. The measured
higher-runs savings are small:

| Adopted-Yul setting | Extra revolving bytes versus 1 | Gas saved per common sample versus 1 | Percentage saved |
| ---: | ---: | ---: | ---: |
| 5 | 24 | 78–306 | 0.04–0.37% |
| 13 | 24 | 78–339 | 0.05–0.37% |
| 14 | 113 | 204–565 | 0.14–0.64% |

Runs 13 would spend 24 bytes for those savings. Runs 14 consumes almost half
the current revolving headroom for less than 1% improvement in these samples.
No production setting was changed.
Selecting either alternative still requires the ordinary suites, compressed-store
and strict-deployment checks, and regenerated deployment artifacts.

This completes the hot-path measurement follow-up. Creation gas versus raw
storage, the actual deployment ceremony, the required Anvil-fork rehearsal, and
the final inventory/freeze remain separate work. This local benchmark is not the
fork rehearsal.

## Receipts and reproduction

The [summary receipt](./results/e22.json) records source/settings, artifact hashes,
fixture identity, test counts, and comparison ranges. Complete inputs, outputs,
snapshots, logs, and detached benchmark worktrees are under
`/home/kethcode/wildcat/bytecode-research/2026-09-27/`, in
`e22-runs-sweep-qualified/` and `e22-gas-final-{runs1,runs5,runs13,runs14,default44,release44}/`.
Some final receipts reuse earlier worktrees; each receipt records its actual path.

Two setup corrections are retained in earlier receipts: the first sweep expected
storage layouts in normal Forge artifacts, which do not emit them; subsequent
points compare against the native runs-1 layout while still checking Forge bytecode
and ABI exactly. The first gas worktree copied dependency source without Git
metadata; the final runner preserves dependency repository references and runs
offline. Initial periodic scenarios proposed during an open withdrawal window
and were correctly rejected in all three initial compiler/source builds. The
final common fixture proposes after that window closes. No production changes or
weakened assertions were needed.

From the repository root, use new receipt directories:

```sh
python3 scripts/research/optimizer-sweep.py /tmp/wildcat-runs-sweep --forge-reference deploy-out --workers 4
python3 scripts/research/gas-benchmark.py /tmp/wildcat-gas-runs1 --ref 63f80d4 --runs 1 --yul adopted
python3 scripts/research/gas-benchmark.py /tmp/wildcat-gas-runs13 --ref 63f80d4 --runs 13 --yul adopted
python3 scripts/research/gas-benchmark.py /tmp/wildcat-gas-runs14 --ref 63f80d4 --runs 14 --yul adopted
python3 scripts/research/gas-benchmark.py /tmp/wildcat-gas-default44 --ref 63f80d4 --runs 44 --yul default
python3 scripts/research/gas-benchmark.py /tmp/wildcat-gas-release44 --ref 4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c --runs 44 --yul default --legacy
```

The sweep reads a fixed source snapshot and does not mutate the working tree.
Gas runs use detached worktrees and archived copies of the same scenario fixture.
All benchmark inputs and derived files stay outside normal build/test outputs.
