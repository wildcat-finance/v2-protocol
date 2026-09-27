# Bytecode experiment catalogue

See the [research protocol](./README.md) for constraints and baseline sizes.
All listed commits belong to the experimental branch. Split initcode storage
is excluded. No experiment has been adopted into the release branch.

The [candidate review](./candidate-review.md) collects the demonstrated bundle,
its deployment sizes, tests and adoption limits.

| Experiment | Hypothesis                                                            | Source parent            | Result                                           | Decision / dependencies                                             |
| ---------- | --------------------------------------------------------------------- | ------------------------ | ------------------------------------------------ | ------------------------------------------------------------------- |
| E00        | Reproduce the exact compiler baseline with the research runner        | `7b47eec`                | Exact match on all 10 targets                    | Runner qualified                                                    |
| E01        | [Compiler size bias](./E01-compiler.md)                               | `9cc8b18`                | Best variant saves 374/394 market creation bytes | Combined and qualified within E12's stated scope |
| E02        | [Bounded constructor query](./E02-constructor-call.md)                | `2389da5`                | Saves 121/117 creation bytes; 132 tests pass     | Retained; independent of compiler variants                          |
| E03        | [Bounded periodic APR query](./E03-periodic-call.md)                  | `04c5c6a`                | Saves 44 periodic bytes; 207 tests pass          | Retained; shares E02 helper file                                    |
| E04        | [Direct state-only view](./E04-state-view.md)                         | `3e77136`                | Saves 37 bytes per market; 137 tests pass        | Retained at runs 44; adds 2 bytes with E05                          |
| E05        | [Combined compiler settings](./E05-compiler-combination.md)           | `fe2adad`                | Low runs/no F wins; raw storage still over       | 436 reported tests including the restored invariant suite in E13 |
| E06        | [Remove runtime-obscured constants](./E06-literal-arguments.md)       | `28ee38c`                | Grows 2,395 bytes at runs 44; 48 with E05        | Rejected; patch archived, source restored                           |
| E07        | [Additional Yul pass removals](./E07-additional-yul-passes.md)        | `ff6a6e1`                | All three unchanged or larger                    | Rejected; settings and results archived                             |
| E08        | [Bounded liability additions](./E08-bounded-additions.md)             | `16b3d4d`                | Saves 11/15 bytes at runs 44; 154 tests pass     | Retain narrow draft; broader draft rejected                         |
| E09        | [Compressed single storage](./E09-compressed-storage.md)             | E08 source              | Market stores fit at 17,769 / 18,248 bytes with E05 + E11 | Assumed candidate; deeper verification and tooling follow in E15 |
| E10        | [Optimizer ordering and opcode options](./E10-optimizer-followups.md) | Archived E04/E08 sources | Six alternatives unchanged or larger on markets  | Rejected; reproducible archived-input runs                          |
| E11        | [Lifecycle transition arena](./E11-transition-arena.md)               | E08 market source       | Saves 279 creation bytes at 44; 360 with E05; 375 tests pass at 44 | Retain; both runtimes fit with E05, storage fits with E09 |
| E12        | [Compiler qualification](./E12-compiler-qualification.md)              | `a4ca461`               | Ten target binaries unchanged; 435 tests and 12 strict deployments pass | Retain annotations; handler regression diagnosed and resolved in E13 |
| E13        | [Restore invariant parity](./E13-invariant-parity.md)                  | `b2b91a0`               | All nine invariants pass at runs 44 and with E05; ten target binaries unchanged | Retain handler refactor; invariants now included in broader research qualification |
| E14        | [Reliable qualification fixtures](./E14-qualification-fixtures.md)     | `59ca2c2`               | 436 tests pass under both configurations; ten fresh artifacts match each native build | Retain explicit test-clock reads and measured-target build roots |
| E15        | [Compression integrity](./E15-compression-integrity.md)                | `050c0b1`               | 457 tests under both configurations; upstream codec oracle, guard controls, and 38 real local transactions | Retain artifact attestation and prepared images; factory runtime +44 / +117 bytes with E05 |
| E16        | [Hook artifact commitment](./E16-hook-artifact-commitment.md)             | `e649e19`               | 463 tests under both configurations; 28 strict tests, four guard controls, and 38 real local transactions | Retain permanent hash checks at registration and deployment; each factory +279 runtime bytes with E05 |
| E17        | [Lifecycle invariants](./E17-lifecycle-invariants.md)                     | `95e6f0c`               | 483 focused tests under both configurations; independent lifecycle campaigns, longer sequences, and fault controls; ten target artifacts unchanged | Retain expanded coverage and original no-date guarantees; ceremony and Anvil-fork rehearsal follow |
| E18        | [Review corrections](./E18-review-corrections.md)                        | `f56c30e`               | 497 tests per configuration; 425,536 invariant calls with zero reverts; allocator fault controls; 28 strict tests and 38 local transactions | Retain isolated surplus recovery and closed-market fee skips; public ABIs/layouts unchanged; candidate revolving headroom 242 bytes |
