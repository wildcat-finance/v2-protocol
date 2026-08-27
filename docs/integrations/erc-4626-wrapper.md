# Wildcat ERC-4626 Wrapper (EIP-4626)

This repository includes an [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626)
wrapper for Wildcat market tokens. It turns a rebasing market token into a
non-rebasing share token whose balance tracks the market's scaled accounting.

## TL;DR

- **Asset:** the rebasing Wildcat market token returned by `asset()`.
- **Shares:** a non-rebasing ERC-20 balance equal to scaled market-token
  ownership.
- **Exchange rate:** `market.scaleFactor()`; conversions do not use the
  `totalAssets() / totalSupply()` ratio.
- **Direct market-token transfers:** mint no shares. They restore missing
  backing or create surplus that the operational borrower may sweep.
- **Execution guards:** state-changing ERC-4626 methods and share transfers
  enforce sanctions and scaled-backing solvency.

## Where it lives in the repo

- [`src/vault/Wildcat4626Wrapper.sol`](../../src/vault/Wildcat4626Wrapper.sol)
- [`src/vault/Wildcat4626WrapperFactory.sol`](../../src/vault/Wildcat4626WrapperFactory.sol)
- Tests:
  - [`test/vault/Wildcat4626Wrapper.t.sol`](../../test/vault/Wildcat4626Wrapper.t.sol)
  - [`test/vault/Wildcat4626WrapperFactory.t.sol`](../../test/vault/Wildcat4626WrapperFactory.t.sol)
  - [`test/integration/Wildcat4626WrapperIntegration.t.sol`](../../test/integration/Wildcat4626WrapperIntegration.t.sol)

## Background: Wildcat scaling in 60 seconds

Wildcat markets use “scaled” balances internally and expose “normalized” ERC‑20 balances externally:

- **Scaled amounts** are ownership units that do not grow as interest accrues.
- **Normalized amounts** are the values used by `balanceOf`, `transfer`, and
  other ERC-20 functions; they rebase as interest accrues.
- The conversion is controlled by `scaleFactor` (ray, `1e27`):
  - `normalized = scaled * scaleFactor / 1e27`
  - `scaled = normalized * 1e27 / scaleFactor`

See [Scaling and Rounding](../protocol/scaling-and-rounding.md).

## Contracts

### `Wildcat4626Wrapper`

An ERC‑4626 vault where:

- **Asset** is the Wildcat market debt token (rebasing ERC‑20).
- **Shares** are a wrapper ERC‑20 that mirrors the market’s *scaled* accounting (non‑rebasing).

#### Metadata

- `name()` = `"<marketSymbol> [4626 Vault Shares]"`
- `symbol()` = `"v-<marketSymbol>"`
- `decimals()` = `wrappedMarket.decimals()` (same decimals as the market token / underlying asset)
- Shares also support EIP‑2612 `permit` (inherited from Solady `ERC20`).

#### Construction

Only the address returned by `market.wrapperFactory()` can deploy the wrapper.
Construction rejects a zero market, borrower, principal, or sentinel and
malformed market metadata. It captures the market, sentinel, transfer-policy,
decimals, name, and symbol dependencies. Borrower and principal remain live
market reads.

#### Key view helpers

| View | Meaning |
| --- | --- |
| `wrappedMarket()`, `market()`, `asset()` | The wrapped market token. `asset()` is the ERC-4626 asset getter. |
| `sanctionsSentinel()` | Sentinel captured from the market at construction. |
| `marketOwner()` | Compatibility getter for the market's current operational borrower. |
| `totalAssets()` | Normalized `wrappedMarket.balanceOf(address(this))`; grows as the market token rebases. |
| `assetsPerShareRay()` | Current market `scaleFactor`, in ray units. |
| `sharesPerAssetRay()` | Floored ray inverse: `RAY * RAY / scaleFactor`. |

#### Conversions & rounding

All conversions are derived from the market’s `scaleFactor` (ray, `1e27`), not from `totalAssets/totalSupply`.

**ERC-4626 preview rounding**

| Method | Rounding |
| --- | --- |
| `convertToShares(assets)` | floor |
| `convertToAssets(shares)` | floor |
| `previewDeposit(assets)` | floor (delegates to `convertToShares`) |
| `previewRedeem(shares)` | floor (delegates to `convertToAssets`) |
| `previewMint(shares)` | ceil |
| `previewWithdraw(assets)` | ceil |

