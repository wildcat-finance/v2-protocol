# M4 results: extension and composition proof

- Plan: [M4 execution plan](hook-refactor-m4-plan.md).
- Current status: [M4 tracker](hook-refactor-m4-tracker.md).
- Execution starting revision: `579bba16f5204b0a4b815811a527aed61dfb256f`.
- Approved M3 handoff: `eff4d5898a5384b35f16acba23fee2aca47745d0`.
- Raw evidence roots: `audits/hook-refactor/m4/2026-09-23/` for M4-01 through
  M4-03 and `audits/hook-refactor/m4/2026-09-24/` for M4-04 through M4-06 (ignored).

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

## M4-02: Three-policy checks and feature state

### Open configuration and ownership

Extracted `OpenTermPolicy` and `types/OpenTermHookTypes.sol`; the existing
`OpenTermHooks` adopts them immediately. Of the original 12 contract members,
eight now belong to the abstract policy and four remain in the concrete hook
(constructor, identity, and two public configuration adapters). Every original
member's signature/body tokens, the global struct, and all original comment
lines are preserved. The struct remains importable from `OpenTermHooks.sol`.

This gives open compositions the same constructor arrangement as fixed and
periodic: the concrete hook supplies `BaseHooks` flags once, while reusing the
authoritative packed configuration and its adapters. Shared access/constraint
code and both other term policies/concrete hooks are unchanged. No production
callback, public API, or market flow is added by this correction.

### Independent features and explicit integration

`test/mocks/TransferFeaturePolicies.sol` owns the two test rules:

- `RecipientRestrictionPolicy`: one restricted recipient per market, with an
  administrator-managed setter and public query. Zero clears that restriction.
  One predicate serves both transfer validation and recipient eligibility.
- `TransferAmountPolicy`: a positive maximum scaled amount per transfer and
  accepted scaled volume per market. The volume saturates at `uint256.max`;
  neither reaching the per-transfer limit cumulatively nor arithmetic overflow
  can turn this observational total into a global transfer lock.

Their shared `FeatureAuthority` declares an authorization adapter, with no new
administrator or registration state. Each composition implements it using
`onlyAdministrator` and `_requireHookedMarket`. `TransferFeatures` selects the
order explicitly: record an allowed amount, then check the recipient. A later
recipient rejection rolls back that write and the preceding default credential
effects. There is no inheritance-order decision between these rules.

`test/mocks/TransferFeatureHooks.sol` binds that integration to open, fixed, and
periodic behavior. The abstract assemblies leave their callback bindings virtual
for the next composition; concrete hooks select constructor flags and their own
test-only identities. Thin configuration getters read the term-owned state.
They force transfer dispatch without forcing transfer credentials and retain
each term's other callback flags. Borrow dispatch is still absent.

During creation, the probe uses `maxTotalSupply` as its initial scaled transfer
limit, while the initial market scale factor is `RAY`. Setup uses callback
inputs after term registration and reads no undeployed-market getters. A zero
initial limit rejects setup and restores the preceding registration/configuration
effects. This is a test-feature choice, not a new production creation rule.

Removed the old immutable, open-only `RecipientRestrictionHooks` mock. Its four
cases now use the reusable recipient component alongside the amount component
across all three term choices. All 25 original assertion/revert expressions
remain, with only the error declaration's owner qualification changed. There
is one maintained recipient rule and no inherited test entrypoints.

### Behavioral evidence and verification

The existing `HookExtensionsTest` now owns 14 properties: its four retained
recipient cases, expanded to the runtime matrix, and ten new composition cases.
The added coverage verifies:

- Declared/effective callback flags and ungated entry when transfer credentials
  were omitted, including setup before the market has code.
- Rejected creation followed by successful creation at the same market address.
- Below/at/above amount bounds, successful volume events, volume beyond a
  single-transfer limit, and saturation without disabling transfers.
- Independent recipient/amount failures, explicit priority when both reject,
  and rollback of default credentials, known-lender state, and feature effects.
- Both rules still applying after known-recipient and registered-wrapper
  credential exemptions, with the recipient view retaining its narrower promise.
- Administrator/registration checks, pending and completed administrator
  transfer, management events/queries, and isolation of multiple markets.
- Retained minimum-deposit, withdrawal-access/schedule, fixed APR guard,
  closure, and globally disabled-transfer behavior in the compositions.
- Actual deployment of each composed runtime and its `STOP || initcode`
  storage contract, with explicit runtime/storage/constructor size bounds.

Final focused default and deploy runs each pass **339 tests across 18 suites**,
with 1,000 fuzz iterations and seed `0x5eed`. They include common/access/APR/
term suites and factory, dispatch, lens, administrator transfer, borrower-account,
wrapper, standard/revolving production matrix, and market tests. Discovery
matches the prior 329-case selection plus these ten additions. The complete
source inventory remains 51 owning suites with 737 entrypoints; the three full
canonical runs and invariant campaigns remain M4-06.

All six touched Solidity files pass Prettier. Full lint and standalone Solhint
logs match M3 exactly: 33 untouched formatting failures, zero Solhint errors,
and 22 existing warnings. An initial test-harness stack-depth failure was
resolved by using the existing `LibStoredInitCodeExternal` wrapper for the
deployment assertion; no production assembly or compiler setting changed.
Long new imports were split to remove their lint warnings before final checks.

### Compatibility, deployment sizes, and costs

Both profiles retain all three production raw ABIs, selectors, creation/runtime
bytes, link references, and immutable patch positions. Normalized layouts match
M1 and M3 with 11 entries each and no slot changes. Comparison to M1 permits
only the already-approved callback-input names from M2. Fresh artifact metadata
matches current source hashes, including the moved open implementation.

Production runtime/creation sizes remain 15,653/18,379 bytes for open,
17,014/19,741 for fixed, and 19,949/22,676 for periodic. The qualified production
gas observations remain applicable under their original state, inputs, tool
settings, isolation, and measurement boundaries: 97 callback, 70 creation/
minimum/query, and 14 management observations. This is retained evidence with
zero executable/cost delta from M3, not fresh production gas measurement; all
previous exclusions remain.

