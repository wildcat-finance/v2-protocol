# Deployment ceremony UI

This disposable static UI executes locked deployment plans. It supports:

- Testnet execution with an EOA.
- Proposing, signing, and executing prebuilt Safe bundles.

It has no backend. It never accepts editable calldata.

## Run locally or on a fork

Release acceptance uses a reviewed package and operator runbook. See
[`deployment.md`](../docs/operations/deployment.md) for the durable artifacts
and verification model.

The file loader below is for development and debugging only.

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

Add `http://127.0.0.1:8545` as chain `31337` in the browser wallet.

The headless acceptance tests use the mini-plan development key. They deploy a
fresh canonical Safe 1.4.1 proxy on each fork:

```bash
npm test
npm run test:fork
```

## Release package and modes

Production builds embed one `ceremony-<release>-<mode>.json` file. It contains:

- The exact plan bytes.
- Every Safe manifest, when using Safe mode.
- Expected addresses.

The browser recomputes every artifact hash and the package digest. It locks the
execution mode and displays a short call-time fingerprint. Embedded builds have
no file picker or mode switch.

EOA mode:

- Sends one plan transaction at a time.
- Stores progress against the exact plan-file hash.
- Re-verifies completed predicates on resume.
- Halts on any failure.

The first Sepolia deployment used three separately locked authority packages
before activation. Those packages are historical. Do not resume them.

Later maintenance packages use the current helper. They must not add an
ownership or authorization phase. Plan schema 1.1 records the required `deploy`
Foundry profile and exact ABI constructor types. The browser does not infer ABI
types from JSON values.

Safe mode also loads every `bundle-N.manifest.json` and
`expected-addresses.json`.

Before wallet interaction, it rebuilds and verifies:

- Constructor and call payloads.
- CREATE2 addresses.
- CreateCall operations.
- MultiSend transactions.

Any manifest mismatch halts execution. Protocol Kit receives the rebuilt
`DELEGATECALL (1)` transaction. It never receives untrusted manifest calldata or
the Transaction Builder import row.

Every bundle pins its Safe nonce and full EIP-712 transaction hash. On supported
public chains, API Kit proposes the transaction and polls signatures. Thresholds
and confirming owners are checked against the Safe itself.

On chain `31337`, or with `VITE_SAFE_LOCAL_ONLY=true`, a 1-of-1 Safe signs
EIP-712 and calls `execTransaction` directly. Service failure may fall back only
when the onchain threshold is exactly one. A production multi-owner Safe halts.

Without `CEREMONY_PACKAGE`, local development keeps the file and URL loaders and
the mode switch. Optional build-time defaults are:

- `VITE_MAINNET_RPC_URL`
- `VITE_SEPOLIA_RPC_URL`
- `VITE_ANVIL_RPC_URL`
- `VITE_SAFE_TX_SERVICE_URL`
- `VITE_SAFE_API_KEY`

Files may also be loaded from static URLs with CORS enabled:

```text
/?plan=<url>&manifest=<url>&manifest=<url>&expectedAddresses=<url>
```

## Build the release-specific site

Run these examples from the `v2-protocol` root. This gives every plan and
package path one unambiguous base.

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
allow hosting at any path.

Before execution:

- Publish the full ceremony digest and short fingerprint through an independent
  review channel.
- Confirm the UI shows the same values.

After every predicate is green, export `run-state-<release>.json` unchanged. The
UI names the next staging command for the three Anvil authority packages and
activation. A normal release activation passes its run-state to step 08:

```bash
export RUN_STATE=/path/to/run-state-v2-5.json
bash script/deploy/v2-5/08-finalize-inventory.sh
```
