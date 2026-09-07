# Emitter-fidelity differential suite

Assuming, unless corrected:

1. Foundry, not Hardhat. `foundry.toml` pins `solc = "0.8.25"`, `evm_version = 'cancun'` and `ffi = true`; `hardhat.config.ts` exists but the test tree is Foundry.
2. `forge` 1.7.1, `medusa` 1.5.1 and `echidna` 2.3.3 are on PATH, and `forge test` is the build-and-run command. `forge build` exits non-zero on this tree because forge-lint denies `unsafe-typecast` in `src/market/WildcatMarketBase.sol`; `forge test` reports the same lint as a warning and exits zero. Every step exit therefore rests on `forge test`.
3. The target is `main` at `f5a26146987926f4811b72a795d662813dedfe85`. `git diff --stat c7be4039 main` returns five files, none of them Solidity, so this tree is Solidity-identical to the `v2.1.0` production tag and a suite built here covers the deployed emitters.
4. `release/v2.5` is not in scope. Its emitter set differs from `main` and is discussed only as compatibility evidence.
5. The fuzz engine is Foundry's own stateless fuzzer with a recorded `--fuzz-seed`. The emitters are pure free functions with no storage, so a stateful campaign under Echidna or Medusa would explore no state a stateless campaign does not.
6. The suite is developer- and CI-run, not a deployed service.

I will proceed on these unless corrected.

## 1. Problem statement

Twenty-seven event emitters in this repository build their logs by hand in assembly rather than through the compiler's `emit`. Twenty-two are free functions in `src/libraries/MarketEvents.sol`; five are free functions in `src/spherex/SphereXProtectedEvents.sol`. Each one `mstore`s a data region and calls `log1`, `log2` or `log3` with a hard-coded 32-byte topic0 constant. There is no assembly `log` opcode anywhere else in `src/`.

Anything that decodes a Wildcat market's history does so against the Solidity `event` declarations in `src/interfaces/IMarketEventsAndErrors.sol` and `src/spherex/SphereXConfig.sol`. Nothing in this repository holds the assembly to those declarations. The arity and indexed count of every one of these events has so far been established by reading the assembly, and a read is not a check. A divergence that still decodes would corrupt every capture built on the declaration without producing an error anywhere.

**Who this is for.** The engineer changing an emitter, the auditor asked whether an event is topic-filterable on a given argument, and the indexer author who decodes against the declared ABI.

**What a working prototype means here.** A Foundry suite under `test/fizz/` in which every one of the 27 emitters is fuzzed across its own argument domain, and for each case the log the emitter records is compared to a log produced by emitting the same declared event through high-level `emit`. Five fields are compared and each is reported separately: topic0, the topic count, indexed topic 1, indexed topic 2, and the data region. A difference in any of them fails the test and is preserved as a specimen.

**The demo path.** From the repository root:

```
forge test --match-path 'test/fizz/*.t.sol' --fuzz-seed <seed> -vv
```

exits zero, and `fizz_data/emitter-fidelity-campaign.json` records the engine, the seed, the run length, the commit and the emitter count.

**Success criteria, each checked by a command.**

1. `forge test --match-path 'test/fizz/*.t.sol'` exits zero.
2. The suite asserts that the number of emitters it pairs equals the number of `emit_` free functions in the two emitter files; a new emitter with no case makes the suite fail rather than pass quietly.
3. `python3 .hexaemeron/measure_design.py --table` reports empty `topic0_mismatches`, `indexed_mismatches`, `data_word_mismatches` and `unpaired` lists.
4. The campaign record exists and names engine, seed, run length and commit.
5. Zero counterexamples, or each counterexample is a committed specimen test that fails without the fix.

## 2. Prior art

**In this repository.**

`test/LogTest.sol` is not prior art for this work, and the name invites the mistake. It logs natural-logarithm values through `console2.log` using `solady`'s `FixedPointMathLib.lnWad`. It has nothing to do with EVM event logs. Say so before anyone reads the filename and stops looking.

