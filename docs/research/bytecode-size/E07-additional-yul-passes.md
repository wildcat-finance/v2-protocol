# E07: additional Yul pass removals

Source parent: `ff6a6e1`; production source remains E02 + E03 + E04.
Hypothesis: with runs 1/no F, further pass removal may avoid expanded expressions
or unnecessary branch rewrites.

| Additional removal            | Standard creation | Revolving creation | Result vs E05                |
| ----------------------------- | ----------------: | -----------------: | ---------------------------- |
| None                          |            25,808 |             26,429 | Reference                    |
| ExpressionInliner (`e`)       |            26,249 |             26,806 | Worse                        |
| ConditionalSimplifier (`C`)   |            25,808 |             26,429 | Markets unchanged; hooks +12 |
| ConditionalUnsimplifier (`U`) |            25,849 |             26,470 | Worse                        |

All ten contracts compile with unchanged complete ABIs and normalized storage
layouts. [Exact settings and sizes](./results/e07.json). Runtime qualification
is unnecessary for these rejected settings; no source or production settings
changed. Decision: reject all three and keep the E05 compiler candidate.
