# Revolving covenant hooks

Composable conditions-precedent for revolving Wildcat markets.

Every TradFi revolver gates each utilisation on conditions: no default
continuing, representations repeated, clean-down observed. We've got no
analogue for any of that in the shipped templates. These contracts add two of
them, and both are computable from chain state alone. Neither needs an attestor
or a guardian, and neither hands anyone a party they can lean on in court to
freeze a borrower.

Both are drawstops. Breach one and new draws are blocked, and that's it: no
acceleration, no forced repayment, nobody adjudicating. Lender exit rights
aren't touched, and drawing picks back up once the condition clears.

## Contents

| File | Role |
| --- | --- |
| `CovenantBase.sol` | Market/registry interfaces; drawn-amount prediction shared by all covenants |
| `CovenantHooksCore.sol` | Abstract host: `OpenTermHooks`-equivalent access control, market registry, hook scaffolding |
| `CleanDownCovenant.sol` | Clean-down covenant (mixin) |
| `CrossMarketDelinquencyCovenant.sol` | Cross-market delinquency gate (mixin) |
| `../RevolvingCovenantHooks.sol` | Concrete template: both covenants |
| `../RevolvingCleanDownHooks.sol` | Concrete template: clean-down only |
| `../../libraries/RevolvingDrawnMath.sol` | Pure drawn-amount transitions |

Tests: `test/integration/RevolvingCovenantHooks.t.sol` (17, behavioural),
`test/integration/RevolvingCleanDownHooks.t.sol` (4, composition seam).

## Why mixins rather than separate hooks contracts

A market stores exactly one hooks address, so you can't have covenants sitting
side by side as separate deployed contracts. That's the constraint everything
else follows from.

You could do one dispatcher hook holding a mutable list of covenant module
addresses, which buys you runtime composability. It also means a module
registry, and a module registry is an admin surface, which makes it a
compellable control point. For this protocol that trade runs the wrong way.

Abstract mixins give you file-level separation with immutable composition:

- A template inherits only the covenants it wants. Whatever it doesn't inherit
  costs it nothing in bytecode, storage, ABI or borrow-path work.
- Hook dispatch flags get derived per template. A template that never needs to
  observe repayments doesn't require `onRepay`, and pays nothing for it.
- Past what the borrower sets at market creation, nothing is configurable after
  deployment. No registry, no owner, no upgrade path.

`RevolvingCleanDownHooks` is there so that claim stays tested rather than just
asserted: `test_crossMarketAbiAbsent` checks the gate's entire ABI is missing
from a template that doesn't inherit it.

## Covenants

### Clean-down

Near-universal in TradFi revolvers. The facility has to return to zero drawn
for `duration` consecutive seconds at least once every `interval` seconds,
which evidences use as a revolver rather than disguised term debt.

Three behaviours here are deliberate:

- **Idle time counts from market creation.** A market that's never drawn
  shouldn't hit its first deadline already in breach.
- **Maturity gets credited at the moment of the next draw**, rather than by a
  keeper. A streak that matured a second ago is banked inside the transaction
  that consumes it, so there's no sentinel and no liveness dependency.
- **Reclaiming an over-repayment doesn't count as credit.** A draw that leaves
  the drawn amount at zero neither trips the covenant nor breaks a running
  streak.

Partial repayments don't start a streak. Only reaching zero does.

### Cross-market delinquency gate

The on-chain analogue of a cross-default clause: draws revert while the
borrower is delinquent on any of their other markets.

The watch-list is permissionless. Anyone can add a market that's registered
with the arch controller and reports this instance's borrower, which reaches
markets from other factories and hooks instances while admitting nothing else.
Anyone can prune closed markets too, since a closed market has settled and can
never be delinquent again. The list is capped at `MAX_WATCHED_MARKETS` (30),
because the gate iterates it on the borrow path and that loop needs a hard gas
ceiling.