`TESTS.md` is the governing convention and it already anticipates half of this problem. It requires `test/<subdir>/<FileName>.t.sol` mirroring `src/<subdir>/<FileName>.sol`, and test names of the form `test_<functionName>_<PascalCaseLabel>` with the event name as the label when a specific event is under test. It also states the reason this suite needs a wrapper at all: `expectEmit` and `expectRevert` act on the next message call, not the current call context, so a library or free function that emits must be invoked externally to be tested. `test/libraries/wrappers/` holds seven such wrappers (`FeeMathExternal.sol`, `MathUtilsExternal.sol` and five others). This suite follows that pattern.

`test/spherex/SphereXConfig.t.sol` is the closest thing to prior art in the tree and it is worth being exact about. It names all five SphereX events and holds nine `vm.expectEmit` assertions against them, so the `expect-emit` candidate in item 4 is already in use here for 5 of the 27 emitters. What it does not do is fuzz: each assertion fixes the argument values the test chose, so it establishes that those particular values round-trip and nothing about the rest of the domain. It also inherits the limitation the candidate is rejected for, which is that a mismatch surfaces as one cheatcode revert rather than a named field. Nothing anywhere in `test/` compares a recorded log to its declaration across an argument domain.

`src/interfaces/IMarketEventsAndErrors.sol` declares 23 events and `src/spherex/SphereXConfig.sol` declares 5. `AccountSanctioned` is declared and has no assembly emitter and no `emit` anywhere in `src/`; it is a dead declaration on this branch.

**The last two merged pull requests that changed the subject.** Filtering merge commits on `main` by whether they touched either emitter file gives pull request 93 and pull request 62 as the two most recent.

Pull request 93, "Merge changes from mainnet deployment", merged 2026-03-16 into `main`. It is the branch deployed to Ethereum mainnet. It removed `forceBuyBack` and its `ForceBuyBack` event, added `pushProviderIndex` to three `RoleProvider` events, renamed the two hooks contracts, fixed a bit shift in `HooksConfig.setHooksAddress`, and reduced `optimizer_runs` to 50,000. Its body records nothing unfinished. Nothing in it is carried forward here beyond the fact that it is the deployed shape.

Pull request 62, "Introduce force buyback feature", merged 2024-10-12 into `main`. It added the emitter that pull request 93 later removed. Nothing carried forward.

Two earlier pull requests are closer to the subject than either of those and are worth naming. Pull request 35, "Review Finding Mitigation: emit_SanctionedAccountAssetsQueuedForWithdrawal corrupts free pointer", records a Violet security-review finding that the emitter wrote over the free memory pointer at `0x40` and did not restore it, and its mitigation cached and restored the pointer. That mitigation is visible in `src/libraries/MarketEvents.sol` today in three emitters. Pull request 36 carried the rest of the Violet findings. Neither pull request left an executable check behind, which is precisely the gap this study addresses: the fix is in the source and nothing re-proves it. `free-pointer-clobber` in the risk register below carries it forward as a check.

**Audit records.** There are none in this target. `find . -type d -name audit` outside `lib/` returns nothing, `git ls-files` matches no `audit/AUDIT.md`, no `AUDIT_SYNOPSIS.md` and no `audit/rounds/`, and `.hexaemeron/` contains only this run's `state.json`, `ledger.jsonl` and lock. There is therefore no in-scope audit source and no synopsis to check for currency; the `audit_synopsis.py --check` step has nothing to run against and was not run. No finding id, status, `Covered`, `Not checked`, `Elenchus verdict` or `Leads not pursued` field exists to carry forward. The Violet findings named above reach this study through pull request bodies, not through an audit record, and are recorded as such.

**Outside this repository.** `forge-std`'s `Vm.Log` struct (`bytes32[] topics`, `bytes data`, `address emitter`) and the `vm.recordLogs` and `vm.getRecordedLogs` cheatcodes are the recording surface. `vm.expectEmit` is the alternative oracle and is evaluated as a candidate in item 4. The ABI event encoding this suite checks is the one in the Solidity ABI specification: topic0 is the keccak-256 of the canonical signature, each `indexed` value-typed argument becomes one topic in declaration order, and the non-indexed arguments are ABI-encoded into the data region.

