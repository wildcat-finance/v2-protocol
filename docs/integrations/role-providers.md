# Role providers

Role providers supply credential timestamps to Wildcat access-control hooks.
Each hook chooses which providers it accepts and how long it caches their
results.

[`IRoleProvider`](../../src/access/IRoleProvider.sol) defines credential calls.
It does not define administration, deployment provenance, or product support.
Source presence alone does not make a provider supported.

## V2.5 status

| Provider    | Status      | Deployment      |
| ----------- | ----------- | --------------- |
| Access list | Supported   | Sepolia factory |
| Merkle      | Source only | None            |
| ERC-20      | Source only | None            |
| ERC-4626    | Source only | None            |
| ERC-721     | Source only | None            |
| ERC-1155    | Source only | None            |
| ERC-5192    | Exploratory | None            |
| ERC-5484    | Exploratory | None            |
| Universal   | Development | Sepolia mock    |
| Mock        | Test only   | None            |

_Deployment_ means an address recorded in
[`deployments/`](../../deployments/). It does not include every provider anyone
has created permissionlessly. At this source commit, the tracked inventories
contain no V2.5 role-provider deployment on mainnet.

The [Sepolia inventory](../../deployments/sepolia/deployments.json) records:

- `AccessListRoleProviderFactory` at
  `0x92995EA2ba572E4Cb8bB41E30f813BeB77FD4974`
- the `UniversalProvider` development mock at
  `0x9aCdE253F7A51456c48604185C0ceA4Fc9e58E3a`

Source-only and exploratory providers still need product and security review,
plus SDK, subgraph, app, and release work.

## Hook model

A hook administrator attaches a provider with a TTL. The same provider can use
different TTLs on different hooks.

- **Pull providers** implement `getCredential(account)`. Hooks can refresh them
  without user data.
- **Validation providers** implement `validateCredential(account, data)`. The
  caller packs the data after the provider address in `hooksData`.
- **Push providers** call `grantRole` or `grantRoles` on the hook. An EOA, Safe,
  or smart account can be a push provider without implementing `IRoleProvider`.

Only an exact `true` response from `isPullProvider()` creates a pull provider.
A revert, false value, short response, or malformed boolean classifies it as
push-based.

`IRoleProvider` deliberately says nothing about ownership. Managed providers
can also implement
[`IManagedRoleProvider`](../../src/access/IManagedRoleProvider.sol), but hooks do
not require it.

## Credential lifetime and failure

A provider returns the timestamp when it granted a credential:

- zero means no credential;
- a future timestamp is invalid; and
- expiry is the timestamp plus the hook's TTL, capped at
  `type(uint32).max`.

A zero-TTL pull credential is checked on every gated interaction, including
another interaction in the same block. A positive TTL lets a cached credential
survive membership, balance, ownership, or root changes until expiry. Removing
a provider makes its cached credential unusable on the next check.

A revert or invalid timestamp is a miss, so another provider can still succeed.
If a stateful validation call succeeds but returns less than one word, the hook
reverts. Its side effects cannot survive without a usable result.

## Factory model

Access-list, Merkle, ERC-20, ERC-4626, ERC-721, and ERC-1155 providers each have
a CREATE2 factory. Every factory:

- namespaces the salt by the factory caller;
- exposes deterministic address calculation;
- emits a typed event with the initial configuration; and
- retains no ownership, upgrade path, or authority over the provider.

The address depends on the factory, caller, salt, and constructor inputs. Only
the access-list factory belongs to the tracked V2.5 deployment surface.

## Provider contracts

### `AccessListRoleProvider`

**Supported. Factory deployed on Sepolia.**

[`AccessListRoleProvider`](../../src/providers/AccessListRoleProvider.sol) is a
pull provider. It returns the current timestamp for a member and zero for
everyone else.

The administrator can add, remove, and enumerate members. Administration moves
through the optional two-step managed-provider interface. A transfer preserves
the provider address and membership.

Factory:
[`AccessListRoleProviderFactory`](../../src/providers/AccessListRoleProviderFactory.sol)

### `MerkleRoleProvider`

**Source only. No tracked factory deployment.**

[`MerkleRoleProvider`](../../src/providers/MerkleRoleProvider.sol) validates a
sorted-pair proof for `keccak256(abi.encode(account))`. The payload after the
packed provider address is `abi.encode(bytes32[] proof)`. Malformed payloads
return no credential.

The administrator can update the root and transfer administration through the
two-step managed-provider interface. The provider cannot enumerate members or
recover the source list. Operators must retain that list and its proof data
offchain.

Factory:
[`MerkleRoleProviderFactory`](../../src/providers/MerkleRoleProviderFactory.sol)

### `ERC20RoleProvider`

**Source only. No tracked factory deployment.**

[`ERC20RoleProvider`](../../src/providers/ERC20RoleProvider.sol) is a pull
provider. An account qualifies when `balanceOf(account) >= minBalance`.
`minBalance` is nonzero and uses token base units.

