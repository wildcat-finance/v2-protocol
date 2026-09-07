# Runbook: emitter-fidelity differential suite

Derived from `.hexaemeron/study.md`. The selected design is the one the record
below locks; no step reopens that choice.

```design-lock
schema | protasis-design-evidence/v1
sha256 | af3f9fd53c62692eb01a47811865029850a1ddd52e800b6a303bc2ae94873369
candidate | mirror-emit
```

### Source receipts

```text
starting ref: f5a26146987926f4811b72a795d662813dedfe85
run branch: fiat/fizz-4-emitter-fidelity-differential-suite
kickoff issue: https://github.com/wildcat-finance/skills/issues/1354
```

The topic is one capability in four dependency-ordered steps, so there is no
module table. Step 1 puts the accepted proposition in the tree. Step 2 builds
the harness that produces and compares two logs. Step 3 fills in all 27
emitter cases. Step 4 runs the campaign and records it. The suite is a Fizz
artefact and Fizz is a vendored skill with no ledger, so no step appends a
version row and no `version-relations` block is declared.

The kickoff issue belongs to another repository, so this run records no task
issue and its closure is a manual step after the merge rather than a closing
keyword in the pull request body.

Two commands matter at every step and neither is `forge build`. `forge build`
exits 1 at the starting ref because `forge lint` denies a pre-existing
`unsafe-typecast` and this Foundry release offers no flag to skip it, so a
step that gated on it could never be met. The suite command is:

```bash
forge test --match-path 'test/fizz/*.t.sol'
```

and the repository-wide command is the one `package.json` declares as its
`test` script:

```bash
forge test --block-timestamp $(date +%s)
```

The suite command must exit 0 at every step's exit. The repository-wide
command does not, and cannot: at the starting ref it exits 1 with exactly two
failing tests, `testFail_redeem` and `testFail_withdraw`, against 795 passing,
because this Foundry release removed the `testFail` prefix those two still
use. Neither is touched by this run. So each step requires that command to
report those same two failures and no others, with the passing count not
falling below 795. New Solidity also passes the repository's own `lint:check`
script, which runs Prettier and Solhint over `src` and `test`.

The committed `.horos/boundary.json` describes a tracked universe and is
already two files stale at the starting ref, so each step regenerates it with
the Horos scanner as its last action before committing and requires
`python3 <plugin-root>/../horos/skills/horos/scripts/horos.py check .` to
report that the boundary matches the tree.

The source-bound Elenchus runner contract is the same at every step, because
every step's evidence is the same suite. The test command is
`sh -c "forge test --match-path 'test/fizz/*.t.sol' --junit > {report}"`, the
report format is `forge-junit-v1`, and the report file is
`.hexaemeron/test-reports/step-<n>.json`. A missing, stale, empty or
malformed report is `inconclusive`, never evidence that a repair is guarded.

## Step 1: Publish the accepted specification

**Goal.** Commit the receipted study and runbook as tracked documents, in the
shape this repository already uses for prose, so the proposition is readable
before any test code exists.

**Entry.** The run branch `fiat/fizz-4-emitter-fidelity-differential-suite` at
starting ref `f5a26146987926f4811b72a795d662813dedfe85`, working tree clean.
No tracked file from this run exists at entry, and `docs/` holds flat prose
files whose names carry spaces, indexed by `docs/README.md`.

**Exit.** The following all hold on the committed head:

1. `docs/Emitter Fidelity Study.md` is byte-identical to the receipted
   `.hexaemeron/study.md`, and `docs/Emitter Fidelity Runbook.md` is
   byte-identical to the receipted `.hexaemeron/runbook.md`, each proved by
   `cmp -s` exiting 0.
2. `docs/README.md` gains one index line per document, matching the form the
   surrounding entries already use.
3. `python3 <plugin-root>/skills/protasis/scripts/protasis.py --study 'docs/Emitter Fidelity Study.md'`
   and `python3 <plugin-root>/skills/protasis/scripts/protasis.py 'docs/Emitter Fidelity Runbook.md'`
   exit 0, and
   `python3 <plugin-root>/skills/imprimatur/scripts/imprimatur.py 'docs/Emitter Fidelity Study.md' 'docs/Emitter Fidelity Runbook.md' docs/README.md`
   reports no defect.
4. The Horos boundary is regenerated and
   `python3 <plugin-root>/../horos/skills/horos/scripts/horos.py check .`
   reports that it matches the tree, which also clears the two-file staleness
   the starting ref carries.
5. `forge test --block-timestamp $(date +%s)` reports the two pre-existing
   failures and no others, with at least 795 passing; `git diff --check`
   exits 0. The suite command is not yet meaningful, because no
   `test/fizz/` path exists at this step.

**Files.** Create `docs/Emitter Fidelity Study.md` and
`docs/Emitter Fidelity Runbook.md`. Change `docs/README.md` only to add their
index lines. Rewrite `.horos/boundary.json` only through the Horos scanner.
No Solidity, no configuration, no dependency.

