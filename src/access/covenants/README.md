# Revolving covenant hooks

Composable conditions-precedent for revolving Wildcat markets.

Every revolving credit facility in traditional finance gates each drawing on
conditions: no default continuing, representations repeated, clean-down
observed. Wildcat's shipped hooks templates have no analogue for any of that.
These contracts add two covenants that are computable from chain state alone,
plus the architecture to add more.

Both are **drawstops**. Breach one and new draws are blocked, and that's it: no
acceleration, no forced repayment, nobody adjudicating. Lender exit rights stay
untouched, and drawing resumes once the condition clears. That's a deliberate
choice. A drawstop is the proportionate remedy for a revolver, it needs no third
party to invoke it, and it can't be waived by inattention.

## Contents

| File | Role |
| --- | --- |
| `CovenantBase.sol` | Market and registry interfaces, plus drawn-amount prediction shared by all covenants |
| `CovenantHooksCore.sol` | Abstract host: `OpenTermHooks`-equivalent access control, market registry, hook scaffolding |
| `CleanDownCovenant.sol` | Clean-down covenant. Storage and external surface |
| `CrossMarketDelinquencyCovenant.sol` | Cross-market delinquency gate. Storage and external surface |
| `lib/CleanDownLib.sol` | Clean-down bodies, external library |
| `lib/CrossMarketGateLib.sol` | Gate bodies, external library |
| `lib/CovenantEvents.sol` | Events and errors shared between each mixin and its library |
| `lib/CovenantLibraries.sol` | Deterministic library addresses and salts |
| `../RevolvingCovenantHooks.sol` | Deployable template: both covenants |
| `../RevolvingCleanDownHooks.sol` | Deployable template: clean-down only |
| `../../libraries/RevolvingDrawnMath.sol` | Pure drawn-amount transitions |
| `../../lens/CovenantLens.sol` | Read-only view surface |

Tests live at `test/access/RevolvingCovenantHooks.t.sol` (17),
`test/access/RevolvingCleanDownHooks.t.sol` (4) and
`test/access/covenants/CovenantBase.t.sol` (5).

---

# How it fits together

## One hooks address per market

A Wildcat market stores exactly one hooks address, so covenants can't be
separate deployed contracts sitting side by side. That single constraint shapes
everything else here.

The obvious alternative is one dispatcher hook holding a mutable list of
covenant module addresses, which buys runtime composability. It also means a
module registry, and a module registry is an admin surface, which makes it a
compellable control point. For this protocol that trade runs the wrong way, so
covenants are **abstract mixins composed at compile time** instead.

What that gives you:

- A template inherits only the covenants it wants. Whatever it doesn't inherit
  costs it nothing in ABI or borrow-path work.
- Hook dispatch flags are derived per template. A template that never needs to
  observe repayments doesn't require `onRepay`, and pays nothing for it.
- Past what the borrower sets at market creation, nothing is configurable after
  deployment. No registry, no owner, no upgrade path.

`RevolvingCleanDownHooks` exists partly to keep that claim tested rather than
merely asserted: `test_getWatchedMarkets_AbsentFromTemplate` checks the gate's
entire ABI is missing from a template that doesn't inherit it.

## Why the bodies live in external libraries

Inheritance flattens. A template inheriting two covenants compiles both into one
deployed contract, so mixins give you source separation and the option to leave
a covenant out, but once you've inherited one you're carrying its bytecode.

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

The saving is per covenant, which is the property that makes a fourth, fifth and
sixth affordable. Each body stays at its own address and the template carries
only the dispatch.

Costs, stated honestly: roughly 2,600 gas cold per library call on the borrow
path, paid by the borrower on every draw; a wider audit surface, since template
behaviour now depends on contracts at addresses rather than inlined code; and a
compile-time link, handled below.

## Events, errors and the ABI trap

Events and errors are declared in `ICovenantEvents`, referenced by both the
mixins and the libraries. **The mixins inherit it**, which keeps every error and
event in the template's ABI even though they're raised from library code.
Selectors and topic hashes are unchanged either way.

