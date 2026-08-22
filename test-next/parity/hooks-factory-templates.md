# Hooks factory template-management parity

Status: standard and revolving factory construction, registration, template administration, fee
configuration, and template pagination are complete. Hook-instance and market-deployment behavior
remain in progress in the same replacement suite.

## Family boundary

This checkpoint covers 25 entries from `HooksFactoryTest` and `HooksFactoryRevolvingTest`: the
shared template state machine, both factories' constructor/registration wiring, and template-list
pagination. It does not yet claim full parity for either legacy factory suite.

## Property disposition

Nine properties run both production factories at runtime rather than compiling their shared
behavior into separate suites.

| Legacy behavior group                                  | Entries | Replacement entries |
| ------------------------------------------------------ | ------: | ------------------: |
| Constructor identity and ArchController registration   |       1 |                   1 |
| Add-template state/events and valid fee boundaries     |       2 |                   1 |
| Add-template owner and duplicate rejection             |       4 |                   1 |
| Add-template invalid fee configurations                |       2 |                   1 |
| Fee-update state and events                            |       2 |                   1 |
| Fee-update owner/not-found/invalid fee rejection       |       6 |                   1 |
| Permanent disable state, events, and retained metadata |       2 |                   1 |
| Disable owner/not-found rejection                      |       4 |                   1 |
| Template pagination, clamping, and empty ranges        |       2 |                   1 |
| **Total**                                              |  **25** |               **9** |

The replacement retains every factory event and error selector, all four invalid fee shapes,
zero-fee and maximum-fee boundary configurations, template indexes/order, permanent disable
behavior, and all pagination edge cases. It also makes the standard factory's constructor wiring
explicit rather than relying on assertions buried in legacy `setUp`.

## Canonical result

All nine properties pass at the fixed timestamp and seed. The suite uses canonical production
factory artifacts, stored standard/revolving market initcode, the production ArchController and
borrower identity registry, and an OpenTerm hooks template. Its current test contract emits 12,584
bytes of initcode and 12,558 bytes of runtime bytecode; the final family delta will be recorded
after the remaining 61 legacy factory entries are replaced.

The complete replacement checkpoint now has 418 tests across 29 suites, zero inherited entries,
405,980 bytes of test-side initcode, and 397,380 bytes of runtime bytecode.
