# X-Ray Report

> Wildcat V2.5 | 13,444 in-scope nSLOC | 215f441 (`feat/v2.5-gas-optimizations-reviewed`) | Foundry / Solidity 0.8.25 / Cancun | 21/08/26

---

## 1. Protocol Overview

**What it does:** Wildcat originates uncollateralized borrower-controlled credit markets whose rebasing debt tokens accrue lender interest and settle withdrawals through timed FIFO batches.

- **Users**: Registered borrowers originate and operate markets; lenders supply assets, hold or wrap debt tokens, and queue withdrawals.
- **Core flow**: Deposit underlying → receive scaled interest-bearing debt claims → queue claims into expiry batches → execute paid claims.
- **Key mechanism**: Scaled balances plus a monotonic scale factor, reserve obligations, hook-gated actions, and FIFO withdrawal settlement.
- **Token model**: Rebasing market ERC-20 claims and an optional non-rebasing ERC-4626 wrapper whose shares equal scaled custody.
- **Admin model**: ArchController owner governs registration/templates; borrower, hook administrator, provider administrator, and SphereX roles are independent and mostly instant.

For a visual overview of the protocol's architecture, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|--------------|------:|------|
| Markets | WildcatMarket, WildcatMarketBase, WildcatMarketConfig, WildcatMarketToken, WildcatMarketWithdrawals, WildcatMarketRevolving | 1,457 | Core debt, interest, liquidity, token, and withdrawal state |
| Hooks & access | BaseAccessControls, OpenTermHooks, FixedTermHooks, PeriodicTermHooks, MarketConstraintHooks | 2,035 | Lender credentials, term gates, transfers, and APR constraints |
| Role providers | AccessList, Merkle, ERC20/4626/721/1155/5192/5484 providers and factories | 943 | Reusable credential sources and deterministic deployment |
| Market factories | HooksFactory, HooksFactoryRevolving | 1,431 | Template policy, transient constructor state, CREATE2 deployment, indexing |
| Registry & protection | WildcatArchController, BorrowerIdentityRegistry, Sanctions Sentinel/Escrow, SphereX bases, ReentrancyGuard | 1,085 | Root registration, identity, sanctions, middleware, reentrancy |
| ERC-4626 | Wildcat4626Wrapper, Wildcat4626WrapperFactory | 627 | Non-rebasing scaled-custody facade and generation routing |
| Lens | MarketLens and helper/data libraries | 1,938 | Aggregated read models across factories and markets |
| Math, state & low-level | MarketState, FeeMath, Withdrawal, FIFOQueue, LibERC20, LibStoredInitCode, events/errors, packed types | 2,453 | Accounting formulas, low-level calls, encodings, and queues |

### How It Fits Together

The core trick: exact scaled balances carry ownership while the scale factor changes their normalized labels, allowing interest accrual without iterating lenders.

### Market origination

```text
HooksFactory.deployMarket()
├─ resolve borrower principal in WildcatBorrowerIdentityRegistry
├─ stage MarketParameters in transient storage
├─ LibStoredInitCode.create2WithStoredInitCode()
│  └─ WildcatMarket[Revolving].constructor()  *reads staged parameters*
├─ AccessHooks.onCreateMarket()                *fixes hook flags/config*
└─ WildcatArchController.registerMarket()      *records canonical market*
```

### Deposit and credit draw

```text
WildcatMarket.deposit()
├─ accrue FeeMath / process expired batch      *first state update in block path*
├─ AccessHooks.onDeposit() → RoleProvider      *credential/minimum gate*
├─ asset.transferFrom(lender, market)
└─ account.scaledBalance += shares
   └─ state.scaledTotalSupply += shares        *paired accounting write*

WildcatMarket.borrow()
├─ verify borrower + borrower/principal sanctions
├─ compute assets above liquidityRequired()
└─ asset.transfer(borrower, amount)             *revolving market also updates drawnAmount*
```

### Withdrawal settlement

