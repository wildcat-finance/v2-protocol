# Bytecode experiment catalogue

See the [research protocol](./README.md) for constraints and baseline sizes.
All listed commits belong to the experimental branch. Split initcode storage
is excluded. No experiment has been adopted into the release branch.

| Experiment | Hypothesis                                                            | Source parent            | Result                                           | Decision / dependencies                                             |
| ---------- | --------------------------------------------------------------------- | ------------------------ | ------------------------------------------------ | ------------------------------------------------------------------- |
| E00        | Reproduce the exact compiler baseline with the research runner        | `7b47eec`                | Exact match on all 10 targets                    | Runner qualified                                                    |
| E01        | [Compiler size bias](./E01-compiler.md)                               | `9cc8b18`                | Best variant saves 374/394 market creation bytes | Keep no-specializer and low runs as unqualified compiler candidates |
| E02        | [Bounded constructor query](./E02-constructor-call.md)                | `2389da5`                | Saves 121/117 creation bytes; 132 tests pass     | Retained; independent of compiler variants                          |
| E03        | [Bounded periodic APR query](./E03-periodic-call.md)                  | `04c5c6a`                | Saves 44 periodic bytes; 207 tests pass          | Retained; shares E02 helper file                                    |
| E04        | [Direct state-only view](./E04-state-view.md)                         | `3e77136`                | Saves 37 bytes per market; 137 tests pass        | Retained at runs 44; adds 2 bytes with E05                          |
| E05        | [Combined compiler settings](./E05-compiler-combination.md)           | `fe2adad`                | Low runs/no F wins; raw storage still over       | Candidate settings; runtime qualification pending                   |
| E06        | [Remove runtime-obscured constants](./E06-literal-arguments.md)       | `28ee38c`                | Grows 2,395 bytes at runs 44; 48 with E05        | Rejected; patch archived, source restored                           |
| E07        | [Additional Yul pass removals](./E07-additional-yul-passes.md)        | `ff6a6e1`                | All three unchanged or larger                    | Rejected; settings and results archived                             |
| E08        | [Bounded liability additions](./E08-bounded-additions.md)             | `16b3d4d`                | Saves 11/15 bytes at runs 44; 154 tests pass     | Retain narrow draft; broader draft rejected                         |
| E10        | [Optimizer ordering and opcode options](./E10-optimizer-followups.md) | Archived E04/E08 sources | Six alternatives unchanged or larger on markets  | Rejected; reproducible archived-input runs                          |
