# E15: compression and deployment integrity

Source parent: `050c0b1` (E14). FastLZ remains a research candidate.

## Guarantee

Compression must preserve the exact compiled creation code. The factory must
execute the intended code with the intended constructor arguments, sender and
value. Invalid data must not leave a market, hook registration, fee payment or
partial deployment behind.

The trusted reference is the independently compiled artifact. A hash supplied
by the same storage contract is not an independent commitment. The existing
market CREATE2 address check commits to the original creation-code hash, but
previously ran only after construction. Hook templates are owner-approved deployment inputs;
their stored address does not by itself establish that an executable reader is
the canonical, context-independent reader.

## Work and qualification tracker

- [x] Cross-check Solady against upstream FastLZ level 1 at the commit referenced
  by the vendored library. Keep that reference test-only and reproducible offline.
- [x] Exercise short, long, repetitive and incompressible payloads, storage and
  creation limits, memory boundaries, constructor arguments, CREATE/CREATE2,
  revert propagation and repeated reads.
- [x] Characterize malformed streams and hostile executable stores. Solady's
  decoder is not a parser for arbitrary untrusted streams; reject unexpected
  storage bytecode before treating its output as an approved artifact.
- [x] Verify canonical storage runtime and decoded bytes against the original
  artifact in deployment tooling, including existing-store reuse and plan mode.
- [x] Check the market's full decoded hash before CREATE2. Retain the existing
  address check and test failure atomicity in both factories.
- [x] Compare factory-deployed market/hook runtime and initialization against
  raw-code controls, with identical deployment addresses and constructor context.
- [x] Run the expanded suite at runs 44 and runs 1/no F, the full existing focused
  qualification including invariants, and real-limit factory deployment checks.
- [x] Record sizes, changed interfaces or storage, gas feasibility, limitations
  and signed checkpoints. Keep the normal compiler configuration at runs 44.

The raw comparison is an oracle for byte identity, not evidence that oversized
raw storage fits EIP-170. Real-limit tests separately deploy every compressed
store and market without replacing their code. Mutation tests may deliberately
replace test storage code to model corrupt or hostile deployment inputs.

No new repayment-date stateful invariant model is part of this experiment.
No mainnet deployment, push or release adoption is authorized by these tests.

## Artifact verification

Compile a concrete template, including its selected policies, before preparing
its storage artifact. There is no dynamic policy assembly. Per-instance
administrator and constructor data are appended after reading the template's
original creation code, exactly as before.

The compressed runtime is the pinned reader plus the pinned Solidity encoder's
output and a two-byte length footer. `LibCompressedInitCode.getStorageRuntime`
is shared by creation and verification. Tooling compares the entire deployed
runtime hash with that expected image before calling the reader, then compares
the recovered bytes' hash with the original artifact. This covers new stores,
existing-store reuse, plan execution, and resume. Raw stores remain supported.

Plan generation encodes locally and puts the finished image in constructor
arguments. `CompressedInitCodeStorage` only installs that image. It is an
alternative creation blueprint to the raw `InitCodeStorage`, not a second
deployed helper. The plan's `codeHash` predicate binds both the stored image
(`expect`) and recovered creation code (`initCodeHash`). Schema 1.1, the CLI,
and the UI are updated together; older executors cannot run these new plans.

Both factories now hash the complete decoded market creation code before
`CREATE2`, then deploy those same bytes. The existing address check remains.
A mismatch uses the existing `MarketDeploymentAddressMismatch` error. The
reader and Solady codec are unchanged, and there is no self-reported checksum
in the storage footer.

Hook templates still use owner-approved registration. No on-chain template
hash registry is added. Exact canonical runtime verification in the deployment
tooling establishes that an approved reader cannot vary its response by caller
or calldata. An owner bypassing that tooling and registering arbitrary code is
outside that guarantee. Constructor arguments and factory context are checked
independently in the tests.

## Independent reference and adversarial cases

The test-only [C reference](../../../test/reference/fastlz/README.md) is pinned
to the upstream commit named by the vendored Solady library. Its source hashes
are checked before compilation. Tests need Python 3, `cc`, and FFI, but no
network. C decodes Solady output; the deployed reader decodes C output. The
corpus includes all ten measured artifacts, 17 boundary lengths, four payload
patterns, and 1,000 fuzz cases per property. The short-input adapter is explicit:
upstream compression requires at least 16 bytes, so shorter inputs use one
literal run and empty input uses an empty stream.

