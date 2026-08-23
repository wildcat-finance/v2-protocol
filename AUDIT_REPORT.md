# Wildcat V2 Protocol Security Audit Report

## Audit Metadata

| Field | Value |
|---|---|
| Repository | `v2-protocol` |
| Branch | `feat/v2.5-gas-optimizations-reviewed` |
| Assessed revision | `215f4411dc48b83e2ac9a4f4c25a43243b02afec` |
| Report date | 2026-08-22 |
| Review methods | X-Ray v2, Solidity Auditor v3, Fizz v1, focused Foundry regressions, Medusa stateful fuzzing |
| Solidity-auditor coverage | 12 independent review passes over 95 in-scope files |
| Final result | 5 reportable findings: 2 Medium, 3 Low, 0 High, 0 Critical; 2 accepted observations |

This report consolidates the findings and test results already validated during the audit. It does not claim that the assessed development branch is deployed to mainnet, and it does not represent a guarantee that the code contains no additional vulnerabilities.

## Executive Summary

The audit identified five reportable issues and two accepted observations. The most important reportable issues involve wrapper sanctions-escrow provenance and a sanctions-policy inconsistency in `closeMarket`. Three lower-severity findings concern reserve rounding, metadata compatibility in the lens, and temporary reserve rounding after an APR reduction. The checkpoint-dependent delinquency behavior and finite withdrawal-batch counter were accepted after considering the protocol's operating model and controlled asset list.

No finding was rated High or Critical after considering attacker prerequisites, market-listing controls, asset ownership, lifecycle constraints, and the cost or time needed to reach the vulnerable state.

The final Fizz campaign compiled the exact harness through viaIR and executed 508,301 calls. It finished with 135 passing targets and four expected failing targets. Those four counterexamples map to three findings already identified by the manual audit: F-01, F-04, and F-06. The final campaign produced no new root cause, harness false positive, or unresolved result.

### Finding Summary

| ID | Severity | Confidence | Title | Status |
|---|---:|---:|---|---|
| F-01 | Medium | 95% | Foreign Sentinel escrow bypasses wrapper sanctions | Open |
| F-02 | N/A | 100% | Checkpoint-based delinquency transitions require state writes | Accepted / Hydra mitigated |
| F-03 | N/A | 100% | Finite `uint104` withdrawal-batch lifetime counter | Accepted known issue |
| F-04 | Low | 90% | Scaled-space reserve rounding understates required liquidity | Open |
| F-05 | Low | 100% | Factory-admitted `bytes32` metadata can revert lens batches | Fixed / shared decoder |
| F-06 | Low | 75% | APR-cut double rounding creates a one-basis-point reserve gap | Open |
| F-07 | Medium | 75% | `closeMarket` surplus payout bypasses the raw sanctions draw gate | Open |

## Scope and Methodology

The review covered the current `v2-protocol` checkout, including core market accounting, withdrawals, hooks, sanctions enforcement, wrapper behavior, factories, libraries, and lens contracts. The assessed revision is an unreleased V2.5 development revision; this report makes no affected-release or deployment-prevalence claim.

The work included:

- an X-Ray architecture, trust-boundary, entry-point, invariant, documentation, and test-readiness analysis;
- 12 independent Solidity-auditor passes with different security focuses;
- targeted source and state-transition analysis;
- focused Foundry regression tests for selected findings;
- construction of a stateful Fizz harness using real protocol contracts and bounded mocks;
- two harness-calibration campaigns followed by a clean final Medusa campaign; and
- deduplication and severity calibration of overlapping observations.

The protocol source tree was not modified during the audit. Generated X-Ray and fuzzing artifacts are listed at the end of this report.

## Detailed Findings

### F-01 — Foreign Sentinel Escrow Bypasses Wrapper Sanctions

**Severity:** Medium  
**Confidence:** 95%  
**Affected code:** [`src/vault/Wildcat4626Wrapper.sol`](src/vault/Wildcat4626Wrapper.sol), `_isEscrowRelease` and `_beforeTokenTransfer`; [`src/WildcatSanctionsSentinel.sol`](src/WildcatSanctionsSentinel.sol), `createEscrow` and `overrideSanction`

#### Description

