# M1 design: shared hooks and explicit policy integration

- Status: M1 complete; ready for milestone review. Production refactoring has
  not started.
- Implements the [agreed spec](hook-composition.md) against the
  [behavior map](hook-behavior-map.md) and [measured baseline](hook-refactor-m1-baseline.md).
- This is an implementation contract for M2/M3, not deployed Solidity or an
  executable composition proof. Tranching economics remain out of scope.

## Storage decision

Keep one packed, template-specific market configuration and expose common
fields to shared logic through internal memory adapters. Do not replace it
with a common storage mapping plus a schedule mapping. The access adapter is
a view of the owned state, never a second persisted copy.

The current compiler storage layout confirms every `HookedMarket` occupies one
32-byte slot: open uses 20 bytes, fixed 27, periodic 31. Open/fixed additionally
use `_depositHookEnabled`; periodic embeds that flag in its packed slot.

| Alternative | Consequence | Decision |
| --- | --- | --- |
| Common `uint128` minimum plus all periodic fields in one ordinary struct | 35 field bytes need two storage slots; solc reports 64 bytes. | Reject. It loses current packing merely to unify field types. |
| Common access mapping plus separate periodic schedule mapping | At least two independently addressed configuration slots; creation and schedule-dependent callbacks touch both. | Reject for the current templates. It adds persistent state/storage work without an established feature need. |
| Existing packed structs with read/write adapters | One authoritative configuration per market; adapters widen periodic's minimum only in memory and check narrowing on writes. | Select. Share rules while retaining current packing and public formats. |

Preserve each existing field order and width initially. Internal mapping slot
numbers may move in new deployments; this is not a proxy upgrade/storage
migration. Do not spend layout complexity packing open/fixed's dispatch flag
into their remaining bytes during this refactor. Its separate getter is only
needed for minimum updates, so common hot-callback reads must not load it.

Expected costs are explicit but are not final-template measurements:

- Reading the common access view decodes the existing packed configuration.
  It must not fetch `_depositHookEnabled` unless the action needs that flag.
- A term helper may reread the same packed slot already read by the coordinator;
  that read is warm within the callback. Inlining/common-subexpression
  elimination may remove it, but the design does not assume that optimization.
- Memory adapters and internal integration can add instructions even where
  storage work stays the same. Measure the actual M2/M3 templates against M1;
  source sharing alone does not prove a gas or bytecode improvement.
- Existing writes retain their width/slot behavior: minimum updates modify the
  packed configuration, fixed maturity modifies that same slot, periodic
  closure modifies it and can delete the separate one-slot APR proposal.
  Credential and temporary-reserve writes retain their existing owners.
- Periodic's 2,577-byte stored-initcode headroom is the immediate deployment
  constraint. Compare creation code plus the STOP prefix after every substantial
  extraction, as well as final runtime and operation gas.

## Component and state ownership

Names below are the selected organization. Implementations may make mechanical
file adjustments without creating parallel versions of the same behavior.

| Component | Owned behavior/state/events |
| --- | --- |
| Existing `BaseAccessControls` | Instance administrator/name/provider configuration, provider indices, lender credential cache, local deposit blocks, per-market known-lender mapping, credential/first-entry/admin/provider events, wrapper/access query helpers. Keep one implementation; no duplicate access base. |
| Existing `MarketConstraintHooks` | Creation bounds and advertised constraints, `temporaryExcessReserveRatio` and its events, existing APR/reserve calculation. Extract its callback body into one named internal default strategy so selection never requires calling a public callback and discarding results. |
| New `BaseHooks` | Callback coordination, common deposit/transfer/withdrawal-access defaults, common creation/access/flag helpers, minimum setter checks/event, common transfer-policy query coordination, common errors, explicit internal extension points. Inherits the two existing bases once. |
| `OpenTermHooks` | Open packed configuration and dispatch mapping, open decoding/read/write adapters, constructor/family/public tuple adapters. No separate open schedule policy. |
| New `FixedTermPolicy` | Fixed packed configuration and dispatch mapping, maturity/permissions, fixed initialization/schedule/APR guard/closure/setter helpers and term events. Its common adapters expose the packed state to `BaseHooks`. |
| New `PeriodicTermPolicy` | Periodic packed configuration, one-slot pending proposals, schedule/proposal lifecycle and events, periodic APR strategy and dedicated execution API. Its common adapters expose the packed state to `BaseHooks`. |
| `FixedTermHooks`, `PeriodicTermHooks` | Thin concrete constructors, family/revision identity, existing public configuration/proposal type adapters. Reuse the corresponding term policy. |
| Future feature component | Its own feature state, events, and management/query APIs, plus action validation or deliberately selected strategy helpers. It neither duplicates credentials nor appends named-feature branches to the base. |