| Test composition | Runtime bytes | Creation bytes | Stored initcode bytes | Stored headroom | Creation with empty `args` |
| --- | ---: | ---: | ---: | ---: | ---: |
| `OpenTransferHooks` | 16,480 | 19,207 | 19,208 | 5,368 | 19,303 |
| `FixedTransferHooks` | 17,838 | 20,565 | 20,566 | 4,010 | 20,661 |
| `PeriodicTransferHooks` | 20,730 | 23,457 | 23,458 | 1,118 | 23,553 |

The composed ABIs and executable bytes match between profiles. These artifacts
fit the 24,576-byte runtime/storage and 49,152-byte constructor limits. Source
reuse does not eliminate feature bytecode cost; periodic's remaining 1,118
bytes are the concrete budget for M4-03's fourth-feature example.

Two existing scenarios supply 15 new direct transfer-callback observations.
Representative trace-reported gas is shown below; complete inputs/outcomes are
in the raw summary. Calls use Foundry isolation, fixed timestamp/seed, caller
`MarketA`, initial limit 100, and a zeroed intermediate state. These are probe
callback costs, not complete market-transfer estimates or production deltas.

| Composition | Rejected for missing credentials | Accepted credential entry, amount 1 | Recipient rejection after entry/volume processing, amount 1 |
| --- | ---: | ---: | ---: |
| Open | 45,891 | 119,649 | 102,556 |
| Fixed | 45,853 | 119,611 | 102,518 |
| Periodic | 46,088 | 119,846 | 102,753 |

The other six observations cover amount rejection before recipient validation
and recipient rejection after an at-limit amount write. Actual factory-created
composed markets, borrowed-asset effects, and the fourth feature remain M4-03.
Default replacement and the remaining alternate-route/lifecycle proofs remain
M4-04/M4-05. This checkpoint does not claim those later results.

### M4-02 evidence identities

Paths are relative to the ignored M4 evidence root. The final input manifest
contains 288 source/test/script/settings files and 897 dependency files.

| File | SHA-256 |
| --- | --- |
| `m4-02-qualification.json` | `b22c82cbabe3f14ad28194d357710f3517c26ab7d4dde43e913f15b8b247d3bd` |
| `m4-02-review-inputs.sha256.json` | `30996b2789245d7f073b92a76c4134ae41ae80da217367a5eafd71a303bf9d80` |
| `m4-02-review-tests-default-receipt.json` | `d93ca5109cf8fcd58b5aba538ab84a67ecdebfe2e64c116c64014db0eacb20d6` |
| `m4-02-review-tests-deploy-receipt.json` | `03ee6759926aa99d1d9897c1ef00e6d078e6115eff4ccbf2328c5b1e07182e70` |
| `m4-02-ownership-comparison.json` | `a0e34d0d52854e2f6d9d4c96f452b6d8c92b2a7ff51a46a240ca203f0d57d371` |
| `m4-02-abi-comparison.json` | `c8dc4de428066730717f83c972cf91ec0828fd148c3a7723dd3be43987b9ac28` |
| `m4-02-storage-comparison.json` | `aad7a77b82e41c203354497f1f28d987a4aaa21821f16634bf22f896cc011ac7` |
| `m4-02-composition-artifacts.json` | `f7e1bce71cf6c2cb9fa1cf7b8a44a3808f9cd170a320672b49e30969dab83cd6` |
| `m4-02-transfer-gas-summary.json` | `fb6fa3b083512bf07fa09005a90c209d41c62b64e9ed1b697af6bcf3679468d2` |
| `m4-02-lint-comparison.json` | `975399b18f75bed9d7fe3ebdbe5ee0b3a15b3cc1997b07328eaff98181f3e246` |

The user approved the staged M4-02 checkpoint and authorized commit/continuation.
Its reviewed Solidity and all 40 evidence hashes were verified unchanged before
the signed kethcode commit; only completion-status documentation changed after
review. M4-03 is next. The reference documents and voice guide remain untracked
and excluded.

## M4-03: Fourth feature and callback activation

M4-02 was approved and committed as `d3811bbb21b09faf2610e507687aee92fe82c330`,
with the kethcode SSH signature verified. M4-03 adds test-only code; all
production sources and both frozen transfer-component files remain unchanged.

### Independent feature and explicit integration

`BorrowAmountPolicy` owns two market-keyed values: `maximumNormalizedBorrow`
and `lastNormalizedBorrow`. Its management API delegates to the existing
`FeatureAuthority` implementation, so administrator and market registration
checks still have one owner. The limit applies to each borrow in underlying
asset units. Zero prevents positive borrows; it does not disable transfers or
withdrawals. Recording the last accepted amount provides an observable effect
without introducing another cumulative counter or quota.

`OpenBorrowHooks`, `FixedBorrowHooks`, and `PeriodicBorrowHooks` inherit the
unchanged transfer assemblies plus that independent component. Each concrete
hook declares required borrow dispatch, explicitly calls its existing transfer
initializer before initializing the borrow limit from `parameters.maxTotalSupply`,
and authenticates `msg.sender` with `_requireHookedMarket` before invoking the
borrow feature. Initialization uses callback parameters while the market has
no deployed code. No existing feature or reusable base/term implementation
needed editing.

The feature itself does not inherit `BaseHooks`. The concrete assembly wires
its helper into `_checkBorrow`; this avoids adding a second `BaseHooks`
inheritance branch and having to resolve unrelated term overrides. The original
production templates retain their unguarded, empty borrow callback. Their
existing no-op callback test remains unchanged and passes in both profiles.

Two overloads in `ProductionMatrixFixture` accept custom template artifacts
and an existing hook instance with exact requested flags. The original helper
signatures retain the built-in templates and original default flags. Template
storage, factory setup, and market deployment still have one implementation.
The new cases request only deposit credentials, deliberately omitting both
borrow and transfer dispatch. Actual market flags agree with the composition's
public configuration, and uncredentialed transfers still reach the feature rules.

### Behavioral proof and retained tests

Four new properties belong to `ProductionMatrixScenariosTest`. Each covers all
six open/fixed/periodic and standard/revolving combinations through real
factories and actual stored initcode:

