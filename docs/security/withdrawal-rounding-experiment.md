# Withdrawal rounding carry experiment

Status: local experiment branching from the cumulative-counter fix
`23c47cde20c60d42c8e7a6aa1d4639968e45f9fb`. Not a deployment recommendation.

Protocol selection comes first: establish the immutable accounting and interfaces,
then adapt the subgraph, SDK and app. Existing consumer models do not constrain
the protocol design. Their migration is subsequent integration work.

## Smaller complete-accounting candidate — 2026-09-29

`experiment/withdrawal-rounding-size` branches from the saved carry checkpoint
`5cf66ab884420c207002532cfac51dc010260a29`. It retains the accounting described
below, but reduces runtime by 429 bytes with three changes:

- Price the entire unpaid live amount first. If it is unaffordable, compute the
  largest affordable burn directly as
  `((available + 1) * RAY - 1 - batchRemainder) / scaleFactor`. The conditional
  bounds `available` before multiplying, including arbitrary direct donations.
  The live amount is checked against uint104 before calculation; cumulative
  counters stay uint128. Payment, liability and counter checks remain intact.
- Use the same carry-aware pending/outstanding reserve partition at every
  reserve ratio. It already gives exactly the old results at 0% and 100%, so
  those separate branches are unnecessary. It also rejects the unreachable
  invalid state where normalized pending exceeds supply at those endpoints;
  previously only intermediate ratios checked that subtraction.
- Return a stored withdrawal batch through Solidity's native struct copy. The
  pending-batch preview path is unchanged.

No compiler setting, deployment limit or accounting guard was relaxed. No new
assembly was added. Market ABI hashes match the original complete carry branch;
the extra slot and compatibility costs below remain.

| Market    | Counter fix | Original complete carry | Smaller complete carry | EIP-170 headroom |
| --------- | ----------: | ----------------------: | ---------------------: | ---------------: |
| Standard  |      23,611 |                  24,427 |                 23,998 |              578 |
| Revolving |      24,167 |                  24,983 |                 24,554 |           **22** |

The smaller candidate adds 387 runtime bytes over the counter-only branch.
These are measured deployment-profile artifacts under the unchanged settings.
Twenty-two bytes is a tight margin, not room for further functionality. Passing
the size limit does not approve this accounting change or its consumer rollout.

### Current verification

Final verification on the frozen candidate:

- `forge test --summary`: **906 passed, zero failed or skipped**, across 81 suites.
  Repayment and penalty invariants each run 2,000 sequences / 60,000 calls.
- `forge test --block-timestamp 1724284800 --fuzz-seed 0x5eed --fuzz-runs 10000
--match-path 'test/{market/WithdrawalRoundingCarry,lens/MarketAccountingReader,libraries/WithdrawalRemainderState,libraries/WithdrawalPaymentCapacity,libraries/BoundedMarketState}.t.sol'
-vv`: **22 passed, zero failed**. Each of the five fuzz tests runs 10,000 cases.
- `forge test --code-size-limit 24576 --match-path
'test/research/SingleStorageDeployment.t.sol' -vv`: **two passed**. Actual
  deployments exercise all six factory/market/hook combinations and periodic
  feature compositions, with runtime and code-storage limits enforced.
- `FOUNDRY_PROFILE=deploy forge build src/market/WildcatMarket.sol
src/market/WildcatMarketRevolving.sol --out final-deploy-out
--cache-path final-deploy-cache --skip test --skip script --sizes`: **passed**.
  Default and deployment market runtimes match byte for byte. Market ABIs match
  the complete-carry baseline.
- Independent integer arithmetic: **300,000 cases** compare the old affordability
  calculation with the direct inverse, assert maximality, and compare reserve
  formulas at endpoints and intermediate ratios, including huge donations.
- Changed Solidity and documentation pass Prettier; `git diff --check` passes.

The initial full run had 905 passes and one failure in the old invalid-state
reference: at 0% it accepted pending above total supply. The updated independent
reference checks the partition subtraction at every ratio; the explicit invalid
state test now covers 0%, 50% and 100%. Valid-state comparisons retain the old
endpoint formulas. No production guard was removed to make that test pass.

New tests call the real payment helper through `WithdrawalPaymentHarness`. They
cover exact funded price, maximal affordable burn, debt conservation, zero/one-unit
liquidity, maximum factors, uint256-max donations, wide cumulative counters with
small live differences, and checked liability failures. The original fragmentation
and closure regressions still pass across both market and hook types. Reports,
logs, comparison source and size hashes are retained locally under
`artifacts/withdrawal-rounding-size/` in the same persistent artifact collection
as the original experiment.

### Protocol correctness review — 2026-09-29