**Hermes rule CMP-10.** The rule is `require semantic equivalence testing`, priority P0, `verified_on` compiler 0.8.25 and evm cancun, which matches this repository's pins exactly. It carries two obligations, quoted from the corpus: "optimization validation must cover outputs, storage, logs, reverts, calls, value movement, and protocol invariants", and "assembly and decoder rewrites should retain an executable reference implementation wherever possible".

One suite serves both members only in part, and the honest statement is worth making rather than repeating the claim. This suite discharges the second obligation in full for these 27 emitters: it is an executable reference implementation of every assembly emitter, and Hermes can cite it. It touches the first obligation on one of the seven named surfaces, `logs`, and leaves outputs, storage, reverts, calls, value movement and protocol invariants untouched. CMP-10 also scopes itself to validating an optimization; nothing here is being optimized, so what the suite gives Hermes is a standing reference it can cite when it later proposes or attests an emitter change, not a discharge of CMP-10 for any particular rewrite. Hermes accepting the suite as its CMP-10 reference is a statement about the second obligation.

**Fizz.** The skill's default pipeline builds a stateful campaign: handlers, actors, ghost variables, snapshots and invariants, run under Echidna or Medusa. Most of that does not apply to 27 pure free functions with no storage. What does apply, and what this suite adopts, is the layout (`test/fizz/` for the suite, `fizz_data/` for metadata and the campaign record), the `PROPERTIES.md` spec with stable Spec IDs and a `SHOULD-HOLD` or `EXPLORATORY` guarantee tag per property, the Foundry validation command, and the rule that a counterexample becomes a deterministic replay test rather than a log line.

## 3. Constraints and non-goals

**Starting ref.** `main` at `f5a26146987926f4811b72a795d662813dedfe85`, run branch `fiat/fizz-4-emitter-fidelity-differential-suite`.

**Toolchain pins.** `solc 0.8.25`, `evm_version cancun`, `forge 1.7.1`, `medusa 1.5.1`, `echidna 2.3.3`, `node 26.6.0`, `python3 3.14.6`. `foundry.toml` sets `ffi = true`, `bytecode_hash = 'none'` and `[profile.default.fuzz] runs = 1000`, and declares remappings for forge-std, ds-test, solmate, solady, sol-utils, openzeppelin and ethereum-access-token.

**`forge build` cannot be an exit command.** On forge 1.7.1 it fails this tree with `Error: Lint failed` on an `unsafe-typecast` in `src/market/WildcatMarketBase.sol:45`. There is no `--no-lint` flag on this version. Suppressing it would mean editing `foundry.toml`, which is an ask-first change and is not proposed. `forge test` compiles the same tree, prints the lint as a warning and exits zero, so exits use `forge test`.

**Suite location.** The kickoff issue names `test/fizz/` and Fizz's `SUITE_DIR` default agrees. `TESTS.md` would put a test for `src/libraries/MarketEvents.sol` at `test/libraries/MarketEvents.t.sol`. The reading chosen: `test/fizz/` wins for the differential suite because both the issue and the skill name it, and `TESTS.md`'s other conventions are honoured inside it. Test functions are named `test_emit_<EventName>_<PascalCaseLabel>`, and the emitters are reached through an external wrapper in `test/fizz/wrappers/`, following the seven wrappers already in `test/libraries/wrappers/` and the reason `TESTS.md` gives for them. Recorded here rather than resolved silently.

**No task issue.** This run records none. The kickoff issue lives in `wildcat-finance/skills` and the work lands in `wildcat-finance/v2-protocol`, and the controller refuses a task issue in another repository. The issue is closed by hand after the merge; no closing keyword goes in a commit or pull request body.

**Non-goals.**

- `release/v2.5` compatibility. That branch has 29 emitters, uses `log4`, renames two events and adds one emitter with no declaration. The suite is expected to extend to it because its oracle re-derives from declarations, and item 4 measures that, but porting it is not in this delivery.
- Stateful fuzzing, handler generation, ghost variables, and the discovery of properties over stored state. The emitters hold no state.
- Any change to `src/`. The suite is added; no emitter and no declaration is edited. If a counterexample proves an emitter wrong, the specimen is filed and the fix is a separate decision.
- Gas measurement. Hermes owns that and no gas claim is made here.
- Events emitted through high-level `emit` elsewhere in `src/`. Only the 27 assembly emitters are in scope.

