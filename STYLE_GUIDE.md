# Solidity source style guide

This guide defines the formatting, source organization, and comment layout used
to give readers and auditors consistent visual landmarks. It is written for
contributors and coding agents applying the style to existing Solidity code.

The reference implementation is
[`WildcatMarketWithdrawals.sol`](./src/market/WildcatMarketWithdrawals.sol).
Apply it within the agreed scope, not as an unsolicited rewrite of dependencies,
generated code, or frozen historical evidence.

Track the repository-wide adoption in [STYLE_ROLLOUT.md](./STYLE_ROLLOUT.md).

The intended hierarchy is a prominent file header, full-width logical section
headers, compact function cards, and ordinary inline comments. Whitespace
separates ideas; decoration identifies boundaries. Do not add more graphical
layers to compensate for unclear organization.

## Safety boundaries

A presentation pass must preserve behavior and reviewed documentation.

- Move complete functions together with their attached documentation. Preserve
  names, signatures, visibility, modifiers, and bodies.
- Preserve inheritance order, storage declarations, initializers, struct field
  order, enum values, and assembly layout assumptions.
- Preserve event and error parameter order and their associated emitters.
- Do not rename functions, change visibility, extract helpers, or change logic
  merely to make the layout easier to arrange.
- Preserve NatSpec wording and existing prose wrapping unless a separate prose
  edit is part of the task. Cards and spacing are not an invitation to rewrite
  audited explanations.
- Leave dependencies, generated files, and unrelated working-tree changes alone.

Function reordering can affect compiler output even when the function bodies
are unchanged. Cosmetic intent is not proof of bytecode or deployment-size
equivalence. Follow the validation guidance below.

### Bytecode-locked contracts

Before a rollout, explicitly identify contracts whose bytecode must not change,
including contracts not planned for redeployment, and record their comparison
baselines. This is a bytecode lock, not an unconditional ban on reordering.

- Comments, formatting, and function moves are permitted only when creation
  and runtime bytecode remain identical for every affected locked contract.
  Include inheriting contracts and other affected build outputs, not just the
  contract named in the edited file.
- Use the same compiler version, settings, dependencies, and linking inputs
  for both builds. Do not change build settings to make a comparison pass.
- Stop and review any mismatch before accepting the protected change. Passing
  tests or staying below a size limit is not a substitute for bytecode identity.
- For a deployed contract, use its verified deployment or release baseline.
  Equality with the current branch's `HEAD` alone does not establish equality
  with deployed code.
- Settings such as `bytecode_hash = 'none'` and `cbor_metadata = false` remove
  metadata-related differences; they do not guarantee that every reorder leaves
  executable bytecode unchanged.

Bytecode identity does not preserve source maps, source line numbers, or audit
references. Review those separately where they matter. This guide does not
itself establish a deployment inventory or declare a contract verified.

## Formatter

Use the Foundry version pinned in [`.foundry-version`](./.foundry-version).
[`foundry.toml`](./foundry.toml) is authoritative for the active configuration.
The agreed formatter settings are:

```toml
[fmt]
line_length = 120
tab_width = 2
bracket_spacing = true
quote_style = 'single'
multiline_func_header = 'all'
prefer_compact = 'none'
int_types = 'preserve'
number_underscore = 'preserve'
hex_underscore = 'preserve'
wrap_comments = false
docs_style = 'preserve'
single_line_statement_blocks = 'preserve'
sort_imports = false
namespace_import_style = 'preserve'
```

Use two-space indentation, single-quoted strings, bracket spacing, and a
120-column code line target. The decorative full-width rules described below
use 80 columns, including indentation and the comment prefix; they do not impose
an 80-column limit on code or NatSpec prose.

Let Forge lay out function signatures. With these settings, long headers expand
their parameters, modifiers, and return clauses; short headers may remain on
one line. This does not force every return parameter onto its own line. Do not
fight the formatter with manual wrapping that it will immediately undo.

The repository also has older Prettier and Solhint settings, and the package
lint scripts use those tools. Their Solidity formatting rules are not fully
aligned with this configuration. Do not alternate formatters or use
`yarn lint:fix` as a substitute for Forge during this cleanup. Changes to lint
tooling are a separate task.

## Source organization

Keep the existing license notice and pragma first. Put the file title block
immediately after the pragma, followed by imports and the documented contract,
interface, or library declaration. Preserve import order during a presentation
pass.

Group functions by conceptual flow, not visibility. Put an operation's entry
points and implementation helpers together, preserving their actual visibility.
For the withdrawal reference, the groups are:

1. Queueing: the queue entry points, followed by `_queueWithdrawal`.
2. Batch funding: repayment and processing, followed by the batch helper.
3. Claim collection: single and multi-claim entry points, their execution
   helper, and the matching available-amount query.
4. Queries: the remaining independent getters.

A view that must agree with a state-changing operation belongs beside that
operation, not in a distant visibility or getter section. Keep related overloads
adjacent. Do not change visibility or add wrappers to make the layout uniform.