| Property | Observable result |
| --- | --- |
| Factory deployment and activation | Registered markets use the selected stored template; required callbacks are enabled despite omitted request flags. Both creation defaults are present. Stored bytes, runtime size, and complete constructor payload meet deployment limits. |
| Borrow bounds and retained transfer rules | Below/at/above-limit borrowing after interest moves `scaleFactor` above RAY uses normalized asset amounts. Accepted borrows transfer assets, record the amount/event, and increase revolving principal. Rejected borrowing preserves state/balances. Both prior transfer rules still reject and allow real transfers; recipient rejection restores the earlier volume write. |
| Authority and market isolation | Two markets share one instance with distinct limits and accepted amounts. Unknown callback callers fail registration before the feature's amount check. Unauthorized and unknown-market management fail. Pending administrators have no authority; accepted transfer replaces authority while retaining both markets' state. |
| Downstream failure and earlier core guards | A mocked underlying transfer returns false after the hook runs. The last accepted amount, market state, balances, and revolving principal roll back. Clearing the mock allows the same amount. Borrowability and closed-market errors precede the feature's zero-limit rejection. |

Source comparison retains **all 737 existing test/invariant entrypoints byte
for byte**, including their assertions and expectations. Four additions bring
the source inventory to 741 entrypoints with the same 51 owning suites and no
inherited or fixture-owned test entrypoints. This is an inventory, not a full
suite run.

Final focused default and deploy checks each pass **345 tests across 19 suites**,
with 1,000 fuzz iterations and seed `0x5eed`. They retain the prior 339-case
selection, add the four composition properties, and include the two existing
production-economics cases because they also consume the changed shared fixture.
All users of that fixture are covered. The three full canonical runs and
invariant campaigns remain M4-06.

All four touched Solidity files pass Prettier. Lint retains the same 33 untouched
formatting failures, zero Solhint errors, and 22 warnings. Initial diagnostics
exposed a reused market salt in the new matrix helper and two overlong comments;
both were corrected before the final checks. No existing assertion was relaxed.

### Deployment sizes, compatibility, and costs

| Test composition | Runtime bytes | Creation bytes | Stored initcode bytes | Stored headroom | Actual constructor payload |
| --- | ---: | ---: | ---: | ---: | ---: |
| `OpenBorrowHooks` | 16,945 | 19,672 | 19,673 | 4,903 | 19,768 |
| `FixedBorrowHooks` | 18,303 | 21,030 | 21,031 | 3,545 | 21,126 |
| `PeriodicBorrowHooks` | 21,195 | 23,922 | 23,923 | 653 | 24,018 |

Both profiles produce identical composition ABIs and executable bytes. Each
adds 465 bytes to its M4-02 counterpart. Real factory deployments verify the
`STOP || initcode` bytes and the 24,576-byte runtime/storage and 49,152-byte
constructor limits, without a raised code-size setting. Constructor payloads
include the actual administrator and empty `args`. Periodic fits with 653 bytes
of stored-initcode headroom; further examples must keep measuring that limit.

All three production ABIs, selectors, creation/runtime bytes, link references,
and immutable patch positions remain identical to M3/M4-02 in both profiles.
The prior transfer compositions' ABIs and bytecode also remain identical.
Unchanged production sources qualify retained M4-02 layout and production gas
evidence under their original conditions and exclusions; no fresh production
layout or gas measurement is claimed here.

Two canonical scenarios supply 48 trace-reported composed-market borrow calls,
including 36 nested borrow callbacks and 12 earlier core rejections. Six failed
asset transfers show the feature event before the failed transfer; the three
revolving cases also show the principal update before rollback. Those trace
events describe execution before a revert, not persisted logs. Tests separately
assert the restored state and successful retry.

Representative callback costs for below-limit entry, an at-limit update, and
above-limit rejection are 30,111 / 13,011 / 6,566 gas for open, 30,073 / 12,973 /
6,528 for fixed, and 30,308 / 13,208 / 6,763 for periodic. These nested callback
costs match across the two market kinds in that scenario. Measurements use
Foundry isolation, initial timestamp `1724284800`, seed `0x5eed`, and the exact
source-bound states/inputs retained in the trace summary. They are probe costs,
not a production regression or a full transaction estimate.

### M4-03 evidence identities

Paths are relative to the ignored M4 evidence root. The final manifest contains
290 source/test/script/settings files and 897 dependency files. Tools, settings,
and dependency identities remain unchanged. The review receipt binds the
final tests, artifact comparisons, ownership check, lint, and borrow traces.

| File | SHA-256 |
| --- | --- |
| `m4-03-qualification.json` | `946e2f2ac2236d8a828a2db08f0ce2c7e2ca8b2cd33ee25fff0585f9cb9d69fb` |
| `m4-03-review-inputs.sha256.json` | `70305f7499bbbe27e0b5c2c0d9730a79cda7511a0553c095f5ed4db3fe572b10` |
| `m4-03-review-tests-default-receipt.json` | `7a0e5445ae1fcd7f4058944ccd0c26aa82fce3e705ffe68d4138aa856f8eb020` |
| `m4-03-review-tests-deploy-receipt.json` | `37f7f008ae9066408e0f1c49b85ef14c1f9af162ad377e784db15ccfcaedc723` |
| `m4-03-ownership-comparison.json` | `e17b939332339487a9948a0325ad4bbc7e1411df8bd87d6b88ec695bfa257809` |
| `m4-03-composition-artifacts.json` | `6d9f87ce25ca76020c7acb5e3c4d40756a6184c2656b4d154d5de7ce23f5b087` |
| `m4-03-borrow-gas-summary.json` | `f953e7b603b89a6728055b92e2cfe98fd641a2c98c9bc891779de4212fb9bcc1` |
| `m4-03-lint-comparison.json` | `352728115f1902a66fe7b58de7edcaf10af69b39f145a5e5f849af98861c8c70` |

The user approved the M4-03 commit on 2026-09-24 and requested a hold for reboot.
The reviewed index, all 52 evidence artifacts, and 1,187 qualified inputs were
verified unchanged before the signed kethcode commit; only completion-status
documentation changed after review. M4-04 has not started and waits for the user
to resume. The voice guide, PDF, and lifecycle sketch remain excluded.

## M4-04: Deliberate APR default replacement

