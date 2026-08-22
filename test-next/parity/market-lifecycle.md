# Market lifecycle parity

Status: complete; the withdrawal checkpoint now owns the two inherited closed-market drain entries.

## Family boundary

The legacy `WildcatMarketTest` exposes 61 runnable properties and
`FixedTermWildcatMarketTest` recompiles all 61 through inheritance. The replacement adds 14
properties to the shared `WildcatMarketTest` runtime matrix. Behavior already owned by the token,
hook-dispatch, or production access-hook suites is mapped to those completed families instead of
being compiled into the market artifact again.

| Shared behavior slice                                              | Legacy entries | Replacement ownership |
| ------------------------------------------------------------------ | -------------: | --------------------- |
| State persistence, no-op update, and both expired-batch paths      |              8 | 2 market properties   |
| Deposit exactness, capacity, rounding, closure, and transfer error |             18 | 1 market property     |
| Production minimum-deposit integration                             |              2 | 1 market property     |
| Deposit and withdrawal credential/access matrices                  |             14 | access-hook families  |
| Empty, available, and unavailable protocol fees                    |              6 | 1 market property     |
| Borrow liquidity, authority, closure, and sanctions                |              6 | 1 market property     |
| Close debt/excess, pending/unpaid batches, and batch-key safety    |             24 | 6 market properties   |
| Repay success, zero, closure, and transfer failure                 |              6 | 1 market property     |
| Exact hook dispatch and revert bubbling                            |             18 | hook/type families    |
| Rescue authority and protected assets                              |              6 | 1 market property     |
| Transfer rounding, known-lender, disabled, and access policy       |             12 | token/access families |
| Randomized closed-market withdrawal drain                          |              2 | 1 withdrawal property |
| **Total**                                                          |        **122** | **122 mapped**        |

The deposit property tests both entrypoints rather than treating `deposit` as an alias: `depositUpTo`
clips to remaining capacity and returns the actual transfer, while `deposit` rolls the same clipped
operation back with `MaxSupplyExceeded`. It also preserves zero-scaled minting after interest,
closed-market rejection, and the underlying transfer failure. A separate production-hook property
keeps the minimum-deposit boundary visible at the market entrypoint.

The close properties preserve the recent batch-key fixes directly. Closing at the current batch's
expiry installs the one-second sentinel key. Closing before a future expiry leaves the old batch and
lender status immutable when a later closed-market withdrawal selects the fallback key. Existing
fallback keys revert without changing state, and `uint32.max` still reverts on the checked increment.
Pending-only, unpaid-only, and mixed pending/unpaid debt are settled, while missing borrower approval
rolls back an unpaid-batch close.

Shared-property composition is explicit. `HooksConfigTest` proves exact custom-error bubbling for
every callback, `HookDispatchTest` proves the real market entrypoints build and route the expected
calldata, and the lifecycle properties execute the ordinary callbacks. OpenTerm and FixedTerm suites
own credential, known-lender, blocked-lender, and transfer-disablement state machines. The market-token
properties own transfer accounting and the post-interest scaled-rounding failure.

## Coverage and canonical result

The fixed-seed legacy oracle passes all 122 standard/fixed-term entries. All 43 cumulative replacement
market properties pass; 14 were added for this slice. Focused accurate coverage reports 98.32% lines,
97.90% statements, 86.36% branches, and 100% functions for `WildcatMarket` (117/119 lines, 140/143
statements, 19/22 branches, and 11/11 functions). `WildcatMarketToken` and `WildcatMarketConfig` remain
at 100% across all four measures.

The two uncovered `WildcatMarket` lines are not ordinary lifecycle omissions. The internal `_repay`
closed-state guard is preceded by `closeMarket`'s public closed-state rejection, and
`CloseMarketWithUnpaidWithdrawals` requires an adversarial asset that reports a successful repayment
without moving funds. The latter stays available for the adversarial/invariant pass rather than
weakening the normal fixture's ERC-20 semantics.

The comparison charges the two legacy suite artifacts and their dedicated reverting-hook artifact
against growth of the already-shared replacement market artifact. Hook and token artifacts reused by
the mapped properties are already charged to their own completed families.

| Lifecycle artifact delta              | Initcode bytes | Runtime bytes |
| ------------------------------------- | -------------: | ------------: |
| Legacy standard/fixed suites and hook |        518,970 |       277,749 |
| Replacement shared-market growth      |         40,109 |        40,107 |
| **Difference**                        |   **-478,861** |  **-237,642** |
| **Reduction**                         |     **92.27%** |    **85.56%** |

The full replacement checkpoint is 549 tests across 35 suites with zero inherited entries,
688,728 bytes of test-side initcode, and 679,543 bytes of runtime bytecode. A forced canonical
compile-to-green takes 1m53.83s, including 110.76s in solc, with a 3,044,364 KiB RSS peak;
execution takes 1.80s.