```text
queueWithdrawal[Scaled|Full]()
├─ AccessHooks.onQueueWithdrawal()              *term/window/access gate*
├─ lender.scaledBalance -= queued
└─ batch + pendingWithdrawals += queued         *claim remains interest-bearing*

[expiry] → updateState()/next action
├─ pay largest floor-priced scaled amount fitting liquidity
├─ burn paid scaled supply
└─ normalizedUnclaimedWithdrawals += paid       *reserved until execution*
   └─ executeWithdrawal() → lender or sanctions escrow
```

### Wrapper custody

```text
Wildcat4626Wrapper.deposit()/mint()
├─ marketToken.transferFrom(holder, wrapper)
├─ measure scaledBalanceOf(wrapper) delta       *must equal minted shares*
└─ mint non-rebasing wrapper shares

withdraw()/redeem()
├─ burn exact wrapper shares
├─ marketToken.transfer(wrapper, receiver)
└─ verify exact scaled custody delta            *solvency rechecked*
```

### Borrower authority migration

```text
requestBorrowerTransfer(target)
├─ registry.resolveBorrower(target)
├─ bind pending target to resolved principal
└─ check old + new borrower/principal sanctions

acceptBorrowerTransfer()
├─ require exact pending operational account
├─ re-resolve registration/principal/sanctions
└─ atomically replace borrower + principal      *accounting/hooks/providers unchanged*
```

---

## 2. Threat & Trust Model

### Protocol Threat Profile

> Protocol classified as: **Uncollateralized credit market** with **rebasing debt-token, ERC-4626 vault, and modular access-policy** characteristics

Lender safety is dominated by liability accounting, borrower authority, withdrawal ordering, and the correctness/liveness of hooks and external token/sanctions dependencies.

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| Lender | Untrusted | Deposits, transfers, wraps, queues, and executes claims with arbitrary trailing hook data |
| Borrower | Trusted for credit repayment; bounded on-chain | Instantly draws borrowable assets, changes cap/APR/reserves, closes, rescues unrelated tokens, and transfers operational authority |
| ArchController owner | Trusted | Instant borrower/asset/factory/controller/template policy; no protocol timelock in scope |
| Hook administrator | Bounded to one hook instance | Instantly changes providers, lender blocks, policy metadata, minimums/terms, and begins two-step authority transfer |
| Provider administrator | Bounded to one provider | Instantly changes list members or Merkle root and begins two-step authority transfer |
| SphereX admin/operator | Trusted middleware authority | Changes operator/engine; ArchController propagates engine changes to registered contracts |
| Hooks factory | Contract-trusted | Stages constructor data, deploys/records markets, and applies template protocol fees |
| Chainalysis sanctions oracle | External dependency | Determines raw sanctions status; failure can stop guarded actions |

**Adversary Ranking** (ordered by threat level for this protocol type, adjusted by git evidence):

1. **Compromised or defaulting borrower** — controls credit draws and market parameters in an intentionally uncollateralized design.
2. **Hostile lender/market-token holder** — can compose deposits, transfers, exact scaled queues, batch execution, and wrapper operations around rounding and timing edges.
3. **Credential adversary** — supplies arbitrary hook data and may interact through attached push, pull, or validation providers.
4. **Compromised policy/root authority** — Arch, hook, provider, and SphereX roles act instantly on distinct but interacting trust boundaries.
5. **Adverse integration** — listed assets, token/vault role providers, hooks, sanctions oracle, and legacy wrapper factory can revert or report unexpected state.

See [entry-points.md](entry-points.md) for the full permissionless entry point map.

### Trust Boundaries

- **Borrower → lender reserves** — borrow is instant but capped by `MarketState.liquidityRequired`; no collateral or repayment guarantee exists (`src/market/WildcatMarket.sol:145-167`).
- **Arch owner → origination surface** — owner controls borrower/factory/asset/template admission without an in-contract delay (`src/WildcatArchController.sol:150-380`, `src/HooksFactory.sol:194-321`).
- **Market → hook** — immutable hook address/flags can veto enabled actions; a reverting hook can stop the corresponding flow (`src/types/HooksConfig.sol:84-105`).
- **Hook admin → credentials** — provider attachments, TTLs, blocks, and term configuration update instantly; two-step transfer protects only the administrator seat (`src/access/BaseAccessControls.sol:170-419`).
- **Provider → lender admission** — token/vault balance and proof semantics are trusted after defensive call/timestamp checks (`src/access/BaseAccessControls.sol:641-758`).
- **SphereX operator → protected calls** — engine rotation is instant and protection can be disabled with address zero (`src/spherex/SphereXConfig.sol:137-160`).
- **Git signal** — fund-flow and state-machine areas have 287 and 238 historical source commits respectively, with 49 late source commits in the final 30-day window.

