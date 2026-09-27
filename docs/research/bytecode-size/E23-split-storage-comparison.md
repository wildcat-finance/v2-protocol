# E23: two-contract initcode storage versus FastLZ

Source parent: `94c0a42`. Branch: `codex/split-initcode-comparison`.
Status: comparison qualified; the user selected split storage on 2026-09-27.
[E24](./E24-split-storage-adoption.md) tracks deployment-tooling adoption. The
measurements and limitations below describe the E23 comparison checkpoint.

The user explicitly requested a branch comparing two storage contracts with
the current FastLZ workflow. This authorizes the comparison despite the earlier
single-store constraint. The parent branch retains the compressed candidate.
Keep runs 1 and the adopted Yul sequence fixed. Do not change market behavior,
factory interfaces, artifact commitments, or hook composition for this test.

## Hypothesis

Storing the original creation bytes across two contracts should cost more to
install but less to read for each deployment. It also replaces the codec with
byte concatenation. Measure the actual costs and remaining trust boundaries;
do not assume either option is safer or cheaper overall.

Use exactly two contracts, not two payload contracts plus a reader. The primary
contract holds an executable reader, the first payload chunk, and an immutable
footer identifying the second contract and both chunk lengths. The second
contract is inert `STOP || remaining bytes`. The primary returns their
concatenation through the same interface used by compressed storage.

The existing factory checks the returned creation-code hash before CREATE2.
It continues to register one template address and one decoded artifact hash.
No factory or market changes should be necessary. Prepared deployment data must
attest both runtimes and their linkage, as compressed tooling attests its one
runtime and decoded bytes today.

## Plan and tracker

- [x] Implement the two-contract format and prepared runtime builder; document
      its exact capacity, footer, validation, and deployment order.
- [x] Test round trips, chunk boundaries, malformed/missing/wrong secondary
      stores, constructor arguments/context, and factory rejection of wrong bytes.
- [x] Exercise both market families and all three hook templates, including
      composed hooks, with the actual code-size limit. Compare initialized market
      code/state/events against the compressed route.
- [x] Run matched local transactions for storage installation, factory and hook
      deployment, and market creation. Report one-time versus per-use gas, aggregate
      stored bytes, transaction counts, and the measured break-even point.
- [x] Compare code, tooling, validation, and operational complexity. Record what
      is demonstrated and what remains before either option can be released.
- [x] Commit signed kethcode checkpoints on this branch. Do not push or select
      the alternative for release without the user's review.

This is a deployment-format comparison on a local chain. The deployment-plan
rehearsal on an Anvil fork, final inventory/freeze, audit delta, downstream
integrations, and export/removal of working documents still follow it.

## Result

Split storage costs more to install, but recovers the difference on the first
market deployment. Each subsequent market saves about two million gas. Both
routes deploy identical market addresses, initialized runtime, initial state,
and events. No existing factory, market, hook, or lens source changed; all
fourteen measured creation/runtime artifacts match E22 under both profiles.

The result supports choosing split storage if the additional storage contract
is acceptable. It removes the codec from this deployment path and keeps the
existing artifact-hash checks. This prototype's new assembly still needs review;
a smaller reader is not proof of lower risk. FastLZ retains its existing E15/E16
qualification and deployment-tooling support.

## Format and capacity

`LibSplitInitCode` produces these two runtimes:

```text
primary   = SplitInitCodeReader || first bytes || secondary address || first length || second length
secondary = STOP || remaining bytes
footer    = 20-byte address     || 2-byte first length || 2-byte second length
```

The reader is 114 bytes under the selected compiler settings. The primary
holds at most 24,438 original bytes; the secondary holds at most 24,575.
Maximum original creation-code capacity is therefore 49,013 bytes. Each
runtime independently fits 24,576 bytes. Constructor arguments still count
toward the separate 49,152-byte CREATE/CREATE2 initcode limit. FastLZ can support
49,152 original bytes if its reader and compressed payload fit one contract.

Preparation splits bytes without encoding them. Deploy the secondary first,
bind its address into the primary footer, then deploy the primary. The reader
checks the declared bounds, requires the secondary's exact code length and
leading STOP, copies both chunks, and returns the original bytes. It executes
no secondary code. There is no third contract, mutable registry, or admin key.
The factory still receives only the primary address.

The format builder derives capacity from the compiled reader, so recompiling
the reader can change the split point and store hashes. Release tooling must
pin these artifacts just as it pins the compressed reader today. For a small
payload the experiment deliberately still creates two contracts, with a
STOP-only secondary; production should keep the existing raw single-store
format wherever it fits.

## Matched transaction measurements

All gas figures below are actual transaction receipt gas, including intrinsic
transaction costs. Both formats use the same prepared-runtime installation
constructor. The compressor runs during off-chain preparation, never in these
installation transactions. The comparison uses Anvil 1.8.3, Osaka execution,
Cancun compiler output, runs 1, and the unchanged pinned Yul sequence.