The follow-up review adds independent accounting checks without changing
production source or its measured runtime. The payment identity is:

```text
S = live shares, F = factor, G = aggregate carry, U = funded unclaimed units
k = shares burned, r = old batch carry, R = RAY
p = floor((k*F + r) / R), r' = (k*F + r) mod R

G' = G - r + r' = G + k*F - p*R
S'*F + G' = (S-k)*F + G + k*F - p*R = S*F + G - p*R
U' = U + p
```

Removing an integer multiple of R before half-up normalization, then adding the
same integer to U, preserves total debt exactly. The same identity applies to
pending shares, so both normalized pending and total supply decrease by p.
Their difference is unchanged. Required reserves therefore also stay unchanged
at a fixed factor, for every reserve ratio. Repayment changes backing assets;
allocation itself cannot create or erase a reserve obligation.

For closure, let X be the prior batches' unsettled numerator and Y the current
batch's unsettled numerator, each including its own carry. Then:

```text
roundHalfUp((X+Y)/R) - roundHalfUp(X/R) >= floor(Y/R)
```

Consequently cash equal to recorded debt covers a complete current-batch payment
while protecting prior batches. A FIFO payment likewise fits the free cash when
total debt is backed. Payments conserve debt; final fraction release lowers it
by at most one atom and never raises required reserves at ratios from 0% through
100%. These properties establish the accounting basis for closing without an
extra funding unit. They do not prove every contract entrypoint or lifecycle path.

The argument depends on these maintained invariants:

- Aggregate carry equals the sum of all retained batch carries; each is below R.
- A batch's live unpaid difference is part of pending supply, bounded by live
  uint104 supply. Its cumulative counters may independently exceed uint104.
- The factor is positive, starts at R and does not decrease. Burned fractions
  do not subsequently earn interest.
- Funded unclaimed withdrawals include every paid unit less executed claims;
  carry is an additional unfunded fractional liability.
- Release occurs only when the batch is fully paid and cannot accept requests.

With uint104 live shares and a uint112 factor, products fit below 2^216. The
inverse branch bounds liquidity by the full batch price before multiplying it
by R. At most 2^32 distinct expiry buckets bound aggregate carry below 2^122.
These width arguments, checked liability mutations and source lifecycle rules
connect the mathematical integer identities to the implementation.

Added checks:

- The six-cell market invariant now checks the summed carry and sub-R batch
  bounds alongside pending shares, funded liabilities, account allocations and
  actual claims. A fixed-seed run passed 2,000 sequences / 60,000 actions.
- `WithdrawalCarrySequence.t.sol` uses an independent exact-numerator ledger
  and binary-search affordability oracle. It checks three batches through cash
  additions, factor increases, growing requests, partial payments and terminal
  release, then funds exactly its independently reconstructed debt and finishes
  all batches. It also tests a paid current batch growing again with its fraction
  retained. The final run passed 10,000 sequences of 32 generated actions.
- The capacity fuzz now checks reserve conservation with free supply, another
  batch's carry, fees and varying reserve ratios, for 10,000 cases.
- The hook test creates carry through real interest accrual and verifies the
  nonzero final state word and arbitrary trailing data through repayment,
  repayment/FIFO processing and manual closure, for both market types. It passed
  10,000 cases, without injecting storage.
- Z3 5.1.0 finds no counterexample to 16 arithmetic lemmas under explicit
  premises: conservation, affordability, overflow bounds, funding, reserve
  partition/monotonicity and final-release bounds. These are proofs about the
  mathematical formulas, not Solidity/EVM program equivalence or an independent
  external review. The exact script and output are retained in
  `artifacts/withdrawal-carry-validation/`.

`forge test --summary --fuzz-seed 0xc414`: **910 passed, zero failed or skipped**
across 82 suites, including the strengthened market, repayment and penalty
invariants. Production source is unchanged from `5800b64`; runtime hashes still
match that candidate and its deployment build. This pass found no new accounting
failure. It is additional source/test evidence, not release approval or a proof
of the entire protocol.

### Alternatives and remaining decision

| Option                                                 | Consequence                                                                                                                                                       |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Complete carry, with the size reductions above         | Retains each payment fraction and conserves debt. Requires the additional aggregate slot, new hook inputs and consumer accounting changes.                        |
| Counter fix alone, retaining the rounding issue        | Keeps the original rounding behavior and avoids the carry's additional state/hook migration. Counter-width reader compatibility still needs the assessed updates. |
| Round each payment up                                  | Replaces repeated underpayment with repeated overpayment. Simply changing the payment rounding does not reconcile closure debt.                                   |
| Reserve an extra whole unit for each retained fraction | Can conservatively fund payments, but overstates liabilities/reserves and can change delinquency or closure timing, particularly for low-decimal assets.          |
| Fund only complete batches                             | Reduces fragmentation but delays lender access; shares left unburned continue earning interest. This changes market economics.                                    |