### Key Attack Surfaces

- **Scaled supply and withdrawal conservation** &nbsp;&#91;[I-1](invariants.md#i-1), [I-2](invariants.md#i-2), [I-3](invariants.md#i-3), [E-1](invariants.md#e-1)&#93; — `WildcatMarket.sol:77-84` and `WildcatMarketWithdrawals.sol:121-132` use paired writes across live balances, batches, supply, and liabilities; trace every alternate mutation path.

- **Batch expiry, FIFO payment, and close finalization** &nbsp;&#91;[I-3](invariants.md#i-3), [I-4](invariants.md#i-4), [I-6](invariants.md#i-6), [E-3](invariants.md#e-3)&#93; — `WildcatMarketBase.sol:994-1002` and `WildcatMarket.sol:223-242` split accrual at expiry and use floor-priced maximal settlement; confirm identical behavior under partial liquidity and same-timestamp closure.

- **Floor/half-up conversion boundaries** &nbsp;&#91;[I-5](invariants.md#i-5), [X-7](invariants.md#x-7), [E-7](invariants.md#e-7)&#93; — `MarketState.sol:69-115` deliberately floors normalized→scaled but half-up normalizes labels; inspect one-unit boundaries at every market, hook, and wrapper caller.

- **Revolving drawn-principal interest** &nbsp;&#91;[I-16](invariants.md#i-16), [E-5](invariants.md#e-5)&#93; — `WildcatMarketRevolving.sol:75-195` couples borrow/repay clamps with a custom rate formula and segmented accrual; compare every override with the standard market seam.

- **Borrower/principal two-step migration** &nbsp;&#91;[I-8](invariants.md#i-8), [I-15](invariants.md#i-15), [X-3](invariants.md#x-3), [X-9](invariants.md#x-9)&#93; — `WildcatMarketBase.sol:468-509` crosses registry resolution, raw sanctions, reserved storage, wrapper authority, and pending-state replacement.

- **Credential cache and provider replacement** &nbsp;&#91;[I-9](invariants.md#i-9), [I-10](invariants.md#i-10), [X-5](invariants.md#x-5)&#93; — `BaseAccessControls.sol:541-797,971-1001` combines push timestamps, TTL-zero refresh, arbitrary provider calls, and a permanent known-lender latch; trace ordering and provider-skip cases.

- **Periodic windows and permissionless APR execution** &nbsp;&#91;[I-11](invariants.md#i-11), [I-12](invariants.md#i-12), [I-13](invariants.md#i-13), [X-10](invariants.md#x-10)&#93; — `PeriodicTermHooks.sol:383-392,468-489,683-797` stores proposal-time bounds and recurring windows; confirm all time and closure boundaries.

- **Hand-built hook calldata** &nbsp;&#91;[X-6](invariants.md#x-6)&#93; — `HooksConfig.sol:294-910` manually lays out `MarketState`, dynamic trailing bytes, return data, and selectors for every action; compare constants against `IHooks` after any type-layout change.

- **ERC-4626 scaled custody, lender access, and sanctions transfer** &nbsp;&#91;[I-17](invariants.md#i-17), [X-7](invariants.md#x-7), [X-9](invariants.md#x-9), [X-11](invariants.md#x-11), [X-12](invariants.md#x-12), [E-4](invariants.md#e-4)&#93; — `Wildcat4626Wrapper.sol:184-218,289-441,620-792` reconciles observed scaled deltas, receiver eligibility, and sanctions; trace preview/limit/execution symmetry across inherited ERC-20 paths.

