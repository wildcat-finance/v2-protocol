# Glossary

These terms describe supported V2.5 behavior. Names in `code` match the source.
Rates use basis points (`bips`); 10,000 bips is 100%.

For the mechanics, see [markets](./markets.md),
[accounting](./accounting.md), [scaling and rounding](./scaling-and-rounding.md),
[withdrawals](./withdrawals.md), and
[borrower identity](./borrower-identity.md).

## Authority and identity

### ArchController

The registry and permission boundary for borrower principals, approved
deployment components, markets, and blacklisted assets.

Wildcat Foundation is a separate entity that manages KYC/KYB and registers or
removes borrower principals. Wildcat Labs has no administrative control over
the ArchController.

### Borrower

The legal and economic counterparty using a Wildcat credit facility. The source
uses more specific terms when it needs to distinguish the legal principal from
the address operating a market.

### Borrower principal

The registered legal borrower stored by `market.borrowerPrincipal()`. It is the
lender-facing namespace for sanctions checks and new sanctions escrows.

### Operational borrower

The address returned by `market.borrower()`. This exact address can call
borrower-only market functions. Supported V2.5 markets keep
`borrower() == borrowerPrincipal()` at origination and after transfer.

### Borrower Account

A contract account associated with a registered principal through the borrower
identity registry. The account-aware path exists in source and ABI, but no
supported V2.5 factory or deployment uses it. It is planned for V2.6.

### Lender

A counterparty that supplies the market's underlying asset. A lender account
may own market tokens, withdrawal-batch shares, or both.

## Markets and access

### Market

An isolated lending facility for one borrower principal and one underlying
asset. It accepts lender deposits, issues market tokens, and makes credit
available to the operational borrower under its reserve and withdrawal rules.

### Standard market

A `WildcatMarket` instance. While open, it accrues `annualInterestBips` on the
full supply.

### Revolving market

A `WildcatMarketRevolving` instance. While open, it pays a fixed commitment fee
on the full supply and annual interest on the lesser of `drawnAmount` and total
supply. Explicit borrows and repayments change `drawnAmount`; raw underlying
transfers do not.

### Underlying asset

The ERC-20 chosen when a market is deployed. Implementing ERC-20 does not make
an asset compatible or supported by itself. Token behavior and deployment
policy still matter.

### Market token

The ERC-20-compatible lender claim issued by a market. Balances are stored in
scaled units and reported in normalized units. Queueing a withdrawal moves
scaled ownership into a batch; payment burns it.

### Hooks template

An implementation approved by a hooks factory as the basis for new hook
instances. The factory records whether it is available and how its fees are
configured, plus an immutable hash of its original creation code. A split
template still has one primary address in the factory registry.

### Hooks instance

A contract attached to a market that implements its enabled callbacks. Those
callbacks can validate, constrain, or account for specific market actions.

### Role provider

A credential source used by access-control hooks. It may push credentials, be
queried, or validate caller-supplied data. Credential lifetime belongs to each
hook attachment. Administration depends on the provider.

### Sanctions sentinel

The contract that wraps the sanctions oracle, applies borrower-scoped lender
overrides, and derives sanctions escrows.

### Sanctions escrow

A contract that holds underlying owed to a sanctioned lender after a paid
withdrawal is executed. The assets become releasable if the oracle clears the
account or the borrower adds an override.

### Vault

An ERC-4626 contract, including the canonical Wildcat wrapper where applicable.
Current documentation does not use _vault_ as another name for a Wildcat
market.

## Balances and capacity

### Scaled amount

An ownership unit that stays fixed while interest accrues. The current scale
factor converts it into a normalized amount using the operation's defined
rounding.

### Normalized amount

An underlying-denominated value derived from a scaled amount and the current
scale factor. It is a claim value, not necessarily underlying the market
currently holds.

### Scale factor

The conversion rate from scaled to normalized amounts. Lender rates increase
it. In a revolving market, that includes the commitment fee. Delinquency fees
also increase it; protocol fees accrue separately.

### Total supply

