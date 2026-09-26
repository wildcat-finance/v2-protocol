# E14: correct time simulation and artifact freshness

Source parent: `59ca2c2` (E13).

E13 restores all existing invariants under both compiler configurations. Its
broader runs-44 campaign also exposes a test expectation that caches time, and
an unused composition artifact left over from the preceding compiler profile.
This checkpoint resolves both follow-ups and repeats the broader qualification.

## APR expiry test

Hypothesis: the APR test's direct `block.timestamp` reads are being reused across
`vm.warp`, which changes a value Solidity normally treats as transaction-constant.

The diagnostic trace confirms the sequence:

1. Market A's reduction starts at `StartTimestamp`, expiring two weeks later.
2. Advancing one week and reducing APR again extends that expiry to week three.
3. The test resets time to `StartTimestamp` before starting Market B's reduction.
4. The test still expects week three; the hook correctly emits week two.

The baseline hook suite passes all 197 tests. The changed compiler output exposes
the latent clock-read assumption in the current test. Foundry documents this
case beside `Vm.getBlockTimestamp()` in the vendored `forge-std/src/Vm.sol`.

Use `vm.getBlockTimestamp()` for the four expiry calculations in
`MarketConstraintHooks.t.sol`. The APR inputs, time warps, event expectations,
reserve-ratio checks and stored-expiry assertions remain. No production code
changes, and no expected value is relaxed to match incorrect behavior.

## Measured artifacts

Hypothesis: a focused build can leave an unused target's artifact unchanged when
switching compiler profiles, making a later file comparison read the wrong build.

Both E13 broader graphs exclude `test/mocks/BorrowFeatureHooks.sol`. The strict
deployment graph includes it. After switching from the strict no-F build to the
broader runs-44 build, `PeriodicBorrowHooks.json` still contains the no-F bytes:
23,890 creation / 21,405 runtime, instead of 25,027 / 22,300 at runs 44. The seven
production artifacts are current and match the native compiler in both runs.

The research runner now makes every target in `bytecode.py` an explicit source
root, alongside the selected tests and production sources. An unused measured
composition still compiles under the current settings. Test selection and the
invariant budget do not change.

## Qualification

Both broader runs pass all 436 reported tests, with zero failures or skips:
canonical runs 44 and the candidate's runs 1/no-F settings. Each includes all
nine invariant properties at the existing 2,000 runs and depth 30, completing
60,000 handler calls with zero reverts. All 17 action counts match the baseline
campaign at seed `0x5eed`; the six cells and final unwind are unchanged.

All ten measured targets are now in each build's source graph. Their artifact
metadata confirms the intended optimizer run count, and their creation/runtime
bytes, full ABIs and normalized storage layouts match the independent native
compiler output exactly. No production source or measured bytecode changes.
The earlier failure and stale-file comparison remain in E13's receipts.

E13's strict deployment evidence still applies to these unchanged candidate
binaries: two tests, 12 factory/market/hook combinations, with the real
24,576-byte limit. That separate campaign was not repeated for this test-only
checkpoint. Formatting, lint and whitespace checks pass, and the normal
compiler configuration remains unchanged. [Concise results](./results/e14.json).

Decision: retain the explicit test-clock reads and measured-target build roots.
The existing invariant suite is restored under both compiler configurations.
FastLZ deployment-tool integration, deeper codec verification and a stateful
repayment-date lifecycle model remain separate work.

External receipts are under
`/home/kethcode/wildcat/bytecode-research/2026-09-26/`:

- `e14-baseline-hooks/`: baseline control;
- `e14-apr-before/`: unchanged failing test with its complete trace;
- `e14-all-default/` and `e14-all-noF/`: corrected qualification, archived
  artifacts and comparisons for both compiler configurations;
- `e14-compare-artifacts.py`: source-graph, metadata and native-output comparison.