**Tests.** None written; the two receipted artefacts are copied without
rewriting. The Elenchus runner contract above applies to any repair, with the
report file `.hexaemeron/test-reports/step-1.json`.

**Disciplines.** phylax: none, the step adds static Markdown and opens no
input or execution boundary. ephoros: none, nothing here runs unattended.
metron: none, no performance claim is made. elenchus: a byte-identity,
structural or suite regression stops the step and any repair uses the runner
above. hypomnema: the tracked study and runbook are the durable homes the
accepted proposition selected, and `docs/README.md` is where this repository
makes a document findable.

## Step 2: Build the differential harness

**Goal.** A harness that records one log from an assembly emitter and one from
a high-level `emit` of the same declared event, and compares them field by
field, with the expectation derived from the declaration rather than from the
assembly.

**Entry.** Step 1's committed head. No `test/fizz/` directory exists. The 27
emitters are free functions in `src/libraries/MarketEvents.sol` and
`src/spherex/SphereXProtectedEvents.sol`; their declarations are in
`src/interfaces/IMarketEventsAndErrors.sol` and `src/spherex/SphereXConfig.sol`.

**Exit.** The following all hold on the committed head:

1. A reference contract under `test/fizz/` emits each event through high-level
   `emit`, and it obtains the event declarations by importing the declaring
   interface rather than redeclaring them, so a declaration change cannot pass
   unnoticed (study risk `reference-declaration-source`).
2. External wrappers under `test/fizz/wrappers/` expose the emitter free
   functions to a test, following the wrapper convention `TESTS.md` states for
   libraries.
3. A comparator collects both logs through `vm.recordLogs`, asserts exactly
   two entries, pairs them by position rather than by topic0, and reports five
   fields separately: topic0, topic count, indexed topic 1, indexed topic 2,
   and the data region. The topic array is compared on length first and then
   element by element, with no hard-coded arity ceiling, because the release
   branch already emits with `log4` (study risks `recordlogs-pairing`,
   `log4-arity-ceiling`, `data-region-length`).
4. Nothing in `test/fizz/` transcribes a topic0 constant, topic count, indexed
   position or data offset out of the two emitter files, checkable by reading
   the diff and by `grep` for those constants (study risk
   `oracle-derived-from-assembly`).
5. Two memory guards hold across an emitter call: the free memory pointer at
   `0x40` is read before and after and is unchanged, and a deliberately
   dirtied scratch space at `0x00` to `0x5f` does not change the recorded data
   (study risks `free-pointer-clobber`, `scratch-space-reuse`).
6. At least one emitter is wired end to end and passes, so the harness is
   demonstrated rather than asserted.
7. `forge test --match-path 'test/fizz/*.t.sol'` exits 0;
   `forge test --block-timestamp $(date +%s)` reports the two pre-existing
   failures and no others, with at least 795 passing; `yarn lint:check`
   reports no finding on the new files; the Horos boundary check reports a
   match; `git diff --check` exits 0.

**Files.** Create `test/fizz/` with the reference contract, the comparator and
`test/fizz/wrappers/`. Rewrite `.horos/boundary.json` only through the Horos
scanner. No change to `src/`, to `foundry.toml`, or to any existing test.

**Tests.** The harness is itself test code. Expect one `.t.sol` carrying the
comparator and the first wired emitter, plus the two memory guards. The
Elenchus runner contract above applies, with the report file
`.hexaemeron/test-reports/step-2.json`.

**Disciplines.** phylax: the suite must issue no `vm.ffi` call even though
`foundry.toml` sets `ffi = true`, checkable by `grep` over `test/fizz` (study
risk `ffi-enabled`). ephoros: the comparator reports which of the five fields
diverged, because a single boolean failure would not say what changed.
metron: none, no performance claim is made and the suite's own runtime is not
a budget this step declares. elenchus: each memory guard begins as a failing
case before the guard exists. hypomnema: none, the harness records no decision
the study has not already fixed.

## Step 3: Cover all twenty-seven emitters

**Goal.** Every emitter has a fuzz case, and the suite fails rather than
passes quietly when an emitter has no case.

**Entry.** Step 2's committed head, with the harness proved on at least one
emitter.

**Exit.** The following all hold on the committed head:

1. All 27 emitters have a case, each fuzzed across the domain its own
   parameter types bound, with any widening to the declared type made explicit
   where the two differ (study risk `narrowed-fuzz-domain`).
2. Cases are named `test_emit_<EventName>_<PascalCaseLabel>`, following the
   naming rule `TESTS.md` states.
3. Every emitter resolves to exactly one declaration by the `emit_<EventName>`
   convention, and the suite asserts that the number of pairs it covers equals
   the number of `emit_` free functions in the two emitter files, so a new
   emitter with no case fails the suite (study risks `pairing-by-name`,
   `unpaired-emitter`).
4. `python3 .hexaemeron/measure_design.py --table` reports empty
   `topic0_mismatches`, `indexed_mismatches`, `data_word_mismatches` and
   `unpaired` lists.