`Wildcat4626Wrapper` makes a special exception for transfers sent by a canonical Wildcat sanctions escrow. The wrapper verifies that the sender is the deterministic escrow for the borrower namespace, recipient, and wrapper reported by that escrow. It does not verify that the wrapper created or funded the escrow through its own `nukeFromOrbit` flow, nor that the escrow's borrower namespace belongs to the wrapper's market.

A wrapper-share holder can therefore create a genuine escrow under an unrelated namespace controlled by the holder, fund it with the holder's wrapper shares, override the recipient only under that unrelated namespace, and release the shares. The recipient can remain sanctioned under the market's live principal while the release succeeds.

#### Impact

This bypasses the wrapper's live-principal sanctions policy and permits repeatable delivery of wrapper shares to an otherwise blocked recipient. It does not steal lender assets: the attacker must control the shares placed in the foreign escrow.

#### Validation

A focused Foundry regression demonstrated that a direct transfer to the sanctioned recipient reverted while release from the foreign-principal escrow succeeded. Fizz property SP-43 independently reproduced the provenance failure in the final campaign.

#### Recommendation

Record the escrows created by this wrapper's `nukeFromOrbit` flow and require `_isEscrowRelease` to accept only a recorded escrow. Store provenance rather than requiring the current principal so legitimate escrows created under a former principal can still release after principal migration.

Add negative tests for canonical escrows created under unrelated namespaces and retain the existing historical-principal release test as a positive control.

### F-02 — Checkpoint-Based Delinquency Transitions Require State Writes

**Disposition:** Accepted known behavior. **Confidence:** 100%. **Operational control:** Hydra keeper.

**Affected code:** [`src/libraries/FeeMath.sol`](src/libraries/FeeMath.sol), interest and delinquency accrual; [`src/market/WildcatMarketBase.sol`](src/market/WildcatMarketBase.sol), `_calculateCurrentState` and `_writeState`; [`src/market/WildcatMarket.sol`](src/market/WildcatMarket.sol), `closeMarket`

#### Description

Market accounting is updated lazily because a blockchain cannot persist a state transition without a transaction. Accrual classifies an elapsed interval using the previously stored `isDelinquent` flag, then recalculates the current liquidity requirement and stores the new flag at the end of the state write.

Ordinary state-changing activity naturally refreshes busy markets. Idle markets can otherwise accumulate a larger difference between their economically projected condition and stored `timeDelinquent`, so Wildcat operates the Hydra keeper across all markets. Hydra monitors approaching delinquency and refreshes state before and after the relevant timeout when the threshold is crossed.

Keeper polling and block inclusion are not exact to the instant, so a small cadence-dependent difference remains possible. This timing tolerance is an accepted operational property of the lazy-state model.

#### Audit Resolution

A focused regression demonstrated the expected difference between an indefinitely idle market with no checkpoint and a path containing a timely permissionless checkpoint. It did not demonstrate a way to bypass ordinary market writes or the Hydra keeper.

F-02 is therefore not a reportable vulnerability and requires no protocol change. Reopen it only if a supported market can defeat timely checkpointing under the stated operating model, or if a material accounting divergence remains after the expected checkpoint occurs.

### F-03 — Lifetime `uint104` Withdrawal Counter Enables Renewable Queue Denial

**Disposition:** Accepted known issue. **Confidence:** 100%.

**Affected code:** [`src/libraries/Withdrawal.sol`](src/libraries/Withdrawal.sol), `WithdrawalBatch`; [`src/market/WildcatMarketWithdrawals.sol`](src/market/WildcatMarketWithdrawals.sol), `_queueWithdrawal`

#### Description

`WithdrawalBatch.scaledTotalAmount` is a `uint104` cumulative counter. Queueing adds to this total with checked arithmetic. Paying and burning queued shares advances `scaledAmountBurned`, but it never reduces `scaledTotalAmount` or restores counter headroom.

An eligible lender can repeatedly deposit and queue liquid shares until the pending batch total reaches `2^104 - 1`. Any later attempt to queue even one additional scaled unit into that batch reverts with arithmetic panic. At expiry, the attacker can execute the paid withdrawal, recover the underlying asset, and use it to saturate a later batch.

#### Impact