Both term policies inherit `BaseHooks` abstractly. An independent feature may
also inherit that base for its extension signatures; Solidity's diamond has
one base state instance. The final composition must explicitly resolve actual
override conflicts and choose helper ordering. State unification is not a
semantic conflict-resolution mechanism.

Store `config` once as a `BaseHooks` immutable initialized from the concrete
composition's deployment flags. Constructor inputs stay `(address,bytes)` on
all public templates; base constructor arguments are internal implementation
details. `IHooks` remains the single owner of the immutable creating factory
and the existing factory-authenticated creation entrypoint.

### Public types and source consumers

Move global public struct declarations, if necessary, into distinct type files
under `src/access/types/` (`OpenTermHookTypes.sol`, `FixedTermHookTypes.sol`, and
`PeriodicTermHookTypes.sol`). Each retains its existing global type names,
field names/order/widths, including `HookedMarket` and periodic proposal types.
The concrete template files import/re-export their own types so existing lens
imports continue to work. Policy files import the type file directly; avoid a
policy-to-concrete circular dependency.

Keep concrete `getHookedMarket(s)` adapters because Solidity return types are
different source types and public tuples. They directly read the authoritative
mapping; no extra cache or mirrored state is maintained. These small adapters
are format conversion, not independent implementations of access rules.

A solc 0.8.25 probe confirms named import through the concrete file preserves
the global struct and its ABI `internalType`. The probe also confirms that
`ConcreteHook.SomeError.selector` does not resolve an error newly inherited
from a base. Update such repository references to the declaration owner
(`BaseHooks`, `FixedTermPolicy`, or `PeriodicTermPolicy`) when moving them;
qualified event references should follow the owning declaration as needed.
That is a mechanical source import/namespace adjustment. Error/event selectors,
indexed fields, payloads, and runtime revert/event behavior must remain equal.
Do not retain duplicate declarations or implementations just to avoid it.

### Compiler evidence

Local evidence uses solc `0.8.25`, Cancun, via IR, optimizer 44, with
`storageLayout`/ABI output selected. The exact standard-JSON inputs and outputs
are under `audits/hook-refactor/m1/2026-09-22/`; reproduce with
`solc --standard-json --base-path . --allow-paths . < <request-file>`.
The adapter probe contains only minimal structs/contracts, not a second
protocol implementation. Its first error is deliberate evidence of the
qualified inherited-error limitation; the corrected struct-import probe
compiles successfully.

| Evidence | SHA-256 |
| --- | --- |
| `storage-output.json` (current three templates) | `45ff5722085235108d0ec613c264a96124f59ba02bd64451f1f72072b52b9db9` |
| `adapter-experiment-request.json` | `3c6cb9e555f1b73769febf6b7965f89467539d01131c44137e08c5e44642c35e` |
| `adapter-experiment-output.json` (qualified error rejected) | `95db3355e62dbfb4404ad593350ef6178e5494497445b123347fd961773d11be` |
| `adapter-experiment-reexport-request.json` | `eb9a10b0e6137aa3d75ece39d945ca6dd2be180b0023b79cc588ce69d8794da4` |
| `adapter-experiment-reexport-output.json` (successful type/layout probe) | `b895fd3a3f133f0b45e273af8b8e3e3773336f4cf43d4ed29fc6814690165eea` |

## Internal contract

The following are concrete implementation signatures and sequencing. Existing
external selectors, argument/return encodings, and public configuration types
stay unchanged. Shared callback bodies coordinate the internal operations;
compositions override the declared internal points rather than copying those
bodies. There is no policy registry, fixed policy count, or ownership bitmask.

### Access adapters and authentication

```solidity
struct AccessConfig {
  bool isHooked;
  bool transferRequiresAccess;
  bool depositRequiresAccess;
  bool withdrawalRequiresAccess;
  uint128 minimumDeposit;
  bool transfersDisabled;
}

function _readAccessConfig(address market)
  internal view virtual returns (AccessConfig memory);
function _isDepositHookEnabled(address market)
  internal view virtual returns (bool);
function _writeMinimumDeposit(address market, uint128 value) internal virtual;

function _requireHookedMarket(address market)
  internal view returns (AccessConfig memory access);
```

The first three signatures are implemented by the storage owner. The last
loads the adapter and reverts `NotHookedMarket` when unregistered. It performs
no market external call and no `code.length` check. Registration is meaningful
before deployment. An open adapter supplies `withdrawalRequiresAccess=true`
because its queue callback always requires access when invoked; it does not
invent a new stored field or enable queue dispatch.

