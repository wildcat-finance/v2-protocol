# Withdrawal rounding carry experiment

Status: local experiment branching from the cumulative-counter fix
`23c47cde20c60d42c8e7a6aa1d4639968e45f9fb`. Not a deployment recommendation.

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

## Costs and compatibility

Using the unchanged solc 0.8.25, Cancun, via-IR, runs-1 and pinned optimizer settings:

| Market | Counter-fix base | Carry implementation | EIP-170 margin |
| --- | ---: | ---: | ---: |
| Standard | 23,611 | 24,427 | 149 |
| Revolving | 24,167 | 24,983 | **407 over** |

The added runtime is 816 bytes. Correcting accounting therefore exceeds the
available 409-byte revolving margin. Unit tests use Foundry's normal test
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

The known issue for existing immutable markets remains. The patch is a concrete
comparison point for deciding whether to find more space, design a less intrusive
alternative, or keep accepting the existing rounding behavior.

## Verification

The focused suite covers the original payment-fragmentation loss, the closure
regression, several concurrent batch remainders, changing factors, terminal
fraction release, automatic closure and protection against surplus rescue.
A separate lens suite exercises legacy/extended responses and malformed data.

The counter-fix base reproduces the original loss: ten shares at a factor of 1.1,
funded by eleven one-unit repayments, reserve only ten units for withdrawal. The
new regression reserves eleven. The four-shares/five-units closure case also
passes for both market types and both open- and fixed-term hooks.

Final checks on the experiment:

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

Outcome: **blocked for deployment by code size**. Consumer migrations are assessed
but not implemented; there has been no deployment or independent external review.
The original known issue remains accepted for existing immutable markets.