For a concrete round-up counterexample, two expired one-share batches at factor
1.1 have combined half-up debt of two units, but independently ceiling each
payment requires four. A payment-only change would therefore still break closure.

The recommended next step is to review this as a candidate, not deploy it merely
because it fits. Per-lender pro-rata floor dust remains: integer ERC20 units cannot
represent every fractional entitlement. The carry changes bound the discarded
payment fraction per completed batch; they do not promise exact per-lender payouts.
The protocol decision remains open. The stack follows the selected protocol;
its future migration is not a reason to retain an incorrect immutable design.

## Maintenance checkpoint — 2026-09-29

Historical checkpoint, before the size work above. Work paused at the user's
request for machine maintenance. Implementation and
tests are committed locally; no changes have been pushed or deployed, and the
umbrella submodule pin has not been updated.

| Remediation                                    | Saved revision                                                                                                                   | Status                                                                                                                                                                                                                                       |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F-03: cumulative withdrawal-counter exhaustion | `experiment/withdrawal-counters-128` at `23c47cde20c60d42c8e7a6aa1d4639968e45f9fb`                                               | Implemented and validated locally. Cumulative counters widen to uint128 without additional storage slots. The 887-test suite passed in default and deployment configurations; revolving runtime retains 409 bytes of headroom. Not deployed. |
| Repeated partial-payment rounding              | `experiment/withdrawal-rounding-carry` implementation at `3ea7a25567f135841d6cd2673b60facb0849a0bb`, followed by this checkpoint | Complete accounting experiment; 896 tests pass, with three size-gate failures. Deployment blocked by the revolving runtime exceeding EIP-170 by 407 bytes. Detailed costs and evidence below.                                                |

The original rounding and counter-only branches remain independently available.
Committed implementation,
tests and this assessment do not depend on temporary worktrees surviving a
restart. Raw verification reports, logs and the patch are also retained in the
local persistent Codex Security artifact collection under
`artifacts/withdrawal-counters-128/` and `artifacts/withdrawal-rounding-carry/`.

At this checkpoint the choice was whether to recover bytecode space, try a smaller
alternative, or retain the known issue. The smaller candidate above addresses the
size gate. Neither experiment is an approved release. SDK/subgraph migrations remain unimplemented;
their required accounting changes are described below. Existing market behavior
and known-issue dispositions have not been changed by deployment.

The broader task is to revisit known issues whose rationale assumed approved
underlying assets, then assess other reasonably supportable ERC20 quirks.
Arbitrary ERC20 admission has always been possible, including V2.0. Rebasing,
fee-on-transfer and explicitly malicious token behavior remain unsupported.
Continue that review after the withdrawal-remediation decision; the broader
assessment is not complete. Work remains solo, and replacement lenses must
continue reading older market generations even when consumers migrate SDKs.

## Accounting

Each batch retains a ray numerator `paymentRemainder < RAY`. A payment adds
`burnedShares * currentScaleFactor`, funds the integer quotient and stores the
fraction. This respects the factor at each actual burn; burned shares and their
fraction do not continue earning interest.

`MarketState.withdrawalRemainder` is the sum across batches that still retain a
fraction. The shared debt calculation becomes:

```text
roundHalfUp((liveScaledSupply * scaleFactor + sumOfRemainders) / RAY)
  + fundedUnclaimedWithdrawals + protocolFees
```

Reserving a payment subtracts its whole-unit value from the combined numerator
and adds the same value to funded withdrawals. Debt is conserved at that factor.
Required reserves include the fraction at full weight; the reserve ratio still
applies only to live shares outside withdrawals. Pending-batch liquidity protects
other batches' remainders without counting the current batch's fraction twice.

Only whole funded units enter `normalizedUnclaimedWithdrawals`. Final lender
entitlements retain the existing cumulative pro-rata calculation. When a batch
is fully paid and cannot accept new entries, its final fraction is released.
This discards less than one atomic unit for the batch's lifetime, rather than
one per payment. Fraction release can leave whole-unit surplus from rounded
closure funding; the existing closed-market `rescueTokens` path returns only
surplus above the remaining carry-aware debt.

The aggregate fits uint128: at most 2^32 distinct uint32 expiry keys, each
contributing less than RAY, bound it below 2^122. Payment products use uint104
live shares and a uint112 factor, below 2^216. Cumulative normalized payments
retain their existing checked uint128 limit.

## Concrete correction

