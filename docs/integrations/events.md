# Events

V2.5 changes several factory, market, access-control, and authority event ABIs.
Historical V2 and V2.1 deployments keep their original ABI families.

Choose an ABI from the emitting address and its deployment generation. Do not
infer it from a package version, template name, or apparent contract shape.

This is a curated integration reference. It covers events whose signature,
emitter, or order matters when reconstructing V2.5 state. It is not a complete
catalogue. Generate the full catalogue from the final release ABIs and pin it to
the release source commit.

## Log identity and ordering

Always retain the emitting address. Apply logs in this order:

1. Block number.
2. Transaction index.
3. Log index.

A matching signature from an unknown emitter proves nothing about its contract
family or deployment generation.

A reverted transaction leaves no durable logs. Successful market creation runs
in this order:

1. The hook may emit initialization events before the market exists.
2. The factory deploys the market.
3. The ArchController registers it and emits
   `WildcatArchController.MarketAdded`.
4. The factory writes its associations and emits the market deployment bundle.

`MarketAdded` proves registration. It does not contain enough data to initialize
a market entity. Upsert the address, then finish initialization from the later
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

The fields have distinct meanings:

- `administrator` is the registered principal resolved by the factory.
- `deployer` is the immediate factory caller.
- `hooksTemplate` identifies the implementation. Its display name and version
  string do not.

Constructor-time `RoleProviderAdded` events may come before factory discovery.
`HooksInstanceRoleProviders` supplies the initial provider snapshot.

If `metadataAvailable` is false, empty arrays mean the metadata is unknown.
They do not prove the provider set is empty.

Optional metadata reads are bounded and cannot block an otherwise valid
deployment:

- Names and versions must fit within 4,096 bytes.
- Each provider array is limited to 256 entries.
- Provider arrays are read with a one-million-gas static call.
- Failed optional reads leave the metadata unavailable.

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

The events split the initial state:

- `MarketDeployed` records deployment identity and the installed hook
  configuration.
- `MarketDeploymentConfig` records the initial economic configuration.
- `MarketHooksData` records the opaque payload accepted by `onCreateMarket`.
- `RevolvingMarketDeployed` identifies the revolving market family and records
  its initial commitment fee.

Decode `hooksData` only against the exact approved hook template revision.

**`OpenTermHooks`**

```solidity
(uint128 minimumDeposit, bool transfersDisabled)
```

Both words are optional.

**`FixedTermHooks`**

```solidity
(
  uint32 fixedTermEndTime,
  uint128 minimumDeposit,
  bool transfersDisabled,
  bool allowClosureBeforeTerm,
  bool allowTermReduction
)
```

Only the first word is required.

**`PeriodicTermHooks`**

```solidity
(
  uint32 firstWithdrawalWindowStart,
  uint32 periodDuration,
  uint32 withdrawalWindowDuration,
  uint96 minimumDeposit,
  bool transfersDisabled
)
```

The first three words are required.

These hooks use word-based manual readers:

- Missing optional words read as zero.
- Booleans use the low bit of their word.
- `abi.decode` may reject payloads the hook accepts.

Preserve both hook configurations. `requestedHooks` is the borrower-selected
address and flags passed to `onCreateMarket`. `hooks` is the final address and
callback set installed on the market.

Also preserve the factory's `borrowerIdentityRegistry`. Do not infer it from
the current borrower or principal.

See [`HooksFactory.sol`](../../src/HooksFactory.sol) and
[`HooksFactoryRevolving.sol`](../../src/HooksFactoryRevolving.sol) for the
ordering and payload emitters.

## Authority and access history

Use these event families for authority and hook state:

- Template admission and fees: `HooksTemplateAdded`, `HooksTemplateDisabled`,
  and `HooksTemplateFeesUpdated`.
- Hook administration: the hook's request, cancellation, and completion events,
  followed by `HooksInstanceAdministratorTransferred` from the factory.
- Built-in hook state: `MinimumDepositUpdated`, `FixedTermUpdated`,
  `PeriodicTermUpdated`, and `PeriodicTermClosed`.
- APR and reserve overrides: the three `AnnualInterestBipsReduction*` events and
  four `TemporaryExcessReserveRatio*` events.

These state events belong to the current OpenTerm, FixedTerm, and PeriodicTerm
template families.

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

A pending borrower has no market authority. Keep the operational borrower and
legal principal in separate fields. See
[`borrower-identity.md`](../protocol/borrower-identity.md) for the state machine.
Borrower-account factory and principal-transfer events exist in source for
forward compatibility. No account factory is part of the current V2.5 release
surface.

Hook access state is reconstructed from three related families:

- `RoleProviderAdded`, `RoleProviderUpdated`, and `RoleProviderRemoved` own
  attachment, TTL, and pull/push indexes.
- `AccountAccessGranted` and `AccountAccessRevoked` own stored credentials.
- `AccountBlockedFromDeposits`, `AccountUnblockedFromDeposits`, and
  `AccountMadeFirstDeposit` own hook-local lender state.

Removing a provider does not emit synthetic revocations or delete every stored
credential. Effective access still depends on:

- Current provider attachment.
- TTL.
- Credential timestamp.
- Hook-local blocking state.

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
events supersede it in log order.

Classify a provider only when the event and its known factory emitter both
match. A provider without trusted factory provenance is still valid protocol
input. Its type is unknown.

Other provider factories exist in source, but are not scheduled or supported in
the current V2.5 release surface. They are intentionally omitted here. Their
source status belongs in [`role-providers.md`](./role-providers.md).

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

APR and reserve ratio form one transition because a hook may transform both.
Closing sets APR to zero and the reserve ratio to 10,000, then emits
`MarketClosed`.

These events have separate jobs:

- `InterestAndFeesAccrued` records time-based accrual.
- `StateUpdated` records the persisted scale factor and delinquency flag.
- `FeesCollected` records asset transfer from the market.

`Borrow` records proceeds. Revolving markets separately emit
`DrawnAmountUpdated` when drawn principal changes. The two are deliberately
independent:

- A borrow after over-repayment may transfer assets without increasing drawn
  principal.
- An interest-only repayment may emit `DebtRepaid` without reducing drawn
  principal.

See [`IMarketEventsAndErrors.sol`](../../src/interfaces/IMarketEventsAndErrors.sol)
and [`IWildcatMarketRevolving.sol`](../../src/interfaces/IWildcatMarketRevolving.sol).

## Wrappers, withdrawals, and sanctions

Canonical V2.5 wrapper creation emits:

1. `WrapperRegistered` from the market.
2. `WrapperDeployed` from the wrapper factory.

Standard ERC-20 and ERC-4626 `Transfer`, `Approval`, `Deposit`, and `Withdraw`
events remain part of the wrapper ABI. See
[`erc-4626-wrapper.md`](./erc-4626-wrapper.md).

The market withdrawal family includes:

- `WithdrawalBatchCreated` and `WithdrawalQueued`.
- `WithdrawalBatchPayment` and `WithdrawalBatchExpired`.
- `WithdrawalBatchClosed` and `WithdrawalExecuted`.

`queueWithdrawalScaled` uses this existing family. It adds no event or indexer
state.

Withdrawal and wrapper quarantine may also emit:

- `SanctionedAccountAssetsQueuedForWithdrawal`.
- `SanctionedAccountWithdrawalSentToEscrow`.
- `SanctionedAccountSharesSentToEscrow`.
- `NewSanctionsEscrow` and `EscrowReleased`.

Retain the emitter. Market-token escrow, underlying-asset escrow, and
wrapper-share escrow hold different assets and represent different transitions.

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