Additional cases cover memory guards and unaligned free-memory pointers,
overlapping matches, repeated reads, caller/calldata independence, CREATE and
CREATE2, ETH value, constructor failure rollback, and the total 49,152-byte
creation limit after memory or calldata arguments are appended.

Malformed FastLZ is not an accepted deployment input. For example, `02ab`
decodes to `ab0000` in Solady despite its truncated literal. The suite records
that behavior and verifies that artifact attestation rejects the store. Other
cases alter the reader, payload, or footer; truncate or append bytes; select
the wrong artifact; or return a correct response only to the verifier.

A different valid encoding of the same bytes is also rejected by canonical
runtime attestation. The vendored JavaScript encoder produced a valid stream
61 bytes larger than the Solidity encoder for the standard market. That
diagnostic is archived. Alternative encoders can cross-decode correctly
without producing the approved stored image; they are not interchangeable
when calculating the expected runtime hash.

Raw/compressed factory comparisons keep deployment addresses identical using
snapshots. They compare market and hook runtime hashes, initial market state,
and deployment logs for both models and all three production templates. A
separate factory constructor probe fuzzes constructor bytes and checks the
administrator, factory, data length, data hash, and predicted hook address. It preserves the existing unpadded
trailing constructor bytes, which are part of CREATE2 identity.

## Transaction feasibility