Deposit, transfer, and queue coordinators call `_requireHookedMarket(msg.sender)`
once before default processing. Minimum management and transfer-policy queries
authenticate their explicit market argument. APR coordination and unused
callbacks do not gain that guard globally. Fixed's APR guard reads its mapping
without asserting registration; periodic's strategy authenticates as it does
today. Closure authentication belongs to the selected term validation; open's
empty default stays unguarded.

`setMinimumDeposit(address,uint128)` remains shared, administrator-only:
read/authenticate market, reject positive values without deposit dispatch,
capture previous minimum, call the storage owner's `_writeMinimumDeposit`,
emit `MinimumDepositUpdated`. The periodic writer performs the current checked
`uint96` conversion; open/fixed accept the full `uint128`. No callback is
enabled by this setter. A bespoke feature can add its own management API;
changing these shared setter semantics requires an explicit internal helper
extraction/override with corresponding tests, not a second minimum mapping.

### Creation

```solidity
constructor(
  address administrator_,
  bytes memory args,
  HooksDeploymentConfig deploymentConfig
);

function _initializeMarket(
  address administrator_, address market,
  DeployMarketInputs calldata parameters, bytes calldata hooksData
) internal virtual returns (HooksConfig);

function _configureMarketAccess(
  address administrator_, address market, HooksConfig requested,
  uint128 minimumDeposit, bool transfersDisabled
) internal returns (
  AccessConfig memory access, bool depositHookEnabled, HooksConfig effective
);

function _onMarketConfigured(
  address administrator_, address market,
  DeployMarketInputs calldata parameters, bytes calldata hooksData,
  HooksConfig effective
) internal virtual;
```

The constructor shown is `BaseHooks`' internal inheritance contract. It invokes
the existing access constructor, assigns `config`, and uses the existing
`NameAndProviderInputs` initialization when `args` is nonempty. Public concrete
constructors still accept only `(address,bytes)` and supply their exact
optional/required deployment flags. New compositions deliberately supply the
union of callbacks their selected features need. Required flags do not imply
credential requirements.

`IHooks.onCreateMarket` keeps its current factory guard and delegates to
`BaseHooks._onCreateMarket`. That coordinator runs the existing
`MarketConstraintHooks._onCreateMarket` bounds check, then the administrator
match, then `_initializeMarket`, then `_onMarketConfigured`, returning the
effective configuration. The final extension point defaults to empty; it can
validate/initialize feature state while the future market still has no code.
Failure rolls back the entire configuration and its events.

Open implements `_initializeMarket` directly; term policies delegate it to
named, reusable `_initializeFixedMarket` / `_initializePeriodicMarket` helpers
with the same arguments and return type. Each helper preserves its current
staged decoding and check order: required length and schedule numbers first,
term validation and event next, then minimum/optional fields and common access
configuration. Do not eagerly decode all fields into a struct: a minimum-width
failure must not precede an existing term failure.

`_configureMarketAccess` owns requested access-bit capture, invalid withdrawal
access rejection, minimum event/dispatch, disabled-transfer dispatch, supporting
deposit/transfer flags, and merging the template's deployment flags. It returns
the common values and final deposit-dispatch flag; the template/policy packs
and stores its complete configuration once. Open/fixed also store the separate
dispatch flag. Current periodic records that flag before the merge; its required
flags contain no deposit bit, so storing the final result is equivalent for
the existing template and correct for a future composition requiring deposits.
Feature-driven callback activation must not recategorize the earlier requested
access bits.

Preserve the current raw calldata readers and encodings. `_onMarketConfigured`
does not allocate ownership of `hooksData` to multiple features automatically.
A new composition that needs different configuration or callback data explicitly
defines decoding and coordinates its components. No universal data envelope
is introduced here.

### Lender action defaults and additional rules

```solidity
function _processDeposit(
  AccessConfig memory access, address lender, uint256 scaledAmount,
  MarketState calldata state, bytes calldata extraData
) internal virtual;
function _checkDeposit(
  address lender, uint256 scaledAmount,
  MarketState calldata state, bytes calldata extraData
) internal virtual;

function _processTransfer(
  AccessConfig memory access, address caller, address from, address to,
  uint256 scaledAmount, MarketState calldata state, bytes calldata extraData
) internal virtual;
function _checkTransfer(
  address caller, address from, address to, uint256 scaledAmount,
  MarketState calldata state, bytes calldata extraData
) internal virtual;

function _checkWithdrawalSchedule(
  address lender, uint32 expiry, uint256 scaledAmount,
  MarketState calldata state, bytes calldata extraData
) internal view virtual;
function _processWithdrawalAccess(
  AccessConfig memory access, address lender, bytes calldata extraData
) internal virtual;
function _checkQueueWithdrawal(
  address lender, uint32 expiry, uint256 scaledAmount,
  MarketState calldata state, bytes calldata extraData
) internal virtual;
```

