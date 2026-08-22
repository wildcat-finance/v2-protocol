# Hooks factory template-management parity

Status: standard and revolving factory construction, registration, template administration,
hook-instance deployment, fee configuration, and template pagination are complete. Market
deployment and fee propagation remain in progress in the same replacement suite.

## Family boundary

This checkpoint covers 25 entries from `HooksFactoryTest` and `HooksFactoryRevolvingTest`: the
shared template state machine, both factories' constructor/registration wiring, and template-list
pagination. A second checkpoint covers all ten direct hook-instance deployment entries. It does
not yet claim full parity for either legacy factory suite.

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

## Hook-instance deployment checkpoint

Two additional runtime-matrix properties replace ten legacy entries:

- the successful path preserves CREATE2 deployment, resolved administration, template and
  administrator indexes, compatibility aliases, deployment nonces, hook name/version metadata,
  and the initial pull/push role-provider snapshot
- the rejection matrix preserves borrower approval ordering, missing and disabled templates,
  constructor failure normalization, exact error selectors, and unchanged indexes/nonces after
  every failed attempt

The replacement uses a real OpenTerm hooks template with one pull and one push provider, so the
constructor-argument and metadata path is asserted against production hook behavior in both
factory implementations. The failure path uses one minimal reverting initcode artifact.

## Canonical result

All 11 properties pass at the fixed timestamp and seed. The suite uses canonical production
factory artifacts, stored standard/revolving market initcode, the production ArchController and
borrower identity registry, and an OpenTerm hooks template. Its current test contract emits 12,584
bytes of initcode and 12,558 bytes of runtime bytecode at the first checkpoint. After adding
hook-instance deployment, the suite plus its dedicated failure artifact emits 17,042 bytes of
initcode and 17,007 bytes of runtime bytecode. The final family delta will be recorded after the
remaining 51 legacy factory entries are replaced.

The complete replacement checkpoint now has 420 tests across 29 suites, zero inherited entries,
410,438 bytes of test-side initcode, and 401,829 bytes of runtime bytecode.
