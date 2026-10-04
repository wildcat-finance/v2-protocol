# Sepolia v2.5.6 activation

This packet prepares a `v2.5.6` hook-template update on Sepolia (`11155111`).
It carries the repayment-date parameter freeze into fresh hook templates.
Follow the [ceremony checklist](../../script/deploy/CEREMONY_CHECKLIST.md) for
the real-wallet fork rehearsal, live activation, and receipt-backed finalization.

## Scope

The plan contains 15 cards: three deployments and twelve calls.

| Action | Count |
| --- | ---: |
| Open, fixed, and periodic hook template stores | 3 |
| Register each new template on both current factories | 6 |
| Disable each v2.5.5 template on both current factories | 6 |

The existing v2.5.5 factories, market stores, wrapper, AccessList provider
factory, and lenses are reused because their deployment bytecode is unchanged.
The shared borrower identity registry and V1 wrapper fallback are also retained.
All six registrations complete before any old template is disabled.

The app at `bde1e83b` selects the first enabled template of the requested kind
on its configured factory. Leaving old templates enabled could select the old
implementation. Disabling the six old registrations makes the new templates
the only enabled choices once indexed state has caught up. Disabling cannot be
undone. It blocks new hook instances, but existing instances can still deploy
markets directly on-chain; existing markets keep their deployed behavior.

Authority and SphereX roles remain fixed. Factory registrations and indexing
policy are unchanged, including the four excluded test generations. Broader
factory deregistration is a separate ceremony.

The hook changes freeze maximum supply, minimum deposit, fixed-term maturity,
and new APR-reduction proposals at the repayment date. APR and reserve-ratio
freezes already existed. The three concrete hook templates now require the
maximum-supply callback so borrowers cannot omit that guard at market creation.
These changes apply to newly deployed hooks; existing immutable markets retain
their deployed behavior.

## Source and deployment baseline

- Configuration: [`v2.5.6.json`](../../deployments/sepolia/v2.5.6.json).
- Release base and inventory baseline:
  `01144a3ec7cff853aca0721212a0d105ff6de624` on `release/v2.5`.
- Contract source: `fe431bbdfc157b8778ac3690772c6556c74a0a9d`.
- Compiler: frozen `deploy` profile; full settings and submodule pins are in
  [`source-v2.5.6.txt`](../../deployments/sepolia/source-v2.5.6.txt).
- Executor and fee recipient: `0xCa7007a75296b532Ce1606d9e130eAa849800Ca7`.
- Template fees: 500 protocol-fee bips, no origination fee.

Executor and fees carry forward the operator's 2026-10-02 confirmation. The
source commit carries the reviewed freeze commit
`05dc81bb01ff87573736cc6a74d93d795d623dcb` onto the merged release base; `src/`,
`test/`, `lib/`, and `foundry.toml` match that tested revision exactly.

The baseline includes the receipt-backed [v2.5.5 handoff](../../deployments/sepolia/handoff-v2.5.5.json)
and original [deployment evidence](../../deployments/sepolia/ceremony-evidence/wildcat-v2.5.5-evidence-20261002T202805Z.zip).
The `existing` addresses in the new configuration are that generation's
canonical factories and wrapper. Validation compares every reused deployment's
creation bytecode with its pinned plan and checks its address against the
receipt-backed handoff. Preparation preserves `deployments.json`,
`factory-inventory.json`, and historical packets. Template aliases change only
after verified live receipts are finalized; factory aliases remain unchanged.

## Prepare the packet

From the repository root:

```sh
export SEPOLIA_REPLACEMENT_CONFIG=deployments/sepolia/v2.5.6.json
node scripts/sepolia-v2-5-fix-rotation.js generate
node scripts/sepolia-v2-5-fix-rotation.js validate
node scripts/sepolia-v2-5-fix-rotation.js generate-rehearsal
```

Review `plan-v2.5.6.json`, `plan-entries-v2.5.6/`,
`inventory-pending-v2.5.6/`, `impact-v2.5.6.json`, and the generated digest in
`deployments/sepolia/`. The impact file describes deployment scope. The stage
derives and prints the package identity; use its complete digest when checking
the locked UI.

Commit and push the reviewed packet before operator gates. They require clean
tracked files and submodules, with `HEAD` matching its upstream. Untracked files
under `src/`, `lib/`, `script/`, `scripts/`, `test/`, `deploy-ui/`, or
`deployments/`, and root `.npmrc`, `npm-shrinkwrap.json`, or `package-lock.json`
also block the gate unless ignored as generated/operator artifacts. Other
untracked notes and new files under `deployments/*/ceremony-evidence/` do not
block it. Session evidence can be committed; only active-session pointers stay
ignored there. Stop generating packets once execution starts.

The release wrappers are:

