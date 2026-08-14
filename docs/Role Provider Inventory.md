# Role Provider Inventory

This is the repository-scoped inventory for the v2.5 provider migration. It distinguishes production contracts from test fixtures and examples. `IRoleProvider` remains ownership-agnostic; administration is a capability of a particular provider, not a property the hook assumes.

| Provider | Location | Status | Credential model | Administration |
| --- | --- | --- | --- | --- |
| `AccessListRoleProvider` | `src/providers/AccessListRoleProvider.sol` | v2.5 production candidate | Pull provider. Returns the current timestamp while an account is a member and zero otherwise. | `IManagedRoleProvider` two-step administrator transfer. Membership and provider address survive transfer. |
| `ERC20RoleProvider` | `src/providers/ERC20RoleProvider.sol` | v2.5 production candidate, not scheduled for deployment | Pull provider. Requires a configured token balance at or above `minBalance`. | Ownerless. Token and threshold are immutable. |
| `ERC4626AssetsRoleProvider` | `src/providers/ERC4626AssetsRoleProvider.sol` | v2.5 production candidate, not scheduled for deployment | Pull provider. Converts the account's vault shares to assets and requires at least `minAssets`. | Ownerless. Vault and threshold are immutable. |
| `ERC721RoleProvider` | `src/providers/ERC721RoleProvider.sol` | Exploratory | Pull provider. Requires a non-zero balance in the configured collection. | Ownerless. Collection is immutable. |
| `ERC1155RoleProvider` | `src/providers/ERC1155RoleProvider.sol` | Exploratory | Pull provider. Requires a non-zero balance of one configured token ID. | Ownerless. Collection and token ID are immutable. |
| `ERC5192RoleProvider` | `src/providers/ERC5192RoleProvider.sol` | Exploratory | Validation provider. Checks ownership of the token ID supplied in hooks data and can require the token to be locked. | Ownerless. Collection and lock requirement are immutable. |
| `ERC5484RoleProvider` | `src/providers/ERC5484RoleProvider.sol` | Exploratory | Validation provider. Checks ownership of the token ID supplied in hooks data and an allowed burn-authorization mask. | Ownerless. Collection and mask are immutable. |
| `MerkleRoleProvider` | `src/providers/MerkleRoleProvider.sol` | v2.5 production candidate, not scheduled for deployment | Validation provider. Verifies a sorted-pair proof for `keccak256(abi.encode(account))`. | `IManagedRoleProvider` two-step administrator transfer. The administrator can update the root. |
| `UniversalProvider` | `script/mock/UniversalProvider.sol` | Local deployment mock | Pull and validation provider. Always returns the current timestamp. | Ownerless and immutable. |
| `MockRoleProvider` | `test/shared/mocks/MockRoleProvider.sol` | Test fixture | Configurable pull, push, stored credential, or signature-validation behavior. | Unrestricted test setters; not a production authority model. |
| `AlwaysAuthorizedRoleProvider` | `test/shared/mocks/AlwaysAuthorizedRoleProvider.sol` | Test fixture | Always returns the current timestamp. | Ownerless and immutable. |
| EOA, Safe, or smart-account push provider | No provider contract required | Supported integration shape | Calls `grantRole` or `grantRoles` on a hook directly. The hook stores the pushed timestamp and TTL. | Defined by the calling account, not by `IRoleProvider`. |

The remaining NFT token providers are compatibility proofs and are not part of the v2.5 deployment ceremony. They have no bundled factories, SDK encoders, or app flows. Each can be deployed independently and attached through `addRoleProvider`. They need separate product, security, and integration review before production use.

`MerkleRoleProvider`, `ERC20RoleProvider`, and `ERC4626AssetsRoleProvider` are production candidates with their own factories, but none are scheduled for the v2.5 deployment ceremony. They still need subgraph, SDK, app, and release integration before they can be treated as supported products.

ERC20 and ERC4626 thresholds must be greater than zero. Providers that check ERC165 reject contracts with invalid ERC165 behavior unless interface checking is explicitly skipped. Skipping the constructor check does not make an incompatible token valid; later credential checks still fail if the required token call is unavailable.

Token and vault providers prove only the state visible during a credential check. They do not prove how long an account held an asset or prevent it from returning borrowed assets later in the transaction. The ERC20 provider trusts the configured token's `balanceOf` result, and the ERC4626 provider trusts the configured vault's `convertToAssets` result. Neither is a price oracle. Provider selection and TTL must account for those properties.

