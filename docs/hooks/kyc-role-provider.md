# KYCRoleProvider

Borrowers can share one `KYCRoleProvider` across their markets. Anyone can look up a wallet by address. Wallet addresses, enrollment times, membership changes, and transaction calldata are public. Keep identity records and other personal information in secure offchain storage.

## Membership and authority

- The constructor takes a nonzero administrator and starts with an empty list. A Wildcat Protocol EOA or a Foundation-controlled wallet can hold this role.
- The administrator uses `addMember` and `removeMember` for one wallet, or `addMembers` and `removeMembers` for a batch. Adding the zero address or an existing member reverts. Removing an unlisted wallet reverts. One invalid or repeated entry reverts the whole batch.
- `addedAt(account)` returns the block timestamp of the wallet's current enrollment, or `0` for an unlisted wallet. Removal clears the timestamp, and re-adding the wallet records the new block time.
- `isMember(account)` returns true when `addedAt(account)` is nonzero. Both getters read the same slot for that wallet. Reconstruct a wallet's enrollment history from `MemberAdded` and `MemberRemoved`. Both events index the wallet and administrator.
- The administrator can nominate a successor, replace the nominee, or cancel the transfer. Only the nominee can accept, and authority passes on acceptance. The provider checks `msg.sender` against its own administrator addresses, independently of borrower registration and hook attachment. [ManagedRoleProvider](../../src/providers/ManagedRoleProvider.sol)

## Hook compatibility

To opt in, call `addRoleProvider(provider, timeToLive)` on the market's hooks instance. The borrower makes this call in v2.0 and v2.1. The hooks administrator makes it in v2.5. Each instance sets a time to live (TTL) in seconds for each provider it trusts. [Legacy hooks](../../src/access/BaseAccessControls.sol) · [v2.5 hooks](https://github.com/wildcat-finance/v2-protocol/blob/27b3f79e698c4d25573ba336597c4a9403e117df/src/access/BaseAccessControls.sol)

| Provider call | Result |
| --- | --- |
| `isPullProvider()` | `true` |
| `getCredential(address account)` | Current block timestamp as a `uint32` for a member, `0` otherwise |
| `validateCredential(address account, bytes data)` | Same result as `getCredential(account)` for any payload, including empty bytes |

