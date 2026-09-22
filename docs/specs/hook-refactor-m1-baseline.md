# M1 baseline: existing hook templates

- Source: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c` on `feat/tranching_support`.
- Captured: 2026-09-22 UTC.
- Execution status: identity, compatibility inventory, and required test runs
  complete; size/gas measurements follow in M1-03. See the [tracker](hook-refactor-m1-tracker.md).
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
