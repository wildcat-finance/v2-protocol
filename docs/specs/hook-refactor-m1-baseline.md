# M1 baseline: existing hook templates

- Source: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c` on `feat/tranching_support`.
- Captured: 2026-09-22 UTC.
- Execution status: identity, compatibility inventory, required tests, and
  size/gas baselines complete. See the [tracker](hook-refactor-m1-tracker.md).
- Raw evidence root, relative to the checkout:
  `audits/hook-refactor/m1/2026-09-22/` (ignored).

## Identity and reproduction settings

The initial checkout has no tracked modifications. The untracked composition
documents and two user-supplied reference documents do not affect compilation.
Subsequent documentation commits retain this production/test source baseline.
The reference PDF and lifecycle sketch are excluded from milestone commits.

| Input | Recorded value |
| --- | --- |
| Git tree | `834fced977e552562beec8325670096389a5de58` |
| Foundry pin / actual Forge | `v1.8.3` / `1.8.3`, commit `cae51ad458f6abb64852b7709eb784352429825d` |
| Solidity | `0.8.25+commit.b61c2a91.Linux.g++` |
| EVM / optimizer | Cancun; via IR; optimizer enabled, 44 runs |
| Metadata | Bytecode hash `none`; CBOR metadata disabled |
| Default / deploy initial timestamp | `1`; suites may explicitly warp |
| Call isolation | `isolate = true`; each top-level test-to-contract call has a separate transaction/EVM context |
| Dynamic test linking | `true`; explicitly pinned with isolation after the default review below |
| Default fuzz / invariant settings | 1,000 fuzz runs; 2,000 invariant runs, depth 30; no configured seed |
| Fixed command | Timestamp `1724284800`, fuzz seed `0x5eed` |
| Deploy profile differences | `deploy-out`, `deploy-cache`, additional `ir` / `irOptimized` output files; same compiler/EVM/optimization settings |
| Node / Yarn | `v24.21.0` / `1.22.22` |

All four top-level submodules match their recorded revisions and have clean
working trees:

| Submodule | Revision |
| --- | --- |
| `lib/forge-std` | `b6a506db2262cad5ff982a87789ee6d1558ec861` |
| `lib/openzeppelin-contracts` | `fd81a96f01cc42ef1c9a5399364968d0e07e9e90` |
| `lib/solady` | `2ba1cc1eaa3bffd5c093d94f76ef1b87b167ff3c` |
| `lib/solmate` | `1b3adf677e7e383cc684b5d5bd441da86bf4bf1c` |

`inputs.sha256.json` records 1,166 materialized tracked files under `src`,
`test`, `script`, `scripts`, and `lib`, plus the build/package pins and lockfile.
Four nested dependency gitlinks are not materialized as files and are listed
separately in `identity.json`; they are not compiler inputs for this suite.
Compiler artifact metadata will identify the sources actually used by each
template. Configuration captures come from `forge config --json` with the
corresponding `FOUNDRY_PROFILE`.

| Evidence / executable | SHA-256 |
| --- | --- |
| `identity.json` | `0f3a6aa6164f840aa33d979652eacfc013e855f08f0f51553c16d935761eae31` |
| `inputs.sha256.json` | `52b23073b83e3f1b81d3065fd0aa465ec17ad20648562d3036bf7c44d53aa35c` |
| `config-default.json` | `43acd28461317a1f75c1f064dab1c0d6890b3805e3146056b1fe30245cdfcbff` |
| `config-deploy.json` | `a771cfc793c764faec63cf0f7aa70b6f18d070b7b0ce58a1130e678e105596eb` |
| Forge executable | `deb412a722e873e11e60051deb9d403b584a2d7e49d8b9ee68441edfea215e9c` |
| solc executable | `c42aada7a52057ddbed93ec011235e256c564c440b68dbaac5ae482babbb3d6d` |

Yarn was absent from the shell. Corepack supplied Yarn 1.22.22 through an
ignored local shim; no package or toolchain configuration was changed:

```sh
corepack enable --install-directory audits/hook-refactor/m1/2026-09-22/bin yarn
export PATH="$PWD/audits/hook-refactor/m1/2026-09-22/bin:$PATH"
export COREPACK_ENABLE_AUTO_PIN=0
```

## Prior evidence disposition

| Existing evidence | Disposition | Reason |
| --- | --- | --- |
| `/tmp/v2-protocol-foundry-1.8.3-{canonical,fixed,deploy}.log` | Historical | Passing output is inspectable, but the logs do not bind the run to an input manifest, tool binary, and effective settings. |
| `/tmp/v2-protocol-foundry-1.8.3-{default,deploy}-sizes.log` | Historical | Size tables lack the same run identity and do not measure the template storage deployment boundary. |
| Existing `out/` and `deploy-out/` artifacts | Build cache, subject to fresh Forge verification | Metadata identifies compiler/source hashes; cache presence alone is not test evidence. |
| Earlier build-only scratch artifacts | Not adopted | Not canonical test receipts; no reason to revive the canceled tooling task. |
| Prior per-operation hook gas receipts | Unavailable | No qualifying receipt found. M1-03 will establish the measurements. |

The historical logs' exact hashes are recorded in `identity.json`. Their
existence avoids ambiguity about what was inspected; no historical passing
count is claimed as a new M1 result. M1-02 will run the three commands in
[`TESTS.md`](../../TESTS.md), export compiler ABIs, and inventory compatibility.
M1-03 will capture creation/runtime sizes and representative operation gas.

### Foundry default review and explicit pins

After M1-03, compared this checkout's effective `forge config --json` using the
available 1.7.1 and 1.8.3 binaries. Two existing defaults changed:
`isolate: false -> true` and `dynamic_test_linking: false -> true`. The config
now explicitly retains both 1.8.3 values. This choice preserves the transaction
semantics under which the canonical tests and M1 gas measurements passed.

New options include coverage/tracing configuration, additional fuzz/invariant
mutation and frontier controls, and disabled symbolic/experimental features.
They retain pinned-1.8.3 defaults; no corpus, symbolic analysis, or mutation
workflow is enabled by this milestone. Existing fuzz/invariant counts and
depth remain explicit. A fixed seed identifies a run under the pinned engine;
it does not promise identical generated cases across engine versions.

Default and deployment `forge config --json` objects compare exactly equal
before and after making these two values explicit. No effective test/compiler
setting changed, so the existing M1 receipts remain applicable without another
identical suite run. The input manifest still records the original file bytes;
`explicit-config-pins.json` records this intentional, equivalent amendment:

- Previous `foundry.toml` SHA-256:
  `885f709eefb5343bb47854b9225cd77908a48d49a2778315f3b581d761c9ed66`.
- Explicit-pins `foundry.toml` SHA-256:
  `a10657160908dc326c00525ca6c30af9c1b30605795a4d794a7380de88ce6513`.
- Amendment receipt SHA-256:
  `48aab12a0c0e41ac78921687da96220fb66453a3e9aec318b91ef2f8d4920802`.

The available 1.7.1 production artifacts also match all 115 corresponding
current deployment artifacts in ABI, creation/runtime bytecode, and source
metadata. That comparison is recorded in `foundry-artifact-comparison.json`,
SHA-256 `4f042786a80a0b86e7dd45c751e9deacf479f68a0ebea6a4e073aa1aafc57fcd`.
This checks artifact identity; it is not a claim that M1 reran the old engine.

## Verification receipts

All three required commands passed against the identified inputs. Forge
validated its existing compilation cache and reported no changed files; these
are fresh test executions, not claims of a clean rebuild. Input hashes still
matched the original manifest after execution. No baseline failures remain.

| Command | Tests / suites | Failed / skipped | Receipt SHA-256 |
| --- | --- | --- | --- |
| `forge test` | 698 / 48 | 0 / 0 | `tests-default.log`: `21f255d22309060577ddc5d79f9a9260d832cfb07106db3a88ee994338b72f36` |
| `yarn test:fixed` | 698 / 48 | 0 / 0 | `tests-fixed.log`: `f69f550ee1ff3687dee2959614e5ac500f2bdf90339e6f4c0f053693e414ae57` |
| `FOUNDRY_PROFILE=deploy forge test` | 698 / 48 | 0 / 0 | `tests-deploy.log`: `eece9094f83fe5323d179e1cc53d23ec9c37f62185b1012b6b1f9e9961936404` |

`test-receipts.json` records command arguments, profile, timestamps, durations,
exit codes, and the input-manifest identity; SHA-256:
`3ebe08810f2cf5c6c5fdf9e001928c450b408f6b39ce8bd0aee27767b92b8368`.

## External compatibility inventory

Full compiler ABIs, including inherited entries, are preserved as
`abi/<Template>.json`. Export normalization is Python
`json.dumps(artifact['abi'], indent=2, sort_keys=True) + '\n'`: sort object keys,
preserve array order and all component names/types, mutability, and indexed
fields. `metadata/<Template>.json` preserves compiler metadata. Default and
deployment artifacts have identical ABIs. Re-export from the baseline revision
after `forge build` to reproduce these hashes; M5 must also compare semantic
entries so a harmless compiler array-order change is not mistaken for an ABI
break. Do not drop inherited errors/events from comparison.

| Template | Functions | Events | Errors | ABI SHA-256 |
| --- | ---: | ---: | ---: | --- |
| Open | 46 | 17 | 26 | `c7000f99a60a991bc3f4fcbdd647fc6c9e9f26b8cf7dcf26bbf62502c108b5aa` |
| Fixed | 48 | 18 | 33 | `3920b04d28b65657aeb5d8a39020855600b685248e296a4f318900540c8ea237` |
| Periodic | 57 | 22 | 39 | `211acc00596a47474360566170cfec44a7beab9ad282e842efa62b0ca5b92069` |

Each also has one constructor, `(address _administrator, bytes args)`.
Empty `args` skips provider initialization; nonempty `args` uses ABI decoding
of `NameAndProviderInputs`: `(string name, address roleProviderFactory,
(uint32 timeToLive, bytes providerFactoryCalldata)[] newProviderInputs,
(address providerAddress, uint32 timeToLive)[] existingProviders)`. Factory and
administrator immutables/authority retain their current meanings.

### Market creation and configuration

`hooksData` uses 32-byte words in the order below. Required prefix lengths are
checked explicitly; optional words use the existing raw calldata readers,
including partial-word behavior and zero-padding at the end of calldata.
Boolean readers use the low bit; these are not strict ABI-decoded booleans.
Numeric readers retain checked narrowing and the current panic behavior.
Replacing these readers with `abi.decode` would change accepted inputs.

| Template | Market creation words | Required bytes | Minimum range |
| --- | --- | ---: | --- |
| Open | minimum, transfers disabled | 0 | `uint128` |
| Fixed | maturity, minimum, transfers disabled, early closure allowed, term reduction allowed | 32 | `uint128` |
| Periodic | first window start, period duration, window duration, minimum, transfers disabled | 96 | `uint96` |

Fixed maturity is `uint32`, from now through 365 days ahead inclusive. Periodic
times are `uint32`; periods are 6 minutes through 365 days inclusive, windows
are at least 1 minute and strictly shorter than the period, and a future first
window is at most 365 days away. Past/current periodic anchors remain valid.
Common creation bounds remain those advertised by `getParameterConstraints`:
APR, reserve ratio, and delinquency fee are each 0–10,000 bips; withdrawal-batch
duration is 0–365 days; delinquency grace is 0–90 days, all inclusive.

Creation order is factory authentication, common bounds, administrator match,
then template decoding/term checks and access configuration. Fixed/periodic
emit their term event before any positive-minimum event. Registration must
work before code exists at the future market address.

| Template | Optional callback flags | Required callback flags |
| --- | --- | --- |
| Open | Deposit, transfer, queue | APR/reserve update |
| Fixed | Deposit, transfer | Queue, closure, APR/reserve update |
| Periodic | Deposit, transfer | Queue, closure, APR/reserve update, pending APR execution |

Access requirements are captured from requested flags before feature-driven
enabling or merging required flags. Requested withdrawal access requires
deposit access and transfer access or disabled transfers; it enables supporting
deposit/transfer callbacks. A positive minimum enables deposit; disabled
transfers enable transfer. Forced queue dispatch alone does not request access.
All three minimum setters retain `(address,uint128)`, administrator checks,
registration checks, and the prohibition on adding a positive minimum without
deposit dispatch. Periodic performs the `uint96` downcast after those checks.

The public `HookedMarket` field orders are:

| Template | Ordered fields |
| --- | --- |
| Open | `bool isHooked, bool transferRequiresAccess, bool depositRequiresAccess, uint128 minimumDeposit, bool transfersDisabled` |
| Fixed | Open's first three booleans, `bool withdrawalRequiresAccess, uint128 minimumDeposit, uint32 fixedTermEndTime, bool transfersDisabled, bool allowClosureBeforeTerm, bool allowTermReduction` |
| Periodic | Open's first three booleans, `bool withdrawalRequiresAccess, bool depositHookEnabled, uint96 minimumDeposit, uint32 firstWithdrawalWindowStart, uint32 periodDuration, uint32 withdrawalWindowDuration, bool transfersDisabled, bool isClosed` |

Single/batch getters return these tuples, preserve order, and return zero
configurations for unknown markets. The exported source type names remain
available from the existing concrete-template import paths. Periodic
`pendingAprChanges(address)` returns `(uint16,uint32)`;
`getPendingAprChange(address)` returns `((uint16,uint32),uint32,uint32)`.
`version()` returns each exact template family name. Only periodic currently
has `templateVersion()`, returning `uint256(2)` and documented as an ABI revision.
The M1 design record will resolve the metadata choice.

### Runtime and integration boundaries

The [behavior map](hook-behavior-map.md) is the detailed callback/event/revert
reference. Preserve the deposit scaling floor, credential side effects,
per-market permanent known-lender status, wrapper exemption, queue boundaries,
APR strategy selection, and proposal/closure event ordering described there.
Open queue access runs whenever invoked; fixed/periodic access is conditional
on the stored request. Open/fixed APR callbacks and existing no-ops must not
gain an incidental registered-market guard. Periodic APR paths and fixed/
periodic closure retain their existing checks.

| Consumer | Dependency |
| --- | --- |
| [Lens configuration](../../src/lens/HooksConfigData.sol) | Exact family strings and all three exported `HookedMarket` types/tuple decoders. |
| [Lens instance data](../../src/lens/HooksInstanceData.sol), [lender data](../../src/lens/LenderAccountData.sol) | Shared access/provider/admin views and concrete-template source imports. |
| [Wrapper](../../src/vault/Wildcat4626Wrapper.sol) | `IMarketTransferPolicy` views, canonical wrapper exemption, and permanent meaning of a false global-transfer-disable result. |
| [Standard factory](../../src/HooksFactory.sol), [revolving factory](../../src/HooksFactoryRevolving.sol) | Constructor args, initcode storage, immutable deploying factory, flags, creation callback, administrator transfer/indexing. |
| [Market configuration](../../src/market/WildcatMarketConfig.sol) | Ordinary APR callback returns APR/reserves; periodic permissionless path returns APR only and retains current reserves. |
| [Deployment scripts](../../script/deploy/v2-5/) and [canonical fixtures](../../test/shared/) | Existing artifact paths, concrete types, constructor/creation encodings, and deployment behavior. |

No market callback selector, `MarketState` tuple, underlying withdrawal batch,
or borrower-account authority change is part of this refactor. New bytecode
and initcode hashes represent new deployments; existing deployment inventories
remain historical.

### Existing coverage and work left for implementation

| Owning suites | Baseline coverage / later obligation |
| --- | --- |
| `test/access/{Open,Fixed,Periodic}TermHooks.t.sol` | Constructors, flags, widths, minimums, deposit/transfer/access rules, no-ops, term boundaries, APR and closure. Periodic tests both execution routes and cancellation/equality. Consolidate common assertions into a runtime matrix during the refactor without inheriting test entrypoints. |
| `test/access/BaseAccessControls.t.sol` | Provider/cache/credential state, known-lender and exact-wrapper queries, blocking, provider administration. Keep this ownership. |
| `test/access/MarketConstraintHooks.t.sol` | Creation bounds and temporary-reserve calculation, rounding, activation/update/cancellation/expiry. Keep this ownership. |
| `test/integration/HookDispatch.t.sol`, `HooksAdministratorTransfer.t.sol`, borrower-account suites | Callback ABI/intermediate states, authentication, transfers of authority and deployment permissions. |
| Factory, production-matrix/economics, lens, wrapper integration suites | Actual standard/revolving deployment and lifecycle paths, family/tuple decoding, wrapper behavior. |

The existing suite is a behavioral baseline, not evidence of extensibility.
M2–M4 must add focused tests for independent overlapping validators, a third/
fourth policy, deliberate default replacement and absence of skipped state/
events, rollback, normally-unused callback activation, alternate APR routes,
and feature isolation across markets. The current creation tests are not an
exhaustive malformed/partial-word matrix; preserve the raw decoding design
and add targeted boundary cases where that code moves. These are implementation
coverage obligations, not baseline failures.

## Deployment size baseline

Lengths come from deployment artifacts' `bytecode.object` and
`deployedBytecode.object`, excluding the hex prefix. Runtime lengths include
immutable placeholders; patching their values does not change length. The
compiler, settings, and source identity are those recorded above.

| Template | Runtime bytes | Creation bytes | Runtime headroom | `STOP + creation` bytes | Storage-contract headroom |
| --- | ---: | ---: | ---: | ---: | ---: |
| Open | 15,304 | 18,030 | 9,272 | 18,031 | 6,545 |
| Fixed | 16,601 | 19,328 | 7,975 | 19,329 | 5,247 |
| Periodic | 19,271 | 21,998 | 5,305 | 21,999 | 2,577 |

Runtime and template storage each face the 24,576-byte
[EIP-170 limit](https://eips.ethereum.org/EIPS/eip-170).
[LibStoredInitCode](../../src/libraries/LibStoredInitCode.sol) creates the storage
contract with `creation length + 11` bytes of initialization code and returns
`STOP || creation`. The storage contract, rather than the final hook runtime,
is the tighter boundary for every current template.

The factory then copies that creation code and appends 96 bytes of constructor
encoding plus the exact supplied `args.length`; its assembly does not add a
separate padding allowance. Empty-args hook deployment lengths are 18,126,
19,424, and 22,094 bytes respectively. Against the 49,152-byte
[EIP-3860 initcode limit](https://eips.ethereum.org/EIPS/eip-3860), the remaining
constructor payload budgets are 31,026, 29,728, and 27,058 bytes. These are size
budgets, not promises that arbitrary provider payloads are semantically valid
or affordable to execute. Canonical factory/matrix tests exercise the real
stored-initcode deployment path for both factory types.

`sizes.json` contains all lengths, formulas, and creation/unpatched-runtime
SHA-256 identities. Its hash is
`d2809d6ef79b45b1ad13175c51ec2a33343ba74511b66df9310f9abb5992ad9c`.
M5 must remeasure compiled templates and exercise deployment, not infer size
savings from source deduplication.

## Operation gas baseline

These are measured callback trace entries from existing canonical tests,
not aggregate test-function gas. No measurement harness or production/test
source was added. Run each identified test with:

```sh
FOUNDRY_PROFILE=deploy forge test --match-contract '<suite>' \
  --match-test '<test name>' --block-timestamp 1724284800 \
  --fuzz-seed 0x5eed -vvvv
