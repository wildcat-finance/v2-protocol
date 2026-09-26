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

- [ ] Implement registration and per-instance checks in both factories.
- [ ] Update artifact-derived hashes, plan predicates, and registration callers.
- [ ] Test raw/compressed stores, incorrect registration hashes, changed decoder
  output, standalone and combined market/hook creation, rollback, and recovery.
- [ ] Run both compiler configurations and existing invariants; verify that
  removing the checks makes the intended tests fail.
- [ ] Measure factory size, registration/deployment gas, deliberate ABI/storage
  changes, and unchanged market/hook artifacts. Repeat strict deployments.
- [ ] Record results and a signed kethcode checkpoint. Keep runs 44 as the normal
  configuration and leave the supplied reference documents uncommitted.
