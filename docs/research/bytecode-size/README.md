# V2.5 bytecode size research

Experimental branch: `experiment/tranching-bytecode-size`.
Baseline: `7b47eecb3832b74a37416d88e16a67bb8e7b060a`.

The user authorized a research loop: state a hypothesis, implement it, measure
and test it, record the result, make a signed kethcode commit, and repeat.
Candidates will be selected after the catalogue is reviewed. The initial size
pass excluded gas; E22 adds the subsequently requested gas qualification and
runs sweep. Nothing is pushed automatically.

The parent branch assumes FastLZ, subject to further verification. The user
subsequently requested [E23's two-contract comparison](./E23-split-storage-comparison.md)
on `codex/split-initcode-comparison`; that experiment is an explicit exception
to the original single-store constraint and does not select a release format.
[E13](./E13-invariant-parity.md) restores the existing invariant suite, and
[E14](./E14-qualification-fixtures.md) passes the broader qualification under
both compiler configurations. [E15](./E15-compression-integrity.md) adds artifact
attestation, prepared deployment images, independent codec checks, and real
transaction qualification. [E16](./E16-hook-artifact-commitment.md) adds permanent
on-chain hook creation-code commitments and checks them before deployment.
Those checkpoints qualified the candidate; E20 below adopts its compiler
settings for normal repository builds and tests.

[E17](./E17-lifecycle-invariants.md) adds independently checked repayment,
default, and automatic-closure campaigns while retaining the original
invariants. All 483 focused tests pass under both compiler configurations;
longer sequences and deliberate faults qualify the new coverage.

[E18](./E18-review-corrections.md) addresses the external review: automatic
closure retains surplus for borrower recovery through `rescueTokens`, fee
pushes skip closed markets, and a fuzz test pins the transition allocator's
layout. Recovery reserves all lender claims and protocol fees, and a rejected
borrower transfer cannot block lender actions.
All 497 focused tests pass under both configurations, with 425,536 invariant
calls and zero handler reverts across the full and deeper campaigns. Real-limit
deployment checks and all 38 local transactions pass with the new artifacts.

[E19](./E19-integration-qualification.md) updates the remaining integration
expectations for withdrawal collection and compressed artifact storage. It
adds a complete test-tree selection alongside the earlier focused research
selection, including every artifact and deployment-size gate.
All 852 tests pass under the candidate settings. Runs 44 passes 849 and fails
only the three checks for the known revolving runtime overage. Both full runs
retain their invariant budgets, with 360,000 calls and zero handler reverts;
all ten measured artifacts remain unchanged from E18.

[E20](./E20-compiler-adoption.md) adopts runs `1` and the pinned Yul sequence
without FunctionSpecializer in the default compiler profile. The `deploy`
profile inherits the same settings. Ordinary build and test qualification is
recorded there: all 852 tests pass under default, fixed-seed, and deployment
settings, with 540,000 invariant calls and zero reverts. The strict deployment
matrix and production size report pass without changing production source.

[E21](./E21-lens-feature-surfaces.md) updates the full/live/aggregated lens
surfaces for repayment, recorded default, liquidity and surplus, wrapper
registration, periodic proposals, and template commitments. It also preserves
legacy constraint reads and aligns batch collectibility with automatic closure.
The return ABI changes; market/factory/hook source and binaries are unchanged.

[E22](./E22-gas-and-runs-sweep.md) measures every runs value from 1 through 44
with the adopted Yul sequence: both market runtimes fit at 1–14, while revolving
fails at 15–44. Six gas builds pass 56 matched scenarios, including the release
baseline; all comparable accounting fingerprints match. Runs 13 saves 78–339
gas per common call at a cost of 24 market runtime bytes. The user confirmed
retaining runs 1 for its headroom; production configuration is unchanged.

[E23](./E23-split-storage-comparison.md) compares FastLZ with two immutable
storage contracts through unchanged factories. Split pays back its larger
installation cost on the first market and saves 1.996 / 2.066 million gas per
standard / revolving deployment. Both routes produce identical deployed
markets. The full suite passes 880 tests, the strict deployment matrices pass,
and 114 real local transactions qualify the comparison. Raw storage remains
appropriate for the currently fitting hooks.

Next: review the storage choice, integrate the selected deployment format, and
rehearse the actual plan on an Anvil fork. Reproducible release-build gates,
inventory, freeze, and audit delta accompany that work; the selected compiler
settings are already applied.

## Objective and constraints

The original E00–E22 constraints below remain the basis of those experiments.
E23 separately permits two storage contracts, at the user's explicit request.

Make both market models and the supported hook/composition targets deployable
while preserving their behavior. Runtime must fit 24,576 bytes. Each market or
template must use one storage contract whose runtime also fits 24,576 bytes.
For the existing raw format, that means creation code plus its leading STOP.
A compressed format must fit its reader and entire payload in that same contract;
the decoded creation code must also satisfy the 49,152-byte creation limit.
**Split initcode storage is excluded by the user.** This research
must not work around the limit by dividing a market/template across storage
contracts. Do not remove features or weaken tests to manufacture a size win.
Yul, inline assembly and compiler experiments are explicitly in scope, subject
to that same single-storage constraint and behavioral verification.

Keep Solidity 0.8.25, Cancun, viaIR and metadata settings fixed. Compiler run
counts and optimizer details were experimental through E19; E20 applies the
qualified settings to the repository configuration. A compiler-only measurement
is not runtime qualification.

The baseline had 324 passing focused behavior tests and two failing size
gates. E19 resolves the intentional integration callback updates. Final release
configuration, deployment-ceremony, and audit qualification remain outstanding;
research test results do not replace those steps.

## Baseline byte budget

| Target                           | Runtime | Creation | Single-storage overage |
| -------------------------------- | ------: | -------: | ---------------------: |
| Standard market                  |  24,773 |   26,516 |                  1,941 |
| Revolving market                 |  25,350 |   27,167 |                  2,592 |
| Open hook                        |  16,349 |   19,075 |                      0 |
| Fixed hook                       |  17,788 |   20,515 |                      0 |
| Periodic hook                    |  21,059 |   23,786 |                      0 |
| Periodic transfer example        |  21,879 |   24,606 |                     31 |
| Periodic borrow example          |  22,344 |   25,071 |                    496 |
| Periodic APR-replacement example |  21,598 |   24,355 |                      0 |

The production factories fit. Market runtimes separately exceed EIP-170 by
197 and 774 bytes. Creation-code storage is the tighter constraint.

## Research protocol

Each numbered experiment records its source parent, hypothesis, patch, compiler
settings, measured target sizes, relevant tests, ABI/storage effects, decision
and dependencies. Successful source experiments may accumulate on this branch;
the catalogue distinguishes incremental savings from the original baseline.
A successful experiment is a candidate for selection, not release approval.

Rejected source experiments are restored before the next iteration. Their
patches and results are committed in this research directory so they remain
reviewable without leaving broken code as the next experiment's input. Compiler
variants are recorded as settings and results. One experiment record per signed
checkpoint; dependent combinations are tested explicitly.

Use the same target graph and exact compiler for comparisons. The measurement
runner must reproduce the existing Forge artifacts before its results are
trusted. Track creation and runtime separately, including storage STOP bytes.
Match complete public ABIs and normalized storage layouts. Flag any deliberate
interface or deployment-format change instead of calling it a local reduction.

Focused behavior tests use the existing larger allowance for oversized test
harnesses. Keep artifact-size tests separate. A final deployable candidate also
needs real deployments with the production limits enforced; a relaxed test
allowance alone is not deployment evidence.

## Initial hypotheses

1. **Compiler size bias.** The old run-count selection balanced gas and size.
   Measure low run counts and optimizer/inlining variants on the current source.
2. **Bounded call encoders.** Revisit useful unadopted gas-sweep candidates,
   starting with the market constructor's borrower-registration query and the
   periodic hook's fixed-return queries. Preserve malformed-return and revert
   semantics.
3. **Generated-code duplication.** Inspect dispatch, memory initialization and
   internal specialization in optimized IR; evaluate shared bodies where this
   demonstrably reduces generated code.
4. **Lifecycle representation.** Try more compact in-memory transition/result
   representations or replay structure while preserving chronology, inclusive
   deadlines, rounding, checkpointing and view/write agreement.
5. **Larger extraction candidates.** If local changes cannot meet the budget,
   measure a separately deployed immutable calculation helper or other explicit
   architecture changes. Record trust, ABI and deployment consequences. Split
   initcode storage remains excluded.

The list can change based on measurements. Do not continue a weak hypothesis
just to complete a preset list.

## Previous work reviewed

- `origin/experiment/gas-optimization-sweep` at `f0260b8`: its
  `docs/gas-optimization-sweep.md` distinguishes source candidates from rejected
  ideas and architectural upper bounds. The G-41 borrower-registration reader
  saved 99/125 creation bytes on its older source; that is a lead, not a current
  result. G-43 and shared fixed-return readers are also relevant.
- The user-supplied August optimizer checkpoint and TSV show a non-monotonic
  run-count curve. Runs 44 was selected partly for gas. Those figures do not
  predict the new lifecycle code's optimum.
- The preceding four local checkpoints rejected larger allocation rewrites that
  triggered inlining and grew bytecode. Their evidence remains outside the
  repository at `/home/kethcode/wildcat/tranching-size-review/2026-09-26/`.

Keep the supplied reference documents and voice guide uncommitted. Large
compiler output and logs are under
`/home/kethcode/wildcat/bytecode-research/2026-09-26/`; concise results and patches
belong in this branch's [catalogue](./catalogue.md). These are working research
records, to be exported and removed from the final release documentation.

The [candidate review](./candidate-review.md) summarizes the resulting bundle
which passes real-limit deployments, along with its remaining adoption work.
