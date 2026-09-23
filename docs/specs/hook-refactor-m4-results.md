# M4 results: extension and composition proof

- Plan: [M4 execution plan](hook-refactor-m4-plan.md).
- Current status: [M4 tracker](hook-refactor-m4-tracker.md).
- Execution starting revision: `579bba16f5204b0a4b815811a527aed61dfb256f`.
- Approved M3 handoff: `eff4d5898a5384b35f16acba23fee2aca47745d0`.
- Raw evidence root: `audits/hook-refactor/m4/2026-09-23/` (ignored).

## M4-01: Handoff identity and proof map

The user approved the M4 plan and instructed execution after reboot. The
starting tree has no tracked changes. All 285 source/test/script/settings
inputs and 897 dependency inputs match the qualified M3 manifest. Four
submodules are clean and unchanged. Foundry 1.8.3 and solc 0.8.25 binary hashes,
effective default/deploy settings, and Node 24.21.0 match the retained setup.
The M3 handoff and M4 planning signatures verify under the configured kethcode
identity and SSH key.

Verified all 55 artifacts and eight retained references bound by the M3-06
review receipt, the committed M3 documentation against its receipt, and the
separate original-test replay's receipts, log, input manifest, and artifact
hashes. Cached production artifacts in both profiles match the retained ABIs,
selectors, creation/runtime bytes, links, and immutable patch positions. No
tests were rerun for unchanged inputs in this checkpoint.

| Retained evidence | Disposition |
| --- | --- |
| M3 default/fixed-seed/deploy runs | Reuse the qualified 719-test / 51-suite passes, including the nine-property invariant campaigns. These are prior runs, not M4 results. |
| Original pre-refactor hook fixtures | Reuse the separate 53-case replay against M3 after only mechanical import/declaration-owner adaptations. No permanent duplicate suite is added. |
| Production ABI/layout/size/gas | Immediate reference is M3; M1 retains the original compatibility contract. Requalify after the open-policy move below. Executable identity may justify retaining gas observations under their original conditions and exclusions. |
| Lint | Starting baseline: 33 untouched Prettier failures, zero Solhint errors, 22 warnings. Format touched Solidity only. |

### Callback configuration correction

`BaseHooks.config` is an immutable public value supplied at construction.
`_configureMarketAccess` first captures requested credential flags, then merges
the optional/required dispatch flags from that value. `_onMarketConfigured`
cannot replace the returned flags. Forcing a bit only in `_initializeMarket`
would leave the public deployment configuration incomplete; requesting transfer
access just to reach the callback would change credential semantics.

Fixed and periodic compositions can already inherit their abstract policies and
supply the `BaseHooks` constructor arguments once. Open compositions currently
inherit `OpenTermHooks`, whose constructor fixes those arguments and flags.
They cannot select a different immutable configuration while reusing its packed
initialization/adapters. This is a concrete gap exposed by M4's required-transfer
and later required-borrow examples.

M4-02 will move open packed state, initialization/decoding, and access adapters
to abstract `OpenTermPolicy`. `OpenTermHooks` will adopt it immediately, keeping
its exact constructor, flags, family identity, and public configuration getters.
Move `HookedMarket` to `types/OpenTermHookTypes.sol` and re-export it from the
existing concrete file, as with the fixed/periodic types. Preserve function
bodies, comments, packing, public imports, and ABI `internalType`. There is no
new open schedule rule and no duplicated open implementation.

Concrete test compositions can then supply their actual deployment configuration
for all three term choices. The first assemblies require transfer dispatch in
addition to each term's existing required flags. The fourth-feature assemblies
will add borrow dispatch. Requested credential flags remain separate. Neither
change enables new callbacks on the original three production templates.

### Feature ownership and ordering

| Component | State, API, and integration choice |
| --- | --- |
| Recipient restriction | One recipient value per market; zero disables that recipient restriction. Reuse the same predicate for transfer rejection and the no-data recipient view. Configuration authenticates the current administrator and registered market. Preserve the existing four recipient-extension properties when adopting the reusable component. |
| Transfer amount limit | Positive maximum scaled amount and accepted scaled volume per market. Configuration/query APIs expose those values. A limit applies to each transfer, not cumulative volume. Volume recording must not eventually create a global transfer lock through overflow. |
| Transfer assembly | Shared default credentials/bookkeeping first, then amount validation/volume effect, then recipient validation. This deliberately makes later recipient rejection exercise rollback of both earlier owners. Both extra checks apply to known recipients and exact registered wrappers. The recipient-only query does not claim to validate amounts. |
| Creation | Initialize feature limits from supplied creation context after the term has registered the market; never read the not-yet-deployed market. Include accepted setup and rejected setup that restores registration, packed configuration, and feature state. Preserve the existing credential-data encoding. |
| Authority | Reuse the existing administrator and market-registration checks; no second administrator or registration mapping. Feature management follows completed administrator transfer, with pending administrators having no authority. |
| Borrow feature, M4-03 | Own its normalized per-action limit and accepted-amount effect. Authenticate the market before state changes, declare required dispatch, and add it without changing the established transfer components or reusable production policies. |
| APR replacement, M4-04 | Replace only `_applyDefaultAprUpdate`, retain explicit bounds, and keep surrounding fixed/periodic strategy selection. Distinguish its result from the skipped default and seed temporary-reserve state to detect accidental default effects. |

