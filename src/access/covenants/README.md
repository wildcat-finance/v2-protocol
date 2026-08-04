# Revolving covenant hooks

Composable conditions-precedent for revolving Wildcat markets.

Every revolving credit facility in traditional finance gates each drawing on
conditions: no default continuing, representations repeated, clean-down
observed. Wildcat's shipped hooks templates have no analogue for any of that,
which is a gap you notice the moment a credit desk asks what the covenants
are. These contracts add four covenants that are computable from chain state
alone, plus the architecture to add more: a cross-market delinquency gate, a
clean-down requirement, a commitment-reduction schedule, and a draw timelock.
They ship across six templates spanning all three term structures, so a
covenant-bearing market can be open-term, fixed-term, or windowed.

Three of the four are **drawstops**. Breach one and new draws are blocked, and
that's it: no acceleration, no forced repayment, nobody adjudicating. Lender
exit rights stay untouched, and drawing resumes once the condition clears.
That's a deliberate choice. A drawstop is the proportionate remedy for a
revolver, it needs no third party to invoke it, and it can't be waived by
inattention.

The fourth works the other way round. The draw timelock doesn't stop anything;
it makes large draws wait long enough that any lender who dislikes one can be
fully out before it executes. Same spirit, no adjudicator, but the remedy is
the exit right itself rather than a block, and the covenant map below explains
why that's the right shape for this covenant in particular.

Covenants compose with term behaviour too. Alongside the open-term host, two
host mixins gate withdrawals the way the standard term templates do:
`FixedTermHost` locks lenders until a term end, and `PeriodicTermHost` opens
recurring exit windows. That's what makes a fixed-term amortising revolver and
a window-aware timelock buildable, and both ship as templates.

## Contents

| File | Role |
| --- | --- |
| `CovenantBase.sol` | Market and registry interfaces, plus drawn-amount prediction shared by all covenants |
| `CovenantHooksCore.sol` | Abstract host: `OpenTermHooks`-equivalent access control, market registry, hook scaffolding |
| `CrossMarketDelinquencyCovenant.sol` + `lib/CrossMarketGateLib.sol` | Cross-market delinquency gate: mixin surface plus library bodies |
| `CleanDownCovenant.sol` + `lib/CleanDownLib.sol` | Clean-down covenant: mixin surface plus library bodies |
| `CommitmentScheduleCovenant.sol` + `lib/CommitmentScheduleLib.sol` | Commitment-reduction schedule: mixin surface plus library bodies |
| `DrawTimelockCovenant.sol` + `lib/DrawTimelockLib.sol` | Draw timelock: mixin surface, announcement queue, library bodies |
| `FixedTermHost.sol` | Host-behaviour mixin: withdrawals blocked before a fixed term end |
| `PeriodicTermHost.sol` | Host-behaviour mixin: withdrawals only inside recurring windows |
| `FixedTermHost.sol` | Host mixin: withdrawals blocked until a fixed term end |
| `PeriodicTermHost.sol` | Host mixin: withdrawals only inside recurring windows; the timelock's exit floor reads this schedule |
| `lib/CovenantEvents.sol` | Events and errors shared between every mixin and its library |
| `lib/CovenantLibraries.sol` | Deterministic library addresses and salts |
| `../RevolvingCovenantHooks.sol` | Deployable template: gate and clean-down |
| `../RevolvingCleanDownHooks.sol` | Deployable template: clean-down only |
| `../RevolvingScheduleHooks.sol` | Deployable template: commitment schedule only |
| `../RevolvingTimelockHooks.sol` | Deployable template: draw timelock only |
| `../FixedTermScheduleHooks.sol` | Deployable template: fixed term plus commitment schedule |
| `../PeriodicTimelockHooks.sol` | Deployable template: periodic windows plus window-aware timelock |
| `../FixedTermScheduleHooks.sol` | Deployable template: fixed term plus commitment schedule |
| `../PeriodicTimelockHooks.sol` | Deployable template: periodic windows plus window-aware timelock |
| `../../libraries/RevolvingDrawnMath.sol` | Pure drawn-amount transitions |
| `../../lens/CovenantLens.sol` | Read-only view surface |

Tests live at `test/access/RevolvingCovenantHooks.t.sol` (17),
`test/access/RevolvingCleanDownHooks.t.sol` (4),
`test/access/RevolvingScheduleHooks.t.sol` (5),
`test/access/RevolvingTimelockHooks.t.sol` (9),
`test/access/FixedTermScheduleHooks.t.sol` (5),
`test/access/PeriodicTimelockHooks.t.sol` (6) and
`test/access/covenants/CovenantBase.t.sol` (5).

---

# How it fits together

## One hooks address per market

A Wildcat market stores exactly one hooks address, so covenants can't be
separate deployed contracts sitting side by side. That single constraint shapes everything else here, so it's worth sitting with
for a second.

The obvious alternative is one dispatcher hook holding a mutable list of
covenant module addresses, which buys runtime composability. It also means a
module registry, and a module registry is an admin surface, which makes it a
compellable control point. For this protocol that trade runs the wrong way, so
covenants are **abstract mixins composed at compile time** instead.

What that gives you:

- A template inherits only the covenants it wants. Whatever it doesn't inherit
  costs it nothing in ABI or borrow-path work.
- Term behaviour composes the same way. `FixedTermHost` and `PeriodicTermHost`
  are host mixins rather than covenants: no library, storage and errors of
  their own, wired into a defaulted `_beforeQueueWithdrawal` seam on the core.
  An open-term template pays nothing for their existence.
- Term structure composes the same way. `FixedTermHost` and `PeriodicTermHost`
  are host-behaviour mixins, not covenants: no library, a few words of storage,
  and a `_beforeQueueWithdrawal` seam on the core that they override to gate
  withdrawal queueing. An open-term template pays nothing for either.
  `PeriodicTermHost` mirrors the window arithmetic of `PeriodicTermHooks`
  line for line, and has to keep doing so: the timelock's exit guarantee is
  computed from that schedule.
