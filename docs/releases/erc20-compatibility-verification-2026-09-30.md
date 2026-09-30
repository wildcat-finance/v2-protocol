# ERC-20 compatibility stack verification

Observed 2026-09-30. This is a local mechanical verification receipt for the
named experimental stack, not a release approval, audit extension or deployment
attestation. No production source or test behavior changed in this pass.

## Identity

- Source/test commit: `ade86605a79eac916d6595ba7b4813398dd28a9e`.
- `src/` tree: `9e69ff0ce2be2e4ab61605a0b6a0eb453ed412f6`.
- Foundry: 1.8.3, commit `cae51ad458f6abb64852b7709eb784352429825d`.
- Solidity: 0.8.25; Cancun; via IR; optimizer runs 1 and the pinned Yul sequence;
  metadata hash and CBOR metadata disabled, as recorded in `foundry.toml`.
- Fuzz seed: `0x5eed`; configured fuzz runs 1,000; invariant runs 2,000,
  depth 30. No reduced test budgets or test exclusions were used for the full run.
- The four library gitlinks were initialized at their recorded commits:
  forge-std `b6a506db2262cad5ff982a87789ee6d1558ec861`, OpenZeppelin
  `fd81a96f01cc42ef1c9a5399364968d0e07e9e90`, Solady
  `2ba1cc1eaa3bffd5c093d94f76ef1b87b167ff3c`, and Solmate
  `1b3adf677e7e383cc684b5d5bd441da86bf4bf1c`.

The stack includes the still-paused withdrawal-counter and carry candidates.
Its successful tests do not resolve the
[counter-capacity concern](../security/withdrawal-counter-capacity-handoff.md).
That characterization is attached as evidence outside `test/`; it is not one
of the passing release-suite assertions.

## Results

| Check | Result |
| --- | --- |
| `forge test --summary --fuzz-seed 0x5eed` | 941 passed, 0 failed, 0 skipped; 85 suites. Includes deterministic production lifecycle scenarios and stateful invariants. |
| `FOUNDRY_PROFILE=deploy forge build --force --sizes src` | Passed. All production-source build runtime sizes are within EIP-170. |
| `forge test --match-path test/lens/MarketLensDeployment.t.sol --code-size-limit 24576 -vv` | Passed: real-limit deployment of the lens helpers/facade and market families. |
| Default/deployment artifact comparison | All 140 emitted production/dependency artifacts match in runtime, creation code and ABI. Constructor argument lengths are not included in the size table. |
| Documentation/evidence diff checks | Passed; the original counter characterization is retained byte-for-byte. |

An initial broad command, `forge build --skip test --skip script --sizes` under
the deployment profile, returned a size error for `LifecycleHandler` (47,918
bytes) and `MarketMatrixHandler` (24,788 bytes). Those invariant helpers do not
end in `.t.sol`, so the skip alias did not remove them. This was a test-helper
size error, not oversized production contracts. The passing production check
uses the explicit `src` scope; the strict deployment test separately checks
actual runtime enforcement.

| Contract | Runtime bytes | EIP-170 headroom |
| --- | --- | --- |
| Standard market | 23,998 | 578 |
| Revolving market | 24,554 | 22 |
| Standard factory | 16,568 | 8,008 |
| Revolving factory | 17,118 | 7,458 |
| Core lens | 21,431 | 3,145 |
| Aggregation lens | 22,306 | 2,270 |
| Live lens | 5,993 | 18,583 |
| Lens facade | 4,512 | 20,064 |

The revolving creation code is 26,256 bytes before constructor arguments.
The current wrapper/lens size and market measurements are source/build facts,
not proof that any deployed address uses these artifacts. A later production
edit needs renewed verification; the 22-byte revolving margin is specific to
this source and compiler configuration.

## What the integration matrix already covers

The earlier recommendation to test a complete lifecycle was too broad: that
lifecycle is already covered. The remaining distinction is the **asset behavior
axis**, rather than missing standard/revolving or hook-family coverage.

| Coverage | Existing evidence at this revision | Limit |
| --- | --- | --- |
| Standard/revolving x open/fixed/periodic lifecycle | `ProductionMatrixScenarios.test_deterministicLifecycleRunsAcrossProductionMatrix`, with real factories and built-in hooks. `MarketMatrixInvariantTest` checks supply, claims, fees, principal, utilization, withdrawal gates, sanctions and no unexpected arithmetic panic. | Both matrix fixtures use ordinary `MockERC20` assets; the asset implementation is not a varied axis. |
| No-return transfers | `LibERC20Test.test_safeTransfer_NoReturnData` and `test_safeTransferFrom_NoReturnData`. | Library-level call spies; no balance-accounting no-return asset through a complete market lifecycle. |
| False-returning/reverting token transfers | Transfer-library and individual market tests; `MarketSurplusTest` exercises borrower-recipient rejection in both market types, failed recovery rollback, lender settlement and recovery after lifting a restriction. | Targeted paths, primarily open-term fixtures; not every token restriction through every matrix cell. |
| Zero-rejecting transfers | `ZeroValueTransferReviewTest` covers both real factories and both deployment routes, zero-call avoidance and successful positive fees. | Origination-fee token behavior, not the whole underlying-asset lifecycle; optional `borrow(0)`, empty rescue and empty escrow calls retain their stated limits. |
| Asset pause/blocklist and restoration | Recipient-rejection scenarios cover related transfer failures; ArchController asset blacklisting is tested separately. | No dedicated token-wide pause fixture across the complete matrix. ArchController blacklisting is not a token-originated restriction. |

The narrow outstanding coverage opportunities are an honest balance-accounting
no-return token across the lifecycle, and pause/recipient-restriction failure
and recovery cases. They are coverage observations, not newly demonstrated
protocol defects or an instruction to rewrite the existing matrix. Unsupported
rebasing, fee-on-transfer and dishonest accounting remain outside this pass.

## Sepolia and mainnet scope

The four `TODO FOR MAINNET` parameters in `PeriodicTermPolicy.sol` are being
settled with the team. The user explicitly confirmed on 2026-09-30 that their
mainnet finalization is not a prerequisite for a Sepolia deployment. This
receipt leaves those values unchanged and records verification of the current
ones. Final mainnet source, review scope, inventory and ceremony qualification
remain separate release work.

## Retained logs

Full logs and the artifact comparison are retained locally under
`artifacts/protocol-signoff-2026-09-30/` in the protocol evidence collection.
The receipt travels in Git; external local logs do not automatically travel
with a pushed branch. SHA-256 identities:

- Full suite: `0958a4fc12867b2a891a8ad063e84c28bbc6eab90a99cc5a5a331c467f4431f0`.
- Production deployment build: `7a72ab338deb15fafe49927d9e5fbf14f64316ea96a53a7c560c038e643443a8`.
- Strict deployment test: `0c844c4d0cf6886a7b742533b1a39bb5bf0ee53314e91e6ea57087fdd3d3da01`.
- Sizes/profile comparison: `0912e025f54ee5159b482c8023f93a42a4fff737d7502b56bd258f7289217190`.
