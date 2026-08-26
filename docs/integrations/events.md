# Events

V2.5 changes several factory, market, access-control, and authority event ABIs.
Historical V2 and V2.1 deployments retain their original ABI families. Select
the ABI from the emitting address and its deployment generation, not from a
package version, template name, or guessed contract shape.

This is a curated integration reference, not a complete event catalogue. It
covers events whose signatures, emitters, or ordering matter when reconstructing
V2.5 state. A complete release catalogue should be generated separately from
the final release ABIs and pinned to the release source commit.

## Log identity and ordering

Retain the emitting address and apply logs in `(block number, transaction index,
log index)` order. The same signature from an unknown emitter is not evidence
that the emitter belongs to a known factory, market, hook, provider, wrapper,
registry, or ArchController generation.

A reverted transaction produces no durable logs. During market creation, hook
initialization events may be emitted before the market exists. The market is
then deployed and registered, causing `WildcatArchController.MarketAdded`.
Only after registration and factory association writes does the factory emit
its market deployment bundle.

`MarketAdded` proves registration. It does not contain enough data to initialize
a market entity. Upsert the address, then complete initialization from the later
factory events in the same transaction.

## Hook instance creation

The factory emits these events after deploying and indexing a hook instance:

```solidity
event HooksInstanceDeployed(
  address indexed hooksInstance,
  address indexed hooksTemplate,
  address indexed administrator,
  address deployer,
  string name,
  string version
);
event HooksInstanceRoleProviders(
  address indexed hooksInstance,
  bool metadataAvailable,
  RoleProvider[] pullProviders,
  RoleProvider[] pushProviders
);
```

`administrator` is the registered principal resolved by the factory. `deployer`
is the immediate factory caller. The template address, not its display name or
version string, identifies the implementation.

Constructor-time `RoleProviderAdded` events may precede factory discovery of
the hook. `HooksInstanceRoleProviders` therefore supplies the initial provider
snapshot. If `metadataAvailable` is false, empty arrays mean unknown metadata,
not an empty provider set.

Optional metadata reads are bounded and fail open with respect to deployment.
Names and versions are retained only when the returned string fits within
4,096 bytes. Each provider array is limited to 256 entries and read with a
one-million-gas static call. Failure to read optional metadata does not revert
an otherwise valid deployment.

See [`IHooksFactory.sol`](../../src/IHooksFactory.sol) for the event ABI and
bounded metadata readers.

## Market creation

Standard market creation ends with this factory event bundle:

```solidity
event MarketDeployed(
  address indexed hooksTemplate,
  address indexed hooksInstance,
  address indexed market,
  address borrower,
  address borrowerPrincipal,
  address borrowerIdentityRegistry,
  string name,
  string symbol,
  address asset,
  HooksConfig requestedHooks,
  HooksConfig hooks
);
event MarketDeploymentConfig(
  address indexed market,
  uint256 maxTotalSupply,
  uint256 annualInterestBips,
  uint256 delinquencyFeeBips,
  uint256 withdrawalBatchDuration,
  uint256 reserveRatioBips,
  uint256 delinquencyGracePeriod,
  address feeRecipient,
  uint256 protocolFeeBips,
  address originationFeeAsset,
  uint256 originationFeeAmount
);
event MarketHooksData(address indexed market, bytes hooksData);
```

Revolving factories then emit:

```solidity
event RevolvingMarketDeployed(address indexed market, uint256 commitmentFeeBips);
```

`MarketDeployed` owns deployment identity and the installed hook configuration.
`MarketDeploymentConfig` owns initial economic configuration.
`MarketHooksData` owns the opaque payload accepted by `onCreateMarket`.
`RevolvingMarketDeployed` selects the revolving market family and records its
initial commitment fee.

Decode `hooksData` only against the exact approved hook template revision. The
current built-in template layouts are:

| Template | Deployment payload |
| --- | --- |
| `OpenTermHooks` | `(uint128 minimumDeposit, bool transfersDisabled)`; both words are optional |
| `FixedTermHooks` | `(uint32 fixedTermEndTime, uint128 minimumDeposit, bool transfersDisabled, bool allowClosureBeforeTerm, bool allowTermReduction)`; only the first word is required |
| `PeriodicTermHooks` | `(uint32 firstWithdrawalWindowStart, uint32 periodDuration, uint32 withdrawalWindowDuration, uint96 minimumDeposit, bool transfersDisabled)`; the first three words are required |

These hooks use word-based manual readers. Missing optional words read as zero,
and booleans use the low bit of their word. This is not a promise that
`abi.decode` accepts every payload the hook accepts.

`requestedHooks` records the borrower-selected hook address and flags passed to
`onCreateMarket`. `hooks` records the final address and callbacks returned by
the hook and installed on the market. Preserve both. Preserve the factory's
`borrowerIdentityRegistry`; do not infer it from the current borrower or
principal.

See [`HooksFactory.sol`](../../src/HooksFactory.sol) and
[`HooksFactoryRevolving.sol`](../../src/HooksFactoryRevolving.sol) for the
ordering and payload emitters.

## Authority and access history

Template admission and fee history use `HooksTemplateAdded`,
`HooksTemplateDisabled`, and `HooksTemplateFeesUpdated`. Hook administration
uses the hook's request, cancellation, and completion events; the factory then
emits `HooksInstanceAdministratorTransferred` after updating its enumeration.

Built-in hook state is reconstructed from `MinimumDepositUpdated`,
`FixedTermUpdated`, `PeriodicTermUpdated`, `PeriodicTermClosed`, the three
`AnnualInterestBipsReduction*` events, and the four
`TemporaryExcessReserveRatio*` events. These events belong to the current
OpenTerm, FixedTerm, and PeriodicTerm template families.