Two modes. `penaltyOnly` gates on markets past their grace period, so the ones
actually accruing penalty APR, and I'd recommend it as the default: strict
delinquency will drawstop on transient reserve dips that cure themselves inside
grace anyway.

The calling market gets checked through the `intermediateState` handed to the
hook, never through its own `currentState()`. That view is reentrancy-guarded
and the borrow path holds the lock, so querying it would revert every draw.
`test_crossMarket_healthySelfDoesNotBlock` is what guards against that
regression.

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
| `0x60` | `uint32` | `cleanDownInterval`; must strictly exceed duration |
| `0x80` | `bool` | `crossMarketGateEnabled` |
| `0xa0` | `bool` | `gateOnPenaltyOnly`; requires the gate |

`RevolvingCleanDownHooks` uses `0x00` to `0x60` only.

Three inconsistent combinations revert at market creation rather than deploying
inert config: an interval without a duration, an interval that doesn't exceed
its duration, and `gateOnPenaltyOnly` without the gate.

All covenant templates are revolving-only, because the covenants read
`drawnAmount()` and standard markets don't implement it.
`CovenantHooksCore`'s constructor checks the deploying factory's name, so you
can't create an instance through the standard hooks factory.

## Adding a covenant

1. Write `covenants/YourCovenant.sol` as an `abstract contract` inheriting
   `CovenantBase`. Own your storage (`mapping(address => YourState)`), your
   events, and your errors.
2. Expose three kinds of `internal` entry point: `_initYourCovenant(market,
   ...)` called at creation, one enforcement function per hook you care about,
   and external views.
3. Declare host requirements as abstract functions **on your covenant**, not on
   `CovenantBase`. That way a template inheriting only some covenants
   implements only their requirements. `CrossMarketDelinquencyCovenant` does
   this with `_covenantBorrower()` and `_covenantArchController()`.
4. Write a concrete template inheriting `CovenantHooksCore` plus your covenant,
   implementing `version()`, `_requiredCovenantFlags()`, `_initCovenants()`,
   and the hook bodies that call your enforcement functions.

Don't add covenant state or logic to `CovenantHooksCore`. The whole reason the
split exists is that a template should only pay for what it inherits.

**Measure the result.** Creation code has to stay under EIP-170's 24,576
bytes and inheritance flattens, so a third covenant will not fit in an
existing template. See "The size ceiling, and the library route past it"
below.

## Known limitations and open decisions

- **`RevolvingDrawnMath` isn't called by the market.** The hooks predict the
  post-transition drawn amount from inside `onBorrow`/`onRepay`, which run
  before `WildcatMarketRevolving` updates its own value, so the two have to
  agree exactly. The library holds one definition; the market still applies its
  formulas inline. Pointing it at the library was trialled: behaviourally
  identical, 19/19 revolving tests pass, but deployed bytecode moves 44 bytes,
  which moves `marketInitCodeHash`, an immutable on the Sepolia revolving
  factory that feeds CREATE2 market addresses. Doing it means a new factory.
  `test/access/covenants/CovenantBase.t.sol` pins the drift in the meantime and
  is mutation-checked. Worth folding in whenever the market is next redeployed
  for other reasons.
- **Direct-mode deployment is unproven.** Plan mode is exercised end to end.
  Direct mode logs success on a Sepolia fork but the post-run state showed no
  change, and nobody has worked out whether that's the impersonated-sender
  broadcast not landing or a real fault. Run it on a fork and check the
  factory's template count with `cast` before trusting it.
- **Watch-list cap.** 30 markets is a real limit for a borrower with a lot of
  facilities. The alternative is a push model where markets report delinquency
  rather than a pull loop, and that costs you the permissionless property.
- **Gas.** Each covenant owns its own storage slot, so a template inheriting
  two pays one extra cold `SLOAD` on the borrow path relative to a single
  packed struct, on top of the delegatecall into each library. Negligible
  against a borrow, but it's the price of the split.
- **No `CovenantLens` test.** It compiles and is read-only, but a fixture-based
  suite would be better than nothing.