The normalized value of `scaledTotalSupply`. It includes ownership in current
and expired unpaid withdrawal batches until payment burns those shares. It is
not the market's underlying balance.

### Outstanding supply

Supply outside current and expired unpaid withdrawal batches. The reserve
calculation derives its normalized value by subtracting carry-aware pending
debt from carry-aware total lender debt, so both sides share the same rounding
domain. See [accounting](./accounting.md#collateral-obligation).

### Total debt

`totalDebts()`, the full funding obligation. It combines live scaled supply and
retained withdrawal-payment fractions before rounding, then adds paid but
unclaimed withdrawals and accrued protocol fees. It is not simply
`totalSupply()` plus funded claims and fees.

### Capacity

`maxTotalSupply`, the cap used for new deposits. Interest can move total supply
above the cap, and the borrower can lower the cap below current supply. It does
not limit withdrawals.

## Credit, liquidity, and fees

### Borrow and repay

`borrow(amount)` sends available underlying to the operational borrower.
`repay(amount)` moves underlying from its caller into the market and is not
borrower-gated.

In revolving markets, only explicit borrows and repayments change
`drawnAmount`. A raw token transfer is a donation.

### Reserve ratio

`reserveRatioBips`, the fraction of outstanding supply included in the market's
required liquid balance.

### Collateral obligation

`liquidityRequired()`, the minimum underlying balance for a healthy market. It
includes pending withdrawals and retained payment fractions, paid but unclaimed
withdrawals, reserve coverage for outstanding supply, and accrued protocol fees.

### Delinquency

The state where the market's underlying balance is below
`liquidityRequired()`. `timeDelinquent` rises during a shortfall and decays while
the market is healthy. The penalty rate applies while that timer exceeds
`delinquencyGracePeriod`.

Scheduled repayment removes unused grace while the market is underfunded.

### Repayment date and deadline

Optional immutable market terms. The date starts the full-funding obligation,
100% reserves and immediate underfunded penalty. The deadline is that date plus
the repayment period, inclusive. These terms are separate from hook maturity
and withdrawal windows. See [repayment and default](./repayment-and-default.md).

### Default marker

`defaultedAt`, a permanent recorded timestamp. It identifies the first missed
repayment deadline or uncured 90-day penalty cutoff. It does not itself change
market permissions, rates or closure. Zero means no default has been recorded.

### Closure

Permanent funded settlement that stops interest and penalty accrual. It can be
requested manually or occur automatically once a scheduled market is fully
funded at or after its repayment date. Lender collection and surplus recovery
continue; lending and borrowing do not resume.

### Interest and fees

- `annualInterestBips`: the base annual rate paid to lenders
- `commitmentFeeBips`: the fixed rate paid on the full supply of a revolving
  market
- `delinquencyFeeBips`: the extra lender rate during penalized delinquency
- `protocolFeeBips`: the protocol's share of base interest, charged on top of
  lender interest and accrued separately

## Withdrawals

### Withdrawal request

An instruction that moves scaled ownership from a lender into the current
withdrawal batch. Queueing does not burn it or reduce total supply.

### Withdrawal batch

The shared accounting unit for requests made during one withdrawal period. A
batch can be current, expired and unpaid, or paid. Expired unpaid batches get
liquidity in FIFO order. Lenders inside a batch share its allocation pro rata by
scaled ownership.

### Withdrawal payment

The reservation of underlying for a batch. Payment burns the batch's scaled
market-token ownership, stops its interest accrual, and records the underlying
as unclaimed withdrawals.

### Withdrawal payment remainder

The fraction below one underlying atomic unit retained between batch payments.
`WithdrawalBatch.paymentRemainder` stores it as a ray numerator;
`MarketState.withdrawalRemainder` sums the retained fractions across batches.
They remain non-interest-bearing debt until funded or released when a fully
paid batch can no longer accept requests.

### Withdrawal execution

The transfer of a lender's share from a paid batch after expiry or closure
releases the batch. Anyone can execute for an account and batch. Assets owed to
a sanctioned account go to its sanctions escrow.
