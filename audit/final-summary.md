# Final Audit Summary

## Scope

- Repository: `v2-protocol`
- Branch: `feat/periodic_hooks`
- Reviewed head: `629e7a7`
- Baseline: `origin/main` merge-base `c7be4039f8f383a9dda4e45f63331c17d63f9ed9`
- Primary feature diff: `src/access/PeriodicTermHooks.sol`, `test/access/PeriodicTermHooks.t.sol`, `test/shared/mocks/MockPeriodicTermHooks.sol`
- Solidity surface reviewed: `src/**/*.sol`, excluding SphereX warnings/findings as requested because that code is third-party/out of scope.

## Result

No confirmed Critical issue was identified. After comparing the new audit register
against the previous CAF report and remediation results, most High/Medium items are
known CAF root causes rather than new findings. The CAF remediation statuses are
cross-branch dispositions: findings marked fixed in
`audit/previous/caf-remediation-results-20260507.md` can still be present on this
branch until those fixes are merged or imported.

Current triage count after the `M-03` policy decision and `L-02`/`L-03`/`HARD-01` fixes:

- 0 substantive new findings remain open.
- 2 substantive new findings were fixed on this branch: `L-02`, `L-03`.
- 2 known CAF findings remain relevant to Periodic until their remediation branch is
  imported: `M-05`, `L-01`.
- 4 valid documentation, monitoring, known-behavior, or operational items hold up:
  `M-03`, `DOC-01`, `MON-01`, `SUP-01`.
- 1 hardening item was fixed on this branch: `HARD-01`.
- 6 items are CAF duplicates, accepted policy decisions, out of scope, or known tooling
  gaps: `H-01`, `M-01`, `M-02`, `M-04`, `QA-01`, `TOOL-01`.

The new `PeriodicTermHooks` windowing design is otherwise internally consistent
with the existing hook model: queue-withdrawal, close-market, and APR/reserve-ratio
hooks are required; withdrawals are blocked outside windows unless the market is
closed; APR reductions require a prior proposal and a completed response window;
paid withdrawals are moved to `normalizedUnclaimedWithdrawals` and no longer accrue
interest.

## Confirmed Findings

| ID | Severity | Disposition | Summary |
| --- | --- | --- | --- |
| H-01 | High | Known CAF-05; fixed elsewhere | Push role providers can grant future-dated credentials that bypass configured TTL limits. |
| M-01 | Medium | Known CAF-01; fixed elsewhere | Half-up scaled conversions can overcredit deposits, transfers, allowances, and withdrawal payment accounting. |
| M-02 | Medium | Known CAF-02; accepted policy boundary | Fee-on-transfer or deflationary assets can make market accounting overstate received repayments/deposits/fees. |
| M-03 | Medium | Intended wrapper composability; documented in KB | ERC4626 wrapper shares can circulate without re-running market role-provider checks once the wrapper is an approved market-token recipient. |
| M-04 | Medium | Known CAF-06; accepted behavior | Disabled hook templates can still be used indirectly by deploying new markets through existing hook instances. |
| M-05 | Medium | Known CAF-03; relevant until fix imported | Sanctions `nukeFromOrbit` can be blocked by fixed/periodic term withdrawal hooks. |
| L-01 | Low | Known CAF-04; relevant until fix imported | Withdrawal-gated markets can accept deposits from accounts that may later be unable to queue withdrawals. |
| L-02 | Low | Fixed on this branch | `MarketLens.getHooksInstancesForBorrower` allocated a zero-length array then indexed by hook-instance count. |
| L-03 | Low | Fixed on this branch | Lens types omitted `PeriodicTermHooks`, causing periodic markets/instances to be reported as unknown or incomplete. |
| QA-01 | Low | Third-party/out of scope | Full `forge test --summary` fails because inherited ERC4626 standard tests use removed Foundry `testFail*` methods. |
| DOC-01 | Low | Valid documentation item | `PeriodicTermHooks` lacks matching production docs in `docs/hooks/`. |
| MON-01 | Low | Deferred to coordinated hook-template refresh | Periodic hook market events follow the existing open/fixed pattern and do not index `market`, reducing off-chain monitoring ergonomics. |
| TOOL-01 | Low | Known tooling gap | Full Slither/MCP and Forge coverage are blocked by parser/tooling limitations; targeted analysis was used instead. |
| SUP-01 | Informational | Valid operational hardening item | Semgrep found one deployment-script `curl | bash` pattern. This is not a Solidity runtime issue. |
| HARD-01 | Informational | Fixed on this branch | `HooksFactory._deployMarket` ignored the returned CREATE2 address instead of asserting it matched the precomputed market address. |

## Verification

- `forge build src/access/PeriodicTermHooks.sol --deny never`: pass; one expected timestamp lint warning.
- `forge test --match-path test/access/PeriodicTermHooks.t.sol --summary`: 108 passed, 0 failed.
- `forge test --match-path test/market/FixedTermEquivalenceTests.t.sol --summary`: fixed-term equivalence suites passed.
- `forge test --summary`: 903 passed, 2 failed; both failures are inherited ERC4626 `testFail*` methods.
- `forge test --no-match-path test/vault/Wildcat4626WrapperStandard.t.sol --summary`: all displayed suites passed with 0 failures.
- `forge test --match-path test/lens/MarketLens.t.sol -vvv`: 12 passed, 0 failed.
- `forge test --match-path test/HooksFactory.t.sol -vvv`: 31 passed, 0 failed.
- Semgrep auto scan: one low-signal script finding, no Solidity runtime findings.
- Slither full repository run: blocked by dynamic library-function casts. Targeted Slither runs completed for periodic hooks, base access controls, hooks factory, and wrapper.
- X-ray coverage: blocked first by the SphereX `locals` parser issue, then by a Yul stack-depth failure under `--ir-minimum`.

## Working List

Use this queue for follow-up work on this branch.

### Known CAF items to import or defer

1. Import/adapt the CAF-03 `nukeFromOrbit` remediation for withdrawal-restricted
   hooks, including Periodic.
2. Import/adapt the CAF-04 open-entry/gated-withdrawal remediation for Periodic if
   the separate remediation branch does not already cover the new hook.

### Docs, monitoring, and operational hardening

3. `L-02` is fixed on this branch with a one-line allocation correction and a
   focused `MarketLens` regression test.
4. `L-03` is fixed on this branch with `PeriodicTermHooks` lens kind/support,
   periodic schedule/window/access fields, and focused `MarketLens` regression
   tests.
5. `M-03` is closed as intended wrapper composability. The durable known-issue
   wording lives in `kb/immunefi-scope/KNOWN_ISSUES_INTERNAL.md` as `WKI-030`.
6. Add production documentation for `PeriodicTermHooks`, including withdrawal
   windows, closed-market behavior, and APR reduction response windows.
7. Defer indexed `market` hook events to a coordinated hook-template refresh so
   open, fixed, and periodic hooks stay aligned with SDK/subgraph/frontend event
   decoding.
8. Replace or harden the deployment-script `curl | bash` pattern if that script is
   part of the supported operational path.
9. `HARD-01` is fixed on this branch with an explicit CREATE2 return-address
   assertion and a stale-init-code-hash regression test.

### No immediate action from this pass

10. Defer `H-01`, `M-01`, `M-02`, and `M-04` to their CAF dispositions.
11. Leave `QA-01` and `TOOL-01` out of scope for this branch unless the team chooses
    to clean up inherited tests or audit tooling separately.