Both hook generations measure the TTL from the timestamp the provider returns. An enrolled wallet can get a fresh credential after an earlier approval expires. Both credential calls revert for a member if the block timestamp exceeds `type(uint32).max`. [KYC provider](../../src/providers/KYCRoleProvider.sol) · [Legacy interface](../../src/access/IRoleProvider.sol) · [v2.5 interface](https://github.com/wildcat-finance/v2-protocol/blob/27b3f79e698c4d25573ba336597c4a9403e117df/src/access/IRoleProvider.sol) · [v2.5 access-list provider](https://github.com/wildcat-finance/v2-protocol/blob/27b3f79e698c4d25573ba336597c4a9403e117df/src/providers/AccessListRoleProvider.sol)

Removal makes both credential calls return `0` immediately. A hook can still honor a cached approval through its expiry timestamp or accept a credential from another trusted provider. With a zero TTL, v2.0 and v2.1 can reuse an approval at the same block timestamp. A v2.5 hook checks the provider again whenever it needs that credential. [Legacy expiry check](../../src/types/LenderStatus.sol) · [v2.5 credential checks](https://github.com/wildcat-finance/v2-protocol/blob/27b3f79e698c4d25573ba336597c4a9403e117df/src/access/BaseAccessControls.sol)

Both generations track known lenders per market. A removed wallet that is already a known lender can still receive market tokens or queue a withdrawal under the market's other rules. [Legacy transfer and withdrawal checks](../../src/access/OpenTermHooks.sol) · [v2.5 transfer and withdrawal checks](https://github.com/wildcat-finance/v2-protocol/blob/27b3f79e698c4d25573ba336597c4a9403e117df/src/access/BaseHooks.sol)

## Release base

`feat/kyc-roleprovider` was authored against `v2.1.0` (`c7be4039`) and integrated into `develop` (`91ce3715`, with CI updates). See the [KYCRoleProvider Audit Scope](../releases/kyc-role-provider-audit-scope.md) for the audit boundary and SLOC counts. Its open-term and fixed-term hook sources match `v2.0.0` and `release/ink` at `c3ae324e`. The access-list reference and v2.5 integration tests use `release/v2.5` at `27b3f79e`. [v2.1.0](https://github.com/wildcat-finance/v2-protocol/tree/c7be4039f8f383a9dda4e45f63331c17d63f9ed9) · [Ink source](https://github.com/wildcat-finance/v2-protocol/tree/c3ae324eb3a61bf653736018d63d85fce94f0880)

At Ethereum block 26,436,762, the mainnet hooks factory had three enabled templates. The open-term and 365-day fixed-term templates matched the tagged deployment artifacts. Recompiling the fixed-term artifact with only `MaximumLoanTerm` set to 730 days reproduced the third template's complete stored creation code. All three use the legacy provider logic. [Mainnet hooks factory](https://etherscan.io/address/0xdd7dd3b5076cf89440d05585ff56d246386207be#readContract) · [Tagged deployment records](https://github.com/wildcat-finance/v2-protocol/tree/c7be4039f8f383a9dda4e45f63331c17d63f9ed9/deployments/mainnet) · [730-day template](https://etherscan.io/address/0x731c775385d0efb2caC61074Ba2d885D343A09cD#code)

## Acceptance checks

- Membership tests cover single and batch edits, rollback, administrator handoff, and the difference between enrollment time and credential lookup time.
- Hook tests attach the provider to two borrowers' hooks, then detach it from one. Only the hooks instance that still trusts the provider admits the wallet. After removing a member, the tests check access at the original lookup timestamp, at cache expiry, and one second later. The legacy tests use the tagged Ethereum open- and fixed-term hook artifacts.
- Market tests use factory-deployed markets. A deposit with explicit credential data moves underlying assets and mints market tokens. On transfer, the hook calls `getCredential` for the recipient. With KYC as the lender's only approval, removal blocks fresh deposits once the cache expires. Re-enrollment restores access. A known recipient can still receive market tokens, queue a withdrawal, and claim the underlying after removal. [Shared market tests](../../test/providers/KYCMarketLifecycle.sol)

Each market and hook combination runs twice, with TTLs of zero and one hour.

| Release | Market | Hooks |
| --- | --- | --- |
| v2.0.0 and v2.1.0 | Standard | Open, fixed |
| v2.5 (`27b3f79e`) | Standard and revolving | Open, fixed, periodic |

Run the provider tests from the feature branch. To repeat them on `v2.0.0`, copy `src/providers/`, `src/access/IManagedRoleProvider.sol`, and `test/providers/` to the same paths in a checkout of that tag.

```sh
forge test --match-path 'test/providers/*.t.sol'
```

To run the forward-compatibility tests, set `V25_CHECKOUT` to the absolute path of a disposable checkout of `27b3f79e` with its submodules initialized. Run the following from the feature branch after the legacy tests. Both v2.5 suites deploy the legacy build and check its runtime bytecode.

```sh
cp src/providers/KYCRoleProvider.sol "$V25_CHECKOUT/src/providers/"
cp test/providers/KYCMarketLifecycle.sol test/providers/KYCRoleProviderHooks.t.sol \
  compat/v2.5/test/providers/KYCRoleProviderMarketsV25.t.sol "$V25_CHECKOUT/test/providers/"
cp out/KYCRoleProvider.sol/KYCRoleProvider.json "$V25_CHECKOUT/deployments/KYCRoleProvider.legacy.json"

cd "$V25_CHECKOUT"
forge build src test/mocks
KYC_V25_TEST_PROVIDER_ARTIFACT=deployments/KYCRoleProvider.legacy.json \
  forge test --match-contract '^KYCRoleProvider(Hooks|MarketsV25)Test$'
```