Skip that inheritance and the errors quietly vanish from the ABI while still
reverting on-chain, so anything decoding against the template's interface breaks
while everything on-chain looks fine. Easy mistake to make.

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
  'src/access/covenants/lib/CleanDownLib.sol:CleanDownLib:0x...'
]
```

`CovenantLibraries.sol` is the single source of truth for those addresses and
salts. The deploy script and every test suite import from it. `foundry.toml`
can't import Solidity, so its `libraries` entry is the one duplicate you can't
get rid of: change one, change both, same commit.

Those addresses come out of the compiled library bytecode, so they move if the
compiler version or optimizer settings change. The deploy script recomputes each
one and asserts it matches, so drift fails the run rather than registering
templates linked to an empty address. If you see an address-drift error,
regenerate both values together. `CovenantLibraries.sol` carries the recipe.

Tests need the library runtime code placed at the linked addresses before they
touch a template, since a fresh test EVM has nothing there and a library call
into an empty address trips the `extcodesize` check. See
`_deployCovenantLibraries` in the covenant suites.

---

# What's implemented

## Clean-down

Near-universal in revolving facilities. The drawn balance has to return to zero
for `duration` consecutive seconds at least once every `interval` seconds, which
evidences use as a revolver rather than disguised term debt.

Enforcement is a drawstop. Once overdue, draws that would leave the market drawn
revert, and drawing resumes as soon as a fresh qualifying streak completes.

Three behaviours are deliberate and worth knowing before you read the code:

- **Idle time counts from market creation.** A market that has never drawn
  doesn't arrive at its first deadline already in breach.
- **A matured streak is credited at the moment of the next draw**, rather than
  by a keeper. A streak that matured a second ago gets banked inside the
  transaction that consumes it, so there's no sentinel and no liveness
  dependency.
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

One trap worth flagging for anyone modifying this. The calling market is checked
through the `intermediateState` handed to the hook, never through its own
`currentState()`. That view is reentrancy-guarded and the borrow path holds the
lock, so querying it would revert every draw.
`test_onBorrow_HealthySelfDoesNotBlock` guards the regression.

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

Three inconsistent combinations revert at market creation rather than deploying
inert config: an interval without a duration, an interval that doesn't exceed
its duration, and `gateOnPenaltyOnly` without the gate.

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
   `CovenantBase`. That way a template inheriting only some covenants implements
   only their requirements. `CrossMarketDelinquencyCovenant` does this with
   `_covenantBorrower()` and `_covenantArchController()`.
5. Write a concrete template inheriting `CovenantHooksCore` plus your covenant,
   implementing `version()`, `_requiredCovenantFlags()`, `_initCovenants()`, and
   the hook bodies that call your enforcement functions.

Don't add covenant state or logic to `CovenantHooksCore`. The whole reason the
split exists is that a template should only pay for what it inherits.

**Measure the result.** Creation code has to stay under 24,576 bytes, and the
combined template is already using most of its budget. Check with
`FOUNDRY_PROFILE=deploy forge build` and read `bytecode.object` from the
artifact. Don't reach for `forge build --sizes`, which reports runtime size and
will tell you everything's fine when it isn't.

Practically: **a template carrying three covenants won't fit.** Treat templates
as configurations rather than a feature-complete superset, and ship the
combinations borrowers actually ask for.

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

## How the scores work

Each endogenous candidate gets a mark out of 100:

| Component | Weight | What it measures |
| --- | --- | --- |
| Lender value | 30 | How much protection it actually buys, not how impressive it sounds |
| Desk legibility | 20 | Whether a credit person recognises it without a lecture |
| Cheapness to build | 20 | Bytecode, storage, hook surface, test burden. Higher is cheaper |
| Fidelity | 15 | How close the on-chain version gets to the thing it's translating |
| Composition safety | 15 | How little it interferes with the other covenants |

The weights are a judgement call and reasonable people would move them. Lender
value is heaviest because a covenant nobody's protected by is theatre however
elegant it is. Composition safety is in there because a covenant can be
individually correct and still dangerous sitting next to another one, and the
draw timelock below is exactly that case.

Scores are calibrated against each other rather than against anything absolute.
The ordering is more defensible than the individual numbers.

## Implemented

### Cross-market delinquency gate (86/100)

*Lender value 27 · legibility 19 · cheapness 15 · fidelity 14 · composition 11*

The strongest endogenous covenant available, because default status genuinely is
on-chain state. Cross-default is the covenant credit desks lean on hardest, and
here you get it structurally rather than contractually. Marked down on cheapness
for the watch-list loop and its gas ceiling, and on composition because the
watch-list is shared mutable state.

### Clean-down (84/100)

*Lender value 22 · legibility 20 · cheapness 17 · fidelity 15 · composition 10*

Near-universal in TradFi, so a treasurer nods at it immediately. Loses a little
on composition because it interacts with anything else that gates drawing: if
the facility is drawstopped for another reason during the window where the
borrower needs to clean down, you can wedge them. Worth re-checking whenever a
new covenant lands.

## Candidates

### 1. Availability-period expiry (90/100)

A hard drawdown deadline. After it, borrowing reverts while repayment and
withdrawal carry on as normal.

*Lender value 20 · legibility 20 · cheapness 20 · fidelity 15 · composition 15*

Top of the list not because it's clever but because the ratio is absurd. Every
facility in existence has an availability period, every credit person expects
one, and it's a timestamp comparison in `onBorrow`. Nothing else touches it.
Lender value is only moderate on its own, but it's the cheapest protection
you'll ever ship and it makes a facility look finished.

### 2. Commitment-reduction schedule (88/100)

A monotonically declining ceiling, enforced on `onBorrow` and
`onSetMaxTotalSupply`. Implements scheduled commitment reductions and amortising
revolvers.

*Lender value 24 · legibility 19 · cheapness 17 · fidelity 15 · composition 13*

In a syndicated deal this depends on the agent tracking dates and the borrower
not over-drawing, and it gets disputed. Here it's a cap that can't be exceeded,
full stop.

Decide before building: what happens when the ceiling drops below current
supply. Hard stop on new deposits, soft stop, or forced return of capital are
all defensible, and the choice affects lenders more than the borrower.

### 3. Excess-availability springing regime (82/100)

When undrawn availability drops below a threshold, spring a stricter state:
freeze new draws, force a clean-down, or tighten another covenant.

*Lender value 26 · legibility 17 · cheapness 14 · fidelity 14 · composition 11*

Lifted from asset-based lending, where springing controls keyed to availability
do most of the protective work in place of maintenance ratios. Fidelity actually
beats the original, since an ABL agent recomputes availability from a monthly
certificate whereas here it's exact and continuous.

Costs more because you're building a state machine rather than a check, and
composition needs care: a spring that fires into a clean-down window is exactly
the wedge described above.

### 4. Borrowing base over on-chain collateral (79/100)

Availability capped at eligible collateral times an advance rate, minus
reserves.

*Lender value 28 · legibility 20 · cheapness 8 · fidelity 13 · composition 10*

Highest lender value on the board and the widest commercial unlock, since it
opens asset-based lending and receivables finance, both of which dwarf leveraged
lending. Sits at four rather than one purely on cost: eligibility rules, advance
rates, reserves and rounding are a real engine rather than a check.

Conditional in a way the others aren't. It's endogenous **only** where the
collateral and its valuation are both on-chain. Off-chain collateral makes it an
attested covenant and it moves to the section below. If tokenised collateral
turns up in a live market, move this to the top of the list immediately.

### 5. Sweep-before-draw (78/100)

Where borrower inflows are observable on-chain, require application to the drawn
balance before the next draw is permitted.

*Lender value 24 · legibility 18 · cheapness 12 · fidelity 12 · composition 12*

The mandatory-prepayment analogue, and another case where on-chain beats the
original. A TradFi cash sweep depends on the borrower actually remitting and on
the agent's excess-cash-flow calculation, and both leak. Making repayment a
precondition of the next draw can't be dodged. Fidelity capped because it only
ever sees on-chain flows.

### 6. Cross-market aggregate exposure cap (78/100)

A ceiling on total drawn across all of a borrower's markets rather than just
this one.

*Lender value 22 · legibility 16 · cheapness 16 · fidelity 11 · composition 13*

The incurrence-test analogue, and cheap because it reuses the watch-list the
delinquency gate already maintains. Fidelity is the weak spot: it caps Wildcat
debt, not debt, so a borrower can lever up freely anywhere else. Describe it as
limiting concentration within the protocol, never as limiting leverage.

### 7. Utilisation-triggered springing (76/100)

Extra constraints spring when drawn-to-supply crosses a threshold.

*Lender value 14 · legibility 18 · cheapness 18 · fidelity 14 · composition 12*

This is the cov-lite mechanic where a maintenance test springs only once the
revolver is drawn past a point, so it reads instantly to anyone from that
market. Scored low on value because it overlaps heavily with excess-availability
springing. Build one or the other, not both, and excess-availability is the more
useful framing.

### 8. On-chain control change (71/100)

Detect a change in the controlling address or signer set of a smart-account
borrower, and drawstop.

*Lender value 18 · legibility 17 · cheapness 15 · fidelity 7 · composition 14*

Change of control is universal in loan documents so it reads well, but fidelity
is poor and it's worth saying so out loud: this catches the borrower's *wallet*
changing hands. The borrower's *company* is a different matter entirely, and it
happens in a share register nobody on-chain can see. Useful, but easy to
oversell.

### 9. Draw timelock (68/100)

Announce a draw above a threshold, execute it after a delay long enough for any
lender who dislikes it to exit first.

*Lender value 25 · legibility 13 · cheapness 12 · fidelity 10 · composition 8*

Genuinely valuable, and the honest translation of a material adverse change
clause. A MAC clause converts a lender's discomfort into a right to refuse
funding; this converts it into a right to not be there when it funds. No
approver exists, so nothing is compellable, and the draw proceeds against
whatever capital voluntarily stayed.

It still scores badly, and the reasons are worth keeping visible. Legibility is
low because no credit person has heard of it. Fidelity is low because it isn't a
drawstop at all, it's an exit right, and those buy you different things.
Composition is the worst on the board.

Four traps, since anyone building this will hit them:

**Periodic markets break the naive version.** On `PeriodicTermHooks`,
`queueWithdrawal` only succeeds inside scheduled windows, so a fixed delay in
seconds no longer implies exit opportunity. If the next window opens after the
delay expires, the draw executes before any lender could queue. The deadline has
to be window-aware:

```
executableAt = nextWindowStartAfter(announceTime)
             + withdrawalWindowDuration
             + withdrawalBatchDuration