The user resumed execution on 2026-09-24. Verified the signed M4-03 handoff
`81934d7df4b0db296bf6c475dc512acdc1357def`, all 52 retained evidence artifacts,
and its 1,187 input hashes before implementation. M4-04 changes only test code
and documentation. Production contracts and the existing transfer/borrow
components remain unchanged.

### Selected calculation and shared validation

`AprReplacementPolicy` keeps the requested APR, selects a reserve ratio of
3,333 bips, records `lastSelectedApr[market]`, and emits `AprDefaultSelected`.
These are test observables, not proposed lending or tranching terms. The
selected reserve differs from the original temporary-reserve calculation and
provides a result for the effective-value validator to accept or reject.

`OpenAprReplacementHooks`, `FixedAprReplacementHooks`, and
`PeriodicAprReplacementHooks` combine that policy with the existing two transfer
features. They replace only `_applyDefaultAprUpdate` and explicitly reapply the
existing inclusive APR bounds before selecting the replacement. They never
call the skipped implementation. Their `_checkAprChange` calls the shared
effective-value validator after the selected calculation's effects.

The term strategies remain inherited. Fixed maturity still rejects a requested
APR reduction before the default is selected; preserving the requested APR
also preserves that guard's meaning. Periodic increases cancel pending proposals
and use the replacement; equality retains proposals and uses the replacement.
Proposal-backed reductions through either route retain current reserves and
bypass both the original default and its replacement.

The existing validator's errors, two bounds fields, setter body, and validation
statements move to `AprValidationPolicy`. `AprValidationHooks` adopts it while
retaining its original context-recording fields and effects. The setter becomes
`public virtual` so the new assemblies can add `onlyAdministrator` and delegate
to the same implementation. The original harness retains its unrestricted
test setup API. Nonzero temporary-reserve setup in the new assemblies is a
separate harness-only API guarded by administrator and market registration.

The first size probe included full context recording in the shared component;
periodic exceeded the stored-initcode limit by 422 bytes. Keeping that recording
in its existing harness removes the excess instrumentation from the compositions.
The final shared component owns validation only; the replacement's accepted-APR
record is sufficient to prove its effects and rollback.

### Behavioral proof and retained tests

Seven new properties belong to `AprValidationTest`, alongside its five existing
cases:

| Property | Observable result |
| --- | --- |
| Skipped temporary-reserve effects | Eleven cases cover inputs that would activate, update, cancel, or expire the inherited default. Nonzero seeded state stays unchanged and successful calls emit only the selected-default event plus any required periodic proposal cancellation. Periodic reductions cannot enter the original activation path; their bypass has its own test. |
| Inclusive APR bounds | Zero and 10,000 bips pass for every term; 10,001 and `uint16.max` reject before the selected effect. Seeded temporary-reserve state stays intact. |
| Effective-value validation and rollback | Requested/current reserves pass a ceiling that the selected 3,333 exceeds. Rejection restores the prior selected APR and any periodic proposal cancellation. A subsequent valid update succeeds even with an out-of-range requested reserve, because validation uses the selected value. APR-floor rejection is also covered. |
| Fixed guard priority | One second before maturity, the term error precedes the selected calculation and APR-floor check. At maturity, effective-value validation applies; satisfying the floor permits the reduction. |
| Both periodic reduction routes | Rejection retains the proposal, prior selected APR, and seeded default state. Retry returns the exact proposed APR and current reserves, consumes the proposal, and emits only the execution event. The replacement's accepted-APR record stays unchanged. |
| Unrelated rules | Deposit minimum and credential checks, known-lender bookkeeping, both transfer rules and their rollback, withdrawal timing/access, and management authority remain effective after using the replacement. |
| Deployment limits | Actual composed runtimes and `STOP || initcode` storage contracts deploy and fit the unchanged size limits, including the complete constructor payload. |

All 741 prior test/invariant entrypoints remain. The only adaptations to old
case bodies are six error-selector references in five cases: they now name
`AprValidationPolicy`, which owns the unchanged errors. Inputs, assertions,
expected values, and behavior are retained. Seven additions bring the source
inventory to 748 entrypoints with the same 51 owners and no inherited or
fixture-owned test entrypoints.

Standalone before/after compilation confirms the original validator's raw ABI
and all 17 normalized storage entries are unchanged. Current definitions also
match both Foundry profiles; standalone solc and Foundry differ only in ABI
entry ordering. Source comparison confirms identical moved declarations,
setter body, validation statements, and retained recording statements/members.

Final focused default and deploy runs each pass **352 tests across 19 suites**,
with 1,000 fuzz iterations and seed `0x5eed`. This is the prior 345-case selection
plus seven new properties. All six touched Solidity files pass Prettier. Full
lint remains at 33 untouched formatting failures; Solhint has zero errors and
the same 22 warnings. Full canonical runs and invariant campaigns remain M4-06.

### Compatibility, deployment sizes, and costs

| Test composition | Runtime bytes | Creation bytes | Stored initcode bytes | Stored headroom | Constructor payload with empty `args` |
| --- | ---: | ---: | ---: | ---: | ---: |
| `OpenAprReplacementHooks` | 16,167 | 18,924 | 18,925 | 5,651 | 19,020 |
| `FixedAprReplacementHooks` | 17,506 | 20,263 | 20,264 | 4,312 | 20,359 |
| `PeriodicAprReplacementHooks` | 20,558 | 23,315 | 23,316 | 1,260 | 23,411 |

Both profiles produce identical composition ABIs and executable bytes. All
runtime/storage contracts fit 24,576 bytes and constructor payloads fit 49,152
bytes without changing compiler or code-size settings. These assemblies combine
APR replacement with the two transfer features; the independent borrow examples
remain unchanged. Real factory-created replacement markets and their APR/closure
lifecycle are M4-05 work, not a result claimed by this checkpoint.

Production ABIs, selectors, creation/runtime bytes, links, and immutable patch
positions remain identical to M3/M4-03. Existing transfer and borrow compositions
retain their ABIs and bytecode. Unchanged production inputs qualify retained
layout and gas evidence under their original conditions and exclusions; no fresh
production layout or gas measurement is claimed.

