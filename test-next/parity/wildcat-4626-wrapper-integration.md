# Wildcat 4626 wrapper integration parity

Status: complete.

## Family boundary

This checkpoint closes the ten legacy wrapper integration entries, the six wrapper handoffs
previously parked in the borrower-transfer family, the three token-provider cross-feature entries,
and the three wrapped scaled-withdrawal entries. Eleven composed properties use the production
ArchController, borrower registry, sanctions Sentinel and escrows, all three built-in access hooks,
standard and revolving markets, wrapper factory, and wrapper. Artifact-backed deployment keeps
that production graph out of the test artifact instead of rebuilding the legacy matrix fixture.

| Behavior slice                                                       | Legacy entries | Replacement properties |
| -------------------------------------------------------------------- | -------------: | ---------------------: |
| Factory-only registration and readiness across all built-in hooks    |              2 |                      1 |
| Coordinated direct/share quarantine and unaffected-holder redemption |              2 |                      1 |
| Market-first quarantine and both wrapper-backing protections         |              3 |                      1 |
| Live escrow release before and after principal migration             |              3 |                      1 |
| Principal escrow namespace and live-borrower sweep authority         |              2 |                      1 |
| Same-principal overrides and post-migration wrapper readiness        |              2 |                      1 |
| Empty/repeated quarantine and the revolving-market path              |              2 |                      1 |
| Debt-token self-reference and cross-market interest authorization    |              2 |                      2 |
| Wrapper-interest cross-market authorization                          |              1 |                      1 |
| Atomic wrapper redemption and exact scaled withdrawal queue          |              3 |                      1 |
| **Total**                                                            |         **22** |                 **11** |

Readiness is checked before and after credentialing the wrapper on production OpenTerm,
FixedTerm, and PeriodicTerm hooks. Wrapper previews remain arithmetic while the executable limits
stay closed, and the limits open only after the hook can accept a plain market-token transfer to
the wrapper.

The sanctions properties prove both sides of the composition. A wrapper call quarantines a
lender's direct market position and wrapper shares without changing aggregate backing or blocking
an unrelated holder's redemption. A market-first call leaves wrapper shares in place until the
wrapper completes quarantine. Neither entrypoint can quarantine the registered wrapper or remove
the backing for outstanding shares, and standard and revolving markets follow the same rules.

Real CREATE2 escrows exercise the wrapper's canonical escrow-release branch. An escrow created
under the old principal remains releasable after a borrower transfer even while the lender and old
escrow are sanctioned in the new namespace. Later quarantine moves the shares into a distinct
escrow owned by the new principal. Same-principal borrower-account rotation preserves lender
overrides; a principal migration deliberately starts a new namespace. Wrapper sweep authority
tracks the operational borrower account rather than either principal.

The role-provider properties also preserve the source-market self-reference edge. A direct
provider read can see the source debt-token balance, but a source-market deposit fails closed when
the recursive balance read reaches the market's view reentrancy guard. Debt-token and wrapper
claims that grow through production interest can authorize deposits into a separate production
market after first being rejected below their configured thresholds.

The scaled-withdrawal property runs standard and revolving markets at an accrued scale factor. A
small account helper redeems wrapper shares and queues the same exact scaled amount in one call,
without consuming its pre-existing direct market-token balance. Asking it to queue one scaled token
too many reverts the whole call and restores wrapper shares, backing, direct balance, and market
state.

## Coverage and canonical result

The fixed-seed legacy oracle passes all ten wrapper integration entries, all 37 borrower-transfer
entries, all three token-provider cross-feature entries, and all three scaled-queue entries. All
eleven replacement properties pass under canonical via-IR settings. Accurate coverage also compiles this 79-source production graph
without an additional workaround and executes the live sanctions-escrow release path and real
cross-market deposit paths that the focused suites intentionally left open.

At the seven-property wrapper checkpoint, the two legacy runnable integration artifacts totalled
432,010 bytes of initcode and 191,416 bytes of runtime bytecode. The replacement runnable artifact
and its five reusable support artifacts totalled 32,678 and 32,417 bytes, reducing initcode by
92.44% and runtime bytecode by 83.06%.

The three token-provider properties replace two additional legacy artifacts totalling 335,492
bytes of initcode and 94,900 bytes of runtime bytecode. Conservatively charging the complete
12,271-byte growth of the replacement suite—including the shared memory-safe artifact deploy
path—still reduces that final slice by 96.34% and 87.07%, respectively.

Before the scaled-queue property was added, the borrower-transfer and wrapper-integration boundary
reduced 47 legacy entries to 19 composed properties. Counting both runnable artifacts and the five
unique reusable support artifacts, emitted test-side bytecode fell from 638,876 to 65,129 initcode
bytes and from 277,826 to 64,842 runtime bytes: reductions of 89.81% and 76.66%, respectively.

The full-suite counts and bytecode totals in the earlier checkpoint predate this property and its
small account helper. They are rerun once at the final cutover gate rather than revised from a
focused artifact.