```sh
bash script/deploy/v2-5/sepolia-v2.5.6-stage.sh check
FORK_RPC_URL=https://eth-sep.hinterlight.net \
  bash script/deploy/v2-5/rehearse-sepolia-v2.5.6.sh --ui
DEPLOYMENTS_NETWORK=anvil bash script/deploy/v2-5/sepolia-v2.5.6-stage.sh activation
```

Use the checklist for the complete wallet, LAN, export, and acceptance sequence.
A headless fork check does not replace the required real-wallet rehearsal.

## Handoff and remaining work

After live receipt verification, `stage finalize-inventory` records the three
versioned template addresses, updates their unversioned aliases, and writes
`template-update-v2.5.6.json`. This update handoff contains deployment receipts,
registration and disable receipts for both factories, creation-code commitments,
and ABI paths. It references the byte-for-byte v2.5.5 handoff by SHA-256 for the
reused deployments. It neither adds factory generations nor changes factory
aliases, inventory records, or indexing flags.

After reconciliation, the stage packages the retained evidence and finalized
records into a ZIP with a SHA-256 checksum and per-file manifest. Python 3.9+
is required; no additional packages are needed. `stage archive-evidence`
can package an already-finalized live session offline, including after a
tooling-only update. It records the source commit from the original session.
See the [checklist](../../script/deploy/CEREMONY_CHECKLIST.md) for handoff and
archive recovery commands.

SDK and application creation routes must target the v2.5.5 factory addresses in
the configuration's `existing` bindings and use the new enabled templates.
The local SDK checkout at `e64e766` still selects v2.5.4 Sepolia factories,
wrapper, lens, and AccessList factory in `src/config/deployments.ts` (observed
2026-10-04). Adopt the retained v2.5.5 handoff in the SDK, subgraph configuration,
and application before opening creation flows. The deployed application's
current configuration was not established by this source review.

Confirm indexing has processed the six registrations and six disables and that
the application's selection resolves to the new templates on both factories.
Capacity, minimum-deposit, and maturity controls
also need repayment-date gating for the new hooks. The review at SDK `e64e766`
and application `bde1e83b` found those controls gated on closure instead; the
updated contracts reject changes at the repayment date. Those downstream edits
are outside this protocol packet. Market behavior testing after deployment,
unready providers, backfill decisions, and authority cleanup remain separate.

## Verification

On 2026-10-04, the fresh canonical deployment build passed with Solidity
`0.8.25` and Forge `1.8.3`. The standard market runtime is 23,978 bytes; the
revolving runtime is 24,534 bytes, retaining 42 bytes of EIP-170 headroom. Both
market creation payloads match the v2.5.5 packet. Only the three concrete hook
artifacts changed. The 15-card packet stores those artifacts, registers their
commitments, and disables the prior templates.

All 82 deployment-tooling tests passed, including checks against unapproved
factory targets, template disables, reused bytecode changes, incomplete receipts,
and conflicting handoff evidence. Inventory validation, lint, and live
reconciliation passed. Lint retains the existing allowlisted historical
deployment-key warnings.

The carried freeze revision passed all 955 protocol tests in each of the
default, fixed-seed (`0x5eed`, timestamp `1724284800`), and deployment profiles,
plus 113 focused tests. Those runs preceded the release packet; matching Git
tree identities establish the unchanged contract and test source. The ceremony's
cold gate checks deployment tooling and the UI separately.

The 15-transaction headless rehearsal passed on local Anvil pinned to Sepolia
block `11840328`. Every receipt, creation-code commitment, registration, disable,
and final binding was verified. Finalization was exercised in an isolated
directory and changed only the three versioned template keys and their three
aliases. A later read-only live preflight passed at block `11840339`.

The [preparation record](../../deployments/sepolia/preparation-v2.5.6.json)
identifies the package digest, source pins, observation scope, and checksum of
the [evidence archive](../../deployments/sepolia/ceremony-evidence/v2.5.6-preparation-evidence-20261004.zip).
That preparation archive retains original protocol-test logs, deployment checks,
both locked packages, and explicitly labelled local-fork receipts; it predates
live execution.

The [live evidence archive](../../deployments/sepolia/ceremony-evidence/wildcat-v2.5.6-evidence-20261004T081346Z.zip)
was received on 2026-10-04 in commit `71a65ff`. Its SHA-256 is
`72bbd797a6739c59e8af86ab069cb11ab86e053752c8a36b0107016009f1a0a8`.
The retained records identify ceremony source `26c5209`, the accepted real-wallet
rehearsal, all 15 verified live transactions, and green finalization at block
`11841012`. The committed template update and deployment records match the
archive bytes. This archive inspection did not repeat live RPC verification;
downstream adoption and market behavior testing remain separate work.
