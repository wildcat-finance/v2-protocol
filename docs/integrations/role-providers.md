# Role providers

Role providers supply credential timestamps to Wildcat access-control hooks.
Each hook chooses which providers it accepts and how long it caches their
results.

[`IRoleProvider`](../../src/access/IRoleProvider.sol) defines credential calls.
It does not define administration, deployment provenance, or product support.
Source presence alone does not make a provider supported.

## Audit scope

This branch includes AccessList, its factory, and the shared managed-provider
base. Other provider implementations and their deployment helpers are excluded.
The [audit scope](../releases/v2.5-audit-scope.md) defines the exact boundary.

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

The `type(uint32).max` cap is also the V2.x generation's absolute timestamp
horizon, not an indefinite-expiry encoding after that date. Once
`block.timestamp` exceeds 2106-02-07 06:28:15 UTC, a new or refreshed pull or
push credential cannot satisfy the current-time check. Markets and lender
positions must be retired before that boundary; see
[known limitations](../security/known-issues.md#timestamp-horizon).

A revert or invalid timestamp is a miss, so another provider can still succeed.
If a stateful validation call succeeds but returns less than one word, the hook
reverts. Its side effects cannot survive without a usable result.

## Factory model

The AccessList CREATE2 factory:

- namespaces the salt by the factory caller;
- exposes deterministic address calculation;
- emits a typed event with the initial configuration; and
- retains no ownership, upgrade path, or authority over the provider.

The address depends on the factory, caller, salt, and constructor inputs.

## Provider contracts

### `AccessListRoleProvider`

[`AccessListRoleProvider`](../../src/providers/AccessListRoleProvider.sol) is a
pull provider. It returns the current timestamp for a member and zero for
everyone else.

The administrator can add, remove, and enumerate members. Administration moves
through the optional two-step managed-provider interface. A transfer preserves
the provider address and membership.

Factory:
[`AccessListRoleProviderFactory`](../../src/providers/AccessListRoleProviderFactory.sol)

## Integration constraints

External token and vault providers can inspect current contract state only. They do not prove
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

[`MockRoleProvider`](../../test/mocks/MockRoleProvider.sol) has unrestricted test
setters and configurable failures. `LiveBalanceRoleProviderMock` reads real
market balances or wrapper share values for the integration regressions. These
are test fixtures, not provider implementations in the audit scope.

Provider tests:

- [`ManagedRoleProviders.t.sol`](../../test/providers/ManagedRoleProviders.t.sol)
- [`RoleProviderFactories.t.sol`](../../test/providers/RoleProviderFactories.t.sol)