Membership and configuration changes follow the TTL selected for that provider on each hook. A zero TTL rechecks pull-provider membership on every access check and requires validation providers to supply fresh data after the current timestamp. A positive TTL deliberately allows a previously granted credential to remain cached until it expires. Dynamic token balances, token ownership, and Merkle roots should use zero or a deliberately short TTL unless delayed revocation is acceptable.

`ERC5192RoleProvider` and `ERC5484RoleProvider` expect `abi.encode(tokenId)` after the packed provider address. `MerkleRoleProvider` expects `abi.encode(proof)` after the provider address. Malformed validation data fails closed.

External providers may use different persistence and authority models, so SDK and migration tooling must probe optional capabilities rather than infer them from `IRoleProvider`.

## Access-list factory provenance

`AccessListRoleProviderFactory` emits the provider address, intended administrator, actual factory caller, caller-scoped salt, and initial member list. It has no owner, registry role, upgrade path, or callable authority over a deployed provider. The provider itself exposes current membership and paginated enumeration, so current state does not depend on replaying factory or membership events.

## Merkle provider construction

`MerkleRoleProviderFactory` follows the same authority and CREATE2 rules as the access-list factory. It emits the provider address, intended administrator, actual factory caller, caller-scoped salt, and initial root. It has no owner, registry role, upgrade path, or callable authority over a deployed provider.

The leaf for an account is `keccak256(abi.encode(account))`. Each tree level hashes the two child values in ascending byte order. `validateCredential` accepts only the canonical `abi.encode(bytes32[] proof)` payload after the packed provider address. A zero root is allowed and behaves as an empty list unless somebody can produce a proof for it.

The provider stores only the root. It cannot enumerate members or recover the source list, so the administrator must keep the canonical list and proof-generation data somewhere else. Root updates and administrator transfers are observable onchain, but the list itself is not. A zero-TTL credential remains usable for the rest of its block timestamp and needs a fresh proof once the timestamp advances.

## ERC20 provider construction

`ERC20RoleProviderFactory` deploys one immutable provider configuration from a token, a minimum balance, and a caller-scoped salt. The factory and provider have no administrator, upgrade path, or authority to change the token or threshold after deployment. The deployment event records the provider, token, factory caller, supplied salt, and threshold.

Eligibility is `token.balanceOf(account) >= minBalance`. The threshold is inclusive and uses the token's base units. The constructor checks that the token address has code, but ERC20 has no ERC165 interface to probe. The hook administrator is responsible for trusting the selected token. A malicious or nonconforming token can lie or revert, and a rebasing token can change eligibility without a transfer.

The provider checks current balance, not holding time. A temporary or borrowed balance can satisfy the threshold during a check. TTL `0` rechecks the balance on every gated interaction, including another interaction in the same block. A positive TTL deliberately lets access survive until the cached credential expires after the account transfers the tokens. If `balanceOf` reverts, the hook treats that provider as granting no credential and may still accept a later provider.

A Wildcat market token for Market A can authorize access to Market B as the lender's claim grows with interest. It cannot authorize a state-changing action on Market A itself. That path calls Market A's guarded `balanceOf` while Market A is already executing, so the view reentrancy guard rejects it. This limit is intentional. The provider does not weaken the market guard.

## ERC-4626 assets provider construction

`ERC4626AssetsRoleProviderFactory` deploys one immutable provider configuration from a vault, a minimum asset threshold, and a caller-scoped salt. The factory and provider have no administrator, upgrade path, or authority to change the vault or threshold after deployment. The deployment event records the provider, vault, factory caller, supplied salt, and threshold.

Eligibility is `vault.convertToAssets(vault.balanceOf(account)) >= minAssets`. The threshold is inclusive and uses the underlying asset's base units. It measures the vault's current ideal conversion for the shares held directly by the account. It does not check `maxRedeem`, liquidity, fees, holding time, or whether the shares were borrowed. A malicious or nonconforming vault can report a misleading value, so the hook administrator is responsible for trusting the selected vault.

TTL `0` rechecks the share balance and conversion on every gated interaction, including another interaction in the same block. A positive TTL deliberately lets access survive until the cached credential expires after the account transfers or redeems its shares. If the vault reverts, the provider call reverts. The hook treats that as no credential and may still accept a later provider.

A Wildcat wrapper for Market A can authorize access to Market B as the wrapped claim grows with interest. The wrapper cannot authorize a state-changing action on its own wrapped market. That path would read Market A's `scaleFactor()` while Market A is already executing, and the market's view reentrancy guard rejects it. This limit is intentional. The provider does not weaken the market guard.
