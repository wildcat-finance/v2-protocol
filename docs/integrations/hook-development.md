# Hook development

A custom hook combines shared behavior, one term policy, and additional feature
policies in Solidity source. The result is one deployed hook contract. Each
market still calls one immutable hook address with its selected callback flags.

Start with [Hooks](./hooks.md) for the market callback contract and
[Access control](./access-control.md) for credentials and administration. This
guide covers the internal extension points and the decisions a composition must
make. Existing hook instances do not acquire new features when new source is
deployed.

## Components and state ownership

| Component | Responsibility |
| --- | --- |
| [`BaseAccessControls`](../../src/access/BaseAccessControls.sol) | Administrator, providers, credentials, local deposit blocks, known-lender state, and wrapper recognition. |
| [`MarketConstraintHooks`](../../src/access/MarketConstraintHooks.sol) | Creation bounds, temporary-reserve state, and the default APR calculation. |
| [`BaseHooks`](../../src/access/BaseHooks.sol) | Constructor/provider initialization, callback coordination, common action defaults, minimum-deposit management, and transfer-policy queries. |
| [`OpenTermPolicy`](../../src/access/OpenTermPolicy.sol) | Open configuration decoding, packed storage, and access adapters. It adds no withdrawal schedule. |
| [`FixedTermPolicy`](../../src/access/FixedTermPolicy.sol) | Fixed configuration/storage, maturity, term management, closure, and the pre-maturity APR guard. |
| [`PeriodicTermPolicy`](../../src/access/PeriodicTermPolicy.sol) | Periodic configuration/storage, windows, closure, and APR proposal/execution state. |
| Concrete template | Constructor flags, implementation identity, public configuration getters, and explicit integration of its selected rules. |
| Feature policy | Its own validation, state, events, and management/query APIs. |

Each term policy already inherits `BaseHooks`. A concrete composition supplies
the `BaseHooks(administrator, args, deploymentConfig)` constructor arguments
once. Inheriting a term policy lets it choose its own flags while retaining the
term's implementation. The existing concrete templates fix their constructor
flags and expose their original public getters.

`AccessConfig` is a memory view of the term's authoritative packed state.
`_readAccessConfig`, `_isDepositHookEnabled`, and `_writeMinimumDeposit` adapt
shared logic to that state. They do not maintain another access mapping. The
periodic configuration retains its one-slot packing and `uint96` minimum;
open/fixed minima use `uint128`.

Reuse the existing administrator and registration checks. Instance-wide
provider/credential state and market-specific feature state have different
scopes. A feature that applies separately to each market needs that market in
its state key; it must not duplicate registration or known-lender bookkeeping.

## Adding rules and replacing defaults

The public callbacks coordinate the action. Use the internal extension points
for customization; the public callback bodies are not a general override API.

| Action | Selected behavior and extension point |
| --- | --- |
| Creation | `_initializeMarket` decodes and writes term state; `_onMarketConfigured` adds feature setup after that state exists. |
| Deposit | Registration, `_processDeposit`, then `_checkDeposit`. Replace `_processDeposit` only when deliberately replacing block/minimum/credential processing and its bookkeeping. |
| Transfer | Registration, `_processTransfer`, then `_checkTransfer`. Default credential exemptions return from the helper, so additional checks still run. |
| Withdrawal queue | Registration, `_checkWithdrawalSchedule`, `_processWithdrawalAccess`, then `_checkQueueWithdrawal`. The market still selects the batch and expiry. |
| APR/reserves | `_applyAprUpdate` selects a strategy, usually `_applyDefaultAprUpdate`; `_checkAprChange` validates the effective result after that strategy's effects. |
| Closure | `_validateCloseMarket`, then `_applyCloseMarket`. Fixed/periodic policies supply their existing validation and effects. |
| Other callbacks | `_checkExecuteWithdrawal`, `_checkBorrow`, `_checkRepay`, `_checkNukeFromOrbit`, `_checkMaxTotalSupply`, and `_checkProtocolFeeBips` extend the existing empty defaults. |
| Recipient query | `_featureTransferRecipientAllowed` adds a recipient condition to the default transfer-policy answer. |

An additional check can reject an action and, where its signature permits,
record feature state. Rejection rolls back the transaction, including earlier
credential updates, proposal changes, events, and feature effects. A later
market rejection also rolls back a successful hook call.

