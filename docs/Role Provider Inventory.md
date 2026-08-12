# Role Provider Inventory

This is the repository-scoped inventory for the v2.5 provider migration. It distinguishes production contracts from test fixtures and examples. `IRoleProvider` remains ownership-agnostic; administration is a capability of a particular provider, not a property the hook assumes.

| Provider | Location | Status | Credential model | Administration |
| --- | --- | --- | --- | --- |
| `AccessListRoleProvider` | `src/access/AccessListRoleProvider.sol` | v2.5 production candidate | Pull provider. Returns the current timestamp while an account is a member and zero otherwise. | `IManagedRoleProvider` two-step administrator transfer. Membership and provider address survive transfer. |
| `UniversalProvider` | `script/mock/UniversalProvider.sol` | Local deployment mock | Pull and validation provider. Always returns the current timestamp. | Ownerless and immutable. |
| `MockRoleProvider` | `test/shared/mocks/MockRoleProvider.sol` | Test fixture | Configurable pull, push, stored credential, or signature-validation behavior. | Unrestricted test setters; not a production authority model. |
| `AlwaysAuthorizedRoleProvider` | `test/shared/mocks/AlwaysAuthorizedRoleProvider.sol` | Test fixture | Always returns the current timestamp. | Ownerless and immutable. |
| EOA, Safe, or smart-account push provider | No provider contract required | Supported integration shape | Calls `grantRole` or `grantRoles` on a hook directly. The hook stores the pushed timestamp and TTL. | Defined by the calling account, not by `IRoleProvider`. |
| Merkle-proof provider | No implementation in this repository | Example/future design only | `validateCredential` could verify a proof, but no root storage or persistence model is defined here. | Undefined until a concrete provider is designed. |

No other production role-provider implementation was found in this repository. External providers may use different persistence and authority models, so SDK and migration tooling must probe optional capabilities rather than infer them from `IRoleProvider`.

## Access-list factory provenance

`AccessListRoleProviderFactory` emits the provider address, intended administrator, actual factory caller, caller-scoped salt, and initial member list. It has no owner, registry role, upgrade path, or callable authority over a deployed provider. The provider itself exposes current membership and paginated enumeration, so current state does not depend on replaying factory or membership events.