## The size ceiling, and the library route past it

Templates are stored as init code, so the creation code of each has to stay
under EIP-170's 24,576 bytes. Measured under `FOUNDRY_PROFILE=deploy`:

| Template | Creation code | Headroom |
| --- | --- | --- |
| RevolvingCovenantHooks | 23,495 | 1,081 |
| RevolvingCleanDownHooks | 20,526 | 4,050 |

Inheritance flattens, so mixins won't help you here. A template inheriting two
covenants compiles both into one deployed contract, which is exactly why the
combined template is 3,000 bytes heavier than the single-covenant one. Mixins give you source separation and the option to leave a covenant out, but
once you've inherited one you're carrying it.

So the limit is hard rather than soft. **A template carrying three
covenants will not fit.** Think of templates as configurations rather than a
feature-complete superset. Ship the combinations borrowers actually ask for and
turn the rest down, otherwise the count goes exponential.

### Recovering bytes without an external library

Stripping the convenience views the lens already covers [`firstBlockingMarket`,
`getCrossMarketGateConfig`, `getWatchedMarkets`, `getCleanDownState`,
`getHookedMarkets`] and exposing the watch-list as a public array recovers
roughly 1,160 bytes, taking headroom to about 2,240. Worth keeping in reserve rather than
spending, because `firstBlockingMarket` isn't free: the lens can only
replace it by duplicating the delinquency check, which recreates the drift
problem `CovenantBase.t.sol` exists to close.

### The external library route

**Implemented for both covenants.** `CrossMarketGateLib` holds the watch-list
management, the borrow-path delinquency sweep and the preview; `CleanDownLib`
holds streak accounting and status. Each mixin keeps its storage and external
surface and delegates the bodies.

Events and errors are declared in `ICovenantEvents`, which both the mixins and
the libraries reference. **The mixins inherit it**, so every error and event
stays in the template ABI even though it is raised from a library. Selectors
and topic hashes are unchanged. Skip that inheritance and the errors quietly
vanish from the ABI while still reverting on-chain, which breaks decoding for
anything reading the template's interface. Easy mistake to make; I made it.

Measured, legacy optimizer:

| Template | before | after | saved |
| --- | --- | --- | --- |
| RevolvingCovenantHooks | 25,130 | 22,936 | 2,194 (8%) |
| RevolvingCleanDownHooks | 22,120 | 21,255 | 865 (3%) |

The saving is per covenant, which is what makes a fourth, fifth and sixth
affordable. Each body stays at its own address and the template just carries
the dispatch.

333 tests pass through the delegatecall boundary, including the three existing
hooks suites. Tests need the library runtime code placed at the linked addresses before they
touch a template; see `_deployCovenantLibraries` in the covenant
suites. A fresh test EVM has nothing there, and a library call into an empty address
trips the `extcodesize` check.

What it costs:

- roughly 2,600 gas cold per call on the borrow path, paid by the borrower on
  every draw;
- a wider audit surface, since template behaviour now depends on a contract at
  an address rather than on inlined code;
- a compile-time link, so templates carry the library addresses. Handled by
  fixed CREATE2 addresses; see below.

### Linking: CREATE2, single-phase

The library is deployed through the canonical deterministic-deployment proxy
at `0x4e59b44847b379578588920cA78FbF26c0B4956C` with a fixed salt, which puts
it at the same address on every chain. Templates are compiled against that
address up front, so `type(T).creationCode` resolves and the deploy stays
single-phase.

`foundry.toml` needs the link in every profile the templates are built under:

```toml
libraries = [
  'src/access/covenants/lib/CrossMarketGateLib.sol:CrossMarketGateLib:0xFa43841a597a4378762358ae8fc34dF82279eBd2',
  'src/access/covenants/lib/CleanDownLib.sol:CleanDownLib:0x3A37d9d85CafeB47B5273CbcD22896F41FfD13d7'
]
```

Salts are `0x…01` for the gate and `0x…02` for clean-down.

