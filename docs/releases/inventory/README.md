# Contract inventories

Each generated inventory pins the first-party Solidity source and ABI surface
for one release. It records:

- Every `src/` source unit, Git blob, content hash, and declaration.
- Compiler settings and exact submodule commits used to extract the ABIs.
- Canonical ABI hashes, function selectors, error selectors, and event topics.

The generator rejects:

- Missing artifacts.
- Duplicate artifacts.
- Source hashes that do not match the requested commit or its pinned
  submodules.

Recorded compiler settings describe ABI extraction. They do not attest to
deployed bytecode.

Build the exact release checkout first. Then run the generator from a current
checkout containing
[`generate-contract-inventory.js`](../../../scripts/generate-contract-inventory.js):

```console
FOUNDRY_PROFILE=default FOUNDRY_LINT_LINT_ON_BUILD=false forge build \
  --root <release-checkout> --force src

yarn inventory:contracts \
  --repo <release-checkout> \
  --release <release> \
  --ref HEAD \
  --artifacts out \
  --output docs/releases/inventory/<release>.json
```

Add `--check` to verify an existing inventory without rewriting it.
