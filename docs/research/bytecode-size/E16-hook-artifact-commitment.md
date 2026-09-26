# E16: on-chain hook artifact commitment

Source parent: `e649e19` (E15).

The user selected an on-chain commitment for hook creation code. A registered
template must decode to the reviewed artifact before its constructor can run,
even if deployment tooling is bypassed or an executable store returns different
bytes later.

## Design

- Append a required `bytes32 initCodeHash` argument to `addHooksTemplate` in both
  factories. It comes from the original compiled artifact, not a decoder response.
- Check the decoded bytes during registration and record the hash permanently
  in a separate mapping. Keep the existing template tuple and admission event;
  expose a hash getter and emit a separate hash-record event.
- Recheck the decoded bytes before appending constructor arguments and running
  CREATE2. Use those same bytes for deployment. Reject a mismatch before any
  constructor executes; keep nonce and index updates atomic.
- Do not retain an unchecked registration overload. Update active deployment
  scripts and tests. Historical tooling must remain explicit about which
  factory interface it supports.

This commits to the template's creation code. Choosing an incorrect artifact
and its matching hash, incorrect constructor arguments, or incorrect hook logic
remain outside the checksum guarantee. Canonical storage-runtime attestation
still rejects unreviewed readers before registration through the supplied tools.

## Tracker

- [x] Implement registration and per-instance checks in both factories.
- [x] Update artifact-derived hashes, plan predicates, and registration callers.
- [x] Test raw/compressed stores, incorrect registration hashes, changed decoder
  output, standalone and combined market/hook creation, rollback, and recovery.
- [x] Run both compiler configurations and existing invariants; verify that
  removing the checks makes the intended tests fail.
- [x] Measure factory size, registration/deployment gas, deliberate ABI/storage
  changes, and unchanged market/hook artifacts. Repeat strict deployments.
- [x] Record results and a signed kethcode checkpoint. Keep runs 44 as the normal
  configuration and leave the supplied reference documents uncommitted.

## Implementation

Both factories now require
`addHooksTemplate(address,string,address,address,uint80,uint16,bytes32)`.
The last argument is the hash of the original creation artifact, without
instance constructor arguments. A mismatch at registration or deployment
reverts with `HooksTemplateInitCodeHashMismatch`.

`getHooksTemplateInitCodeHash(address)` exposes the permanent commitment.
`HooksTemplateInitCodeHashRecorded(address indexed hooksTemplate, bytes32
initCodeHash)` is emitted alongside the existing admission event. The mapping
occupies appended storage slot 9 in both factories. Existing slots, the
`HooksTemplate` tuple, fee updates, and the admission event are preserved.
Disabling a template cannot change its hash, and duplicate registration remains
rejected.

The deployment check is in the shared instance-creation path. It verifies the
exact buffer that will be passed to CREATE2, before instance arguments are
appended. Both standalone hook deployment and `deployMarketAndHooks` use it.
There is no second decoder read between checking and deployment.

The V2.5 owner script derives the argument from the selected compiled artifact
and reads it back after registration. Its plan predicate checks the committed
hash. Activation validation checks all six factory/template registrations
against their corresponding storage-entry hashes, including forwarded calls.
The active Sepolia ceremony config forwards the new registration selector.
It also now accepts prepared compressed-storage blueprints; its older raw-only
restriction was missed in E15. The CLI and UI's existing storage-image checks
remain in place.

Template sync requires commitments for every input before sending any change.
Old exports remain readable but need hashes from reviewed creation artifacts;
the tool does not derive an expected hash from a live decoder. The historical
Sepolia fix-1 generator explicitly rejects the new factory interface. Existing
deployment plans and release inventories are retained as historical evidence.

## Qualification

- 463 reported focused tests pass under runs 44 and runs 1/no F, up from E15's
  457. This includes all nine existing invariant properties, reported as one
  group: 2,000 runs, depth 30, 60,000 calls, zero handler reverts. Budgets and
  assertions are unchanged. Fuzz tests retain 1,000 runs and seed `0x5eed`.
