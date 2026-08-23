# Market borrower-transfer parity

Status: complete, including the wrapper handoffs in the production integration checkpoint.

## Family boundary

The legacy `WildcatMarketBorrowerTransferTest` has 37 entries in one full-stack market fixture.
Twenty-nine are market and borrower-identity behavior. The replacement maps those into ten composed
properties and adds one adversarial property for malformed registry return data. One production
Sentinel property covers the two market-withdrawal escrow entries, and three shared wrapper
integration properties close the remaining six. The market suite uses production ArchController,
borrower registry, sanctions Sentinel, OpenTerm hooks, and market code with artifact-backed
deployment.

| Behavior slice                                                   | Legacy entries | Replacement ownership            |
| ---------------------------------------------------------------- | -------------: | -------------------------------- |
| Request, replacement, cancellation, authority, and target checks |              7 | 3 market properties              |
| Direct-principal and borrower-account transition matrix          |              6 | 1 market property                |
| Same-account principal migration and pending binding             |              3 | 2 market properties              |
| Raw sanctions on transfer requests                               |              2 | 1 market property                |
| Acceptance identity and sanctions revalidation                   |              6 | 1 market property                |
| Operational-borrower and principal draw sanctions                |              1 | 1 market property                |
| Active, delinquent, and closed accounting preservation           |              3 | 1 market property                |
| Latest-target replacement fuzzing                                |              1 | 1 market property                |
| Lender namespace changes plus wrapper readiness                  |              2 | 1 wrapper integration property   |
| Market withdrawal escrow namespace and release                   |              2 | 1 market integration property    |
| Wrapper escrow namespace, release, and sweep authority           |              4 | 2 wrapper integration properties |
| **Total**                                                        |         **37** | **all mapped**                   |

The identity matrix covers direct principal to direct principal, direct principal to account,
same-principal account rotation, account to a new principal's account, and account back to a direct
principal. An account remains transferable after its factory is removed, but only the current
operational borrower gains market authority.

Same-account migration binds the principal resolved at request time. If the registry changes the
account again before acceptance, the market preserves the pending transfer and rejects it with both
principal values. Cancelling, requesting again, and accepting moves only the reserved borrower
slots; sequential accounting storage remains unchanged.

Sanctions checks use the production Sentinel and its raw sanctions-list dependency. Borrower
overrides do not permit a flagged operational account or principal to request a transfer or draw.
Acceptance rechecks the current principal, target account, target principal, direct-principal
registration, account-principal registration, and ambiguous identities. Lender overrides stay in
the same namespace across account rotation and move to the new principal's namespace after a
principal migration.

## Coverage and canonical result

The legacy fixed-seed oracle passes all 37 entries. The 12 market properties and three shared
wrapper-integration properties pass with the same timestamp, seed, and 1,000 fuzz runs. Focused
accurate coverage hits all 64 executable lines
and all 12 branches in the borrower-transfer region of `WildcatMarketBase`, including the two
low-level registry response-validation branches absent from the legacy suite.

The current market suite artifact is 32,451 bytes of initcode and 32,425 bytes of runtime bytecode.
The final family-wide comparison includes the wrapper integration artifact and its reusable support
contracts rather than pretending the six cross-boundary entries can be priced independently. See
`wildcat-4626-wrapper-integration.md` for that result.

The full replacement checkpoint is 560 tests across 36 suites with zero inherited entries,
718,635 bytes of test-side initcode, and 709,424 bytes of runtime bytecode. A forced canonical
compile-to-green takes 1m57.16s, including 114.03s in solc, with a 3,121,564 KiB RSS peak;
execution takes 1.84s.