**`CovenantLibraries.sol` is the single source of truth.** Addresses and salts
are declared there once and imported by the deploy script and by every test
suite. `foundry.toml` can't import Solidity, so its `libraries` entry is the one
duplicate you can't get rid of. Change one, change both, same commit. A new covenant
library takes the next salt and a constant in that file.

Confirmed: with that in place the artifact has no `__$...$__` placeholders and
an empty `linkReferences`.

**Those addresses come out of the compiled library bytecode**, so they move if
the compiler version or optimizer settings change. The deploy script
recomputes it from `type(CrossMarketGateLib).creationCode` and asserts it
matches, so drift fails the run with
`<name> address drift: update the constant and foundry.toml libraries`
rather than silently registering templates linked to an empty address. If you see that error, just regenerate both values together.

The script deploys the library if no code is present, skips if it is, and in
plan mode reports it instead. Verified in plan mode against a fixture.

**Style of the library boundary is subject to Kethic's final review.**

---

# Planned covenants

Three more covenants are scoped but unbuilt. Each one's written up below with
the clause it translates, the mechanism, the traps that aren't obvious from the
mechanism, and what picking it up from cold actually involves.

Read "Adding a covenant" above first. The four-step recipe applies to all
three, and the notes below only cover what's specific to each.

## 1. Draw timelocks sized to the exit window

**The clause.** Material adverse change. A MAC clause lets lenders refuse to
fund when the humans smell smoke, so the bad feeling *is* the trigger. There's
no honest on-chain analogue, and any oracle claiming to detect one is lying.

**What it actually does, and how to translate that.** A MAC clause turns a
lender's discomfort into a right to refuse funding. The trust-minimised version
turns it into a right to *not be there when it funds* instead. The borrower
announces a draw above a threshold, the draw executes only after a delay, and
the delay is sized so any lender who saw the announcement can be fully exited
before the funds leave. No approver exists, so nothing is compellable, and the
borrow goes ahead against whatever capital voluntarily stayed.

**The invariant.** Not that a delay elapsed, but:

```
executableAt >= announceTime + (time for a lender to fully exit from announceTime)
```

On an open-term market, exit time is `withdrawalBatchDuration`: queue, then
wait for the batch to expire and pay. So `delay >= withdrawalBatchDuration`
satisfies it.

**Trap 1: periodic markets break the naive version.** On `PeriodicTermHooks`,
`queueWithdrawal` only succeeds inside scheduled windows, so a fixed delay in
seconds no longer implies exit opportunity:

```
announce at t; next window opens at W, where W > t + delay
=> the draw executes before any lender could queue
```

What you want is a window-aware deadline:

```
executableAt = nextWindowStartAfter(announceTime)
             + withdrawalWindowDuration
             + withdrawalBatchDuration
```

Waiting for the full window plus batch means a lender who queues on the last
second of the window still gets paid before the draw. Waiting only for the
window to *open* is the weaker defensible minimum. That's a policy call, and
worst case the announcement lands just after a window closes and executable
time is nearly a full `periodDuration` out. Surface that to the borrower when
they're configuring the market, not when they're trying to draw.

Ship a constant-delay implementation onto a periodic market and it'll emit
announcement events, enforce delays, and protect nobody. That's worse than
leaving the covenant out entirely, because integrators and lenders will assume
the property holds. **Shipping this without window-awareness is a bug, not a
limitation.**

**Trap 2: stale announcements are pre-positioned instant draws.** If
announcements never expire, a borrower announces routinely, sits on the ripe
ones, and draws instantly the moment smoke appears, which defeats the point
entirely. Announcements need a tight execution window `[executableAt,
executableAt + grace]`, after which they expire and have to be re-announced.

**Trap 3: exits during the delay reduce available liquidity**, so an announced
draw might be partially or fully unfundable by the time it executes. That
ordering is correct behaviour, since exits should take priority over a pending
draw. But decide explicitly between `min(announced, available)` and
revert-and-reannounce: partial-fill lets one small exit shave a draw, and
revert-and-reannounce lets one small exit reset the clock. Both are griefable,
just in opposite directions.