Three canonical scenarios provide 27 direct APR-callback observations. For an
accepted update from recorded APR 1,000 to 1,100, callback gas is 34,449 for open,
36,791 for fixed, and 44,155 for periodic. The periodic case also cancels a pending
proposal. Costs use Foundry isolation, initial timestamp `1724284800`, seed
`0x5eed`, and the exact stored states/calldata in the retained trace summary.
They describe these test compositions, not production deltas or complete market
transactions. Rejected traces show selected/proposal effects before rollback;
successful-call event assertions establish absence of committed default events.

### M4-04 evidence identities

Paths below are relative to `audits/hook-refactor/m4/2026-09-24/`. The final
manifest contains 293 source/test/script/settings files and 897 dependency files.
Toolchain, settings, and dependency identities remain unchanged. The qualification
record binds the final tests, artifact comparisons, validator extraction/layout,
test ownership, lint, and APR observations.

| File | SHA-256 |
| --- | --- |
| `m4-04-qualification.json` | `4689c3a6f2b07ba8f8f9849371d21017a406f112a2e8c7f828c113c131d54086` |
| `m4-04-review-inputs.sha256.json` | `a49aebf1cc948cfa0b736e804aa0de13da8ccf6804c3961ddabb117b94983cb1` |
| `m4-04-tests-default-receipt.json` | `8d40afc6b629831f697b7274a3d52aa35021dcbbfdf77bbc63eb4eff9270410f` |
| `m4-04-tests-deploy-receipt.json` | `5e3b41799bec9b27da67738a13a6eb5b29ba93796e131644b499c3cdc8e262a0` |
| `m4-04-validator-comparison.json` | `a1d02243081e4e29542078f07db34e92d9741628c49c65715b30917157c5d595` |
| `m4-04-validator-move.json` | `03f9485e2dd2f499151662e0af33388a3da14eb0b4198dbd5dcf5dd4b580de00` |
| `m4-04-ownership-comparison.json` | `9871aea316e54770007d00d397863b2eae799068afaaa4cdfc66c62b6652f2f4` |
| `m4-04-composition-artifacts.json` | `17f61e1082061151bb381a4df7b79512655a9c4947b174f390d5b334756a08c6` |
| `m4-04-apr-gas-summary.json` | `540d52714de55a76476bb0f6f5c633b37b669816293a3deda5ae9ab3b3b9a76c` |
| `m4-04-lint-comparison.json` | `24ff7b26b5ab54c216f6967996b1900af0486cde990444aa30e9c2de0fc051b0` |

The user approved M4-04 and continuation on 2026-09-24. Before committing, the
reviewed index, all 59 evidence artifacts, and 1,190 qualified inputs were verified;
only completion-status documentation changed after review. M4-05 is next. The
voice guide, PDF, and lifecycle sketch remain excluded.

## M4-05: Alternate routes and lifecycle integration

M4-04 was approved and committed as `ba6f4af14be677c46303c78feaecba94fb1eae3c`
with a verified kethcode SSH signature. M4-05 adds five properties to
`ProductionMatrixScenariosTest`, using the same three APR replacement assemblies
through the real standard/revolving factories. No production contract or
existing test mock changed.

### Changes and proof ownership

`ProductionMatrixFixture` now accepts explicit market-creation hook data through
one additional `_deployMatrixCell` overload. Its existing overload forwards the
same default data, arguments, and current timestamp. The original factory body
is reused unchanged after relocating the hook-data local; all other existing
fixture and matrix-test methods retain identical tokens.

The new properties cover 26 real factory deployments, with one owner for each
integration behavior:

| Property suffix after `test_replacement` | New evidence |
| --- | --- |
| `FactoriesApplyEffectiveAprAcrossProductionMatrix` | All six term/market combinations deploy with creation APR/reserves outside the update validator's bounds, proving creation is separate. Updates reject the selected reserve of 3,333 even when the caller requests zero. Once validation permits it, insufficient market liquidity still rejects the update and rolls back the hook's selected-APR record. Repayment permits the retry; the market stores the effective values and emits the corresponding update. |
| `PeriodicExecutionRechecksBothMarketRoutes` | Both market types and both APR entrypoints accept a proposal before the validation bounds change. Execution rejects one second before the response window ends, then rejects unpaid response withdrawals. Funding the batch permits the term strategy to proceed even while its claim is unexecuted; the changed APR floor and reserve ceiling still reject execution. Each rejection restores the proposal and prior market state. Restoring both bounds permits APR 800 with the current reserve ratio 2,000. Neither reduction route selects the replacement default's 3,333 reserve or touches seeded temporary-reserve state. |
| `PeriodicEqualityAndIncreaseUseMarketState` | On both market types, equal APR retains the proposal while applying replacement reserves. A rejected increase restores the proposal, prior selection, and market state; the accepted retry cancels the proposal and commits the selected APR. |
| `ClosureRetainsBatchingAndAccessAcrossProductionMatrix` | All six combinations close with a positive APR floor and a reserve ceiling below 100%. Closure pulls the exact debt shortfall, emits repayment/closure events, then stores APR zero and reserves 10,000. It leaves the prior APR-selection record intact. Fixed maturity moves to the early closure time; periodic closure cancels its proposal and opens withdrawals outside the schedule. Unknown lenders still fail access, while a known lender blocked from deposits can exit. Shared pre-/post-closure batches pay the exact pro-rata claims and drain the markets to rounding dust; revolving drawn principal reaches zero. |
| `FixedClosurePermissionsRemainIndependentAcrossMarkets` | All four combinations of `allowClosureBeforeTerm` and `allowTermReduction` run on both market types. The setter keeps its own reduction permission and does not invoke APR selection. Either permission allows early closure. With neither permission, the rejected close rolls back debt transfers and state; exact maturity permits closure. |

Every periodic market execution has `deadbeef` appended to its calldata. The
ordinary route also requests reserves of 7,777. The dedicated-route proof
records the actual market-to-hook call and checks its complete calldata against
`executePendingAnnualInterestBipsReduction(state)`: the appended bytes are absent.
The unchanged `AprValidationTest` separately records the internal validator
context and proves its hook data is empty. Together these distinguish the
APR-only route from the ordinary callback; neither route can replace current
reserves when executing a periodic proposal.

