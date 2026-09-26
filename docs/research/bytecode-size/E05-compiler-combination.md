# E05: combined size settings

Source: E02 + E03 initially; E04 added for the final combination at `fe2adad`.
No production compiler configuration change. These are selectable settings.

Hypothesis: combine runs 1 with FunctionSpecializer removed, then test whether
also removing LiteralRematerialiser (`T`) or UnusedFunctionParameterPruner (`p`)
helps. Every other setting stays pinned.

| Variant, on E02 + E03          | Standard creation/runtime | Revolving creation/runtime |
| ------------------------------ | ------------------------: | -------------------------: |
| Runs 1, remove F               |           25,806 / 24,119 |            26,427 / 24,676 |
| Runs 1, remove F and T         |           25,994 / 24,319 |            26,615 / 24,876 |
| Runs 1, remove F and p         |           25,811 / 24,124 |            26,432 / 24,681 |
| Runs 1, remove F, **plus E04** |           25,808 / 24,121 |            26,429 / 24,678 |

Decision: keep runs 1/no F as the strongest compiler candidate so far. Reject
both additional removals for size. E04 adds two bytes under these settings,
though it saves 37 at canonical runs 44. All measured hook/composition targets
fit raw single-storage payloads with the winning settings.

The combined source is 708/738 creation bytes smaller than E00, but the market
storage deficits are still 1,233/1,854 bytes. Revolving runtime is 102 bytes over.
Compiler tuning alone has not made the markets deployable.

All ten ABIs and normalized storage layouts are unchanged. Alternate-runtime
behavior qualification is deferred to the selected combined candidate; source
qualification at runs 44 does not qualify different compiler settings.
[Exact optimizer sequences and all sizes](./results/e05.json). Full external
receipts retain source texts and compiler hashes, so the initial and E04
combinations can be reproduced independently.

Follow-up: E11 brings both live runtimes under the limit, and E09's compressed
format fits their creation code into one store each. [E12](./E12-compiler-qualification.md)
records 435 passing focused tests and 12 real-limit deployments on that final
bundle, as well as the remaining full-invariant-suite compiler limitation.