The first plan constructor compressed the artifact on chain. Both market stores
deployed, but gas was 13,489,806 / 13,840,800. The plan's normal 30% gas buffer
would exceed the 16,777,216 per-transaction cap in
[EIP-7825](https://eips.ethereum.org/EIPS/eip-7825).

Preparing the encoded runtime locally fixes that integration problem. Installing
the prepared standard/revolving image costs 3,897,264 / 4,000,979 gas via the
plan constructor, or 3,888,363 / 3,991,884 via the direct creation prefix.
The decoded market creation code is unchanged. The runtime storage bytes are
identical between the two installation paths.

[`compression-rpc.js`](../../../scripts/research/compression-rpc.js) starts a
private Anvil with Osaka transaction limits and the actual code-size limit.
It first proves that an over-cap transaction is rejected, then checks the
normal buffered transactions, stored bytes, decoded hashes, and factory
deployments. It uses the pinned Solidity encoder's exported fixture and rejects
a fixture that no longer matches the compiled artifact.

The completed RPC campaign has 38 successful transactions and six market
deployments: both models with open, fixed, and periodic hooks. Market creation
costs 7,230,248 to 7,419,854 gas; the largest buffered transaction is 9,645,811.
This campaign uses raw storage for the three already-fitting hook templates and
compressed storage for both markets. It checks predicted addresses, runtime
bytes outside compiler-declared immutable positions, administrator, factory,
borrower, asset, and repayment terms. The Forge raw/compressed comparison also
checks complete initialized runtime hashes, including immutables.

## Qualification and limits

The broader research campaign passes 457 reported tests in both configurations:
normal runs 44 and candidate runs 1/no F. Fuzz cases use 1,000 runs and seed
`0x5eed`. All nine existing invariant properties pass at 2,000 runs and depth 30,
with 60,000 handler calls and zero handler reverts in each configuration. Their
17 action counts match E14. The compression-focused campaign passes 55 tests.

The separate deployment campaign passes 22 tests with the 24,576-byte limit
enforced, including the original 12 factory/market/hook combinations. Those
real-limit cases retain their deposit, borrow, repay, and scheduled-closure
checks and never replace deployed code. The raw comparison and mutation cases
are separate tests and are not counted as deployment-limit evidence.

Ten fresh Forge artifacts in each broader build match the independent native
compiler output exactly: creation code, runtime code, full ABI, and normalized
storage layout. Compared with E14, all market and hook bytecode is unchanged.
Only the factories change; all ten ABIs and layouts remain unchanged.

| Configuration | Factory | Creation bytes (delta) | Runtime bytes (delta) |
| --- | --- | ---: | ---: |
| Runs 44 | Standard | 17,987 (+52) | 17,146 (+45) |
| Runs 44 | Revolving | 18,906 (+141) | 18,065 (+120) |
| Runs 1/no F | Standard | 16,946 (+51) | 16,233 (+44) |
| Runs 1/no F | Revolving | 17,496 (+138) | 16,783 (+117) |

Candidate market runtimes remain 23,791 / 24,344 bytes and stores remain
17,769 / 18,248 bytes. Revolving still has only 232 bytes of live-runtime
headroom. Runs 44 still exceeds the revolving runtime limit; compression does
not change that. The normal compiler configuration is unchanged.

Negative controls run in an isolated checkout. Removing the full-runtime
attestation makes both the context-dependent reader test and the alternative
valid encoding test fail. Removing the factory hash check makes the wrong
constructor test fail with `DeploymentFailed` instead of the expected early
`MarketDeploymentAddressMismatch`. The control is repeated with only the
revolving guard removed. Restoring the guards makes all three tests pass.
No guard is removed from the working branch during these controls.

All 42 deployment UI tests and the production UI build pass. The tests include
CLI/UI predicate agreement, literal hash validation, decoded-output checks,
rejecting a runtime before calling it, and halting execution and resume on a
hash mismatch. All three changed V2.5 release scripts compile with the native
compiler. Modified Solidity passes formatting and lint checks.

These are scoped integration and behavioral checks, not a formal proof or a
completed release audit. The existing invariant model has no scheduled
repayment dates. Baseline integration callback updates, a dedicated stateful
repayment-date model, release rehearsal, review of the selected optimizer and
memory arena, and audit/refreeze remain separate work. The Sepolia fix-1
rotation generator is a historical release path and still builds raw stores;
it is not qualified for this candidate's oversized creation artifacts.

## Reproduction and receipts

Run from the repository root; receipt directories must be new. Do not run two
`check.py` commands concurrently because they temporarily select a profile in
`foundry.toml` and share the artifact directory.

```sh
size_yul_steps='dhfoDgvulfnTUtnIf[xa[r]EscLMcCTUtTOntnfDIulLculVcul [j]Tpeulxa[rul]xa[r]cLgvifCTUca[r]LSsTOtfDnca[r]Iulc]jmul[jul] VcTOcul jmul'
python3 scripts/research/check.py /tmp/wildcat-compression-44 --scope all --runs 44
python3 scripts/research/check.py /tmp/wildcat-compression-size --scope all --runs 1 --yul-steps "$size_yul_steps"
python3 scripts/research/check.py /tmp/wildcat-compression-deployment --scope deployment --runs 1 --yul-steps "$size_yul_steps" --code-size-limit 24576
node scripts/research/compression-rpc.js /tmp/wildcat-compression-transactions
```

The last Forge run exports the RPC fixture to `deploy-out/compression-rpc.json`.
The RPC check is local, creates its own temporary chain, and sends no public
network transactions. [Concise results](./results/e15.json) link the external
evidence under `/home/kethcode/wildcat/bytecode-research/2026-09-26/`:

- `e15-all-default/`, `e15-all-noF-final/`: broader campaigns, source snapshots,
  effective settings, fresh artifacts, and native comparisons;
- `e15-native-default/`, `e15-native-noF/`, `e15-native-delta.json`: measurements
  and byte/ABI/layout comparisons with the previous candidate;
- `e15-deployment-noF/`: strict deployment campaign and fresh native comparison;
- `e15-negative-guards/`: removed guards, commands, expected failures, and
  restored controls;
- `e15-rpc-receipts/`: successful transaction requests and receipts, exact compiled artifacts,
  and encoded fixtures;
- `e15-plan-scripts/`: native compilation of the three release scripts.

Failed development attempts remain archived, including test compilation fixes,
early runs-44 size-gate failures, the noncanonical JavaScript stream, the
on-chain compression gas-buffer problem, and an RPC mock-artifact name
collision corrected before the successful matrix campaign.

Decision: retain the artifact checks, pre-constructor market guard, prepared
deployment images, and verification suite on this experimental branch. FastLZ
remains the assumed candidate pending release review.
