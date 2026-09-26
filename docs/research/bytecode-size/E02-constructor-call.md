# E02: bounded borrower-registration query

Source parent: `2389da5`. Settings: canonical runs 44, default Yul optimizer.
No dependency on E01 compiler variants.

Hypothesis: replacing the constructor's general Solidity external-call encoder
and decoder with a one-word staticcall can shrink creation code. This revisits
G-41 from the older gas branch, adding explicit address-argument cleanup.

Implemented `LibFixedCall.readBool` and used it only for constructor borrower
registration. A zero principal still short-circuits before the query. Identity
registry validation, engine initialization, and every other constructor check
remain in place. Reverts bubble unchanged; short or dirty boolean returns revert;
valid trailing data is accepted. Success copies only the return word.

| Target           | Before creation | After creation | Saved | Runtime change |
| ---------------- | --------------: | -------------: | ----: | -------------: |
| Standard market  |          26,516 |         26,395 |   121 |              0 |
| Revolving market |          27,167 |         27,050 |   117 |              0 |

Other measured targets are byte-for-byte unaffected. Complete ABIs and normalized
storage layouts match E00. [All sizes](./results/e02.json).

Validation: **132 tests passed**, including five new differential tests against
Solidity's actual decoder. Coverage includes all 0–31-byte returns, arbitrary
return/revert data, valid trailing bytes, dirty booleans, dirty high argument
bits and an empty-code target. Fuzz tests use 1,000 cases with seed `0x5eed`.
Existing market constructor, repayment, deadline and revolving tests also pass.
Both tested market bytecodes exactly match the measured artifacts.

The new test runner temporarily adds a research profile, archives its complete
configuration and restores foundry.toml afterward. Initial runner attempts had
no tests / an invalid config filename; neither is counted as qualification.
Successful evidence: external `e02-behavior/`; compiler receipt: `e02/`.

Decision: retain as an independently selectable source candidate. Market storage
still exceeds the limit by 1,820/2,475 bytes. This is a local size reduction,
not a deployability claim.
