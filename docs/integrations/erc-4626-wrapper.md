# ERC-4626 wrapper

This repository includes an [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626)
wrapper for Wildcat market tokens. The wrapper turns a rebasing market token
into a non-rebasing share token. Its balance tracks the market's scaled
accounting.

## In short

- **Asset:** The rebasing Wildcat market token returned by `asset()`.
- **Shares:** A non-rebasing ERC-20 balance equal to scaled market-token
  ownership.
- **Exchange rate:** `market.scaleFactor()`. Conversions do not use the
  `totalAssets() / totalSupply()` ratio.
- **Direct market-token transfers:** Mint no shares. They restore missing
  backing or create surplus that the operational borrower may sweep.
- **Execution guards:** State-changing ERC-4626 methods and share transfers
  enforce sanctions and scaled-backing solvency.

## Where it lives in the repo

- [`src/vault/Wildcat4626Wrapper.sol`](../../src/vault/Wildcat4626Wrapper.sol)
- [`src/vault/Wildcat4626WrapperFactory.sol`](../../src/vault/Wildcat4626WrapperFactory.sol)
- Tests:
  - [`test/vault/Wildcat4626Wrapper.t.sol`](../../test/vault/Wildcat4626Wrapper.t.sol)
  - [`test/vault/Wildcat4626WrapperFactory.t.sol`](../../test/vault/Wildcat4626WrapperFactory.t.sol)
  - [`test/integration/Wildcat4626WrapperIntegration.t.sol`](../../test/integration/Wildcat4626WrapperIntegration.t.sol)

## Wildcat scaling

Wildcat markets use scaled balances internally. They expose normalized ERC-20
balances externally.

- **Scaled amounts:** Ownership units that do not grow as interest accrues.
- **Normalized amounts:** Values used by `balanceOf`, `transfer`, and
  other ERC-20 functions; they rebase as interest accrues.
- **Conversion:** Controlled by `scaleFactor`, expressed as a ray (`1e27`).

```text
normalized = scaled * scaleFactor / 1e27
scaled = normalized * 1e27 / scaleFactor
```

See [Scaling and Rounding](../protocol/scaling-and-rounding.md).

## Contracts

### `Wildcat4626Wrapper`

`Wildcat4626Wrapper` is an ERC-4626 vault with:

- A rebasing Wildcat market debt token as its asset.
- A non-rebasing ERC-20 share that mirrors the market's scaled accounting.

#### Metadata

- `name()` = `"<marketSymbol> [4626 Vault Shares]"`
- `symbol()` = `"v-<marketSymbol>"`
- `decimals()` = `wrappedMarket.decimals()`
- Shares support EIP-2612 `permit` through Solady's `ERC20`.

#### Construction

Only `market.wrapperFactory()` can deploy the wrapper.

Construction rejects:

- A zero market, borrower, principal, or sentinel.
- Malformed market metadata.

The wrapper captures its market, sentinel, transfer policy, decimals, name, and
symbol. It reads the borrower and principal from the market when needed.

#### Key view helpers

- `wrappedMarket()`, `market()`, and `asset()` return the wrapped market token.
  `asset()` is the ERC-4626 asset getter.
- `sanctionsSentinel()` returns the sentinel captured at construction.
- `marketOwner()` returns the current operational borrower. It exists for
  compatibility.
- `totalAssets()` returns normalized
  `wrappedMarket.balanceOf(address(this))`. It grows as the market token
  rebases.
- `assetsPerShareRay()` returns the current market `scaleFactor`.
- `sharesPerAssetRay()` returns its floored ray inverse:
  `RAY * RAY / scaleFactor`.

#### Conversions and rounding

All conversions use the market's `scaleFactor`. They do not use
`totalAssets() / totalSupply()`.

Preview methods use standard ERC-4626 rounding:

| Method                    | Rounding                               |
| ------------------------- | -------------------------------------- |
| `convertToShares(assets)` | floor                                  |
| `convertToAssets(shares)` | floor                                  |
| `previewDeposit(assets)`  | floor (delegates to `convertToShares`) |
| `previewRedeem(shares)`   | floor (delegates to `convertToAssets`) |
| `previewMint(shares)`     | ceil                                   |
| `previewWithdraw(assets)` | ceil                                   |

