# Borrower Identity and Transfers

v2.5 separates the address that operates a market from the legal borrower identity registered through the ArchController. This lets a market move from an EOA to a Safe, from one Safe to another, or to a future Borrower Account without replacing the market or resetting its state.

## Identity model

Each market exposes two identities:

- `borrower()` is the current operational borrower. It is the exact address authorized for borrower-only market calls.
- `borrowerPrincipal()` is the registered legal principal associated with the market. It is also the borrower namespace used for lender-facing sanctions checks and new sanctions escrows.

For a market operated directly by its principal, both addresses are the same. A market operated by a recognized contract account may instead have:

```text
borrower()          = account A
borrowerPrincipal() = principal P
```

The market stores both accepted addresses. Ordinary borrower actions do not depend on a live identity-registry lookup.

## Borrower identity registry

`WildcatBorrowerIdentityRegistry` recognizes contract accounts belonging to registered principals.

- The current ArchController owner may approve or remove account factories.
- An approved factory may associate a deployed contract account with an initial registered principal.
- An account must be a deployed contract, must differ from its principal, and must not be registered directly as a borrower in the ArchController.
- A factory may register an account address only once. The factory that registered it remains recorded.
- One principal may have several registered accounts.
- An account has one current principal at a time. Its current principal may request a two-step transfer to another registered principal.
- Removing a factory prevents new registrations from that factory. It does not invalidate associations the factory already registered.
- The registry can classify identities, but it cannot call markets, move assets, or execute a borrower transfer.

`resolveBorrower(address)` accepts either a currently registered direct principal or a registered account whose principal is currently registered. Unknown, unregistered, or ambiguous identities fail closed.

The Foundation remains responsible for registering legal principals in the ArchController. It does not register each borrower account or execute transfers. Approved account factories register the accounts they deploy or otherwise authenticate.

### Account principal transfer

An account principal transfer changes which registered principal the registry associates with an existing account. It does not change the account address or automatically update any market.

```solidity
function requestBorrowerAccountPrincipalTransfer(address account, address newPrincipal) external;
function cancelBorrowerAccountPrincipalTransfer(address account) external;
function acceptBorrowerAccountPrincipalTransfer(address account) external;

function principalOf(address account) external view returns (address);
function pendingPrincipalOf(address account) external view returns (address);
```

The current principal requests the transfer, may replace the pending principal, and may cancel it. The pending principal must accept. The registry checks the proposed principal's current ArchController registration on both request and acceptance. The account factory cannot initiate, approve, or accept the transfer.

After acceptance:

- `principalOf(account)` returns the new principal;
- current-principal enumeration moves the account from the old principal to the new one;
- factory provenance remains unchanged; and
- existing markets keep the borrower and principal they previously accepted.

A registry transfer cannot silently change a market's sanctions namespace or lender-facing identity.

The registry does not rewrite an account's internal permissions. A future Borrower Account that expects its administrative authority to follow `principalOf(account)` must use the registry as its source of truth, or update its own authority as part of the same borrower-controlled operation. That requirement belongs to the account implementation and its approved factory, not to a protocol administrator.

## Market construction

The ordinary v2.5 standard and revolving factories initialize direct markets with `borrower == borrowerPrincipal`.

The shared market constructor can also represent a different initial operational borrower and principal. This is the compatibility seam for future factories that may initialize a market under a temporary construction contract while retaining the requesting principal as its legal identity. The ordinary v2.5 factories do not implement deferred origination or Borrower Account policy.

## Two-step transfer

Every v2.5 market exposes:

```solidity
function requestBorrowerTransfer(address newBorrower) external;
function cancelBorrowerTransfer() external;
function acceptBorrowerTransfer() external;

function borrower() external view returns (address);
function borrowerPrincipal() external view returns (address);
function pendingBorrower() external view returns (address);
function pendingBorrowerPrincipal() external view returns (address);
```

### Request

Only the current borrower may request a transfer. A new request replaces any existing pending target and emits both the displaced target and the new target.

The market resolves the proposed borrower through the identity registry and checks current ArchController registration. It also checks the raw sanctions status of the current borrower, current principal, proposed borrower, and proposed principal. Borrower sanctions overrides do not bypass these transfer checks.

Pending status grants no market authority before acceptance. In a same-account principal update, the address remains the current borrower and keeps only the authority it already had.

### Cancellation

Only the current borrower may cancel a pending request. Cancellation remains available without transferring authority.

### Acceptance

Only the pending borrower may accept. Acceptance repeats identity, registration, and raw sanctions checks against current state, then clears the pending identity and writes the new operational borrower and resolved principal.

