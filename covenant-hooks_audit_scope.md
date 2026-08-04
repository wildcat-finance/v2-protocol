# Summary

`RevolvingCovenantHooks` and `RevolvingCleanDownHooks` (v2-protocol/src/access/)
are hooks templates for **revolving** markets that add mechanical
conditions-precedent to the borrow path. They translate two covenants that turn
up in essentially every TradFi revolving credit facility and that we have no
analogue for in the shipped templates.

- **Clean-down** (`CleanDownCovenant`): the facility has to return to zero drawn
  for `duration` consecutive seconds at least once every `interval` seconds,
  which evidences use as a revolver rather than disguised term debt. Enforcement is
  a drawstop, not a default: once overdue, draws that would leave the market
  drawn revert, and drawing resumes as soon as a fresh qualifying streak
  completes. A matured streak gets credited inside the transaction that consumes
  it, so there's no keeper and no liveness dependency.
- **Cross-market delinquency gate** (`CrossMarketDelinquencyCovenant`): the
  on-chain analogue of a cross-default clause. Draws revert while the borrower
  is delinquent on any watched market, or under `penaltyOnly`, only while
  they're past grace and accruing penalty APR. The watch-list is permissionless,
  verified against the arch controller and the instance's borrower, and capped
  at 30 entries because the gate iterates it on the borrow path.

`RevolvingCleanDownHooks` ships as a deployable template in its own right
rather than as test scaffolding. It's the configuration for a borrower who wants
clean-down discipline without cross-default exposure, and it carries no
watch-list, no gate storage and no borrow-path iteration.

Both are additive. No existing contract is modified. Access control, minimum
deposits, transfer policy and the APR/reserve constraint path are inherited
from `CovenantHooksCore`, which is a near-verbatim lift of `OpenTermHooks`
(244 nSLOC) with the covenant seams factored out.

Covenants are abstract mixins rather than separate deployed contracts, because
a market stores exactly one hooks address. A concrete template inherits only
the covenants it wants and pays nothing in bytecode, storage, ABI or
borrow-path work for the rest. `RevolvingCleanDownHooks` keeps that
property tested: `test_getWatchedMarkets_AbsentFromTemplate` checks the gate's
entire ABI is missing from a template that doesn't inherit it.

Templates are revolving-only. The covenants read `drawnAmount()`, which
standard markets don't implement, and `CovenantHooksCore`'s constructor checks
the deploying factory's name so you can't create an instance through the
standard hooks factory.

`RevolvingDrawnMath` holds the drawn-amount transitions. The hooks predict the
post-transition drawn amount from inside `onBorrow`/`onRepay`, which run before
`WildcatMarketRevolving` updates its own value, so the two have to agree
exactly.
The library is one definition of that arithmetic; the market still applies its
formulas inline (see Open Items).

Tests (`test/access/RevolvingCovenantHooks.t.sol`,
`test/access/RevolvingCleanDownHooks.t.sol`,
`test/access/covenants/CovenantBase.t.sol`) cover covenant configuration
validation at market creation, clean-down crediting and expiry, the
over-repayment exemption, gate behaviour in both modes, watch-list
authorisation and pruning, the composition seam, and a differential suite
pinning `RevolvingDrawnMath` to the market's real transitions. 26 tests, all
passing; `RevolvingDifferential.t.sol` (4), `HooksFactoryRevolving.t.sol` (45)
and the three existing hooks suites (307) are unaffected.

## Baseline

Reviewed baseline is `release/v2.5`, not `main`. The templates are built on the
revolving primitives introduced in v2.5 (`WildcatMarketRevolving`,
`HooksFactoryRevolving`) and do not compile without them. Diff against
`release/v2.5`, not the deployed protocol.

## Audit Scope

| Filepath | nSLOC |
| --- | --- |
| src/access/covenants/CovenantHooksCore.sol | 251 |
| src/access/covenants/CrossMarketDelinquencyCovenant.sol | 62 |
| src/access/covenants/lib/CrossMarketGateLib.sol | 96 |
| src/access/covenants/lib/CovenantEvents.sol | 18 |
| src/access/covenants/CleanDownCovenant.sol | 78 |
| src/access/RevolvingCovenantHooks.sol | 54 |
| src/access/covenants/CovenantBase.sol | 35 |
| src/access/RevolvingCleanDownHooks.sol | 33 |
| src/access/covenants/CommitmentScheduleCovenant.sol | 26 |
| src/access/covenants/lib/CommitmentScheduleLib.sol | 59 |
| src/access/covenants/DrawTimelockCovenant.sol | 50 |
| src/access/covenants/lib/DrawTimelockLib.sol | 134 |
| src/access/RevolvingScheduleHooks.sol | 38 |
| src/access/RevolvingTimelockHooks.sol | 42 |
| src/libraries/RevolvingDrawnMath.sol | 25 |
| **Total** | **930** |

All four concrete templates are in scope and registered by the same deploy
script. `CovenantHooksCore` changed in this revision: `_initCovenants` now
receives `DeployMarketInputs` (the timelock's delay floor is checked against
`withdrawalBatchDuration` at creation), and an offset overload of
`_readUint128Cd` was added beside the existing `uint32` reader. Both existing
templates were updated for the widened seam; behaviour is otherwise
unchanged.

### Novel surface

581 overstates the review burden. `CovenantHooksCore` (251) is
`OpenTermHooks` (244) with the deposit, withdrawal, transfer, minimum-deposit
and APR paths carried over unchanged, and three seams added:
`_requiredCovenantFlags`, `_initCovenants`, and the revolving-factory
constructor check. Anyone who has already audited `OpenTermHooks` should diff the two rather than
read the file cold.

