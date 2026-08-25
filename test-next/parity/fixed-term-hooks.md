# FixedTerm hooks parity

Status: all direct FixedTerm hook properties replaced; shared temporary-reserve-ratio transitions
are covered separately in `market-constraint-hooks.md`.

## Family boundary

This checkpoint covers all 41 properties declared in `test/access/FixedTermHooks.t.sol`. The 70
shared `BaseAccessControls` entries inherited by the legacy concrete suite remain represented once
by the completed base-access slice.

The fixture deploys the production `FixedTermHooks` artifact and mock role providers. The test
contract supplies only the factory callback and borrower-registration surface; no legacy fixture,
market, ArchController, sentinel, or hooks factory is imported.

| Direct behavior slice                                       | Legacy entries | Replacement entries |
| ----------------------------------------------------------- | -------------: | ------------------: |
| Provider initialization and failed creation                 |              4 |                   2 |
| Version, deployment config, and parameter constraints       |              3 |                   1 |
| Market creation, config matrix, batch reads, and admin move |             12 |                   3 |
| Minimum-deposit and fixed-term administration               |              9 |                   2 |
| Withdrawal gating and all unhooked callback errors          |              8 |                   2 |
| Disabled-transfer policy                                    |              1 |                   1 |
| APR changes during and after the term                       |              2 |                   1 |
| Early and disabled closure                                  |              2 |                   1 |
| **Direct-property total**                                   |         **41** |              **13** |
| Additional production-policy properties                     |              0 |                   2 |
| **Replacement total**                                       |         **41** |              **15** |

The runtime configuration matrix fuzzes requested deposit, withdrawal, and transfer access;
minimum deposit; transfer disablement; early closure; and term reduction together. It asserts the
difference between stored requested-access policy and the required callback flags returned to the
market. Fixed-term boundaries, missing and overflowing hook data, every setter rejection, exact
events, configuration preservation across administrator transfer, and unknown batch reads remain
explicit.

Withdrawal coverage preserves the pre-term gate, unrestricted post-term withdrawal, known-lender
continuity after credential revocation, and hooks-data validation for an unknown lender. APR
coverage preserves the pre-term reduction ban and the parent constraint-hook result after the term.
Closure is tested through both early-close permissions, the disabled path, and the elapsed-term
no-op.

The two additional properties exercise the complete deposit policy and every unrestricted
callback selector. Transfer access is also strengthened through unknown, credentialed, known,
revoked, blocked, and disabled recipients.

## Coverage and canonical result

Focused accurate coverage reports 100% lines, statements, branches, and functions for
`FixedTermHooks`. The completed temporary-reserve-ratio state machine is documented separately in
`market-constraint-hooks.md`.

All 15 properties pass at the fixed timestamp and seed. The combined provider-shape property and
seven-input market-configuration matrix each pass 1,000 fixed-seed fuzz runs.

| Test artifact                    | Initcode bytes | Runtime bytes | Test entries |
| -------------------------------- | -------------: | ------------: | -----------: |
| Legacy `FixedTermHooksTest`      |        158,407 |       153,629 |          111 |
| Replacement `FixedTermHooksTest` |         31,989 |        31,963 |           15 |

The legacy artifact includes all 70 inherited access-control properties. The byte counts are not
presented as a standalone reduction; the completed fair access-family comparison is recorded in
`periodic-term-hooks.md`.

The full replacement checkpoint is 476 tests across 32 suites with zero inherited entries,
525,268 bytes of test-side initcode, and 516,354 bytes of runtime bytecode. A forced canonical
compile-to-green took 93.21 seconds, including 90.80 seconds in solc, and peaked at 2,861,828 KiB
RSS.