The attacker can repeatedly deny honest lenders access to `queueWithdrawal`, `queueWithdrawalScaled`, and `queueFullWithdrawal` for the active batch. The attack is most practical for a market whose underlying token has unusually high decimals. In the validated 30-decimal example, filling the counter required approximately 20.2824 nominal tokens, plus any interest top-up, and the principal was recoverable at expiry. The Foundation-controlled asset list currently contains only 6- and 18-decimal assets; even the old `uint104` threshold represents approximately 20.28 trillion nominal tokens for an 18-decimal asset.

#### Validation

A focused regression filled the batch counter to `20282409603651670423947251286015`, observed a competing queue request revert with panic `0x11`, then reclaimed the attacker's withdrawal and repeated the fill against the next batch. The temporary regression was removed after validation.

#### Audit Resolution

No protocol or ABI change was retained. Saturating the counter requires repeatedly replacing paid shares before the same batch expires. At the minimum scale factor, the `uint104` limit represents approximately `2.03e13` nominal tokens for an 18-decimal asset or `2.03e25` for a 6-decimal asset. Scale-factor growth only increases the required underlying amount.

The Foundation controls the supported asset list, which currently contains only 6- and 18-decimal assets. The demonstrated low-capital case required an unsupported 30-decimal token, while reaching the same state with a supported asset is not credible under present capital, transaction-count, and block-gas constraints. The original representation and storage layout are therefore retained.

The finite counter is recorded in `docs/Known Issues.md`. Reopen F-03 if a higher-decimal asset is considered for listing, a practical path reaches the limit with a supported asset, or the counter can fail below `type(uint104).max`.

### F-04 — Scaled-Space Reserve Rounding Understates Required Liquidity

**Severity:** Low  
**Confidence:** 90%  
**Affected code:** [`src/libraries/MarketState.sol`](src/libraries/MarketState.sol), `liquidityRequired` and `borrowableAssets`; [`src/market/WildcatMarket.sol`](src/market/WildcatMarket.sol), `borrow`

#### Description

`liquidityRequired` applies the reserve ratio while outstanding lender debt is still expressed in scaled shares, then converts the rounded result into normalized underlying units. A fractional reserve share can round away before normalization even when that fraction represents a positive and potentially material underlying-token obligation at a high scale factor.

The documented invariant instead describes the reserve requirement in normalized underlying units. Because `borrowableAssets` consumes the understated result, the borrower can withdraw liquidity that the documented formula would reserve for lenders.

#### Impact

The market can be under-reserved relative to its documented accounting invariant and can remain classified as healthy after the borrower removes the omitted amount. Reaching a materially large discrepancy requires an extreme but reachable scale factor.

The validated high-scale trace used one scaled share, a scale factor of `2^22 * RAY`, and a 4,999-bip reserve ratio. The implementation returned zero reserve, while the documented half-up normalized formula required 2,096,733 underlying atomic units.

#### Validation

Fizz global property GL-08 and positive-borrow property SP-20 reproduced the discrepancy in the final campaign. These two failed targets are the same root cause.

#### Recommendation

Calculate the reserve in the documented unit order: normalize the relevant outstanding supply and then apply the reserve ratio. If the protocol adopts a different one-pass formula, specify its rounding direction and prove that it cannot understate the required reserve.

Add high-scale, low-share-count tests covering reserve calculation, borrowing limits, and delinquency classification.

### F-05 — Factory-Admitted `bytes32` Metadata Can Revert Lens Batches

**Severity:** Low  
**Confidence:** 100%<br>
**Affected code:** [`src/HooksFactory.sol`](src/HooksFactory.sol), market deployment metadata checks; [`src/libraries/LibERC20.sol`](src/libraries/LibERC20.sol), compatible metadata queries; [`src/lens/TokenData.sol`](src/lens/TokenData.sol), `fill`; [`src/lens/MarketData.sol`](src/lens/MarketData.sol), batch fill functions

#### Description

Market deployment reads token names and symbols through `LibERC20`, which accepts both modern ABI-encoded strings and legacy fixed-width `bytes32` returns. The lens later uses typed `IERC20.name()` and `symbol()` calls that require dynamic-string encoding.

