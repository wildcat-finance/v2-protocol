# Role Providers

Role providers supply credential timestamps to Wildcat access-control hooks.
Each hook chooses which providers to accept and how long to cache their results.
[`IRoleProvider`](../../src/access/IRoleProvider.sol) defines credential calls;
it does not define administration, deployment provenance, or product support.

This page distinguishes the supported V2.5 surface from additional contracts
present in the repository. Source presence alone does not imply deployment or
support.

## V2.5 status

| Provider | Status | Deployment |
| --- | --- | --- |
| Access list | Supported | Sepolia factory |
| Merkle | Source only | — |
| ERC-20 | Source only | — |
| ERC-4626 | Source only | — |
| ERC-721 | Source only | — |
| ERC-1155 | Source only | — |
| ERC-5192 | Exploratory | — |
| ERC-5484 | Exploratory | — |
| Universal | Development | Sepolia mock |
| Mock | Test only | — |

`Deployment` means an address recorded in [`deployments/`](../../deployments/),
not every provider instance created permissionlessly. At this source commit,
the tracked inventories contain no V2.5 role-provider deployment on mainnet.

The [Sepolia inventory](../../deployments/sepolia/deployments.json) records:

- `AccessListRoleProviderFactory` at
  `0x92995EA2ba572E4Cb8bB41E30f813BeB77FD4974`.
- `UniversalProvider`, a development mock, at
  `0x9aCdE253F7A51456c48604185C0ceA4Fc9e58E3a`.

Source-only and exploratory providers require product and security review plus
SDK, subgraph, app, and release integration before they become supported.

## Hook model

A hook administrator attaches each provider with a provider-specific
time-to-live (TTL). The same provider may be attached to several hooks with
different TTLs.

- **Pull providers** return a grant timestamp from `getCredential(account)`.
  Hooks can refresh them without user-supplied data.
- **Validation providers** return a grant timestamp from
  `validateCredential(account, data)`. The caller supplies the data after the
  packed provider address in `hooksData`.
- **Push providers** call `grantRole` or `grantRoles` on the hook. An EOA, Safe,
  or smart account can be a push provider without implementing
  `IRoleProvider`.

Only an exact `true` response from `isPullProvider()` classifies an address as
pull-based. A revert, false value, short response, or malformed boolean
classifies it as push-based.

`IRoleProvider` is deliberately ownership-agnostic. Managed providers may also
implement
[`IManagedRoleProvider`](../../src/access/IManagedRoleProvider.sol), which the
hooks do not require.

## Credential lifetime and failure

A provider returns the timestamp when it granted the credential. Zero means no
credential. Future timestamps are invalid. The hook adds the provider TTL and
caps the result at `type(uint32).max`.

A zero-TTL pull credential is rechecked on every gated interaction, including
another interaction in the same block. A positive TTL deliberately allows a
cached credential to survive membership, balance, ownership, or root changes
until expiry. Removing a provider prevents its cached credential from being
used by later checks.

A provider revert or invalid timestamp grants nothing on the ordinary hook
path, and a later provider may still succeed. A successful stateful validation
call that returns less than one word reverts so its side effects cannot survive
without a usable result.

## Factory model

The access-list, Merkle, ERC-20, ERC-4626, ERC-721, and ERC-1155 providers each
have a CREATE2 factory. Every factory:

- namespaces the supplied salt by the factory caller;
- exposes deterministic address calculation;
- emits a typed event containing the initial configuration; and
- retains no ownership, upgrade path, or authority over the provider.

The resulting address depends on the factory, caller, supplied salt, and
constructor inputs. Only the access-list factory is part of the tracked V2.5
deployment surface.

## Providers

### `AccessListRoleProvider`

**Status:** supported. Its
[`AccessListRoleProviderFactory`](../../src/providers/AccessListRoleProviderFactory.sol)
is deployed on Sepolia.

[`AccessListRoleProvider`](../../src/providers/AccessListRoleProvider.sol) is a
pull provider. It returns the current timestamp while an account is a member
and zero otherwise.

The administrator can add or remove members and enumerate the current set.
Administration moves through the optional two-step managed-provider interface.
The provider address and membership survive an administrator transfer.

### `MerkleRoleProvider`

**Status:** source only. Its
[`MerkleRoleProviderFactory`](../../src/providers/MerkleRoleProviderFactory.sol)
has no tracked deployment.

[`MerkleRoleProvider`](../../src/providers/MerkleRoleProvider.sol) is a
validation provider. It verifies a sorted-pair proof for
`keccak256(abi.encode(account))`. The validation payload is
`abi.encode(bytes32[] proof)` after the packed provider address. Malformed
payloads return no credential.

The administrator can update the root and transfer administration through the
two-step managed-provider interface. The provider cannot enumerate members or
recover the source list. Operators must retain the canonical list and proof
data offchain.

### `ERC20RoleProvider`

**Status:** source only. Its
[`ERC20RoleProviderFactory`](../../src/providers/ERC20RoleProviderFactory.sol)
has no tracked deployment.

