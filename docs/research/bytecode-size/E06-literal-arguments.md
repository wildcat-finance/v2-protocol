# E06: remove runtime-obscured constants

Source parent: `fe2adad` (E05 then added documentation only at `28ee38c`).

Hypothesis: `_runtimeConstant` prevents expensive constant specialization. Once
FunctionSpecializer is disabled, ordinary literal arguments might remove its
scratch-memory work and save bytes.

Replaced its boolean and zero-address call sites with literal values. Measured
both canonical runs 44 and E05 runs 1/no F. [Rejected patch](./patches/e06-literal-arguments.patch).

Result: **worse under both configurations**. Creation code grows 2,395 bytes per
market at runs 44, and 48 bytes per market even with FunctionSpecializer removed.
Other optimizer passes can still react to literal arguments. Do not assume the
runtime obfuscation is redundant merely because the named specialization pass
is disabled. [All sizes and settings](./results/e06.json).

Validation: both variants compile with unchanged ABIs and normalized layouts.
No behavioral tests were run because neither variant meets the size hypothesis.
Decision: reject and restore the source before continuing. Only the patch and
research record are committed. Receipts: external `e06-literals-*` directories.
