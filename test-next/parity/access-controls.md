# Base access-controls parity

Status: base slice complete; the full access-hooks comparison is recorded in
`periodic-term-hooks.md`.

## Property disposition

- All 70 properties declared by `test/access/BaseAccessControls.t.sol` have a replacement with the
  same test name in `test-next/access/BaseAccessControls.t.sol`.
- 66 retain the exact legacy ABI signature.
- Three caller/error properties drop fuzz arguments that the legacy bodies never read:
  - `test_createRoleProvider_CallerNotAdministrator`
  - `test_grantRole_ProviderNotFound`
  - `test_grantRoles_ProviderNotFound`
- `test_fuzz_getOrValidateCredential` replaces the 747-line legacy context builder with one
  explicit 12-scenario state machine. It covers cached credentials, hooks-data validation and
  pulls, previous-provider refresh, provider-list fallback, unknown/reverting/short-return
  providers, expiration, and credential clearing.
- `test_isMarketTransferRecipientAllowed` is one new property for the shared recipient-side
  wrapper-transfer gate. It covers unrestricted transfers, known and unknown lenders, blocked
  lenders, and a live pull-provider credential.

The legacy inheritance graph materializes these 70 shared properties in OpenTerm, FixedTerm, and
PeriodicTerm suites: 210 concrete entries. The replacement runs them once against a focused
`BaseAccessControls` harness: 70 concrete entries and zero inherited tests. The shared public
functions are non-virtual; hook constructors and genuinely hook-specific behavior remain separate
parity work.

The harness calls the production `_tryValidateAccess` and `_writeLenderStatus` path. It does not
carry a test-side copy of the storage and event logic.

## Canonical-profile result

| Measure                                             |            Legacy shared behavior | Replacement base slice |
| --------------------------------------------------- | --------------------------------: | ---------------------: |
| Legacy properties replaced                          |                                70 |                     70 |
| Additional coverage properties                      |                                 0 |                      1 |
| Concrete entries                                    |                               210 |                     71 |
| Inherited entries                                   |                               210 |                      0 |
| Replacement test contract initcode                  | n/a; mixed into three hook suites |           58,571 bytes |
| Replacement slice initcode, including harness/mocks |                               n/a |           73,662 bytes |
| Fixed-seed result                                   |         retained in legacy oracle |        71 / 71 passing |
| Accurate line coverage                              |   current legacy coverage blocked |                 96.28% |
| Accurate branch coverage                            |   current legacy coverage blocked |                 93.75% |
| Accurate function coverage                          |   current legacy coverage blocked |                   100% |

The legacy access family is 501,473 bytes of initcode, including 161 hook-specific test entries.
OpenTerm, FixedTerm, and PeriodicTerm are now replaced; see `periodic-term-hooks.md` for the fair
family comparison.

The replacement result uses official solc 0.8.25, via-IR, optimizer enabled at 44 runs, Cancun,
no bytecode hash, and no CBOR metadata. Accurate coverage uses the temporary SphereX workaround
described in `parity/README.md`; no coverage-only protocol patch is kept.