- **Transient CREATE2 constructor state** &nbsp;&#91;[X-1](invariants.md#x-1), [X-2](invariants.md#x-2)&#93; — `HooksFactory.sol:586-596,703-795` and the revolving twin stage constructor data and deploy stored init code. Salts must explicitly encode the immediate factory caller; zero-prefix salts are rejected, while valid prefixed salts remain publicly predictable.

- **Sanctions quarantine lifecycle** &nbsp;&#91;[X-8](invariants.md#x-8), [X-9](invariants.md#x-9)&#93; — `WildcatSanctionsSentinel.sol:93-133`, `WildcatSanctionsEscrow.sol:15-43`, and market/wrapper nuke paths cross mutable overrides, deterministic custody, term gates, and borrower-principal changes.

- **Manual storage and Yul return/event layouts** &nbsp;&#91;[I-18](invariants.md#i-18)&#93; — `WildcatMarketBase.sol:77-93,118-154,202-334` and `MarketEvents.sol` bypass Solidity layout/ABI checks; re-derive slot, selector, memory-pointer, and return-size assumptions.

### Protocol-Type Concerns

**As an uncollateralized credit market:**

- `MarketState.liquidityRequired:117-135` prioritizes pending/unclaimed withdrawals, reserves, and fees, but cannot protect lenders from borrower default beyond retained market liquidity.
- `WildcatMarket.closeMarket:220-300` is borrower-funded and iterates unpaid batches; operators must process long queues incrementally before closure.
- `FeeMath.updateTimeDelinquentAndGetPenaltyTime:88-121` lets delinquency time decay while healthy; compare alternating health intervals with the documented rolling model.

**As a rebasing token / ERC-4626 wrapper:**

- `WildcatMarketToken._transfer:78-100` emits the requested normalized amount while ownership moves in floor-scaled units; consumers must not infer exact balance deltas from events alone.
- `Wildcat4626Wrapper.maxWithdraw:197-207` returns the greatest normalized label whose market transfer burns no more than all shares; inspect ERC-4626 preview/execution inequalities at maximal scale factors.
- `Wildcat4626Wrapper.sweep:432-462` converts surplus scaled custody upward to the smallest exact normalized transfer; confirm no share backing is reachable under rounding extremes.

### Temporal Risk Profile

**Deployment & Initialization:**

- `HooksFactory._deployMarket:690-782` relies on transaction-scoped EIP-1153 state and Cancun opcodes; manual deployment to a pre-Cancun chain is unsupported and should fail before ceremony generation.
- `LibStoredInitCode.deployInitCode:7-48` now stores the revolving market's 23,178-byte creation code in one inert runtime; its 23,179-byte stored form leaves 1,397 bytes of EIP-170 margin, so the deploy profile remains release-critical.

**Market Stress:**

- `WildcatMarket.closeMarket:248-300` walks unpaid batches and can exceed transaction gas for a long queue; the documented operational control is incremental permissionless processing.
- Chainalysis or enabled-hook failure reverts sanctions, borrow, withdrawal, or policy paths synchronously; there is no asynchronous fallback.

**Deprecation:**

- `Wildcat4626WrapperFactory:91-170` routes undeclared rounding generations to the immutable v1 factory, so v2.5 and legacy wrappers remain one public discovery surface with different arithmetic implementations.

### Composability & Dependency Risks

**Dependency Risk Map:**

> **Listed ERC-20 asset** — via `WildcatMarket.deposit/borrow/repay/withdraw`
> - Assumes: stable metadata, standard balance accounting, and transfer semantics without fee/rebase/callback surprises
> - Validates: low-level success plus optional true return; most paths infer received value from balance reads
> - Mutability: External token governance is out of scope
> - On failure: Market action reverts

> **Chainalysis sanctions list** — via `WildcatSanctionsSentinel.isSanctioned`
> - Assumes: oracle liveness and meaningful sanctions result
> - Validates: call success through the typed interface
> - Mutability: Immutable oracle address; oracle data/implementation external
> - On failure: Guarded action reverts