| Coordinator | Ordered internal work after registration |
| --- | --- |
| `onDeposit` | `_processDeposit`, then `_checkDeposit` |
| `onTransfer` | `_processTransfer`, then `_checkTransfer` |
| `onQueueWithdrawal` | `_checkWithdrawalSchedule`, `_processWithdrawalAccess`, then `_checkQueueWithdrawal` |

The process functions are replaceable defaults, with one original implementation
in `BaseHooks`. `_processDeposit` retains local block, scaled-minimum floor,
credential resolution, and `_writeLenderStatus` order. `_processTransfer` retains
disabled-transfer rejection before known/canonical-wrapper exemptions, then
unknown-recipient block, credential resolution, and bookkeeping. They call the
existing `BaseAccessControls` machinery exactly once where currently required.

Credential exemption returns occur inside `_processTransfer`, not in the
external coordinator; every applicable additional transfer rule still runs.
Likewise, optional credentials or a known lender cannot bypass additional
queue/deposit rules. `_processWithdrawalAccess` honors the adapter's access
boolean, uses the current known-or-credential condition, and does not mark a
new lender known merely for queueing.

The three additional `_check*` action points default to empty. They are
non-view so a feature may validate and maintain its own callback-time state.
They run after default processing but before the market's subsequent action
accounting. Rejection rolls back credential, known-lender, and feature changes.
These are not post-deposit/post-transfer observers.

Default replacement overrides the relevant `_process*` function and documents
which parts are retained or skipped. It can call a base implementation once
when retaining it; a replacement must own any omitted credential/bookkeeping
semantics explicitly. Authentication and unrelated action checks stay in the
coordinator. Additive policies use named helpers called by an explicit final
`_check*` override, so no inherited early return chooses the winning feature.

The schedule default is empty. Fixed checks current maturity; periodic checks
the schedule and both hook/market closed-state exemptions before withdrawal
access. Schedule policies cannot choose the batch, alter expiry, or bypass
underlying queue accounting; the existing callback returns no such value.
Quarantine later reaches this same ordinary queue path.

### APR strategy and effective-value validation

```solidity
enum AprRoute { Ordinary, PendingReduction }

struct AprChange {
  address market;
  AprRoute route;
  uint16 requestedApr;
  uint16 requestedReserve;
  uint16 effectiveApr;
  uint16 effectiveReserve;
}

function _applyDefaultAprUpdate(
  uint16 annualInterestBips, MarketState calldata state
) internal virtual returns (uint16 effectiveApr, uint16 effectiveReserve);

function _applyAprUpdate(
  uint16 annualInterestBips, uint16 reserveRatioBips,
  MarketState calldata state, bytes calldata extraData
) internal virtual returns (uint16 effectiveApr, uint16 effectiveReserve);

function _checkAprChange(
  AprChange memory change, MarketState calldata state, bytes calldata extraData
) internal virtual;
```

`MarketConstraintHooks` owns `_applyDefaultAprUpdate`: move the existing
calculation/state/events into it without rewriting the algorithm. The shared
external callback moves to `BaseHooks`; `_applyAprUpdate` defaults to that
internal calculation. It deliberately does not use the requested reserve.
This helper is itself a designated replacement point: a composed feature can
replace the shared calculation while leaving fixed's guard or periodic's
increase/cancellation coordination in place. The outer `_applyAprUpdate` is
the replacement point when the entire strategy selection, requested reserve,
or callback data matters. A periodic reduction bypasses the default helper
deliberately; replacing that helper alone does not replace the proposal policy.
The coordinator constructs `AprChange` from the selected result, invokes
`_checkAprChange`, then returns that exact pair to the market. The check defaults
to empty, is non-view for feature state, and returns no replacement values.

Fixed overrides `_applyAprUpdate` to run its pre-maturity reduction guard then
invoke `_applyDefaultAprUpdate`. Periodic selects its whole strategy explicitly:

1. Authenticate the market.
2. Increase: cancel/delete an existing proposal and emit cancellation, then
   invoke the default strategy.
3. Equal APR: retain the proposal and invoke the default strategy.
4. Reduction: execute the exact pending proposal with the periodic helper,
   return that APR and `state.reserveRatioBips`, and never invoke the default
   strategy. Temporary-reserve storage/events are deliberately untouched.

Do not invoke two calculators and discard one result: its state changes would
remain. A composition requiring a different APR/reserve calculation replaces
`_applyAprUpdate` and owns that calculation's associated state/events. Several
effective-value constraints combine in `_checkAprChange`; all must accept the
selected pair. Two competing replacement strategies require developer-written
integration, not `super` linearization or a min/max rule added by the framework.

Periodic keeps one `_executePeriodicReduction` helper shared by both routes:

