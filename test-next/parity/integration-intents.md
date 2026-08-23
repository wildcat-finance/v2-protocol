# Integration intent parity

Status: open. The replacement suite is green and substantially smaller, but semantic parity for
cross-contract flows has not been established.

This ledger treats the frozen suite as a requirements archive, not an implementation template.
The goal is to preserve each useful guarantee without rebuilding the old inheritance graph or its
omnibus fixture.

The legacy suite will not be imported, moved back into default discovery, or used as replacement
test infrastructure. Every retained guarantee is implemented natively under `test-next/`.

## What the old integration matrix was proving

`MarketConfigMatrix` was more than a convenient way to duplicate tests. It composed the production
ArchController, both production hooks factories, all three built-in hook templates, a role
provider, standard and revolving market initcode, the sanctions Sentinel, and the wrapper factory.
Its six cells were:

- OpenTerm × standard
- FixedTerm × standard
- PeriodicTerm × standard
- OpenTerm × revolving
- FixedTerm × revolving
- PeriodicTerm × revolving

That topology supplied four independent guarantees:

1. both immutable production factories can deploy every supported built-in hook/market pairing;
2. the factory -> template -> instance -> market -> provider composition agrees on identity,
   configuration, flags, and authority;
3. common lifecycle behavior remains compatible in every cell; and
4. standard markets provide an economic control for new revolving behavior.

The replacement invariant suite executes all six runtime cells, but deploys markets through a
lightweight parameter factory. The factory suite executes both production factories, but only with
OpenTerm hooks. Those are useful tests; together they still do not prove the production six-cell
topology.

## Intent catalogue

| Intent                                               | Frozen owner                                                                                                 | Current replacement                                                                                                                              | Status          | Replacement owner/action                                                                                                                                                                                         |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Production six-cell deployment topology              | `MarketConfigMatrix` and every matrix scenario                                                               | Production factories cover OpenTerm; invariant matrix directly composes all three hooks with both market bytecodes                               | Missing seam    | Add one artifact-backed production-factory matrix fixture and assert all six deployments                                                                                                                         |
| Deterministic six-cell lifecycle                     | `LifecycleScenarios` happy-quarter matrix, 6 tests                                                           | Unit slices and randomized matrix cover individual transitions                                                                                   | Missing flow    | Add a runtime matrix scenario: deposit -> borrow -> independently checked accrual -> repay -> gated withdrawal -> close -> drain                                                                                 |
| Fixed and periodic withdrawal boundaries             | `LifecycleScenarios`, 4 tests                                                                                | Hook unit tests and invariant ghost counters                                                                                                     | Partial         | Keep the unit/invariant owners; add exact boundary assertions to the deterministic matrix flow                                                                                                                   |
| Periodic APR governance through a real market        | `AprGovernance`, 6 tests                                                                                     | Periodic hook state machine and market callback behavior are tested separately                                                                   | Missing seam    | Add proposal -> response window -> lender exit -> permissionless execution for standard and revolving; retain expiry/cancellation at the smallest real composition boundary                                      |
| Minimum deposit composition and ordering             | `MinimumDepositScenarios`, 5 tests                                                                           | Hook units cover scale conversion; market units cover ordinary minimum rejection                                                                 | Partial         | Add capacity-clamp-before-hook, live minimum update, and exact accrued-scale boundary through production hooks and markets                                                                                       |
| Audited rounding regressions                         | `RoundingRegressionRepro`, 5 tests                                                                           | Broad deposit/withdrawal/closed-market properties exercise nearby behavior                                                                       | Partial         | Restore the exact vulnerable numeric windows and explicit non-vacuity guards; do not replace these with broad success assertions                                                                                 |
| Direct sanctions lifecycle                           | `SanctionsScenarios`, 3 tests                                                                                | Market units cover queueing/escrow routing; wrapper integration uses the real Sentinel and escrows; invariant matrix covers randomized sanctions | Partial         | Add direct sanction -> nuke -> expired withdrawal -> escrow -> override -> release, periodic-window limitation, and deterministic revolving drawn-principal preservation                                         |
| Borrower-account compatibility                       | `BorrowerAccountCompatibility`, 18 tests                                                                     | The separate 11-entry origination family is replaced; borrower transfer and wrapper namespace behavior have focused owners                       | Substantial gap | Add account execution across six production cells, credentialed borrowing/provider operations, representative standard/revolving lifecycles, and only-principal/salt/fee checks not already owned by origination |
| Production-shaped economics                          | `ProductionMirror`, 5 tests                                                                                  | Revolving formula and differential math are strong at smaller scales; wrapper behavior is covered separately                                     | Mostly missing  | Restore large-balance delinquency/grace/penalty/recovery and standard/RCF yield crossover; keep wrapper execution with the wrapper owner unless the large-scale composition finds a distinct boundary            |
| Standard/revolving economic anchors                  | `RevolvingDifferential`, 4 tests                                                                             | Five deterministic properties in `WildcatMarketTest`                                                                                             | Preserved       | No new integration owner unless the production matrix exposes a different factory/configuration result                                                                                                           |
| Wrapper readiness and sanctions composition          | `WrapperReadinessScenarios` plus `WrapperSanctionsScenarios`, 10 tests                                       | Ten production-composition properties in `Wildcat4626WrapperIntegrationTest`                                                                     | Preserved       | Keep current owner; it intentionally uses artifact-backed market deployment because factory deployment is not the behavior under test                                                                            |
| Redeem plus scaled-withdrawal composition            | `WrappedWithdrawalScaledQueue`, 3 tests                                                                      | Exact scaled queueing exists; wrapper redeem/queue atomicity does not                                                                            | Missing seam    | Add an account helper that redeems and queues in one transaction, including rollback and standard/revolving parity                                                                                               |
| Stateful matrix safety and liveness                  | `MatrixInvariant`, 18 inherited matrix invariants; CAF12 and withdrawal identities add 10 meaningful entries | Eight six-cell invariants with stronger conservation and corrected revolving-principal semantics                                                 | Preserved       | Keep current owner; use deterministic scenarios for required sequences rather than forcing them into random action generation                                                                                    |
| Exact production event contracts                     | Event assertions distributed through market/integration suites                                               | OpenTerm and market lifecycle owners now assert every missing event's exact emitter, topics, and data                                            | Replaced        | Keep event assertions beside the state transition they describe                                                                                                                                                  |
| Lens rejects non-V2 markets with the canonical error | Legacy Lens bubble test                                                                                      | Facade now routes a V1-shaped token through the production core and bubbles exact `NotV2Market`                                                  | Replaced        | Keep in `MarketLensFacadeTest`                                                                                                                                                                                   |

