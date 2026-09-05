# Scaling and rounding

## Short version

- Wildcat tracks _scaled amounts_ and _market-token amounts_.
- Scaled amounts are shares. They stay fixed while interest accrues.
- Market-token amounts are the current debt value of those shares, denominated
  in the underlying asset. They are also called _normalized amounts_.
- The scale factor converts scaled amounts into normalized amounts. If the
  scale factor is 2, one scaled wTKN is worth two normalized wTKN.
- The scale factor never decreases. Lender interest and delinquency fees
  increase it; otherwise it stays flat.
- Standard ERC-20 and deposit functions use normalized amounts. Explicit scaled
  surfaces, including `scaledBalanceOf`, `scaledTotalSupply`, and
  `queueWithdrawalScaled`, use scaled amounts.

## Rounding

V2.5 uses deliberate, asymmetric rounding:

- Converting a normalized amount **into** scaled units rounds **down** through
  `scaleAmountDown`. Deposits, transfers, and withdrawal queueing never credit,
  move, or queue more shares than the normalized input can support.
- Converting scaled units **out** to normalized labels rounds **half-up** through
  `normalizeAmount`. Balances, debt totals, and scale-factor compounding retain
  the rounding used by deployed V2 markets.
- Withdrawal payments use `maxScaledSettleableAmount` to find the largest scaled
  amount whose floor-priced cost fits in available liquidity. Capacity
  saturates at the `uint104` batch limit before multiplying an unbounded
  underlying balance. A fully funded closed market can always finish its
  batches.

Markets before V2.5 rounded transfers half-up. V2.5 and later markets declare
their convention through `scaledTransferRounding()`. Rounding-sensitive
integrations, including the ERC-4626 wrapper factory, use that declaration.

## Finite scale-factor representation

`MarketState.scaleFactor` is a `uint112`. Accrual uses a checked cast. An
extreme, long-lived compounded rate that reaches the representation ceiling
reverts instead of truncating or wrapping.

Once that ceiling is reached, ordinary state-changing calls cannot advance the
market. A supported market must close or migrate before it gets there.

## Relevant code

The scale factor is stored as a ray with `1e27` base units. A value of `1.1e27`
means 1.1.

[`MathUtils`](../../src/libraries/MathUtils.sol) contains ray multiplication and
division.

## Scaled balances

Scaling works much like Aave's aTokens or shares in an
[ERC-4626 vault](https://eips.ethereum.org/EIPS/eip-4626#methods). The important
difference is what the reported token balance means.

### Vault analogy

Suppose an ERC-4626 vault called VUSDC has 100 shares and holds 200 USDC:

```solidity
VUSDC.totalSupply() = 100
VUSDC.totalAssets() = 200
```

One VUSDC converts to two USDC. If Alice owns 10 VUSDC, her shares convert to
20 USDC:

```solidity
VUSDC.balanceOf(alice) = 10
VUSDC.convertToAssets(10) = 20
```

If the vault receives another 100 USDC, Alice still owns 10 shares. Their value
rises to 30 USDC because the asset-to-share ratio increased by 50%.

### Wildcat markets

A Wildcat market reports the _value_ of shares through ordinary ERC-20
functions. It reports the _number_ of shares through scaled functions.

Using the same numbers for a WUSDC market, Alice owns 10 of 100 shares:

```solidity
WUSDC.scaledBalanceOf(alice) = 10
WUSDC.scaledTotalSupply() = 100
```

Those shares currently represent 20 of 200 normalized tokens:

```solidity
WUSDC.balanceOf(alice) = 20
WUSDC.totalSupply() = 200
```

At this point, `WUSDC.balanceOf(alice)` is analogous to
`VUSDC.convertToAssets(VUSDC.balanceOf(alice))`.

Two differences matter:

1. Wildcat market-token balances rebase as interest accrues.
2. The market may not hold all underlying assets represented by those balances.

An ordinary ERC-4626 vault generally values shares from assets it holds or can
access:

```text
convertToAssets(shares) = shares * totalAssets / totalSupply
```

A Wildcat market is an undercollateralized lending market. Its borrower may have
borrowed the underlying, and accrued interest increases debt without
transferring more underlying into the contract. `totalAssets` therefore cannot
price a Wildcat market token.

The `scaleFactor` does that job. It is the ratio between shares and the amount
of underlying debt those shares represent. A state-changing call or
current-state view compounds interest since the last stored update. Repeating
the calculation at the same timestamp adds no interest.

Deposits take a normalized underlying amount and divide it by the scale factor.
The result, rounded down, is the number of scaled shares minted.

Normalized withdrawal requests also round down to scaled units. The market
moves that exact scaled balance into the withdrawal batch; it does not burn the
shares at queue time. Shares burn when the market reserves underlying liquidity
for the batch. The lender later claims its share of those reserved assets.

A market-token balance therefore represents debt the borrower owes at a point
in time. It is the eventual underlying claim if the borrower repays. It is not
the number of shares an account owns, or an amount of underlying immediately
available for redemption.

## Terminology

- **Scale factor:** the ratio of borrower debt to market shares. At a scale
  factor of 2, one scaled token equals two normalized market tokens.
- **Normalized amount:** an amount denominated in the underlying asset, such as
  USDC. Most market-token and deposit functions use normalized amounts.
- **Market-token amount:** the normalized value of scaled tokens and the amount
  of underlying the borrower is ultimately obligated to repay.
- `scaleAmountDown(x)`: divides normalized amount `x` by the scale factor and
  rounds down.
- `normalizeAmount(x)`: multiplies scaled amount `x` by the scale factor using
  the operation's defined rounding.

## Example

Bob deposits 100 TKN into a new wTKN market with 10% annual interest.

### T1: initial deposit

```text
scaleFactor = 1
scaledBalanceOf(bob) = 100
balanceOf(bob) = 100 * 1 = 100
scaledTotalSupply = 100
totalSupply = 100 * 1 = 100
```

### T2: six months later

The market updates after half a year:

```text
scaleFactor = 1 * (1 + 10% * 0.5) = 1.05
scaledBalanceOf(bob) = 100
balanceOf(bob) = 100 * 1.05 = 105
scaledTotalSupply = 100
totalSupply = 100 * 1.05 = 105
```

### T3: Alice deposits in the same block

Alice deposits 210 TKN at the current scale factor:

```text
scaleFactor = 1.05
scaledBalanceOf(bob) = 100
balanceOf(bob) = 105
scaledBalanceOf(alice) = 210 / 1.05 = 200
balanceOf(alice) = 200 * 1.05 = 210
scaledTotalSupply = 300
totalSupply = 300 * 1.05 = 315
```

### T4: another six months later

```text
scaleFactor = 1.05 * (1 + 10% * 0.5) = 1.1025
scaledBalanceOf(bob) = 100
balanceOf(bob) = 110.25
scaledBalanceOf(alice) = 200
balanceOf(alice) = 220.50
scaledTotalSupply = 300
totalSupply = 330.75
```