A replacement owns everything it skips. For example, replacing
`_processDeposit` also takes responsibility for minimum-deposit rounding and
known-lender updates. Call only the selected implementation. Calling the old
default and ignoring its return values leaves its writes and events in effect
unless the transaction reverts.

## Composing several features

There is no fixed number of policy slots or capability-ownership bitmask.
Several policies can participate in one callback, and one policy can affect
several actions. The concrete composition chooses their order and resolves any
competing decisions.

Independent validators normally all have to pass. Two policies that calculate
the reserve ratio require a deliberate choice or a defined combined strategy.
Inheritance order alone does not establish that their writes, events, and
return values are compatible. A `super` call is appropriate when its selected
behavior is understood; it is not an automatic conflict resolver.

The compiling examples under `test/mocks/` demonstrate these choices:

| Example | Integration decision |
| --- | --- |
| [`TransferFeaturePolicies.sol`](../../test/mocks/TransferFeaturePolicies.sol) | Separate recipient restriction and per-transfer scaled-amount limit. `TransferFeatures` records accepted volume before checking the recipient, so a later rejection must roll back both feature and default effects. Volume saturates; it is observational, not a cumulative transfer quota. |
| [`TransferFeatureHooks.sol`](../../test/mocks/TransferFeatureHooks.sol) | Combines both rules with each term. `_checkTransfer` runs them after default processing; `_featureTransferRecipientAllowed` uses the same recipient predicate. Management delegates to `onlyAdministrator` and `_requireHookedMarket`. |
| [`BorrowAmountPolicy.sol`](../../test/mocks/BorrowAmountPolicy.sol) and [`BorrowFeatureHooks.sol`](../../test/mocks/BorrowFeatureHooks.sol) | Adds a fourth policy to the term-plus-two-transfer-rule composition, without editing those components. The amount is normalized underlying units. The assembly requires borrow dispatch and authenticates the market before recording a draw. |
| [`AprReplacementPolicy.sol`](../../test/mocks/AprReplacementPolicy.sol) and [`AprReplacementHooks.sol`](../../test/mocks/AprReplacementHooks.sol) | Replaces the default APR calculation while retaining both transfer features and term routing. The probe keeps the requested APR, selects reserve ratio 3,333, records its choice, and validates effective values. |

These are test assemblies, not supported product templates. Their limits,
identities, and harness-only state setters are examples of integration and
verification, not a recommended economic policy.

For every override, identify the retained and replaced defaults, caller checks,
state/event owners, error priority, and related entrypoints. Put the explanation
at the override and test the resulting behavior. A feature affecting transfers
may also affect recipient queries and wrappers; a feature affecting rates must
consider proposal execution and closure separately.

## Creation and callback activation

The factory authenticates `onCreateMarket`. `BaseHooks` keeps parameter bounds
and administrator validation ahead of term decoding. The term initializer
preserves its required data length, optional-word defaults, low-bit booleans,
checked numeric widths, and failure/event order.

`_onMarketConfigured` runs after packed term state is written but before market
code is deployed. Use `parameters`, `hooksData`, the future address, and the
stored hook configuration. Calling getters on the future market is invalid at
this point. A rejection restores registration and all creation effects.

Declare every required callback in the concrete constructor's immutable
`deploymentConfig`. `_onMarketConfigured` cannot replace the final flags. An
inherited callback implementation does nothing if the market never dispatches
to it.