**Where the study and runbook live.** This repository has no convention for them. `docs/` is a flat set of prose documents with spaces in their filenames (`Core Behavior.md`, `Known Issues.md`, `Scale Factor.md`, `Terminology.md`), one subdirectory `docs/hooks/`, and an index at `docs/README.md` that links each one. There is no decision-record directory and no numbered-record scheme anywhere in the tree. The proposal is to follow what is there: `docs/Emitter Fidelity Study.md` and `docs/Emitter Fidelity Runbook.md`, each added as a line in `docs/README.md`. Commands naming them must quote the path because of the spaces. Introducing a numbered decision-record scheme where none exists is an ask-first change and is not proposed.

### Boundaries

**Always.** Run `forge test --match-path 'test/fizz/*.t.sol'` before any commit on this branch, and the repository's own suite before the final step's push. Run the imprimatur lint on the study and the runbook at their published `docs/` paths. Record the seed and run length of any campaign whose result is reported.

**Ask first.** Editing `foundry.toml`, including any lint suppression or new profile. Adding a dependency to `lib/`. Changing any file under `src/`. Introducing a numbered decision-record scheme. Touching `.github/`.

**Never.** Commit a key or an RPC credential. Edit anything under `lib/`. Delete or skip a failing case to make the suite green. Report a campaign that did not run, or a seed that was not the one used. Derive an expected topic, arity or data offset from the assembly.

## 4. Design options

The question is where the expected log comes from and how the two logs are compared. The trap the whole exercise exists to avoid is an oracle that derives its expectation from the assembly, because such an oracle agrees with the assembly by construction and cannot see the divergence.

**mirror-emit.** A reference contract imports `IMarketEventsAndErrors` and `SphereXConfig`'s declarations and emits each event with high-level `emit`. The harness calls the assembly emitter through an external wrapper and then the reference, both inside one `vm.recordLogs` window, asserts exactly two entries, and compares them field by field. The compiler produces the reference log from the declaration, so the expectation is declaration-derived. The trade: it needs one reference function per event, and the emitter-to-event pairing is by name.

**expect-emit.** The test writes the expected event as a high-level `emit` and lets `vm.expectEmit` compare it against the emitter's log. Also declaration-derived, and shorter. The trade: the cheatcode collapses the whole comparison into one revert, so a failure says the log did not match and not which field diverged. `TESTS.md` also records that `expectEmit` acts on the next message call, so the wrapper is needed either way and the saving is smaller than it looks.

**abi-reconstruct.** The harness rebuilds topic0 with `keccak256`, splits arguments into indexed and non-indexed by a table written into the suite, and `abi.encode`s the data. The trade: the signature strings and the indexed split are transcribed by hand, which is the read the issue exists to replace, and a transcription taken from the assembly cannot catch an arity divergence at all.

**artifact-oracle.** The expectation is read from the compiler's ABI artifact for the declaring interface. Declaration-derived, with nothing transcribed. The trade: a clean checkout has no `out/`, so the derivation includes a full `forge build`.

The prose above explains the candidates. The selection is made by `.hexaemeron/design-evidence.json` under `protasis-design-evidence/v1`, from five criteria whose every value `.hexaemeron/measure_design.py` computes from the real tree. Nothing in the matrix is transcribed from this prose, and the reverse is also true.

The five criteria and what each measures:

- `assembly-independent-oracle` (correctness, gate, at least 27). How many of the 27 emitters the candidate checks against an expectation that a mutation of the assembly text does not move. An assembly-derived oracle scores zero.
- `release-branch-survival` (compatibility, gate, at least 28). How many of the 29 emitters on `release/v2.5` at `bea503c2736d47de7fd34130c64f10783dc35b39` the candidate's rule resolves with no hand edit. The script reads that branch's blobs out of git.
- `failure-field-resolution` (recovery, gate, at least 5). How many log fields the candidate's failure surface reports separately. The threshold is derived from the tree: the maximum indexed count across the 27 emitters is 2, so the comparable fields are topic0, the topic count, two indexed topics and the data region.
- `transcribed-oracle-bytes` (space, metric, minimise). Bytes of expectation data a person must hand-write into the suite.
- `oracle-derivation-ms` (time, metric, minimise). Measured wall-clock to derive the full expectation set once, cold.