Four shares at factor 1.25 are worth five units. A first payment of three burns
three shares and retains 0.75. The old debt calculation reports four units total;
the carry-aware calculation reports five. Manual closure therefore collects two
more units and pays the final share together with the 0.75, without leaving an
unpaid share. The earlier carry-only prototype reverted in this case.

## Original implementation costs and shared compatibility

Using the unchanged solc 0.8.25, Cancun, via-IR, runs-1 and pinned optimizer settings:

| Market    | Counter-fix base | Carry implementation | EIP-170 margin |
| --------- | ---------------: | -------------------: | -------------: |
| Standard  |           23,611 |               24,427 |            149 |
| Revolving |           24,167 |               24,983 |   **407 over** |

The original added runtime was 816 bytes and exceeded the available 409-byte
revolving margin. The smaller candidate above fits. Unit tests use Foundry's normal test
configuration; their success does not mean an oversized runtime can be deployed.

- Batches remain two storage slots; their second slot now holds two uint128s.
- The market gets one additional storage slot for the aggregate remainder.
  State reads/writes include that word; this also shifts subsequent storage slots.
- State tuples grow from 14 to 15 words and batch tuples from three to four.
  Hook selectors and calldata sizes change with the state tuple. Existing hook
  deployments cannot serve these new markets without matching implementations.
- Lens readers accept old and new tuples with checked decoding. Lens output
  tuple layouts are unchanged by the carry experiment itself.
- SDK `e64e766` still derives `totalDebts` and indexed reserve coverage without the
  fraction (`src/market.ts`). Adoption needs a new read/calculation path, not just
  ABI regeneration.
- Subgraph `584e5de` likewise calculates debt/reserves without carry (`src/utils.ts`).
  Existing payment events still describe actual funded amounts correctly, but
  indexing the new fractional liability needs an explicit source. This experiment
  does not add a remainder event or migrate the indexer.

The known issue for existing immutable markets remains. The patches are concrete
comparison points for deciding whether to adopt carry accounting for new markets
or keep accepting the existing rounding behavior.

## Original complete-carry verification

The focused suite covers the original payment-fragmentation loss, the closure
regression, several concurrent batch remainders, changing factors, terminal
fraction release, automatic closure and protection against surplus rescue.
A separate lens suite exercises legacy/extended responses and malformed data.

The counter-fix base reproduces the original loss: ten shares at a factor of 1.1,
funded by eleven one-unit repayments, reserve only ten units for withdrawal. The
new regression reserves eleven. The four-shares/five-units closure case also
passes for both market types and both open- and fixed-term hooks.

Checks at the original complete-carry checkpoint:

- `forge test --summary`: **896 passed, three failed**. All three failures are
  the unchanged deployment-size gates in `RepaymentPrototype.t.sol` and
  `SingleStorageDeployment.t.sol`; no accounting or lifecycle tests fail.
  Repayment and penalty invariant suites each exercise 2,000 runs / 60,000 calls.
- `forge test --block-timestamp 1724284800 --fuzz-seed 0x5eed --match-path
'test/{market/WithdrawalRoundingCarry,lens/MarketAccountingReader,libraries/WithdrawalRemainderState}.t.sol'
-vv`: **12 passed**, including 1,000-case payment and reserve fuzz tests.
- Independent integer-arithmetic checks: 200,000 randomized multi-batch cases
  satisfy payment debt conservation, sufficient funding for pending batches and
  the bound on debt released with a final fraction.
- ABI comparison against the counter fix: market input selectors and event
  signatures unchanged; state/batch return tuples and hook inputs changed;
  the four lens contracts' public input and output layouts unchanged.
- Storage layout: five slots for market state, two for each batch. Updated
  transition-memory, hook-calldata and white-box storage tests pass.
- Changed Solidity files pass Prettier; `git diff --check` passes.
- `FOUNDRY_PROFILE=deploy forge build --skip test --skip script --sizes`:
  compilation succeeds, then the size check fails. Market and lens runtimes
  match the default profile byte for byte, including the 24,983-byte revolving
  market. No compiler setting was relaxed to make the experiment fit.

The post-implementation review found and corrected an intermediate reserve-ratio
edge case: computing outstanding supply without the same fractional offset as
pending supply could make 99.99% reserves exceed 100%. Both partitions now use
the same offset, with a deterministic regression and a monotonicity fuzz test.
Old lifecycle scenarios that relied on rounding erasing a final unpaid unit now
require that unit to be repaid before closure.

Original outcome: **blocked for deployment by code size**. The smaller candidate's
size result is recorded above. Consumer migrations are assessed but not implemented;
there has been no deployment or independent external review.
The original known issue remains accepted for existing immutable markets.