- All 28 strict-deployment tests pass with the actual 24,576-byte code limit,
  including the 12 production/composition cells and the new commitment tests.
- Incorrect hashes, zero hashes, the old selector, raw/compressed stores,
  changed reader output, and corrupt stored bytes are covered. Both deployment
  paths reject before running the wrong constructor. Tests check nonce/index
  rollback, preserve the recorded hash, restore the store, and retry successfully.
- Four isolated negative controls remove registration or deployment validation
  from one factory at a time. Registration controls fail two tests; deployment
  controls fail three. Restoring all checks passes all six commitment tests.
- Ten fresh Forge artifacts match the independent compiler output under both
  configurations. Both markets, three templates, and three composition examples
  retain byte-identical creation/runtime code, ABIs, and layouts. Factory ABI
  deltas are exactly the replaced registration selector plus the getter, error,
  and event above; only the appended mapping changes storage.
- All 38 real local transactions pass on Osaka Anvil with code and transaction
  gas limits enabled. The six production model/policy combinations verify
  committed hashes, deployed runtime, constructor context, and market terms.
- Sixteen tooling tests reject missing or mismatched commitments, incorrect
  storage associations, weak registration predicates, unsupported old targets,
  and missing source commitments. The 42 existing UI tests and UI build pass.
- Changed Solidity registration callers compile at runs 44; the three changed
  deployment scripts also compile under runs 1/no F. The owner script initially
  exceeded the compiler's stack limit; extracting argument construction into
  `_templateRegistrationArgs` resolves it without changing the payload.

These are scoped research checks, with the release and invariant-model limits
already recorded in the [candidate review](./candidate-review.md). They do not
replace release qualification or an audit.

## Size and cost

| Configuration | Factory | Runtime bytes | E16 runtime increase | Creation bytes |
| --- | --- | ---: | ---: | ---: |
| Runs 1/no F | Standard | 16,512 | 279 | 17,225 |
| Runs 1/no F | Revolving | 17,062 | 279 | 17,775 |
| Runs 44 | Standard | 17,441 | 295 | 18,282 |
| Runs 44 | Revolving | 18,360 | 295 | 19,201 |

No market or hook bytes are added. The selected market runtimes remain 23,791
and 24,344 bytes; their single compressed stores remain 17,769 and 18,248 bytes.
The normal configuration remains runs 44, where revolving still exceeds the
runtime limit by 485 bytes. E16 does not change that selection decision.

Compared with E15's same local transaction sequence, registering a raw production
template adds 35,042–37,219 gas. Each hook instance adds 5,646 gas for open term,
5,922 for fixed term, or 6,534 for periodic term. This cost is paid at deployment,
not during ordinary market operations. Compressed registration also pays for a
decoder read; the RPC sequence uses raw production templates, while the strict
Forge matrix separately exercises compressed templates and compositions.

The largest actual transaction uses 7,419,876 gas; its 30% buffer is 9,645,839,
below the 16,777,216 Osaka transaction cap used in the rehearsal.

## Evidence and decision

Retain the on-chain commitment. Tooling verifies the canonical stored image;
the factory independently refuses to execute template bytes that differ from
the artifact committed during registration. The expected hash is not supplied
by the decoder. There is still one storage contract per artifact.

The [machine-readable results](./results/e16.json) summarize the qualification.
Compiler inputs, test logs, mutation controls, and transaction requests/receipts
are archived under `/home/kethcode/wildcat/bytecode-research/2026-09-26/` with
the `e16-` prefix. The initial failed script compile and missing-import test
compile are retained alongside the successful reruns.

Use the [candidate reproduction commands](./candidate-review.md#reproduce-the-selected-checks)
for the broader suites and strict deployments. The new tooling tests run with:

```sh
node --test scripts/__tests__/template-commitments.test.js
```