```solidity
function _executePeriodicReduction(
  HookedMarket memory marketConfig, MarketState calldata state,
  uint16 annualInterestBips, PendingAprChangeStorage memory proposal
) internal returns (uint16);
```

Its types are periodic's owned types. It retains missing/mismatch/strict-
reduction/range/time/unpaid-withdrawal checks in their existing order, then
deletes proposal state and emits execution. No extra closed check is introduced
inside it: ordinary market entrypoints already reject closed APR changes,
and closure clears proposals. Preserve direct-call behavior as well.

The dedicated external `executePendingAnnualInterestBipsReduction` retains its
APR-only ABI and registration check. It loads the proposal, executes that same
helper, constructs `AprChange` with route `PendingReduction`, the proposal APR
as requested APR, and current reserves as both requested/effective reserves,
then invokes the same `_checkAprChange` and returns the APR. It has no data
argument: pass the empty calldata slice `msg.data[msg.data.length:]`. Ordinary
callbacks continue passing the original calldata bytes without a generic
allocation/envelope. A validator can distinguish unavailable data via the route.

The market fixes reserves on this dedicated route. A feature whose alternate
calculation requires changing them must reject or deliberately exclude this
route under its documented template semantics, or request separate core work.
Returning another reserve value inside the hook cannot make the market apply
it. Both routes validate the values the market actually uses, after selected
proposal/default effects and before return; rejection reverts all those effects.

### Closure, term management, and proposals

```solidity
function _validateCloseMarket(MarketState calldata state, bytes calldata extraData)
  internal view virtual;
function _applyCloseMarket(MarketState calldata state, bytes calldata extraData)
  internal virtual;

// FixedTermPolicy: administrator-only public setter coordinates these.
function _validateFixedTermChange(address market, uint32 previousTime, uint32 newTime)
  internal view virtual;
function _afterFixedTermChange(address market, uint32 previousTime, uint32 newTime)
  internal virtual;

// PeriodicTermPolicy: administrator-only public proposal entrypoint.
function _checkPeriodicProposal(
  address market, uint16 proposedApr, uint32 responseStart, uint32 responseEnd
) internal view virtual;
```

`onCloseMarket` calls validation then state effects. Open defaults are empty,
including no new authentication. Fixed validates registration and the existing
early-close permission `(allowClosureBeforeTerm || allowTermReduction)`; its
effects move a still-future maturity to now and emit the existing update with
the market as caller. Periodic validates registration, sets its closed flag,
cancels/deletes any proposal with its event, then emits `PeriodicTermClosed`.
Neither clears temporary-reserve state merely because the market closes.

Provide named term helpers for the two phases so a combined hook can call
fixed/periodic validation and effects explicitly without copying them.
Additional closure restrictions go in validation; feature state changes go in
effects. All of this is at the existing pre-finalization callback boundary:
the market already funded debt (and may have invoked `onRepay`), then calls the
closure hook, then directly sets APR 0/reserves 10,000 and closes. It does not
call `_checkAprChange` through an APR callback. Rate features must therefore
state their creation and closure rules separately.

The fixed setter remains reusable in the policy: administrator and registration
checks, term-reduction permission (including the existing equal-time behavior),
no-extension check, `_validateFixedTermChange`, write maturity, emit
`FixedTermUpdated`, `_afterFixedTermChange`. The two extension defaults are
empty. Queueing, APR, closure, and queries read that same maturity; no second
term date is introduced. The after-helper still precedes return to the caller.

Periodic proposal management keeps its current public APIs, authority checks,
window calculations, bounds, strict-reduction market query, and fixed response
window. After those checks/calculations it calls `_checkPeriodicProposal`, then
cancels any prior proposal event, stores the new proposal, and emits proposed.
The extension default is empty. Proposal replacement, execution, APR increase,
and closure all use the same owned proposal mapping. Equality retains it;
expiry invalidates execution without deleting it automatically. A proposal
feature can restrict creation here, but must still validate at execution when
its conditions can change.

### Currently unused callbacks

Each shared external callback delegates once to the corresponding internal
virtual, non-view default below; all default bodies are empty:

```solidity
function _checkExecuteWithdrawal(
  address lender, uint32 expiry, uint128 amount,
  MarketState calldata state, bytes calldata extraData
) internal virtual;
function _checkBorrow(uint256 amount, MarketState calldata state, bytes calldata extraData)
  internal virtual;
function _checkRepay(uint256 amount, MarketState calldata state, bytes calldata extraData)
  internal virtual;
function _checkNukeFromOrbit(address lender, MarketState calldata state, bytes calldata extraData)
  internal virtual;
function _checkMaxTotalSupply(uint256 amount, MarketState calldata state, bytes calldata extraData)
  internal virtual;
function _checkProtocolFeeBips(uint16 bips, MarketState memory state, bytes calldata extraData)
  internal virtual;
```