**Trap 4: a single pending slot is a self-DoS.** Key announcements by
`(market, nonce)`. With one slot, a pending large draw locks out the
sub-threshold working-capital dribbles that a revolver exists to provide in the
first place.

**Prerequisite work.** This is the one covenant with a structural dependency.
Getting it right on periodic markets means reading the window schedule, and
that lives in `PeriodicTermHooks`, which is a *concrete* template deriving from
`BaseAccessControls` rather than a mixin. `CovenantHooksCore` is
`OpenTermHooks`-equivalent, so right now there's no template that's both
periodic and covenant-bearing. Either:

- refactor `PeriodicTermHooks`' window logic into a `PeriodicWindowsMixin`
  alongside these covenants and build a `PeriodicCovenantHooksCore`, or
- have the covenant declare a host requirement
  `_nextWithdrawalWindowStart(market, from)` and implement it per template,
  returning `from` on open-term hosts where withdrawals are always queueable.

The second is cheaper and leaves `PeriodicTermHooks` alone; the first is better
if more periodic-aware covenants follow. Decide before you write any code.

**Cold-start checklist.**

- Storage: `mapping(address => mapping(uint256 => Announcement))` plus a
  per-market nonce and a per-market config `(threshold, graceWindow)`.
- Hooks: `onBorrow` only. Nothing needs `onRepay`, so a timelock-only template
  mustn't require `Bit_Enabled_Repay`.
- Host requirement: `_nextWithdrawalWindowStart(market, from)` as above, plus
  the market's `withdrawalBatchDuration`, which you can read off the market.
- New external, borrower-only: `announceBorrow(market, amount)`. Also decide
  whether cancellation is explicit, and whether an APR change or a market close
  voids outstanding announcements.
- Tests that have to exist: sub-threshold draws bypass entirely; announcing
  before the delay reverts; announcing after grace reverts; a lender who queues
  on announcement gets paid before execution [assert on balances, not
  timestamps]; concurrent announcements don't block each other. The one the
  covenant lives or dies by: **on a periodic market, a lender who sees an
  announcement can always queue before execution.**

## 2. Staleness-gated attestations

**The clause.** Conditions precedent to each utilisation: representations
repeated, no default, borrowing base certificate delivered and current.

**Mechanism.** A designated attestation [NAV, receivables base, compliance
certificate, licence status] has to be fresh within a staleness window for a
draw to go through. Continued validity of the attestation is the repeated
representation, and revocation or expiry is the drawstop.

**Why it's worth building.** Enforcement comes from staleness rather than from
anyone having to take action. Miss your reporting covenant and availability
freezes by itself. That gives information covenants actual enforcement, which
TradFi private credit doesn't have: reporting breaches over there get waived,
because the alternative is disproportionate. It also lets an off-chain monitor
freeze draws without publishing why, which is the honest shape of a compliance
drawstop.

