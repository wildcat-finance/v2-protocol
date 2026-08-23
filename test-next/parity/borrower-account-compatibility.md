# Borrower-account compatibility parity

Status: replaced.

## Boundary

`BorrowerAccountCompatibilityTest` checks calls made by a registered smart-account borrower after
origination. It uses a minimal native `test-next` account whose only policy is that the registry's
current principal may execute calls. The old fixture and its test contracts are not imported.

The production ArchController, identity registry, both hooks factories, all three built-in hook
types, standard and revolving markets, sanctions Sentinel, and role-provider machinery are composed
through the artifact-backed production matrix fixture.

## Property disposition

| Frozen behavior group                                           | Entries | Replacement owner                                                                                |
| --------------------------------------------------------------- | ------: | ------------------------------------------------------------------------------------------------ |
| Account execution and principal policy across the six cells     |       6 | One six-cell runtime property                                                                    |
| Credentialed borrow across standard and revolving markets       |       2 | One two-factory account/principal-migration property                                             |
| Shared provider reused across account-owned markets             |       1 | The six-cell property attaches and updates one provider across every production composition      |
| Hooks then market and market-plus-hooks origination             |       1 | `BorrowerAccountOriginationTest`                                                                 |
| Provider creation during hook deployment                        |       1 | Hook constructor and role-provider-factory owners plus `BorrowerAccountOriginationTest` identity |
| Providerless hook configured after deployment                   |       1 | Base access-control/hook owners plus `BorrowerAccountOriginationTest` identity                   |
| Standard and revolving account-operated lifecycle               |       2 | One two-market lifecycle property                                                                |
| Market and wrapper authority after account rotation             |       1 | `Wildcat4626WrapperIntegrationTest`                                                              |
| Origination fees paid from the account                          |       1 | `BorrowerAccountOriginationTest`                                                                 |
| Salt bound to the operational account rather than its principal |       1 | One two-factory negative property                                                                |
| Only the registry's current principal may execute               |       1 | Deterministic negative assertion in the six-cell property                                        |
| **Total**                                                       |  **18** | **Four new compatibility properties plus existing focused owners**                               |

The six-cell property keeps operational and policy authority separate: the account owns market
actions, the principal administers hooks, and an unrelated caller cannot use the account. It also
proves provider revocation affects live deposits in every built-in hook/factory pairing.

The lifecycle property sends the draw to the account, forwards it to the principal, returns and
approves funds through the account, repays, and closes both market implementations. The revolving
path additionally ends with zero drawn principal.

The credentialed-borrow property deliberately uses a small test hook because no current built-in
hook gates borrowing this way. It protects future hook extensibility by proving the callback sees
the operational account and its current market principal, continues across same-principal account
rotation, rejects a stale principal after registry migration, and accepts the new principal after
the market identity is refreshed. Both production factories run the same property.

## Focused result

All four properties pass under the canonical via-IR profile. The initial two-file compile took
26.16 seconds; after fixing template storage wiring, the complete suite executes in 5.75
milliseconds.
