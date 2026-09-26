# E11: allocate the lifecycle transition once

Source parent: `d2c14fe`; market source is E02 + E04 + E08. E09 is a separate
deployment-format candidate and does not change market bytes.

Hypothesis: solc's generated default struct allocation is redundant when
`_calculateTransition` immediately loads state and lifecycle from storage.
Allocate the remaining transition memory once, then fill it in place. Reuse
the function-pointer casting technique already used for MarketState returns.

The allocator reserves and zeroes 0x520 bytes: a ten-word transition header,
an empty three-word batch, four record pointers and four six-word accrual
records. The state and lifecycle pointers are assigned by `_calculateTransition`
before they are read. The calculator accepts that transition as an argument and
returns no value; all three callers use the same allocation path.

Zeroing includes flags, counters and unused records. Boundary replay, event
order, deadlines, rounding, checkpointing and closure logic are unchanged.
The arena offsets are coupled to LifecycleTransition, WithdrawalBatch and
LifecycleAccrual's memory shapes. Any future struct edit must revisit them.

| Settings | Standard runtime / creation | Revolving runtime / creation | Incremental runtime / creation saving |
| --- | ---: | ---: | ---: |
| Canonical runs 44 | 24,488 / 26,068 | 25,061 / 26,719 | 237 / 279 each |
| E05 runs 1, no F | 23,791 / 25,436 | 24,344 / 26,053 | 318 / 360 each |

The E05 combination fits both live runtimes: 785 bytes spare on standard and
232 on revolving. Raw creation storage still exceeds the single-store limit
by 861 and 1,478 bytes; E09's compressed format addresses that separate limit.
E11 changes no hook/factory bytes, public ABI or storage layout.
[Incremental measurements](./results/e11.json) and
[final combined measurements](./results/combined-e11.json).

This arrangement differs from the earlier rejected allocator rewrite: callers
allocate explicitly and the calculator fills a supplied struct. The measured
result, rather than the general idea of assembly allocation, justifies keeping
this draft. E04's state-only view is incorporated into the new caller path.

## Qualification

The real-limit E09/E11 deployment test passes for all six production
combinations. Existing repayment tests exercise all four accrual intervals,
repeated views, event chronology, inclusive deadlines, same-block cures,
late donations, ordinary markets and revolving principal accounting.

The no-F compiler initially failed on the market test graph. Investigation of
the specific compilation failure is recorded with the final qualification.
No test assertion or tested path is removed. The canonical settings stay at 44.

**375 focused tests pass at canonical runs 44**, including the library, hook,
factory, market and repayment suites (`e09-e11-all-default/`). The no-F broad
qualification requires E12's valid memory-safe annotations in the arithmetic
helpers and test reader. E12 records those results separately. The old
raw-storage size gates remain separate from behavioral qualification and from
E09's real-limit deployment test.

Decision: retain the arena candidate. It gives
a useful reduction at both settings. Adopt E05 only with its full recorded
optimizer sequence and associated compiler qualification; setting runs to one
alone does not reproduce these figures.
