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
runs after construction. Hook templates are owner-approved deployment inputs;
their stored address does not by itself establish that an executable reader is
the canonical, context-independent reader.

## Work and qualification tracker

- [ ] Cross-check Solady against upstream FastLZ level 1 at the commit referenced
  by the vendored library. Keep that reference test-only and reproducible offline.
- [ ] Exercise short, long, repetitive and incompressible payloads, storage and
  creation limits, memory boundaries, constructor arguments, CREATE/CREATE2,
  revert propagation and repeated reads.
- [ ] Characterize malformed streams and hostile executable stores. Solady's
  decoder is not a parser for arbitrary untrusted streams; reject unexpected
  storage bytecode before treating its output as an approved artifact.
- [ ] Verify canonical storage runtime and decoded bytes against the original
  artifact in deployment tooling, including existing-store reuse and plan mode.
- [ ] Check the market's full decoded hash before CREATE2. Retain the existing
  address check and test failure atomicity in both factories.
- [ ] Compare factory-deployed market/hook runtime and initialization against
  raw-code controls, with identical deployment addresses and constructor context.
- [ ] Run the expanded suite at runs 44 and runs 1/no F, the full existing focused
  qualification including invariants, and real-limit factory deployment checks.
- [ ] Record sizes, changed interfaces or storage, gas feasibility, limitations
  and signed checkpoints. Keep the normal compiler configuration at runs 44.

The raw comparison is an oracle for byte identity, not evidence that oversized
raw storage fits EIP-170. Real-limit tests separately deploy every compressed
store and market without replacing their code. Mutation tests may deliberately
replace test storage code to model corrupt or hostile deployment inputs.

No new repayment-date stateful invariant model is part of this experiment.
No mainnet deployment, push or release adoption is authorized by these tests.
