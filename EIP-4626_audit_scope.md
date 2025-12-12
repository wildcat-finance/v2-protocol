# Summary


`Wildcat4626Wrapper` (v2-protocol/src/vault/Wildcat4626Wrapper.sol) is a Solady-based ERC‑4626 vault that wraps a Wildcat market debt token. The underlying “asset” is the rebasing market token; the vault “shares” are a non‑rebasing ERC20 that track the market’s scaled balances (i.e., share count you can bridge cross‑chain).

- Conversions don’t use `totalAssets`/`totalSupply`; they use the market’s `scaleFactor` (ray, 1e27).
	- EIP-4626 compliance: `convertToShares`/`convertToAssets` and `previewDeposit`/`previewRedeem` floor‑round; `previewMint`/`previewWithdraw` ceil‑round.
	- Execution: `deposit`/`mint`/`withdraw`/`redeem` use half‑up rounding to mirror Wildcat’s `rayDiv`/`rayMul`, then verify actual scaled deltas.
- `deposit(assets, receiver)` pulls market tokens and mints shares equal to `scaledBalanceOf(wrapper)` increase; reverts on zeroes, cap excess, sanctions, or if minted shares fall below the half‑up expectation.
- `mint(shares, receiver)` computes the minimal assets that half‑up‑round to exactly shares, transfers them in, and requires the scaled delta to equal shares.
- `withdraw(assets, receiver, owner)` burns half‑up shares for the asset amount, spends allowance if needed, transfers assets out, and requires the scaled delta to match burned shares. `redeem(shares, receiver, owner)` is the symmetric exact‑shares path.
- Safety/ops: reentrancy guard on all mutating funcs; sanctions enforced for callers/owners/receivers and on share transfers via `_beforeTokenTransfer`; cap enforced vs `market.maxTotalSupply()`; stray asset donations of debt token raise `totalAssets` but don’t dilute shares (assets become stranded). Borrower can sweep non‑market ERC20s only.
- Wildcat4626WrapperFactory (v2-protocol/src/vault/Wildcat4626WrapperFactory.sol) permissionlessly deploys at most one wrapper per registered market via `archController.isRegisteredMarket`, stored in `wrapperForMarket`.
- Tests (v2-protocol/test/vault/4626) cover metadata, rounding rules, scale‑factor changes, sanctions, cap, donation/inflation resistance, fuzzed execution, and a full ERC‑4626 standard test suite against a real WildcatMarket.


## Audit Scope

| Filepath | nSLOC |
| --- | --- |
| src/vault/Wildcat4626Wrapper.sol | 281 |
| src/vault/Wildcat4626WrapperFactory.sol | 23 |
| **Total** | **304** |

