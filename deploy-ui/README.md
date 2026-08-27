# Deployment ceremony UI

Disposable static UI for executing a deployment plan with a testnet EOA or
proposing/signing/executing prebuilt Safe bundles. It has no backend and never
accepts editable calldata.

## Run locally or on a fork

Release acceptance uses the reviewed release package and operator runbook. The
durable artifact and verification model is documented in
[`../docs/operations/deployment.md`](../docs/operations/deployment.md). The file
loader below is retained for development and debugging only.

```bash
cd deploy-ui
npm ci
npm run dev
```

Start a pinned target-chain fork separately:

```bash
anvil --fork-url "$SEPOLIA_RPC_URL" --host 127.0.0.1 --port 8545
# or, for Safe rehearsal:
anvil --fork-url "$MAINNET_RPC_URL" --host 127.0.0.1 --port 8545
```

Add `http://127.0.0.1:8545` as chain `31337` in the browser wallet. The headless
acceptance tests use the mini-plan dev key and deploy a fresh canonical Safe
1.4.1 proxy on the respective forks:

```bash
npm test
npm run test:fork
```

## Release package and modes

Production builds embed one `ceremony-<release>-<mode>.json` file. The package
contains the exact plan bytes and, for Safe mode, all manifests and expected
addresses. The browser recomputes every artifact hash and the package digest,
locks the mode, and displays a short call-time fingerprint. There is no file
picker or mode switch in an embedded build.

EOA mode sends one plan transaction at a time, persists progress by exact
plan-file hash, re-verifies completed predicates on resume, and halts on any
failure. The first Sepolia deployment uses three separately locked authority
packages before activation. The replacement helper remains ArchController owner
throughout the activation plan, so activation has no reclaim or compensating
ownership-return card. Plan schema 1.1 records the mandatory `deploy` Foundry
profile and exact ABI constructor types; the browser does not infer ABI types
from JSON values.

Safe mode also loads every `bundle-N.manifest.json` plus
`expected-addresses.json`. Before wallet interaction, it independently rebuilds
every constructor/call payload, CREATE2 address, CreateCall operation, and
MultiSend transaction from the plan and rejects any manifest mismatch. Protocol
Kit receives the rebuilt `DELEGATECALL (1)` transaction, never untrusted manifest
calldata or the Transaction Builder import row. Every bundle pins its Safe nonce
and full EIP-712 Safe transaction hash. On supported public chains, API Kit
proposes and polls signatures while thresholds and confirming owners are checked
against the Safe itself. On chain `31337`, or with
`VITE_SAFE_LOCAL_ONLY=true`, a 1-of-1 Safe signs EIP-712 and calls
`execTransaction` directly. A service failure can fall back only when the
on-chain threshold is exactly one; a production multi-owner Safe halts.

Without `CEREMONY_PACKAGE`, local development retains the file/URL loaders and
mode switch for debugging. Optional build-time defaults are `VITE_MAINNET_RPC_URL`,
`VITE_SEPOLIA_RPC_URL`, `VITE_ANVIL_RPC_URL`, `VITE_SAFE_TX_SERVICE_URL`, and
`VITE_SAFE_API_KEY`. Files can also be loaded from static, CORS-enabled URLs:

```text
/?plan=<url>&manifest=<url>&manifest=<url>&expectedAddresses=<url>
```

## Build the release-specific site

Run these examples from the `v2-protocol` root so plan/package paths have one
unambiguous base:

```bash
export FOUNDRY_PROFILE=deploy
export REPO_ROOT="$(pwd -P)"

# EOA / Sepolia
export PLAN="$REPO_ROOT/deployments/sepolia/plan-v2-5.json"
export PACKAGE="$REPO_ROOT/deployments/sepolia/ceremony-v2-5-eoa.json"
node scripts/plan.js ceremony-package --plan "$PLAN" --mode eoa --out "$PACKAGE"
(cd deploy-ui && CEREMONY_PACKAGE="$PACKAGE" npm run build)

# Safe / mainnet, after bundle-simulate has rewritten the manifests
export PLAN="$REPO_ROOT/deployments/mainnet/plan-v2-5.json"
export PACKAGE="$REPO_ROOT/deployments/mainnet/ceremony-v2-5-safe.json"
node scripts/plan.js ceremony-package \
  --plan "$PLAN" \
  --mode safe \
  --bundles "$REPO_ROOT/deployments/mainnet/bundles-v2-5" \
  --out "$PACKAGE"
(cd deploy-ui && CEREMONY_PACKAGE="$PACKAGE" npm run build)
```

Serve or upload `deploy-ui/dist/` as ordinary static files. Relative asset URLs
allow hosting at any path. Publish the full ceremony digest and short fingerprint
through the release's independent review channel. After all predicates are
green, export `run-state-<release>.json` unchanged. The UI names the next
staging command for the three Anvil authority packages and activation. A normal
release activation passes its run-state to step 08:

```bash
export RUN_STATE=/path/to/run-state-v2-5.json
bash script/deploy/v2-5/08-finalize-inventory.sh
```
