# KYCRoleProvider audit scope

Audit scope for `KYCRoleProvider`, branched from `develop` (`91ce3715` —
`feat/kyc-roleprovider` on top of `main` / `v2.1.0`).

Only the three new Solidity files below are in scope. The rest of the repo and
test suite stay here so you can compile and run the v2.0/v2.1 hook and market
integration tests.

## In-scope contracts

| File | Kind | Lines | Physical SLOC | nSLOC |
| --- | --- | ---: | ---: | ---: |
| [`src/access/IManagedRoleProvider.sol`](../../src/access/IManagedRoleProvider.sol) | Interface | 77 | 19 | 14 |
| [`src/providers/ManagedRoleProvider.sol`](../../src/providers/ManagedRoleProvider.sol) | Abstract contract | 85 | 38 | 38 |
| [`src/providers/KYCRoleProvider.sol`](../../src/providers/KYCRoleProvider.sol) | Deployable contract | 131 | 51 | 51 |
| **Total** | **3 files (1 deployable)** | **293** | **108** | **103** |

`nSLOC` uses `solidity-code-metrics@0.0.28` (non-blank, non-comment lines with
multi-line headers collapsed). Physical SLOC drops blanks and comments without
collapsing headers. Reproduce `nSLOC`:

```sh
npx --yes --package solidity-code-metrics@0.0.28 solidity-code-metrics \
  src/access/IManagedRoleProvider.sol \
  src/providers/ManagedRoleProvider.sol \
  src/providers/KYCRoleProvider.sol
```

Pin the final report to the reviewed commit SHA on `audit/kyc-role-provider`,
not the branch name.

## Review focus

Full behavior and hook rules live in the
[KYCRoleProvider spec](../hooks/kyc-role-provider.md).

- **Two-step authority (`ManagedRoleProvider`, `IManagedRoleProvider`):**
  - Nonzero initial admin; `requestAdministratorTransfer` rejects zero and current admin, and overwrites any prior pending nominee.
  - Authority doesn't move until `pendingAdministrator` calls `acceptAdministratorTransfer`, which clears the pending slot. `cancelAdministratorTransfer` is admin-only and reverts when nothing's pending.
  - Provider authority is separate from hooks admin and `ArchController` registration. Attaching this provider to a hook gives that hook no control over the list.
- **Membership (`KYCRoleProvider`):**
  - All writes (`addMember`, `addMembers`, `removeMember`, `removeMembers`) are `onlyAdministrator`.
  - Zero address, duplicate adds, and removing an unlisted wallet all revert. Batch calls are atomic — one bad or repeated entry reverts the whole batch.
  - `addedAt` stores the enrollment timestamp and clears to `0` on removal; `isMember` reads the same slot (`addedAt != 0`). Re-adding overwrites `addedAt` with the new block timestamp.
- **Credentials (`KYCRoleProvider`):**
  - `isPullProvider()` is constant `true`.
  - `getCredential(account)` returns `uint32(block.timestamp)` for members and `0` otherwise. `validateCredential(account, data)` ignores `data` and returns the same result.
  - Member lookups cast via `SafeCastLib.toUint32` so timestamps past `type(uint32).max` revert (`Panic(0x11)`) instead of wrapping.
- **Hook integration:**
  - Works with deployed v2.0/v2.1 open- and fixed-term hooks and stays forward-compatible with v2.5 hooks.
  - Sharing one provider across borrowers doesn't share opt-in consent, TTLs, or cached lender state across hooks.

## Exclusions

- **Tests (`test/**`, `compat/**`):** verification support only; excluded from scope and SLOC.
- **Pre-existing contracts (`src/**` outside the three files above):** build and integration context only. Direct imports `src/access/IRoleProvider.sol` and `src/libraries/SafeCastLib.sol` haven't changed since `v2.0.0`.
- **Dependencies and repo tooling (`lib/**`, `deployments/`, `script/`, `scripts/`, `EIP-4626_audit_scope.md`, `.horos/`, `AGENTS.md`):** out of scope. None of the three in-scope files import from `lib/`.

Prior v2.0 (aleph_v, Code4rena) and v2.1 wrapper (Côme du Crest) reviews don't
cover `KYCRoleProvider`.

## Trust model and accepted behavior

- **Provider admin:** trusted Wildcat Protocol EOA or Foundation wallet. Sole writer for membership and admin handoff; batch gas sizing is the caller's responsibility.
- **Hooks borrower / admin:** opts in per hooks instance via `addRoleProvider(provider, ttl)` and picks the TTL.
- **Callers and lenders:** untrusted. All reads are public, and wallet addresses, enrollment times, events, and calldata are public onchain — keep PII offchain.
- **Removal vs. cached approvals:** removing a member zeros `getCredential` and `validateCredential` immediately, but a hook can still honor a cached approval until its TTL expires. On v2.0/v2.1 hooks, a zero TTL can reuse an approval within the same block timestamp.
- **Known lenders after removal:** once a wallet is a known lender on a market, removing it from KYC doesn't block receiving market tokens, queueing withdrawals, or claiming under the market's rules.
- **`uint32` timestamp ceiling:** `IRoleProvider` returns `uint32`. Past `type(uint32).max` (year 2106), member lookups revert with `Panic(0x11)` while unlisted wallets still return `0`.

## Build and test

Pinned to Foundry `v1.8.3` (`.foundry-version`) and Solc `0.8.25`
(`foundry.toml`, EVM `cancun`, `bytecode_hash = 'none'`, default profile).

```sh
git submodule update --init --recursive
forge test --match-path 'test/providers/*.t.sol' --summary
```

| Test suite | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| `KYCRoleProviderTest` (unit + 1,000-run fuzz) | 7 | 0 | 0 |
| `KYCRoleProviderHooksTest` (mainnet v2.0/v2.1 hook artifacts) | 2 | 0 | 0 |
| `KYCRoleProviderMarketsTest` (open + fixed markets, TTL 0 and 1h) | 2 | 0 | 0 |

For the optional v2.5 forward-compatibility checks, see
[Acceptance checks](../hooks/kyc-role-provider.md#acceptance-checks).
