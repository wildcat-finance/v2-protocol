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
- An approved factory may permanently associate a deployed contract account with a currently registered principal.
- An account cannot be zero, the principal itself, a directly registered borrower, or an account that was already registered.
- One principal may have several registered accounts.
- An account-to-principal association cannot be changed or removed.
- Removing a factory prevents new registrations from that factory. It does not invalidate associations the factory already registered.
- The registry can classify identities, but it cannot call markets, move assets, or execute a borrower transfer.

`resolveBorrower(address)` accepts either a currently registered direct principal or a registered account whose principal is currently registered. Unknown, unregistered, or ambiguous identities fail closed.

The Foundation remains responsible for registering legal principals in the ArchController. It does not register each borrower account or execute transfers. Approved account factories register the accounts they deploy or otherwise authenticate.

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
```

### Request

Only the current borrower may request a transfer. A new request replaces any existing pending target and emits both the displaced target and the new target.

The market resolves the proposed borrower through the identity registry and checks current ArchController registration. It also checks the raw sanctions status of the current borrower, current principal, proposed borrower, and proposed principal. Borrower sanctions overrides do not bypass these transfer checks.

The pending borrower has no market authority before acceptance.

### Cancellation

Only the current borrower may cancel a pending request. Cancellation remains available without transferring authority.

### Acceptance

Only the pending borrower may accept. Acceptance repeats identity, registration, and raw sanctions checks against current state, then clears the pending borrower and writes the new operational borrower and resolved principal.

The same path supports:

- direct principal migration, `P -> Q`;
- direct principal to account, `P -> A(P)`;
- same-principal account rotation, `A1(P) -> A2(P)`;
- account to direct principal, `A(P) -> Q`; and
- account-to-account principal migration, `A(P) -> A(Q)`.

The protocol does not prove that two principals represent the same legal entity. Registration remains the Foundation's onchain representation of its offchain KYB process.

## What transfer changes

Acceptance changes only borrower identity and pending-transfer state. It does not move or reset lender balances, withdrawal claims or batches, accrued fees, market terms, drawn amount, delinquency state, or closure state. Active, delinquent, and closed markets can all transfer.

After acceptance:

- the old borrower fails every borrower-only market check;
- the new borrower controls borrower-only market actions; and
- the market uses the new principal for new lender-facing sanctions checks and escrow derivation.

Existing sanctions escrows remain under the principal namespace used when they were created.

## Wrapper authority

The canonical ERC-4626 wrapper follows its market directly:

- `marketOwner()` resolves the live `market.borrower()`;
- `sweep()` authorizes the live market borrower; and
- sanctions checks and new escrow derivation resolve the live `market.borrowerPrincipal()`.

The wrapper has no separate transfer step. The old borrower loses wrapper sweep authority as soon as the market transfer is accepted.

## Hooks and role providers

A market transfer does not transfer its hooks or role providers. Hooks may be shared by several markets, and reusable credentials belong to role providers rather than to one market. Hook administration and managed-provider administration therefore need their own explicit transfer paths.

This separation is intentional. A market must not seize a shared hook or credential list merely because its borrower changed.

## Batching and atomicity

Each market acceptance is atomic for that market. There is no protocol transfer manager and no Wildcat-controlled coordinator.

A Safe or future Borrower Account may batch several independent acceptance calls in one transaction. An EOA may need to accept them sequentially. Integrators must expose partial progress when a migration cannot fit in one borrower-controlled batch; they must not describe several unrelated transactions as atomic.

## Events and lens reads

Markets emit:

- `BorrowerTransferRequested`, including the current borrower and principal plus the previous and new pending targets;
- `BorrowerTransferCancelled`, including the cancelled target; and
- `BorrowerTransferred`, including previous and new borrowers and principals.

`MarketDataV2_5` exposes the current borrower through its nested market data and adds `borrowerPrincipal`, `pendingBorrower`, and `borrowerIdentityRegistry` for v2.5 consumers.

Downstream systems must not assume that `market.borrower()` is itself registered in the ArchController. They should display and index the operational borrower and legal principal separately.
