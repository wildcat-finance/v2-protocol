# Borrower identity and transfers

V2.5 stores the address that operates a market separately from the registered
legal borrower. That lets the borrower transfer control without replacing the
market or resetting its state.

## V2.5 boundary

Supported V2.5 factories create markets for direct registered principals.
Supported transfers also resolve to direct registered principals. The following
invariant therefore holds for every supported V2.5 market:

```text
borrower() == borrowerPrincipal()
```

The source and ABI already contain an account-aware path where the two values
may differ. No supported V2.5 factory deploys Borrower Accounts. That path is
planned for V2.6, but it is documented here because the compatibility seam is
already in the code.

## Identity model

Each market exposes:

- `borrower()`: the operational borrower. This exact address can call
  borrower-only market functions.
- `borrowerPrincipal()`: the registered legal principal. This is also the
  lender-facing namespace for sanctions checks and new sanctions escrows.

The account-aware path can represent:

```text
borrower()          = account A
borrowerPrincipal() = principal P
```

The market stores both accepted addresses. Ordinary borrower actions do not
require a live registry lookup.

Borrower, principal, pending transfer, and wrapper pointers occupy the final
five EVM storage slots, from `type(uint256).max` through
`type(uint256).max - 4`. The established sequential market layout remains in
slots 0 through 10, and derived markets can keep extending it normally. New
manual storage must not use the reserved five-slot range.

## Borrower identity registry

`WildcatBorrowerIdentityRegistry` resolves direct ArchController-registered
principals and recognizes contract accounts associated with those principals.

Registry rules:

- The current ArchController owner can approve or remove account factories.
- An approved factory can associate a deployed contract account with an initial
  registered principal.
- The account must be deployed code, differ from its principal, and not be
  directly registered as a borrower in the ArchController.
- An account address can only be registered once. Its original factory remains
  recorded.
- A principal can have several accounts. An account has one current principal.
- The current principal can request a two-step transfer to another registered
  principal.
- Removing a factory blocks new registrations from that factory. Existing
  associations remain valid.
- The registry classifies identities. It cannot call markets, move assets, or
  execute borrower transfers.

`resolveBorrower(address)` accepts either:

- a currently registered direct principal; or
- a registered account whose current principal is registered.

Unknown, unregistered, and ambiguous identities fail closed.

Wildcat Foundation registers legal principals in the ArchController as part of
its KYC/KYB process. It does not register individual borrower accounts or
execute transfers. Approved account factories register the accounts they
deploy or otherwise authenticate.

### Account principal transfers

An account principal transfer changes the principal associated with an existing
account. It does not change the account address or update any market.

```solidity
function requestBorrowerAccountPrincipalTransfer(
  address account,
  address newPrincipal
) external;

function cancelBorrowerAccountPrincipalTransfer(address account) external;

function acceptBorrowerAccountPrincipalTransfer(address account) external;

function principalOf(address account) external view returns (address);

function pendingPrincipalOf(address account) external view returns (address);
```

The current principal can request, replace, or cancel a pending transfer. Only
the pending principal can accept it. The registry checks the proposed
principal's current ArchController registration at request and acceptance.
The account factory cannot initiate, approve, or accept the transfer.

After acceptance:

- `principalOf(account)` returns the new principal;
- principal enumeration moves the account from the old principal to the new
  one;
- factory provenance remains unchanged; and
- existing markets keep the borrower and principal they previously accepted.

A registry transfer cannot silently change a market's sanctions namespace or
lender-facing identity.

The registry also does not rewrite the account's internal permissions. A future
Borrower Account that expects authority to follow `principalOf(account)` must
read the registry or update its own authority during the same borrower-controlled
operation. That is the responsibility of the account implementation and its
approved factory, not a protocol administrator.

## Market construction

The supported standard and revolving factories initialize markets with
`borrower == borrowerPrincipal`.

The shared market constructor can accept a different operational borrower and
principal. A future factory could use that seam to construct a market through a
temporary contract while retaining the requesting principal's legal identity.
The V2.5 factories do not support deferred origination or Borrower Account
policy.

## Two-step market transfer

Every V2.5 market exposes:

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

Only the current borrower can request a transfer. A new request replaces the
pending target and emits both the displaced and replacement identities.

The market resolves the proposed borrower through the identity registry. It
checks current ArchController registration and the raw sanctions status of:

- the current borrower;
- the current principal;
- the proposed borrower; and
- the proposed principal.

Borrower sanctions overrides do not bypass these checks. A pending identity has
no market authority before acceptance. If an account requests a transfer to
itself after changing principal, it keeps only the authority it already had.

