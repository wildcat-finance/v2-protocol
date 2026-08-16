# Changelog

## V2.5 Changelog

Changes between deployed V2 and the V2.5 release. The full pre-audit change
inventory with per-file provenance is in [v2.5-audit-delta.md](./v2.5-audit-delta.md).

### Revolving credit markets

- Added `WildcatMarketRevolving`, a market type for revolving credit facilities: tracks the borrower's drawn amount and accrues `commitmentFee + APR * min(drawn, supply) / supply` instead of APR on the full supply. No interest accrues while the market is closed or empty. Drawn amount is clamped to outstanding debt so self-supplied assets (e.g. an over-repayment) never accrue lender interest, including when an unusually large donated asset balance makes a borrow amount exceed ordinary market debt.
- Added `HooksFactoryRevolving`, deploying revolving markets with factory-owned `marketData` (`abi.encode(uint8 version, uint16 commitmentFeeBips)`).
- Extension seams (`_onBorrow`, `_onRepay`, `_onRepayAndGetTotalAssets`, `_onCloseMarket`, `_updateScaleFactorAndFees`) added to the base market as virtual functions; the standard market's behavior is unchanged.

### Periodic-term hooks

- Added `PeriodicTermHooks`: withdrawals may only be queued during a recurring scheduled window (closed markets bypass the window). See [Periodic Term Hooks](./hooks/templates/Periodic%20Term%20Hooks.md).
- APR reductions on periodic markets must be proposed in advance: lenders get the next withdrawal window to exit, then the reduction is executable — including **permissionlessly** through the market's new `executePendingAnnualInterestBipsReduction`, gated by a new hook flag. Increases and market closure cancel pending proposals; proposals expire after a validity period.

### Scaled-amount rounding (all markets)

