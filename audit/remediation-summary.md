# Periodic Hooks Remediation Summary

Date prepared: 2026-05-20

Branch: `feat/periodic_hooks`

Companion summary: `audit/final-summary.md`

## Contents

- [Status Snapshot](#status-snapshot)
- [Remediation Table](#remediation-table)
- [Verification](#verification)
- [Remaining Follow-Up](#remaining-follow-up)

## Status Snapshot

| Category | Count | Items |
| --- | ---: | --- |
| Substantive new findings fixed on this branch | 2 | `L-02`, `L-03` |
| Substantive new findings still open | 0 | None |
| Known CAF fixes still to import/defer | 2 | `M-05`, `L-01` |
| Accepted or documented behavior | 2 | `M-03`, `M-04` |
| Hardening items fixed on this branch | 1 | `HARD-01` |
| Out of scope or tooling-only | 2 | `QA-01`, `TOOL-01` |
| Operational/docs follow-up | 3 | `DOC-01`, `MON-01`, `SUP-01` |

## Remediation Table

| ID | Severity | Status | Remediation / Decision | Verification / Note |
| --- | --- | --- | --- | --- |
| `M-03` | Medium | Documented / accepted | ERC4626 wrapper share transferability is intended composability; sanctions and unwrap paths still rely on market-token transfer restrictions. | Added durable known-issue wording as `WKI-030` in `kb/immunefi-scope/KNOWN_ISSUES_INTERNAL.md`. |
| `L-02` | Low | Fixed | Corrected `MarketLens.getHooksInstancesForBorrower` array allocation to use the borrower hook-instance count. | Added focused `MarketLens` regression coverage; lens suite passes. |
| `L-03` | Low | Fixed | Added `PeriodicTermHooks` lens kind/support and exposed periodic schedule, window, access, and closed-state fields. | Added periodic market-data and borrower-instance regression tests; lens suite passes. |
| `M-05` | Medium | Deferred / known CAF | Sanctions `nukeFromOrbit` can be blocked by withdrawal-restricted hooks until the CAF-03 remediation is imported/adapted. | Fix exists on another branch; intentionally deferred from this feature branch. |
| `L-01` | Low | Deferred / known CAF | Open-entry with gated withdrawals remains a known CAF-04 configuration trap until the separate remediation is imported/adapted for Periodic if needed. | Fix exists on another branch; intentionally deferred from this feature branch. |
| `MON-01` | Low | Deferred | Periodic events keep the same non-indexed `market` pattern as open/fixed hooks. Indexed hook events should be handled as an all-hooks 2.5 template/SDK/subgraph/frontend change. | No event-signature change on this branch. |
| `DOC-01` | Low | Open docs item | Production docs still need a `PeriodicTermHooks` section covering windows, closed-market behavior, and APR reduction response windows. | Documentation follow-up; no protocol test required. |
| `SUP-01` | Informational | Operational follow-up | Semgrep flagged one deployment-script `curl \| bash` pattern. Not a Solidity runtime issue. | Harden only if the script remains part of supported ops flow. |
| `H-01` | High | Known CAF | Future-dated push credential TTL bypass is a CAF-05 finding fixed elsewhere. | Defer to CAF remediation branch/import. |
| `M-01` | Medium | Known CAF | Scale-factor rounding consistency is a CAF-01 finding fixed elsewhere. | Defer to CAF remediation branch/import. |
| `M-02` | Medium | Accepted policy boundary | Fee-on-transfer and other nonstandard ERC20 behavior remains an asset-listing policy boundary. | No code remediation planned for this branch. |
| `M-04` | Medium | Accepted behavior | Disabled templates block new hook instances only; existing hook instances can still deploy markets. | Matches Wildcat's immutable deployed-instance model. |
| `QA-01` | Low | Out of scope | Full test summary still reports inherited third-party ERC4626 `testFail*` failures. | Third-party test issue; no local remediation. |
| `TOOL-01` | Low | Tooling gap | Full Slither/MCP and coverage workflows remain blocked by known parser/tooling limitations. | Targeted analysis was used instead. |
| `HARD-01` | Informational | Fixed | `HooksFactory._deployMarket` now asserts the returned CREATE2 deployment address matches the precomputed market address. | Added stale-init-code-hash regression coverage. |

## Verification

| Command | Result |
| --- | --- |
| `forge build src/access/PeriodicTermHooks.sol --deny never` | Pass; one expected timestamp lint warning. |
| `forge test --match-path test/access/PeriodicTermHooks.t.sol -vvv` | 109 passed, 0 failed; known SphereX parser warning still prints. |
| `forge test --match-path test/market/FixedTermEquivalenceTests.t.sol --summary` | Fixed-term equivalence suites passed. |
| `forge test --match-path test/lens/MarketLens.t.sol -vvv` | 12 passed, 0 failed; known SphereX parser warning still prints. |
| `forge test --match-path test/HooksFactory.t.sol -vvv` | 31 passed, 0 failed; known SphereX parser warning still prints. |
| `forge test --no-match-path test/vault/Wildcat4626WrapperStandard.t.sol --summary` | Displayed suites passed with 0 failures. |
| `forge test --summary` | 903 passed, 2 failed; both failures are inherited ERC4626 `testFail*` methods. |

## Remaining Follow-Up

| Priority | Item | Target |
| --- | --- | --- |
| P1 | Import/adapt CAF-03 `nukeFromOrbit` remediation for withdrawal-restricted hooks, including Periodic. | Separate CAF remediation import. |
| P1 | Import/adapt CAF-04 open-entry/gated-withdrawal remediation for Periodic if the merged branch does not already cover it. | Separate CAF remediation import. |
| P2 | Add production docs for `PeriodicTermHooks`. | Docs update before team-facing release notes. |
| P2 | Revisit indexed hook events as an all-hooks template refresh. | 2.5 hook-template, SDK, subgraph, and frontend coordination. |
| P3 | Harden the `curl \| bash` deployment-script pattern if it is supported ops surface. | Ops/scripts cleanup. |