The token and threshold are immutable. There is no administrator. The
constructor checks that the token address has code, but cannot verify ERC-20
behavior.

Factory:
[`ERC20RoleProviderFactory`](../../src/providers/ERC20RoleProviderFactory.sol)

### `ERC4626AssetsRoleProvider`

**Source only. No tracked factory deployment.**

[`ERC4626AssetsRoleProvider`](../../src/providers/ERC4626AssetsRoleProvider.sol)
is a pull provider. An account qualifies when:

```text
convertToAssets(balanceOf(account)) >= minAssets
```

`minAssets` is nonzero and uses underlying-asset base units. The vault and
threshold are immutable, and there is no administrator. The provider does not
check redeemability, liquidity, fees, price, or holding history.

Factory:
[`ERC4626AssetsRoleProviderFactory`](../../src/providers/ERC4626AssetsRoleProviderFactory.sol)

### `ERC721RoleProvider`

**Source only. No tracked factory deployment.**

[`ERC721RoleProvider`](../../src/providers/ERC721RoleProvider.sol) is a pull
provider. Any positive collection balance qualifies; no specific token ID is
required.

The collection is immutable, and there is no administrator. The normal
constructor checks ERC-165 and ERC-721 support. `skipInterfaceCheck` only skips
deployment-time detection. It cannot repair an incompatible `balanceOf`.

Factory:
[`ERC721RoleProviderFactory`](../../src/providers/ERC721RoleProviderFactory.sol)

### `ERC1155RoleProvider`

**Source only. No tracked factory deployment.**

[`ERC1155RoleProvider`](../../src/providers/ERC1155RoleProvider.sol) is a pull
provider. Any positive balance of one configured token ID qualifies. Other
token IDs do not.

The collection and token ID are immutable, and there is no administrator. The
normal constructor checks ERC-165 and ERC-1155 support. `skipInterfaceCheck`
has the same narrow effect as the ERC-721 provider.

Factory:
[`ERC1155RoleProviderFactory`](../../src/providers/ERC1155RoleProviderFactory.sol)

### `ERC5192RoleProvider`

**Exploratory. No bundled factory.**

[`ERC5192RoleProvider`](../../src/providers/ERC5192RoleProvider.sol) validates
ownership of a supplied token ID and can require `locked(tokenId)` to return
true. The payload after the packed provider address is `abi.encode(tokenId)`.

The collection and lock requirement are immutable, and there is no
administrator. The normal constructor checks ERC-165, ERC-721, and ERC-5192
support. That check can be skipped.

### `ERC5484RoleProvider`

**Exploratory. No bundled factory.**

[`ERC5484RoleProvider`](../../src/providers/ERC5484RoleProvider.sol) validates
ownership of a supplied token ID. Its burn-authorization value must match an
immutable four-bit allow mask. The payload after the packed provider address is
`abi.encode(tokenId)`.

The collection and mask are immutable, and there is no administrator. The
normal constructor checks ERC-165, ERC-721, and ERC-5484 support. That check can
be skipped.

## Integration constraints

Token and vault providers inspect current contract state only. They do not prove
holding duration or stop an account from returning temporarily borrowed assets
later in the transaction. They trust the configured token or vault to report
balances and conversions honestly.

An ERC-20 market token or Wildcat ERC-4626 wrapper for Market A can authorize
access to Market B. It cannot authorize a state-changing action on its own
underlying Market A. The credential check would reenter Market A through a
guarded view and fail.

External providers may use different state, failure, and authority models.
Probe optional capabilities; do not infer them from `IRoleProvider`.

## Lens and indexer boundary

The V2.5 lens returns each attached provider's address, TTL, pull and push
indices, and optional managed-provider administration. It does not guess a
provider kind or add provider-specific configuration to the lens ABI.

Indexers should classify supported kinds from events emitted by known factory
addresses. Later provider events supply membership, root, and administrator
history. A provider without known factory provenance remains visible by address
and should stay classified as unknown.

- Hooks own attachment and credential caching.
- Providers own credential logic and provider-specific configuration.
- Indexers own typed history.

## Development contracts

[`UniversalProvider`](../../script/mock/UniversalProvider.sol) always returns
the current timestamp. It is a deployment helper, not a production authority
model, even though Sepolia inventory includes one.

[`MockRoleProvider`](../../test/mocks/MockRoleProvider.sol) has unrestricted test
setters and configurable failures. It is a test fixture only.

Provider tests:

- [`ManagedRoleProviders.t.sol`](../../test/providers/ManagedRoleProviders.t.sol)
- [`RoleProviderFactories.t.sol`](../../test/providers/RoleProviderFactories.t.sol)
- [`RoleProviderHookIntegration.t.sol`](../../test/providers/RoleProviderHookIntegration.t.sol)
- [`TokenRoleProviders.t.sol`](../../test/providers/TokenRoleProviders.t.sol)
