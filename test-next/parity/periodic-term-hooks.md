# PeriodicTerm hooks parity

Status: all direct PeriodicTerm hook properties replaced; the complete access-hooks family is now
available for a fair comparison.

## Family boundary

This checkpoint covers all 93 properties declared in `test/access/PeriodicTermHooks.t.sol`. The
70 shared `BaseAccessControls` entries inherited by the legacy concrete suite remain represented
once by the completed base-access slice.

The replacement deploys the production `PeriodicTermHooks` artifact, real mock role providers,
and a 96-byte APR-market mock. The test contract supplies only the factory callback and borrower
registration surface. It does not import the legacy fixture or deploy a Wildcat market,
ArchController, sanctions sentinel, or hooks factory.

| Direct behavior slice                                              | Legacy entries | Replacement entries |
| ------------------------------------------------------------------ | -------------: | ------------------: |
| Existing, new, mixed, and failed provider initialization           |              4 |                   2 |
| Metadata, deployment config, template version, and constraints     |              4 |                   1 |
| Market creation, schedule validation, config, reads, and authority |             16 |                   5 |
| Withdrawal windows, queue access, and closure                      |             17 |                   5 |
| Deposit and minimum-deposit policy                                 |              9 |                   2 |
| Transfer policy                                                    |              5 |                   1 |
| Unrestricted callback                                              |              1 |                   1 |
| APR proposal authorization, timing, getters, and overwrite         |             15 |                   3 |
| APR execution gates, expiry, cancellation, and permissionless path |             22 |                   3 |
| **Direct-property total**                                          |         **93** |              **23** |

The runtime market-configuration matrix keeps requested deposit, queue-withdrawal, and transfer
access separate from the callback flags forced by the template. It also covers minimum-deposit
auto-enablement, disabled transfers, the invalid withdrawal-access combinations, the compact
`uint96` storage boundary, and every accepted/rejected schedule edge.

Window behavior is checked at the first start, last open second, exact close, recurring periods,
past schedules, deployment during an active recurring window, market closure, and 1,000
fixed-seed fuzzed period/offset combinations. Queue access uses actual credentials and a lender
made known through a production deposit path; it does not write hook storage through a test-only
setter.

The APR properties preserve the complete proposal state machine:

- administrator, hooked-market, open-window, closed-market, range, and strict-reduction gates;
- the next scheduled response window before the first window and after missed periods;
- exact proposal, cancellation, execution, and no-event behavior;
- proposal replacement and both public getter shapes;
- missing, mismatched, early, non-reducing, unpaid-withdrawal, and expired execution rejections;
- execution at the last valid second through the borrower callback;
- permissionless execution through the market callback;
- reserve-ratio preservation, proposal deletion, and parent-hook delegation for equal/increased
  APRs.

The replacement strengthens the direct legacy file by checking scaled minimum-deposit rounding,
every unrestricted callback selector, both transfer-policy queries, and actual credential-to-known
lender continuity.

## Coverage and canonical result

Focused accurate coverage reports 100% lines, statements, branches, and functions for
`PeriodicTermHooks`. `MarketConstraintHooks` remains intentionally partial until its shared
temporary-reserve-ratio state machine is migrated.

All 23 properties pass at the fixed timestamp and seed. Provider construction, market
configuration, window/closed-state behavior, strict APR reduction, and response-window selection
each run 1,000 fixed-seed fuzz cases.

| Test artifact                       | Initcode bytes | Runtime bytes | Test entries |
| ----------------------------------- | -------------: | ------------: | -----------: |
| Legacy `PeriodicTermHooksTest`      |        196,195 |       191,417 |          163 |
| Replacement `PeriodicTermHooksTest` |         48,877 |        48,851 |           23 |

The legacy artifact includes all 70 inherited access-control properties. The replacement APR
market mock adds 195 bytes of initcode and 96 bytes of runtime bytecode.

With the base, OpenTerm, FixedTerm, and PeriodicTerm slices complete, the fair access-family
comparison is:

| Access-family measure |  Legacy | Replacement |         Difference |
| --------------------- | ------: | ----------: | -----------------: |
| Concrete test entries |     371 |         124 |     -247 (-66.58%) |
| Inherited entries     |     210 |           0 |       -210 (-100%) |
| Test-side initcode    | 501,473 |     181,342 | -320,131 (-63.84%) |
| Runtime bytecode      | 486,887 |     178,301 | -308,586 (-63.38%) |

The replacement totals conservatively include its base harness, provider factory, providers, and
APR-market support artifacts. The legacy total is the previously recorded three concrete hook
suites plus their access-file support artifacts.

The full replacement checkpoint is 499 tests across 33 suites with zero inherited entries,
574,340 bytes of test-side initcode, and 565,301 bytes of runtime bytecode. A forced canonical
compile-to-green took 97.25 seconds, including 95.11 seconds in solc, and peaked at 2,748,736 KiB
RSS.