Choose a workflow appropriate to each file. Related implementations should use
comparable conceptual ordering so readers can find corresponding operations
across files. Do not impose the withdrawal workflow on unrelated domains or
alphabetize functions instead of arranging their flow.

Use logical declaration sections such as events or errors where useful, but
do not move storage or layout-sensitive declarations merely to achieve a
preferred visual order. Constructors, receive/fallback functions, modifiers,
free functions, and files with multiple declarations need sections appropriate
to their actual contents. Do not invent a visibility category for them.

Omit empty sections. The source itself should provide a natural reading order;
do not add a separate suggested reading-order essay or a storage map.

## File title and function index

Use ordinary `//` comments for the decorative banner, not `///` or a block
comment. A NatSpec banner can become an unintended notice when placed above an
otherwise undocumented declaration. Reserve `///` for actual declaration and
function documentation; do not rely on imports to isolate decoration from it.

Keep the logo, project/family label, file name, one-sentence purpose, and complete
function index inside one open-sided frame. The following is the reference layout:

```solidity
// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // WildcatMarketWithdrawals
// ║  ██▀▀     ▀▀██   Withdrawal queueing, batch funding, and claim collection.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  QUEUEING
// ║  queueWithdrawal(...)
// ║  queueWithdrawalScaled(...)
// ║  queueFullWithdrawal()
// ║  _queueWithdrawal(...)
// ║
// ║  BATCH FUNDING
// ║  repayAndProcessUnpaidWithdrawalBatches(...)
// ║  _processUnpaidWithdrawalBatch(...)
// ║
// ║  CLAIM COLLECTION
// ║  executeWithdrawal(...)
// ║  executeWithdrawals(...)
// ║  _executeWithdrawal(...)
// ║  getAvailableWithdrawalAmount(...)
// ║
// ║  QUERIES
// ║  getUnpaidBatchExpiries()
// ║  getWithdrawalBatch(...)
// ║  getAccountWithdrawalStatus(...)
// ╚═════
```

- Keep the five-row logo unchanged. It uses only full and half blocks, not
  triangle glyphs or terminal color escape sequences. Check its rendering in
  the editor when applying the style in a different environment.
- Use `WILDCAT v2.5` as the contract-family identifier, alongside the appropriate
  file or primary declaration name. It distinguishes this family from v2.0 or
  v2.1; it is not a package patch version or evidence of deployment. Keep it
  stable within the family rather than updating it for each patch release.
- List every function defined in the file, not inherited-only functions. Use
  `name(...)` when there are parameters and `name()` when there are none.
- Build the index after reordering. Its entries and conceptual groups must
  match the actual source order. Keep overload entries adjacent.
- Use one function per line, plain uppercase group labels, and one blank framed
  line between groups. Do not compress groups into dot-separated lists.
  For multiple declarations or special function kinds, use enough labels to
  reflect the actual layout without introducing another decorative scheme.
- Repeating a function name in the index, its card, and its signature is
  intentional. Keep all three synchronized; do not remove navigation merely
  to avoid maintaining repeated names.
- Do not include parameter types, return types, line numbers, or a storage map.
- Continue the left `║` through the index. End with `// ╚═════`: five double
  horizontal characters, not a full-width bottom rule. Do not add a right rail.

## Declaration cards

The file banner does not replace the declaration's NatSpec. Give the contract,
interface, or library its own card immediately above its declaration:

```solidity
// ┌─ WildcatMarketWithdrawals ─────────────────────────────────────────────────
/// @notice batched lender exit flow with FIFO payment priority across expired batches.
```

This declaration-level top rule remains 80 columns wide. There is no closing
rule. Keep the declaration directly after its NatSpec, with its original
inheritance list and documentation intact. The file's visual tagline does not
replace or override this tool-readable documentation.

## Logical section headers

Use a single-line gradient header for each meaningful section:

```solidity
  // ░░▒▒▓▓██ [ QUEUEING ] ─────────────────────────────────────────────────────

  // ░░▒▒▓▓██ [ BATCH FUNDING ] ────────────────────────────────────────────────

  // ░░▒▒▓▓██ [ CLAIM COLLECTION ] ─────────────────────────────────────────────

  // ░░▒▒▓▓██ [ QUERIES ] ──────────────────────────────────────────────────────
```

Use the same pattern for other file-appropriate flows and declaration sections,
such as `EVENTS` or `ERRORS`. Labels are uppercase and should match the conceptual
groups in the index where applicable. Adjust the trailing rule to end at column
80, counting indentation and the comment prefix. Leave a blank line above and
below the header.

Use ordinary `//` comments for these headers. There is no endpoint circle, no
angled gradient cap, and no extra border above or below. The gradient already
distinguishes a major section from a function card.

## Function NatSpec cards

Every function gets a compact named card, including small getters and internal
helpers. Use the function's existing name and a five-character trailing rule.
There is no card footer:

```solidity
  // ┌─ executeWithdrawals ─────
  /// @notice claims several account/batch pairs in one transaction.
  ///
  /// @dev the arrays are paired by index. one invalid or empty claim reverts the whole call.
  ///
  /// @param accountAddresses lenders that own each claim.
  /// @param expiries         batch key paired with each lender.
  ///
  /// @return amounts underlying assets transferred for each pair.
```