Excluding that inherited body, the genuinely new logic is approximately
**680 nSLOC**:

| Component | nSLOC | Notes |
| --- | --- | --- |
| Covenant mixins and libraries | 452 | The substance: streak accounting, gate iteration, schedule validation, timelock windowing and announcement queue |
| Concrete templates | 167 | Wiring only: flags, config parsing, hook bodies |
| Covenant base | 35 | Interfaces plus two drawn-amount predictions |
| Drawn-amount library | 25 | Pure arithmetic, mirrors the market |

The draw timelock library (134) is the densest single file: a rolling
cumulative-headroom baseline plus a nonce-ordered announcement queue with
expiry skipping. `test_onBorrow_SplitDrawsShareHeadroom` pins the anti-split
property the baseline exists for, and is the test to break first if the
windowing logic is touched.

### Deployed size

Templates are stored as init code by `LibStoredInitCode`, so the creation code
of each has to fit under the EIP-170 limit of 24,576 bytes. Measured under
`FOUNDRY_PROFILE=deploy` (via_ir, optimizer, 200 runs):

| Contract | Creation code | Headroom |
| --- | --- | --- |
| RevolvingCovenantHooks | 23,495 | 1,081 |
| RevolvingCleanDownHooks | 20,526 | 4,050 |
| PeriodicTermHooks (reference) | 21,924 | 2,652 |

The combined template fits with roughly 4% to spare. Real, but thin. The ceiling is hard rather than soft: go over it and the
template simply won't deploy. Two consequences.

First, **any change to `CovenantHooksCore` or to either mixin wants
re-measuring**, not just re-testing. A few hundred bytes added to the shared
core lands on the combined template twice over.

Second, **a template combining three or more covenants will not fit.** The
mixin architecture composes per-template precisely so this is a choice rather
than a wall, but the practical limit is now measured and the combined template
is close to full. The cross-market gate's body has been moved into `CrossMarketGateLib`, an
external library reached by `DELEGATECALL`, which recovers roughly 1,250 bytes
on the combined template and keeps each further covenant's body out of it. That
introduces a link-time dependency: templates must be compiled against the
library's address, and the deploy script does not yet do this. See the covenants
README. Style of the boundary is subject to Kethic's final review.

The reference row does not match the `PeriodicTermHooks` init-code storage
deployed on Sepolia (21,054 bytes). That gap is source drift, since the
deployed instance predates the current template revision, rather than a
toolchain mismatch.

### Out of scope

`src/lens/CovenantLens.sol` (155 nSLOC) is read-only, holds no state, is
referenced by no contract in scope, and can't affect market behaviour. Listed
for completeness rather than review.

## Areas of focus

1. **Drawn-amount prediction agreement.** `CovenantBase._drawnAfterBorrow` and
   `_drawnAfterRepay` have to produce exactly what `WildcatMarketRevolving`
   applies immediately afterwards. `test/access/covenants/CovenantBase.t.sol`
   pins this: each case reads the inputs the hook would see, computes the
   library's answer, performs the operation and asserts the market agreed,
   across fixed cases and two fuzzed ones. Mutation-checked, in that a one-off
   introduced into the library fails four of the five tests.
2. **Reentrancy on the self-check.** The gate reads the calling market's state
   from the hook's `intermediateState`, never `currentState()`, which is
   reentrancy-guarded while the borrow path holds the lock. Reintroduce a self
   `currentState()` call and every draw on a gated market reverts.
   Guarded by `test_onBorrow_HealthySelfDoesNotBlock`.
3. **Watch-list bound.** `MAX_WATCHED_MARKETS = 30` bounds borrow-path gas.
   Closed markets are skipped during iteration and can be pruned
   permissionlessly. Worth confirming a borrower can't be griefed into an
   unusable facility by watch-list saturation, keeping in mind only their own
   arch-controller-registered markets get in.
4. **Storage packing.** `CleanDownState` (uint32, uint32, uint40, uint40) and
   `CrossMarketGateConfig` (bool, bool) each occupy one slot. The covenants own
   separate mappings, so a template inheriting both pays one extra cold SLOAD
   on the borrow path relative to a single packed struct.
5. **Configuration validation.** Inconsistent covenant words revert at market
   creation rather than deploying inert config: an interval without a duration,
   an interval that doesn't exceed its duration, and `gateOnPenaltyOnly`
   without the gate.

## Open Items

- **Point `WildcatMarketRevolving` at `RevolvingDrawnMath`.** The market
  applies its drawn-amount formulas inline and the library holds a second copy
  that the hooks use, so the two can drift. I trialled the refactor: it's
  behaviourally identical [19/19 revolving tests pass] but moves deployed
  bytecode by 44 bytes, which moves `marketInitCodeHash`, an immutable
  constructor arg on `HooksFactoryRevolving` that feeds CREATE2 market
  addresses.

  That cost is currently zero. No revolving factory exists on mainnet or
  Sepolia, so it would simply be deployed carrying the new hash. The window
  shuts the moment script 03 runs on mainnet, and after that the change needs a
  new factory, new addresses and inventory churn. **If it's going in, it wants
  to go in this release.** The differential suite covers the drift either way.
- **Deployment.** `script/deploy/v2-6/01-deploy-covenant-hooks-templates.s.sol`
  deploys both templates and registers them on the revolving factory. Fees come
  from environment variables with no defaults, so a misconfigured run fails
  closed. It's the first script of the v2.6 release and requires `RELEASE_TAG=v2-6`,
  since deployment labels carry the tag and the base class still defaults to
  `v2-5`.