Execution must also match Wildcat's transfer rounding. V2.5 market transfers
move:

```text
floor(amount * RAY / scaleFactor)
```

This is `scaleAmountDown`. Markets before V2.5 rounded half-up.

The wrapper keeps an exact identity against the V2.5 floor:

- `deposit(assets, receiver)` transfers `assets` in. It mints the observed
  increase in scaled balance. That increase must equal
  `floor(assets -> shares)` and cannot be zero.
- `mint(shares, receiver)` finds the smallest asset amount whose floored
  conversion equals `shares`. It transfers that amount in and verifies the
  scaled balance increased by exactly `shares`.
- `withdraw(assets, receiver, owner)` burns `floor(assets -> shares)`, transfers
  `assets` out, and verifies the scaled balance fell by exactly that amount.
- `redeem(shares, receiver, owner)` burns `shares`, transfers
  `ceil(shares -> assets)` out, and verifies the scaled balance fell by exactly
  `shares`.

Normalized amounts are labels over exact scaled accounting. The asset amount
returned by `redeem`, or passed to `withdraw`, may exceed the receiver's
`balanceOf` increase by up to one scaled token's value. The rebasing balance
view and the transfer round independently.

Reconcile integrations against `scaledBalanceOf` deltas, not `balanceOf`.

#### ERC-4626 limits and capacity

The wrapper applies `market.maxTotalSupply()` to the normalized market tokens it
holds. It is not a cap on aggregate market supply.

- `maxDeposit(receiver)` returns
  `max(0, market.maxTotalSupply() - totalAssets())`.
- `maxMint(receiver)` converts the remaining deposit capacity to shares with
  floor rounding.
- `maxWithdraw(owner)` returns the largest normalized amount whose floored
  scaled transfer burns no more than the owner's shares. A nonzero maximum
  burns all of them.
- `maxRedeem(owner)` returns the owner's share balance.

The relevant `max*` view returns zero when:

- The owner, receiver, or wrapper checked by that view is sanctioned.
- The wrapper is under-backed.
- Recipient policy denies or fails for a deposit.
- Remaining deposit capacity would mint zero shares.

All four execution methods reject zero assets or shares. ERC-4626 does not
require this.

The wrapper allows shares to be minted or transferred to `address(0)`. Those
shares remain fully backed, but cannot be recovered.

Notes:

- Wrapper creation is permissionless. If market-token transfers require access,
  `maxDeposit` and `maxMint` remain zero until the wrapper can receive tokens.
- Preview methods only convert values. They ignore sanctions, capacity, and
  transfer readiness.
- Readiness cannot predict sender balance, allowance, amount-dependent policy,
  or later state changes.
- The `max*` views fail closed to zero if a required market, sentinel, or
  transfer-policy read reverts or returns malformed data. Preview conversions
  and execution paths remain strict. They propagate dependency failures.
- `maxTotalSupply` and `totalAssets()` are normalized. They can grow without
  deposits. The wrapper may be at its cap while market tokens remain elsewhere.

#### Backing invariant

Operational ERC-4626 paths require:

```text
wrappedMarket.scaledBalanceOf(wrapper) >= wrapper.totalSupply()
```

When backing equals supply, the canonical execution paths preserve equality.
Direct market-token transfers may create surplus backing.

If backing falls below share supply:

- ERC-4626 state changes revert with `InsolventWrapper`.
- Share transfers revert with `InsolventWrapper`.
- All four `max*` views return zero.

Restoring scaled backing clears the solvency failure. Sanctions and transfer
policy remain independent.

#### Sanctions enforcement

The wrapper reads `market.borrowerPrincipal()` for every sanctions check. It
stores the market and sentinel addresses, but does not cache borrower identity.

- ERC-4626 entry points always check `msg.sender`.
- `deposit` and `mint` check `receiver` through the mint hook.
- `withdraw` and `redeem` check `receiver` directly and `owner` through the burn
  hook.
