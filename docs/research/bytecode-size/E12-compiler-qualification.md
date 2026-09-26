# E12: qualify the size compiler

Source parent: `a4ca461` (E09 and E11 retained).

Hypothesis: correct memory-safe annotations can let the compiler spill a large
test contract's stack under E05, while leaving the measured production
contracts unchanged. This is compiler qualification, not a claimed size saving.

## Diagnosis and patch

The initial broad no-F runs failed with a Yul stack-depth error and no source
location. Isolated standard-JSON compilations narrowed it to WildcatMarketTest;
the other selected market tests compiled. Annotating only that test's
parameter-decoding read did not resolve the failure.

The remaining relevant memory operations are the error paths in MathUtils and
SafeCastLib. They write only the first two scratch words: either Panic's selector
and code, or MulDivFailed's selector. Arithmetic-only blocks touch no memory.
All can be annotated memory-safe without changing a condition, instruction,
return value, rounding rule or error. The test reader accesses three words inside
the allocated return buffer after checking its length; it is annotated too.

The isolated market test then compiled successfully, with a runtime memoryguard.
No assertions, fuzz bounds or test paths were removed. LibStoredInitCode's
memory-safe helpers are already part of E09.

A second failure came from `test/invariants/MarketMatrixHandler.sol`. The old
focused runner excluded unselected `.t.sol` files but still compiled every
other test helper. Capturing Forge's exact solc input and compiling that handler
alone reproduced the second failure. Disabling dynamic test linking did not
help; the final qualification retains the normal linking setting.

The focused runner now resolves imports and literal deployment-artifact paths
from its selected tests and the complete production source tree. Unreachable
test helpers are excluded from that focused build. It still runs the same
selected tests and adds the arithmetic suites relevant to these annotations.
The invariant handler's no-F compilation failure remains unresolved. The full
invariant suite is not part of this qualification; selecting these compiler
settings for release still requires making that suite compile and running it.

## Measurements and qualification

Both canonical runs 44 and E05 runs 1/no F produce **identical creation and
runtime bytecode on all ten measured targets** before and after E12. Full ABIs
and normalized storage layouts also match. This is an exact byte comparison,
not merely matching lengths. [Measurements](./results/e12.json).

External diagnostics: `diagnose-market-main/`, `diagnose-market-others/`,
`diagnose-market-main-ir/` and `diagnose-market-safe-arithmetic/`. Earlier failed
runs remain recorded separately from the successful qualification. The second
failure is isolated in `diagnose-invariant-handler/`; `diagnose-forge-input/`
contains Forge's original standard-JSON input.

**435 focused tests pass** at runs 1/no F (`e12-all-noF-reachable/`), with the
existing 1,000-run fuzz configuration and seed 0x5eed. This includes the market,
repayment, hook, factory, storage codec and arithmetic suites.
The final arithmetic and bounded-call suites also pass **70 tests at canonical
runs 44** (`e12-arithmetic-default/`).

**Two strict deployment tests pass**, covering 12 combinations: both market
types with all three production templates and the three largest periodic
composition examples (`e12-deployment-noF-reachable/`). Each uses a single
compressed storage contract. The EVM enforces the actual 24,576-byte code limit;
no market runtime is replaced or etched into an address. Every combination
completes deposit, borrow, repay and scheduled closure.

All ten final strict-deployment artifacts exactly match the independent size
runner's creation bytes, runtime bytes, complete ABI and normalized layout.
The artifacts and comparisons are archived with that deployment receipt.
The production artifacts also matched during the broad behavioral run. An
intermediate comparison of a composition mock differed between build graphs;
the final strict build and all-ten comparison are the authoritative deployment
evidence, not that interrupted comparison.

Decision: retain the annotations with the E05 compiler candidate. They make the
focused test graph buildable without changing measured production binaries.
Canonical runs 44 remains the repository default. This does not claim complete
release qualification or resolve the baseline's pending integration-test updates.
