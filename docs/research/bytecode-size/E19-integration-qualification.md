# E19: integration-test updates

Source parent: `7d73ded` (E18). Status: complete; the normal compiler's known
runtime-size failures remain explicit below.

The user requested completion of the integration-test updates before release
qualification. The earlier repayment work deliberately removed market dispatch
to `onExecuteWithdrawal` and rejects new markets that enable that reserved
callback. Two integration tests still expect that dispatch. Establish the
complete failure list before changing their assertions.

## Plan and tracker

| Task | Required evidence | Status |
| --- | --- | --- |
| E19-01 | Run all integration tests against the E18 contracts, recording stale expectations and any other failures. Extend the receipt runner to select integrations and the complete test tree. | Complete; fixture split restores compilation, then 78 pass and three fail for the reasons below. |
| E19-02 | Update callback expectations to the agreed collection guarantee. Retain batch amounts, claim accounting, sanctions, calldata, and unaffected callback checks. Cover both market models and reject reserved execution-hook configurations. | Complete at runs 44: 82 integration behavior tests pass; both configurations follow in E19-03. |
| E19-03 | Update remaining artifact gates to the selected storage format, then run the complete test tree under runs 44 and the candidate settings. Preserve invariant budgets, compare fresh production artifacts, and explicitly report any runtime-size failures at runs 44. | Complete; all 852 pass under the candidate settings, 849 pass with three known runtime-size failures at runs 44, and all 28 actual-limit deployment tests pass. |

Use signed kethcode checkpoints on the existing research branch; do not push.
Keep the user's PDFs, review handoff, earlier sketch, and voice guide untracked.
Large receipts belong outside the repository under
`/home/kethcode/wildcat/bytecode-research/2026-09-27/`.

No production behavior or compiler setting change is planned. Any unexpected
failure needs a concrete diagnosis; do not turn it into an accepted behavior
change just to make the suite pass. The initial behavior run separates size
gates, as in earlier research. The complete qualification must update obsolete
raw-only artifact assumptions to the selected format while preserving all
storage, runtime, and creation-payload limits. Candidate deployment must still
pass the existing tests with actual size limits.

`check.py --scope integration` selects every integration test;
`--scope full` selects every test file and does not filter size gates. This
includes providers, lenses, token wrappers, borrower identity, and lower-level
libraries absent from the focused research selection. `--scope all` retains
its historical focused meaning.

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

## Callback and storage-format updates

`e19-integration-updated` passes all 82 selected integration behavior tests at
runs 44. Single and bulk execution fuzz arbitrary trailing data, both market
models, and sanctions applied after queuing. A direct control call proves the
mocked execution veto is active; collection then succeeds without dispatching
it. Assertions check exact returned amounts, lender/escrow balances, consumed
claims, empty reserved liabilities, and rejection of repeat collection. The
single path retains the pending-batch rejection. Creation rejects the reserved
bit on both market models, with and without repayment terms. Unaffected callback
calldata expectations remain intact.

The shared production fixture now follows `LibDeployment.broadcastDeployInitcode`:
raw storage through 24,575 creation bytes, compressed storage above that. The
four-policy composition test checks its actual stored image, decoded original
creation code, and all previous size bounds. Production source is unchanged.

The same old raw-only assumption remains in the two standalone artifact gates.
E19-03 will update those expectations too. The complete runner will execute
size gates rather than silently filtering them; the known revolving runtime
overage at runs 44 must remain visible until the final compiler decision.

Both standalone artifact gates now install the selected raw/compressed image,
require exactly one storage contract, compare its complete runtime with the
prepared image, and decode the original creation code exactly. The hook gate
retains its constructor-argument payload check. The market gate additionally
checks the creation hash and EIP-3860 payload bound. All EIP-170 limits remain
24,576 bytes. The low-level raw-storage tests are unchanged.

## Complete runs-44 result

`e19-full-default` discovers all 67 test files and runs 852 reported tests:
849 pass, three fail, none are skipped. The failures are exactly the known
revolving runtime overage:

- `test_ProductionArtifactsFitActualCodeStorageAndRuntimeLimits`;
- `test_realLimits_AllSixFactoryMarketCombinations`;
- `test_realLimits_PeriodicFeatureCompositions`.

The standalone hook-composition gate and all behavior assertions pass. The
original nine invariant properties and both lifecycle campaigns each retain
2,000 runs/depth 30, complete 60,000 calls, and report zero handler reverts.
All ten fresh Forge artifacts exactly match E18's independent runs-44 compiler
output for creation/runtime bytes, complete ABI, and normalized storage layout.
Production code and compiler selection have not changed.

## Complete candidate result

`e19-full-noF` passes all 852 tests across 69 suites, with no failures, skipped
tests, or test-name filters. This includes all 83 integration tests and both
standalone artifact gates. Both full runs use identical Solidity source
snapshots, 1,000 fuzz cases, and seed `0x5eed`. The original invariant group
and both lifecycle campaigns again complete 2,000 runs/depth 30 with 60,000
calls each and zero handler reverts. Together the two complete runs account
for 360,000 invariant calls. No invariant action, budget, or assertion changed.

All ten fresh candidate artifacts match E18's independent compiler output
exactly for creation/runtime bytes, full ABI, and normalized storage layout.
No production source changed. Candidate runtimes remain 23,778 / 24,334 bytes,
with 798 / 242 bytes spare. Normal runs 44 still leaves revolving at 25,050
bytes, or 474 above the runtime limit.

The full runs retain the established 262,144-byte test-harness allowance.
`e19-deployment` separately enforces the actual 24,576-byte code-size limit and
passes all 28 tests, including twelve factory/market/hook combinations. The
storage images remain 17,759 / 18,254 bytes for the two markets. E18's real
local transaction receipts apply to these unchanged production artifacts;
that transaction campaign is not repeated for test-only edits.

Changed-file Prettier, Solhint, and whitespace checks pass with no warnings or
errors. The normal `foundry.toml` is restored unchanged. Signed implementation
checkpoints are `74cfc72` (fixture compilation and baseline) and `04f08ee`
(callback expectations and production storage selection). The complete
machine-readable record is [results/e19.json](./results/e19.json).

Final compiler selection, gas measurements, release-profile checks on the
frozen configuration, the actual deployment ceremony/Anvil-fork rehearsal,
inventory, and audit/refreeze review remain separate release work. No pending
integration expectation update remains from the failures recorded here.

## Reproduce

Each receipt directory must be new. The runs-44 full command intentionally
returns a nonzero exit status for the three runtime-size gates listed above.

```sh
size_yul_steps='dhfoDgvulfnTUtnIf[xa[r]EscLMcCTUtTOntnfDIulLculVcul [j]Tpeulxa[rul]xa[r]cLgvifCTUca[r]LSsTOtfDnca[r]Iulc]jmul[jul] VcTOcul jmul'
python3 scripts/research/check.py /tmp/e19-default --scope full --lifecycle-coverage
python3 scripts/research/check.py /tmp/e19-candidate --scope full --runs 1 --yul-steps "$size_yul_steps" --lifecycle-coverage
python3 scripts/research/check.py /tmp/e19-deployment --scope deployment --runs 1 --yul-steps "$size_yul_steps" --code-size-limit 24576
```
