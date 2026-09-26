# Candidate review: single-storage deployment

Research branch: `experiment/tranching-bytecode-size`.
Baseline: `7b47eec`. No candidates have been adopted into the release branch or
pushed. The repository's normal compiler configuration remains runs 44.

FastLZ is now the assumed candidate for continued verification. The invariant
compilation blocker is resolved by [E13](./E13-invariant-parity.md), and
[E14](./E14-qualification-fixtures.md) passes the broader qualification under
both compiler configurations. [E15](./E15-compression-integrity.md)
integrates artifact verification into the V2.5 scripts and plan executors,
adds independent codec checks, and qualifies real local transactions.
[E16](./E16-hook-artifact-commitment.md) adds on-chain hook artifact commitments
and requalifies deployment. [E17](./E17-lifecycle-invariants.md) expands stateful
repayment/default coverage with an independent timeline model. Full release
qualification remains outstanding.

## Demonstrated bundle

E02's bounded constructor query, E03's bounded periodic query, E08's liability
additions and E11's transition arena are combined with E05's runs-1 optimizer
sequence without FunctionSpecializer (`F`). E04's view path is incorporated into
E11. E09 supplies compressed single-contract initcode storage. E12 makes the
focused test graph compile under those settings without changing the measured
production binaries.

This is the tested bundle, not a proof that every small saving is required.
Removing candidates or changing compiler settings requires rebuilding and
checking that particular combination.

| Market | Live runtime | Runtime headroom | Single storage contract | Storage headroom |
| --- | ---: | ---: | ---: | ---: |
| Standard | 23,791 | 785 | 17,769 | 6,807 |
| Revolving | 24,344 | 232 | 18,248 | 6,328 |

All figures are bytes; both limits are 24,576. Each storage figure includes its
decoder and entire compressed payload. The decoder is part of that same
contract. Factories recover the original creation code and deploy normally.
There is no second storage contract or separately deployed decoder.

The creation code itself is 25,436 / 26,053 bytes. It therefore still fails the
old raw `STOP || initcode` storage limit. Compression solves that limit; E05 and
E11 solve the live-runtime limit. At canonical runs 44, the revolving runtime
is still 485 bytes oversized, even with these source edits.

All three production hooks and the three periodic composition examples fit.
The latter's compressed stores are 17,054 bytes (transfer), 17,396 (borrow),
and 16,965 (APR replacement). Both factories fit comfortably; E09 costs each
101 runtime bytes under the selected compiler settings. E15's pre-constructor
market hash check adds a further 44 / 117 runtime bytes. E16 adds 279 bytes to
each factory for hook artifact commitments. It changes the registration selector
and adds a getter, error, event, and mapping; existing factory slots and template
tuples are preserved. Market and hook ABIs, layouts, and binaries are unchanged.

## Evidence

- 375 focused tests pass at runs 44 before E12's annotation-only change.
- 435 focused tests pass with the final size settings, including the additional
  arithmetic suites. Fuzz cases use 1,000 runs and seed 0x5eed.
- E13 restores all nine invariant properties, which Forge reports as one group.
  E14 passes all 436 reported tests under both compiler configurations. The existing
  2,000 runs, depth 30, 17 actions, six market/hook cells and final unwind remain.
  The campaign completes 60,000 handler calls with zero reverts under both the
  candidate settings and runs 44. All ten measured artifacts are fresh in both
  broader builds and match the independent compiler output exactly.
- E14 fixes the APR test's cached time expectation and adds every measured target
  to the runner's build graph. E13's failed APR-test receipt and stale composition
  artifact comparison remain archived; both follow-ups are resolved.
- 70 arithmetic and bounded-call tests pass at runs 44 after E12.
- Two tests deploy and exercise 12 factory/market/hook combinations with the
  actual code-size limit enforced. They cover both market types, three production
  templates and three periodic composition examples, through scheduled closure.
- All ten final deployment artifacts exactly match the independent compiler
  measurements, including full ABIs and normalized storage layouts.
- E15 passes 457 reported tests under both compiler configurations, including
  all existing invariants with unchanged action counts and budgets. It checks
  the codec against upstream C, rejects corrupted or context-dependent stores,
  and compares raw/compressed initialized runtimes and constructor context.
  Removing the integrity guards makes the intended tests fail.
