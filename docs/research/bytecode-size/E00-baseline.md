# E00: reproducible baseline

Source: `7b47eecb3832b74a37416d88e16a67bb8e7b060a`.

Hypothesis: native standard-JSON compilation can provide isolated, repeatable
measurements without altering the release configuration or Forge caches.

Implemented [the runner](../../../scripts/research/bytecode.py). It follows the
imports of the ten target contracts, pins Solidity 0.8.25/Cancun/viaIR/metadata,
and saves the complete compiler input, output, executable hash, source hashes,
settings and timestamps outside the repository. Each receipt uses a new directory.

Result: all ten creation and runtime bytecodes match the preceding production
Forge artifacts byte for byte. Full ABIs match after sorting entries (Forge
orders them differently); all fields and duplicate entries remain checked.
Normalized storage layouts match too. [Sizes](./results/e00.json).
The first comparison stopped on ABI entry order; correcting the comparison
allowed verification of the already completed compiler output. No Solidity changed.

Reproduce from this source with:

```sh
python3 scripts/research/bytecode.py /absolute/path/to/new-receipt \
  --forge-reference /absolute/path/to/reference-forge-out
```

The external receipt is `bytecode-research/2026-09-26/e00/` alongside this repo.
Focused behavior qualification is inherited from the baseline: 324 passing
tests, two known size-gate failures. No runtime test rerun was needed for this
measurement-only change. Keep the runner for subsequent experiments.
