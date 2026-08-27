# Contract Inventories

These generated files pin the first-party Solidity source and ABI surface for
each release. They record:

- every `src/` source unit, Git blob, content hash, and declaration;
- compiler settings and exact submodule commits used to extract the ABIs; and
- canonical ABI hashes, function and error selectors, and event topics.

The generator rejects missing or duplicate artifacts and any source hash that
does not match the requested commit or its pinned submodules. The recorded
compiler settings describe ABI extraction. They do not attest to deployed
bytecode.

Build the exact release checkout, then run the generator from a current checkout
that contains [`generate-contract-inventory.js`](../../../scripts/generate-contract-inventory.js):

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

Use `--check` with the same arguments to verify an existing inventory without
rewriting it.
