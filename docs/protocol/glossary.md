# Glossary

These terms describe the supported v2.5 protocol. Identifiers in `code` match
the source. Rates use basis points (`bips`), where 10,000 bips is 100%.

For full mechanics, see [markets](./markets.md),
[accounting](./accounting.md), [scaling and rounding](./scaling-and-rounding.md),
[withdrawals](./withdrawals.md), and
[borrower identity](./borrower-identity.md).

## Authority and Identity

### ArchController

The protocol registry and permission boundary for registered borrower
principals, approved deployment components, deployed markets, and blacklisted
assets. Wildcat Foundation, a separate entity that manages KYC/KYB, registers
and removes borrower principals. Wildcat Labs has no administrative control
over the ArchController.

### Borrower

The legal and economic counterparty using a Wildcat credit facility. Because
the word is overloaded, source-facing documentation distinguishes the borrower
principal from the operational borrower address.

### Borrower Principal

The registered legal borrower identity recorded for a market and returned by
`market.borrowerPrincipal()`. It is the lender-facing namespace for sanctions
checks and new sanctions escrows.

### Operational Borrower

The exact address returned by `market.borrower()` and authorized for
borrower-only market actions. Supported v2.5 markets maintain
`borrower() == borrowerPrincipal()` at origination and after transfer.

### Borrower Account

A contract account associated with a registered principal through the borrower
identity registry. The account-aware path exists in the source and ABI, but no
supported v2.5 factory or deployment uses it. It is planned for v2.6.

### Lender

A counterparty that supplies the market's underlying asset. Onchain, a lender
account may hold market tokens, withdrawal-batch ownership, or both.

## Markets and Access

### Market

An isolated lending facility for one borrower principal and one underlying
asset. A market accepts lender deposits, issues market tokens, and makes credit
available to its operational borrower subject to its reserve and withdrawal
rules.

### Standard Market

A `WildcatMarket` instance. While the market is open, its
`annualInterestBips` rate accrues on the full supply.

### Revolving Market

A `WildcatMarketRevolving` instance. While the market is open, lenders earn the
fixed commitment fee on the full supply and the annual interest rate on the
lesser of `drawnAmount` and total supply. Explicit borrows and repayments
update `drawnAmount`; raw underlying transfers do not.

### Underlying Asset

The ERC-20 configured when a market is deployed. Implementing the ERC-20
interface does not by itself make an asset compatible or supported; token
behavior and deployment policy also matter.

### Market Token

The ERC-20-compatible lender claim issued by a market. Account balances are
stored in scaled units and reported in normalized units. Queueing a withdrawal
moves scaled ownership from the lender to a batch; payment burns it.

### Hooks Template

An implementation approved in a hooks factory as the basis for hooks
instances. The factory records its availability and fee configuration.

### Hooks Instance

A contract attached to a market that implements its configured callbacks.
Enabled hooks may validate, constrain, or account for specific market actions.

### Role Provider

A credential source used by access-control hooks. A provider may push
credentials, be queried, or validate caller-supplied data. Credential lifetime
is configured per hook attachment; provider administration is
provider-specific.

### Sanctions Sentinel

The contract that wraps the sanctions oracle, applies borrower-scoped
overrides to lender checks, and derives sanctions escrows.

### Sanctions Escrow

A contract that holds underlying assets owed when a paid withdrawal is
executed for a sanctioned lender account. The assets become releasable if the
oracle clears the account or the borrower applies an override.

### Vault

Not a synonym for a Wildcat market in current documentation. It refers to an
ERC-4626 contract, including the canonical Wildcat wrapper where applicable.

## Balances and Capacity

### Scaled Amount

An internal ownership unit that remains stable while interest accrues.
Multiplying it by the current scale factor produces a normalized amount,
subject to the operation's specified rounding direction.

### Normalized Amount

An underlying-denominated value derived from a scaled amount and the current
scale factor. A normalized claim is not necessarily underlying currently held
by the market.

### Scale Factor

The conversion rate from scaled to normalized amounts. The applicable lender
rate increases it; for revolving markets, that rate includes the commitment
fee. Delinquency fees also increase it. Protocol fees accrue separately and do
not.

### Total Supply

The normalized value of `scaledTotalSupply`. It includes ownership assigned
to current and expired unpaid withdrawal batches until payment burns that
ownership. It is not the market's underlying-asset balance.

### Outstanding Supply

Total supply excluding ownership assigned to current and expired unpaid
withdrawal batches. The reserve ratio applies to outstanding supply.

### Capacity

`maxTotalSupply`, the cap used when accepting new deposits. Interest may
increase total supply above it, and the borrower may lower it below current
supply. It does not restrict withdrawals.

## Credit, Liquidity, and Fees

### Borrow and Repay

`borrow(amount)` transfers available underlying assets to the operational
borrower. `repay(amount)` transfers underlying assets from its caller into the
market and has no borrower-only gate. In revolving markets, only explicit
borrow and repay calls update `drawnAmount`; a raw token transfer is a donation.

### Reserve Ratio

`reserveRatioBips`, the fraction of outstanding supply that contributes to
the market's required liquid balance.

### Collateral Obligation

`liquidityRequired()`, the minimum underlying balance needed for a healthy
market. It combines pending withdrawals, paid but unclaimed withdrawals,
reserve-ratio coverage of outstanding supply, and accrued protocol fees.

### Delinquency

The state in which the market's underlying balance is below
`liquidityRequired()`. `timeDelinquent` rises while the shortfall persists
and decays while the market is healthy. The delinquency fee applies while the
timer exceeds `delinquencyGracePeriod`.

### Interest and Fees

- `annualInterestBips` is the base annual rate paid to lenders.
- `commitmentFeeBips` is the fixed rate paid on the full supply of a
  revolving market.
- `delinquencyFeeBips` is the additional lender rate applied during
  penalized delinquency.
- `protocolFeeBips` is the protocol's fraction of base interest, charged in
  addition to lender interest and accrued separately.

## Withdrawals

### Withdrawal Request

An instruction that moves scaled ownership from a lender account into the
current withdrawal batch. Queueing does not burn the ownership or reduce total
supply.

### Withdrawal Batch

The shared accounting unit for requests submitted during one withdrawal
period. A batch may be current, expired and unpaid, or paid. Expired unpaid
batches receive liquidity in FIFO order; lenders within one batch participate
pro rata by scaled ownership.

### Withdrawal Payment

The reservation of underlying assets for a batch. Payment burns the batch's
scaled market-token ownership, stops its interest accrual, and records the
underlying as unclaimed withdrawals.

### Withdrawal Execution

The transfer of a lender's share from a paid batch after expiry. Execution is
permissionless for an account and batch. Assets owed to a sanctioned account
are sent to its sanctions escrow.