Market borrower transfer uses these integration-critical events:

```solidity
event BorrowerTransferRequested(
  address indexed borrower,
  address indexed previousPendingBorrower,
  address indexed pendingBorrower,
  address borrowerPrincipal,
  address previousPendingBorrowerPrincipal,
  address pendingBorrowerPrincipal
);
event BorrowerTransferCancelled(
  address indexed borrower,
  address indexed cancelledPendingBorrower,
  address borrowerPrincipal,
  address cancelledPendingBorrowerPrincipal
);
event BorrowerTransferred(
  address indexed previousBorrower,
  address indexed newBorrower,
  address previousBorrowerPrincipal,
  address indexed newBorrowerPrincipal
);
```

A pending borrower has no market authority. Consumers must retain operational
borrower and legal principal as separate fields. See
[`borrower-identity.md`](../protocol/borrower-identity.md) for the state machine.
Borrower-account factory and principal-transfer events exist in source for
forward compatibility, but no account factory is part of the current V2.5
release surface.

Hook access state is reconstructed from three related families:

- `RoleProviderAdded`, `RoleProviderUpdated`, and `RoleProviderRemoved` own
  attachment, TTL, and pull/push indexes.
- `AccountAccessGranted` and `AccountAccessRevoked` own stored credentials.
- `AccountBlockedFromDeposits`, `AccountUnblockedFromDeposits`, and
  `AccountMadeFirstDeposit` own hook-local lender state.

Provider removal does not emit synthetic revocations or delete every stored
credential. Effective access depends on current attachment, TTL, credential
timestamp, and hook-local blocking state.

For V2.5, only `AccessListRoleProviderFactory` is part of the supported
provider-factory surface:

```solidity
event AccessListRoleProviderDeployed(
  address indexed provider,
  address indexed administrator,
  address indexed deployer,
  bytes32 salt,
  address[] initialMembers
);
event MemberAdded(address indexed administrator, address indexed account);
event MemberRemoved(address indexed administrator, address indexed account);
```

The deployment event is the initial membership snapshot. Later membership
events supersede it in log order. Classify the provider only when both the
event and its known factory emitter match. An attached provider without trusted
factory provenance remains valid protocol input but has unknown type.

Other provider factories present in source are not scheduled or supported in
the current V2.5 release surface and are intentionally omitted here. Their
source status belongs in [`role-providers.md`](./role-providers.md),
not in the current integration event set.

## Market accounting and configuration

The relevant market state families are:

- `Deposit`, `Borrow`, and `DebtRepaid` record asset and debt movement.
- `MaxTotalSupplyUpdated`, `ProtocolFeeBipsUpdated`, and
  `AnnualInterestAndReserveRatioBipsUpdated` record mutable configuration with
  previous and new values.
- `InterestAndFeesAccrued` and `StateUpdated` record accrual and its persisted
  scale factor and delinquency state.
- `FeesCollected` and `MarketClosed` record fee withdrawal and closure.
- `DrawnAmountUpdated` records revolving drawn-principal changes.

APR and reserve ratio are one transition because a hook may transform both.
Closing sets APR to zero and reserve ratio to 10,000, then emits
`MarketClosed`. `InterestAndFeesAccrued` records time-based accrual;
`StateUpdated` records the persisted scale factor and delinquency flag;
`FeesCollected` records asset transfer from the market.

`Borrow` records proceeds. Revolving markets separately emit
`DrawnAmountUpdated` when drawn principal changes. These are deliberately
independent: a borrow after over-repayment may transfer assets without
increasing drawn principal, and an interest-only repayment may emit
`DebtRepaid` without reducing drawn principal.

See [`IMarketEventsAndErrors.sol`](../../src/interfaces/IMarketEventsAndErrors.sol)
and [`IWildcatMarketRevolving.sol`](../../src/interfaces/IWildcatMarketRevolving.sol).

## Wrappers, withdrawals, and sanctions

Canonical V2.5 wrapper creation emits `WrapperRegistered` from the market,
followed by `WrapperDeployed` from the wrapper factory. Standard ERC-20 and
ERC-4626 `Transfer`, `Approval`, `Deposit`, and `Withdraw` events remain part
of the wrapper ABI. See [`erc-4626-wrapper.md`](./erc-4626-wrapper.md).

The market withdrawal family includes `WithdrawalBatchCreated`,
`WithdrawalQueued`, `WithdrawalBatchPayment`, `WithdrawalBatchExpired`,
`WithdrawalBatchClosed`, and `WithdrawalExecuted`. `queueWithdrawalScaled`
uses this existing family; it adds no event or indexer state.

Withdrawal and wrapper quarantine may also emit
`SanctionedAccountAssetsQueuedForWithdrawal`,
`SanctionedAccountWithdrawalSentToEscrow`,
`SanctionedAccountSharesSentToEscrow`, `NewSanctionsEscrow`, and
`EscrowReleased`. Retain the emitter: market-token escrow, underlying-asset
escrow, and wrapper-share escrow are different assets and state transitions.

## Indexer rules

1. Resolve the ABI family from known deployment provenance and retain the
   emitter on every record.
2. Initialize hooks and markets from their factory bundles, then apply later
   component events in log order.
3. Decode hook deployment data only for an exact known template revision;
   preserve unknown payloads unchanged.
4. Classify providers only from trusted factory provenance; keep arbitrary
   attached providers visible as unknown.
5. Keep operational borrower separate from legal principal, and revolving
   borrow proceeds separate from drawn principal.
