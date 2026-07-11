# Deployment ceremony UI

Disposable static UI for executing a deployment plan with a testnet EOA or
proposing/signing/executing prebuilt Safe bundles. It has no backend and never
accepts editable calldata.

## Run locally or on a fork

```bash
cd deploy-ui
npm install
npm run dev
```

Start the fork separately, following `docs/deployment.md` section 5:

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

## Inputs and modes

Load `plan-<release>.json` in both modes. EOA mode sends one plan transaction at
a time, persists progress by exact plan-file hash, re-verifies completed
predicates on resume, and halts on any failure.

Safe mode also loads every `bundle-N.manifest.json` plus
`expected-addresses.json`. It submits the manifest's raw MultiSend transaction
as `DELEGATECALL (1)` through Protocol Kit; it never uses the Transaction Builder
import row. On supported public chains, API Kit proposes and polls signatures.
On chain `31337`, or with `VITE_SAFE_LOCAL_ONLY=true`, a 1-of-1 Safe signs EIP-712
and calls `execTransaction` directly. A service failure can fall back only when
the on-chain threshold is exactly one; a production multi-owner Safe halts.

Optional build-time defaults are `VITE_MAINNET_RPC_URL`,
`VITE_SEPOLIA_RPC_URL`, `VITE_ANVIL_RPC_URL`, `VITE_SAFE_TX_SERVICE_URL`, and
`VITE_SAFE_API_KEY`. Files can also be loaded from static, CORS-enabled URLs:

```text
/?plan=<url>&manifest=<url>&manifest=<url>&expectedAddresses=<url>
```

## Static hosting and handoff

```bash
npm run build
```

Serve or upload `deploy-ui/dist/` as ordinary static files. Relative asset URLs
allow hosting at any path. After all predicates are green, export
`run-state-<release>.json` and pass it unchanged to step 08:

```bash
export RUN_STATE=/path/to/run-state-v2-5.json
bash script/deploy/v2-5/08-finalize-inventory.sh
```