**Execution paths (Wildcat‑compatible rounding)**

As of v2.5, Wildcat market transfers move `floor(amount * RAY / scaleFactor)` scaled tokens (`scaleAmountDown`; markets before v2.5 rounded half‑up). The wrapper's state‑changing methods convert to hold an exact identity against that floor: shares derived from a given asset amount floor (`deposit`, `withdraw`), and assets derived from a given share amount ceil (`mint`, `redeem`) — the smallest normalized amount that moves exactly the target scaled tokens. Each path then verifies the **actual scaled delta** observed on the market token.

- `deposit(assets, receiver)`:
  - Transfers `assets` market tokens into the wrapper.
  - Mints `shares = scaledBalanceOf(wrapper)_after - _before`.
  - Requires `shares == floor(assets → shares)` and reverts if the mint would be zero.
- `mint(shares, receiver)`:
  - Computes the *minimum* `assets` such that `floor(assets → shares) == shares` (a ceil conversion).
  - Transfers `assets` in, then requires the market scaled delta equals `shares`.
- `withdraw(assets, receiver, owner)`:
  - Computes `shares = floor(assets → shares)`, burns those shares, transfers `assets` out.
  - Requires the market scaled delta equals `shares`.
- `redeem(shares, receiver, owner)`:
  - Computes `assets = ceil(shares → assets)`, burns `shares`, transfers `assets` out.
  - Requires the market scaled delta equals `shares`.

Because normalized amounts are labels over exact scaled accounting, the `assets` figure returned by `redeem` (or passed to `withdraw`) can exceed the receiver's `balanceOf` delta by up to one scaled token's value: the market's rebasing balance view rounds independently of its transfer. Integrators should reconcile against `scaledBalanceOf` deltas, not `balanceOf`.

#### ERC-4626 limits and capacity

The wrapper applies the market's `maxTotalSupply` as a cap on normalized market
tokens held by this wrapper, not as a cap on aggregate market supply.

| View | Result under ordinary dependency behavior |
| --- | --- |
| `maxDeposit(receiver)` | `max(0, market.maxTotalSupply() - totalAssets())`, or zero if the receiver or wrapper is sanctioned, the wrapper is under-backed, recipient policy denies or fails, or the remainder would mint zero shares. |
| `maxMint(receiver)` | The remaining deposit capacity converted to shares with floor rounding. |
| `maxWithdraw(owner)` | The largest normalized amount whose floor-scaled transfer burns no more than the owner's shares; a nonzero maximum burns all of them. |
| `maxRedeem(owner)` | The owner's share balance, or zero when the owner or wrapper is sanctioned or the wrapper is under-backed. |

The four ERC-4626 execution methods reject zero assets or shares. ERC-4626 does
not require that implementation choice.

Notes:

- Wrapper creation is permissionless. If market-token transfers require access,
  `maxDeposit` and `maxMint` remain zero until the wrapper can receive tokens.
- Preview methods are conversion-only views. They deliberately ignore
  sanctions, capacity, and transfer readiness.
- The readiness query cannot predict sender balance, allowance,
  amount-dependent policy, or later state changes.
- The `max*` views fail closed to zero when a required market, sentinel, or
  transfer-policy read reverts or returns malformed data. Conversion previews
  and execution paths remain strict and propagate dependency failures.
- `maxTotalSupply` and `totalAssets()` are normalized and can grow apart from
  deposits. The wrapper can be at its cap while market tokens remain elsewhere.

#### Backing invariant

Operational ERC-4626 paths require:

```text
wrappedMarket.scaledBalanceOf(wrapper) >= wrapper.totalSupply()
```

When backing equals supply, canonical deposit, mint, withdraw, and redeem paths
preserve equality. Direct market-token transfers may create surplus backing.
If backing falls below share supply, ERC-4626 state changes and share transfers revert with
`InsolventWrapper`, while all four `max*` views return zero. Restoring scaled
backing clears the solvency failure; sanctions and transfer policy remain
independent.

#### Sanctions enforcement