The runtime-size limit is 24,576 bytes, transaction gas cap 16,777,216, and
block gas limit 30 million. Negative controls confirm both size and transaction
gas limits are enforced. Every transaction fits with a 30% estimated-gas
buffer; the largest buffer is 9,666,890 gas.

| Market payload | FastLZ stored bytes | Split stored bytes, total | FastLZ install gas | Split install gas | FastLZ read/hash gas | Split read/hash gas |
| -------------- | ------------------: | ------------------------: | -----------------: | ----------------: | -------------------: | ------------------: |
| Standard       |              17,759 |                    25,555 |          3,894,825 |         5,624,631 |            2,040,321 |              44,566 |
| Revolving      |              18,254 |                    26,175 |          4,001,807 |         5,758,038 |            2,111,406 |              45,028 |

The split primary is 24,576 bytes for each market. Their secondary stores are
979 and 1,599 bytes. FastLZ's reader is 334 bytes, versus the split reader's 114. Read/hash is a separate cold transaction through the same probe for every
format; it includes transaction overhead and hashing, not just decoding.

| Market deployment    | FastLZ gas | Split gas | Saved per market |
| -------------------- | ---------: | --------: | ---------------: |
| Standard / open      |  7,260,183 | 5,264,428 |        1,995,755 |
| Standard / fixed     |  7,249,166 | 5,253,411 |        1,995,755 |
| Standard / periodic  |  7,227,558 | 5,231,803 |        1,995,755 |
| Revolving / open     |  7,430,014 | 5,363,636 |        2,066,378 |
| Revolving / fixed    |  7,436,069 | 5,369,691 |        2,066,378 |
| Revolving / periodic |  7,414,461 | 5,348,083 |        2,066,378 |

Production hooks use the same raw stores in both transaction variants. Both
factory deployments also cost the same: 3,652,321 and 3,771,241 gas. The market
comparison therefore isolates the creation-code retrieval route. Factory and
hook instance addresses, salt, constructor inputs, account state, and block
timestamps are held constant by restoring an Anvil snapshot between variants.
There is no code replacement in this transaction comparison.

The installation premium is 1,729,806 gas for standard and 1,756,231 for
revolving. Including installation and one market, split saves 265,949 and
310,147 gas respectively. After N markets, the net saving is:

```text
standard:  N * 1,995,755 - 1,729,806
revolving: N * 2,066,378 - 1,756,231
```

Split saves 27.49–27.87% on the measured market creation transactions. The
first deployment pays back the storage premium for both models. This does not
change deposit, withdrawal, borrow, or repay gas: those markets have identical
initialized bytecode and never consult the creation-code stores afterward.
It also does not increase their runtime headroom; revolving still has 242 bytes.

### Hook composition controls

The three periodic composition examples were forced through both formats to
check that the storage choice does not constrain stacked policies. Their hook
instances have identical addresses and initialized runtime in both factories.
The strict deployment test also creates markets from those instances and
exercises deposit, borrow, repayment, and scheduled closure.

These examples already fit raw single-contract storage at runs 1. Raw remains
the intended choice for them; the forced formats are compatibility controls for
larger future templates.

| Example payload          | Raw install gas | FastLZ install gas | Split install gas | Raw read/hash gas | FastLZ read/hash gas | Split read/hash gas |
| ------------------------ | --------------: | -----------------: | ----------------: | ----------------: | -------------------: | ------------------: |
| Periodic transfer        |       5,127,851 |          3,741,392 |         5,214,617 |            34,493 |            1,991,696 |              43,077 |
| Periodic borrow          |       5,228,310 |          3,815,624 |         5,315,077 |            34,702 |            2,025,916 |              43,411 |
| Periodic APR replacement |       5,097,108 |          3,722,428 |         5,183,874 |            34,419 |            1,979,270 |              42,947 |

Forced split saves 1,948,619 / 1,982,505 / 1,936,323 gas on each corresponding
hook-instance deployment relative to FastLZ. Registration also reads and hashes
the template, so it incurs the same retrieval difference. Complete per-factory
registration and deployment receipts are retained in the evidence archive.

## Complexity and failure boundaries

| Concern                                  | FastLZ                                                        | Split                                                                                       |
| ---------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| On-chain artifacts per oversized payload | One reader plus compressed payload in one contract            | Two contracts; the primary includes the reader                                              |
| Reader work                              | Decode tokens, lengths, and backreferences                    | Validate lengths/STOP and copy two byte ranges                                              |
| Preparation                              | Pinned encoder, reader image, exact compressed runtime        | Split point, secondary runtime, address-bound primary runtime                               |
| Installation                             | One prepared image transaction                                | Secondary transaction, then primary transaction                                             |
| Resume/inventory                         | One runtime and artifact commitment                           | Both runtimes, linked secondary address, and artifact commitment                            |
| Factory registry                         | One address and original initcode hash                        | The same one address and original initcode hash                                             |
| Current repository tooling               | E15/E16 preparation and verification integrated               | Research runner only; production plan/CLI/UI validators still need integration              |
| Validation maturity                      | Existing codec differential checks and corruption/guard suite | New round-trip, bounds, corruption, deployment, and parity tests; no independent review yet |