The measured matrix:

| candidate | independent | survival | fields | bytes | ms |
| --- | --- | --- | --- | --- | --- |
| mirror-emit | 27 | 28 | 5 | 0 | 21 |
| expect-emit | 27 | 28 | 1 | 0 | 21 |
| abi-reconstruct | 0 | 19 | 5 | 1135 | 21 |
| artifact-oracle | 27 | 28 | 5 | 0 | 17841 |

`abi-reconstruct` fails two gates, `expect-emit` fails the recovery gate, and `mirror-emit` and `artifact-oracle` survive. On the two metrics they tie at zero transcribed bytes and `mirror-emit` is three orders of magnitude cheaper to derive, so it dominates and the frontier has one member. The record's rule is `unique-frontier` and the selected candidate is `mirror-emit`. The three source-parsing candidates share one derivation measurement because they derive their expectation by the same walk of the same two files; timing them apart would report scheduler jitter as a design difference.

No criterion is left pending. The only evidence not yet in hand is the campaign result itself, and that is the last runbook step's exit command rather than a conformance cell, because a conformance cell would demand the same campaign under three rejected candidates.

**What the measurement already establishes, and what it does not.** Running `python3 .hexaemeron/measure_design.py --table` against `main` gives: 27 emitters, 27 paired to a declaration by stripping the `emit_` prefix, zero unpaired; all 27 hard-coded topic0 constants equal the keccak-256 of the declared canonical signature; all 27 `logN` arities equal the declared indexed count plus one; all 27 data-region sizes equal the declared non-indexed argument count in words. One divergence exists and is not a log divergence: `emit_SanctionedAccountAssetsQueuedForWithdrawal` takes `uint32 expiry` while `SanctionedAccountAssetsQueuedForWithdrawal` declares `uint256 expiry`. The recorded bytes agree, because `mstore` zero-extends, but the emitter's Solidity signature narrows what a caller may pass. That result is a static derivation, which is a stronger read than the one the issue objects to but is still a read: it settles topic0, arity and word count and says nothing about whether the runtime bytes in the data region are the right values in the right order. The suite is what settles that, and it is why the static agreement above does not make the suite redundant.

## 5. Risk register seed

The concerns below are what the audit loop should look hardest at. Two of them, `free-pointer-clobber` and `scratch-space-reuse`, exist because the emitters write into memory the rest of the program owns: three of them borrow the free-pointer slot at `0x40` and restore it, one writes 192 bytes past the free pointer without advancing it, and the rest use scratch space at `0x00` to `0x3f`. `log4-arity-ceiling` exists because `release/v2.5` already emits with `log4`, so anything that assumes a ceiling of three topics is wrong the moment the suite moves.

```risk-register
oracle-derived-from-assembly | how each expected log is produced | no expected topic0, topic count, indexed position or data offset is read from or transcribed out of the two emitter files
reference-declaration-source | the reference contract's event declarations | the reference imports the declaring interface rather than redeclaring the events, so a declaration change cannot pass unnoticed
pairing-by-name | the emit_<EventName> to declaration mapping | every emitter resolves to exactly one declaration and the paired count equals the count of emit_ free functions in the two files
unpaired-emitter | an emitter that resolves to no declaration | the suite fails rather than skipping, and a new emitter with no case makes it fail
narrowed-fuzz-domain | the argument domain each case explores | the emitter's own parameter types bound the domain, and the widening to the declared type is explicit where the two differ
free-pointer-clobber | memory at 0x40 across an emitter call | the free memory pointer is read before and after and is unchanged
scratch-space-reuse | memory 0x00 to 0x5f before an emitter call | a dirtied scratch space before the call does not change the recorded data
recordlogs-pairing | the two Vm.Log entries the harness compares | the harness asserts exactly two entries and pairs them by position, not by topic0, so a wrong topic0 cannot pair with itself
log4-arity-ceiling | the comparison's topic array handling | topic arrays compare on length first and then element by element, with no hard-coded ceiling
data-region-length | the data byte string of each recorded log | length is compared before content, so a short or long region fails on length rather than on a truncated comparison
campaign-record-provenance | the engine, seed, run length and commit in the campaign record | each value is read back from the run that produced it, not written by hand
ffi-enabled | foundry.toml ffi = true under the suite's profile | the suite issues no vm.ffi call, checkable by grep over test/fizz
```

