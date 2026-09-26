# Candidate review: single-storage deployment

Research branch: `experiment/tranching-bytecode-size`.
Baseline: `7b47eec`. No candidates have been adopted into the release branch or
pushed. The repository's normal compiler configuration remains runs 44.

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
101 runtime bytes under the selected compiler settings. Public ABIs and storage
layouts remain unchanged across the measured contracts.

## Evidence

- 375 focused tests pass at runs 44 before E12's annotation-only change.
- 435 focused tests pass with the final size settings, including the additional
  arithmetic suites. Fuzz cases use 1,000 runs and seed 0x5eed.
- 70 arithmetic and bounded-call tests pass at runs 44 after E12.
- Two tests deploy and exercise 12 factory/market/hook combinations with the
  actual code-size limit enforced. They cover both market types, three production
  templates and three periodic composition examples, through scheduled closure.
- All ten final deployment artifacts exactly match the independent compiler
  measurements, including full ABIs and normalized storage layouts.

See [E09](./E09-compressed-storage.md), [E11](./E11-transition-arena.md),
[E12](./E12-compiler-qualification.md) and the [complete catalogue](./catalogue.md).
The working evidence archive is
`/home/kethcode/wildcat/bytecode-research/2026-09-26/`.

## Selection and release work

The meaningful choices are the custom optimizer settings, the manually
allocated transition arena and the compressed deployment format. The smaller
source candidates can be reviewed independently. Every source experiment has
its own signed checkpoint and the rejected alternatives remain documented.

If E09 is selected, update `script/common/LibDeployment.sol` and
`script/common/DeployScriptBase.sol` to create and verify compressed stores;
their release paths currently still use raw storage. Review the executable
storage reader and codec as part of that deployment change. Raw stores remain
supported, so already-fitting hooks do not have to use compression.

If E05 is selected, the full invariant suite still needs compiler work:
`MarketMatrixHandler.sol` fails under no F. It was outside the focused test
scope before this research; the corrected focused runner now also excludes its
unreachable helper source. No selected tests were weakened to get the passing
results. This is a scoped behavioral and deployment qualification, not full
release qualification. The baseline's pending integration callback updates,
full release checks and audit/refreeze work also remain.

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
```

The ordinary raw-storage size gates are intentionally separate and unchanged.
Use the strict deployment test to assess the compressed format.