- Ordinary ERC-20 share transfers reject a sanctioned sender or receiver.
  Sanctions escrows have the narrow exceptions described below.
- `maxDeposit`, `maxMint`, `maxWithdraw`, and `maxRedeem` return zero when the
  relevant account or the wrapper itself is sanctioned.

Sanctions checks call:

```solidity
sanctionsSentinel.isSanctioned(borrowerPrincipal, account)
```

Overrides are keyed by principal. Changing the principal starts a new namespace.
Changing only the operational borrower does not. Existing wrapper-share escrows
remain releasable under their original namespace.

#### Sanctioned-share quarantine

Anyone may call `nukeFromOrbit(account)` when the account is sanctioned under
the market's current principal.

- The wrapper forwards the complete call, including trailing hook data, to the
  market. This handles the account's direct market-token position.
- If the account owns wrapper shares, the wrapper creates the corresponding
  sanctions escrow, authorizes it, and moves the full share balance.
- A sanctioned holder may otherwise send shares only to that deterministic
  escrow. `nukeFromOrbit` is the supported path because it authorizes release.
- The wrapper itself cannot be nuked. A V2.5 market also rejects nuking its
  registered canonical wrapper, protecting the wrapper's pooled backing.
- An authorized escrow may return shares only when releasable under the
  principal namespace that created it. Foreign or spoofed escrows receive no
  release exception.

#### Sweeping stray tokens

`sweep(token, to)` lets the current operational borrower rescue ERC-20 balances
from the wrapper.

- Authorization reads `wrappedMarket.borrower()` at execution time. It follows
  an accepted borrower transfer without a wrapper callback.
- `marketOwner()` remains a dynamic compatibility getter.
- Reverts if `to` is sanctioned.
- For non-market tokens, sweeps the entire token balance.
- For the wrapped market token, sweeps only stranded scaled surplus:

  ```text
  strandedScaled = scaledBalanceOf(wrapper) - totalSupply()
  ```

  The transfer amount uses the current `scaleFactor`. The wrapper verifies that
  it removed exactly `strandedScaled`, leaving backing equal to share supply.

- Emits `TokensSwept(token, to, amount)`.

#### Events

In addition to standard ERC-20 events, the wrapper emits:

- `Deposit(caller, receiver, assets, shares)` (ERC-4626)
- `Withdraw(caller, receiver, owner, assets, shares)` (ERC-4626)
- `TokensSwept(token, to, amount)` (wrapper-specific)
- `SanctionedAccountSharesSentToEscrow(account, escrow, shares)`

#### Errors (wrapper-specific)

- Inputs and limits: `ZeroAddress`, `ZeroAssets`, `ZeroShares`, `CapExceeded`.
- Backing: `SharesMismatch(expected, actual)` and
  `InsolventWrapper(scaledBacking, shareSupply)`.
- Authority: `NotMarketOwner` and `NotWrapperFactory`.
- Sanctions: `SanctionedAccount(account)`, `AccountNotSanctioned(account)`, and
  `CannotNukeWrapper`.

### `Wildcat4626WrapperFactory`

This permissionless factory handles creation and discovery across wrapper
generations.

Wrapper arithmetic is coupled to market transfer rounding:

- V2.5 markets declare `keccak256('scaleAmountDown')`.
- Earlier markets use half-up rounding and do not declare a rounding mode.

A mismatched wrapper can revert with `SharesMismatch` whenever those rules
diverge.

#### Construction and views

- `Wildcat4626WrapperFactory(archController, v1Factory)` stores both addresses
  as immutables.
- A nonzero legacy factory must answer `wrapperForMarket(address(0))` with at
  least one return word.
- `isFloorRoundingMarket(market)` returns true only for the supported floor
  marker. Failed, short, codeless, and unknown responses return false.
- `wrapperForMarket(market)` checks the local registry first. Declared markets
  never fall through to the legacy registry. Undeclared markets do when a
  legacy factory is configured.

#### `createWrapper(market) -> wrapper`