- Hook dispatch flags are derived per template. A template that never needs to
  observe repayments doesn't require `onRepay`, and pays nothing for it.
- Past what the borrower sets at market creation, nothing is configurable after
  deployment. No registry, no owner, no upgrade path.

`RevolvingCleanDownHooks` exists partly so that claim stays tested instead of
merely asserted: `test_getWatchedMarkets_AbsentFromTemplate` checks the gate's
entire ABI is missing from a template that doesn't inherit it.

## Why the bodies live in external libraries

Inheritance flattens. A template compiles every covenant it inherits into one
deployed contract, so mixins give you source separation and the option to
leave a covenant out, but once you've inherited one you're carrying its
bytecode.

Templates are stored as init code, so each one's creation code has to stay under
EIP-170's 24,576 bytes. That's a hard ceiling: go over and the template simply
won't deploy.

So each covenant's body sits in an external `library` with `public` functions,
reached by `DELEGATECALL`. The code lives at its own address and doesn't count
against the template's limit. Each mixin keeps the storage and the external
surface and delegates the work.

Measured under `FOUNDRY_PROFILE=deploy`:

| Template | Creation code | Headroom |
| --- | --- | --- |
| RevolvingCovenantHooks | ~21,400 | ~3,100 |
| RevolvingCleanDownHooks | ~19,900 | ~4,600 |
| RevolvingScheduleHooks | ~20,100 | ~4,400 |
| RevolvingTimelockHooks | ~20,100 | ~4,400 |
| FixedTermScheduleHooks | ~20,600 | ~3,900 |
| PeriodicTimelockHooks | ~21,400 | ~3,100 |

The saving is per covenant, which is what made the third and fourth cheap and
keeps a fifth and sixth affordable. Each body stays at its own address and the
template carries only the dispatch.

The costs, so nobody's surprised later: roughly 2,600 gas cold per library call on the borrow
path, paid by the borrower on every draw; a wider audit surface, since template
behaviour now depends on contracts at addresses instead of inlined code; and a
compile-time link, handled below.

## Events, errors and the ABI trap

Events and errors are declared in `ICovenantEvents`, referenced by both the
mixins and the libraries. **The mixins inherit it**, which keeps every error and
event in the template's ABI even though they're raised from library code.
Selectors and topic hashes are unchanged either way.

Skip that inheritance and the errors quietly vanish from the ABI while still
reverting on-chain, so anything decoding against the template's interface breaks
while everything on-chain looks fine. Easy mistake to make; the inheritance line in each mixin is load-bearing.

## Linking

`public` library functions link at compile time, so templates have to be
compiled against a known library address or their creation code comes out
carrying `__$...$__` placeholders. Storing that as init code produces a template
whose covenants revert on every call.

Libraries are therefore deployed through the canonical deterministic-deployment
proxy at `0x4e59b44847b379578588920cA78FbF26c0B4956C` with fixed salts, which
puts them at the same address on every chain. Templates compile against those
addresses up front and deployment stays single-phase.

`foundry.toml` needs the link in every profile the templates are built under:

```toml
libraries = [
  'src/access/covenants/lib/CrossMarketGateLib.sol:CrossMarketGateLib:0x...',
  'src/access/covenants/lib/CleanDownLib.sol:CleanDownLib:0x...',
  'src/access/covenants/lib/CommitmentScheduleLib.sol:CommitmentScheduleLib:0x...',
  'src/access/covenants/lib/DrawTimelockLib.sol:DrawTimelockLib:0x...'
]
```

`CovenantLibraries.sol` is the single source of truth for those addresses and
salts. The deploy script and every test suite import from it. `foundry.toml`
can't import Solidity, so its `libraries` entry is the one duplicate you can't
get rid of: change one, change both, same commit.

Those addresses come out of the compiled library bytecode, so they move if the
compiler version or optimizer settings change. The deploy script recomputes each
one and asserts it matches, so drift fails the run instead of quietly registering
templates linked to an empty address. If you see an address-drift error, regenerate the whole set together, all
four in one commit alongside `foundry.toml`. `CovenantLibraries.sol` carries
the recipe, and the install script does it automatically.

Tests need the library runtime code placed at the linked addresses before they
touch a template, since a fresh test EVM has nothing there and a library call
into an empty address trips the `extcodesize` check. See
`_deployCovenantLibraries` in the covenant suites.

---

# What's implemented

Four covenants ship today across six templates: each covenant behind its own
open-term single-covenant template, the gate and clean-down together in a
combined one, and two term-structured templates carrying the covenants that
earn their keep there, a fixed-term schedule and a periodic window-aware
timelock. What follows is the behaviour a market actually gets; the covenant
map further down carries the scoring and the reasoning about what to build
next.

## Term hosts

Fixed-term and periodic markets are where several covenants earn their full
value, because lenders who can't leave whenever they like are the ones who
need mechanical protection. Two host-behaviour mixins provide the term
structures:

- **`FixedTermHost`** blocks withdrawal queueing before a per-market term end
  (at most 365 days out, validated at creation). Closed markets always pass:
  closure settles the facility, and holding lenders past it protects nobody.
  Term reduction and early-closure switches are left out on purpose; each is
  an owner surface, and covenant hosts ship with as few of those as possible.
- **`PeriodicTermHost`** allows withdrawal queueing only inside recurring
  windows defined by a first window start, a period, and a window duration,
  with the same bounds as `PeriodicTermHooks` and the same arithmetic. It
  also exposes the next-window query the window-aware timelock is built on.

Both wire into a `_beforeQueueWithdrawal` seam on the core whose open-term
default is a no-op, so they compose with covenants exactly the way covenants
compose with each other. Both are also smaller than the templates they
mirror: the fixed host drops term reduction and early-closure switches, the
periodic host drops the APR-proposal machinery. Each of those is an owner
surface, and covenant hosts ship with as few of those as possible; add one
back if a borrower asks, as a decision rather than a default.

