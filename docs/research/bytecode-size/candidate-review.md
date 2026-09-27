# Candidate review: single-storage deployment

Research branch: `experiment/tranching-bytecode-size`.
Baseline: `7b47eec`. Work remains on the research branch. E20 applies the
qualified runs-1 compiler configuration to normal repository builds and tests.

This document describes the compressed candidate. The later user-authorized
[E23 comparison](./E23-split-storage-comparison.md) lives on
`codex/split-initcode-comparison` and compares it with exactly two storage
contracts. Split costs more to install but saves about two million gas per
market, recovering the premium on the first deployment. The factory still
receives one address and verifies the same creation-code hash. Both formats
remain available for review; this branch has not switched the release ceremony.

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

[E18](./E18-review-corrections.md) addresses the external review's closure,
factory fee-update, and allocator-test findings. Automatic closure retains
surplus; the operational borrower recovers it separately using `rescueTokens`.
This preserves all lender and protocol-fee liabilities and prevents a rejected
borrower transfer from blocking lender actions.

[E19](./E19-integration-qualification.md) aligns the integration expectations
with hook-independent collection and the selected artifact storage format,
then expands qualification to the entire Solidity test tree.

[E20](./E20-compiler-adoption.md) adopts the tested compiler settings in
`foundry.toml`, including the exact Yul optimizer sequence. The default and
deployment profiles inherit the same configuration.

[E21](./E21-lens-feature-surfaces.md) exposes the new features through the
lenses, adds compatibility and boundary tests, and documents the changed return
ABIs. Market, factory, and hook source and bytecode remain unchanged.

[E22](./E22-gas-and-runs-sweep.md) completes the hot-path gas comparison and
the runs-1-through-44 size sweep. Both market runtimes fit at 1–14 with the
adopted Yul sequence; revolving fails at 15–44. All 56 benchmark scenarios pass
with matching comparable accounting. The user confirmed retaining runs 1;
production compiler settings and source are unchanged.

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
| Standard | 23,778 | 798 | 17,759 | 6,817 |
| Revolving | 24,334 | 242 | 18,254 | 6,322 |

All figures are bytes; both limits are 24,576. Each storage figure includes its
decoder and entire compressed payload. The decoder is part of that same
contract. Factories recover the original creation code and deploy normally.
There is no second storage contract or separately deployed decoder.

The creation code itself is 25,416 / 26,036 bytes. It therefore still fails the
old raw `STOP || initcode` storage limit. Compression solves that limit; E05 and
E11 solve the live-runtime limit. At the former runs-44 settings, the revolving runtime
is still 474 bytes oversized, even with these source edits.

All three production hooks and the three periodic composition examples fit.
The latter's compressed stores are 17,054 bytes (transfer), 17,396 (borrow),
and 16,965 (APR replacement). Both factories fit comfortably; E09 costs each
101 runtime bytes under the selected compiler settings. E15's pre-constructor
market hash check adds a further 44 / 117 runtime bytes. E16 adds 279 bytes to
each factory for hook artifact commitments. It changes the registration selector
and adds a getter, error, event, and mapping; existing factory slots and template
tuples are preserved. E16 leaves market and hook ABIs, layouts, and binaries
unchanged. E18 saves 13 / 10 runtime bytes on the markets and adds 64 to each
factory; it preserves all ten measured public ABIs and storage layouts.

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
- E18 reproduces the blocked-withdrawal defect, fixes both closure paths, and
  verifies borrower-only surplus recovery against every liability category.
  All 497 focused tests pass under both configurations; the full and deeper
  campaigns total 425,536 calls with zero handler reverts. Two deliberately
  broken allocators fail the new layout test. All 28 strict-deployment tests
  and 38 local transactions pass with the new artifacts. An artifact-path
  collision between two test tokens was corrected in the qualification script;
  the failed receipt remains archived. No public ABI or storage layout changes.
- E19 runs every test file and every size gate: all 852 tests pass under the
  candidate settings. Runs 44 passes 849 and fails only the three revolving
  runtime-size checks. Both full runs retain the invariant budgets and total
  360,000 calls with zero handler reverts. All 28 actual-limit deployment tests
  pass, and all ten production/composition artifacts are unchanged from E18.
  Withdrawal tests now prove collection ignores a live hook veto while
  preserving batch accounting and sanctions escrow routing. Artifact gates
  verify the selected raw/compressed image without relaxing their size bounds.
- E20 adopts the candidate compiler settings as the repository default. All
  852 tests pass in each of the default, fixed-seed, and deployment-profile runs,
  with 540,000 invariant calls and zero handler reverts. The ordinary build,
  production size report, and strict deployment matrix pass. All ten default
  and deployment artifacts match the previously qualified bytecode and ABIs.
  Two redundant inline research-profile annotations are removed; their strict
  revert behavior remains inherited from the default annotation and is checked
  with independent controls.
