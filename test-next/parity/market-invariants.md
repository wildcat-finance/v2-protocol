# Market invariant parity

Status: complete.

## Family boundary

The legacy invariant tail has 31 runnable entries across ten concrete suites. The replacement
keeps the meaningful market properties in one runtime matrix instead of compiling one inherited
suite for every hook and market combination.

| Behavior                                                      | Legacy entries | Replacement properties |
| ------------------------------------------------------------- | -------------: | ---------------------: |
| Withdrawal gates across six hook and market cells             |              6 |                      1 |
| Monotone scale factors across the matrix and CAF12 accounting |              7 |                      1 |
| Revolving drawn-principal transitions                         |              7 |                      1 |
| Exact revolving utilization-interest formula                  |              1 |                      1 |
| Scaled-supply conservation                                    |              1 |                      1 |
| Withdrawal-liability conservation                             |              1 |                      1 |
| Arithmetic safety across ordinary and underwater paths        |              2 |                      1 |
| Sanctions and expected-action safety                          |              1 |                      1 |
| **Meaningful market total**                                   |         **26** |                  **8** |

The two legacy withdrawal-batch identity invariants are already replaced by stronger deterministic
market properties. The three generic ERC-20 invariants are retired with the rationale below.

## Runtime matrix

One generated handler action is applied to all six production cells:

- OpenTerm, FixedTerm, and PeriodicTerm hooks;
- standard and revolving markets for each hook type; and
- four lender actors sharing one configurable role provider.

This preserves the per-cell action budget without generating six copies of the same invariant
contract. Each canonical property ran 2,000 campaigns at depth 30, so every cell received up to
60,000 attempts from the same generated action stream. The 17-action surface covers deposits,
transfers, borrowing, both repayment paths, three withdrawal queue forms, execution, fees,
state updates, time, lender and borrower sanctions, `nukeFromOrbit`, and periodic APR proposals
and execution. After every campaign, all six markets must close and drain completely.

The revolving transition oracle does not call the market's update implementation or accept its
calculated state as the expected result. It reconstructs the stored pending batch from the public
view-calculated state, applies expiry-boundary accrual, models pending and unpaid settlement
rounding, and then calculates commitment plus utilization interest from the pre-update state using
the shared arithmetic primitives.

## Drawn-principal correction

The legacy matrix asserted `drawnAmount <= totalDebts`. That is not a valid revolving-market
invariant. The documented donation and lender-exit model deliberately keeps unrepaid borrower
principal even when donated liquidity satisfies withdrawals and lender debt falls. Normalized
withdrawal rounding can also put the old bound off by a wei after execution.

The replacement checks the intended rule directly:

- borrow and explicit repayment transitions must match the independently calculated principal;
- state updates, deposits, transfers, withdrawal settlement, sanctions, fees, and APR changes
  must not change drawn principal; and
- closing a revolving market must clear it.

This preserves the owner decision in `docs/v2.5-pre-audit-report-2026-08-15.md` A-15 instead of
retrofitting the replacement to a stale assertion.

## Retired and reassigned entries

`WithdrawalBatchIdentityInvariant`'s two properties are covered more strongly by the deterministic
fresh-key, collision rollback, overflow rollback, old-batch immutability, and closed-market drain
properties in `test-next/market/WildcatMarket.t.sol`.

`ERC20Invariant` is retired. It targets Solmate's generic `MockERC20`, not a Wildcat contract, and
the fixed-seed oracle reported that all 60,000 generated handler calls reverted while its three
assertions continued to pass against the initial empty state. Wildcat market-token and wrapper
conservation remain covered by their production-specific deterministic and matrix properties.

## Coverage and canonical result

The fixed-seed legacy oracle passes all 31 entries. All eight replacement invariants pass at the
canonical 2,000-run, depth-30 settings with zero handler reverts. The focused accurate-coverage
lane also compiles without via-IR after the temporary SphereX workaround and passes all eight
properties at its bounded 8-run, depth-15 settings. The temporary patch restores cleanly.

| Metric             | Legacy invariant tail | Replacement matrix | Reduction |
| ------------------ | --------------------: | -----------------: | --------: |
| Runnable suites    |                    10 |                  1 |    90.00% |
| Runnable entries   |                    31 |                  8 |    74.19% |
| Test-side initcode |       1,761,168 bytes |       54,426 bytes |    96.91% |
| Test-side runtime  |         916,040 bytes |       52,065 bytes |    94.32% |
| Inherited entries  |                    18 |                  0 |   100.00% |

The complete replacement checkpoint has 656 properties across 43 suites with zero inherited
entries, 1,069,410 bytes of test-side initcode, and 1,055,573 bytes of runtime bytecode. A forced
canonical via-IR AST build took 3m27.95s, including 207.17s in solc, and peaked at 5,772,504 KiB
RSS.