Keep protocol-fee state in memory as in the current interface; other callbacks
retain calldata state. No new checks or flags are enabled for current templates.
A stateful new feature must activate its callback in deployment configuration
and authenticate with `_requireHookedMarket(msg.sender)` before treating the
caller as a market. A combined override can authenticate once before invoking
its feature helpers. These callbacks can reject actions and update hook state;
they cannot rewrite supply/fee/borrow amounts or observe the market's later
accounting merely by adding an internal function.

### Transfer-policy views

Shared queries authenticate registration, then use the owned configuration and
existing `BaseAccessControls` query machinery. The internal recipient default
and extension query are:

```solidity
function _defaultTransferRecipientAllowed(
  address market, address recipient, AccessConfig memory access
) internal view returns (bool);
function _featureTransferRecipientAllowed(address market, address recipient)
  internal view virtual returns (bool);
```

The latter defaults to true. `isMarketTransferRecipientAllowed` returns their
conjunction: known-lender/wrapper credential exemptions cannot skip feature
recipient restrictions. A feature with a recipient rule supplies both its
callback validation and corresponding no-data view through the same owned rule
helper where practical. Amount-dependent checks are outside this view's promise.

`isMarketTransferDisabled` returns the existing deployment-time configuration
flag. Its false result is a permanent promise. A new feature that could later
disable transfers universally is not compatible with inheriting that answer
unchanged, even if its callback composition compiles. Such a feature needs an
explicitly different valid integration contract; this refactor does not invent
a runtime global-transfer-lock policy.

### Signature and inheritance probe

A minimal solc probe compiles the selected inheritance shape, an internal pure
term configuration helper passed to the base constructor, memory context plus
calldata state/data, and the empty calldata slice for the dedicated APR route.
It does not implement protocol rules or test runtime composition semantics.

Where the term inheritance leg retains an unmodified base check and two feature
legs override it, the final override list includes all three declaration owners:
`override(BaseHooks, FeatureA, FeatureB)`. The initial probe omitted the base and
solc rejected it; the corrected form compiles. The final body explicitly calls
the two feature helpers. Including the base in the override list does not mean
its body must run, and the list itself does not establish valid rule ordering.

The evidence root contains `interface-probe-request.json` (SHA-256
`ad1e60527d042f7fabdbb554381a5856542da099241b85574292111aac5679e8`)
and `interface-probe-output.json` (SHA-256
`e9485e3c71faf90b0ed630e52894673eae5a7bb44d7bd5aa82e2ef3ebedeb3ab`).
M4 still owes executable tests of overlapping rules, rollback, exemptions,
alternate routes, and three-/four-policy combinations.

## Metadata and expected ABI comparison

Keep all three exact family strings and retain periodic `templateVersion()`
as `uint256(2)`. Do not add revision getters to open/fixed. The periodic source,
tests, and integration guide describe the existing getter as an **ABI revision**;
this refactor preserves that revision's selectors and encoded formats. Treating
it as a new implementation counter would change an established meaning without
helping family-based decoding.

New compiled code still has new creation/runtime hashes and new deployment
identities. Deployment records and bytecode identify that implementation;
neither the family string nor ABI revision claims identical bytecode. Existing
deployment inventories must not be rewritten, and publishing/registering new
templates is later release work.

| Surface | Expected result after implementation |
| --- | --- |
| Family `version()` | Exact values `OpenTermHooks`, `FixedTermHooks`, `PeriodicTermHooks`. |
| `templateVersion()` | Present only on periodic; same selector, return type, and value 2. |
| Public functions/constructor | Same selectors, input/output types, tuple field names/order, widths, and mutability; no new external selectors on existing concrete templates. |
| Public configuration/proposal types | Same names available from current concrete-file imports and same ABI tuple structures. |
| Events/errors | Same signatures, argument/indexed layouts and payloads, and observed ordering/revert behavior. Qualified source references may move to the declaration owner. |
| Bytecode/initcode/address identities | Expected to change in the refactor; newly measured and separately registered/deployed later. |

There is one anticipated JSON-level naming difference to make explicit:
currently unused callback arguments are often unnamed, and the three templates
are inconsistent. For example, periodic's `onExecuteWithdrawal` and `onRepay`
inputs are all unnamed while open/fixed name some of them; only periodic names
the queue callback's `state`. Sharing coordinators that pass these values to
extensions necessarily gives those arguments names.

Keep existing nonempty top-level callback argument names where shared today;
name previously unnamed arguments consistently with their meanings in `IHooks`.
This permits **empty-to-named top-level callback inputs only**, not tuple-field
renames, numeric/type changes, new selectors, or casual relabeling of existing
named arguments. Internal helper argument names have no public ABI meaning.
M5 should retain the raw ABI diff and enumerate these naming additions, while
requiring exact semantic equality of the encoded surface and exact public
tuple field names. Do not claim byte-for-byte ABI JSON equality or blindly
strip all names to hide a configuration-format change. This label-only change
does not require a new periodic ABI revision.