- E21 passes 869 tests in each required profile, including 17 new lens tests,
  with 540,000 invariant calls and zero handler reverts. Strict deployments
  cover the four lenses and both market families alongside the existing
  twelve-combination market/hook matrix. The largest lens runtime is 21,997
  bytes; every production artifact fits. Clean lens builds match across
  profiles, and the ten earlier target binaries and ABIs remain unchanged.
  Return tuples change and need new consumer decoders. Repository-wide
  formatting still flags 26 unchanged files; every changed file passes its
  formatting and lint checks.

See [E09](./E09-compressed-storage.md), [E11](./E11-transition-arena.md),
[E12](./E12-compiler-qualification.md), [E13](./E13-invariant-parity.md),
[E14](./E14-qualification-fixtures.md), [E15](./E15-compression-integrity.md),
[E16](./E16-hook-artifact-commitment.md), [E17](./E17-lifecycle-invariants.md),
[E18](./E18-review-corrections.md), [E19](./E19-integration-qualification.md),
[E20](./E20-compiler-adoption.md), [E21](./E21-lens-feature-surfaces.md), and the
[complete catalogue](./catalogue.md).
The working evidence archive is
`/home/kethcode/wildcat/bytecode-research/2026-09-26/`, with E18–E21 receipts under
`/home/kethcode/wildcat/bytecode-research/2026-09-27/`.

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
E19 resolves the baseline's pending integration callback updates and runs the
complete test tree. E20 applies the tested compiler configuration; final frozen
release-artifact checks and audit/refreeze work remain. The original invariant
matrix has no scheduled repayment dates;
E17 preserves it and adds separate repayment and penalty campaigns with
independent observed-funding and boundary bookkeeping. Their setup and final
drain are excluded from reported exploration coverage.

E22 measures market and hook hot-path gas using current source under both
compiler configurations, three higher-runs candidates, and the release/v2.5
baseline. Adopted runs 1 adds 0.60–2.16% over current source at the former compiler
settings in the common samples. The combined source changes cost more than the
compiler change; they are not attributed solely to lifecycle storage. Equivalent
scenarios, compiler/EVM settings, and call isolation are recorded. Raised test
limits for oversized controls do not qualify them for deployment.

Next review E23's storage comparison, then complete the selected deployment
ceremony update and required Anvil-fork rehearsal,
with release-build gates alongside them, followed by the final inventory,
freeze, and audit review delta. An additional execution client is not a selected
requirement.

E23 measures storage installation and market creation gas for both formats,
with raw controls for the fitting composition hooks. Market creation code is
too large for a single raw store; the uncompressed market control uses the
two-contract format. E22 separately covers method execution and excludes
setup/deployment costs. Recheck the finalized ceremony's transaction budgets.

Downstream work includes regenerating the complete lens bindings, including
common V2.0/V2.1 market reads; indexing `MarketRepaymentTerms`,
`RepaymentDateReached`, `DefaultRecorded`, and
`HooksTemplateInitCodeHashRecorded`; and updating callers of `addHooksTemplate`
for its initcode-hash argument. Use the ABI for each deployment generation.
Before release, export the updated spec and evidence, then remove the working
`docs/specs/` and `docs/research/` documents from the release tree.

E18 compares the arena's zeroing and nested fields with independently allocated
Solidity structs, including negative controls for aliases and dirty memory.
Its offsets still require review when those structs change. Revolving has only
242 runtime bytes spare. Recheck sizes after any selected-code or compiler
change.

## External second pass: 2026-09-27

The reviewer examined the nine commits after `f56c30e` through `04cfbd0`, read
their tests and research records, and measured artifacts. They did not run the
test suite. They confirmed the E18 closure/surplus, fee-update, and allocator
fixes, the E20 compiler adoption, and the E21 lens implementation. Their market
runtime and raw creation-code measurements match the figures above; the largest
lens is 21,997 bytes, with 2,579 bytes spare. Compression remains necessary for
single-contract initcode storage.

The optional surplus-recovery event, avoiding zero-value sweep transfers, and
changing the pre-existing manual-close surplus push are not selected changes.
The reviewer's approximate event-size estimate has not been measured. The
remaining required work is the release qualification and downstream integration
listed above, not a newly identified Solidity fix.

## Reproduce the selected checks

Run from the repository root. Each receipt directory must be new. The runner
temporarily adds a research profile, records the effective settings and source
texts outside the repository, and restores `foundry.toml` afterward.

```sh
size_yul_steps='dhfoDgvulfnTUtnIf[xa[r]EscLMcCTUtTOntnfDIulLculVcul [j]Tpeulxa[rul]xa[r]cLgvifCTUca[r]LSsTOtfDnca[r]Iulc]jmul[jul] VcTOcul jmul'
python3 scripts/research/check.py /tmp/wildcat-size-full --scope full --runs 1 --yul-steps "$size_yul_steps"
python3 scripts/research/check.py /tmp/wildcat-size-deployment --scope deployment --runs 1 --yul-steps "$size_yul_steps" --code-size-limit 24576
node scripts/research/compression-rpc.js /tmp/wildcat-size-transactions
```

E19 updates the artifact gates to the selected raw/compressed format without
changing their size bounds. The full selection includes every size test; the
strict deployment command separately enforces the actual EVM code-size limit.
