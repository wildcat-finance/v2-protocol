# E03: bounded periodic APR query

Source parent: `04c5c6a`. Settings: canonical runs 44, default Yul optimizer.

Hypothesis: the periodic proposal path only needs a single return word, so it
can avoid the general external-call encoder and decoder, as suggested by G-43
in the older gas sweep.

Added `LibFixedCall.readWord` and used it for `IMarketApr.annualInterestBips`.
The actual interface returns **uint256**, not uint16. The first draft narrowed
that return and was rejected during review; its test build was stopped. The
retained implementation preserves the full word and tests against the actual
interface. It rejects short responses and empty-code targets, accepts trailing
data, and bubbles arbitrary revert bytes.

Result: **44 creation and runtime bytes saved** on PeriodicTermHooks and each
of its three measured compositions. Other targets are unchanged. Full ABIs and
normalized storage layouts are unchanged. [Sizes](./results/e03.json).

Validation: **207 tests passed** across ten hook/factory/library suites, with
1,000 fixed-seed fuzz cases. Five new differential word-reader tests include
valid values above uint16 and every short return length; the existing proposal,
APR-composition and administrator checks also pass. An intermediate test-source
typo failed compilation and was corrected; only `e03-word-behavior-fixed/`
counts as the passing run. Measured artifacts are in external `e03-word/`.

Decision: retain. It shares the helper file introduced by E02, but can be
selected independently by carrying only `readWord` and the periodic call site.
At runs 44 the transfer composition now fits with 13 bytes spare; the borrow
composition remains 452 bytes over. No claim of comfortable extension headroom.