## Final walkthrough

The mapping below accounts for each current behavior family. It establishes
design coverage, not an assertion that refactored bytecode has passed tests.

| Existing behavior / edge | Selected path and ownership |
| --- | --- |
| Creation before market code exists | Factory guard in `IHooks`; bounds then administrator match in `BaseHooks`; staged term decode/event then shared access/flag configuration; owner writes packed state; feature binding runs last. |
| Provider administration, hook-administrator transfer, borrower accounts | Existing `BaseAccessControls`/factory/market authority paths retained. The callback caller remains the market, not its borrower or account contract. |
| Positive minimum and credentialed/optional deposits | Shared `_processDeposit` performs block, floored minimum, credential and known-lender work; additional check executes afterward. Periodic storage writer still narrows to 96 bits. |
| Known recipient or exact canonical wrapper | Shared transfer default applies global disabled flag first, then its credential exemption; coordinator still reaches additional rules. Public recipient view includes feature restrictions. |
| Fixed/periodic queue and quarantine | Registration, schedule, requested access, then added checks. Open adapter always requests access when invoked. The market owns batches/expiry/accounting; executing queued withdrawals stays ungated. |
| Fixed APR | Same pre-maturity guard, then selected shared calculation, then effective-value checks. No incidental registered-market assertion. |
| Periodic increase / equality | Registered-market assertion; increase alone cancels the proposal; selected shared calculation follows. Equality preserves proposal. |
| Periodic ordinary reduction | Shared periodic execution helper checks exact proposal, timing, strict reduction and unpaid withdrawals; deletes/emits; returns current reserves; common effective-value checks follow. |
| Periodic dedicated reduction | Same proposal helper and effective-value checks, but explicit APR-only route and empty data; market retains current reserves. |
| Proposal creation/replacement/expiry | Periodic owner retains all checks and fixed window bounds; extension proposal check precedes cancel/write/propose effects. Time alone does not clear a proposal. |
| Fixed maturity setter / closure | Same authoritative date serves queue/APR/views; setter cannot extend. Closure's current OR permission is preserved, then the same date changes with the same event. |
| Periodic closure | Registered-market check, closed flag, proposal deletion/cancellation event, closed event. Later queue schedule is open; access checks remain applicable. |
| Market closure rate reset | Separate closure validation/effects; no invented APR callback. Feature rate rules explicitly decide whether to permit fully funded closure to APR 0/reserves 100%. |
| Empty callbacks | Shared empty internal defaults retain current unknown-caller behavior; stateful extensions authenticate and activate their callbacks explicitly. |
| Public views/encodings | Concrete tuple adapters and type re-exports preserve formats; common views preserve registration/revert behavior and permanent global-transfer promise. |

Provide named term primitives as well as their default override wiring. In
particular, the following helper signatures let a concrete integration reuse
term checks without executing an unwanted APR or closure state strategy:

```solidity
function _validateFixedWithdrawalSchedule() internal view;
function _validatePeriodicWithdrawalSchedule(MarketState calldata state) internal view;
function _validateFixedAprUpdate(uint16 annualInterestBips, MarketState calldata state)
  internal view;
function _validateFixedCloseMarket() internal view;
function _applyFixedCloseMarket() internal;
function _validatePeriodicCloseMarket() internal view;
function _applyPeriodicCloseMarket() internal;
```

These read/write their policy's authoritative mapping using `msg.sender` as
market. Queue registration already occurs in the coordinator; closure helpers
retain the authentication described above. Reusing a validation primitive does
not imply executing its state effects. In particular, effect helpers require
their corresponding validation to have succeeded in the same callback, with
no untrusted external call inserted between the phases. An override that
skips validation must explicitly supply the necessary authority/preconditions.

### Added rules and three-/four-policy compositions

A test-only recipient-denial feature owns a per-market recipient set and an
administrator API that first checks market registration. It requires transfer
dispatch, overrides `_checkTransfer`, and implements
`_featureTransferRecipientAllowed` using the same recipient rule. It does not
add a global transfer-disable switch. A known lender or wrapper may pass the
default credential check and still fail this independent restriction.

A second test-only feature owns a per-market transfer-amount ceiling. It also
requires transfer dispatch and checks the scaled amount in `_checkTransfer`.
The final composition explicitly calls recipient validation and then the amount
check; the view answers recipient eligibility, excluding amount-specific
failures as its interface already specifies. Both features can keep independent
state/APIs without changing the shared base or term implementation.

