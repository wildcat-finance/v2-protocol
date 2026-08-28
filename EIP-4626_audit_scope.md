# Wildcat ERC-4626 wrapper audit scope

## Summary

[`Wildcat4626Wrapper`](./src/vault/Wildcat4626Wrapper.sol) is a Solady-based
ERC-4626 vault around a Wildcat market debt token.

- The asset is the rebasing market token.
- The shares are a non-rebasing ERC-20 that track the market's scaled balances.
  Those shares can be bridged without carrying the market's rebasing behavior
  across chains.
- Conversions use the market's `scaleFactor` (ray, `1e27`), not
  `totalAssets` / `totalSupply`.

At the audited commit:

- `convertToShares`, `convertToAssets`, `previewDeposit`, and `previewRedeem`
  rounded down.
- `previewMint` and `previewWithdraw` rounded up.
- `deposit`, `mint`, `withdraw`, and `redeem` used half-up rounding to match the
  market's `rayDiv` and `rayMul`, then checked the actual scaled-balance delta.
- `deposit(assets, receiver)` minted the exact increase in the wrapper's scaled
  balance. It reverted on zero amounts, cap violations, sanctions, or a result
  below the half-up expectation.
- `mint(shares, receiver)` found the minimum asset amount that half-up rounded
  to exactly `shares`, then required the scaled delta to match.
- `withdraw(assets, receiver, owner)` burned the half-up share amount, spent
  allowance when needed, transferred the assets, and checked the scaled delta.
  `redeem(shares, receiver, owner)` provided the symmetric exact-share path.

The wrapper also enforced:

- reentrancy protection on every state-changing function;
- sanctions checks for callers, owners, receivers, and share transfers through
  `_beforeTokenTransfer`;
- the market cap reported by `market.maxTotalSupply()`; and
- donation resistance. Donated market tokens increased `totalAssets` without
  diluting shares, but became stranded until swept as surplus.

The borrower could sweep non-market ERC-20s and market tokens above the amount
backing wrapper shares.

[`Wildcat4626WrapperFactory`](./src/vault/Wildcat4626WrapperFactory.sol)
permissionlessly deployed at most one wrapper for each registered market. It
checked `archController.isRegisteredMarket` and stored the result in
`wrapperForMarket`.

The audit tests covered metadata, rounding, scale-factor changes, sanctions,
caps, donation and inflation resistance, fuzzed execution, and the full
ERC-4626 standard suite against a real `WildcatMarket`.

See [ERC-4626 wrapper](./docs/integrations/erc-4626-wrapper.md) for the current
integration documentation.

## Audited commit

[`f8d8b9b`](https://github.com/wildcat-finance/v2-protocol/commit/f8d8b9babbe02e5c4d4294abbd8661bb7cf57c10)

Two follow-up commits changed the wrapper after that snapshot:

- `b267afb` adjusted `maxWithdraw` preview accuracy.
- `609c1a8` expanded `sweep` to allow reclaiming surplus wrapped market tokens above share backing.

The V2.5 pre-release cycle made more changes outside the audited commit:

- Execution arithmetic moved from half-up to floor-consistent conversions to
  match the V2.5 market's `scaleAmountDown` transfer rounding. Against V2.5
  markets, the audited half-up arithmetic reverted with `SharesMismatch` in
  roughly half of fractional scale-factor states. Preview behavior did not
  change.
- `maxWithdraw` and `maxDeposit` were re-derived for floor semantics. Both are
  exact and executable.
- `Wildcat4626WrapperFactory` became a generation facade. Its constructor takes
  `(archController, v1Factory)`. It wraps markets that declare floor rounding,
  forwards older markets to the V1 factory, rejects unknown rounding markers,
  keeps discovery consistent, and quarantines mispaired wrappers.
- Exact-integer search verified the wrapper's rounding identities. The retained
  regression coverage lives in `test/vault/Wildcat4626Wrapper.t.sol`.

## Audit scope

| Filepath                                | nSLOC   |
| --------------------------------------- | ------- |
| src/vault/Wildcat4626Wrapper.sol        | 281     |
| src/vault/Wildcat4626WrapperFactory.sol | 23      |
| **Total**                               | **304** |
