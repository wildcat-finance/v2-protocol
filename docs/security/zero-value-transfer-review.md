# Zero-value transfer compatibility review

Reviewed on 2026-09-29 against
`e7ff6c7bd83045616932084f8d7bd87933864c58`, which inherits the paused withdrawal
experiments and the selected metadata candidate. This review adds tests and
documentation only; it does not select those experiments for release or change
production behavior. Local source/tests are not deployment evidence.

CAF-15 accepted metadata and zero-transfer compatibility under an asset-listing
assumption. Arbitrary underlying ERC-20 assets have always been allowed. The
historical disposition remains intact; this note reassesses the zero-transfer
part. Rebasing, fee-on-transfer and dishonest balance accounting remain outside
supported behavior.

## Finding and scope

Both `HooksFactory._deployMarket` and
`HooksFactoryRevolving._deployMarket` call `safeTransferFrom` whenever the
supplied origination-fee asset is nonzero, including when the configured fee
amount is zero. The arguments must first match the template's fee asset and
amount exactly.

This unnecessarily couples a free deployment to the fee token's transfer
behavior. A token rejecting zero amounts causes deployment to fail. There is
also a permitted configuration with a nonzero fee token, zero amount, zero
protocol fee and zero recipient: a token rejecting a zero recipient then blocks
deployment even if it accepts zero amounts. Both failures surface as
`TransferFromFailed()`.

The fee token is configured by the template owner and need not be the deposit
asset. This is not evidence that an arbitrary deposit asset rejecting zero
amounts breaks ordinary lending. Clearing the configured fee asset when no
origination fee is due is an existing administrative workaround.

The same amount-insensitive transfer guard is present in source tags `v2.0.0`
and `v2.1.0`. That comparison does not establish deployed code or historical
exposure.

## Recommended narrow change

In both factories, transfer only when `runtimeParams.originationFeeAmount != 0`.
The existing exact fee-match check remains before the guard. Template validation
already requires a nonzero token and recipient for a positive origination fee.
Positive fee collection therefore retains its current validation and transfer.

Preserve hooks creation and `onCreateMarket`, deployment events and recorded
fee asset/amount, including a configured token with amount zero. The intentional
observable difference is that no external token call or token `Transfer(0)` log
occurs for a zero origination fee. Do not replace the token address with zero in
deployment arguments or events: exact configuration matching still matters.

This proposal changes factories only: no market runtime budget, market storage,
ABI tuple or event-schema change. Factory bytecode and behavior still require
verification after implementation; no candidate size is claimed here. Existing
deployed factories would retain the old behavior.

At `subgraph@584e5de`, V2.5 fee configuration is indexed from
`MarketDeploymentConfig` in `src/hooks-factory-v2-5.ts`, rather than inferred
from a fee-token transfer. At `wildcat.ts@e64e766`,
`src/access/access-control.ts` requires fee balance/allowance only for a positive
amount and sends the configured token and amount to either factory route.
Those paths need no interface change for the proposed guard. This is a scoped
source inspection, not a full SDK/app integration test; no consumers changed.

## Other transfer callers

| Caller | Current zero behavior | Recommendation |
| --- | --- | --- |
| Deposit, standalone repay, fee collection, executed withdrawal payout | Reject zero before the transfer; deposits also reject a rounded-to-zero mint. | Retain. |
| `repayAndProcessUnpaidWithdrawalBatches(0, ...)` | Already skips both the repayment transfer and repayment hook while processing batches. | Retain the process-only mode. |
| Market closure | Repays only a shortfall and returns only an excess. | No zero-transfer change needed. |
| `borrow(0)` | Subject to normal access/lifecycle checks, then runs its hook/state/event path and transfers zero. | Leave unchanged in this narrow proposal. Skipping the token call would require deliberate preservation of the rest of that behavior. A token rejecting zero does not thereby reject positive draws. |
| `rescueTokens` with no recoverable balance | Can attempt a zero transfer, including closed-market underlying rescue. | Optional convenience improvement; failure of an empty rescue alone is not evidence that positive payouts fail. Avoid spending scarce market bytecode here without a separate reason. |
| `WildcatSanctionsEscrow.releaseEscrow()` when empty | Can attempt a zero transfer and emit a zero release. | Optional convenience improvement, separate from the factories; a funded escrow uses a positive transfer. |
| ERC-4626 wrapper actions/sweep | Zero actions/surplus are rejected before transfer; regular actions transfer market tokens, not the underlying arbitrary asset. | Retain. Do not change public token-transfer semantics. |

Do not make `LibERC20` globally suppress zero calls. Different callers have
different hook, event and validation contracts; this factory issue has a local
solution.

## Verification

```sh
forge test --match-path test/factories/ZeroValueTransferReview.t.sol -vv
```

All five characterizations passed with Solidity 0.8.25 and the existing Foundry
profile. Each covers both standard/revolving factories and both existing-hooks
and atomic hooks-plus-market deployment routes:

- Zero-rejecting fee token blocks a zero-fee deployment.
- A token accepting zero amounts but rejecting a zero recipient blocks the
  permitted zero-fee/null-recipient configuration.
- Positive fees transfer the exact amount on each deployment, consuming the
  expected allowance and leaving the expected recipient/borrower balances.
- A zero fee with no fee token deploys successfully without an ERC-20 transfer.
- Fee mismatch is rejected before attempting the transfer.

The fixture uses real factories, markets and open-term hooks and a conventional
balance-accounting token with explicit transfer rejection rules. The tests
characterize existing behavior; they are not proof of remediation. Formatting
and diff checks passed. No full-suite run is needed for these tests/docs alone;
an implementation would need corresponding success assertions and relevant
factory regression checks.