- Reverts if `market == address(0)` or a wrapper is already recorded locally.
- Forwards markets without a declared transfer rounding to the V1 factory.
  These are pre-V2.5 markets. Reverts with `LegacyMarketsNotSupported` if no V1
  factory is configured.
- Rejects any declared rounding other than floor with
  `UnsupportedMarketRounding`. This prevents a hypothetical future market from
  being paired with the wrong wrapper.
- Floor-declaring markets must be registered, expose the complete generic
  transfer-policy interface, permit transfers globally, and designate this
  factory through `market.wrapperFactory()`.
- The factory deploys and records the wrapper, then calls
  `market.registerWrapper(wrapper)`.
- Registration is one-time. The factory emits
  `WrapperDeployed(market, wrapper)`.

#### `wrapperForMarket(market) -> wrapper`

Discovery follows the same routing:

- Locally recorded wrappers always resolve.
- Markets declaring any rounding resolve only from the local registry.
- Undeclared markets read through to the legacy factory.

This keeps a mispaired legacy-factory wrapper out of canonical discovery.

## Integration guide

### Wrap market tokens into non-rebasing shares

1. Acquire Wildcat market tokens, usually by depositing the underlying asset in
   the market.
2. Call `approve(marketToken, wrapper, amount)`.
3. Call `deposit(assets, receiver)` for a known asset amount, or
   `mint(shares, receiver)` for an exact share amount.

### Unwrap shares back into market tokens

- Use `redeem(shares, receiver, owner)` to redeem an exact share amount.
- Use `withdraw(assets, receiver, owner)` to withdraw an exact asset amount.

### Exiting to the underlying asset

Redeeming from the wrapper returns the market token, not the market's underlying
asset. Exiting to the underlying asset then follows the
[market withdrawal flow](../protocol/withdrawals.md): request, batch expiry and
payment, then execution. The [glossary](../protocol/glossary.md) defines those
stages.

For V2.5 markets, one wrapper share represents one scaled market-token unit. A
Safe can atomically redeem and queue an exact share amount with
`wrapper.redeem(shares, safe, safe)` followed by
`market.queueWithdrawalScaled(shares)`. The Safe must be eligible to receive
market tokens under the market's transfer policy. The scaled amount stays exact
while the transaction waits for signatures. Any direct market-token balance
held by the Safe stays separate.

`queueWithdrawalScaled` is not available on pre-V2.5 markets. Integrations must
select the ABI from the deployed market generation. The scaled entry point is
not interchangeable with a normalized withdrawal amount.

## Integration notes

- **Direct transfers do not mint shares.** They may restore backing or create a
  donation. `totalAssets()` can then exceed
  `convertToAssets(totalSupply())`. The operational borrower may sweep only the
  scaled surplus above share supply.
- **Wrapper and market generations must match.** Use the current factory for
  creation and discovery. It routes legacy markets when configured and hides a
  mispaired legacy-factory wrapper from canonical discovery.
- **Legacy wrappers need an operational sanctions override.** Pre-V2.5 markets
  cannot register a canonical wrapper. While one is in use, the borrower
  principal should keep a sentinel override for it. This prevents market-level
  sanctions handling from removing pooled backing while wrapper shares remain
  outstanding. The override does not exempt shareholders.
- **A market cannot use its own wrapper as an access credential.** The provider
  would read the wrapper conversion during the market's guarded state change.
  That conversion reads the same market's guarded `scaleFactor()`. A wrapper
  for one market can still authorize access to another.
- **Do not substitute `queueFullWithdrawal()` for a wrapped-only withdrawal when
  the account also holds market tokens directly.** Full withdrawal queues both
  positions. Use the V2.5 scaled route to preserve the direct position.

## Development notes

- Wrapper behavior is split between the explicit ERC-4626 methods and the
  inherited ERC-20 `_beforeTokenTransfer` guard. Review both.
- The focused command is
  `forge test --match-contract '^Wildcat4626Wrapper(Factory|Integration)?Test$'`.
- [`TESTS.md`](../../TESTS.md) defines the repository-wide test contract.
