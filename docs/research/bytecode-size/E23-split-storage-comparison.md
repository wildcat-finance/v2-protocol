# E23: two-contract initcode storage versus FastLZ

Source parent: `94c0a42`. Branch: `codex/split-initcode-comparison`.
Status: in progress.

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

- [ ] Implement the two-contract format and prepared runtime builder; document
  its exact capacity, footer, validation, and deployment order.
- [ ] Test round trips, chunk boundaries, malformed/missing/wrong secondary
  stores, constructor arguments/context, and factory rejection of wrong bytes.
- [ ] Exercise both market families and all three hook templates, including
  composed hooks, with the actual code-size limit. Compare initialized market
  code/state/events against the compressed route.
- [ ] Run matched local transactions for storage installation, factory and hook
  deployment, and market creation. Report one-time versus per-use gas, aggregate
  stored bytes, transaction counts, and the measured break-even point.
- [ ] Compare code, tooling, validation, and operational complexity. Record what
  is demonstrated and what remains before either option can be released.
- [ ] Commit signed kethcode checkpoints on this branch. Do not push or select
  the alternative for release without the user's review.

This is a deployment-format comparison on a local chain. The deployment-plan
rehearsal on an Anvil fork, final inventory/freeze, audit delta, downstream
integrations, and export/removal of working documents still follow it.
