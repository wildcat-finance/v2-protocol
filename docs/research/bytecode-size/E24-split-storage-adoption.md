# E24: adopt raw and split initcode storage

Source parent: `1e0f3d8`. Branch: `codex/split-initcode-comparison`.
Status: adopted and qualified; full release rehearsal remains outstanding.

The user selected split storage after reviewing E23. Oversized creation code
uses two immutable contracts; fitting code retains raw `STOP || initcode`
storage. FastLZ remains research evidence, not the selected deployment route.
Keep compiler settings, market/factory interfaces, and artifact commitments.

## Plan and tracker

- [x] Record the decision and adoption scope.
- [x] Integrate prepared raw/split installation and exact verification into
  direct deployment, including secondary labels and partial-deployment reuse.
- [x] Generate secondary-before-primary plan entries and inventory records.
  Bind the secondary address without compression in the installation transaction.
- [x] Extend CLI/UI predicates and activation checks to verify both complete
  runtimes, their link, and the original creation-code hash on execution/resume.
- [x] Switch normal production test fixtures and size checks to the selected
  format while preserving the compression comparison controls.
- [x] Qualify Solidity, tooling, deployment limits, unchanged production
  artifacts, and actual execution/resume of the generated storage plans.
- [x] Update maintained deployment documentation and the release tracker;
  make signed kethcode checkpoints. Do not push.

The primary plan predicate commits the runtime with its secondary-address
field zeroed, separately commits the secondary runtime, and references the
secondary deployment output. Verification checks the actual embedded address,
both runtime commitments, then the original creation-code hash. This preserves
literal artifact hashes without depending on a predicted transaction nonce.

The final full ceremony on an Anvil fork, network-limit decisions, final
inventory/freeze, audit delta, and downstream integrations remain release work.
This task qualifies adoption of the selected storage format.

## Implementation

`LibDeployment` and the V2.5 scripts prepare raw images up to 24,575 original
bytes and split images above that. `PreparedInitCodeStorage` installs the raw
or secondary image verbatim. `LinkedInitCodeStorage` installs the prepared
primary after inserting the secondary address into its empty footer field.
Neither constructor encodes or decodes the payload. The 114-byte reader and
the two-contract layout from E23 are unchanged.

Each split primary retains its existing factory-facing label and plan output.
Its secondary has a separate transaction and inventory entry, appending
`_secondary` to the primary deployment label and `-secondary` to the plan
output. Direct deployment checks and reuses an already recorded secondary;
it also recovers a missing secondary inventory link from an authenticated
primary. A recorded link that disagrees with the actual code fails.

The CLI and UI implement `splitCodeHash`. The predicate checks the embedded
address, hashes the primary with that address field zeroed, hashes the entire
secondary, and only then reads and hashes the reconstructed creation code.
Both hashes are literal commitments from preparation. An address reference
binds the separately verified secondary without predicting a CREATE nonce.
Activation validation ties these commitments to constructor inputs, original
artifact bytes and secondary-before-primary ordering, including oversized
future hook templates. Existing on-chain factory hash checks are unchanged.

The handoff generator now records the installer from the verified plan and
includes each companion's address, deployment receipt and installer artifact.
It requires verified plan metadata for storage records instead of guessing
which constructor installed them. Historical raw and compressed artifact names
remain recognized when validating old records.

Normal production fixtures and artifact gates use raw/split storage. Explicit
compression controls remain in research tests so the comparison can still be
reproduced. The direct deployment verifier rejects a compressed image even if
its returned creation code matches; it authenticates the selected image format.
No market, factory, hook, lens, compiler or protocol ABI change is part of E24.

## Qualification

Receipts are under
`/home/kethcode/wildcat/bytecode-research/2026-09-27/e24/`.
The compact record is [results/e24.json](./results/e24.json).

- Full default suite, seed `0x5eed`: **883 passed**, zero failed or skipped.
  All three invariant campaigns retain 2,000 runs and depth 30: **180,000
  handler calls, zero reverts**. Setup now uses the selected split path.
- Deployment-profile tools suite: **11 passed**, including 1,000-run fuzzing,
  byte corruption, missing/trailing chunks, context-dependent readers,
  constructor boundaries and incomplete-installation reuse.
- Strict deployment selection: **27 passed**, runtime limit 24,576. It covers
  split and compressed controls, both factories, original-hash rejection,
  concrete/composed hooks and market parity.
- Node tooling: **35 passed**, including activation and handoff records.
  Deployment UI: **44 passed** and production build succeeds.
- The `deploy` build succeeds. Creation and runtime bytes for all **14**
  tracked market/factory/hook/composition/lens artifacts match E22 in both
  `out` and `deploy-out`. Market runtime headroom remains 798 / 242 bytes.
- Changed Solidity passes Prettier. Solhint reports no errors; its 11 line-length
  warnings include ten existing long lines and one new test path string.

The actual Solidity-generated standard-market storage plan was assembled,
executed and verified through `scripts/plan.js` on an isolated Anvil chain,
with Osaka execution and the real runtime and transaction-gas limits. The
runner installed only the secondary, stopped, then resumed the full plan.
It deliberately corrupted the secondary and later the primary's embedded
link; each resume failed before sending a transaction. With the reviewed code
restored, resuming completed work sent no new transaction.

| Standard-market installation | Receipt gas used |
| --- | ---: |
| Prepared secondary | 267,549 |
| Linked primary | 5,359,932 |
| Total | 5,627,481 |

The installed primary/secondary sizes are 24,576 / 979 bytes. Their returned
creation-code hash is
`0xaa0b53643a8f3866b20af22bfa563d3bd7addc8c5707e28aa14009b8825dd942`.
Prepared installation adds 2,850 gas to E23's split prototype, leaving its
first-market break-even result intact. The reader and factory bytes are
unchanged, so E23's per-market gas comparison still applies. This check covers
the standard storage subplan; E23 and the strict matrices cover both market
models. It is not the required full ceremony on a target-chain fork.

## Corrections during qualification

The first tools run exposed test-only JSON serialization surviving a reverted
harness call while its ID counter rolled back. The harness now explicitly
initializes its empty JSON object; production JSON handling is unchanged.
The first local-chain runner used `contractAddress` instead of the executor's
recorded `resolvedAddress`; it was corrected and the full resume check rerun.
UI predicate type narrowing and the expected validation error text were also
updated. Failed-run evidence remains beside the successful receipts.

## Reproduce

```sh
FOUNDRY_PROFILE=deploy forge build
FOUNDRY_PROFILE=deploy forge test --match-contract InitCodeStorageToolsTest --fuzz-seed 0x5eed
forge test --summary --fuzz-seed 0x5eed
node --test scripts/__tests__/*.test.js
npm --prefix deploy-ui test -- --run
npm --prefix deploy-ui run build
node scripts/research/split-plan-rpc.js /tmp/wildcat-split-plan-new-receipts
```

The deployment-profile tools test writes the storage plan used by the final
command. Its receipt directory must not already exist. The runner starts its
own local node and cleans up only its temporary deployment directory.

## Release boundary

Keep E23/E24 evidence for the audit delta. The new reader and link constructor
remain review scope. Update final network limits, build the frozen ceremony,
rehearse it on the required target-chain fork, and then produce the release
inventory/freeze. Export the working spec and research records before removing
them from the release tree. Nothing has been pushed by this task.
