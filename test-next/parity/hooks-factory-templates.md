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

## Market deployment happy-path checkpoint

Two additional runtime-matrix properties replace six legacy happy-path entries. Existing-hook and
combined hook+market deployment now both run through production OpenTerm hooks and production
standard/revolving markets. They retain:

- exact CREATE2 prediction and returned market addresses
- all factory market/config/hook-data events plus the revolving commitment-fee event
- requested versus effective hook flags and forwarded hook data
- borrower and borrower-principal identity, token metadata, market parameters, sanctions
  sentinel, fee recipient, and initial protocol fee
- origination-fee transfer, template/instance market indexes, controller registration, and the
  revolving commitment fee

The successful combined path also proves the newly deployed hook is indexed under the caller and
used by the market in both factory variants.

## Market rejection checkpoint

Eight additional properties replace 32 legacy rejection and boundary entries. The matrix now
covers:

- borrower resolution, unknown hooks, caller-scoped salts, publicly reproducible nonzero salt
  predictions, blacklisted assets, and unchanged market indexes after rejection
- exact 63-byte name/symbol boundaries, overlong metadata, fee mismatch, duplicate CREATE2 salts,
  and the ordering required to reach each error
- continued market deployment through existing hooks after their template is disabled
- stale market-initcode hashes in both factories
- combined-deployment borrower, template, disabled-template, salt, and both fee mismatch shapes,
  including complete hook nonce/index rollback
- every revolving market-data error (empty, ABI-length mismatch, unsupported version, excessive
  commitment fee), validation before combined hook deployment, and the deployment-context-only
  commitment-fee getter

The replacement strengthens several single-factory legacy cases by running the same rejection
through both implementations and asserting state is unchanged after every failed path.

## Canonical result

All 21 properties pass at the fixed timestamp and seed. The suite uses canonical production
factory artifacts, stored standard/revolving market initcode, the production ArchController and
borrower identity registry, and an OpenTerm hooks template. Its current test contract emits 12,584
bytes of initcode and 12,558 bytes of runtime bytecode at the first checkpoint. After adding
hook-instance deployment, the suite plus its dedicated failure artifact emits 17,042 bytes of
initcode and 17,007 bytes of runtime bytecode. With the market happy paths included, it emits
25,048 bytes of initcode and 25,013 bytes of runtime bytecode. With the rejection matrix, the suite
plus failure artifact emits 36,364 bytes of initcode and 36,329 bytes of runtime bytecode. The
final family delta will be recorded after the remaining 13 market-pagination and protocol-fee
propagation entries are replaced.

The complete replacement checkpoint now has 430 tests across 29 suites, zero inherited entries,
429,760 bytes of test-side initcode, and 421,151 bytes of runtime bytecode.