Capture requested access choices before forcing feature callbacks. Required
transfer dispatch, for example, must not silently require transfer credentials.
The original flag rules are described in [Hooks](./hooks.md#callback-flags).
Callback bits cannot be enabled later on an existing market.

## Caller authentication and authority

Deposit, transfer, and queue coordinators authenticate registration before
their extension checks. Fixed/periodic closure and periodic APR routes also
check their market binding. Existing open/fixed APR paths and empty callbacks
retain their original caller behavior; inheritance does not make every internal
extension point authenticated.

A new stateful feature must call `_requireHookedMarket(msg.sender)` before
trusting the caller as a market or writing its feature state when the enclosing
path does not already do so. The open/fixed APR replacement examples do this
before recording the selected APR. Caller-supplied `MarketState` is not evidence
that the caller is a market.

For management APIs, reuse `onlyAdministrator` and authenticate the supplied
market. A pending administrator has no authority. Completed administrator
transfer changes feature-management authority along with the existing hook
authority, without changing the operational borrower of any attached market.
See [Access control](./access-control.md#hook-administration).

## APR strategy and effective-value validation

`_applyDefaultAprUpdate` owns the shared APR bounds and temporary-reserve
calculation. Replacing it replaces those checks too. The APR examples explicitly
retain the supported range before applying their chosen calculation.

Fixed `_applyAprUpdate` checks `_validateFixedAprUpdate` first. Replacing only
`_applyDefaultAprUpdate` retains the pre-maturity restriction. Replacing the
whole `_applyAprUpdate` strategy must preserve or explicitly replace that guard.

Periodic routing makes a different choice:

- An increase cancels a proposal, then uses `_applyDefaultAprUpdate`.
- An unchanged APR retains the proposal and uses `_applyDefaultAprUpdate`.
- A reduction executes its exact matured proposal and keeps the current
  reserve ratio. It skips the temporary-reserve default entirely.

`_checkAprChange` receives an `AprChange` with the market, route, requested APR/
reserves, and effective APR/reserves. Validate `effectiveApr` and
`effectiveReserve`, since those are what the market will apply. This check
returns no replacement values.

Both periodic execution paths reach it:

| Route | Context |
| --- | --- |
| `AprRoute.Ordinary` | Borrower calls the market's ordinary APR setter. The context retains the requested values and supplied callback data, even when the periodic reduction strategy ignores requested reserves. |
| `AprRoute.PendingReduction` | Anyone calls the market's dedicated execution method; the market calls the hook. Both reserve fields contain the current market reserve ratio. Callback data is empty even if bytes were appended to the market call. |

The dedicated route returns only an APR. An override cannot change its reserve
ratio through this interface. Proposal validation at `_checkPeriodicProposal`
runs before proposal replacement and events; it does not replace execution-time
validation when conditions may have changed. See
[Periodic-term hooks](./periodic-term-hooks.md#apr-reductions).

## Management, closure, and accounting boundaries

`_validateFixedTermChange` runs after native setter checks and before maturity
is written. `_afterFixedTermChange` runs after the write and `FixedTermUpdated`.
Neither runs during creation or early closure. A rule that applies to every
maturity transition must cover those separate paths explicitly.

Preserve fixed/periodic closure behavior when extending `_validateCloseMarket`
or `_applyCloseMarket`. The fixed helpers enforce either permitted early-close
flag and bring maturity forward. The periodic helpers close the schedule and
cancel a proposal. Open closure starts as an empty, unauthenticated default.

The market resets APR to zero and reserves to 10,000 after its closure callback;
it does not call the ordinary APR-update validator. Creation also has its own
rate validation. An APR feature must decide separately how it treats those
transitions.

All callback effects occur at the existing
[intermediate-state boundary](./hooks.md#intermediate-state-ordering). An
additional check after a default is still before the market's subsequent action
accounting. Partial batch payments have no callback. Hooks are not a complete
post-action accounting or event feed, and withdrawal batching remains owned by
the market.

## Views, exemptions, and callback data

Known recipients and registered wrappers bypass default credential/block
checks. They still reach `_checkTransfer` and its feature restrictions. Keep
recipient restrictions consistent with `_featureTransferRecipientAllowed`.

The recipient query has no amount, balance, allowance, or arbitrary callback
data. A true result does not promise that every transfer or wrapper deposit
will succeed. Keep `isMarketTransferDisabled`'s permanent-false promise: a
feature should not repurpose that configuration flag for a mutable global
transfer switch. See [ERC-4626 wrapper](./erc-4626-wrapper.md).

Existing [credential data](./access-control.md#hooksdata) has its own encoding.
There is no general multi-feature data envelope. Two policies cannot each assume
the whole `extraData` payload belongs to them. Define decoding and ownership
explicitly when adding data, and account for routes that provide empty data.

## Public formats and implementation identity

The three original concrete files still export their `HookedMarket` types and
getters. Type definitions live under [`access/types/`](../../src/access/types/).
Use aliases when importing more than one term's configuration type.

Moved errors/events are declared by their owning base or policy. Source code
that qualifies an inherited declaration through a concrete contract may need
to name that owner instead, such as `BaseHooks.NotHookedMarket.selector`.
This does not change the emitted address, event topic, or error selector.

Generate integration bindings from the concrete implementation ABI. The
abstract `MarketConstraintHooks` APR declaration inherits its parameter/result
labels from `IHooks`; the implemented callback belongs to `BaseHooks`.
Named callback inputs and declaration moves do not change wire types, but raw
ABI labels still matter to generated bindings.

The original family strings remain `OpenTermHooks`, `FixedTermHooks`, and
`PeriodicTermHooks`; periodic `templateVersion()` remains 2. Existing lenses
recognize those strings and expect their specific public tuples. A new feature
identity is `Unknown` to that classifier until explicitly integrated. Reusing
a family string alone does not qualify a new implementation for its decoder.

Source reuse still produces new initcode and runtime identities. Record the
actual deployed artifact and template provenance. Preserve historical deployment
inventories; a matching interface is not a deployment or an upgrade.

## Deployment limits

Measure each concrete composition with the pinned settings in
[`foundry.toml`](../../foundry.toml): solc 0.8.25, Cancun, via IR, optimizer 44
runs, and no appended CBOR metadata. Source deduplication does not imply smaller
deployed code.

Both deployed runtime and `STOP || initcode` storage must fit 24,576 bytes.
Factory constructor payloads must fit 49,152 bytes; `(address, bytes)` with
empty `args` adds 96 bytes to creation code. Larger provider arguments consume
additional payload space and must be checked for the intended deployment.

Current original-template sizes are:

| Template | Runtime bytes | Creation bytes | Stored-initcode headroom |
| --- | ---: | ---: | ---: |
| Open | 15,653 | 18,379 | 6,196 |
| Fixed | 17,014 | 19,741 | 4,834 |
| Periodic | 19,949 | 22,676 | 1,899 |

The example assemblies show the remaining stored-initcode margin:

| Assembly | Open | Fixed | Periodic | Deployment evidence |
| --- | ---: | ---: | ---: | --- |
| Two transfer features | 5,368 | 4,010 | 1,118 | Direct runtime and actual initcode storage deployment. |
| Transfer features plus borrow | 4,903 | 3,545 | 653 | Both real market factories. |
| Transfer features plus APR replacement | 5,641 | 4,302 | 1,260 | Both real market factories. |

All three original templates also deploy through both real factories. A larger
assembly's factory test does not establish that a different concrete artifact
has been tested through that path. The periodic borrow example leaves little
room for further code; measure the selected combination before relying on it.

For reproducible bytecode comparisons, retain the complete compilation source
set and output settings as well as revision, compiler, and optimizer settings.
Matching per-contract source metadata alone does not identify the whole build.
Compare gas with the same state, calldata, transaction isolation, and direct or
market-nested call boundary. Whole-test gas includes fixture deployments and is
not a transaction quote for the feature.

## Tests

- [`BaseHooks.t.sol`](../../test/access/BaseHooks.t.sol): common creation,
  credential/default actions, public configuration, and legacy caller behavior
- [`HookExtensions.t.sol`](../../test/access/HookExtensions.t.sol): overlapping
  rules, error priority, exemptions, state isolation, views, and rollback
- [`AprValidation.t.sol`](../../test/access/AprValidation.t.sol): effective
  values, default replacement, skipped effects, both APR routes, and callers
- [`FixedTermHooks.t.sol`](../../test/access/FixedTermHooks.t.sol) and
  [`PeriodicTermHooks.t.sol`](../../test/access/PeriodicTermHooks.t.sol): term
  transitions and management extension points
- [`ProductionMatrixScenarios.t.sol`](../../test/integration/ProductionMatrixScenarios.t.sol):
  real factories, composed operations, closure/batches, lens decoding,
  administrator discovery, and wrappers across term/market combinations
- [`BorrowerAccountCompatibility.t.sol`](../../test/integration/BorrowerAccountCompatibility.t.sol):
  delegated caller/principal compatibility using account mocks, without claiming
  a released Borrower Account implementation

Use the canonical commands and suite policy in [`TESTS.md`](../../TESTS.md).
Test the actual concrete combination, including simultaneous failures, later
market rejection, alternate entrypoints, and configuration that forces callback
dispatch without requiring credentials. Keep existing expected behavior in its
owning suites and add focused properties for new decisions.