```

Ship a constant delay onto a periodic market and it emits announcement events,
enforces delays, and protects nobody. That's worse than leaving the covenant out
entirely, because integrators and lenders will assume the property holds.
**Shipping this without window-awareness is a bug, not a limitation.**

**Stale announcements are pre-positioned instant draws.** If announcements never
expire, a borrower announces routinely, sits on the ripe ones, and draws
instantly the moment trouble appears. They need a tight execution window
`[executableAt, executableAt + grace]`.

**Exits during the delay reduce available liquidity**, so an announced draw may
be partly or wholly unfundable by execution. That ordering is correct, since
exits should take priority. But decide explicitly between `min(announced,
available)` and revert-and-reannounce: partial-fill lets one small exit shave a
draw, revert-and-reannounce lets one small exit reset the clock. Both are
griefable, in opposite directions.

**A single pending slot is a self-DoS.** Key announcements by `(market, nonce)`,
or a pending large draw locks out the sub-threshold working-capital dribbles a
revolver exists to provide.

There's also a structural dependency. Window-awareness means reading the
schedule from `PeriodicTermHooks`, which is a concrete template deriving from
`BaseAccessControls` rather than a mixin, and `CovenantHooksCore` is
`OpenTermHooks`-equivalent, so no template is currently both periodic and
covenant-bearing. Either refactor the window logic into a mixin and build a
periodic covenant core, or have the covenant declare a host requirement
`_nextWithdrawalWindowStart(market, from)` implemented per template, returning
`from` on open-term hosts. The second is cheaper and leaves `PeriodicTermHooks`
alone.

### 10. Destination-constrained draws (59/100)

Draws only to addresses on a per-market allow-list.

*Lender value 10 · legibility 15 · cheapness 13 · fidelity 8 · composition 13*

Lowest lender value on the list and the score stays honest about that. A
determined absconder moves funds one hop later, so on its own this prevents
nothing. The value is forensic: breaking the disclosed flow is visible and
timestamped, which matters for later proceedings and for compliance teams who
need a funds-flow answer they can't currently get. Price it as evidence. Never
as prevention.

Blocked on a design question too. `WildcatMarket.borrow` transfers to
`msg.sender`, always the borrower, so a hook can't enforce a destination by
inspecting the transfer. It needs the borrower calling through a contract whose
own outbound payments are constrained, or a change to the market's borrow path.
Settle that before writing anything.

### 11. On-chain negative pledge (59/100)

Detect a competing lien or transfer over collateral held in an observable vault,
and drawstop.

*Lender value 14 · legibility 16 · cheapness 11 · fidelity 6 · composition 12*

Same shape of problem as control change: the covenant is universal, the
on-chain version sees a sliver of what it's meant to. Only worth building if a
market appears where the collateral genuinely is on-chain, and at that point the
borrowing base is a better use of the same effort.

## Summary

| # | Covenant | Score | Status |
| --- | --- | --- | --- |
|   | Cross-market delinquency gate | 86 | Implemented |
|   | Clean-down | 84 | Implemented |
| 1 | Availability-period expiry | 90 | |
| 2 | Commitment-reduction schedule | 88 | |
| 3 | Excess-availability springing | 82 | |
| 4 | Borrowing base, on-chain collateral | 79 | Conditional |
| 5 | Sweep-before-draw | 78 | |
| 6 | Cross-market aggregate exposure cap | 78 | |
| 7 | Utilisation-triggered springing | 76 | Overlaps 3 |
| 8 | On-chain control change | 71 | |
| 9 | Draw timelock | 68 | Needs window-awareness |
| 10 | Destination-constrained draws | 59 | Blocked on borrow path |
| 11 | On-chain negative pledge | 59 | |

Two things the scores say that intuition doesn't.

**The draw timelock ranks lower than it feels.** It's the most intellectually
satisfying covenant on the list and it comes ninth, mostly on composition risk
plus the fact that it's an exit right rather than a drawstop.

**The boring ones win.** Availability expiry and commitment reduction are
unglamorous and they're the two highest-scoring items, because they're near-free,
universally understood and interact with nothing. A facility carrying those two
plus what's already implemented reads as complete to a credit desk in a way one
exotic covenant never will.

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
leaned on. Make that a deliberate topology decision rather than an accident of
which covenants the borrower's counsel asked for.

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

Two properties are worth designing around rather than treating as bonuses.

**Breach-triggered disclosure.** A credential's trigger can be any predicate
evaluable on-chain, and that includes the covenant machinery's own state.
Delinquency, an overdue clean-down, availability through a threshold: the
facility already computes all of these, so a credential can be bound to fire on
them. That gives disclosure contingent on breach, which is how information
rights work in practice anyway. Performing borrowers don't open their books; an
event of default switches on rights that lay dormant. Here the asymmetry is
mechanical rather than negotiated, and a borrower never has to trade
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
- **Gas.** Each covenant owns its own storage slot, so a template inheriting two
  pays one extra cold `SLOAD` on the borrow path relative to a single packed
  struct, on top of a delegatecall into each library. Negligible against a
  borrow, but it's the price of the split.
- **No `CovenantLens` test.** It compiles and is read-only, but a fixture-based
  suite would be better than nothing.

Test conventions follow `TESTS.md`: unit tests mirror `src/` paths and functions
are named `test_<functionName>_<PascalCaseLabel>`, with error-path tests
labelled by error name.
