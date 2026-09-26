# V2.5 bytecode size research

Experimental branch: `experiment/tranching-bytecode-size`.
Baseline: `7b47eecb3832b74a37416d88e16a67bb8e7b060a`.

The user authorized a research loop: state a hypothesis, implement it, measure
and test it, record the result, make a signed kethcode commit, and repeat.
Candidates will be selected after the catalogue is reviewed. Gas is not a
selection criterion in this pass. Nothing is pushed automatically.

## Objective and constraints

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

Keep Solidity 0.8.25, Cancun, viaIR and metadata settings fixed initially.
Compiler run counts and optimizer details may be experimented with. The main
release configuration stays at 44 until a selected experiment explicitly
changes it. A compiler-only measurement is not runtime qualification.

The baseline has 324 passing focused behavior tests and two failing size
gates. Full release qualification and earlier intentional integration callback
updates remain outstanding. This work does not silently redefine that scope.

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