Existing canonical owners retain the other distinct properties. In particular,
`FixedTermHooksTest` covers added setter validation/effects, their rollback, and
their exclusion from initialization and early closure. Existing periodic and
market tests retain proposal expiry and the rest of the term/access lifecycle.
These tests were rerun without changing their assertions or setup.

The APR example deliberately allows normal market closure. `_checkAprChange`
is an update boundary, so its floor does not prevent the core's forced APR zero
or reserve reset. A future feature that restricts closure must use the closure
boundary explicitly. This example makes no repayment/default or tranching-policy
choice.

### Verification and compatibility

Final focused default and deploy runs each pass **357 tests across 19 suites**,
with 1,000 fuzz iterations, seed `0x5eed`, and initial timestamp `1724284800`.
They use the same contract filter as M4-04, adding the five properties to its
352 cases. The receipts retain the exact commands and discovery lists. Full
canonical runs and invariant campaigns remain M4-06.

All **748 prior source entrypoints** retain identical tokens, including setup,
assertions, and expected values. The tree now has 753 entrypoints across the
same 51 owners, with none inherited or placed in fixtures. Both edited Solidity
files pass Prettier. `yarn lint:check` stops at the same 33 untouched formatting
failures; standalone Solhint reports the same zero errors and 22 warnings.

Production hook ABIs, selectors, executable bytes, links, and immutable patch
positions still match M3. All nine existing transfer, borrow, and APR replacement
compositions retain their prior ABIs and code in both profiles. Production
sources and all test mocks are unchanged, so previous layout and production
cost evidence remains applicable under its original conditions; no fresh
production layout or gas measurement is claimed.

The three APR replacement assemblies now deploy through both real factories.
Their M4-04 runtime/stored-initcode sizes are unchanged, including periodic
stored-initcode headroom of **1,260 bytes**. Compiler settings and deployment
limits are unchanged.

Three traced canonical scenarios record **48 nested callbacks inside 50 market
calls**: 44 APR callbacks and four closure callbacks. They distinguish 22 callback
rejections from six successful callback returns subsequently rolled back by the
market's liquidity check. For the accepted APR 1,000-to-1,100 update after funding
liquidity, nested callback costs are 28,061 / 30,403 / 33,572 gas for open / fixed /
periodic, on each market type. These are test-composition frame costs with call
isolation and the recorded state/calldata, not transaction estimates or
production cost deltas. Reverted trace events are not persisted logs.

### M4-05 evidence identities

Paths are relative to ignored `audits/hook-refactor/m4/2026-09-24/`. The manifest
contains 293 source/test/script/settings files and 897 dependency files. Only
the matrix test and its fixture differ from the approved M4-04 inputs.

| File | SHA-256 |
| --- | --- |
| `m4-05-qualification.json` | `41d645b91ef2695df98944d4b3319c9a051c7a8427da39f6af7204cac63abf06` |
| `m4-05-review-inputs.sha256.json` | `458ffe524fc3859d927f8f17ed3148ec60cfe64ac191c4fb11512ec309f28a7d` |
| `m4-05-tests-default-receipt.json` | `f61b333e304ec231ec69e1dde0a2e904a68eefae6491c1c7aaef8aad7e49217f` |
| `m4-05-tests-deploy-receipt.json` | `a6a99e751165a8f1aa936e3afb8b290d9ec04380df57e3ae8a18457f14104bad` |
| `m4-05-ownership-comparison.json` | `b55ee8695475697478b7b9e41db6985fd62e944c44ea0f8cbeda08a9fec08bdb` |
| `m4-05-fixture-comparison.json` | `9ec3eced7ffba247beecfa164aa0f39b4fc67f72f122016d2d348c9f18f81580` |
| `m4-05-composition-artifacts.json` | `19e1afc1561dcd4f4d6b4937fb76157150912fafaa6c59c9199567a68212185a` |
| `m4-05-market-observations.json` | `1ecb18295298c1ef4d3aef47959f2f71132fff230b03450582cab5c22199356a` |
| `m4-05-lint-comparison.json` | `7fda175bcdfbfded2679abaedad6022716782b81ac584de0e97961ca5a19fb76` |

The user approved M4-05 and continuation on 2026-09-24. Before committing, the
reviewed index, all 59 evidence/helper artifacts, and 1,190 qualified inputs were
verified; only completion-status documentation changed after review. M4-06 is
next. The voice guide, PDF, and lifecycle sketch remain excluded.

## M4-06: Qualification and M5 handoff

M4-05 was approved and committed as `5c8c9033b70c89715d6b2018fc1196895d914ef0`,
with its kethcode SSH signature verified. Final qualification is complete on
the approved M4-06 tree. The user approved the two test-only APR caller checks,
regression, and qualification checkpoint on 2026-09-24. No production contract
changed during M4-06.

### Authentication correction

The full suite initially passed 745 reported tests, but review against the
spec's stateful-extension requirement found a missing check. The original open
and fixed APR callbacks accept unregistered callers. Their replacement examples
added `lastSelectedApr[msg.sender]` writes and `AprDefaultSelected` events without
authenticating the caller first. The periodic strategy already authenticates
both APR routes.

The open and fixed `_applyDefaultAprUpdate` implementations in
[`AprReplacementHooks.sol`](../../test/mocks/AprReplacementHooks.sol) now call
`_requireHookedMarket(msg.sender)` before bounds checking and `_selectAprUpdate`.
The existing bounds and fixed maturity guard remain in place. All other assembly
tokens are unchanged, including the periodic implementation. This is a correction
to the new stateful examples; the original templates retain their qualified
callback behavior.

`test_replacementAprCallbackAuthenticatesBeforeFeatureState` in
[`AprValidationTest`](../../test/access/AprValidation.t.sol) fails against the
reviewed M4-05 examples and passes after the two checks. Across all three terms,
an unknown market's otherwise-valid and out-of-range updates both fail with
`NotHookedMarket`. Earlier selections, other markets, and seeded temporary-reserve
state survive unchanged. The dedicated periodic route also rejects that caller;
a registered market still updates successfully. This adds one property without
editing prior cases. The pre-correction runs are archived separately under
`m4-06-before-authentication/`; all results below use the corrected inputs.

