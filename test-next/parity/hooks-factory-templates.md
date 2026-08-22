# Hooks factories parity

Status: complete.

## Family boundary

This family covers all 86 direct entries from `HooksFactoryTest` and
`HooksFactoryRevolvingTest`. One concrete suite runs both production factories at runtime, while
keeping standard/revolving-specific behavior explicit inside the same property matrix.

| Behavior slice                         | Legacy entries | Replacement entries |
| -------------------------------------- | -------------: | ------------------: |
| Construction and template management   |             25 |                   9 |
| Hook-instance deployment               |             10 |                   2 |
| Market-deployment happy paths          |              6 |                   2 |
| Market rejection and revolving parsing |             32 |                   8 |
| Market indexes and fee propagation     |             13 |                   4 |
| **Total**                              |         **86** |              **25** |

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

## Market indexes and protocol-fee propagation

Four final runtime-matrix properties replace the remaining 13 legacy entries. They preserve:

- template and instance market indexes, counts, ordering, bounded pages, clamping, and every
  empty-range shape
- full-list and paged protocol-fee propagation through real standard and revolving markets
- exact per-market fee-update events and untouched markets outside the selected page
- empty-template and empty-page no-ops, invalid range rejection, unknown-template rejection, and
  failed-market error normalization

## Canonical result

All 25 properties pass at the fixed timestamp and seed. The suite uses canonical production
factory artifacts, stored standard/revolving market initcode, the production ArchController and
borrower identity registry, and an OpenTerm hooks template.

| Dedicated family artifacts |  Legacy | Replacement |    Delta | Reduction |
| -------------------------- | ------: | ----------: | -------: | --------: |
| Initcode bytes             | 274,238 |      43,398 | -230,840 |    84.18% |
| Runtime bytes              | 245,720 |      43,363 | -202,357 |    82.35% |

The replacement total includes one 12-byte failure-template artifact; the legacy total includes
the same artifact compiled once for each factory suite.

The full replacement checkpoint is 434 tests across 29 suites with zero inherited entries,
436,794 bytes of test-side initcode, and 428,185 bytes of runtime bytecode. A forced canonical
compile-to-green took 83.28 seconds and peaked at 2,600,456 KiB RSS.

Forge's accurate-coverage mode cannot compile this production graph: its non-IR build is
stack-too-deep at `HooksFactoryRevolving.sol:882`, while `--ir-minimum` fails Yul stack
allocation. This is limited to the coverage-only compiler profile. The canonical via-IR suite is
green, and the temporary SphereX coverage patch was restored cleanly after both attempts.