A token can therefore pass factory admission and support a valid market while causing the lens metadata fill to revert. The multi-market fill loops do not isolate an individual market's metadata failure, so one compatible-but-legacy token can abort the entire batch response.

#### Impact

This is a read-only availability and integration failure. It can prevent applications, SDKs, or monitoring systems from retrieving discovery data for unrelated markets in the same batch. It does not directly affect custody or core market accounting.

#### Validation

The source discrepancy was confirmed against the repository's legacy metadata helpers and fixtures. New `test-next` regressions exercise direct token reads, mixed string/`bytes32` token batches, market data, factory-wide market batches, and aggregated multi-factory batches. The original `bytes32` trigger now succeeds through each lens surface. Existing tests continue to reject truncated and noncanonical dynamic-string encodings while accepting canonical strings, legacy `bytes32`, high-bit final bytes, and harmless trailing data.

#### Audit Resolution

`TokenMetadataLib.fill` now uses `LibERC20` for `name`, `symbol`, and `decimals`, matching the exact decoder used during market deployment. This closes the admission/read discrepancy at the shared metadata boundary without changing any lens ABI, market contract, or storage layout.

The focused lens and metadata suites passed 27 tests. The canonical suite passed all 678 tests, including all eight stateful market-matrix invariants. The added decoder increased `MarketLensCore` and `MarketLensAggregator` runtime bytecode by 270 bytes each; the tighter aggregator retains 3,938 bytes of EIP-170 margin.

Per-market `try/catch` isolation was not added. Metadata that mutates or begins reverting after market deployment remains part of the controlled asset-listing boundary rather than a new partial-result API for the lens.

### F-06 — APR-Cut Double Rounding Creates a One-Basis-Point Reserve Gap

**Severity:** Low  
**Confidence:** 75%  
**Affected code:** [`src/access/MarketConstraintHooks.sol`](src/access/MarketConstraintHooks.sol), temporary excess reserve calculation

#### Description

For a sufficiently large APR reduction, the hook calculates a temporary reserve ratio intended to equal twice the relative APR cut, capped at 100%. The implementation first floors the relative reduction to whole basis points and then doubles that rounded value.

Multiplying after the first floor can produce a result one basis point below a single-floor calculation of the documented expression. The lower temporary reserve remains active during the two-week protection period following the APR change.

#### Impact

The borrower can draw an additional 0.01% of lender supply in affected threshold cases. For example, a one-basis-point reserve gap on a 10 million USDC market makes an additional 1,000 USDC immediately borrowable.

#### Validation

Fizz property SP-14 reproduced the `7,501 -> 5,625` APR transition: the implementation produced a 5,000-bip temporary reserve while the single-floor doubled expression produced 5,001 bips.

#### Recommendation

Multiply the reduction by two before performing the division, cap the result at 10,000 bips, and explicitly document whether the policy rounds down, to nearest, or conservatively upward.

Add exact-boundary and non-zero-remainder test cases, including consecutive APR reductions during the temporary reserve period.

### F-07 — `closeMarket` Surplus Payout Bypasses the Raw Sanctions Draw Gate

**Severity:** Medium  
**Confidence:** 75%  
**Affected code:** [`src/market/WildcatMarket.sol`](src/market/WildcatMarket.sol), `borrow` and `closeMarket`

#### Description

`borrow` rejects a draw when either the operational borrower or its registered principal is raw-flagged by the sanctions policy. `closeMarket` contains another borrower-directed underlying-token outflow: when market assets exceed lender debt, it transfers the full surplus to `msg.sender` before closing.

The close-time surplus branch does not apply the raw borrower/principal check. A flagged borrower can therefore receive existing or donated surplus through `closeMarket` even though an economically equivalent `borrow` call is rejected.

#### Impact

The issue bypasses the protocol's sanctions boundary for borrower-directed underlying payouts. It does not take assets owed to lenders because the transferred value is the surplus above all lender obligations. Severity depends partly on whether the protocol intends close-time return of borrower-owned excess to be subject to the same raw sanctions policy as ordinary draws.

#### Validation

The composed source trace used a fully covered market with excess underlying: the raw-flagged borrower could not borrow the excess, while the close branch transferred that same surplus and closed the market. Existing tests independently establish the raw two-identity borrow guard and return of excess assets during close.