Two properties matter for anyone touching them. The periodic window
arithmetic is a line-for-line mirror of `PeriodicTermHooks` and has to stay
one, because the timelock's exit guarantee is computed from this schedule and
a drifted copy would let draws execute before objecting lenders could leave.
And their errors and events are declared locally, not in `ICovenantEvents`,
on purpose: editing that shared file shifts the metadata hash of every
covenant library importing it, which moves all their CREATE2 addresses at
once. Host behaviour has no library, so it has no reason to pay that cost.

The timelock changes meaning across hosts, and the machinery knows it. Every
deadline in the covenant, an announcement's `executableAt` and the roll of
the unannounced-headroom baseline alike, is the later of the constant delay
and a host-supplied exit floor: on open-term hosts the floor is now (the
delay, at least one batch duration, already guarantees exit), and on periodic
hosts it's the end of the first full window after the moment in question plus
one batch duration. Flooring the baseline matters as much as flooring
announcements; the draw timelock section below has the attack that fails
without it. `FixedTermHost` deliberately has no timelock template: giving
notice to lenders who can't leave protects nobody.

## Clean-down

Near-universal in revolving facilities. The drawn balance has to return to zero
for `duration` consecutive seconds at least once every `interval` seconds, which
evidences use as a revolver rather than disguised term debt.

Enforcement is a drawstop. Once overdue, draws that would leave the market drawn
revert, and drawing resumes as soon as a fresh qualifying streak completes.

Three behaviours are deliberate and worth knowing before you read the code:

- **Idle time counts from market creation.** A market that has never drawn
  doesn't arrive at its first deadline already in breach.
- **A matured streak is credited at the moment of the next draw.** A streak
  that matured a second ago gets banked inside the transaction that consumes
  it, so there's no keeper and no liveness dependency.
- **Reclaiming an over-repayment isn't credit.** A draw that leaves the drawn
  amount at zero neither trips the covenant nor breaks a running streak.

Partial repayments don't start a streak. Only reaching zero does.

## Cross-market delinquency gate

The on-chain analogue of a cross-default clause: draws revert while the borrower
is delinquent on any watched market.

The watch-list is permissionless. Anyone can add a market that's registered with
the arch controller and reports this instance's borrower, which reaches markets
from other factories and hooks instances while admitting nothing else. Anyone
can prune closed markets too, since a closed market has settled and can never be
delinquent again. The list is capped at `MAX_WATCHED_MARKETS` (30) because the
gate iterates it on the borrow path and that loop needs a hard gas ceiling.

Two modes. `penaltyOnly` gates on markets past their grace period, so the ones
actually accruing penalty APR, and it's the better default: strict delinquency
will drawstop on transient reserve dips that cure themselves inside grace
anyway.

One trap worth flagging before you modify anything here. The calling market is checked
through the `intermediateState` handed to the hook, never through its own
`currentState()`. That view is reentrancy-guarded and the borrow path holds the
lock, so querying it would revert every draw.
`test_onBorrow_HealthySelfDoesNotBlock` guards the regression.

## Commitment-reduction schedule

A piecewise-constant ceiling on the drawn amount that declines on a pre-agreed
schedule, enforced when the borrower draws. A final ceiling of zero is
availability-period expiry: after that date the facility can be repaid and
exited but not drawn.

Three behaviours are deliberate here too, and they mirror the clean-down
list above:

- **Enforcement is on drawn.** Breach is curable by repaying
  below the schedule, which keeps the drawstop-plus-fee interaction coherent
  and never forces lender capital out. Whether the commitment itself (and so
  the fee base) steps down alongside the drawn ceiling is a market design
  question, left to `setMaxTotalSupply` on purpose.
- **Draws that don't increase the drawn amount are never gated**, so
  reclaiming an over-repayment works even past expiry.
- **Before the first step the ceiling is unlimited.** A schedule is a promise
  about the future, and a market that hasn't got there yet isn't constrained
  by it.

Schedules are validated at market creation: steps strictly increasing,
ceilings strictly decreasing, the first step in the future, at most 24 steps,
and equal-length arrays. Empty arrays disable the covenant. Get any of that
wrong and the deployment reverts, which beats shipping a market with a
schedule nobody intended and finding out at the first gated draw.

## Draw timelock

Draws above a headroom threshold have to be announced at least `delay` seconds
in advance, and `delay` is required at market creation to be no shorter than
the market's withdrawal batch duration, so any lender who dislikes an
announced draw can be fully out before it executes. No approver exists and
nothing is compellable: the draw proceeds against whatever capital voluntarily
stayed.

- **The headroom is cumulative per rolling window, not per draw.** This is
  the design decision that matters, so here's the attack it closes: a per-draw
  threshold is splittable, and twenty sub-threshold draws in one block extract
  the same amount a single announced draw would have delayed. The covenant
  instead tracks a drawn baseline that rolls forward once per `delay` period
  and gates any draw taking the drawn amount more than `threshold` above it.
  Within any window of that length, unannounced net new drawing can't exceed
  the threshold, however finely it's sliced.
- **Announcements are borrower-only**, keyed by market and nonce, and consumed
  in nonce order with expired ones skipped and deleted along the way. Each is
  executable only inside `[executableAt, executableAt + grace]`: without
  expiry, a borrower could pre-position ripe announcements indefinitely and
  the delay would protect nobody.
- **One announcement covers one draw, up to its amount, consumed whole.**
  Partial cover would let unannounced volume ride along with announced volume.
  After a consumed draw the window resets at the new drawn level, since
  lenders had their notice.
- **Pending announcements are capped at 16** so consumption stays bounded on
  the borrow path, and a delay of zero disables the covenant entirely.