Fixed or periodic term plus those two features is a three-policy composition.
A fourth test-only APR-floor feature uses `_checkAprChange` on both execution
routes and its own per-market bound. It validates initial terms at binding,
checks proposed/effective APR changes as applicable, and explicitly permits
fully funded closure's APR-zero transition. Because the execution bound can
change, checking only proposal creation is insufficient. The final overrides
declare all applicable helpers/order and callbacks; adding this fourth policy
does not require editing the first three components.

Meaningful M4 assertions must include overlapping transfer rejection, wrapper/
known-lender exemptions failing the new rule, empty-data pending execution,
actual returned rates, state/events, rollback, and multiple markets sharing
one instance. A compile-only inheritance probe is not this proof.

### Deliberate default replacement

A test-only APR strategy can replace `_applyDefaultAprUpdate` with a bounded
APR change that preserves the current reserve ratio and never creates temporary
reserve state. Its override uses the existing bounds helper, returns the selected
pair, and deliberately skips the original calculation. This is a demonstration
policy, not a proposed product/economic change.

Open uses the replacement directly. Fixed still invokes its maturity guard
before the virtual default calculation. Periodic increase/equality still retain
their existing proposal-cancellation/retention rules before using the replacement;
periodic reductions continue to select the proposal strategy and bypass that
default on both routes. All effective APR changes still reach the common added
checks. A feature intending to replace periodic notice semantics must additionally
integrate its proposal APIs, both execution routes, and closure; overriding the
shared calculation alone does not do so.

M4 must verify the replacement's return values, absence of temporary-reserve
storage/events, retained term rejection, unchanged lender rules, appropriate
proposal effects, and rollback when an additional validator rejects. The
feature is selected at compilation/new deployment, so this demonstration does
not need to migrate temporary state from an older deployed policy.

## M2 handoff

M2's outcome is one maintained implementation of shared behavior adopted by all
three current templates. Write its task plan/tracker after M1 review; this
handoff is not authorization to start the next milestone in this session.

| Expected area | M2 work |
| --- | --- |
| `src/access/BaseHooks.sol` | Add adapters, common callback coordination/defaults/checks, common registration/access flags, minimum management, transfer views, and empty callbacks using the signatures above. |
| `src/access/MarketConstraintHooks.sol` | Extract the existing APR body into the virtual internal default strategy; let shared coordination select it and validate effective results. Keep one bounds/temporary-state implementation. |
| `src/access/{Open,Fixed,Periodic}TermHooks.sol` | Adopt shared behavior, implement packed adapters, and keep per-template decode/public formats. Fixed/periodic term code may stay here as the single implementation until its M3 extraction. Wire both periodic rate routes to the shared effective check now. |
| `src/access/BaseAccessControls.sol` | Reuse credential/admin/provider logic. Make only narrowly necessary internal-interface adjustments; preserve state and caller assumptions. |
| `src/access/types/` | Move/re-export public structs only when needed to avoid policy/concrete import cycles; this can accompany M3's term extraction. |
| `test/access/`, `test/shared/` | Move equivalent assertions into one owning concrete runtime-matrix suite/helpers; remove the superseded copied assertions. Keep distinct term/proposal cases in their domain suites. Update error/event owner imports mechanically. No inherited test entrypoints or legacy parity oracle. |
| Existing integration/factory/lens/wrapper suites | Run against the real artifacts/factory paths; preserve typed public imports and callback ABI. Add a small independent validator probe to catch an unusable extension seam early. |

M2 should validate each coherent change with the affected canonical suites,
then satisfy the required commands at its completion. Compare raw/semantic
ABIs using the narrow naming allowance above, and inspect the M1 gas scenarios
and both deployment size boundaries. Watch adapter decoding, extra warm reads,
creation packing/writes, and periodic stored-initcode growth. Do not make
unrelated economic, caller-authentication, or configuration changes to make a
refactor test pass.

M3 extracts the term components and management APIs without leaving the old
copies. M4 provides the executable multi-policy/default-replacement proofs.
M5 performs final compatibility/performance/deployment qualification and
maintained integration documentation. Tranching policy, runtime modules,
deployment publication, and changes to core accounting remain separate work.

## M1 evidence review

Identity, effective settings, ABI/format inventory, required test receipts,
size budgets, and operation measurements are in the baseline record with
relative artifact locations and hashes. The later explicit Foundry pins have
an equality receipt showing no effective settings change. Compiler probes
resolve the packing, source-type export, and signature/inheritance questions;
they are labeled separately from runtime tests.

No baseline test failed, no production/test Solidity changed, and no open
design decision prevents M2 from starting after review. Final refactor gas,
size, parity, and composition behavior are still implementation acceptance
requirements, not evidence claimed by M1.
