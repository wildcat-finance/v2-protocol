# Markets

Read [Scaling and rounding](./scaling-and-rounding.md) first. Market accounting
depends on it.

## Market configuration

Markets are configured with the following values:

- `asset`: the market's underlying asset
- `name`: borrower-provided prefix plus the asset name
- `symbol`: borrower-provided prefix plus the asset symbol
- `borrower`: the operational address that can borrow and change market
  parameters. In supported V2.5 markets, it is always equal to
  `borrowerPrincipal`.
- `borrowerPrincipal`: the registered legal principal for the market and its
  lender-facing sanctions namespace. Separate storage supports the account-aware
  identity model planned for V2.6.
- `borrowerIdentityRegistry`: resolves and validates borrower transfer targets.
  V2.5 supports direct registered principals. Account resolution exists in
  source but is not supported until V2.6.
- `feeRecipient`: the immutable recipient of protocol fees. A market with a zero
  recipient cannot adopt a positive protocol fee later.
- `sentinel`: the Chainalysis wrapper used for sanctions checks
- `maxTotalSupply`: the cap on normalized market-token supply. It limits new
  deposits, not withdrawals.
- `protocolFeeBips`: the protocol's share of `annualInterestBips`. It accrues on
  top of lender interest and does not include delinquency fees.
- `annualInterestBips`: the borrower-set base interest rate paid to lenders
- `delinquencyFeeBips`: the additional lender rate charged after the delinquency
  grace period
- `withdrawalBatchDuration`: the length of a withdrawal cycle
- `reserveRatioBips`: the share of outstanding debt the borrower must keep in
  liquid reserves
- `delinquencyGracePeriod`: how long a market may remain delinquent before the
  penalty rate begins
- `archController`: the registry for factories, controllers, and markets
- `sphereXEngine`: the SphereX transaction-checking engine
- `hooks`: the market's hook policy and hook instance address

## Market types

V2.5 has two market implementations sharing the behavior described here:

### Standard

`WildcatMarket` accrues `annualInterestBips` on the full supply.

### Revolving

`WildcatMarketRevolving` supports revolving credit facilities. Lenders earn:

```text
commitmentFee
+ annualInterestBips * min(drawnAmount, totalSupply) / totalSupply
```

The commitment fee is fixed at deployment and applies to the full supply. APR
only applies to the drawn portion.

Borrows and explicit repayments reconcile `drawnAmount` against outstanding
debt. A raw underlying transfer is a donation. It adds liquidity but does not
repay drawn principal. Later borrows cannot count donated or previously
over-repaid liquidity as a new draw.

A revolving market accrues no interest while it is closed or empty.

Collateral obligations, delinquency, withdrawals, and closure work the same in
both implementations.

V2.5 uses explicit rounding directions for every scaled and normalized
conversion. See [Rounding](./scaling-and-rounding.md#rounding).

## Closure

`closeMarket()`:

1. accrues the market through the closure timestamp;
2. settles the remaining debt from or to the borrower;
3. sets APR to zero and the reserve ratio to 100%;
4. clears the delinquency timer; and
5. marks the market closed.

Interest and delinquency fees stop at closure.

Closure also pays the current batch and walks every unpaid withdrawal batch.
Markets with long unpaid queues should process them incrementally before
closure; see [Withdrawals](./withdrawals.md#closing-a-market).

## Borrower identity and transfer

V2.5 stores the operational borrower separately from the registered principal.
Supported factories and deployments keep `borrower == borrowerPrincipal` at
origination and after a transfer.

The source also contains an account-aware path. It lets a recognized contract
account operate a market for a separately recorded principal. That path is
planned for V2.6 and is not supported in V2.5.

Only the operational borrower can call borrower-only market functions. A
Borrower Account can enforce its own delegate policy before calling the market;
the market does not need its own delegate system.

Borrower changes use a two-step flow:

1. The current borrower requests or cancels a transfer.
2. Only the pending target can accept it.

Both steps resolve the target through the borrower identity registry and apply
current registration and raw sanctions checks. Acceptance changes borrower
identity. It does not change market accounting or lifecycle state.

The canonical ERC-4626 wrapper follows the market's live borrower and principal. Hooks and role providers do not transfer implicitly because they may be shared across markets and have separate authority domains.

See [Borrower Identity and Transfers](./borrower-identity.md) for the full state model, transfer cases, events, and integration requirements.

## Related mechanics

- [Accounting and state updates](./accounting.md): collateral obligations,
  interest, fees, delinquency, and state transitions.
- [Withdrawals](./withdrawals.md): batch ownership, payment priority, and
  execution.
