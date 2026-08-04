# Revolving credit facility covenants: taxonomy and on-chain implementability

> **Status: internal working note. Figures unverified.**
>
> This survey was compiled without access to primary sources. Every numeric
> parameter in it is stated as market-typical and **has not been checked**:
> ABL advance rates, cov-lite springing thresholds, excess-cash-flow sweep
> percentages, FCCR levels, restricted-payment basket sizes. Do not cite any
> figure from this document externally, and do not treat the DeFi prior-art
> claims as settled without checking each protocol's own post-mortems.
>
> The taxonomy and the endogenous/attested/not-implementable classification are
> the useful parts and are robust. The numbers are placeholders pending a pass
> against LMA/LSTA precedents, Practical Law, and law firm practice notes.

The classification used throughout:

- **Endogenous** — computable from chain state alone. No attestor, no
  compellable party. Built as covenant mixins under `src/access/covenants/`.
- **Attested** — requires an off-chain signer. Implementable, but introduces a
  party who can be compelled or who can simply stop. Acceptable only where
  failure freezes drawdown rather than permitting it.
- **Not implementable** — requires human judgement or off-chain acts that
  cannot be represented on-chain.

Currently built: clean-down (`CleanDownCovenant`) and the cross-market
delinquency gate (`CrossMarketDelinquencyCovenant`). Both endogenous.

Scoped but unbuilt, with design notes in `src/access/covenants/README.md`:
draw timelocks sized to the exit window, staleness-gated attestations, and
destination-constrained draws.

## Where the remaining value is

The survey's practical conclusion, independent of any unverified figure: the
structural and mechanical family of covenants is the one worth pursuing, and
it is under-exploited relative to its value.

Endogenous candidates not yet built, in rough priority order:

1. **Availability-period expiry.** A hard drawdown deadline enforced in the
   borrow hook. Near-zero cost, implements a universal facility term.
2. **Commitment-reduction schedule.** A monotonic declining ceiling enforced on
   `setMaxTotalSupply` and `borrow`. Implements scheduled commitment reductions
   and amortising revolvers.
3. **Excess-availability springing regime.** When undrawn availability falls
   below a threshold, spring a stricter state. Derived from ABL practice, where
   springing controls keyed to availability do most of the protective work in
   place of maintenance ratios. On-chain the trigger is exact and continuous
   rather than dependent on a monthly borrowing-base certificate.
4. **Sweep-before-draw.** Where borrower inflows are observable on-chain,
   require application to drawn balance before the next draw. The mandatory
   prepayment analogue, and it enforces itself rather than depending on the
   borrower remitting.
5. **Borrowing base over tokenised collateral.** Availability capped at
   eligible collateral times advance rate. Fully endogenous only where the
   collateral and its valuation are on-chain; otherwise attested.

Not worth building as on-chain covenants: financial maintenance ratios
(leverage, interest cover, FCCR, minimum EBITDA, tangible net worth), negative
pledge over off-chain assets, restricted payments, affiliate transactions,
incurrence tests on pro-forma accounting, equity cures, inspection rights.
These are attested at best. Where lenders require them, route them through the
staleness-gated attestation hook so that issuer failure freezes drawdown, and
be explicit that they carry attestor dependency.

## Why the mechanical family automates better than it enforces

A commitment-reduction schedule in a syndicated facility depends on the agent
tracking dates and the borrower not over-drawing; disputes happen. On-chain it
is a cap that cannot be exceeded. An asset-based lender recalculates a
borrowing base monthly from a certificate; the same formula on-chain runs
continuously and cannot be gamed between reporting dates. Payment waterfalls
and pro-rata sharing, a perennial source of litigation in the syndicated
market, are deterministic here and cannot be subverted by an amendment executed
off the rails.

This is the direction the loan market has been moving anyway. Protective weight
has shifted for two decades away from judgement-based maintenance ratios toward
mechanical, formula-driven structures. Those are the structures that translate.

## Attested covenants and issuer substitutability

An attested covenant depends on an issuer, and an issuer can be compelled or
can stop. Under the sealed entity credentials draft ERC that dependency is a
supplier relationship rather than a single point of failure: acceptance turns
on schema and trigger conformance rather than issuer identity, so a consumer
can rotate its accepted set. The failure mode becomes "needs a new supplier"
rather than "facility halts".

Two questions determine how strong that property actually is, and neither is
settled: who holds rotation authority, and whether equivalence between issuers
is mechanical or judged. See `why-credentials-and-covenants-compose.md`.
