# E01: compiler size bias

Production source is unchanged from E00. Source parent: `9cc8b18` (documentation
and runner only). All measurements use solc 0.8.25, viaIR, Cancun, no metadata.

Hypothesis: reducing optimizer runs or preventing duplicated specialized bodies
can reduce size without changing source. Measure creation code first, because
it includes the runtime and must fit the single storage contract.

| Settings                                 | Standard creation | Revolving creation | Periodic creation | Periodic borrow example |
| ---------------------------------------- | ----------------: | -----------------: | ----------------: | ----------------------: |
| Baseline: runs 44                        |            26,516 |             27,167 |            23,786 |                  25,071 |
| Runs 1                                   |            26,281 |             26,919 |            23,775 |                  25,060 |
| Runs 10                                  |            26,281 |             26,919 |            23,746 |                  25,031 |
| Opcode inliner disabled, runs 44         |            26,614 |             27,240 |            24,616 |                  25,939 |
| Yul FullInliner removed, runs 44         |            28,610 |             29,354 |            25,010 |                  26,669 |
| Yul FunctionSpecializer removed, runs 44 |            26,142 |             26,773 |            22,634 |                  23,949 |

The default Yul sequence was extracted from the pinned compiler executable.
Removing `i` disables FullInliner; removing `F` disables FunctionSpecializer.
The cleanup sequence remains the compiler default. These step names and the
cleanup behavior are documented in the [Solidity 0.8.25 optimizer reference](https://docs.soliditylang.org/en/v0.8.25/internals/optimizer.html).
Exact settings and all ten target sizes are in [the receipt summary](./results/e01.json).
Complete inputs and outputs are in the external `e01-*` directories.

Decision: reject both inliner removals for size. Keep low runs and especially
removal of FunctionSpecializer as compiler candidates. The latter saves 374/394
market creation bytes and 1,152 periodic-hook bytes, putting all measured hook
compositions under the storage limit. Both markets still exceed it.

Validation: every variant compiled all ten targets, preserving complete ABIs
and normalized storage layouts. **Runtime qualification is pending** for any
compiler candidate selected later. No production settings or source were
changed, and no behavioral tests are claimed for these alternate binaries.
Source experiments continue at the canonical runs 44/default optimizer to keep
their individual savings distinguishable.
