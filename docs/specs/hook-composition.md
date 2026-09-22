# Shared hook foundation and policy composition

- Status: scope and composition approach agreed; M1 complete, reviewed, and
  pushed. M2 plan/tracker prepared; refactor implementation has not started.
- Date: 2026-09-22.
- Source baseline: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`.

## Purpose

Refactor `OpenTermHooks`, `FixedTermHooks`, and `PeriodicTermHooks` around shared
default behavior and reusable term policies. A new feature should be able to
add restrictions, replace selected defaults, and introduce its own state and
functions without copying the existing hook implementations.

Tranching is one motivating future feature. The foundation must support other
features on the same terms: its extension points describe market actions and
policy decisions, without hard-coding a feature family or reserving special
slots for named features. This specification does not select a tranche policy
interface or implementation.

This document records the agreed scope, composition approach, compatibility
boundary, and acceptance criteria. The [milestones](hook-refactor-milestones.md)
define the sequence. M1's [design](hook-refactor-m1-design.md) selects concrete
internal signatures, ownership, storage adapters, and metadata; its
[baseline](hook-refactor-m1-baseline.md) records existing behavior and measurements.
The [M1 plan](hook-refactor-m1-plan.md) and [tracker](hook-refactor-m1-tracker.md)
record completion. The [M2 plan](hook-refactor-m2-plan.md) and
[tracker](hook-refactor-m2-tracker.md) define the shared-behavior implementation
work. Requirements describe the eventual refactor; its runtime acceptance
evidence remains to be produced during implementation.

## Scope

The refactor covers:

- A shared implementation of the common behavior in the three existing hooks.
- Deliberate internal extension points for additional rules and replacement
  policies.
- Reusable fixed and periodic term behavior, including their management APIs.
- Existing concrete templates that retain their public interfaces and behavior.
- Tests demonstrating compatibility and composition with multiple independent
  features, including features that affect the same action.
- Documentation of the extension contract and its limitations.

The following are separate work:

- Tranche tokens, senior/junior accounting, waterfalls, and tranche managers.
- Repayment dates, penalty/default transitions, or changes to market closure.
- New market accounting observations, checkpoints, callbacks, or factory types.
- Runtime installation, removal, or replacement of feature modules; hook
  forwarding chains; `delegatecall` composition; additional market hook slots.
- Borrower-account contracts or changes to account delegation, role providers,
  borrower transfers, or hook-administrator transfers.
- Selecting one configurable tranching template versus multiple concrete
  templates, implementing either packaging, or migrating existing deployments.

The refactor alone does not establish that V2.5 markets expose everything a
future tranching implementation needs. That compatibility assessment remains a
separate concern. In particular, existing callbacks are not a complete feed of
market accounting changes.

## Current implementation

The three templates already share
[`BaseAccessControls`](../../src/access/BaseAccessControls.sol) and
[`MarketConstraintHooks`](../../src/access/MarketConstraintHooks.sol). Those
provide credential machinery, administration, creation bounds, and the default
APR/reserve policy.

The concrete templates still repeat substantial deposit, transfer, registration,
minimum-deposit, and query behavior. Many callback bodies are not overridable.
Term behavior is interleaved with those bodies and reaches beyond withdrawal
queueing into closure and APR changes.

A hook instance can serve multiple markets. Provider configuration, credential
caches, and local deposit blocks belong to the instance. Market access settings,
known-lender status, schedules, and pending APR proposals are market-specific.
That distinction must survive the refactor.

Each market stores one immutable hook address and callback flags. The factory
calls `onCreateMarket` before deploying code at the future market address. At
runtime the market calls its hook directly, so `msg.sender` is the market.

These boundaries are described in [Hooks](../integrations/hooks.md) and
[Access control](../integrations/access-control.md).

### Behavior and override map

The [source-based behavior map](hook-behavior-map.md) identifies where the
existing templates share implementations, add checks, replace behavior, or
coordinate state across entrypoints. Eight of the eleven ordinary callbacks
have uniform bodies across the three templates, including six no-ops. The
specialized callbacks are withdrawal queueing, closure, and APR/reserve updates.

Periodic APR reductions are the existing return-value strategy replacement:
they deliberately bypass the shared temporary-reserve implementation. Further
developer judgment is needed for closure/proposal state, configuration and
dispatch, access exemptions, and public integration promises. These are
explicit override and integration responsibilities; this specification does
not promise automatic compatibility of feature combinations.

Ownership/capability bitflags remain an option to evaluate, not a requirement.
The mapping informs deliberate extension boundaries and developer-written
integration; selecting a general compatibility mechanism is not a prerequisite
for the refactor.

## Architecture

Composition takes place in Solidity source and produces one deployed hook
contract. The agreed approach is shared implementations with deliberate internal
override points and explicit integration code in the concrete template.

Developer-written overrides are an expected part of extending a hook. They may
add checks, select an existing behavior, or intentionally replace a default.
The developer is responsible for the combined semantics, including ordering,
state changes, related entrypoints, and public integration promises. A correct
override may deliberately skip a shared implementation; it must not copy that
implementation merely to customize one part of it.

The refactor must make these choices understandable and testable. It does not
need a generic conflict resolver, constraint-combination framework, or mandatory
capability/ownership bitmask. Optional metadata could help detect particular
mistakes if a concrete need emerges, but it cannot establish compatibility by
itself. Solidity inheritance resolution likewise does not establish that two
behaviors are semantically compatible.

The initial concrete templates are conceptually:

```text
OpenTermHooks     = BaseHooks
FixedTermHooks    = BaseHooks + FixedTermPolicy
PeriodicTermHooks = BaseHooks + PeriodicTermPolicy
```

Open term is the default absence of an additional withdrawal schedule. A
separate open-term policy contract is unnecessary unless implementation evidence
shows that it improves the design.

| Component | Responsibility |
| --- | --- |
| Shared base | Common registration and access behavior, minimum deposits, transfer rules, callback coordination, and default constraints, reusing or reorganizing existing implementations as appropriate. |
| Fixed term policy | Maturity, term reduction, early closure, and APR restrictions associated with the fixed term. |
| Periodic term policy | Withdrawal windows, closure, APR proposal state, notice windows, and proposal execution. |
| Concrete template | Template identity, existing configuration decoding and public views, and explicit integration of its selected policies. |
| Future feature policy | Feature-specific validation, state, events, management/query functions, and any explicitly required external interaction. |

Reusable policies should be source components, preferably abstract contracts
with narrowly defined internal interfaces. Small stateless calculations may
remain internal library functions. This does not introduce independently
deployed policy contracts or a general plugin registry.

`BaseAccessControls` and `MarketConstraintHooks` are candidates for reuse, not
fixed architectural boundaries. They may be changed, split, reorganized, or
replaced when that gives the shared behavior a better home. The compatibility
requirements below constrain the existing templates' observable behavior,
rather than the names or inheritance structure of their internal components.

Each shared behavior must have one maintained implementation. The completed
refactor must not retain parallel old and new implementations of the same
credential, constraint, or callback logic. Compatibility adapters may preserve
public interfaces by calling shared logic. Compiling that logic into several
templates is expected and does not constitute separately maintained source.

### Policies and action interfaces

A policy is a reusable component for a behavior. An extension point is a
defined place in an action's processing where that behavior can participate.
These do not have a one-to-one relationship:

- One policy may participate in several actions. A periodic term policy affects
  withdrawal queueing, closure, and APR updates.
- Several policies may participate in one action. A transfer may have access,
  recipient-exposure, and transfer-lock rules at the same time.
- A concrete hook may combine three, four, or more policies. The architecture
  must not impose a fixed number of feature slots or require a new base-class
  branch for every additional policy.

Interfaces are bounded by the action context and supported operation: what
information is available, when validation or state changes happen, and whether
the policy can reject an action or help determine a returned value. They do not
limit the number of components that can participate at that point. A component
need only implement its relevant behavior; this does not require every policy
to implement a second copy of the full market callback interface.

For example, a future hook could combine periodic terms, per-lender exposure
limits, a transfer lock, and custom APR bounds. This is an illustration of
composition, not a commitment to implement those features:

| Illustrative policy | Actions it would affect |
| --- | --- |
| Periodic terms | Queue withdrawal, close, and change APR. |
| Per-lender exposure limit | Deposit and transfer to a recipient. |
| Transfer lock | Transfer. |
| Custom APR bounds | Both supported APR update paths. |

These components share the existing base behavior. The final template supplies
the integration code that calls the applicable policies for each action.
Adding a policy may change that integration code and the new policy's
configuration; it should not require editing unrelated reusable components.

This is extensibility when developing and deploying a hook. It does not install
new behavior into an existing deployed hook. Code size, execution cost, and
interactions between selected policies constrain practical combinations; a
hard-coded policy count does not.

### Shared callbacks and extension points

External callbacks should coordinate the action through internal functions with
documented inputs, ordering, and responsibilities. Selected internal functions
are overridable; making every function `virtual` is not the extension design.

The interface must distinguish:

1. **Additional validation:** add a condition while retaining the selected
   default and term rules. All applicable conditions must pass.
2. **Default replacement:** deliberately replace a designated policy, such as
   how an action's access requirement is evaluated. Replacement must not require
   replacing unrelated caller checks or state handling.
3. **Feature state and APIs:** maintain additional state and expose bespoke
   management/query functions without adding feature-specific fields or
   selectors to the shared base.

The callback coordinator should retain common dispatch and bookkeeping. Policy
interfaces must say which layer authenticates the caller, reads/writes state,
validates credentials, and emits events. New policy code must not accidentally
validate credentials or update shared state twice through inheritance.

Existing callbacks have different caller checks, including callbacks that are
currently no-ops. Compatibility includes those differences: the refactor must
not silently make every callback reject unknown callers. A shared authentication
helper should support extensions that add stateful behavior. Such extensions
must authenticate the market before treating `msg.sender` as a registered
market or writing its feature state. Creation retains its distinct factory
authentication and must not require code at the future market address.

A default policy's early return must not skip additional feature checks. For
example, a known recipient or canonical wrapper can bypass credential checks
under the current transfer policy; that exemption must not automatically bypass
an unrelated restriction added by a future feature.

Any feature bookkeeping during a callback runs at the existing market callback
boundary. An internal function called after default validation still runs before
the market's subsequent action accounting. It is not a new post-action observer.
Reverts must roll back shared and feature state together.

### Combining policies

Each concrete composition must make rule ordering and interactions explicit.
Inheritance order or a chain of `super` calls is insufficient documentation of
the intended behavior. Integration overrides may call reusable policy helpers
in a declared order; they should not copy those helpers' implementations.

Multiple additional validators can coexist: every applicable validator must
accept the action. When behaviors calculate values or modify shared state, the
developer must explicitly select the implementation or write the integration
that gives their combined behavior. Two replacements for the same default must
not silently compete through inheritance. Stateful effects likewise need
declared ownership and ordering. These rules apply regardless of policy count;
they do not require a general algorithm for reconciling arbitrary policies.

Some policies are alternatives or have incompatible requirements. The concrete
template must select between them or deliberately define their combined
behavior. The foundation does not promise that arbitrary feature combinations
are valid; review and tests cover the combinations actually provided.

For withdrawal queueing, fixed/periodic schedule checks and the configured
access requirement must both remain effective. A future additional rule must
coexist with them. The existing templates retain their current validation order
and externally observable failure behavior.

APR updates require explicit selection of the calculation and associated state
effects. In the current hooks, periodic reductions replace the shared strategy;
fixed terms add a guard before it. A developer-written override can express
that choice. This does not require a generic resolver for every combination.
Additional validators must see the effective values that will be applied by
the market. There must be no implicit rule that the last policy's returned
values override all earlier policies, or that discarded return values undo a
previous policy's state changes. A feature that changes returned values
requires explicit integration within the market interface's actual abilities.

Periodic APR reductions have two execution paths:

- `onSetAnnualInterestAndReserveRatioBips` for borrower-initiated updates.
- `executePendingAnnualInterestBipsReduction` for the separate market-mediated
  permissionless execution path.

Both paths must reach the same applicable extension validation for an effective
APR change. The second path keeps its existing ABI and has no credential-data
argument. Proposal execution, cancellation, and events remain owned by the
periodic policy. The refactor must not apply the open/fixed temporary-reserve
rule to a periodic reduction that currently preserves the reserve ratio.

The dedicated periodic market path accepts only an APR from the hook and keeps
the current reserve ratio itself. A different reserve calculation cannot be
applied on that path solely by overriding the hook. Creation and closure also
need separate treatment for features constraining rates: closure sets APR to
zero and reserves to 100% after `onCloseMarket`, without invoking the APR hook.
The feature must define whether and how its rules apply to those transitions.

### Responsibilities of an override

For a behavior-changing override or composition, the code documentation and
corresponding tests must establish:

- Which defaults are retained, replaced, or skipped, and why. Calling a default
  and discarding its return value does not discard its state changes or events.
- Which related entrypoints are covered and which are intentionally treated
  differently. Depending on the feature, this includes ordinary callbacks,
  alternate execution routes, creation, closure, management functions, and
  public queries.
- Who updates shared state, in what order, and how exemptions apply. Additional
  rules must not disappear behind another policy's early return, and a rejected
  action must leave no committed partial feature or shared-state changes.
- How callback activation, access settings, data encoding, and existing public
  integration promises remain consistent with the selected behavior.

Brief comments at the override and focused behavioral tests are sufficient;
this does not require a separate compatibility registry or a new approval
process. The tests must verify meaningful returned values, state transitions,
events, and rejection behavior where relevant, rather than only demonstrating
that the selected contracts compile together.

The existing periodic APR reduction illustrates the intended discretion: it
skips the shared temporary-reserve implementation, executes its proposal state
transition, and preserves the current reserve ratio. Closure and the second
APR execution path remain part of that behavior's integration responsibilities.

### Creation, flags, and configuration

Templates retain their existing constructor and market-creation encodings.
Template-specific decoding should feed shared registration/access logic and
term-specific initialization. Optional words, defaults, numeric widths, and
validation behavior must be preserved.

The composition must distinguish requested access requirements from enabled
callbacks. Enabling a callback for a schedule, minimum deposit, or other feature
does not itself mean that the action requires a credential.

The existing flag rules remain intact:

- Open term requires the ordinary APR callback and optionally supports deposit,
  transfer, and withdrawal-queue callbacks.
- Fixed term additionally requires withdrawal-queue and closure callbacks.
- Periodic term additionally requires its pending-APR execution callback.
- A positive initial minimum enables deposits' callback; disabled transfers
  enable transfers' callback.
- Requested withdrawal access requires deposit access and either transfer
  access or disabled transfers, and enables the supporting callbacks.
- A market whose deposit callback was not enabled cannot later acquire a
  positive minimum deposit through the hook setter.

An extension must declare the callbacks it needs when its template and market
binding are created. An inherited no-op implementation is not sufficient to
activate an otherwise disabled callback. Required flags must not be lost when
policies are combined, and unused callbacks must not be enabled as an incidental
effect of the refactor.

Existing callback `extraData` continues to follow the current credential
encoding. This specification does not introduce a universal multi-feature data
envelope. A future feature requiring additional data must define its encoding
and integration explicitly; policies cannot independently assume ownership of
the same bytes.

### State and public views

Each piece of state must have one owning component. Shared state must be
accessible through deliberate internal interfaces, without divergent copies
maintained by different policies. Market-specific state must remain isolated
when an instance serves several markets.

The current `HookedMarket` return structs differ by template. They are public
integration formats, not a requirement to use three unrelated implementations
of shared behavior. Internal storage may be reorganized for new deployments,
with adapters preserving those formats.

The periodic configuration currently fits in one storage slot. Storage design
must evaluate packing and callback costs before replacing it with multiple
common and feature mappings. The goal is maintainability with understood costs,
not deduplication at any gas cost.

No existing hook instance is upgraded or has its storage migrated by this work.
The internal layout is therefore not a proxy storage-compatibility requirement.

## Compatibility requirements

The three existing templates must retain the following behavior and interfaces.
Any intentional exception is a separately identified behavioral change, not an
incidental consequence of moving code.

| Surface | Requirement |
| --- | --- |
| Market callbacks | Preserve selectors, arguments, return encodings, flags, market caller context, and intermediate-state semantics. |
| Creation | Preserve constructor inputs, per-template `hooksData` formats, factory/administrator checks, registration behavior, and validation of supported and malformed inputs. |
| Public configuration | Preserve `getHookedMarket(s)` tuple shapes, source-level exported configuration types where used by this repository, getters, setter selectors, and accepted numeric ranges. |
| Template identity | Preserve the family strings `OpenTermHooks`, `FixedTermHooks`, and `PeriodicTermHooks`; lenses classify these exact values. Implementation revision metadata is a separate review choice below. |
| Events and errors | Preserve signatures, indexed fields, payloads, successful event ordering, and observable revert behavior for existing templates. |
| Access and administration | Preserve provider/cache behavior, known-lender rules, local blocks, wrapper handling, transfer-policy views, and administrator-transfer authority and factory indexing. |
| Integrations | Preserve supported factory deployment paths, standard/revolving market behavior, lens decoding, wrapper integration, and borrower-account caller semantics. |

Specific boundaries that must be retained include:

- Deposits compare the tender and minimum in scaled units with the existing
  flooring. Successful credential validation can mark a lender known even when
  credentials are optional for that action.
- Known-lender status is market-specific and persists across credential expiry,
  revocation, provider removal, and local deposit blocks. Existing transfer and
  withdrawal exemptions remain as specified in the access-control documentation.
- Periodic minimum deposits remain bounded by `uint96`, while the setter retains
  its `uint128` signature. Open/fixed minimum deposits retain their `uint128`
  range. Periodic pending-proposal compatibility getters keep their tuple shapes.
- Fixed maturity permits queueing at and after the maturity timestamp. It does
  not close the market, stop deposits/borrowing, change the hook address, or
  establish a repayment deadline. Term-reduction and early-closure permissions
  retain their existing semantics.
- Periodic windows retain their start-inclusive/end-exclusive boundaries and
  closed-market behavior. APR proposals retain their fixed response windows,
  readiness/expiry bounds, exact-rate matching, cancellation behavior, and
  requirement that scaled pending withdrawals be paid before execution.
- Open/fixed APR changes retain the shared bounds and temporary-reserve policy.
  Periodic increases and unchanged APRs retain their existing shared-policy
  behavior; periodic reductions retain their distinct proposal policy.
- Withdrawal batches remain owned by the underlying market. Hooks gate queueing
  under the existing rules; executing an already queued withdrawal remains
  ungated by these templates. Quarantine continues through the ordinary queue
  callback and its term/access checks.

This work targets the hook implementation layer. It requires no change to the
market callback ABI, `MarketState` layout, withdrawal accounting, or factory
authorization/deployment behavior. Mechanical import or harness adjustments do
not authorize changes to those contracts' behavior.

Refactored templates have new bytecode. Initcode hashes and deployment addresses
derived from changed initcode must be treated as new identities, even when the
public ABI and behavior match. Existing deployment inventories must not be
rewritten to describe the new implementation as already deployed.

## Relationship to future features

The general source composition is:

```text
CustomHook = shared defaults
           + selected term behavior
           + feature policy A
           + feature policy B
           + further applicable policies
