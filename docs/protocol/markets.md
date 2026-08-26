# Markets

This document describes supported market configuration, implementations, and
borrower authority.

Make sure you understand the [scale factor](./scaling-and-rounding.md) before continuing.

## Market Configuration

Markets are configured with the following values:
- `asset` - The underlying asset for the market
- `name` - The name of the market (borrower-provided prefix + asset name)
- `symbol` - The symbol of the market (borrower-provided prefix + asset symbol)
- `borrower` - Current operational address allowed to borrow from and make changes to the market. In supported v2.5 markets, this is always the same address as `borrowerPrincipal`.
- `borrowerPrincipal` - Registered legal principal associated with the market and used as its lender-facing sanctions namespace. Separate storage supports the account-aware identity model planned for v2.6.
- `borrowerIdentityRegistry` - Registry used to resolve and validate transfer targets. V2.5 uses it for direct registered principals; account resolution is implemented in source but is not part of the supported v2.5 release.
- `feeRecipient` - Recipient of protocol fees
- `sentinel` - Chainalysis wrapper determining whether accounts are sanctioned
- `maxTotalSupply` - Cap on normalized market-token supply used to limit new deposits. It does not restrict withdrawals.
- `protocolFeeBips` - A fraction of `annualInterestBips` which accrues to the protocol (in excess of the rate paid to lenders, not subtracted from it). This is not affected by delinquency fees.
- `annualInterestBips` - The base interest rate set by the borrower. Accrues solely to lenders.
- `delinquencyFeeBips` - Penalty fee added to the interest rate when the borrower is delinquent for too long. . Accrues solely to lenders.
- `withdrawalBatchDuration` - The length of a withdrawal cycle.
- `reserveRatioBips` - The fraction of outstanding debt which the borrower is obligated to keep in liquid reserves.
- `delinquencyGracePeriod` - The amount of time a borrower has before incurring penalties for a delinquent market.
- `archController` - Registry for factory/controller/market deployments.
- `sphereXEngine` - Engine for SphereX integration which does security checks on transactions.
- `hooks` - The market's hooks policy and the address of the hooks instance.

## Market Types

V2.5 has two market implementations sharing the behavior described here:

- **Standard markets** (`WildcatMarket`): interest accrues on the full supply at `annualInterestBips`.
- **Revolving markets** (`WildcatMarketRevolving`): for revolving credit facilities. Lenders earn a commitment fee (fixed at deployment) on the full supply plus the APR on only the drawn portion: `commitmentFee + annualInterestBips * min(drawnAmount, totalSupply) / totalSupply`. Borrow and explicit repayment transitions reconcile drawn amount against outstanding debt. Raw underlying transfers are donations: they affect market liquidity but do not themselves reduce drawn principal. A later borrow cannot double-count donated or previously over-repaid liquidity as a new draw. No interest accrues while a revolving market is closed or empty.

Everything else — collateral obligations, delinquency, withdrawals, closure — is identical between the two.

Conversions between scaled and normalized amounts follow deliberate rounding directions as of v2.5; see [Scale Factor — Rounding](./scaling-and-rounding.md#rounding).

## Borrower Identity And Transfer

v2.5 stores the operational borrower separately from the registered principal and supports two-step direct-principal transfers. Supported v2.5 factories and deployments maintain `borrower == borrowerPrincipal` at origination and after transfer.

The source also implements an account-aware identity path in which a recognized contract account may operate a market for a separately recorded principal. That path is planned for v2.6 and is not part of the supported v2.5 release.

Only the current operational borrower can call borrower-only market functions. A Borrower Account can therefore enforce its own delegate policy before calling the market without adding delegate logic to the market itself.

Borrower changes use a two-step request and acceptance flow. The current borrower requests or cancels, and only the pending target accepts. Request and acceptance resolve the target through the borrower identity registry and apply current registration and raw sanctions checks. Acceptance changes borrower identity only; market accounting and lifecycle state remain intact.

The canonical ERC-4626 wrapper follows the market's live borrower and principal. Hooks and role providers do not transfer implicitly because they may be shared across markets and have separate authority domains.

See [Borrower Identity and Transfers](./borrower-identity.md) for the full state model, transfer cases, events, and integration requirements.

## Related Mechanics

- [Accounting and state updates](./accounting.md) covers collateral obligations,
  interest, fees, delinquency, and state transitions.
- [Withdrawals](./withdrawals.md) covers batch ownership, payment priority, and
  execution.