[`ERC20RoleProvider`](../../src/providers/ERC20RoleProvider.sol) is a pull
provider. An account qualifies when `balanceOf(account) >= minBalance`.
`minBalance` is nonzero and expressed in token base units.

The token and threshold are immutable. The provider has no administrator. It
checks that the token address contains code but cannot verify ERC-20 behavior.

### `ERC4626AssetsRoleProvider`

**Status:** source only. Its
[`ERC4626AssetsRoleProviderFactory`](../../src/providers/ERC4626AssetsRoleProviderFactory.sol)
has no tracked deployment.

[`ERC4626AssetsRoleProvider`](../../src/providers/ERC4626AssetsRoleProvider.sol)
is a pull provider. It qualifies an account when
`convertToAssets(balanceOf(account)) >= minAssets`. `minAssets` is nonzero and
expressed in underlying-asset base units.

The vault and threshold are immutable. The provider has no administrator. It
does not check redeemability, liquidity, fees, price, or holding history.

### `ERC721RoleProvider`

**Status:** source only. Its
[`ERC721RoleProviderFactory`](../../src/providers/ERC721RoleProviderFactory.sol)
has no tracked deployment.

[`ERC721RoleProvider`](../../src/providers/ERC721RoleProvider.sol) is a pull
provider. Any positive collection balance qualifies; no particular token ID is
required.

The collection is immutable and the provider has no administrator. The normal
constructor path verifies ERC-165 and ERC-721 support. `skipInterfaceCheck`
bypasses deployment-time detection only; it does not repair an incompatible
`balanceOf` implementation.

### `ERC1155RoleProvider`

**Status:** source only. Its
[`ERC1155RoleProviderFactory`](../../src/providers/ERC1155RoleProviderFactory.sol)
has no tracked deployment.

[`ERC1155RoleProvider`](../../src/providers/ERC1155RoleProvider.sol) is a pull
provider. Any positive balance of one configured token ID qualifies. Balances
of other token IDs do not.

The collection and token ID are immutable. The provider has no administrator.
The normal constructor path verifies ERC-165 and ERC-1155 support.
`skipInterfaceCheck` has the same narrow behavior as the ERC-721 provider.

### `ERC5192RoleProvider`

**Status:** exploratory. It has no bundled factory.

[`ERC5192RoleProvider`](../../src/providers/ERC5192RoleProvider.sol) is a
validation provider. It verifies ownership of a supplied token ID and may also
require `locked(tokenId)` to return true. The validation payload is
`abi.encode(tokenId)` after the packed provider address.

The collection and lock requirement are immutable. The provider has no
administrator. The normal constructor path verifies ERC-165, ERC-721, and
ERC-5192 support; the interface check may be skipped.

### `ERC5484RoleProvider`

**Status:** exploratory. It has no bundled factory.

[`ERC5484RoleProvider`](../../src/providers/ERC5484RoleProvider.sol) is a
validation provider. It verifies ownership of a supplied token ID and requires
its burn-authorization value to match an immutable four-bit allow mask. The
validation payload is `abi.encode(tokenId)` after the packed provider address.

The collection and mask are immutable. The provider has no administrator. The
normal constructor path verifies ERC-165, ERC-721, and ERC-5484 support; the
interface check may be skipped.

## Integration constraints

Token and vault providers observe current contract state only. They do not
prove holding duration or prevent an account from returning temporarily
borrowed assets later in the transaction. They trust the configured token or
vault to report balances and conversions honestly.

An ERC-20 market token or Wildcat ERC-4626 wrapper for Market A can authorize
access to Market B. It cannot authorize a state-changing action against its own
underlying Market A: the credential check would reenter Market A through a
guarded view and fail.

External providers may use different state, failure, and authority models.
Integrations must probe optional capabilities rather than infer them from
`IRoleProvider`.

## Lens and indexer boundary

The V2.5 lens reports each attached provider's address, TTL, pull and push
indexes, and optional managed-provider administration. It does not infer a
provider kind or copy provider-specific configuration into the lens ABI.

Indexers should classify supported provider kinds from events emitted by known
factory addresses. Mutable provider events supply later membership, root, and
administrator history. An attached provider without known factory provenance
remains visible by address and should be classified as unknown.

Hooks own provider attachment and credential caching. Providers own credential
logic and provider-specific configuration. Indexers own typed historical
projection.

## Development contracts

[`UniversalProvider`](../../script/mock/UniversalProvider.sol) always returns
the current timestamp. It is a deployment helper, not a production authority
model, even though an instance is recorded in the Sepolia inventory.

[`MockRoleProvider`](../../test/mocks/MockRoleProvider.sol) exposes unrestricted
test setters and configurable failure behavior. It is a test fixture only.

Provider behavior is covered by:

- [`ManagedRoleProviders.t.sol`](../../test/providers/ManagedRoleProviders.t.sol)
- [`RoleProviderFactories.t.sol`](../../test/providers/RoleProviderFactories.t.sol)
- [`RoleProviderHookIntegration.t.sol`](../../test/providers/RoleProviderHookIntegration.t.sol)
- [`TokenRoleProviders.t.sol`](../../test/providers/TokenRoleProviders.t.sol)