## 6. Glossary seeds

- **Emitter.** One of the 27 `emit_<EventName>` free functions that builds a log in assembly.
- **Declaration.** The Solidity `event` statement the emitter corresponds to, in `IMarketEventsAndErrors` or `SphereXConfig`.
- **topic0.** The keccak-256 of the event's canonical signature; the first topic of a non-anonymous log.
- **Indexed topic.** A topic after topic0, carrying one `indexed` argument in declaration order.
- **Data region.** The ABI-encoded non-indexed arguments, the bytes `logN` reads from memory.
- **Arity.** The `N` in `logN`; equal to one plus the number of indexed arguments.
- **Reference emission.** The same declared event emitted through high-level `emit`, which the compiler encodes from the declaration.
- **Differential case.** One fuzz case that calls an emitter and its reference and compares the two recorded logs.
- **Specimen.** A committed replay test built from a counterexample, which fails without the fix.
- **Campaign record.** The JSON naming engine, seed, run length, commit and emitter count for a run.
- **Scratch space.** Memory `0x00` to `0x3f`, which Solidity leaves free for transient use.
- **Free memory pointer.** The word at `0x40` holding the next unallocated memory offset.

## 7. Sources

- `src/libraries/MarketEvents.sol`: 22 emitters, 9 `log1`, 9 `log2`, 4 `log3`.
- `src/spherex/SphereXProtectedEvents.sol`: 5 emitters, all `log1`.
- `src/interfaces/IMarketEventsAndErrors.sol`: 23 declarations, lines 81 to 170.
- `src/spherex/SphereXConfig.sol`: 5 declarations, lines 42 to 46.
- `TESTS.md`: naming, layout and the wrapper rationale.
- `AGENTS.md` and `.horos/boundary.json`: the reading boundary; its two entries are `deployments/` and `yarn.lock`, neither in scope here.
- `foundry.toml`: pins, remappings, `ffi = true`, fuzz runs.
- `test/LogTest.sol`: named to record that it is not prior art.
- `test/libraries/wrappers/`: seven existing external wrappers.
- `wildcat-finance/v2-protocol` pull requests 93, 62, 36 and 35.
- `release/v2.5` at `bea503c2736d47de7fd34130c64f10783dc35b39`, compatibility evidence only.
- Hermes rule `CMP-10` in the Hermes gas-rule corpus, `plugins/hermes/skills/hermes/references/gas-rule-corpus.json`.
- The Fizz skill and its `templates/` and `references/`, in the pinned Hexaemeron plugin.
- The maintainer's kickoff issue, entry 4: `https://github.com/wildcat-finance/skills/issues/1354`.
- `.hexaemeron/measure_design.py`, `.hexaemeron/design-evidence.json` and `.hexaemeron/reports/`, this study's own measurements.

## 8. Signals, and the questions behind them

Two questions, and neither is a three-in-the-morning question in the usual sense, because this suite runs in CI and in a terminal rather than unattended in production. They are still questions someone will ask of a red or green result they did not watch. The `ephoros` skill contract, at `skills/ephoros/SKILL.md` in the Hexaemeron plugin, owns what a signal must carry.

**Did the campaign actually run, and with what?** A green suite says nothing about how hard it was tried. The signal is `fizz_data/emitter-fidelity-campaign.json`, written by the final step, carrying the engine and its version, the `--fuzz-seed` used, the runs per case, the commit, the emitter count and the case count. Every value is read back from the run that produced it. The final step emits this.

**Did an emitter go unchecked?** The case that costs the most is a new emitter with no test, because the suite then passes. The signal is an assertion inside the suite that the number of paired cases equals the number of `emit_` free functions in the two emitter files, and the count is printed on every run. The step that builds the harness emits this.

## 9. Boundaries, per capability

The suite opens no new trust boundary, and that is a claim worth checking rather than asserting. The `phylax` skill contract, at `skills/phylax/SKILL.md` in the Hexaemeron plugin, owns the boundary list and the controls.