The wrapper reads the market's current `borrowerPrincipal()` for each sanctions
check. It stores the market and sentinel addresses at construction, but does not
cache borrower identity.

- ERC‑4626 entrypoints (`deposit/mint/withdraw/redeem`) check:
  - `msg.sender` (always),
  - `receiver` (for `withdraw/redeem`, and for `deposit/mint` via mint hook),
  - `owner` (for `withdraw/redeem` via burn hook).
- Ordinary ERC-20 share transfers reject a sanctioned sender or receiver.
  Sanctions escrows have the narrow exceptions described below.
- `maxDeposit`, `maxMint`, `maxWithdraw`, and `maxRedeem` return zero when the
  relevant account or the wrapper itself is sanctioned.

Sanctions checks call
`sanctionsSentinel.isSanctioned(borrowerPrincipal, account)`. Overrides are
keyed by principal: changing the principal starts a new namespace, while an
operational-address change that preserves the principal does not. Existing
wrapper-share escrows remain releasable under their original namespace.

#### Sanctioned-share quarantine

Anyone may call `nukeFromOrbit(account)` for an account sanctioned under the
market's current principal.

- The wrapper forwards the complete call, including trailing hook data, to the
  market's `nukeFromOrbit` path for the account's direct market-token position.
- If the account owns wrapper shares, the wrapper creates the corresponding
  sanctions escrow, authorizes it, and moves the account's full share balance.
  A sanctioned holder can otherwise send shares only to that deterministic
  escrow; `nukeFromOrbit` is the supported path because it authorizes release.
- The wrapper itself cannot be nuked. A v2.5 market also rejects nuking its
  registered canonical wrapper, protecting the wrapper's pooled backing.
- An authorized escrow may return shares only when releasable under the
  principal namespace that created it. Foreign or spoofed escrows receive no
  release exception.

#### Sweeping stray tokens

`sweep(token, to)` allows the market’s current operational borrower to rescue arbitrary ERC‑20 balances from the wrapper:

- Authorization resolves `wrappedMarket.borrower()` at execution time, so it follows an accepted borrower transfer without a wrapper callback. `marketOwner()` remains as a dynamic compatibility getter.
- Reverts if `to` is sanctioned.
- For non-market tokens, sweeps the entire token balance.
- For the wrapped market token, sweeps only the **stranded scaled surplus**:
  - `strandedScaled = scaledBalanceOf(wrapper) - totalSupply()`
  - transfer amount is derived from current `scaleFactor`
  - verifies that the transfer removed exactly `strandedScaled`, leaving
    backing equal to share supply
- Emits `TokensSwept(token, to, amount)`.

#### Events

In addition to standard ERC‑20 events, the wrapper emits:

- `Deposit(caller, receiver, assets, shares)` (ERC‑4626)
- `Withdraw(caller, receiver, owner, assets, shares)` (ERC‑4626)
- `TokensSwept(token, to, amount)` (wrapper‑specific)
- `SanctionedAccountSharesSentToEscrow(account, escrow, shares)`

#### Errors (wrapper‑specific)

- Inputs and limits: `ZeroAddress`, `ZeroAssets`, `ZeroShares`, `CapExceeded`.
- Backing: `SharesMismatch(expected, actual)` and
  `InsolventWrapper(scaledBacking, shareSupply)`.
- Authority: `NotMarketOwner` and `NotWrapperFactory`.
- Sanctions: `SanctionedAccount(account)`, `AccountNotSanctioned(account)`, and
  `CannotNukeWrapper`.

### `Wildcat4626WrapperFactory`

This permissionless factory is the discovery and creation facade across wrapper
generations. Wrapper arithmetic is coupled to market transfer rounding: v2.5
markets declare `keccak256('scaleAmountDown')`, while earlier markets use
half-up rounding and lack the declaration. A mismatched wrapper can trip
`SharesMismatch` whenever those rounding rules diverge.

#### Construction and views

- `Wildcat4626WrapperFactory(archController, v1Factory)` stores both as
  immutables. A nonzero legacy factory must successfully answer
  `wrapperForMarket(address(0))` with at least one return word.
- `isFloorRoundingMarket(market)` returns true only for the supported floor
  marker. Failed, short, codeless, and unknown responses return false.