If extracting the existing test recipient mock changes its representation or
removes the old assembly, retain its four behavioral cases in the same owning
suite and explain their adaptation. Do not retain a duplicate implementation
just to avoid updating test setup. New concrete assemblies contain integration
code; feature rules stay in their reusable components.

### Proof and test ownership

| Requirement | Owner and evidence to add or retain |
| --- | --- |
| Open extraction, original constructor/config formats, packed adapters | Existing `OpenTermHooksTest` and `BaseHooksTest`; ABI/layout/bytecode comparison plus current lens/factory consumers. No copied open-policy suite. |
| Two overlapping transfer features with each term choice | `HookExtensionsTest`, using a runtime matrix. Preserve its four existing recipient cases, then cover independent and simultaneous failures, error priority, accepted volume/events, and rollback. |
| Multiple markets, public APIs, positive amount bounds, view promises | `HookExtensionsTest`; two registered markets on each instance, unknown-market calls, administrator/pending/successor authority, no-data view versus amount-specific failure, and continuing transfers after recorded volume exceeds one transfer's limit. |
| Creation, requested credentials versus forced dispatch | Existing common creation owners plus composition-specific cases in `HookExtensionsTest`. Prove declared and effective flags agree and omitted transfer access stays ungated. Reject setup after term registration without leaving partial state. |
| Retained deposit, queue schedule, APR and closure behavior | Existing common/term owners; add focused composition checks where they distinguish feature integration from the unchanged production templates. |
| Fourth feature, borrow authentication, downstream rollback | Composition cases in the existing extension owner and real operations in `ProductionMatrixScenariosTest`; mocks/shared helpers have no test entrypoints. |
| Actual composed hook/market deployment and borrow dispatch | `ProductionMatrixScenariosTest`, using standard/revolving factories for each term choice. Reuse its fixture with an explicit custom-template selection if needed. Verify all runtime/stored-initcode/constructor limits. |
| Chosen APR default, absent skipped state/events, effective-value rejection | `AprValidationTest`; retain its five existing properties and add replacement cases. Cover fixed maturity priority, periodic ordinary/dedicated reductions, and unchanged seeded default state. |
| Changed proposal/execution conditions and separate lifecycle paths | Existing fixed/periodic and APR owners for their distinct callback properties; production matrix for actual returned APR/reserves, closure reset, and continuing withdrawal batching. |
| Wrappers, authority, borrower-account and lens compatibility | Retain the existing real integration suites; run affected cases after the production policy move. No external SDK/app/subgraph qualification is claimed. |
| No hidden test weakening | Reconcile old/new case ownership and assertions at each checkpoint. No inherited test functions, removed legacy assertions without explanation, or internal-call counters standing in for behavior. |

### Measurements and verification boundaries

| Artifact | M3 runtime / creation bytes | Stored-initcode headroom |
| --- | ---: | ---: |
| Open production hook | 15,653 / 18,379 | 6,196 |
| Fixed production hook | 17,014 / 19,741 | 4,834 |
| Periodic production hook | 19,949 / 22,676 | 1,899 |

M4-02 compares the moved open implementation and all three production
artifacts to M3, including raw ABI, normalized layout, executable bytes, link
references, and immutable patch positions. Reuse prior gas only if those
execution conditions remain identical; otherwise measure affected paths.
Existing creation/minimum/query and management receipts supplement the original
97 callback observations, with all prior exclusions retained.

Measure new concrete compositions separately. Start with construction and
`STOP || initcode` size/storage checks in M4-02, then the full six-cell real
factory deployment/operation matrix in M4-03. Adding small source components is
not evidence that their combined deployed bytecode fits. Do not raise code-size
limits or drop periodic coverage to hide a failure.

Collect representative accepted/rejected transfer and later borrow/APR costs
from the owning scenarios with fixed inputs/state, Foundry call isolation, and
explicit direct versus market-nested boundaries. Production preservation and
the cost of an intentionally selected extra rule are separate comparisons.
Run focused checks in both profiles after changes; the three required full
runs and lint reconciliation remain M4-06.

### M4-01 evidence identities

Paths below are relative to the ignored M4 evidence root.

| File | SHA-256 |
| --- | --- |
| `identity-start.json` | `b4789ee8db8459e9ef2aa95941712b5b6da760d7a6c53caea4b6adb8d3dd423c` |
| `inputs-start.sha256.json` | `5f97d472a8d3ddb9ee0b39ee83cb788e4e25065ba21fee866ec2ff323c4c3ee5` |
| `retained-evidence.sha256.json` | `2a13de3ebd7c7487c56fdd90989e9360a2407b4e1df4254f14191d964c0d2691` |

M4-01 is complete as a documentation/evidence checkpoint. M4-02 follows with
the demonstrated open configuration correction and the first composed features,
subject to staged Solidity review before commit.