**Sealed entity credentials are the natural fit here.** The draft ERC
([sealed entity credentials](https://hackmd.io/@wildcatlabs/erc-draft-sealed-entity-credentials)) lines up with this covenant almost exactly.
Null triggers give you the freeze-without-publishing behaviour described above
as a first-class primitive rather than something bolted on afterwards. Schema
profiles mean NAV, receivables base and licence status each get a declared
shape instead of ad-hoc per-market encoding. The normative issuer policy
declaration is what makes a staleness window mean anything to a lender before
they rely on it, since they can read what the issuer has committed to attesting
and how often. Role decomposition separates issuer from subject from verifier,
which is what you want when the attestor is an auditor rather than the borrower
themselves. If this covenant gets built after the ERC lands, build it against
that rather than inventing an attestation format in here.

**The tension, which wants documenting rather than papering over.** This
covenant creates an attestor, and the attestor is compellable. A court that
can't touch the protocol can order the auditor to stop attesting, and staleness
does the rest. Sealing changes what's visible, not who can be ordered about.
From a lender's chair that's a feature; measured against non-compellability
it's a deliberate exception. Whoever builds this should
write the trade-off into the contract's natspec as well as the README, so
nobody adopts it without having thought about it.

Worth noting as well: this is the only planned covenant that isn't endogenous.
The other four are computable from chain state alone.

**Design decisions to settle before coding.**

- Who attests: a single designated address per market, a role provider
  reachable through the existing `BaseAccessControls` machinery, or a
  credential contract. Reusing the role-provider path is lowest-friction and
  inherits the access-control model that's already in the template.
- Whether an attestation carries a value [a borrowing base figure that caps
  availability] or is just a bare freshness signal. Bare is much simpler and
  covers the reporting-covenant case; a valued attestation turns this into a
  borrowing-base facility and needs its own arithmetic and rounding review.
- Whether revocation is explicit, implicit by expiry, or both.
- What happens to an in-flight announced draw if the attestation goes stale
  between announcement and execution, where the timelock covenant is also
  inherited. Those two compose and the interaction isn't obvious.

**Cold-start checklist.**

- Storage: per-market `(attestor, stalenessWindow, lastAttestedAt)` and, if
  valued, the attested figure.
- Hooks: `onBorrow` only.
- New externals: `attest(market, ...)` restricted to the attestor, and
  `revokeAttestation(market)`.
- Tests: fresh attestation permits a draw; expired attestation blocks; explicit
  revocation blocks immediately; re-attestation unblocks; nobody but the
  configured authority can change the attestor; a valued attestation caps
  availability at the attested figure.

## 3. Destination-constrained draws

**The clause.** Purpose clause plus funds-flow statement: the borrower can only
draw to fund the stated purpose, evidenced by a pre-agreed payment destination.

**Mechanism.** Draws can only go to addresses on a per-market allow-list
declared at market creation. Sits adjacent to the existing `BorrowAgent.sol`
work.

**What it actually buys.** A determined absconder moves the funds one hop
later, so on its own this prevents nothing. The value is forensic and
compositional: the borrower has to break the disclosed flow *visibly*, which
trips monitoring and timestamps intent for later proceedings, and it gives
institutional lenders' compliance teams a funds-flow answer they can't get
right now. Anything borrower-facing should price it as evidence rather than
prevention. Overselling it is worse than not shipping it.

**Trap: the market pays the caller.** `WildcatMarket.borrow` transfers to
`msg.sender`, which is always the borrower. So you can't enforce a destination
constraint by inspecting the transfer inside `onBorrow`. It needs either the
borrower calling through a contract whose own outbound payments are constrained
[the `BorrowAgent` pattern], or a change to the market's borrow path. Work out
which of those is in scope before writing anything. As a pure hooks covenant,
the useful surface is limited to attesting a declared destination alongside the
draw and emitting it, with enforcement living in the agent.

**Cold-start checklist.**

- Storage: per-market allow-list of destinations plus a mutability policy.
  Immutable at creation is strongest and simplest; borrower-mutable with a
  timelock is the realistic one.
- Hooks: `onBorrow` only.
- Extra calldata: the declared destination comes in via the hook's `extraData`,
  which the market forwards from the borrow call. Confirm the calldata plumbing
  before designing around it.
- Tests: a draw to an allow-listed destination succeeds and emits the
  destination; a draw to an unlisted destination reverts; allow-list mutation
  respects whatever policy gets chosen; the emitted event is enough to
  reconstruct a funds-flow ledger from logs alone.

## Sequencing note

Clean-down and the cross-market gate are pure mechanism and create no
compellable party. Of the three above, the timelock is in the same category,
which makes it the natural next build. Destination constraints are cheap but
need the `BorrowAgent` question settled first. Attestation gating carries the
most weight in a pitch and is the only one that introduces a compellable party,
so build that one last, deliberately, with the trade-off written into the code.