**Foundry FFI.** `foundry.toml` sets `ffi = true` at the default profile, so any test in this repository may shell out. This suite takes nothing at that boundary: its oracle is the compiler's own output, not an external process. The control is that no file under `test/fizz/` calls `vm.ffi`, `vm.readFile` or `vm.writeFile`, checkable by grep, and it is the `ffi-enabled` line in the risk register.

**Network.** `.hexaemeron/measure_design.py` runs `git fetch` once to obtain the pinned `release/v2.5` commit if it is absent. That is a study-time script and is not shipped in the suite; the ref it fetches is pinned by full SHA rather than by branch name, so a moved branch cannot change a measured number. The suite itself makes no network call and no fork request.

**Untrusted input.** The suite's only inputs are fuzzer-chosen argument values, which are the point of it, and they reach only pure functions with no storage and no external call. There is no subprocess, no filesystem write from Solidity, no credential and no dependency addition.

## 10. The budget, or its absence

There is a budget, because the suite is meant to sit in CI and 27 fuzzed cases at the repository's default of 1000 runs is 27,000 EVM executions. The `metron` skill contract, at `skills/metron/SKILL.md` in the Hexaemeron plugin, owns what a budget carries and how it is checked.

**The budget.** The full suite finishes inside 120 seconds of wall clock at 1000 runs per case on the machine that records the baseline, measured warm, with `out/` already built.

**The command that measures it.**

```
time forge test --match-path 'test/fizz/*.t.sol' --fuzz-runs 1000 --fuzz-seed <seed>
```

The baseline is recorded before the budget is claimed to hold, and the same command with the same seed and run count re-measures it. If it does not hold, the lever is the run count per case, recorded in the campaign record, not a narrower argument domain.

## 11. The fail-closed posture

The `elenchus` skill contract, at `skills/elenchus/SKILL.md` in the Hexaemeron plugin, owns the triage order and the guard rule.

**What stops the run.** Any difference in any of the five compared fields fails the case. A recorded-log count other than two fails the case, because a harness that recorded one log has not compared anything. An emitter that resolves to no declaration fails the suite rather than being skipped. A paired-case count that does not equal the emitter count fails the suite. Nothing is warned about and allowed through.

**The guard convention.** A counterexample becomes a specimen: a deterministic replay test in `test/fizz/specimens/`, named `test_emit_<EventName>_Specimen<N>` per `TESTS.md`, hard-coding the failing arguments, with the shrunk values and the seed that found them in a comment above it. The specimen fails without the fix and passes with it. Specimens are committed even when the underlying emitter is not changed in this delivery, so a deferred fix stays visible.

**The runner contract.** The exact command a step's audit uses when it claims a fix:

```
forge test --match-path 'test/fizz/*.t.sol' --json > {report}
```

The report format is Foundry's JSON test output and the report file is `{report}`.

## 12. Decisions and their homes

The `hypomnema` skill contract, at `skills/hypomnema/SKILL.md` in the Hexaemeron plugin, owns which decisions earn a record and where each one lives. Its first rule is to match what is already there, and what is there is a flat `docs/` directory of prose files with spaces in their names, indexed by `docs/README.md`, with no numbered decision records anywhere in the tree.

Three decisions are expensive to reverse.

**The oracle is declaration-derived.** Reversing this means rewriting every case, and worse, a suite that has been green for a year under a transcribed oracle has been proving nothing. Home: `docs/Emitter Fidelity Oracle.md`, linked from `docs/README.md`, carrying the status, the context, the decision, the three rejected candidates with the gate each failed, and the consequence that any new emitter must be paired by name or the suite fails.

**The suite lives under `test/fizz/` rather than the path `TESTS.md` implies.** Reversing it moves every file and every specimen path. Recorded in the same document as a section, because it is a consequence of the first decision rather than an independent one.

**The study and the runbook live in `docs/` as ordinary prose files.** Reversing it breaks the links added to `docs/README.md`. Recorded as a line in `docs/README.md` itself, which is where this repository already says where its documents are, rather than in a new record. Introducing a numbered decision-record scheme to hold it would be the larger and less reversible change, so it is not proposed.