- Transfers, deposits, and withdrawal queueing now scale normalized amounts **down** (`scaleAmountDown`) instead of half-up: the scaled amount credited, moved, or queued is never rounded up. Markets declare this via the new `scaledTransferRounding()` marker; `version()` is now `'2.5'` (first byte remains `'2'` for major-version checks).
- Added `queueWithdrawalScaled(uint256)` for integrations that already know the exact scaled amount to queue. This lets a Safe redeem canonical wrapper shares and queue those same shares without consuming an unrelated direct market-token balance or relying on a normalized amount calculated before execution.
- Withdrawal batch payments settle up to the exact floor-priced capacity (`maxScaledSettleableAmount`), capped at the largest representable `uint104` batch amount before processing an unbounded underlying balance, so fully-funded closes always settle their batches and nothing strands on closed markets.
- Hook minimum-deposit checks compare in scaled units, so depositing exactly the advertised minimum succeeds at any scale factor.
- The half-up `MarketState.scaleAmount` was removed; rounding directions are documented in [Scale Factor](./Scale%20Factor.md#rounding).

### Borrower identity and market transfers

- Split market identity into a stored operational `borrower` and registered `borrowerPrincipal`. Ordinary borrower calls still require the exact operational borrower, while lender-facing sanctions checks use the principal namespace.
- Added `WildcatBorrowerIdentityRegistry`. The ArchController owner approves account factories, approved factories register each account once, and one principal may have several accounts. Account principals may transfer an account to another registered principal through a two-step path. Removing a factory blocks only future registrations.
- Added borrower-requested, target-accepted market transfers with replacement, cancellation, acceptance-time identity and registration checks, and raw sanctions checks for the current and proposed borrower/principal identities. An account may use the same path to keep its market ownership while updating the market's stored principal.
- Transfers support direct principals, same-principal account rotation, and principal migration. They preserve balances, lender claims, accrued fees, market terms, revolving drawn amount, delinquency, and lifecycle state.
- Market construction now supports different initial borrower and principal addresses so future account-aware or deferred-origination factories can use the same identity seam without changing ordinary v2.5 factories.
- Wrapper sweep authority now resolves the live market borrower, and wrapper sanctions checks resolve the live market principal. Hooks and role providers do not move implicitly with a market transfer.
- Added borrower transfer events and v2.5 lens fields for current and pending principals, pending borrower, and identity-registry discovery. See [Borrower Identity and Transfers](./Borrower%20Identity%20and%20Transfers.md).

### ERC-4626 wrapper

- Wrapper execution paths converted to floor-consistent arithmetic matching v2.5 market transfers (previews keep their spec rounding); `maxDeposit`/`maxMint`/`maxWithdraw` are exact and executable whenever nonzero.
- `Wildcat4626WrapperFactory` is now a permanent generation facade: it wraps floor-rounding (v2.5+) markets locally, forwards pre-v2.5 markets to the previously deployed v1 factory for creation and discovery, and rejects unknown future rounding markers. See [EIP-4626](./EIP-4626.md).
- Canonical wrapper creation fails closed unless a v2.5 market's hooks expose the generic transfer-policy capability, and rejects markets whose transfers are permanently disabled.

### Lens

- Reintroduced as a facade (`MarketLens`) forwarding to helper contracts (`MarketLensCore`, `MarketLensAggregator`, `MarketLensLive`) to stay under the contract size limit; the aggregator serves both direct and multi-factory aggregated queries. The function-selector surface is preserved, but returned `HooksConfigData` tuples append `useOnExecutePendingAnnualInterestBipsReduction`, so consumers must use the v2.5 ABI.
- Hook instance lens data now exposes administrator and pending administrator instead of treating hook administration as market borrower identity. Managed role-provider data exposes its own administrator and pending administrator without assuming every provider is managed.

### Events and indexer data

- Factory deployment events now form a complete market snapshot: operational borrower and legal principal, hook template and instance, requested and final hook flags, economic configuration, fee terms, accepted hook deployment payload, and the revolving commitment fee where applicable.
- Hook instance deployment records the initial administrator, deploying borrower address, instance name, implementation version, and a bounded initial role-provider snapshot so borrower-account origination and constructor-time provider configuration can be indexed without a historical state call.
- Mutable market, hook, provider, fee, and lender-access events now identify the acting address and carry old/new values where replay requires them. Market closure records its implicit APR and reserve-ratio transition.
- Revolving markets emit drawn-principal changes separately from borrow proceeds and repayments. This preserves over-repayment and interest-only repayment semantics without adding fee-on-draw accounting.
- Custom assembly market emitters have direct parity tests against ordinary Solidity event encoding. See [v2.5 Event Model](./v2.5%20Event%20Model.md).

### Factories and access control

- Factory hardening: CREATE2 address verification on market deployment, pagination bounds validation (`InvalidPaginationRange`), empty-page handling. Market salts must encode the immediate factory caller in their first 20 bytes and a 12-byte nonce in the remainder. Zero-prefix salts are rejected. For borrower accounts, the prefix is the account contract rather than its principal.
- Disabling a hooks template now blocks both new hook instances and new markets that would reuse an existing instance; existing instances and markets remain operational.
- APR-reduction constraints compare the exact rational reduction against the 25% boundary before converting it to basis points, so a slightly-over-threshold reduction cannot floor onto the unpenalized boundary.
- `BaseAccessControls`: push credentials must have nonzero, non-future timestamps; `isPullProvider()` is probed defensively (non-implementing providers become push-only); providers already consulted via `hooksData` are skipped in the fallback pull loop.
- Hook administration is now separate from credential ownership. Hooks no longer add their administrator as a permanent push provider, and hook administrators can move through a two-step transfer without rewriting provider configuration or lender state.
- Added `AccessListRoleProvider`, a reusable pull provider with enumerable membership, explicit batch updates, and independent two-step administration. Its CREATE2 factory can assign the intended administrator when deployment is initiated through a hook and retains no authority after deployment.
- Added `MerkleRoleProvider` as a production candidate for reusable offchain lists. It accepts canonical sorted-pair proofs, supports independent two-step root administration, and has a caller-namespaced CREATE2 factory that retains no authority. It is not scheduled for the v2.5 deployment ceremony.
- Added `ERC20RoleProvider` as a production candidate for token-balance gates. Its token and inclusive balance threshold are immutable, and its caller-namespaced CREATE2 factory retains no authority. It is not scheduled for the v2.5 deployment ceremony.
- Added `ERC721RoleProvider` as a production candidate for collection-balance gates. Its collection is immutable, its optional interface-check bypass is explicit, and its caller-namespaced CREATE2 factory retains no authority. It is not scheduled for the v2.5 deployment ceremony.
- Added `ERC1155RoleProvider` as a production candidate for token-ID balance gates. Its collection and token ID are immutable, its optional interface-check bypass is explicit, and its caller-namespaced CREATE2 factory retains no authority. It is not scheduled for the v2.5 deployment ceremony.
- Added `ERC4626AssetsRoleProvider` as a production candidate for asset-denominated vault-share gates. Its vault and inclusive threshold are immutable, and its caller-namespaced CREATE2 factory retains no authority. It is not scheduled for the v2.5 deployment ceremony.
- TTL `0` now makes pull credentials non-cacheable, including within the same block. Positive TTLs retain the existing cache window, so delayed removal is an explicit hook configuration choice.
- All three hook templates reject inconsistent access configurations (withdrawal access without deposit access, or without transfer access/disablement) at market creation.

### Misc

- Removed the unemittable `SanctionedAccountAssetsSentToEscrow` event and other dead code.
- Deployed singletons (`WildcatArchController`, `WildcatSanctionsSentinel`, `WildcatSanctionsEscrow`) are unchanged; documentation-only annotations added.
- Hardened generic helpers so saturating addition detects arithmetic wraparound, bytes32 metadata retains a final high-bit byte, and malformed dynamic-string ABI returndata is rejected before it becomes an invalid in-memory string.

## V2 Changelog

### ERC-4626 wrapper

- Added `Wildcat4626Wrapper`, a non-rebasing ERC-4626 share token for Wildcat market debt tokens that tracks the market's scaled accounting.
- Added `Wildcat4626WrapperFactory`, which permissionlessly deploys at most one wrapper per registered market.
- Wrapper behavior is documented in [`docs/EIP-4626.md`](./EIP-4626.md), including scaling-based conversions, sanctions checks, per-wrapper capacity limits, and handling of direct market-token donations.

### Lens

Removed the lens contracts from the core protocol repository.

### Market deployment

**Create2 restrictions**

Borrowers are no longer restricted to deploying one market per combination of (asset, name, symbol), which was an issue when a borrower needed to close and recreate an existing market. When deploying a market, the borrower can now provide an arbitrary salt in the style of 0age's ImmutableCreate2Factory, where the first 20 bytes must match the immediate factory caller and the remaining 12 bytes can be any value so long as the full salt has not already been used. For borrower-account deployments, the caller prefix is the account contract, not its principal.

**Name/symbol length**

Increased maximum supported name/symbol length for underlying contract from 32 to `63 - prefix.length`.
The name/symbol queries now support arbitrary length strings; once combined with their prefixes, each must fit into two slots, with one byte reserved for the string length.

### Market

**Accounts**
- Accounts no longer have a `role` field, their ability to access various functions (other than borrower-only ones) is not restricted within the market itself, this is delegated to the market's hooks.

**Handling of sanctioned accounts**

- Removed `stunningReversal` because accounts no longer have roles marking them as sanctioned
- Market tokens are forced into a withdrawal batch rather than being transferred to an escrow when an account is marked as sanctioned. Withdrawal execution on a sanctioned account still transfers the underlying assets to the corresponding escrow.
- Functions which are not accessible to sanctioned entities no longer fail gracefully (in V1 they would block the account rather than revert). They now revert with an `AccountBlocked` error when the account is sanctioned.

**Withdrawal batch rounding**

Normalized values for withdrawal batch payments are now rounded down rather than up to prevent a bug where closed markets could have their last withdrawal batch become uncloseable due to underpayment by a few wei.

**Token rescue function**

For assets other than the market token itself or the underlying asset, ERC20 tokens sent to the contract can be recovered by the borrower.

**Market closure**

- When a borrower closes a market that has pending withdrawals or unpaid withdrawal batches, rather than reverting, the market now steps through the list of unpaid batches and closes them after transferring all remaining debt from the borrower.
- `closeMarket` now callable by borrower rather than controller.

**ReentrancyGuard**

The ReentrancyGuard now uses transient storage, using a modified version of 0age's ReentrancyGuard from Seaport.

**APR/reserve ratio setters**

- Removed `setAnnualInterestBips` and `setReserveRatioBips`
- Added `setAnnualInterestAndReserveRatioBips`
- Now callable by borrower rather than controller

**Misc.**

Replaced most of the remaining ABI decoders/encoders for calls and large structs with manual assembly coder functions.

- Custom encoder for writing MarketState to storage.
- Custom decoder for constructor parameters and factory call.
- Custom encoders for all sentinel calls in market.
- Custom name/symbol query functions
- Custom state initialization in constructor, only touching slots that are actually initialized.

### Market Control

Market controllers have been removed in favor of borrower-controlled markets with hooks that can impose their own restrictions. By default, the market itself does not restrict basic access to the market.
