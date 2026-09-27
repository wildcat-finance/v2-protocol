# Market lenses

[`MarketLens`](../../src/lens/MarketLens.sol) forwards reads to separate
[core](../../src/lens/MarketLensCore.sol),
[aggregation](../../src/lens/MarketLensAggregator.sol), and
[live-data](../../src/lens/MarketLensLive.sol) helpers. Deploy the facade and
helpers from the same source and compiler configuration. The facade forwards
their exact return bytes; it does not translate between ABI generations.

Use the ABI for the deployed lens address. These return tuples include new
nested fields even where the input selector is unchanged. Regenerate SDK and
application decoders when adopting this lens deployment. Reading older
contracts does not make its return ABI compatible with an older lens ABI.

This includes the common `getMarketData` result used for V2.0/V2.1 markets:
its nested `MarketHooksData` changed too. Common market arrays, lender-paired
results, and aggregation results containing these types need the new decoder,
as do hook-instance and template metadata. Regenerate the lens bindings as a
whole, including integrations that only read older markets. Previously deployed
lenses retain their own ABIs.

## Choosing a read

| Need | Interface |
| --- | --- |
| Full V2.5 configuration, hook metadata, borrower identity, canonical wrapper, and current accounting | `getMarketDataV2` or `getMarketsDataV2` |
| Frequent accounting, repayment/default, and available-liquidity refreshes | `getMarketsLiveDataV2` |
| The same compact data with lender balances and access status | `getMarketsLiveDataWithLenderStatusV2` |
| V2.5 markets discovered by template | `getAllMarketsDataV2ForHooksTemplate`, its paginated form, or `getAggregatedAllMarketsDataV2ForHooksTemplate` |
| Lender batch claims and amounts currently collectible | `getWithdrawalBatchDataWithLenderStatus` and its batch/lender array forms |
| Template commitments and fees with factory provenance | `getAggregatedHooksTemplatesForBorrowerWithFactory` or an explicit-factory template query |

The common `getMarketData` tuple and its lender-paired variants remain for
markets with the common V2 interfaces. Use the V2.5 full or live routes for
`lifecycle` and `liquidity`; the common tuple does not contain those additions.
Strict batch reads preserve input order and revert if any required read fails.
Cross-factory discovery retains its existing failure-isolation and
deduplication behavior.

## Repayment and default

Both full and live V2.5 results contain the same `MarketLifecycleData`:

| Field | Meaning |
| --- | --- |
| `isPresent` | All four lifecycle getters returned complete words. False means the data is unavailable, including on older markets; it does not mean there are no repayment terms. |
| `repaymentDate` | Immutable date from the market; zero disables scheduled repayment. |
| `repaymentPeriod` | Immutable period in seconds. Zero is valid with a nonzero date. |
| `repaymentDeadline` | The market's inclusive deadline, or zero without repayment terms. |
| `defaultedAt` | Permanent timestamp already recorded by a market state update. Zero means no default has been recorded yet. |
| `isInRepayment` | The date has arrived and accrued market state is not closed. Closing ends this phase without erasing the terms or default marker. |

These fields deliberately mix immutable terms, a committed marker, and a
current phase view. After an unpaid deadline passes, `defaultedAt` can still
be zero until the next state update records it. The lens does not recreate
historical default logic or treat zero as proof that the deadline was met.
Likewise, `isClosed` can already be true in an accrued view before closure has
been written. Default itself does not imply closure.

Markets without repayment terms still return `isPresent == true` when these
getters exist. They can record a default from a consecutive penalty run.

## Capacity and surplus

`MarketLiquidityData` is also shared by the full and live results:

- `maximumDeposit`, `borrowableAssets`, and `totalDebts` come directly from the
  market's current getters. This includes the repayment-date gates and all
  lender and protocol-fee liabilities.
- `recoverableUnderlying` is assets above `totalDebts` when accrued state is
  closed, and zero otherwise. It matches the accounting amount available to
  the borrower's underlying-asset `rescueTokens` call; paid but uncollected
  withdrawal claims remain protected.

