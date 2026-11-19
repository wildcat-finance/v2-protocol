# Code comment voice

Code-casual, slightly impatient, terse, precise, conceptual. Write for a peer
who knows the language but still needs this code's model and constraints.
This is a source-comment voice, not an imitation of anyone's personal voice.

[STYLE_GUIDE.md](./STYLE_GUIDE.md) owns layout, cards, spacing, and function order.
This guide owns the words inside that layout. The reference implementation is
[`WildcatMarketWithdrawals.sol`](./src/market/WildcatMarketWithdrawals.sol).
Apply it within the agreed prose-editing scope; a layout-only pass must preserve
existing wording.

## The voice

Get to the useful part. Name the constraint, explain the consequence, stop.
The impatience is with unnecessary explanation, not with the reader.

- **Casual:** ordinary verbs, natural contractions, no ceremony. Technical nouns
  stay exact. Casual does not mean approximate.
- **Slightly impatient:** put the restriction or reason first.
  `don't reuse this key` is useful when the next sentence says what reuse breaks.
  Don't turn every comment into an order.
- **Terse:** remove setup and repetition, not qualifications. A short comment
  that needs three guesses is not an improvement.
- **Precise:** keep units, actors, rounding direction, conditions, exceptions,
  and failure behavior. `funded`, `expired`, and `claimed` are different states.
- **Conceptual:** explain the accounting, lifecycle, or trust boundary. The code
  already shows the assignments and branches.

No forced personality. Don't add `yeah`, `obviously`, `just`, jokes, profanity,
sarcasm, or fake frustration to make a comment sound casual. No assistant-style
setup such as `it's important to note that`. Use emphasis only for a real warning.

## What earns a comment

A comment should supply something a reader cannot get cheaply from the next line:

- Why this order matters, or what a tempting simplification would break.
- Which quantities must agree and which assets or actors an operation affects.
- A boundary case, representation limit, rounding choice, or caller obligation.
- The distinction between a stored value, a preview, and a committed transition.

An overview can explain **what** a larger operation does. An inline comment usually
earns its place with **why**, **under what condition**, or **what must stay true**.
Don't narrate `load`, `increment`, `emit`, or `update` when the code says the same
thing. Remove that comment rather than finding a more colorful verb.

Keep useful explanations, even when they're long. An arithmetic bound, assembly
layout, or security rationale may need a paragraph. Terseness is not a word limit.
Don't replace a proof with `safe`, or a specific invariant with `keep in sync`.

## Sentence style

- Use lowercase prose by default. Preserve identifiers, acronyms, proper names,
  units, quoted text, licenses, and the existing decorative headings.
- Prefer direct verbs: `queue`, `reserve`, `burn`, `claim`, `revert`. Avoid
  `perform the processing of` and similar scaffolding.
- Short sentences and useful fragments are fine. Contractions are fine too.
  Full sentences get periods; the reader shouldn't have to reconstruct them.
- State cause and consequence plainly: `do this so that ...`.
  `don't do this; it would ...` works too. Not every comment needs that pattern.
- Name the actual subject when `this`, `it`, or `the value` could mean two things.
  Use exact identifiers when they're clearer than a new nickname.
- Don't manufacture urgency, certainty, history, intent, or performance claims.
  Keep `can` distinct from `always`, and `must` distinct from `usually`.

## NatSpec and inline comments

Use the same voice in both. NatSpec is not the formal version of an inline comment.

- `@notice`: the operation and its caller-visible result. Lead with a verb;
  don't repeat the function name in prose.
- `@dev`: the model, restriction, exception, or integration detail that a caller
  or maintainer needs. Don't repeat the notice with more words.
- `@param`: the value's role and units, plus a meaningful sentinel or boundary.
  Keep parameter names exact and retain the existing alignment.
- `@return`: what comes back and in which units. Distinguish a zero result from
  a revert, and reserved assets from assets actually transferred.
- Inline comments: the local reason or invariant. Keep each explanation with
  the code it covers, including coupled writes and their assembly checks.

Don't document every local variable. Don't repeat the same explanation in the
notice, dev paragraph, and body. A short reminder is useful where two separate
implementations must preserve the same rule, such as a preview and execution.

## Calibration

These are wording examples, not permission to invent the underlying behavior.

Narration:

```solidity
// Cache account data
Account memory account = _getAccount(msg.sender);
```

Remove the comment. The assignment already says it.

Constraint with its reason:

```solidity
// don't reopen a processed batch. mixing pre- and post-close claims shifts value
// between withdrawers.
```

Representation versus admission:

```solidity
// the ABI is uint128. keep the uint104 admission cap and its overflow panic.
```

An exception the reader could miss:

```solidity
// funded closure can release the batch before expiry. preview and execution must agree.
```

Too terse: `// no reuse`. Too performative: `// obviously don't reuse the damn key`.
Neither explains what breaks. The constraint-and-consequence version does.

## Applying and reviewing

1. Read the implementation and relevant callers before changing a claim. Use the
   existing prose as evidence, not as proof that every sentence is still correct.
2. Identify the substantive points: actors, units, conditions, invariants, failure
   cases, and reasons. Preserve those while removing narration and duplicate prose.
3. If a comment conflicts with the code, resolve it from the implementation and
   tests. Call out a substantive correction; don't hide it as a voice change.
4. Leave code tokens, signatures, function order, tags, visual layout, and unrelated
   files alone. A prose pass is not a refactor or a new round of feature design.
5. Check technical accuracy and voice separately. Then check formatting, NatSpec
   attachment, ABI, and affected creation/runtime bytecode against the pre-edit
   source baseline. Prose changes intentionally change generated documentation;
   they must not change its coverage or turn decoration into documentation.

Final read: does each comment explain the model, a constraint, or a consequence?
Is every qualification still there? Does any sentence exist only to show off
the voice? Cut that sentence, not the technical detail.