Function-card tops are not padded to a fixed width. Reserve full-width rules
for the file, declaration, and logical section boundaries. Do not introduce
different card styles for tiny getters or repeat the logo on individual cards.

Keep the function declaration directly after the last NatSpec line, without a
closing rule or intervening blank line. Inside the card:

- Keep `@notice`, `@dev`, parameters, and returns in distinct groups, separated
  by one empty `///` line. Include only the groups applicable to the function.
- Keep consecutive `@param` entries together and align their descriptions
  within that card. Keep consecutive `@return` entries together as well.
- Preserve existing text and prose wrapping. Do not add filler documentation
  just to populate every tag group.
- Keep tags and parameter names valid for the declaration. In particular,
  `@title` is not a function-level tag. Use the ordinary-comment card label as
  the function heading instead.
- Put decorative headings in `//`, not `///`. Text inside NatSpec can leak into
  generated documentation. Do not prefix the function's NatSpec lines with the
  file header's `║` rail.

Refer to the
[Solidity NatSpec reference](https://docs.soliditylang.org/en/v0.8.25/natspec-format.html)
for supported tags. Source formatting and generated documentation are separate
concerns: wrapping or indenting continuation lines can change whitespace in
`userdoc` and `devdoc`. Do not assume a visual-only edit leaves those outputs
identical without checking.

## Inline comments and whitespace

Use blank lines to separate logical steps, not mechanically before every
comment. Leave one blank line above a comment that introduces a new step after
a statement or closing code block:

```solidity
    uint256 normalizedAmountWithdrawn = _executeWithdrawal(state, accountAddress, expiry);

    // Update stored state
    _writeState(state);
```

Keep the comment immediately above the code it explains. Do not insert blank
lines between consecutive lines of the same comment, or between a card's border
and its NatSpec. Comments at the start of a function, loop, or conditional may
sit directly after the opening brace without an extra blank line.

A nested explanatory comment can stay inside a cohesive operation without a
blank line above it. In particular:

- Keep coupled account, batch, and market-state updates together, even when an
  assembly explanation appears between those writes.
- Keep a loop's initializer with its loop; put a comment describing the whole
  operation above the initializer rather than splitting them apart.
- Keep an event with the preceding mutation when the comment describes both.
- Separate a completed guard from the next logical step, such as selecting and
  loading batch data. Give a final state write its own paragraph when it is a
  distinct step after processing.

A comment should describe a coherent unit of work. Do not insert a blank line
that makes part of that unit appear unrelated, or add obvious comments merely
to make every paragraph look symmetrical.

Retain useful whitespace between logical steps and between functions. Do not
compress it to offset the height of the documentation, and do not add multiple
blank lines as another way to emphasize section boundaries.

## Applying the guide

1. Read the repository's applicable instructions and inspect the working tree.
   Identify the files in scope, any bytecode-locked contracts and their verified
   baselines, and preserve unrelated edits.
2. Check the pinned formatter version and configuration. When adapting this
   guide to another repository, agree on formatter adoption and project/family
   branding rather than copying Wildcat-specific labels or replacing build
   settings.
3. Inventory the file's functions and choose a domain-appropriate workflow.
   Reorder complete function units by conceptual flow, keeping related entry
   points, helpers, and behavior-dependent queries together while
   preserving all safety boundaries above.
4. Build the title and function index from the resulting source order. Add
   declaration cards, section headers, compact function cards, and comment
   spacing without rewriting the implementation or documentation prose.
5. Format and check only the intended files. Review the result in a monospaced
   editor; the gradients should identify major sections and the compact cards
   should identify individual functions without competing with those sections.
6. Verify the index against the definitions and compare the implementation and
   documentation with the pre-edit baseline. Keep this guide and the reference
   implementation consistent when intentionally changing the convention.

For the reference file, the formatting checks are:

```sh
forge fmt src/market/WildcatMarketWithdrawals.sol
forge fmt --check src/market/WildcatMarketWithdrawals.sol
git diff --check
```

Validation should match the edit:

- For decoration and whitespace changes, inspect the diff and run the scoped
  formatter and whitespace checks. When changing NatSpec layout or attachment,
  compare the compiler's `userdoc` and `devdoc`; cards and spacing must not lose
  documentation or add border text to it.
- For function reordering, additionally verify that every original definition
  remains intact, compare creation and runtime bytecode and generated ABI and
  documentation for affected contracts, and run the affected tests and applicable
  deployment-size checks. Use [`TESTS.md`](./TESTS.md) for the repository's test
  policy.
- For bytecode-locked contracts, apply the identity gate above to every
  presentation change, including comments and whitespace. Record the baseline
  and build inputs used; do not substitute a current-branch comparison for
  verification against the protected baseline.
- For an explicitly approved prose or behavior change, review and validate it
  separately from the mechanical presentation changes.

Do not stage, commit, or expand the migration beyond the requested scope merely
because a file now matches the guide.
