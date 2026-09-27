# E24: adopt raw and split initcode storage

Source parent: `1e0f3d8`. Branch: `codex/split-initcode-comparison`.
Status: in progress.

The user selected split storage after reviewing E23. Oversized creation code
uses two immutable contracts; fitting code retains raw `STOP || initcode`
storage. FastLZ remains research evidence, not the selected deployment route.
Keep compiler settings, market/factory interfaces, and artifact commitments.

## Plan and tracker

- [x] Record the decision and adoption scope.
- [ ] Integrate prepared raw/split installation and exact verification into
  direct deployment, including secondary labels and partial-deployment reuse.
- [ ] Generate secondary-before-primary plan entries and inventory records.
  Bind the secondary address without compression in the installation transaction.
- [ ] Extend CLI/UI predicates and activation checks to verify both complete
  runtimes, their link, and the original creation-code hash on execution/resume.
- [ ] Switch normal production test fixtures and size checks to the selected
  format while preserving the compression comparison controls.
- [ ] Qualify Solidity, tooling, deployment limits, unchanged production
  artifacts, and actual execution/resume of the generated storage plans.
- [ ] Update maintained deployment documentation and the release tracker;
  make signed kethcode checkpoints. Do not push.

The primary plan predicate commits the runtime with its secondary-address
field zeroed, separately commits the secondary runtime, and references the
secondary deployment output. Verification checks the actual embedded address,
both runtime commitments, then the original creation-code hash. This preserves
literal artifact hashes without depending on a predicted transaction nonce.

The final full ceremony on an Anvil fork, network-limit decisions, final
inventory/freeze, audit delta, and downstream integrations remain release work.
This task qualifies adoption of the selected storage format.