The delay is only half the guarantee. Every deadline in the covenant, both an
announcement's `executableAt` and the roll of the unannounced-headroom
baseline, is floored by a host-supplied exit floor: the earliest moment a
lender who learned something at time `from` is guaranteed to be fully out. On
the open-term host the floor is `from` itself, so the delay does all the work
and behaviour is exactly as above. On the periodic host it's the end of the
first full withdrawal window after `from`, plus one batch duration. Flooring
the baseline roll matters as much as flooring announcements: roll on the delay
alone and a borrower dribbles `threshold` per delay-period between windows,
extracting a multiple of the headroom while nobody can leave.
`test_onBorrow_HeadroomDoesNotRollBetweenWindows` pins it, mutation-checked.

Fixed-term markets are excluded entirely, and that's structural rather than
cautious: a timelock giving notice to lenders who can't leave protects
nobody. The covenant map entry below carries the full scoping.

## Configuration

Covenant words get appended to the standard `hooksData` tuple. Trailing words
can be omitted, since calldata beyond the supplied length reads as zero, so
all-zero covenant words deploy a market with open-term behaviour.

`RevolvingCovenantHooks`:

| Offset | Type | Meaning |
| --- | --- | --- |
| `0x00` | `uint128` | `minimumDeposit` |
| `0x20` | `bool` | `transfersDisabled` |
| `0x40` | `uint32` | `cleanDownDuration`; 0 disables the covenant |
| `0x60` | `uint32` | `cleanDownInterval`; has to strictly exceed duration |
| `0x80` | `bool` | `crossMarketGateEnabled` |
| `0xa0` | `bool` | `gateOnPenaltyOnly`; requires the gate |

`RevolvingCleanDownHooks` uses `0x00` to `0x60` only.
`RevolvingScheduleHooks` takes standard ABI encoding rather than fixed words,
because schedules are arrays:
`abi.encode(uint128 minimumDeposit, bool transfersDisabled, uint40[] steps,
uint128[] ceilings)`. The two fixed heads land at the offsets the core reads
for its own fields, and empty arrays disable the covenant.

`RevolvingTimelockHooks`:

| Offset | Type | Meaning |
| --- | --- | --- |
| `0x00` | `uint128` | `minimumDeposit` |
| `0x20` | `bool` | `transfersDisabled` |
| `0x40` | `uint128` | `threshold`; cumulative unannounced headroom per window |
| `0x60` | `uint32` | `delay`; 0 disables; floor is the withdrawal batch duration |
| `0x80` | `uint32` | `grace`; execution window length, has to be nonzero |

`FixedTermScheduleHooks` extends the schedule template's ABI encoding with the
term as a third head:
`abi.encode(uint128 minimumDeposit, bool transfersDisabled,
uint32 fixedTermEndTime, uint40[] steps, uint128[] ceilings)`. The term is
mandatory; empty arrays disable the schedule, which gives a plain
fixed-term revolver.

`PeriodicTimelockHooks` extends the timelock words with the window schedule:

| Offset | Type | Meaning |
| --- | --- | --- |
| `0xa0` | `uint32` | `firstWithdrawalWindowStart` |
| `0xc0` | `uint32` | `periodDuration`; 6 minutes to 365 days |
| `0xe0` | `uint32` | `withdrawalWindowDuration`; at least 1 minute, below the period |

Inconsistent configuration reverts at market creation instead of deploying
inert config: a clean-down interval without a duration or that doesn't exceed
its duration, `gateOnPenaltyOnly` without the gate, a malformed schedule, and
a timelock delay below the batch duration or with zero grace or threshold, a
fixed term in the past or beyond 365 days, and a periodic schedule outside
its bounds.

All covenant templates are revolving-only, because the covenants read
`drawnAmount()` and standard markets don't implement it. `CovenantHooksCore`'s
constructor checks the deploying factory's name, so you can't create an instance
through the standard hooks factory.

---

# Adding a covenant

1. Write `covenants/YourCovenant.sol` as an `abstract contract` inheriting
   `CovenantBase` and `ICovenantEvents`. Own your storage
   (`mapping(address => YourState)`), and declare your events and errors in
   `ICovenantEvents` so they stay in the template ABI.
2. Put the bodies in `lib/YourCovenantLib.sol` as a `library` with `public`
   functions taking storage pointers. Add its address and salt to
   `CovenantLibraries.sol`, take the next salt, and add a line to
   `foundry.toml`.
3. Expose three kinds of `internal` entry point on the mixin:
   `_initYourCovenant(market, ...)` called at creation, one enforcement function
   per hook you care about, and external views.
4. Declare host requirements as abstract functions **on your covenant**, not on
   `CovenantBase`. That way a template inheriting only some covenants
   implements only their requirements. `CrossMarketDelinquencyCovenant` does
   this with `_covenantBorrower()` and `_covenantArchController()`, and
   `DrawTimelockCovenant` with `_timelockBorrower()`.
5. Write a concrete template inheriting `CovenantHooksCore` plus your covenant,
   implementing `version()`, `_requiredCovenantFlags()`, `_initCovenants()`,
   and the hook bodies that call your enforcement functions. `_initCovenants`
   receives the full `DeployMarketInputs` alongside `hooksData`, so covenants
   can validate against market parameters at creation; the timelock's delay
   floor against `withdrawalBatchDuration` is the existing example.