- `wrapperForMarket(market)` returns a local wrapper first. Declared markets do
  not fall through to the legacy registry; undeclared markets do when a legacy
  factory is configured.

#### `createWrapper(market) -> wrapper`

- Reverts if `market == address(0)` or a wrapper is already recorded locally.
- Markets that do not declare a transfer rounding (pre‑v2.5) are **forwarded to the v1 factory**, which performs its own checks (`LegacyMarketsNotSupported` if no v1 factory is configured).
- Markets declaring a rounding other than floor (a hypothetical future generation) revert `UnsupportedMarketRounding` rather than being mispaired.
- Floor-declaring markets must be registered, expose the complete generic
  transfer-policy interface, permit transfers globally, and designate this
  factory through `market.wrapperFactory()`.
- The factory deploys and records the wrapper, then calls
  `market.registerWrapper(wrapper)`. Registration is one-time and emits
  `WrapperDeployed(market, wrapper)` from the factory.

#### `wrapperForMarket(market) -> wrapper`

Discovery routes like creation: locally recorded wrappers always resolve;
markets declaring any rounding resolve only from the local registry, so a
mispaired legacy-factory wrapper is quarantined from canonical discovery.
Undeclared markets read through to the legacy factory.

## Usage guide (integration)

### Wrap market tokens into non‑rebasing shares

1. Acquire Wildcat market tokens (e.g., by depositing the underlying asset into the market contract).
2. `approve(marketToken, wrapper, amount)`
3. Call either:
   - `deposit(assets, receiver)` to wrap a known asset amount, or
   - `mint(shares, receiver)` to wrap and receive an exact share amount.

### Unwrap shares back into market tokens

- `redeem(shares, receiver, owner)` to redeem exact shares, or
- `withdraw(assets, receiver, owner)` to withdraw an exact asset amount.

### Exiting to the underlying asset (important)

Redeeming from the wrapper returns the **market token**, not the market's
underlying asset. Exiting to the underlying asset then follows the
[market withdrawal flow](../protocol/withdrawals.md): request, batch expiry and
payment, then execution. The [glossary](../protocol/glossary.md) defines those
stages.

For v2.5 markets, one wrapper share represents one scaled market-token unit. A
Safe can atomically redeem and queue an exact share amount with
`wrapper.redeem(shares, safe, safe)` followed by
`market.queueWithdrawalScaled(shares)`. The Safe must be eligible to receive
market tokens under the market's transfer policy. The scaled amount stays exact
while the transaction waits for signatures, and any direct market-token balance
held by the Safe remains separate.

`queueWithdrawalScaled` is not available on pre-v2.5 markets. Integrations must
select the ABI from the deployed market generation. The scaled entry point is
not interchangeable with a normalized withdrawal amount.

## Gotchas / integration notes

- **Direct transfers do not mint shares.** They may restore missing backing or
  create a donation. `totalAssets()` can then exceed
  `convertToAssets(totalSupply())`; the operational borrower can sweep only
  scaled surplus above share supply.
- **Wrapper generations must match market generations.** Use the current
  factory for creation and discovery. It routes legacy markets when configured
  and quarantines a mispaired legacy-factory wrapper from discovery.
- **Legacy wrappers require an operational sanctions override.** Pre-v2.5
  markets cannot register their canonical wrapper. The borrower principal
  should keep a sentinel override for that wrapper while it is in use, so
  market-level sanctions handling cannot remove pooled backing while wrapper
  shares remain outstanding. The override does not exempt shareholders.
- **A market cannot use its own wrapper as an access credential.** The role provider must read the wrapper conversion during the market's state-changing hook call, and that conversion reads the same market's guarded `scaleFactor()`. A wrapper for one market can still authorize access to another market.
- **Do not replace a wrapped-only withdrawal with `queueFullWithdrawal()` when the account also owns market tokens directly.** Full withdrawal queues both positions. Use the v2.5 scaled route to preserve the direct position.

## Dev notes (for working on this code)

- Wrapper behavior is split between the explicit ERC-4626 methods and the
  inherited ERC-20 `_beforeTokenTransfer` guard. Review both.
- The focused command is
  `forge test --match-contract '^Wildcat4626Wrapper(Factory|Integration)?Test$'`.
- [`TESTS.md`](../../TESTS.md) defines the repository-wide test contract.