Both formats have the same final safety boundary: the factory hashes the
returned original creation bytes against its permanent market or template
commitment before CREATE2. A decoder, copy, or linkage error that produces
different bytes cannot deploy a different artifact. It can make deployment
revert. This does not protect against approving the wrong artifact/hash in
the first place.

Returning the right bytes once is insufficient attestation for an arbitrary
executable store. With split storage, deployment tooling must compare the
entire secondary runtime and the entire primary runtime, including its linked
address, with the prepared artifacts, then check the original-byte hash.
The reader's bounds and STOP checks do not replace those checks. There are no
new mutable dependencies when the two expected immutable runtimes are used.

The research runner already verifies both installed runtime images, the reader
prefix, the bound footer address, and the reconstructed initcode hash. The
production `LibDeployment.isValidInitCodeStorage` currently recognizes raw and
FastLZ images only. Do not feed a split store into the existing release ceremony
and assume its preparation/verification support is complete.

## Qualification and evidence

- Full default suite with seed `0x5eed`: 880 passed, zero failures or skips.
  The three invariant campaigns retain their 2,000-run/depth-30 budgets:
  180,000 handler calls, zero reverts.
- Eleven new split tests pass under the deployment profile, including 1,000
  fuzz cases per fuzz test. Cases cover empty/small/maximum payloads, random
  bytes crossing the chunk boundary, missing/truncated/trailing/non-STOP
  secondaries, mutated reader/footer/payloads, constructor context/arguments,
  ETH forwarding, and duplicate CREATE2 salts.
- Both factories reject corrupted market bytes and changed approved hook
  bytes. Restoring the market payload permits the same deployment afterward.
- Three strict-limit deployment tests pass: the existing FastLZ matrix and
  the new split matrix each deploy six production and six composition markets
  and exercise them through repayment. Exactly two stores are created per
  split payload. These tests do not replace deployed code with `vm.etch`.
- A separate controlled parity test uses code replacement to hold storage
  addresses fixed. The 114 actual local transactions independently reproduce
  exact address/runtime/state/event parity without that substitution, and
  compare composed-hook addresses and runtime too.
- All fourteen existing target creation/runtime artifacts match E22 in both
  default and deployment profiles. Changed Solidity passes formatting and
  Solhint; the transaction runner passes formatting and JavaScript syntax checks.

The first RPC attempt stopped when it queried a transaction receipt before
Anvil had mined it. The runner now polls for the receipt, as the existing E15
runner does. The failed attempt is preserved; the completed 114-transaction
run has no failed receipts. No contract change was needed for that correction.

Concise measurements: [e23.json](./results/e23.json).
Full logs, prepared images, source snapshots, artifacts, transaction requests
and receipts:
`/home/kethcode/wildcat/bytecode-research/2026-09-27/e23/`.
The completed transaction run is `transactions-qualified/`; regression logs
are in `full-suite/`, `focused-deploy/`, and `strict-deployment/`.

## Adoption work if split is selected

1. Integrate raw-or-split artifact preparation into the deployment scripts and
   plan generators. Generalize the prepared-runtime constructor's current
   `CompressedInitCodeStorage` name; its implementation already installs either
   image without encoding during the transaction.
2. Add companion labels, deterministic linkage, partial-deployment resume, and
   exact two-runtime verification to manifests, CLI/UI predicates, and inventory.
   Keep original creation-code commitments and raw storage for fitting hooks.
3. Review the new reader and qualify those deployment-tooling changes. Do not
   remove the FastLZ comparison evidence merely because another format is chosen.
4. Confirm the remaining network limits, rehearse the final deployment plan on
   the required Anvil fork, then generate the final inventory, source/artifact
   freeze, and review delta. The local comparison is not that rehearsal.

The current branch adds an alternative and its evidence. It does not alter the
parent branch's compressed path or silently switch the production ceremony.

## Reproduce

Run from the repository root. Use a new receipt directory for the RPC run.
The focused command exports the prepared images consumed by that runner.

```sh
FOUNDRY_PROFILE=deploy forge test --match-contract '^(SplitInitCodeTest|SplitStorageDeploymentTest|SplitStorageIntegrityTest|SplitStorageParityTest)$' --fuzz-seed 0x5eed -vv
FOUNDRY_PROFILE=deploy forge test --match-contract '^(SplitStorageDeploymentTest|SingleStorageDeploymentTest)$' --code-size-limit 24576 -vv
node scripts/research/storage-comparison-rpc.js /tmp/wildcat-split-comparison
forge test --summary --fuzz-seed 0x5eed
```