Amounts are denominated in underlying-asset units. They describe accounting
capacity, not permission: borrower authority, lender access, sanctions, hook
validation, and token transfers can still prevent an action. In particular,
the lens does not promise that a surplus transfer will succeed.

The full tuple's `registeredWrapper` is the market's canonical
[ERC-4626 wrapper](./erc-4626-wrapper.md). It is not a tranche-vault address.
Existing APR, reserve, commitment-fee, drawn-principal, and borrower-identity
fields remain available. Senior APR, tranche floors, shares, and waterfall
state belong to later V2.6 contracts and are not inferred here.

## Hook policies and artifact commitments

Known hook families expose their existing access and term settings through
`market.hooksConfig`. Periodic hooks additionally expose
`periodicWithdrawalWindowOpen` and `pendingAprChange`:

- `pendingAprChange.isPresent` identifies support for the four-word proposal
  getter. `proposalTimestamp == 0` means there is no proposal.
- `annualInterestBips`, `proposalTimestamp`, `responseWindowStart`, and
  `responseWindowEnd` come from `getPendingAprChange`. The bounds are those
  fixed at proposal creation. An expired proposal can remain readable.
- Older hooks without that getter return an absent proposal bundle. The lens
  does not reconstruct historical bounds from the current schedule.
- The withdrawal-window and closure values come from the hook's current
  queries, including repayment-date behavior. A window being open does not
  prove lender authorization.

`market.hooks.constraints` supports both the original ten-word constraints
and the current twelve-word constraints. `repaymentConstraintsAvailable` is
true only for the latter. Older hooks retain their original bounds, with zero
in the two new slots; check the flag before interpreting those zeros as limits.
Incomplete tuples and out-of-range integer encodings revert. Unknown hook
families keep their typed configuration empty.

`HooksTemplateData.initCodeHash` contains the factory-registered commitment to
the **decoded creation code before instance constructor arguments**, with an
`isPresent` flag for getter support.
This is distinct from a store's runtime hash or a deployed hook instance's
runtime hash. Check `exists` and `enabled` separately: support for the getter
does not prove that a template is registered or enabled.

The same template address can have different records at different factories.
Use factory-scoped results when retaining commitments and fees. Deduplicated
results still select the first record encountered; they are not a consensus
across factories. A version string alone does not identify verified code.

## Withdrawal reads

`normalizedAmountOwed` reports the lender's outstanding batch claim, including
unpaid amounts. `availableWithdrawalAmount` reports the already funded portion
that can currently be collected under the market's timing rules. It is zero
while the batch is pending, even if assets have been reserved for it.

Automatic closure can fully fund and release the current batch before its
scheduled expiry. The lens then reports it as `Complete` and exposes the
collectible amount, including when closure is still an accrued view. An
expired but not yet stored batch remains `Expired`; an older partially funded
batch is `Unpaid`. Unknown batch keys retain the empty, zero-claim result.

These are amounts owed to the lender. Sanctions may redirect collection into
escrow. Reading a collectible amount does not guarantee that an arbitrary
asset's transfer succeeds. See [withdrawals](../protocol/withdrawals.md).

## Tests

- [`MarketLensDeployment.t.sol`](../../test/lens/MarketLensDeployment.t.sol):
  a small harness that deploys all four lens contracts and checks forwarding
  against both real market families with `--code-size-limit 24576`
- [`MarketLensLifecycle.t.sol`](../../test/lens/MarketLensLifecycle.t.sol):
  both real factories and all three term templates, repayment/default
  boundaries, zero periods, automatic closure, protected surplus, periodic
  proposals, and full/live/aggregation/facade propagation
- [`MarketLensOptionalData.t.sol`](../../test/lens/MarketLensOptionalData.t.sol):
  legacy constraint tuples, malformed responses, integer-width validation,
  missing lifecycle/proposal getters, and valid zeros
- [`MarketLensCore.t.sol`](../../test/lens/MarketLensCore.t.sol),
  [`MarketLensAggregator.t.sol`](../../test/lens/MarketLensAggregator.t.sol), and
  [`MarketLensFacade.t.sol`](../../test/lens/MarketLensFacade.t.sol): common
  reads, lender accounts, discovery, factory-scoped commitments, optional
  probes, and forwarding behavior