```

All selected tests have no fuzz arguments. The main trace receipt passed 17
tests across five suites; the cached-repeat supplement passed one production
matrix test. The initial attempt with an end-anchored name regex discovered no
tests and is excluded from measurements; the corrected selector and positive
test count are retained in `gas-trace-receipt.json`.

The measurement boundary matters:

- **Direct:** the bracketed gas on a direct test-to-hook callback. With the
  recorded `isolate=true`, this is an isolated top-level transaction boundary,
  including its transaction overhead. Storage warmth resets between such
  calls even when credential/proposal state persists. This is a comparison
  reference, not an estimate of the nested production hook cost.
- **Nested:** the bracketed gas on the hook callback inside the actual market/
  wrapper transaction. It includes the callback's nested calls, excluding the
  surrounding market/transaction setup. Warmth is determined by that exact
  enclosing transaction, including earlier policy queries and the already
  executing market. Do not mix this column with direct-call totals.

The [trace format](https://getfoundry.sh/forge/traces) identifies the measured
call and its children. Retain the same call boundary, fixture steps, compiler,
isolation setting, and state for comparisons; these numbers do not claim
whole-transaction fees or a normalized refund-adjusted cost. Provider cache
state and EVM storage warmth are separate concerns.

Test keys below use the exact baseline source and existing fixture setup.
Ordinals count calls to the named callback on that template within the test,
including rejected calls. The raw trace records every argument, market caller
prank, return/revert, event, provider call, and state snapshot.

| Key | Suite / test name |
| --- | --- |
| D | Each concrete `*TermHooksTest`: `test_onDeposit_EnforcesMinimumBlockAndCredentialPolicies` |
| T | Open/fixed: `test_onTransfer_EnforcesDisabledAndCredentialPolicies`; periodic: `test_onTransfer_EnforcesDisabledCredentialAndKnownLenderPolicies` |
| QO | `OpenTermHooksTest`: `test_onQueueWithdrawal_PreservesKnownAccessAndValidatesUnknownLenders` |
| QF | `FixedTermHooksTest`: `test_onQueueWithdrawal_EnforcesTermAndRequestedAccess` |
| QP | `PeriodicTermHooksTest`: `test_onQueueWithdrawal_ValidatesCredentialsAndPreservesKnownLenders` |
| A | `MarketConstraintHooksTest`: `test_onSetApr_CancelsOrExpiresAndRestoresOriginalReserveRatio` |
| AF | `FixedTermHooksTest`: `test_onSetApr_BlocksReductionDuringTermAndDelegatesAllowedChanges` |
| AP | `PeriodicTermHooksTest`: `test_aprReduction_EnforcesExecutionStateMachine` |
| AE | `PeriodicTermHooksTest`: `test_executePendingAnnualInterestBipsReduction_UsesTheSameGates` |
| AI | `PeriodicTermHooksTest`: `test_onSetAnnualInterestBips_IncreasesAndEqualityDelegateAndCancelPrecisely` |
| CF | `FixedTermHooksTest`: `test_onCloseMarket_EnforcesEarlyClosurePolicyAndUpdatesTerm` |
| CP | `PeriodicTermHooksTest`: `test_onCloseMarket_OpensWithdrawalsAndHandlesProposalLifecycle` |
| W | `Wildcat4626WrapperIntegrationTest`: `test_depositAndMintIgnoreLocalBlockForRegisteredWrapperAcrossBuiltInHooks` |
| M | `ProductionMatrixScenariosTest`: `test_minimumDepositOrderingAndLiveUpdatesUseProductionComposition` |

| Scenario / state | Call selector within test | Boundary | Measured gas |
| --- | --- | --- | ---: |
| Positive minimum 100, no credential/access requirement; floor-scaled tender at minimum. Scale factor RAY for open/fixed, 1.5 RAY for periodic. | D, `onDeposit` #2, open / fixed / periodic | Direct | 32,456 / 32,667 / 32,822 |
| First credential-data entry, minimum 0, access required, scaled amount 1; provider validates supplied bytes and lender becomes known. | D, `onDeposit` #5, open / fixed / periodic | Direct | 89,169 / 89,381 / 89,656 |
| Cached credential granted before first market entry; minimum 0, amount 1, empty hook data. | QO, open `onDeposit` #1 | Direct | 56,610 |
| Repeat known-lender deposit, cached credential, minimum reduced to 0, amount 1e18, scale RAY; real standard periodic market. | M, periodic `onDeposit` #4 | Nested | 11,499 |
| Unknown recipient, transfer access required, amount 1, supplied valid credential; becomes known. | T, `onTransfer` #3, open / fixed / periodic | Direct | 90,507 / 90,719 / 91,114 |
| Known recipient after credential revocation; amount 1, empty hook data. | T, `onTransfer` #4, open / fixed / periodic | Direct | 29,974 / 30,185 / 30,472 |
| Canonical wrapper locally blocked and not known; real wrapper deposit transfers backing without credential data. | W, `onTransfer` #1, open / fixed / periodic | Nested | 4,348 / 4,559 / 4,846 |
| Open queue, known lender after revocation, amount 1. | QO, `onQueueWithdrawal` #1 | Direct | 31,784 |
| Fixed queue at maturity, access not requested. | QF, `onQueueWithdrawal` #2 | Direct | 29,731 |
| Periodic queue in open window, known lender after revocation. | QP, `onQueueWithdrawal` #3 | Direct | 32,529 |
| APR 1,000 to 700, reserves 2,000 to 6,000; first temporary activation. | A, open ordinary APR callback #1 | Direct | 50,943 |
| APR restored to 1,001; cancel temporary state, return original reserves 2,000. | A, open ordinary APR callback #2 | Direct | 32,032 |
| APR remains 700 at temporary expiry; restore reserves 2,000. | A, open ordinary APR callback #4 | Direct | 32,020 |
| Fixed reduction 100 to 99 before maturity; rejected by term guard. | AF, ordinary APR callback #1 | Direct | 27,221 |
| Fixed increase 100 to 101, supplied reserves 500 ignored; return 1,000. | AF, ordinary APR callback #2 | Direct | 30,209 |
| Fixed reduction 100 to 99 at maturity; activate shared temporary state, reserves remain 1,000. | AF, ordinary APR callback #3 | Direct | 53,007 |
| Periodic matured exact proposal 1,000 to 900, no unpaid withdrawals; preserve reserves 1,000. | AP, ordinary APR callback #6 | Direct | 36,078 |
| Periodic matured proposal 1,000 to 900 through dedicated APR-only route; no unpaid withdrawals. | AE, `executePendingAnnualInterestBipsReduction` #3 | Direct | 34,616 |
| Periodic APR increase cancels pending proposal then uses shared strategy. | AI, ordinary APR callback #1 | Direct | 37,641 |
| Fixed permitted early closure moves maturity to now. | CF, `onCloseMarket` #1 | Direct | 31,924 |
| Periodic closure cancels pending proposal and marks schedule closed. | CP, `onCloseMarket` #1 | Direct | 37,244 |

These are configuration-specific examples, not exhaustive performance bounds.
M5 should retain equivalent scenarios if common tests are reorganized, without
maintaining a second legacy implementation. Final costs of access adapters and
policy integration remain to be measured on the actual refactor.

| Raw evidence | SHA-256 |
| --- | --- |
| `gas-traces.log` | `d24c6ae0096cfbb3afc1a0382194e3f68afddbdae4d55d7932cd2864e08fa5c5` |
| `gas-cached-deposit.log` | `79dde3251c40d1710a150709aa51226bbeac5341e48753bd1980fb5d2c86dd8b` |
| `gas-calls.json` (indexed calls, results, boundaries, source lines) | `d4a060085b02dcc97123de791f64a8e8195b4f885627edd264327a3a6796909a` |