> **Hook instance** — via `LibHooksConfig._callHook`
> - Assumes: approved implementation respects declared ABI and does not unexpectedly fail
> - Validates: immutable address/flags; callback failure is bubbled
> - Mutability: Code immutable, administrator-controlled state mutable
> - On failure: Enabled market action reverts

> **Role providers** — via `BaseAccessControls._tryGetCredential/_tryValidateCredential`
> - Assumes: provider-specific balance/proof semantics are meaningful
> - Validates: membership, clean call result, timestamp, TTL, and replacement ordering
> - Mutability: Hook admin attaches/removes; some provider admins change membership/root instantly
> - On failure: Fails closed and continues to later providers where applicable

> **SphereX engine** — via `SphereXProtectedRegisteredBase.sphereXGuardExternal`
> - Assumes: engine pre/post validation and selected storage slots are correct
> - Validates: interface at configuration time; ArchController controls registered contracts
> - Mutability: Engine is instantly replaceable or disableable by configured operator paths
> - On failure: Protected action reverts

> **ERC-4626 credential vault** — via `ERC4626AssetsRoleProvider._credentialTimestamp`
> - Assumes: `balanceOf` and `convertToAssets` represent durable economic ownership
> - Validates: nonzero shares and inclusive configured asset threshold
> - Mutability: Vault logic/governance external
> - On failure: Provider returns no credential through the hook's defensive call path

> **Legacy wrapper factory** — via `Wildcat4626WrapperFactory.createWrapper`
> - Assumes: v1 discovery/deployment semantics for markets without a rounding marker
> - Validates: constructor probe and generation marker routing
> - Mutability: Immutable address; implementation external to this audit scope
> - On failure: Legacy wrapper creation/discovery reverts

**Token Assumptions** *(unvalidated only)*:

- Market asset: assumes standard ERC-20 metadata and transfer/balance behavior — impact if violated: accounting or action liveness can diverge from normalized amounts.
- Token/vault role-provider inputs: assumes reported balances/conversions represent durable ownership — impact if violated: temporary or manipulated holdings may satisfy access policy.

---

## 3. Invariants

> ### 📋 Full invariant map: **[invariants.md](invariants.md)**
>
> A dedicated reference file contains the complete invariant analysis — do not look here for the catalog.
>
> - **50 Enforced Guards** (`G-1` … `G-50`) — per-call preconditions with predicate, location, and purpose
> - **18 Single-Contract Invariants** (`I-1` … `I-18`) — Conservation, Bound, Ratio, StateMachine, Temporal
> - **12 Cross-Contract Invariants** (`X-1` … `X-12`) — caller/callee pairs that cross scope boundaries
> - **7 Economic Invariants** (`E-1` … `E-7`) — higher-order properties deriving from `I-N` + `X-N`
>
> Every inferred block cites a concrete Δ-pair, guard-lift + write-sites, state edge, temporal predicate, or NatSpec quote. The single **On-chain=No** block is the future assembly/storage-layout obligation. Attack-surface bullets above cross-link directly into the relevant blocks.

---

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | `README.md` includes v2 status and Yul/type-layout warnings |
| NatSpec | 108 detected documentation signals | Core math, wrappers, factories, hooks, and low-level assembly are documented; several interfaces remain the canonical semantics |
| Spec/Whitepaper | Limited in the prescribed documentation glob | `README.md`, `docs/README.md`, and `deploy-ui/README.md` were the three matched documents; deploy UI claims were treated as spec-derived |
| Inline Comments | Thorough | Recent Yul hardening explains selectors, scratch memory, transient state, and ABI layouts |

The exact X-Ray documentation glob matched only three README files, so current source and this report remain the scope source of truth.

---

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 117 Solidity files | File scan |
| Test functions | 1,422 active test/invariant functions | Anchored function-definition scan |
| Line coverage | Unavailable — SphereX coverage instrumentation is incompatible with the required viaIR build; deferred by the user | `forge coverage` |
| Branch coverage | Unavailable — same instrumentation incompatibility and deferral | `forge coverage` |

### Test Depth

