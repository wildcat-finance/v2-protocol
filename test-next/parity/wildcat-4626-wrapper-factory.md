# Wildcat 4626 wrapper factory parity

Status: complete.

## Family boundary

The legacy factory suite has 16 entries and eight dedicated support artifacts. Nine composed
replacement properties exercise the production `Wildcat4626WrapperFactory` and deployed wrapper
while keeping routing probes and hostile return data in small reusable mocks.

| Behavior slice                                                    | Legacy entries | Replacement properties |
| ----------------------------------------------------------------- | -------------: | ---------------------: |
| V1 factory constructor validation                                 |              1 |                      1 |
| Floor-rounding probe, malformed targets, and return-data bounding |              1 |                      1 |
| Legacy creation, discovery, and duplicate failure                 |              2 |                      1 |
| Fresh-chain behavior without a V1 factory                         |              1 |                      1 |
| Declared-generation isolation and unsupported rounding            |              2 |                      1 |
| Floor wrapper deployment, event, registration, and duplication    |              3 |                      1 |
| Zero and unregistered market rejection                            |              2 |                      1 |
| Transfer-policy capability and disabled-market validation         |              3 |                      1 |
| Wrapper capacity when recipient-policy reads fail                 |              1 |                      1 |
| **Total**                                                         |         **16** |                  **9** |

Generation routing stays explicit. Undeclared markets create and resolve through the configured V1
factory, while any declared rounding is isolated from that registry. A floor market paired with a
wrong V1 record resolves nothing until the current factory creates its canonical wrapper, and a
future declared rounding is rejected rather than silently sent to V1.

The factory proves both transfer-policy methods before deploying a wrapper. Missing or partial
interfaces fail with the exact unsupported-policy error, universally disabled markets fail with the
market-specific error, and recipient-policy failures after deployment close `maxDeposit` and
`maxMint` without breaking those views. The replacement strengthens constructor coverage with a
short-returning V1 target and distinguishes an ordinary recipient denial from a reverting policy.

## Coverage and canonical result

The legacy fixed-seed oracle passes all 16 entries and all nine replacement properties pass with
the same timestamp and fuzz seed. Focused accurate coverage reports 100% lines, statements,
branches, and functions for `Wildcat4626WrapperFactory` (47/47 lines, 61/61 statements, 16/16
branches, and 6/6 functions).

The legacy suite and its dedicated support artifacts total 43,771 bytes of initcode and 43,285 bytes
of runtime bytecode. The replacement suite and reusable wrapper mocks total 18,532 and 18,040 bytes,
reducing initcode by 57.66% and runtime bytecode by 58.32%. This conservatively charges every new
wrapper mock to the factory even though later wrapper slices will reuse them.

The full replacement checkpoint is 588 tests across 37 suites with zero inherited entries,
780,438 bytes of test-side initcode, and 770,735 bytes of runtime bytecode. A forced canonical
via-IR compile-to-green takes 2m08.75s, including 125.56s in solc, with a 3,284,512 KiB RSS peak;
execution takes 1.88s.