Don't add covenant state or logic to `CovenantHooksCore`. The whole reason the
split exists is that a template should only pay for what it inherits. Term
behaviour follows the same rule from the other side: if you're adding a term
structure rather than a covenant, mirror `FixedTermHost`, declare your errors
on the mixin rather than in `ICovenantEvents` (editing that shared file moves
every covenant library's CREATE2 address at once), and wire in through
`_beforeQueueWithdrawal`.

**Measure the result.** Creation code has to stay under 24,576 bytes, and the
combined template is already using most of its budget. Check with
`FOUNDRY_PROFILE=deploy forge build` and read `bytecode.object` from the
artifact. Don't reach for `forge build --sizes`, which reports runtime size and
will tell you everything's fine when it isn't.

Practically: **a template carrying three covenants won't fit**, and the
combined gate-plus-clean-down template already runs closest to the ceiling.
Treat templates as configurations, and ship the combinations borrowers
actually ask for. A feature-complete superset isn't on the menu, which is why
four covenants ship across four templates rather than one.

---

# The covenant map

An index of what a revolving facility can enforce, split by whether it needs a
trust root. This is where the build order comes from, and the attested half
doubles as a target list for a sealed entity credentials reference
implementation.

The distinction that matters:

- **Endogenous** covenants are computable from chain state alone. No issuer, no
  oracle, nobody to compel.
- **Attested** covenants need somebody to sign something. Perfectly
  implementable, but each introduces a party who can be leaned on, so they're
  listed separately and treated differently.

## Four facts that drive the ranking

Scoring covenants by TradFi universality gets the order wrong, because TradFi
lenders are always locked in and Wildcat lenders mostly aren't. Four structural
facts about this protocol do the real sorting, and each candidate below is
scored against them.

**The lender exit right is the master variable.** On an open-term market, a
lender who dislikes anything queues a withdrawal and is out within a batch
duration. That exit right substitutes for most of what TradFi covenants protect
against, which is why several universally loved covenants score poorly here. On
fixed-term markets the exit right is suspended and on periodic markets it's
windowed, so a covenant doesn't have one value: it has a value per market type.

**Covenant value concentrates where lenders are locked.** The core's default
behaviour is open-term, and `FixedTermHost` and `PeriodicTermHost` supply the
other two term structures as mixins. That's where several covenants earn their
keep: a de-risking schedule matters most to a lender who can't leave, and a
timelock means something different when exit is windowed. Scores below are
still stated net of the open-term exit right, since that's the baseline; the
term hosts are what let the higher-value configurations actually deploy.

**The commitment fee punishes permanent drawstops.** The fee accrues on full
supply, drawn or not. A *curable* drawstop plus fee is coherent: the borrower
pays for capacity they can unlock by curing, which is an incentive. A
*permanent* drawstop plus fee is charging for a service that no longer exists,
so any covenant that ends drawing forever has to shrink the commitment with it
or it ships a billing bug.

**The base protocol already carries the ABL cushion.** The reserve ratio is a
hard liquidity floor enforced on the borrow path, and breaching it through
withdrawals makes the market delinquent and springs penalty APR after grace.
That is excess-availability protection with a springing consequence, native to
every market. Covenants that reinvent it are double-counting.

## How the scores work

Each endogenous candidate gets a mark out of 100:

| Component | Weight | What it measures |
| --- | --- | --- |
| Lender value | 30 | How much protection it adds *net of the exit right and the reserve ratio* |
| Desk legibility | 20 | Whether a credit person recognises it without a lecture |
| Cheapness to build | 20 | Bytecode, storage, hook surface, test burden, and whether it needs a host that doesn't exist. Higher is cheaper |
| Fidelity | 15 | How close the on-chain version gets to the thing it's translating |
| Composition safety | 15 | How little it interferes with the other covenants |

The weights are a judgement call and reasonable people would move them. Lender
value is heaviest because a covenant nobody's protected by is theatre however
elegant it is, and it's measured net: protection the exit right or the reserve
ratio already provides doesn't count twice. Composition safety is in there
because a covenant can be individually correct and still dangerous sitting next
to another one.

Scores are calibrated against each other, never against anything absolute.
The ordering is more defensible than the individual numbers.

## Implemented

### Cross-market delinquency gate (86/100)

*Lender value 27 · legibility 19 · cheapness 15 · fidelity 14 · composition 11*

The strongest endogenous covenant available, because default status genuinely is
on-chain state. Cross-default is the covenant credit desks lean on hardest, and
here you get it structurally rather than contractually. It also survives the
exit-right test cleanly: it works on every market type, and it's a curable
drawstop, so the fee interaction is an incentive rather than a bug. Marked down
on cheapness for the watch-list loop and its gas ceiling, and on composition
because the watch-list is shared mutable state.

### Clean-down (84/100)

*Lender value 22 · legibility 20 · cheapness 17 · fidelity 15 · composition 10*

Near-universal in TradFi, so a treasurer nods at it immediately, and it earns
its score here on the merits too: the exit right doesn't substitute for it,
because a lender exiting tells you nothing about whether the facility is really
revolving. If anything it's worth more on term markets, where lenders can't
vote with their feet and the covenant is the only thing evidencing revolver
behaviour. Curable, so the fee stays coherent. Loses a little on composition
because it interacts with anything else that gates drawing: if the facility is
drawstopped for another reason during the window where the borrower needs to
clean down, you can wedge them. Worth re-checking whenever a new covenant
lands.

### Commitment-reduction schedule (82/100)

`CommitmentScheduleCovenant`, shipped in `RevolvingScheduleHooks`. A
piecewise-constant ceiling on the drawn amount that declines on a schedule,
enforced in `onBorrow`. Implements amortising revolvers, scheduled commitment
reductions, and, as its terminal case, availability-period expiry: a final
ceiling of zero ends drawing on a date, which is what an availability period
is.

*Lender value 24 · legibility 19 · cheapness 15 · fidelity 12 · composition 12*

Top of the list because it's the one covenant that gives locked lenders a
de-risking *path* rather than a snapshot. In a syndicated deal the equivalent
depends on the agent tracking dates and the borrower not over-drawing, and it
gets disputed; here it's a cap that can't be exceeded.

Enforcement is on **drawn**, not on supply, and the behaviour section above
covers why. What the score has to price is the half that isn't built: whether
the *commitment* (and so the fee base) should step down alongside the drawn
ceiling is a market design question involving `setMaxTotalSupply` and lender
expectations, and it's still open. It doesn't block the covenant, but a
facility marketed as amortising wants an answer to it before launch.

Two caveats keep the score below the first pair. Its full value is on
fixed-term markets, where lenders actually need a de-risking path, and
`FixedTermScheduleHooks` now ships exactly that pairing alongside the
open-term version. And the expiry case inherits the fee problem: drawn to
zero with the commitment untouched leaves the borrower paying for capacity
they can no longer draw, which is why the fee question above stops being
optional at the terminal step.

### Draw timelock (74/100)

`DrawTimelockCovenant`, shipped in `RevolvingTimelockHooks`. Announce a draw
above a cumulative headroom threshold; it executes after a delay long enough
for any lender who dislikes it to exit first.

*Lender value 25 · legibility 13 · cheapness 15 · fidelity 11 · composition 10*

The honest translation of a material adverse change clause. A MAC converts
lender discomfort into a right to refuse funding; this converts it into a right
to not be there when it funds. No approver exists, so nothing is compellable,
and the draw proceeds against whatever capital voluntarily stayed.

It ranks here because it's the one covenant *native* to the host that actually
exists. On an open-term market the exit right is the protection, and the
timelock is the only candidate that amplifies it instead of duplicating it: a
constant delay of at least the withdrawal batch duration guarantees an
objecting lender is out before the money moves. No window mathematics needed on
the open-term host.

Two templates ship, scoped per host:

- **Open-term** (`RevolvingTimelockHooks`): constant delay of at least the
  withdrawal batch duration, enforced at market creation.
- **Periodic** (`PeriodicTimelockHooks`): window-aware, since a fixed delay in
  seconds no longer implies exit opportunity when `queueWithdrawal` only works
  inside scheduled windows. Each announcement's `executableAt` is floored at
  the end of the first full window after it plus one batch duration, via a
  host requirement the covenant declares and each template implements. A
  constant delay on a periodic market would emit announcement events, enforce
  delays, and protect nobody, which is worse than omitting the covenant
  because integrators would assume the property holds; the host requirement is
  what makes that mistake unrepresentable here. The same floor governs the
  roll of the unannounced-headroom baseline, without which the anti-split
  property collapses between windows: a borrower would dribble the threshold
  per delay-period while nobody could leave. Mutation-checked in
  `test_onBorrow_HeadroomDoesNotRollBetweenWindows`.
- **Fixed-term:** excluded entirely, on purpose. A timelock giving you time to
  exit when you can't exit protects nobody.

Four implementation traps regardless of host. A per-draw threshold is
splittable, which is why the shipped covenant gates cumulative unannounced
drawing per rolling delay-window; the behaviour section above has the full
mechanism and `test_onBorrow_SplitDrawsShareHeadroom` pins the property. Stale
announcements are
pre-positioned instant draws, so give each a tight execution window
`[executableAt, executableAt + grace]`. Exits during the delay reduce available
liquidity, so decide explicitly between `min(announced, available)` and
revert-and-reannounce, since one lets a small exit shave a draw and the other
lets a small exit reset the clock. And key announcements by `(market, nonce)`,
or a pending large draw locks out the sub-threshold working-capital dribbles a
revolver exists to provide.

## Candidates

### 1. Borrowing base over on-chain collateral (79/100)

Availability capped at eligible collateral times an advance rate, minus
reserves.

*Lender value 28 · legibility 20 · cheapness 8 · fidelity 13 · composition 10*

Highest lender value on the board and the widest commercial unlock, since it
opens asset-based lending and receivables finance, both of which dwarf leveraged
lending. It's also genuinely additive: the exit right tells a lender nothing
about collateral coverage, so nothing here is double-counted. Sits at two
instead of one purely on cost: eligibility rules, advance rates, reserves and
rounding add up to a real engine, not a check.

Conditional in a way the others aren't. It's endogenous **only** where the
collateral and its valuation are both on-chain. Off-chain collateral makes it an
attested covenant and it moves to the section below. If tokenised collateral
turns up in a live market, move this to the top immediately.

### 2. Cross-market aggregate exposure cap (65/100)

A ceiling on total drawn across all of a borrower's markets, not just this
one.

*Lender value 17 · legibility 16 · cheapness 15 · fidelity 6 · composition 11*

The incurrence-test analogue, and cheap because it reuses the watch-list the
delinquency gate already maintains. But it inherits that list's incompleteness
asymmetrically. The gate only gets *stronger* as markets are watched, and a
missing market just means one fewer tripwire. The cap is *understated* by every
unwatched market, the list is bounded at 30, and nothing on-chain enumerates a
borrower's markets exhaustively. A cap that undercounts is a cap that lies,
and it caps Wildcat debt rather than debt in any case. Describe it as limiting
concentration within the protocol, never as limiting leverage, and treat the
number as a floor on exposure rather than a ceiling.

### 3. On-chain control change (64/100)

Detect a change in the controlling address or signer set of a smart-account
borrower, and drawstop.

*Lender value 15 · legibility 17 · cheapness 12 · fidelity 6 · composition 14*

Change of control is universal in loan documents so it reads well, but the
on-chain version is doubly narrowed. It only detects anything for smart-account
borrowers, since an EOA handing over a key is invisible, and its value
concentrates on term markets where lenders can't leave on the news, and the
fixed-term host now exists to carry it. On open-term markets the exit right
already is the change-of-control remedy. The host was the blocker; the
smart-account fidelity ceiling is what remains.

### 4. Sweep-before-draw (62/100)

Where borrower inflows are observable on-chain, require application to the
drawn balance before the next draw is permitted.

*Lender value 16 · legibility 18 · cheapness 12 · fidelity 8 · composition 12*

The mandatory-prepayment analogue, and mechanically sound: making repayment a
precondition of the next draw can't be dodged for the flows it sees. The
problem is what it sees. Without a constrained-flow pattern, the borrower
chooses which addresses are observable, so revenue routes around the sweep at
the cost of one hop. That's the same critique destination constraints get, and
it lands here just as hard. Real value arrives only paired with destination
constraints or a borrower operating account the market can watch by
construction, so build it then, as a pair.

### 5. Destination-constrained draws (59/100)

Draws only to addresses on a per-market allow-list.

*Lender value 10 · legibility 15 · cheapness 13 · fidelity 8 · composition 13*

Lowest standalone lender value on the list and the score stays honest about
that. A determined absconder moves funds one hop later, so alone this prevents
nothing. The value is forensic: breaking the disclosed flow is visible and
timestamped, which matters for later proceedings and for compliance teams who
need a funds-flow answer they can't currently get. Price it as evidence. Never
as prevention.

It's also the enabling half of the sweep pairing above, which is the stronger
argument for eventually building it than anything it does alone.

Blocked on a design question. `WildcatMarket.borrow` transfers to `msg.sender`,
always the borrower, so a hook can't enforce a destination by inspecting the
transfer. It needs the borrower drawing through a contract whose own outbound
payments are constrained, or a change to the market's borrow path. Settle that
first.

### 6. Excess-availability springing regime (58/100)

When undrawn availability drops below a threshold, spring a stricter state.

*Lender value 10 · legibility 14 · cheapness 12 · fidelity 12 · composition 10*

Scored against what the protocol already does, most of this is double-counting.
The reserve ratio is a hard availability floor on the borrow path; breach it
through withdrawals and the market goes delinquent and springs penalty APR
after grace. That's the ABL springing mechanic, native, on every market. What a
covenant can add is one pre-breach tier: a drawstop that fires *above* the
reserve ratio, giving lenders a buffer before the base machinery engages. Real
but marginal, and it carries the worst wedge risk on the list, since a spring
that fires into a clean-down window blocks the cure.

### 7. On-chain negative pledge (55/100)

Detect a competing lien or transfer over collateral held in an observable
vault, and drawstop.

*Lender value 12 · legibility 16 · cheapness 10 · fidelity 5 · composition 12*

The covenant is universal; the on-chain version sees a sliver of what it's
meant to. And it's dominated: any market where the collateral genuinely is
on-chain should spend the same effort on the borrowing base, which subsumes
this by construction, since encumbered collateral falls out of eligibility.

### Not listed: utilisation-triggered springing

Deliberately absent, because it isn't a covenant. "Spring when drawn-to-supply
crosses a threshold" is a *trigger condition*, and the excess-availability
entry above is the same trigger stated from the other side, since undrawn
availability is supply minus drawn. Any covenant here can take a utilisation
trigger as a parameter. Listing triggers as covenants inflates the map without
adding protection.

## Summary

| # | Covenant | Score | Status |
| --- | --- | --- | --- |
|   | Cross-market delinquency gate | 86 | Implemented |
|   | Clean-down | 84 | Implemented |
|   | Commitment-reduction schedule (incl. expiry) | 82 | Implemented, open-term and fixed-term; fee step-down is a market question |
|   | Draw timelock | 74 | Implemented, open-term and periodic (window-aware); never fixed-term |
| 1 | Borrowing base, on-chain collateral | 79 | Conditional on tokenised collateral |
| 2 | Cross-market aggregate exposure cap | 65 | Watch-list completeness caveat |
| 3 | On-chain control change | 64 | Smart-account borrowers; fixed-term host now available |
| 4 | Sweep-before-draw | 62 | Pair with destination constraints |
| 5 | Destination-constrained draws | 59 | Blocked on borrow path |
| 6 | Excess-availability springing | 58 | Mostly native already; one pre-breach tier survives |
| 7 | On-chain negative pledge | 55 | Dominated by borrowing base |

Three conclusions to keep visible.

**Availability-period expiry isn't a covenant here, and its absence is the
point.** It looked like the obvious first covenant right up until it was
checked against the exit right: on open-term markets, lenders who can leave
whenever they like don't need a drawdown deadline, and on term markets the
deadline is just a commitment schedule that steps to zero. It ships as the
terminal case of the schedule covenant. Universality in TradFi measures how
locked-in TradFi lenders are, not how valuable the covenant is here.

**The host question is answered.** Fixed-term and periodic covenant hosts
now exist as mixins, which is what let the schedule ship where it matters most
and the timelock ship window-aware. What that unblocks next is candidate 3,
whose value concentrates on locked lenders, and any future pairing a borrower
asks for: a term-structured template is now a composition, not a project.

**The timelock is the native covenant.** It's the one entry that treats the
exit right as the protection to amplify rather than a gap to paper over, and
on the open-term host it's a constant delay with no window mathematics. Funny
outcome: the exotic-looking one turned out to be one of the first two built.

---

# Attested covenants

Everything below needs a trust root. They're implementable, and several are
things lenders genuinely want, but each introduces a party who can be compelled,
can go offline, or can just stop.

This list is the target set for a sealed entity credentials reference
implementation. The pattern is uniform: a credential asserts the condition, the
borrow path gates on that credential staying valid and fresh, and drawdown
freezes automatically if it lapses.

| Covenant | What gets attested | Natural issuer |
| --- | --- | --- |
| Leverage ratio | Within covenanted bound at the test date | Auditor |
| Interest cover | Within bound | Auditor |
| Fixed charge cover | Within bound | Auditor |
| Minimum EBITDA | Above floor | Auditor |
| Tangible net worth | Above floor | Auditor |
| Capex limit | Within cap for the period | Auditor |
| Borrowing base, off-chain collateral | Eligible value after advance rates and reserves | Fund administrator, collateral agent |
| Entity standing | Registered, in good standing, no insolvency filing | Registry, KYB provider |
| Licence and regulatory status | Authorisations current and unrestricted | KYB provider, regulator feed |
| Sanctions screening | No match | Screening provider |
| Beneficial ownership | Unchanged since onboarding | KYB provider |
| Corporate change of control | No change, or change disclosed | KYB provider, registry |
| Negative pledge, off-chain assets | No competing liens | Borrower's counsel, auditor |
| Asset disposals | Within basket for the period | Auditor |
| Restricted payments | Within builder basket | Auditor |
| Insurance maintenance | Cover in force | Broker |
| Financials delivery | Delivered within the reporting window | Auditor |

The issuer column matters. These aren't one role. Financial ratios belong to an
auditor, collateral valuation to an administrator, and entity standing,
licensing, sanctions and control to a KYB provider. A real facility depends on
two or three distinct issuers with different competences and refresh cadences.

## Two rules for all of them

**Failure has to be lender-protective.** Issuer goes quiet, draws freeze. A
covenant where a missing credential *permits* borrowing is worse than no
covenant, because it pays someone to disrupt the issuer.

**Spread the issuers out.** Twenty covenants through one attestor is a worse
structure than five through five, because one order or one outage stops
everything. The interesting question isn't which covenants you can express, it's
how many distinct parties a facility depends on and what happens when each is
leaned on. Choose that topology on purpose. Don't let it fall out of whichever
covenants the borrower's counsel happened to ask for.

## Why gating beats obligating

An affirmative covenant is an *obligation to act*: deliver financials by the
45th day. Obligations need someone willing and able to enforce them, which is
precisely what's missing here. Gating drawdown on credential freshness turns it
into a *condition precedent*: draw only while the certificate is current. Nobody
has to chase anyone, because the facility simply stops being available.

Traditional lenders can't make that swap. A bank that froze a facility every
time a certificate ran late would lose the client. A protocol has no such
incentive and can hold the line, which is one of the few places where being
unable to exercise discretion is an advantage.

## Where credentials beat the original

Two properties deserve to be designed around from the start instead of
discovered as bonuses.

**Breach-triggered disclosure.** A credential's trigger can be any predicate
evaluable on-chain, and that includes the covenant machinery's own state.
Delinquency, an overdue clean-down, availability through a threshold: the
facility already computes all of these, so a credential can be bound to fire on
them. That gives disclosure contingent on breach, which is how information
rights work in practice anyway. Performing borrowers don't open their books; an
event of default switches on rights that lay dormant. Here the asymmetry is
mechanical instead of negotiated, and a borrower never has to trade
confidentiality for covenant protection. They keep it exactly as long as they're
performing, and the disclosure they concede is contingent on something within
their power to avoid.

**Issuers are substitutable.** Acceptance turns on schema and trigger
conformance rather than issuer identity, so a consumer can rotate its accepted
set. No single issuer is load-bearing, and compelling one produces "needs a new
supplier" rather than "facility halts". That's the walkaway test one layer up:
the same argument that says infrastructure should survive its authors leaving
says it should survive its attestors leaving.

Two open questions decide how strong that second property really is, and both
want crisp answers before anyone leans on it. Who holds rotation authority: if
a foundation curates the accepted set, the foundation is still the compellable
party one level up, while fixing it at market deployment means no rotation
without redeploying. And whether equivalence between issuers is mechanical or
judged: hash-comparable schema and trigger conformance is unimpeachable, but a
human deciding issuer Y is stringent enough is a control point in different
clothing.

## Not worth attesting

Some things become expressible once you have a credential layer and still aren't
worth the attestor load.

Restricted payments, affiliate transactions and incurrence pro-forma tests all
guard against value leakage a lender can't unwind anyway, and they're the ones
that make a covenant package feel like box-ticking. Equity cure rights need an
off-chain equity injection plus a deeming construct, which is a lot of machinery
for a mechanism whose purpose is letting a sponsor paper over a breach.
Inspection rights are a physical act and always will be.

Discretionary MAC is the interesting exclusion. Don't implement it as judgement,
because that reintroduces an actor with a decision to make. The draw timelock
covers part of it with no attestor at all, and a null-triggered credential
covers the rest with one. Between them there's no gap worth a discretionary
power.

---

# Known limitations

- **`RevolvingDrawnMath` isn't called by the market.** The hooks predict the
  post-transition drawn amount from inside `onBorrow` and `onRepay`, which run
  before `WildcatMarketRevolving` updates its own value, so the two have to
  agree exactly. The library holds one definition; the market still applies its
  formulas inline. Pointing the market at the library is behaviourally identical
  and moves deployed bytecode by 44 bytes, which moves `marketInitCodeHash`, an
  immutable on the deployed revolving factory that feeds CREATE2 market
  addresses. Doing it means a new factory.
  `test/access/covenants/CovenantBase.t.sol` pins the drift in the meantime and
  is mutation-checked. Worth folding in whenever the market is next redeployed
  for other reasons.
- **Direct-mode deployment is unproven.** Plan mode is exercised end to end
  against a fixture. Direct mode logs success on a Sepolia fork but the post-run
  state showed no change, and nobody has established whether that's the
  impersonated-sender broadcast not landing or a real fault. Run it on a fork
  and check the factory's template count with `cast` before trusting it.
- **Watch-list cap.** 30 markets is a real limit for a borrower with a lot of
  facilities. The alternative is a push model where markets report delinquency
  rather than a pull loop, and that costs you the permissionless property.
- **Gas.** Each covenant owns its own storage, so a template pays a cold
  `SLOAD` per inherited covenant on the borrow path relative to a single
  packed struct, on top of a delegatecall into each library. Negligible
  against a borrow, but it's the price of the split.
- **No `CovenantLens` test.** It compiles and is read-only, but a fixture-based
  suite would be better than nothing.

Test conventions follow `TESTS.md`: unit tests mirror `src/` paths and functions
are named `test_<functionName>_<PascalCaseLabel>`, with error-path tests
labelled by error name.