### Cancellation

Only the current borrower can cancel a pending request. Cancellation does not
transfer authority.

### Acceptance

Only the pending borrower can accept. Acceptance repeats identity,
registration, and raw sanctions checks against current state. It then clears
the pending identity and stores the new borrower and principal.

The requested principal is pinned when the request is made. If the target
account changes principal before acceptance, acceptance reverts. The current
borrower can cancel and submit a new request for the updated principal.

The same path supports:

- direct principal migration, `P -> Q`;
- direct principal to account, `P -> A(P)`;
- same-principal account rotation, `A1(P) -> A2(P)`;
- account to direct principal, `A(P) -> Q`; and
- account-to-account principal migration, `A(P) -> A(Q)`.

The last case can use a different account under `Q`, or the same account after a
registry principal transfer. If the address is unchanged, the account requests
and accepts a transfer to itself. Only `borrowerPrincipal()` changes from `P`
to `Q`.

The protocol does not prove that two principals represent the same legal
entity. ArchController registration is the Foundation's onchain representation
of its offchain KYB process.

## What acceptance changes

Acceptance changes borrower identity and pending-transfer state. It does not
change:

- lender balances;
- withdrawal claims or batches;
- accrued fees or market terms;
- revolving drawn amount;
- delinquency state; or
- closure state.

Active, delinquent, and closed markets can all transfer.

After acceptance:

- the previous borrower loses every borrower-only permission if its address
  changed;
- the accepted borrower controls borrower-only market actions; and
- new lender-facing sanctions checks and escrows use the new principal.

Existing sanctions escrows keep the principal namespace used when they were
created.

## Wrapper authority

The canonical ERC-4626 wrapper follows the market directly:

- `marketOwner()` returns the live `market.borrower()`;
- `sweep()` authorizes that live borrower; and
- sanctions checks and new escrow derivation use the live
  `market.borrowerPrincipal()`.

The wrapper has no separate transfer step. Once a market transfer is accepted,
the previous borrower loses wrapper sweep authority.

## Hooks and role providers

A market transfer does not transfer hooks or role providers. Hooks may be
shared across markets, and reusable credentials belong to role providers.
Their authority must move through separate transfer paths.

Hook administration belongs to the principal and uses its own two-step
transfer. Acceptance updates the creating factory's administrator index. It
does not rewrite provider configuration, lender status, hook-local blocks,
known-lender state, or hooked-market configuration.

V2.5 `AccessListRoleProvider` administration also uses an independent two-step
transfer. The provider address, membership, and every hook attachment remain
unchanged. Other role providers are not assumed to support that interface.

This separation matters. Changing one market's borrower must not seize a shared
hook or credential list.

## Batching and partial progress

Each acceptance is atomic for one account or market. There is no protocol
transfer manager or Wildcat-controlled coordinator.

A Safe or future Borrower Account can batch several independent acceptances in
one transaction. An EOA may need to submit them one at a time. Integrations must
show partial progress when the whole migration does not fit in one
borrower-controlled batch. Several unrelated transactions are not atomic just
because the UI presents them together.

## Events and lens reads

Markets emit:

- `BorrowerTransferRequested`, with the current borrower and principal plus the
  previous and new pending identities;
- `BorrowerTransferCancelled`, with the cancelled borrower and principal; and
- `BorrowerTransferred`, with the previous and new borrower and principal.

`MarketDataV2_5` exposes the current borrower in its nested market data. It also
adds `borrowerPrincipal`, `pendingBorrower`, `pendingBorrowerPrincipal`, and
`borrowerIdentityRegistry`.

Downstream systems must not assume `market.borrower()` is directly registered
in the ArchController. Index and display the operational borrower and legal
principal separately.

## Rotating a principal across accounts and markets

A borrower moving from principal `P` to principal `Q` can keep its accounts and
their internal configuration:

1. Wildcat Foundation registers `Q` in the ArchController.
2. `P` requests `A: P -> Q` for each account that should move.
3. `Q` accepts each account principal transfer.
4. Each account requests and accepts a same-account transfer on every market it
   operates.
5. Hook and managed-role-provider administration move separately where needed.
6. The borrower confirms the migration is complete before Wildcat Foundation
   removes `P`.

The registry does not coordinate a global migration. During partial progress,
it may associate an account with `Q` while one of its markets still stores `P`.
Borrower-only calls still recognize the account. Lender-facing sanctions checks
continue using the principal stored by that market until its transfer is
accepted.