| Category | Count | Contracts Covered |
|----------|-------|-------------------|
| Unit / example | Broad | Markets, factories, hooks, providers, wrappers, lens, libraries, SphereX, identity, sanctions |
| Fork | 0 | Deployment rehearsals exist as scripts/docs, not Solidity fork tests |
| Stateless Fuzz | 44 | Market config/state/math, hooks, providers, wrapper and queue boundaries |
| Stateful Fuzz (Foundry) | 21 invariant functions | Supply/balance conservation, market/revolving properties, withdrawal identity, and integration matrices |
| Stateful Fuzz (Echidna/Medusa) | 0 | No existing Echidna/Medusa property suite detected before this audit's Fizz phase |
| Formal Verification | 0 | No protocol Certora, Halmos, or HEVM specs detected |

### Gaps

- Current coverage is intentionally deferred to the user's separate SphereX-aware coverage pass.
- No independent Echidna/Medusa state machine exists; current invariants run only through Foundry's engine.
- No formal properties prove the floor/half-up settlement math, revolving formula, manual storage slots, or wrapper conversion identities.
- No Solidity fork tests exercise the exact release ceremony; deployment evidence lives in scripts and prior Anvil rehearsal artifacts.

---

## 6. Developer & Git History

> Repo shape: normal_dev — 697 source-touching commits over 1,514 days (2022-06-29 → 2026-08-21) are visible within 1,270 total commits.

### Contributors

| Author | Source Commits | Source Lines Added | % of Source Additions |
|--------|---------------:|-------------------:|----------------------:|
| d1ll0n | — | 29,210 | 64.7% |
| Dave Coleman | — | 12,057 | 26.7% |
| Dr Laurence E. Day | — | 2,610 | 5.8% |
| Jack McSweeney / Jack | — | 1,139 | 2.5% |

### Review & Process Signals

| Signal | Value | Assessment |
|--------|-------|------------|
| Unique contributors | 10 commit identities; 7 line-contribution identities | Small concentrated team |
| Merge commits | 84 of 1,270 (6.6%) | Some integration history; merge count alone does not prove peer review |
| Repo age | 2022-06-29 → 2026-08-21 | 1,514 days |
| Recent source activity (30d) | 49 commits; 10 without paired test-file changes | Late optimization and audit-remediation burst |
| Test co-change rate | 24.4% | File co-modification signal only; not coverage |
| Fix-without-test rate | 20% | Historical fix commit signal; not proof the code lacks later tests |

### File Hotspots

| File | Modifications | Note |
|------|-------------:|------|
| `src/market/WildcatMarketBase.sol` | 85 | Storage, accrual, identity, sanctions, batch core |
| `src/market/WildcatMarket.sol` | 73 | Main value flows and closure |
| `src/market/WildcatMarketWithdrawals.sol` | 64 | Queue/payment/execution state machine |
| `src/market/WildcatMarketConfig.sol` | 55 | APR/reserve/fee/wrapper policy |
| `src/interfaces/IMarketEventsAndErrors.sol` | 35 | Cross-version ABI/event surface |
| `src/HooksFactory.sol` | 29 | Deployment and template control plane |
| `src/types/HooksConfig.sol` | 25 | Manual callback ABI assembly |
| `src/libraries/MarketErrors.sol` | 24 | Manual error ABI emission |

### Security-Relevant Commits

| SHA | Date | Subject | Score | Key Signal |
|-----|------|---------|------:|------------|
| `fa3b76c` | 2026-07-13 | fix: 4626 wrapped shares escrowed on sanction | 15 | Wrapper access/accounting guard fix with tests |
| `7c5deb6` | 2026-07-14 | fix: 4626 sanction fix, more deploy scripting | 14 | Cross-domain sanctions and wrapper hardening |
| `8caf671` | 2026-07-13 | fix: withdrawals at close batch expiry can misallocate repay capital | 14 | Withdrawal accounting/state-machine fix with tests |
| `f2e83a7` | 2026-07-07 | fix: 4626 roudning issues | 14 | Wrapper/market rounding changes with tests |

### Dangerous Area Evolution

