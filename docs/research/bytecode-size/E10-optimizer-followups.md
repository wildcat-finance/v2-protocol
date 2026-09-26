# E10: pass ordering and opcode optimizer follow-ups

These measurements reuse archived source inputs, so later working-tree edits
cannot contaminate the comparisons. The runner now accepts `--source-receipt`.

Hypothesis: late function combination, another optimization pass, delayed
inlining, or opcode-level options might close the remaining runtime gap.
All variants keep runs 1 and remove FunctionSpecializer.

| Variant                                         | Source        | Standard creation delta | Revolving creation delta |
| ----------------------------------------------- | ------------- | ----------------------: | -----------------------: |
| Append `vul`                                    | E04 + E05     |                       0 |                        0 |
| Repeat the main Yul sequence                    | E04 + E05     |                      +9 |                       +9 |
| Delay FullInliner until after the main sequence | E04 + E05     |                    +516 |                     +535 |
| Explicit `orderLiterals = true`                 | E08 additions |                       0 |                        0 |
| Disable opcode common-subexpression elimination | E08 additions |                    +342 |                     +340 |
| Disable opcode constant optimization            | E08 additions |                  +4,329 |                   +4,389 |

Positive deltas mean larger. All compile with unchanged complete ABIs and
normalized layouts. Repeating the sequence saves a few bytes on some hooks,
but makes the limiting markets larger. No variant merits runtime qualification
for the present objective. Decision: reject these alternatives; retain E05's
simpler settings candidate. [Full settings and sizes](./results/e10.json).

E09 compression work ran independently while these archived-input compiler
experiments completed. Experiment numbers describe hypotheses, not timing of
compiler processes or commit order.