### Full verification and test ownership

| Required command | Final result |
| --- | --- |
| `forge test` | 746 reported tests, 51 suites; zero failures or skips. |
| `yarn test:fixed` | 746 reported tests, 51 suites; timestamp `1724284800`, seed `0x5eed`. |
| `FOUNDRY_PROFILE=deploy forge test` | 746 reported tests, 51 suites; zero failures or skips. |
| `yarn lint:check` | Same 33 untouched Prettier failures as M3; no new formatting failures. |
| Standalone Solhint over `src` and `test` | Zero errors, the same 22 warnings as M3. |
| Prettier over all 16 existing M4-changed Solidity paths | Pass. |

Each full run uses 1,000 fuzz iterations and a nine-property invariant campaign
of 2,000 runs at depth 30: 60,000 calls across 17 handler actions, with zero
handler reverts or discards. The tree has **754 source entrypoints**; Foundry
reports the nine invariants as one campaign, yielding 746 reported tests. The
discovery comparison matches every source owner and entrypoint across all runs.

Of M3's 727 entrypoints, 718 retain identical tokens, five change only moved-error
owner qualifications, and four existing recipient tests expand to all three
terms while retaining all 25 original assertions/revert expectations. None are
removed or inherited. The 27 additions have existing owners: ten transfer
properties, four borrow properties, seven APR replacement properties, five
real-market lifecycle properties, and the authentication regression. The prior
53-case replay remains separate M3 evidence, not a fresh M4 replay.

### Requirement reconciliation

