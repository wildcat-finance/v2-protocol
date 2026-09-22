# M1 design: shared hooks and explicit policy integration

- Status: storage/component decision complete; internal API and metadata decisions
  follow in M1-05/M1-06.
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
