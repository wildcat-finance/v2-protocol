# E04: bypass the unused view result tuple

Source parent: `3e77136`. Canonical runs 44/default optimizer.

Hypothesis: state-only views need the first result of `_calculateTransition`,
not `_calculateCurrentState`'s additional batch results. Routing them directly
to the shared transition can avoid wrapper allocations and function-pointer
routing without changing the accounting body.

`_calculateCurrentStatePointers` now reads the existing MarketState pointer from
the transition result. It keeps the runtime flag that prevents constant
specialization. Views needing a batch still use the existing tuple wrapper.

Result: **37 runtime and creation bytes saved on each market**. Complete ABIs
and normalized storage layouts match. Other targets are unchanged.
[Sizes](./results/e04.json).

Validation: **137 tests passed**, including view/accrual consistency, expiry,
repayment boundaries, closure, donations, revolving accounting and fixed-call
regressions. Existing behavioral assertions were not changed. Evidence is in
external `e04/` and `e04-behavior/`.

Decision: retain as a canonical-settings candidate. It is independently
selectable from E02 and E03. **Its saving does not add to E05:** under runs 1
with FunctionSpecializer removed, this source change instead adds two bytes.
The catalogue measures combinations instead of adding unrelated size deltas.
