# E20: adopt the qualified compiler settings

Source parent: `836304c` (E19). Status: complete.

The user authorized applying the qualified size settings to normal builds and
tests. The default profile now uses runs `1` and the exact E05 Yul sequence
without FunctionSpecializer. The normal `deploy` and `ir` profiles inherit
the same configuration. Solidity `0.8.25`, Cancun, via-IR, metadata settings,
call isolation, and dynamic test linking are unchanged. No production source
or test assertion changes are required.

The research test runner inherits the repository's compiler settings unless
an explicit override is supplied. Its standalone native-solc size companion
retains its explicit experiment defaults; archived E19 runs-44 comparisons
remain historical evidence, not the current compiler configuration.

## Plan and tracker

| Task | Scope | Status |
| --- | --- | --- |
| E20-01 | Apply the exact qualified compiler settings and document their use by normal builds, tests, and deployment verification. | Complete; effective default/deploy/IR profiles match E19. |
| E20-02 | Run the ordinary build and the required default, fixed-seed, and deployment-profile suites. Check actual runtime limits and match the qualified production artifacts. | Complete; 852 pass in each ordinary suite, both strict deployment tests pass, and all ten target artifacts match. |
| E20-03 | Record the evidence, update the current research summary, and make a signed kethcode commit without pushing. | Complete; results and reproduction commands below. |

Evidence is retained outside the repository at
`/home/kethcode/wildcat/bytecode-research/2026-09-27/e20-compiler-adoption/`.
Deployment-ceremony/fork rehearsal, gas measurements, inventory, and
audit/refreeze review remain separate release work.

## Normal-command configuration correction

The ordinary `forge build` succeeds and produces exactly the previously
qualified bytecode and ABI for all ten measured targets. The first ordinary
test invocation then stops before running tests: both lifecycle invariant
suites refer to an undefined `research` profile in an inline configuration
annotation. Research receipts had supplied that temporary profile.

Remove only the redundant `research.invariant.fail-on-revert` annotations.
The existing `default.invariant.fail-on-revert = true` annotations remain.
Six isolated control runs on the pinned Foundry version verify inheritance:
an always-reverting handler fails under default/deploy/research with the
default annotation, and passes under all three without it. Each control uses
a fresh failure-persistence directory. Thus the correction preserves strict
revert checking for both campaigns without introducing a required research
profile into ordinary builds. The initial failed invocation and control
receipts remain archived.

## Qualification

| Command | Result |
| --- | --- |
| `forge build` | Pass; 302 files compiled with the new default settings. |
| `forge test --summary` | 852 passed, zero failed or skipped, across 69 suites. |
| `npm run test:fixed -- --summary` | 852 passed, zero failed or skipped; timestamp `1724284800`, seed `0x5eed`. |
| `FOUNDRY_PROFILE=deploy forge build` | Pass; deployment artifacts match the qualified output. |
| `FOUNDRY_PROFILE=deploy forge test --summary` | 852 passed, zero failed or skipped, across 69 suites. |
| `FOUNDRY_PROFILE=deploy forge test --match-contract '^SingleStorageDeploymentTest$' --code-size-limit 24576 -vv` | Both tests pass; twelve factory/market/hook combinations deploy and execute through scheduled closure with the actual code-size limit. |
| `FOUNDRY_PROFILE=deploy forge build --sizes src` | Pass; every production runtime and creation payload fits. |

The three complete suites use the ordinary configuration, without test-name
filters or a code-size-limit override. Each includes the original invariant
group and both lifecycle campaigns at 2,000 runs and depth 30. Together they
complete 540,000 calls with zero handler reverts. The fixed package script was
invoked through npm because Yarn is not installed here; its Forge command and
arguments are exactly those in `package.json`.

The default and deployment artifacts match each other and E18/E19's independently
compiled candidate bytecode exactly for all ten measured targets, including
complete ABIs. There are no production-source changes. The only Solidity edits
remove the two redundant test-configuration annotations described above.

| Market | Runtime bytes | Runtime headroom | Compressed storage bytes |
| --- | ---: | ---: | ---: |
| Standard | 23,778 | 798 | 17,759 |
| Revolving | 24,334 | 242 | 18,254 |

Both limits remain 24,576 bytes; creation payloads also satisfy EIP-3860.
Solidity formatting, Solhint, Python syntax, and whitespace checks pass.
[results/e20.json](./results/e20.json) records settings, log hashes, artifact
hashes, controls, and command receipts. Historical E19 failures at runs 44 remain
archived; they are resolved in the current ordinary configuration.

This selects the compiler configuration for this branch. It does not perform
the target-chain deployment ceremony or replace final release/audit review.
