# Wildcat 4626 wrapper integration parity

Status: complete.

## Family boundary

This checkpoint closes the ten legacy wrapper integration entries and the six wrapper handoffs
previously parked in the borrower-transfer family. Seven composed properties use the production
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
| **Total**                                                            |         **16** |                  **7** |

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

## Coverage and canonical result

The fixed-seed legacy oracle passes all ten wrapper integration entries and all 37 borrower-transfer
entries. All seven replacement properties pass under canonical via-IR settings. Accurate coverage
also compiles this 74-source production graph without an additional workaround and executes the
live sanctions-escrow release path that the focused wrapper mock suite intentionally left open.

The two legacy runnable integration artifacts total 432,010 bytes of initcode and 191,416 bytes of
runtime bytecode. The replacement runnable artifact is 28,093 and 28,067 bytes. Conservatively
charging all five reusable test-next support artifacts used by the fixture brings it to 32,678 and
32,417 bytes, still reducing initcode by 92.44% and runtime bytecode by 83.06%.

Across the complete borrower-transfer and wrapper-integration boundary, 47 legacy entries become
19 composed replacement properties. Counting both runnable artifacts and the five unique reusable
support artifacts, emitted test-side bytecode falls from 638,876 to 65,129 initcode bytes and from
277,826 to 64,842 runtime bytes: reductions of 89.81% and 76.66%, respectively.

The full replacement checkpoint is 614 tests across 39 suites with zero inherited entries,
890,595 bytes of test-side initcode, and 880,367 bytes of runtime bytecode. A forced canonical
via-IR AST compile-to-green takes 2m26.55s, including 142.83s in solc, with a 3,814,448 KiB RSS
peak; execution takes 2.06s.
