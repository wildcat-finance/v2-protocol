# Why sealed credentials and covenant hooks compose

A note on why these two pieces are more useful together than either is alone.

Reference: [sealed entity credentials draft ERC](https://hackmd.io/@wildcatlabs/erc-draft-sealed-entity-credentials)

---

## The two halves of an enforcement problem

A covenant does two things. It **defines a condition**, and it **attaches a
consequence** when that condition fails. Loan documents spend most of their
length on the first and almost none on the second, because the consequence is
assumed: a lawyer writes a demand, and behind the demand sits a court.

On-chain, the ratio inverts. Attaching a consequence is trivial and perfectly
reliable — a hook on the borrow path either lets a draw through or it doesn't,
every time, with no discretion and nobody to persuade. Defining the condition
is where everything falls apart, because a smart contract can only see what is
on the chain, and almost nothing a credit analyst cares about is on the chain.

That is the whole shape of it. Hooks solve enforcement and can't reach the
facts. Credentials reach the facts and can't enforce anything. Neither half is
interesting alone.

## What each half actually provides

**Covenant hooks** give deterministic enforcement over on-chain state. The
enforcement point is the borrow path, which is the right place: a drawstop is
the natural remedy for a revolver, more proportionate than acceleration and
requiring no third party to invoke it. Once written, enforcement can't be
waived by inattention, negotiated away in the moment, or ignored because
someone didn't want the conversation.

The constraint is the state space. Delinquency, drawn balance, utilisation,
elapsed time, addresses, balances: all visible. Leverage, licensing, collateral
value, corporate control: all invisible. Roughly a third of the covenant
universe sits inside the visible set.

**Sealed credentials** extend the state space. An issuer asserts something a
contract cannot observe, and the assertion becomes a fact the chain can read.
The extension is large — it covers most of the remaining two thirds — and it is
privacy-preserving, which is the only reason it is commercially usable.

The constraint is that a credential asserts and does nothing else. It has no
opinion about what should follow.

## Why the composition is clean rather than a bolt-on

Three properties make this fit better than "oracle plus contract" usually does.

**The failure direction is right.** Gate a draw on credential freshness and
issuer failure produces a freeze. Nobody has to notice, decide, or act. That
matters because it converts an affirmative covenant — *deliver financials by
the 45th day*, an obligation needing enforcement — into a condition precedent —
*draw only while the certificate is current*, which enforces itself. TradFi
cannot make this conversion, because a bank that froze a facility every time a
certificate ran late would lose the client. A protocol has no such incentive
and can hold the line.

**Determinism survives the boundary.** The credential's contribution is a
fact; the hook's contribution is a rule. The rule stays as deterministic as it
was before, because the fact enters as an input rather than as a judgement.
Compare with the usual arrangement in on-chain credit, where an off-chain
committee looks at off-chain information and decides. That is not enforcement,
it is delegation, and it degrades to exactly the problem being escaped.

**Non-retroactivity is what makes a covenant a covenant.** A covenant that can
be restated after reliance is not a covenant, it is a preference. Commit-then-
reveal gives a pinned figure that cannot be quietly revised, which is precisely
the property a lender needs when advancing against a compliance certificate.
The damaging failure was never a wrong number; it was a number that moved after
the money went out.

## The part that only works because both halves are present

A credential's trigger can be any predicate evaluable on-chain — which includes
the covenant machinery's own state. Delinquency, an overdue clean-down,
availability through a threshold: the facility already computes all of these,
and a credential can be bound to fire on them.

So the composition runs in both directions. Credentials feed facts into the
hooks; the hooks' own state feeds triggers back into the credentials. Neither
half can do this alone, and it produces something neither was separately aiming
at: **disclosure contingent on breach**.

Which is how information rights actually work. A performing borrower doesn't
open its books. An event of default switches on inspection and reporting rights
that lay dormant while the facility behaved. That asymmetry is negotiated,
imperfectly enforced, and usually litigated. Here it is mechanical: nothing is
disclosed during normal operation, and the event that makes disclosure relevant
is the event that causes it.

The commercial version: a borrower is never asked to trade confidentiality for
covenant protection. They keep confidentiality exactly as long as they are
performing, and the disclosure they concede is contingent on something within
their power to avoid.

## What it does not fix

Worth stating plainly, because overselling this is the fastest way to lose a
sophisticated reader.

A credential has an issuer. An issuer is a party. A party can be unavailable,
compelled, or simply stop. Sealing changes what is *visible*; it does not
change who can be *reached*. An attested covenant is strictly weaker than an
endogenous one and should be described that way.

Two consequences follow.

**Prefer endogenous where a choice exists.** Anything computable from chain
state should be computed from chain state. Clean-down, cross-default,
availability expiry, commitment reduction, utilisation triggers and sweeps need
no issuer, so giving them one is a straight loss.

**Watch concentration, not count.** Twenty attested covenants through one
issuer is a worse structure than five through five, because a single order or
outage halts the facility. The interesting design question is not *which
covenants can we express* but *how many distinct parties does this facility
depend on, and what happens when each is leaned on*. That is a topology
decision, and it should be deliberate rather than an accident of which
covenants the borrower's counsel asked for.

## Issuers are substitutable, and that is the whole point

The standard doesn't privilege particular issuers. Anyone may issue; a consumer
accepts credentials from any issuer meeting its schema and a trigger at least as
stringent as the one it already accepts. Acceptance is conformance-based, not
identity-based.

Which means no issuer is load-bearing. Compel one, and the facility rotates its
accepted set. The dependency is real but it is a *supplier* dependency rather
than a single point of failure, and suppliers are replaceable in a way that
counterparties named in a contract are not.

This is the walkaway test applied one layer up. The same argument that says
infrastructure should survive its authors leaving says it should survive its
attestors leaving. A design where the Foundation going dark ends participation
would fail that test regardless of how good the cryptography was.

Two questions determine whether the property is as strong as it sounds, and
both should have crisp answers before anyone leans on it:

- **Who holds rotation authority?** Curated by the Foundation and the Foundation
  is still the compellable party, one level up. Fixed at market deployment and
  there is no rotation without redeploying. Lender-governed is a third shape.
  The property inherits the weakness of whatever governs the set.
- **Is equivalence mechanical or judged?** Hash-comparable schema and trigger
  conformance is unimpeachable. A human deciding issuer Y is "stringent enough"
  is a control point in different clothing.

Worth saying to prospective issuers directly rather than letting them work it
out. It does mean no lock-in. It also means integration is safe to agree to: a
protocol that couldn't rotate issuers couldn't responsibly onboard one, because
the dependency would be permanent. Substitutability is what makes an issuer
adoptable, and it moves competition onto attestation quality and declared
policy — which suits providers who have something to declare.

## The resulting picture

A facility ends up with two tiers, and being explicit about which is which is
part of the product.

**Tier one — endogenous.** Enforced by the protocol, dependent on nobody.
Roughly a third of the covenant package, and the third that includes most of
the mechanical protections asset-based lenders actually rely on.

**Tier two — attested.** Enforced by the protocol, conditional on an issuer.
Most of the remaining two thirds. Fails safe. Priceable, because the issuer's
policy is declared up front rather than discovered at default.

That second point is the quiet one. Today a lender cannot distinguish a
facility with real underwriting from one with none, so both price the same and
the careful borrower subsidises the careless. Declared issuer policy makes
attestation quality a visible input. Once it is visible it gets priced, and
once it is priced there is a reason to buy the good version.

---

*Design rationale for the covenant hooks in `src/access/covenants/`. Explains
why the architecture separates endogenous covenants from attested ones and why
attested covenants are gated on credential freshness rather than enforced
directly. Not legal advice.*