```

Tranching may eventually be one of these features; its eventual implementation
may itself comprise several components. Neither its component boundaries nor
the number of templates exposing it is fixed here. A configurable template
would require explicit selection, initialization, and dispatch for the
combinations it supports.

The extension promise is that a new composition can reuse existing components
without editing their implementations for every new feature. Existing deployed
hooks do not gain that feature automatically. Features requiring information or
transitions absent from the market interface may need separate core work.

The base must not contain a list of future feature kinds or tranching-specific
branches. Feature-specific state and APIs stay with the feature. Exact tranche
repayment dates, penalty/default rules, and economic constraints remain outside
this specification.

## Acceptance criteria

Acceptance evidence for the eventual implementation must establish:

1. Common behavior has one maintained implementation, and fixed/periodic rules
   are reusable without copying the concrete template bodies. Reorganized or
   replaced shared contracts leave no parallel production implementation of
   the same functionality.
2. Existing access, schedule, APR, closure, creation, and authority behavior
   remains covered across the three templates. Common properties use runtime
   matrices where appropriate; distinct term behavior keeps its owning tests.
3. Small independent test-only features can add validation and their own
   state/APIs to open, fixed, and periodic compositions without modifying the
   base or term policy implementations. At least two additional features must
   work together with a term policy, including overlapping checks on the same
   callback. Extending that composition with another feature must require only
   its new component and integration code, demonstrating three- and four-policy
   compositions. Tests prove existing and additional rules apply, including
   transfer credential exemptions, both periodic APR execution paths, and
   rollback if any additional rule rejects the action. These fixtures must be
   independent of a proposed tranching design.
4. A test extension can intentionally replace a designated default while
   retaining unrelated shared behavior. Its documentation identifies the
   retained/replaced behavior and related entrypoints. Tests exercise observable
   results, including state/events from the selected implementation and the
   absence of effects from a deliberately skipped default; they do not require
   a particular arrangement of internal helper calls. Applicable alternate
   paths and lifecycle interactions must be covered.
5. Tests cover callback activation for an extension, including a callback that
   is normally unused, and isolation between multiple markets on one instance.
   Existing public encodings and template/lens decoding remain compatible.
6. The existing factory, hook dispatch, administrator transfer, wrapper, and
   standard/revolving integration suites continue to pass. Verification follows
   [`TESTS.md`](../../TESTS.md), including default, fixed-seed, and deployment
   profile runs. No parallel legacy implementation or permanent duplicate test
   suite is introduced solely to support the refactor.
7. ABI comparison accounts for inherited functions, events, errors, and tuple
   shapes. Metadata differences are identified explicitly. Code size and
   representative gas costs are compared against the baseline under the same
   compiler and deployment settings.
8. Every concrete template remains deployable through the actual factory path,
   including both deployed runtime size and the `STOP || initcode` storage
   contract used by the template mechanism. Source reuse is not evidence of
   smaller deployed bytecode. Any material size or gas regression needs an
   explicit rationale in implementation review.

Relevant existing evidence lives in the three suites under
[`test/access`](../../test/access/), the shared access/constraint suites, and
[`test/integration`](../../test/integration/),
[`test/factories`](../../test/factories/), and
[`test/lens`](../../test/lens/). These are implementation acceptance requirements;
this draft does not claim they have been satisfied by a refactor.

## M1 implementation decisions

| Choice | Selected design | Review consideration |
| --- | --- | --- |
| Internal state layout | Shared logic uses adapters over the existing packed configurations; one owner per state/event. | Keep periodic's one-slot configuration and measure adapter/callback costs on the implementation. |
| Policy integration API | Separate replaceable defaults/strategy selection from additional action checks; explicitly integrate conflicting policies and related entrypoints. | [Internal contract](hook-refactor-m1-design.md#internal-contract) covers creation, APR routes, closure, management and views; no generic resolver or bitmask is required. |
| Revision metadata | Same family strings; periodic ABI revision remains 2; no new open/fixed revision getters. | New bytecode has a new implementation identity. [ABI comparison rules](hook-refactor-m1-design.md#metadata-and-expected-abi-comparison) permit only documented empty-to-named top-level callback inputs, preserving encoded types and public tuple fields. |

Choosing tranching template packaging, specifying tranching economics, and
designing runtime feature installation are not prerequisites for reviewing this
refactor's scope.