## Exact event assertions

The replacement tree now explicitly asserts these production events:

- `Transfer`
- `AccountMadeFirstDeposit`
- `InterestAndFeesAccrued`
- `StateUpdated`
- `WithdrawalBatchClosed`
- `WithdrawalBatchExpired`
- `WithdrawalQueued`
- `WithdrawalExecuted`
- `SanctionedAccountWithdrawalSentToEscrow`

An event is not considered preserved merely because the state transition is covered. The new
assertions match emitter, indexed topics, and ABI-encoded payload because those are downstream
protocol contracts for indexers and services.

## Replacement shape

The missing work should be added in four bounded layers:

1. **Topology:** one artifact-backed production-factory fixture that can deploy all six cells.
2. **Deterministic flows:** lifecycle, periodic APR, minimum-deposit ordering, sanctions, and the
   production-shaped economic scenarios on that fixture.
3. **Cross-contract identities:** borrower-account execution and wrapped scaled queueing in focused
   suites, reusing the topology helper where that is actually the behavior under test.
4. **Contract surfaces:** exact event assertions and the Lens `NotV2Market` error in their existing
   domain suites.

The stateful invariant matrix stays independent. It explores action ordering and conservation;
it is not expected to guarantee that a particular business sequence occurs in every campaign.

## Exit gate

Do not call the replacement suite semantically complete until:

- every row above is `Preserved`, `Replaced`, or explicitly `Retired` with rationale;
- every one of the 1,438 distinct legacy properties has an exact disposition under one of these
  intent owners;
- no disposition relies only on a test name or line-coverage percentage;
- both fixed-seed suites pass; and
- the replacement compile/runtime measurements are rerun after the missing flows land.
