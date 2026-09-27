# E19: integration-test updates

Source parent: `7d73ded` (E18). Status: in progress.

The user requested completion of the integration-test updates before release
qualification. The earlier repayment work deliberately removed market dispatch
to `onExecuteWithdrawal` and rejects new markets that enable that reserved
callback. Two integration tests still expect that dispatch. Establish the
complete failure list before changing their assertions.

## Plan and tracker

| Task | Required evidence | Status |
| --- | --- | --- |
| E19-01 | Run all integration tests against the E18 contracts, recording stale expectations and any other failures. Extend the receipt runner to select integrations and the complete test tree. | Complete; fixture split restores compilation, then 78 pass and three fail for the reasons below. |
| E19-02 | Update callback expectations to the agreed collection guarantee. Retain batch amounts, claim accounting, sanctions, calldata, and unaffected callback checks. Cover both market models and reject reserved execution-hook configurations. | Pending |
| E19-03 | Run integrations and the full behavioral test tree under runs 44 and the candidate settings. Preserve invariant budgets, compare fresh production artifacts, and separately report deployment-size gates. | Pending |

Use signed kethcode checkpoints on the existing research branch; do not push.
Keep the user's PDFs, review handoff, earlier sketch, and voice guide untracked.
Large receipts belong outside the repository under
`/home/kethcode/wildcat/bytecode-research/2026-09-27/`.

No production behavior or compiler setting change is planned. Any unexpected
failure needs a concrete diagnosis; do not turn it into an accepted behavior
change just to make the suite pass. The unchanged raw-storage and runtime size
gates remain separate from behavior checks, as in earlier research. Candidate
deployment must still pass the existing tests with actual size limits.

`check.py --scope integration` selects every integration test;
`--scope full` selects every test file, including providers, lenses, token
wrappers, borrower identity, and lower-level libraries absent from the focused
research selection. `--scope all` retains its historical focused meaning.

## Initial build diagnosis

`e19-integration-before` cannot reach test execution at runs 44: solc reports
`var_stack ... var_hooksArtifacts` one slot too deep in the shared production
stack setup. This is a test-fixture compilation failure, distinct from the two
known obsolete callback expectations. The first candidate extracts dependency
deployment from `_deployProductionStack`, preserving the order, constructor
arguments, borrower registration, factory setup, and template registrations.
The unchanged integration assertions are rerun before changing callback tests.

`e19-integration-fixture` compiles successfully and runs 81 tests: 78 pass.
The two execution-callback tests fail at construction with
`UnsupportedExecuteWithdrawalHook`, as expected. The third failure is
`test_fourPolicyFactoriesForceCallbacksAcrossProductionMatrix`, whose raw
periodic-composition store exceeds EIP-170 at runs 44. Its callback and factory
assertions remain applicable; update the production fixture to choose raw or
compressed storage like the current deployment tooling, and verify both the
actual stored image and decoded creation bytes. Retain every size bound.

The setup extraction changes no production source, test assertions, constructor
arguments, or deployment order. It is checkpointed separately from the behavior
expectation updates.