The rows follow the [spec acceptance criteria](hook-composition.md#acceptance-criteria).
Earlier task sections retain the individual properties, inputs, and exceptions.

| Criterion | Evidence and owning tests |
| --- | --- |
| 1. One maintained implementation | M2/M3 shared and fixed/periodic ownership proofs, plus M4's open-policy extraction. All 12 original open members retain their tokens with one owner; type imports, comments, and public formats are preserved. Base/access/constraint and fixed/periodic production owners are unchanged from M3. |
| 2. Existing behavior and canonical owners | All three full runs include the original common and term suites, lifecycle cases, and integration owners. The entrypoint comparison above accounts for every existing case. |
| 3. Independent three-/four-policy compositions | `HookExtensionsTest` covers recipient and amount rules with each term, shared state/API authority, credential exemptions, error order, and rollback. The four `test_fourPolicy*` matrix properties add borrow through new component/assembly code without editing those reusable features or production policies. |
| 4. Deliberate default replacement | `AprValidationTest` proves selected APR/reserves, effective-value validation, retained maturity, both periodic routes, absent skipped-default events, and preserved temporary state. The five `test_replacement*` matrix properties prove real-market rollback, proposal/payment changes, creation/setter separation, closure funding/reset, and continuing withdrawal batches. The new authentication regression covers the corrected stateful boundary. |
| 5. Activation, isolation, and encodings | Transfer and borrow assembly tests distinguish requested credentials from forced callback dispatch, validate declared/effective flags, and isolate registered markets and administrator changes. Existing configuration and lens owners still pass; production encodings are unchanged. |
| 6. Full integrations and suite rules | Factory, dispatch, administrator transfer, wrapper, borrower-account, lens, and standard/revolving owners pass in all three full runs. No fixture gains a test entrypoint or permanent legacy implementation. |
| 7. ABI, layout, metadata, size, and costs | Fresh comparisons cover inherited ABI entries, selectors, tuple `internalType`, storage, executable bytes, links, and immutable positions against M3 and the M1 compatibility reference. Current metadata sources match the qualified inputs. Costs below preserve the original measurement boundaries. |
| 8. Actual deployment limits | All three production templates and all six borrow/APR assemblies exercise both real factories. The three transfer-only assemblies exercise runtime and actual `STOP || initcode` storage deployment; their features also run through both factories in the larger assemblies. All measured limits pass. This does not claim that each transfer-only test assembly independently uses a factory path. |

### Compatibility, deployment sizes, and costs

The three production raw ABIs, selectors, creation/runtime executable bytes,
links, and immutable patch positions match qualified M3 and M2. Compared with
M1, the only ABI differences remain the accepted top-level callback input names:
24 open, 24 fixed, and 28 periodic. Fresh normalized storage matches M1/M2/M3
with 11 entries per template, no slot changes, and preserved periodic packing.
The only M4 production source changes are the open-policy extraction/adoption;
they leave the deployed executable output unchanged.

| Production template | Runtime bytes | Creation bytes | Stored initcode bytes | Stored headroom |
| --- | ---: | ---: | ---: | ---: |
| `OpenTermHooks` | 15,653 | 18,379 | 18,380 | 6,196 |
| `FixedTermHooks` | 17,014 | 19,741 | 19,742 | 4,834 |
| `PeriodicTermHooks` | 19,949 | 22,676 | 22,677 | 1,899 |

Production size deltas from M3 are zero. The already-reviewed runtime/creation
increases from M1 remain 349 / 413 / 678 bytes for open / fixed / periodic; the
M2 changes and their rationale are not erased by comparison with M3.

| Test assembly | Runtime bytes | Creation bytes | Stored initcode bytes | Stored headroom |
| --- | ---: | ---: | ---: | ---: |
| `OpenTransferHooks` | 16,480 | 19,207 | 19,208 | 5,368 |
| `FixedTransferHooks` | 17,838 | 20,565 | 20,566 | 4,010 |
| `PeriodicTransferHooks` | 20,730 | 23,457 | 23,458 | 1,118 |
| `OpenBorrowHooks` | 16,945 | 19,672 | 19,673 | 4,903 |
| `FixedBorrowHooks` | 18,303 | 21,030 | 21,031 | 3,545 |
| `PeriodicBorrowHooks` | 21,195 | 23,922 | 23,923 | 653 |
| `OpenAprReplacementHooks` | 16,177 | 18,934 | 18,935 | 5,641 |
| `FixedAprReplacementHooks` | 17,516 | 20,273 | 20,274 | 4,302 |
| `PeriodicAprReplacementHooks` | 20,558 | 23,315 | 23,316 | 1,260 |

The open/fixed APR caller checks add 10 runtime and creation bytes each. All
other composition code and every composition ABI remain unchanged. Both profiles
fit the 24,576-byte runtime/storage limit. Constructor payloads with empty `args`
add 96 bytes to creation code and remain below 49,152 bytes. No compiler or
code-size limit was changed to obtain these results.

Unchanged production executable identity qualifies the original 97 callback,
70 creation/minimum/query, and 14 management observations under their recorded
conditions and exclusions. No fresh production gas replay is claimed. The
15 transfer and 36 borrow composition observations also remain applicable.

The affected APR examples were measured again: 27 direct APR observations and
48 nested APR/closure callbacks inside 50 market calls. Registered call inputs,
state, order, results, and observed events match M4-04/M4-05. The extra caller
check costs 2,977 gas in the measured open APR paths and 998 in fixed paths that
reach the replacement helper; fixed maturity rejections/closure and periodic
paths are unchanged. An accepted real-market APR 1,000-to-1,100 update after
funding now costs 31,038 / 31,401 / 33,572 gas in the open / fixed / periodic
callback frame, on both market types. These are isolated frame observations at
the recorded timestamp, seed, state, and calldata, not transaction estimates.
Reverted trace events are not persisted logs.

### M5 handoff

M4 establishes source composition with explicit integration choices. It does
not establish arbitrary compatibility among future policies or select tranching
economics. M5 needs its own plan and tracker after the user reviews and pushes
M4. Its documentation and final compatibility work should use these boundaries:

- Use the reusable transfer/borrow components as the added-rule examples and
  the APR replacement assemblies as the deliberate-default example. Explain
  explicit ordering, one owner per state/API/event, and which behavior is kept
  or replaced. There is no fixed limit of two feature policies or automatic
  conflict resolver.
- Preserve the distinction between requested access and required dispatch.
  Initialization runs before market deployment. Stateful callbacks authenticate
  registration before writing feature state; legacy callback differences must
  not be generalized into permission for new unauthenticated stateful features.
- Document effective-value APR validation on both routes. Dedicated periodic
  execution uses current reserves and empty hook data. Creation, fixed-term
  management, and closure are separate boundaries; closure's forced APR zero
  and reserves 10,000 do not pass through the ordinary APR-update validator.
- Keep view promises precise: recipient-only queries cannot validate an amount,
  balance, or allowance. Known lenders and wrappers still face extra transfer
  rules. The example amount limit is per transfer; saturating recorded volume
  is observational and cannot exhaust a cumulative exit quota.
- Preserve existing credential-data encoding. Multiple features need explicit
  data integration; hooks are not a complete accounting or post-action event
  feed. Future tranche repayment/default/accounting requirements still need
  their own V2.5 core/interface assessment.
- Carry deployment measurements into each new assembly. The periodic borrow
  example has only 653 bytes of stored-initcode headroom. Record the exact
  factory evidence for each template selected for release and retain existing
  gas conditions/exclusions when evidence is reused.
- Finish the contributor/integration documentation and final encoding, family,
  version, factory/lens/wrapper/authority checks under M5's plan. These test
  assemblies are not production product templates. External SDK/app/subgraph
  changes, publication, and rewriting deployed inventories are not qualified
  or performed by M4.

### M4-06 evidence identities

Paths are relative to ignored `audits/hook-refactor/m4/2026-09-24/`. The final
manifest covers 293 source/test/script/settings files and 897 dependency files;
only the APR mock and regression owner differ from M4-05. Foundry 1.8.3, solc
0.8.25, Node 24.21.0, Yarn 1.22.22, all submodules, and effective default/deploy
settings remain unchanged. The qualification binds the command receipts,
discovery, source ownership, raw artifacts, fresh layout, gas comparisons,
regression evidence, lint, and helper scripts.

| File | SHA-256 |
| --- | --- |
| `m4-06-qualification.json` | `14202f129d0b07da747f23c2ff5c1c5164a02fa964724ac9a0fb063ce61b725b` |
| `m4-06-inputs.sha256.json` | `07c348cf1f0e8149d84a681ee0e1ca2da77e54b75e4fcb04a1fb2ad3531b055d` |
| `m4-06-tests-default-receipt.json` | `28842785dc17477b1c69558bebb7ccba06a82862fe811ba4be3f9e98f91eaf49` |
| `m4-06-tests-fixed-receipt.json` | `e5cb5390eccfbb254d5bb51833a914d49baba093deb1917e23f75112bed42e41` |
| `m4-06-tests-deploy-receipt.json` | `6099a35953be5fb8fdb564c1f7a832c9c3c05e0567543887115fa6a5d3e75c42` |
| `m4-06-ownership-comparison.json` | `5768eb340a591b721676576d1c2b1d9c38fb24e751c09fb0d08bb2685ffdbc24` |
| `m4-06-abi-comparison.json` | `de6746a6fcc42a0fd82fa60342681b5335e95a32c51ab17f7ee91fdeef2d6e78` |
| `m4-06-storage-comparison.json` | `d2d4e51b3ab5f69a27deed70bdee1d37b02b79de0f43250d3dbfb80c94c2c8ec` |
| `m4-06-composition-artifacts.json` | `376ff3d761119d10e7e88a4d711be7113d33074951a97512949defa064752d06` |
| `m4-06-apr-cost-summary.json` | `88c80d3c2af3027bad6c7dc37629822279c9d22241234c9243ae7397dba7f88a` |
| `m4-06-authentication-regression-before-receipt.json` | `f00e2e52c36dd8df062f873742c17c476d61e534a98f5a2498f17fe81882eea4` |
| `m4-06-authentication-regression-after-receipt.json` | `73a06b4a8c33047e2e9f7bf56c82a1f1e656c85f9de484d6d0d6166b7608a8ae` |
| `m4-06-lint-comparison.json` | `62648c0c64228fb0d58acad9a2dca99c85237699ad7d5a07f52375f3f3317702` |

The user approved M4-06 on 2026-09-24. Before committing, the exact reviewed index,
all 88 evidence/helper artifacts, archived earlier runs, and 1,190 qualified
inputs were verified; only completion-status documentation changed after review.
All six M4 tasks are complete and ready for user milestone review and push.
M5 has not started. The voice guide, PDF, and lifecycle sketch remain excluded.
