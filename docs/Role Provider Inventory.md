# Role Provider Inventory

This is the repository-scoped inventory for the v2.5 provider migration. It distinguishes production contracts from test fixtures and examples. `IRoleProvider` remains ownership-agnostic; administration is a capability of a particular provider, not a property the hook assumes.

| Provider | Location | Status | Credential model | Administration |
| --- | --- | --- | --- | --- |
| `AccessListRoleProvider` | `src/providers/AccessListRoleProvider.sol` | v2.5 production candidate | Pull provider. Returns the current timestamp while an account is a member and zero otherwise. | `IManagedRoleProvider` two-step administrator transfer. Membership and provider address survive transfer. |
| `ERC20RoleProvider` | `src/providers/ERC20RoleProvider.sol` | Exploratory | Pull provider. Requires a configured token balance at or above `minBalance`. | Ownerless. Token and threshold are immutable. |
| `ERC4626AssetsRoleProvider` | `src/providers/ERC4626AssetsRoleProvider.sol` | Exploratory | Pull provider. Converts the account's vault shares to assets and requires at least `minAssets`. | Ownerless. Vault and threshold are immutable. |
| `ERC721RoleProvider` | `src/providers/ERC721RoleProvider.sol` | Exploratory | Pull provider. Requires a non-zero balance in the configured collection. | Ownerless. Collection is immutable. |
| `ERC1155RoleProvider` | `src/providers/ERC1155RoleProvider.sol` | Exploratory | Pull provider. Requires a non-zero balance of one configured token ID. | Ownerless. Collection and token ID are immutable. |
| `ERC5192RoleProvider` | `src/providers/ERC5192RoleProvider.sol` | Exploratory | Validation provider. Checks ownership of the token ID supplied in hooks data and can require the token to be locked. | Ownerless. Collection and lock requirement are immutable. |
| `ERC5484RoleProvider` | `src/providers/ERC5484RoleProvider.sol` | Exploratory | Validation provider. Checks ownership of the token ID supplied in hooks data and an allowed burn-authorization mask. | Ownerless. Collection and mask are immutable. |
| `MerkleRoleProvider` | `src/providers/MerkleRoleProvider.sol` | Exploratory | Validation provider. Verifies a sorted-pair proof for `keccak256(abi.encode(account))`. | `IManagedRoleProvider` two-step administrator transfer. The administrator can update the root. |
| `UniversalProvider` | `script/mock/UniversalProvider.sol` | Local deployment mock | Pull and validation provider. Always returns the current timestamp. | Ownerless and immutable. |
| `MockRoleProvider` | `test/shared/mocks/MockRoleProvider.sol` | Test fixture | Configurable pull, push, stored credential, or signature-validation behavior. | Unrestricted test setters; not a production authority model. |
| `AlwaysAuthorizedRoleProvider` | `test/shared/mocks/AlwaysAuthorizedRoleProvider.sol` | Test fixture | Always returns the current timestamp. | Ownerless and immutable. |
| EOA, Safe, or smart-account push provider | No provider contract required | Supported integration shape | Calls `grantRole` or `grantRoles` on a hook directly. The hook stores the pushed timestamp and TTL. | Defined by the calling account, not by `IRoleProvider`. |

The exploratory providers are compatibility proofs, not part of the v2.5 deployment ceremony. They have no bundled factories, SDK encoders, or app flows. Each can be deployed independently and attached through `addRoleProvider`. They need separate product, security, and integration review before production use.

Membership and configuration changes follow the TTL selected for that provider on each hook. A zero TTL rechecks pull-provider membership on every access check and requires validation providers to supply fresh data after the current timestamp. A positive TTL deliberately allows a previously granted credential to remain cached until it expires. Dynamic token balances, token ownership, and Merkle roots should use zero or a deliberately short TTL unless delayed revocation is acceptable.

`ERC5192RoleProvider` and `ERC5484RoleProvider` expect `abi.encode(tokenId)` after the packed provider address. `MerkleRoleProvider` expects `abi.encode(proof)` after the provider address. Malformed validation data fails closed.

External providers may use different persistence and authority models, so SDK and migration tooling must probe optional capabilities rather than infer them from `IRoleProvider`.

## Access-list factory provenance

`AccessListRoleProviderFactory` emits the provider address, intended administrator, actual factory caller, caller-scoped salt, and initial member list. It has no owner, registry role, upgrade path, or callable authority over a deployed provider. The provider itself exposes current membership and paginated enumeration, so current state does not depend on replaying factory or membership events.
