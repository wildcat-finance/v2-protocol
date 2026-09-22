# V2.5 hook behavior and override map

- Status: source analysis supporting the [hook composition spec](hook-composition.md).
- Source baseline: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`.
- Scope: existing open, fixed, and periodic hooks; hypothetical combinations are
  identified separately. No tranching implementation or ownership-bitmask design
  is selected by this map.

## Findings

Of the eleven ordinary `IHooks` action callbacks:

- `onDeposit` and `onTransfer` have identical bodies across all three templates
  after removing comments and whitespace.
- Six have empty bodies in all three: withdrawal execution, borrowing,
  repayment, quarantine, supply-cap changes, and protocol-fee changes.
- Withdrawal queueing, closure, and APR/reserve updates have specialized bodies.

Creation and the additional periodic APR execution entrypoint are outside that
eleven-callback count. The count describes source reuse, not implementation
complexity: the six empty bodies account for little code, while APR behavior
has substantial state and several entrypoints.

There is one existing family of return-value calculations that is deliberately
replaced: periodic APR reductions bypass the ordinary temporary-reserve policy.
Other specialization mainly adds restrictions, changes hook-owned state, or
adapts configuration and public interfaces.

Discretion is therefore concentrated in identifiable places for today's three
templates. This supports shared implementations with explicit, documented
overrides. It does not establish how often arbitrary future features will
conflict or justify a universal compatibility mechanism.

## Callback map

Sources: [open](../../src/access/OpenTermHooks.sol),
[fixed](../../src/access/FixedTermHooks.sol),
[periodic](../../src/access/PeriodicTermHooks.sol), and
[shared constraints](../../src/access/MarketConstraintHooks.sol).

| Entry point | Open | Fixed | Periodic | Refactor implication |
| --- | --- | --- | --- | --- |
| `onCreateMarket` / `_onCreateMarket` | Common creation bounds, access configuration, minimum, and transfer settings. | Same concerns plus maturity and term permissions. | Same concerns plus window configuration. | Share registration/access logic; retain explicit decoding, initialization, and callback selection for each template. |
| `onDeposit` | Registered-market check, deposit block, scaled minimum, credentials, and known-lender/cache updates. | Same body. | Same body; minimum has a narrower stored range. | One default action implementation. Additional restrictions can use a separate extension point. |
| `onTransfer` | Registered-market check, disabled-transfer rule, recipient exemptions, credentials, and known-lender/cache updates. | Same body. | Same body. | One default action implementation; keep access exemptions local to that policy. |
| `onQueueWithdrawal` | Known-lender or credential check whenever the callback is invoked. | Maturity check, then access check if requested. | Window/closed-state check, then access check if requested. | Separate schedule validation from access validation. Callback activation and access requirements are different inputs. |
| `onExecuteWithdrawal` | Empty. | Empty. | Empty. | Shared no-op; existing queued withdrawals acquire no new term or access gate. |
| `onBorrow` | Empty. | Empty. | Empty. | Shared no-op; a new feature must activate the callback it needs. |
| `onRepay` | Empty. | Empty. | Empty. | Shared no-op with the existing market callback timing. |
| `onCloseMarket` | Empty. | May reject early closure; permitted early closure moves maturity to now. | Marks the schedule closed and cancels a pending APR proposal. | Separate closure permission from feature state changes; deliberate integration is required when several features react to closure. |
| `onNukeFromOrbit` | Empty. | Empty. | Empty. | Shared no-op. The market subsequently uses the ordinary withdrawal queue path, including its term/access checks. |
| `onSetMaxTotalSupply` | Empty. | Empty. | Empty. | Shared no-op. A future rule may accept/reject the proposed cap; this callback cannot rewrite it. |
| `onSetAnnualInterestAndReserveRatioBips` | Delegate to shared constraints. | Reject reductions before maturity, then delegate. | On increase, cancel the proposal and delegate; on equality, delegate; on reduction, execute the proposal and retain the current reserve ratio. | Fixed is an additional guard. Periodic selects a different reduction strategy and adds state effects on increases. |
| `onSetProtocolFeeBips` | Empty. | Empty. | Empty. | Shared no-op; retain the current factory/market dispatch boundary. |
| `executePendingAnnualInterestBipsReduction` | Not exposed. | Not exposed. | Execute the pending reduction through the same proposal helper. | A separate external route must reach applicable rate validation. The market fixes the reserve ratio on this route. |

The identical callback bodies do not imply identical storage layouts or public
tuple encodings. The refactor must preserve those differences through its
chosen internal configuration interface and public adapters.

## Where discretion is already necessary

### APR behavior: guard, delegate, or replace

The shared [APR implementation](../../src/access/MarketConstraintHooks.sol#L196)
returns the proposed APR and chooses the reserve ratio. It ignores the supplied
reserve-ratio argument. Its choice can create, update, cancel, or expire
`temporaryExcessReserveRatio[market]`, with corresponding events.

That result is an exact selected value. Treating it as a minimum that another
module may raise would change current semantics and would also require deciding
how its stored original ratio and expiry should work.

| Case | Selected calculation | Other effects |
| --- | --- | --- |
| Open APR update | Shared APR/reserve implementation. | Shared temporary-reserve state and events. |
| Fixed reduction before maturity | No calculation; reject. | No committed effects. |
| Other fixed APR updates | Shared APR/reserve implementation. | Same shared state and events. |
| Periodic APR increase | Shared APR/reserve implementation. | Cancel any pending proposal before delegation. |
| Periodic unchanged APR | Shared APR/reserve implementation. | Keep the pending proposal and retain delegation to the shared reserve logic. |
| Periodic APR reduction through the ordinary setter | Validate and execute the exact pending proposal; return the current reserve ratio. | Delete the proposal and emit execution. Do not run the shared temporary-reserve implementation. |
| Periodic permissionless execution | Same pending-proposal validation/execution; return APR only. | Same proposal effects. The market itself retains the current reserve ratio. |

Sources: [fixed APR guard](../../src/access/FixedTermHooks.sol#L502),
[periodic execution and dispatch](../../src/access/PeriodicTermHooks.sol#L706),
and [market APR entrypoints](../../src/market/WildcatMarketConfig.sol#L176).

Calling every selected rate implementation in sequence would be incorrect for
the existing periodic reduction. Calling `super` and discarding its returned
ratio would still perform unwanted temporary-reserve state changes and events.
The developer must explicitly select which implementation runs, not only which
return value wins.

The dedicated permissionless market entrypoint imposes a stronger boundary:
its hook returns only an APR, and the market applies the existing reserve ratio.
A feature cannot change that ratio by overriding the hook. It can reject an
incompatible execution, use a differently designed supported path, or require
separate core work. A generic hook-level resolver cannot remove this limitation.

### Proposal state belongs to a lifecycle, not one callback

The periodic proposal has several writers:

| Operation | Proposal effect |
| --- | --- |
| `proposeAnnualInterestBips` | Validate authority, market state, schedule, and strict reduction; store the proposal and fixed response-window bounds. Cancel/replace an older proposal if present. |
| Either successful execution path | Check exact APR, timing, continued strict reduction, and zero scaled pending withdrawals; delete and emit execution. |
| APR increase | Cancel and delete. |
| Market closure | Cancel and delete. |
| Unchanged APR | Retain it. |
| Time passing beyond proposal expiry | Execution becomes invalid; stored proposal remains readable until replaced or cancelled. |

A replacement of the APR calculation is therefore not sufficient to replace
the proposal lifecycle. These operations need coordinated behavior and a
single implementation of their shared rules. A component boundary around the
whole notice/proposal behavior is more useful than ownership of one callback.

Source: [periodic management and queries](../../src/access/PeriodicTermHooks.sol#L349).

### Closure changes the meaning of other operations

[Fixed closure](../../src/access/FixedTermHooks.sol#L465) rejects closure before
maturity unless either early closure or term reduction is allowed. A permitted
early close moves maturity to the closure timestamp and emits `FixedTermUpdated`.
That date is also read by withdrawal queueing and the APR-reduction guard. The
administrator's maturity setter affects those same behaviors.

[Periodic closure](../../src/access/PeriodicTermHooks.sol#L673) marks the schedule
closed, makes withdrawal-window queries open, and cancels the APR proposal. The
queue callback also honors the market snapshot's closed state. A future closure
override must account for those effects, even if it adds only one new permission
check of its own.

There is also a rate-changing route outside the two APR entrypoints:
[market closure](../../src/market/WildcatMarket.sol#L183) funds the debt, calls
`onCloseMarket`, and then sets APR to zero and reserves to 100%. It does not call
the APR hook for those assignments. Final repayment, if needed, invokes the
repayment hook before the closure hook.

A future APR floor or reserve restriction must define its closure semantics.
Extending both APR update routes does not automatically extend closure. Usually
a feature may want different rules for a fully funded closed market, but this
map does not select those rules. Creation likewise has its own initial rate
validation through `_onCreateMarket`.

### Access checks have bookkeeping and integration semantics

Deposit, transfer, and withdrawal access use the shared
[credential implementation](../../src/access/BaseAccessControls.sol#L883).
Successful entry can permanently mark a lender known on that market. Credential
validation can call a provider and update the instance's credential cache; it
is not simply an independent, side-effect-free boolean predicate.

The shared implementation should run once where required. Adding another rule
must not duplicate provider validation, change which action makes a lender
known, or accidentally share market-specific state across markets.

The transfer callback currently skips credential work for known recipients and
returns early for the market's canonical wrapper. A new, unrelated restriction
must still execute for those recipients unless it deliberately grants the same
exemption. An access helper may return early; the combined action must not
accidentally return before other applicable checks.

Transfer policy also has a public integration contract:

- `isMarketTransferDisabled` returning false promises that the hook will not
  later make all market-token transfers disabled.
- `isMarketTransferRecipientAllowed` reports recipient eligibility without hook
  data. It deliberately does not cover balance, allowance, or amount-specific
  failures.

These promises come from
[`IMarketTransferPolicy`](../../src/access/IMarketTransferPolicy.sol). An
extension allowing a later global transfer lock cannot simply inherit the
current false answer to the first query. It needs a compatible integration
design or an explicit decision not to provide that optional policy interface.
An amount-dependent exposure limit, conversely, need not pretend the second
query certifies every possible transfer amount.

Thus even an additional transfer check can require judgment about exemptions
and public views without replacing any numerical calculation.

## Other shared behavior and assembly work

| Area | What is shared | What needs an explicit choice or adapter |
| --- | --- | --- |
| Constructor and administration | Name/provider initialization, administrator checks, two-step administrator transfer, factory indexing, and credential-provider management. | Keep one maintained implementation. A new feature with additional authority relationships must define its own transfer behavior; the existing transfer does not move market or provider ownership. |
| Creation bounds | All three call the shared parameter constraints. | Fixed and periodic add different schedule validation and events. Public creation encodings retain different required/optional words. |
| Callback selection | Required/optional callbacks, requested access settings, and callbacks forced by minimums or transfer settings. | Derive access requirements before enabling callbacks for other reasons. Required queue dispatch for a schedule is not a request for credential-gated withdrawal. Future features must declare and enable the calls they need. |
| Minimum-deposit setter | Open/fixed bodies are identical; all three enforce registration, authority, and enabled deposit dispatch. | Periodic stores `uint96` and checks the downcast from the shared `uint128` setter ABI. Dispatch-enabled state is also stored differently. |
| Queries | Transfer-policy and market-configuration getter bodies are identical across templates. | Returned `HookedMarket` types differ. Specialized schedule/proposal queries remain with the corresponding behavior. |
| Callback data | Current credential data uses a provider address and optional provider payload. | A feature that also needs bytes requires deliberate encoding/decoding integration. Both cannot independently consume the whole suffix. |
| Caller checks | Creation is authenticated by the factory; active lender actions authenticate registered markets. | No-op callbacks have no registered-market check. Open/fixed APR callbacks also lack the explicit check present in periodic APR callbacks. A universal new guard would change existing behavior. |

These are recurring implementation responsibilities when adding features, even
when no two components compete to calculate a value. They are a reason to keep
the final template's integration explicit and small, rather than promise that
inheritance alone assembles a correct feature combination.

## Representative combinations

The first row exists today. The remaining rows are design probes, not selected
features or implementation commitments.

| Combination | Judgment required |
| --- | --- |
| Fixed maturity plus withdrawal access | Already combines cleanly: maturity must permit queueing, then the configured known-lender/credential rule must permit it. Neither rewrites the other's result. |
| Periodic notice plus a new APR floor | The floor can validate the selected APR without replacing the notice machinery. It must cover both execution routes; creation, proposal admission, and closure need explicit decisions. A proposal accepted today may otherwise be unexecutable under an added rule later. |
| Periodic notice plus a new reserve calculation | A true behavior conflict on reductions: the existing strategy preserves reserves and the dedicated market path enforces that. Calling both calculations does not solve it. |
| Existing access plus a per-lender exposure limit | Additional deposit/transfer checks can coexist. Decide how known recipients and wrappers are treated, and retain the limited meaning of recipient-only views. |
| Existing transfer-policy interface plus a mutable global transfer lock | Interface compatibility conflict, even if the lock uses only a simple extra validator. The existing permanent promise cannot be retained unchanged. |

## Refactor implications

The agreed composition approach is recorded in the
[specification](hook-composition.md#architecture): shared implementations,
deliberate override points, and developer-written integration with focused
documentation and tests. It does not require a generic compatibility framework.

The evidence supports the following internal boundaries as candidates. Exact
Solidity signatures and inheritance structure remain open:

- Shared deposit/transfer actions, with access-specific exemptions contained
  inside their helpers and room for additional action validation.
- Withdrawal schedule validation separate from withdrawal access validation.
- A deliberate APR strategy selection point, keeping calculation, related
  state changes, and events together; additional effective-value validation
  must cover both supported update routes.
- Closure permission and feature closure effects, with the effects' links to
  schedule and proposal state documented.
- Shared registration/access initialization fed by template-specific decoding
  and configuration adapters.
- Feature-specific APIs and state, such as periodic proposals, without moving
  every bespoke function into the common base.

Developer-written overrides are appropriate at those boundaries. For an
override, its implementation and tests should make clear which defaults it
retains or skips, which related entrypoints and state it affects, and which
public integration promises still hold. A blind `super` call is not a substitute
for that decision; neither is a mask saying two callbacks differ.

Ownership/capability flags remain an optional design idea. The existing
`HooksConfig` flags control market dispatch and must not be repurposed to claim
feature compatibility. This map does not require a generic constraint solver,
runtime module registry, or exclusive-ownership framework.

## Evidence and verification scope

This is a static mapping against the recorded source baseline. The shared-body
comparison ignores comments and whitespace; it does not assert ABI or storage
identity. Relevant tests were inspected, including:

- [Shared reserve-policy tests](../../test/access/MarketConstraintHooks.t.sol):
  temporary-ratio calculation, update, cancellation, and expiry.
- [Fixed-hook tests](../../test/access/FixedTermHooks.t.sol): maturity/access
  queueing, APR delegation, early closure, and no-op callbacks.
- [Periodic-hook tests](../../test/access/PeriodicTermHooks.t.sol): proposal
  timing, both execution paths, increase/equality handling, and closure effects.

No Solidity implementation changed and the Foundry suites were not rerun for
this documentation change. Future composition tests must establish behavior of
the refactor and its selected combinations; existing tests do not establish
compatibility of hypothetical policies.