- Prepared compressed images pass 38 actual local transactions with code-size
  and Osaka transaction gas limits enabled, including all six production
  market/hook combinations. The largest buffered transaction is 9,645,811 gas.
- E16 passes 463 reported tests under both compiler configurations, including
  unchanged invariant budgets and zero handler reverts. All 28 strict-deployment
  tests pass. Four negative controls establish that each factory's registration
  and deployment guards reject wrong bytes. All 38 real local transactions pass
  again, with a largest buffered transaction of 9,645,839 gas. Its 16 tooling
  tests and the existing 42 UI tests pass.
- E17 passes 483 focused tests under both configurations. The original nine
  invariant properties retain their 2,000-run/depth-30 budget; two new six-cell
  lifecycle campaigns each complete the same budget with zero handler reverts.
  Additional seeds and sequences up to 256 actions exercise repayment, default,
  cures, late closure, FIFO batches, and sanctions collection. Nine deliberately
  broken protocol behaviors are detected. Four test-model assumptions were
  corrected with minimized regressions; production source and all ten measured
  target artifacts remain unchanged.

See [E09](./E09-compressed-storage.md), [E11](./E11-transition-arena.md),
[E12](./E12-compiler-qualification.md), [E13](./E13-invariant-parity.md),
[E14](./E14-qualification-fixtures.md), [E15](./E15-compression-integrity.md),
[E16](./E16-hook-artifact-commitment.md), [E17](./E17-lifecycle-invariants.md) and the
[complete catalogue](./catalogue.md).
The working evidence archive is
`/home/kethcode/wildcat/bytecode-research/2026-09-26/`.

## Selection and release work

The meaningful choices are the custom optimizer settings, the manually
allocated transition arena and the compressed deployment format. The smaller
source candidates can be reviewed independently. Every source experiment has
its own signed checkpoint and the rejected alternatives remain documented.

E15 updates `script/common/LibDeployment.sol`, `script/common/DeployScriptBase.sol`,
the V2.5 plan scripts, and CLI/UI execution to create and verify compressed
stores. Images are encoded during preparation; their installation transactions
do not run the compressor. Review this deployment change and its executable
reader trust boundary before release. Raw stores remain supported, so
already-fitting hooks do not have to use compression. The historical Sepolia
fix-1 rotation generator remains a raw-only path.

E16 requires an artifact hash at template registration and checks it again
before every hook deployment. The V2.5 owner script, activation validator, and
template-sync tool use the new interface. Historical factories and the fix-1
ceremony require their pinned tooling. Regenerate release inventories and plans
only after the final source and interface freeze.

E13 resolves the existing invariant suite's compilation failure. The research
runner now includes it in `--scope all` and supports `--scope invariants` for
direct qualification. No invariant assertions, actions or budgets were removed.
This is still scoped behavioral and deployment qualification: the baseline's
pending integration callback updates, full release checks and audit/refreeze
work remain. The existing invariant matrix has no scheduled repayment dates;
E17 preserves it and adds separate repayment and penalty campaigns with
independent observed-funding and boundary bookkeeping. Their setup and final
drain are excluded from reported exploration coverage.

Next are the deployment ceremony update and the required Anvil-fork rehearsal,
with release-build gates alongside them. An additional execution client is not
a selected requirement.

The arena's offsets track three memory struct layouts and must be reviewed if
those structs change. Revolving has only 232 runtime bytes spare. Recheck sizes
after any selected-code or compiler change.

## Reproduce the selected checks

Run from the repository root. Each receipt directory must be new. The runner
temporarily adds a research profile, records the effective settings and source
texts outside the repository, and restores `foundry.toml` afterward.

```sh
size_yul_steps='dhfoDgvulfnTUtnIf[xa[r]EscLMcCTUtTOntnfDIulLculVcul [j]Tpeulxa[rul]xa[r]cLgvifCTUca[r]LSsTOtfDnca[r]Iulc]jmul[jul] VcTOcul jmul'
python3 scripts/research/check.py /tmp/wildcat-size-behavior --scope all --runs 1 --yul-steps "$size_yul_steps"
python3 scripts/research/check.py /tmp/wildcat-size-deployment --scope deployment --runs 1 --yul-steps "$size_yul_steps" --code-size-limit 24576
node scripts/research/compression-rpc.js /tmp/wildcat-size-transactions
```

The ordinary raw-storage size gates are intentionally separate and unchanged.
Use the strict deployment test to assess the compressed format.