| Security Area | Commits | Key Files |
|--------------|--------:|-----------|
| fund_flows | 287 | WildcatMarket, Withdrawals, MarketState |
| state_machines | 238 | MarketBase, Withdrawals, access hooks |
| signatures / ABI layouts | 165 | HooksFactory, HooksConfig, MarketEvents |
| access_control | 160 | Factories, ArchController, BaseAccessControls |
| oracle_price heuristic | 15 | MarketState |

### Forked Dependencies

| Library | Path | Upstream | Status | Notes |
|---------|------|----------|--------|-------|
| OpenZeppelin | `lib/openzeppelin-contracts` | OpenZeppelin | Submodule | Used for EnumerableSet/interfaces; broad vendored pragma range |
| Solady | `lib/solady` | Solady | Submodule | ERC-4626/ERC-20 base and Merkle proof code |
| sol-utils | `lib/sol-utils` | Project dependency | Submodule | Large test/utility dependency; not internalized |
| ethereum-access-token | `lib/ethereum-access-token` | External | Submodule | Access-token dependency; not internalized |

### Technical Debt Markers

| File:Line | Type | Text | Author | Date |
|-----------|------|------|--------|------|
| `src/access/PeriodicTermHooks.sol:127` | TODO | FOR MAINNET: Finalize the minimum period duration with the team. | Dave Coleman | 2026-07-14 |
| `src/access/PeriodicTermHooks.sol:129` | TODO | FOR MAINNET: Finalize the maximum period duration with the team. | Dave Coleman | 2026-05-20 |
| `src/access/PeriodicTermHooks.sol:131` | TODO | FOR MAINNET: Finalize the minimum withdrawal window duration with the team. | Dave Coleman | 2026-05-20 |
| `src/access/PeriodicTermHooks.sol:133` | TODO | FOR MAINNET: Finalize the maximum initial withdrawal window delay with the team. | Dave Coleman | 2026-05-20 |

### Security Observations

- **Two-contributor concentration** — d1ll0n and Dave Coleman account for 91.4% of source additions.
- **Late release burst** — 49 source commits landed in 30 days, including current-branch Yul, lens, access, wrapper, and FIFO gas changes.
- **Unpaired late refactors** — `beedf27` and `aed11ad` changed market Yul/bytecode without test files in the same commits, though surrounding commits add tests.
- **Core churn concentration** — the four market implementation files are the top current-file modification hotspots.
- **Coverage evidence is stale** — `docs/v2.5-audit-delta.md` identifies `822045f` and explicitly says its coverage predates later features.
- **Mainnet constants unresolved** — four PeriodicTermHooks bounds remain explicitly marked for team finalization.

### Cross-Reference Synthesis

- **Market core leads both churn and invariant density** — the top four hotspots implement `I-1` through `I-8` and `E-1` through `E-3` → highest-leverage manual audit surface.
- **Late Yul changes align with manual ABI/storage surfaces** — three final-day refactors touch `HooksConfig`, MarketBase, events/errors, and stored init code → re-derive layouts independently.
- **Wrapper fix history aligns with `I-17`/`X-7`/`X-9`** — sanctions, rounding, and custody each previously required fixes → treat inherited transfer paths as a dedicated audit track.
- **Periodic TODOs align with `I-12`/`I-13`** — unresolved production bounds govern lender exit timing and APR-response windows → explicit release decision required before mainnet.

---

## X-Ray Verdict

**EXPOSED** — Unit, fuzz, invariant, and documentation evidence are substantial, but privileged operational actions have no protocol timelock and four security-relevant PeriodicTermHooks production bounds remain explicit mainnet TODOs; the X-Ray rubric lowers the access-control floor by one tier for those unresolved markers.

**Structural facts:**
1. 13,444 in-scope Solidity nSLOC across eight protocol subsystems.
2. 117 Solidity test files contain 1,422 active test/invariant functions, including 44 stateless fuzz tests and 21 Foundry invariant functions.
3. 697 source-touching commits span 1,514 days; the two largest contributors account for 91.4% of source additions.
4. 49 source commits landed in the final 30-day window; ten did not change a test file in the same commit.
5. Four `FOR MAINNET` TODOs remain in PeriodicTermHooks parameter bounds, and no protocol formal-verification suite was detected.