5. `forge test --match-path 'test/fizz/*.t.sol'` exits 0 and reports 27 cases;
   `forge test --block-timestamp $(date +%s)` reports the two pre-existing
   failures and no others, with at least 795 passing; `yarn lint:check`
   reports no finding on the new files; the Horos boundary check reports a
   match; `git diff --check` exits 0.

**Files.** Add case files under `test/fizz/`, and extend the wrappers under
`test/fizz/wrappers/` where an emitter needs one. No change to `src/` and no
change to the comparator's contract beyond what a new case requires. Rewrite
`.horos/boundary.json` only through the Horos scanner.

**Tests.** Twenty-seven fuzz cases, one per emitter, plus the pairing-count
assertion. The Elenchus runner contract above applies, with the report file
`.hexaemeron/test-reports/step-3.json`.

**Disciplines.** phylax: none new, the cases reuse step 2's harness and add no
boundary. ephoros: a failing case names the emitter and the field that
diverged. metron: none, no performance change is made. elenchus: a divergence
found here is a counterexample, and it is preserved as a specimen test that
fails without the fix rather than being repaired silently. hypomnema: none.

## Step 4: Run the campaign and record it

**Goal.** A recorded campaign that a stranger can rerun: engine, seed, run
length, commit and emitter count, with any counterexample filed as a specimen.

**Entry.** Step 3's committed head, with all 27 cases passing.

**Exit.** The following all hold on the committed head:

1. `forge test --match-path 'test/fizz/*.t.sol' --fuzz-seed <seed> -vv` exits
   0, which is the demo path the study's problem statement names.
2. `fizz_data/emitter-fidelity-campaign.json` records the engine, the seed,
   the run length, the commit and the emitter count, and every value is read
   back from the run that produced it rather than written by hand (study risk
   `campaign-record-provenance`).
3. The Fizz `PROPERTIES.md` entries for this suite exist and describe what
   each property asserts, following the form the Fizz skill states.
4. Either the campaign found no counterexample, or each counterexample is a
   committed specimen under `test/fizz/specimens/` that fails without its fix.
5. `forge test --block-timestamp $(date +%s)` reports the two pre-existing
   failures and no others, with at least 795 passing; `yarn lint:check`
   reports no finding on the new files; the Horos boundary check reports a
   match; `git diff --check` exits 0.

**Files.** Create `fizz_data/emitter-fidelity-campaign.json` and the Fizz
`PROPERTIES.md`. Add `test/fizz/specimens/` only if the campaign produces a
counterexample. Rewrite `.horos/boundary.json` only through the Horos scanner.
No change to `src/`.

**Tests.** No new case beyond a specimen the campaign forces. The Elenchus
runner contract above applies, with the report file
`.hexaemeron/test-reports/step-4.json`.

**Disciplines.** phylax: none, the campaign runs the suite already reviewed.
ephoros: the campaign record is the artefact that answers what ran, against
which commit, and with what seed, months after the run. metron: the run length
is recorded as evidence of how much of the domain was explored, not as a
performance claim. elenchus: a counterexample stops the step and becomes a
guarded specimen. hypomnema: the campaign record is the durable home for the
run's own provenance, and the pull request states what Hermes may cite it for.

### Amendment -- 2026-09-07

**What changed.** Complete replacement Exit: The following all hold on the committed head. First, all 27 emitters have a case, each fuzzed across the domain its own parameter types bound, with any widening to the declared type made explicit where the two differ (study risk `narrowed-fuzz-domain`). Second, cases are named `test_emit_<EventName>_<PascalCaseLabel>`, following the naming rule `TESTS.md` states. Third, every emitter resolves to exactly one declaration by the `emit_<EventName>` convention, and the suite asserts that the number of pairs it covers equals the number of `emit_` free functions in the two emitter files, so a new emitter with no case fails the suite (study risks `pairing-by-name`, `unpaired-emitter`). Fourth, that pairing assertion is tracked test code and is the whole of the reproducible evidence for the study's third success criterion, so a reader who checks the branch out can run it; no exit rests on a script under `.hexaemeron/`, because that directory is ignored in its entirety and ships with no delivered branch. Fifth, `forge test --match-path 'test/fizz/*.t.sol'` exits 0 and reports 27 cases; `forge test --block-timestamp $(date +%s)` reports the two pre-existing failures and no others, with at least 795 passing; `yarn lint:check` reports no finding on the new files; the Horos boundary check reports a match; `git diff --check` exits 0.
**Why.** Step 1 round 1 recorded S1-R1-03: the old fourth clause required `python3 .hexaemeron/measure_design.py --table`, and `.hexaemeron/.gitignore` ignores everything, so that script is in no delivered branch and `git ls-files .hexaemeron` is empty. An exit nobody but the operator can reproduce is not an exit. The check it performed is the same agreement the suite's own pairing assertion makes, and that assertion is tracked, so the clause now rests on the tracked evidence and says why. The study was amended the same day for the same finding.
**Steps touched.** Step 3's Exit field only.
**Still holding.** Step 1: entry holds; exit holds. Step 2: entry holds; exit holds. Step 3: entry holds; exit holds. Step 4: entry holds; exit holds.