The market records the proposed principal when the transfer is requested. If the target account changes principals before acceptance, acceptance reverts. The current borrower may cancel and request the transfer again with the account's new principal.

The same path supports:

- direct principal migration, `P -> Q`;
- direct principal to account, `P -> A(P)`;
- same-principal account rotation, `A1(P) -> A2(P)`;
- account to direct principal, `A(P) -> Q`; and
- account-to-account principal migration, `A(P) -> A(Q)`.

The last case may represent either a different account under `Q` or the same account after its registry principal transfer. When the address is unchanged, the account requests and accepts a market transfer to itself. The market updates only `borrowerPrincipal()` from `P` to `Q`.

The protocol does not prove that two principals represent the same legal entity. Registration remains the Foundation's onchain representation of its offchain KYB process.

## What transfer changes

Acceptance changes only borrower identity and pending-transfer state. It does not move or reset lender balances, withdrawal claims or batches, accrued fees, market terms, drawn amount, delinquency state, or closure state. Active, delinquent, and closed markets can all transfer.

After acceptance:

- if the borrower address changed, the previous borrower fails every borrower-only market check;
- the accepted borrower controls borrower-only market actions; and
- the market uses the new principal for new lender-facing sanctions checks and escrow derivation.

Existing sanctions escrows remain under the principal namespace used when they were created.

## Wrapper authority

The canonical ERC-4626 wrapper follows its market directly:

- `marketOwner()` resolves the live `market.borrower()`;
- `sweep()` authorizes the live market borrower; and
- sanctions checks and new escrow derivation resolve the live `market.borrowerPrincipal()`.

The wrapper has no separate transfer step. If the borrower address changes, the previous borrower loses wrapper sweep authority as soon as the market transfer is accepted.

## Hooks and role providers

A market transfer does not transfer its hooks or role providers. Hooks may be shared by several markets, and reusable credentials belong to role providers rather than to one market. Hook administration and managed-provider administration therefore need their own explicit transfer paths.

This separation is intentional. A market must not seize a shared hook or credential list merely because its borrower changed.

Hook administration belongs to the principal and uses a separate two-step transfer. Acceptance updates the creating factory's administrator index, but it does not rewrite provider configuration, lender status, hook-local blocks, known-lender state, or hooked-market configuration.

The v2.5 `AccessListRoleProvider` also has an independent two-step administrator transfer. Moving its administration preserves the provider address, membership, and every hook attachment. Other role providers are not assumed to implement that interface.

## Batching and atomicity

Each market acceptance is atomic for that market. There is no protocol transfer manager and no Wildcat-controlled coordinator.

A Safe or future Borrower Account may batch several independent acceptance calls in one transaction. An EOA may need to accept them sequentially. Integrators must expose partial progress when a migration cannot fit in one borrower-controlled batch; they must not describe several unrelated transactions as atomic.

## Events and lens reads

Markets emit:

- `BorrowerTransferRequested`, including the current borrower and principal plus the previous and new pending borrowers and principals;
- `BorrowerTransferCancelled`, including the cancelled borrower and principal; and
- `BorrowerTransferred`, including previous and new borrowers and principals.

`MarketDataV2_5` exposes the current borrower through its nested market data and adds `borrowerPrincipal`, `pendingBorrower`, `pendingBorrowerPrincipal`, and `borrowerIdentityRegistry` for v2.5 consumers.

Downstream systems must not assume that `market.borrower()` is itself registered in the ArchController. They should display and index the operational borrower and legal principal separately.

## Principal rotation across accounts and markets

A borrower rotating from principal `P` to principal `Q` may keep its existing accounts and their internal configuration. The expected sequence is:

1. The Foundation registers `Q` in the ArchController.
2. `P` requests `A: P -> Q` for each account that should follow the borrower.
3. `Q` accepts each account principal transfer.
4. Each account requests and accepts a same-account transfer on every market it operates.
5. Hook and managed-role-provider administration move through their own transfer paths where needed.
6. The borrower confirms that the migration is complete before the Foundation removes `P`.

Each acceptance is atomic for one account or market. The registry does not coordinate a global migration. A borrower-controlled Safe or Borrower Account may batch several calls, but integrations must expose partial progress when the migration spans several transactions.

During partial migration, the registry may associate an account with `Q` while one of its markets still stores `P`. Ordinary borrower-only calls continue to recognize the account, but lender-facing sanctions checks continue to use the principal stored by that market until its explicit transfer is accepted.