#### Recommendation

Apply the same raw borrower/principal check before every borrower-directed underlying payout. If a sanctioned borrower must remain able to close a market, close the market while routing only the surplus into a sanctions escrow rather than paying it directly.

Add tests covering a flagged operational borrower, a flagged principal, principal migration, donated surplus, and policy overrides.

## Fizz Campaign Results

The final Fizz suite contained 69 documented properties:

- 25 global properties;
- 44 operation-specific properties;
- 62 executable Solidity assertions; and
- 7 deferred properties requiring dedicated campaign or oracle work.

The exact final suite compiled successfully through viaIR in 35m26s. The final Medusa campaign then ran for 6m27s and recorded:

| Metric | Result |
|---|---:|
| Calls executed | 508,301 |
| Bytecode branch IDs reached | 18,557 |
| Targets passed | 135 |
| Targets failed | 4 |
| Saved test-result JSON files | 21 |
| On-disk call-sequence JSON files | 541 |
| Novel vulnerability roots | 0 |
| Harness false positives in final campaign | 0 |
| Uncertain final results | 0 |

The four failing targets were:

| Target | Property | Finding |
|---|---|---|
| `property_coverageLiquidityFormula` | GL-08 | F-04 reserve rounding |
| `wildcatMarket_borrow_full` | SP-20 | F-04 reserve rounding |
| `wildcatMarket_aprBoundaryCampaign` | SP-14 | F-06 APR-cut rounding |
| `wildcatSanctionsEscrow_provenanceCampaign` | SP-43 | F-01 escrow provenance |

Earlier campaigns exposed several projected-state versus stored-state oracle mismatches and handler precondition errors. Those harness issues were corrected before the final campaign. The affected properties passed in the final run.

## X-Ray Readiness Assessment

X-Ray measured approximately 13,444 non-comment Solidity lines across 108 source files and catalogued the protocol's trust boundaries, entry points, invariants, integrations, documentation, tests, and development history.

Its rubric assigned an **EXPOSED** readiness verdict because:

- the protocol does not enforce a timelock for privileged actions; and
- four mainnet-related `PeriodicTermHooks` TODOs remain unresolved.

This label is an audit-readiness classification. It does not mean that the audit found a Critical-severity vulnerability.

## Limitations

- The assessed checkout is a development branch. Deployment status and affected public release ranges were not evaluated for this summary.
- The final Medusa fuzz phase lasted 6m27s. A longer campaign may find additional state sequences.
- Source-level LCOV attribution is unreliable for this suite because proxy dispatch, viaIR/Yul compilation, and SphereX instrumentation obscure source mappings. The call and bytecode-branch metrics remain useful, but the generated source percentages should not be treated as complete coverage evidence.
- Seven properties remain deferred: SP-08, SP-13, SP-26, SP-27, SP-29, SP-39, and SP-40.
- Temporary focused regressions used to validate F-02 and F-03 were removed after execution and are not included as portable PoCs.
- No audit can establish the absence of all vulnerabilities.

## Remediation Priorities

1. Address F-01 and F-07 before treating the assessed branch as production-ready, retain Hydra checkpointing as the operational control for F-02, and retain the controlled asset-list boundary for F-03.
2. Correct the reserve and APR rounding order in F-04 and F-06, then rerun the existing counterexample properties as regression tests.
3. Align lens metadata handling with factory admission for F-05 and add failure isolation for batch reads.
4. Convert the seven deferred properties into executable campaigns where practical.
5. Run a longer Medusa campaign and a complementary Echidna campaign after the fixes.
6. Perform the planned coverage pass using a configuration that avoids the current SphereX/source-attribution limitations.

## Audit Artifacts

- [X-Ray report](x-ray/x-ray.md)
- [Entry-point inventory](x-ray/entry-points.md)
- [Invariant inventory](x-ray/invariants.md)
- [Architecture diagram](x-ray/architecture.svg)
- [Fizz report](fizz_data/report.md)
- [Property inventory](PROPERTIES.md)
- [Property implementation plan](fizz_data/property-plan.md)
- [Final Medusa log](fizz_data/corpus_medusa/medusa-run.log)
- [Final coverage report](fizz_data/corpus_medusa/coverage/coverage_report.html)
