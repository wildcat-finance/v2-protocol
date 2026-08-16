# Invariant Map

> Wildcat V2.5 | 50 guards | 18 single-contract + 11 cross-contract + 7 economic invariants | 2 not enforced on-chain

---

## 1. Enforced Guards (Reference)

Per-call preconditions. Heading IDs below (`G-N`) are anchor targets from x-ray.md attack surfaces.

#### G-1
`msg.sender == borrower()` · `src/market/WildcatMarketBase.sol:341-351` · Restricts debt draws, closure, rescue, configuration, and transfer initiation to the current operational borrower.

#### G-2
`msg.sender == pendingBorrower()` · `src/market/WildcatMarketBase.sol:494-502` · Makes borrower authority migration opt-in by the exact pending operational account.

#### G-3
`newBorrowerPrincipal == expectedPrincipal` · `src/market/WildcatMarketBase.sol:426-440` · Prevents accepting a borrower account after its registered principal changed underneath the pending request.

#### G-4
`flaggedIdentity == address(0)` · `src/market/WildcatMarketBase.sol:358-370` · Prevents sanctioned operational or principal identities from initiating or accepting authority migration.

#### G-5
`!state.isClosed` · `src/market/WildcatMarket.sol:60` · Prevents new lender supply after market closure.

#### G-6
`scaledAmount != 0` · `src/market/WildcatMarket.sol:67` · Prevents deposits that mint no scaled debt claim.

#### G-7
`amount <= state.maximumDeposit()` · `src/market/WildcatMarket.sol:43-52,103-121` · Enforces the market's normalized supply cap on both bounded and exact deposit paths.

#### G-8
`!state.isClosed && amount <= state.borrowableAssets(totalAssets())` · `src/market/WildcatMarket.sol:145-167` · Keeps borrower draws within assets not reserved for lender and fee obligations.

#### G-9
`!state.isClosed` · `src/market/WildcatMarket.sol:169-208` · Prevents post-close repayments from mutating a finalized liability state.

#### G-10
`!state.isClosed` · `src/market/WildcatMarket.sol:220-223` · Makes closure a one-way market transition.

#### G-11
`state.scaledPendingWithdrawals == 0` · `src/market/WildcatMarket.sol:241-300` · Requires closure to fund and burn every pending scaled withdrawal.

#### G-12
`scaledAmount != 0` · `src/market/WildcatMarketWithdrawals.sol:152-215` · Prevents zero-claim queue entries across normalized, scaled, and full-withdrawal paths.

#### G-13
`expiry != state.pendingWithdrawalExpiry` · `src/market/WildcatMarketWithdrawals.sol:281-305` · Blocks claims against the still-active batch before expiry processing.

#### G-14
`normalizedAmountWithdrawn != 0` · `src/market/WildcatMarketWithdrawals.sol:294-305` · Prevents no-op execution and preserves monotonic account claim accounting.

#### G-15
`msg.sender == wrapperFactory` · `src/market/WildcatMarketConfig.sol:63-69` · Authenticates the only contract allowed to bind a market's canonical wrapper.

#### G-16
`registeredWrapper() == address(0)` · `src/market/WildcatMarketConfig.sol:65-69` · Makes wrapper registration one-shot.

#### G-17
`accountAddress != registeredWrapper()` · `src/market/WildcatMarketConfig.sol:96-104` · Prevents sanctions quarantine from consuming the shared wrapper custody account.

#### G-18
`state.liquidityRequired() <= totalAssets()` · `src/market/WildcatMarketConfig.sol:131-160` · Rejects reserve-ratio transitions that leave current assets below the resulting obligation.

#### G-19
`annualInterestBips <= 10_000 && reserveRatioBips <= 10_000` · `src/market/WildcatMarketConfig.sol:139-145` · Bounds market APR and reserve ratios to their documented basis-point domain.

#### G-20
`hooks.useOnExecutePendingAnnualInterestBipsReduction()` · `src/market/WildcatMarketConfig.sol:213-234` · Limits permissionless APR execution to markets whose immutable hook flags enable that path.

#### G-21
`proposedAnnualInterestBips < state.annualInterestBips` · `src/market/WildcatMarketConfig.sol:213-234` · Ensures the permissionless hook path can only reduce, never raise, borrower APR.

#### G-22
`msg.sender == factory && protocolFeeBips <= 1_000` · `src/market/WildcatMarketConfig.sol:237-253` · Restricts protocol-fee mutation to the creating factory and caps it at ten percent.

#### G-23
`msg.sender == IWildcatArchController(_archController).owner()` · `src/HooksFactory.sol:194-202` · Ties template approval and fee policy to the live ArchController owner.

#### G-24
`template.exists && template.enabled` · `src/HooksFactory.sol:497-505` · Prevents deployments through unknown or disabled hook templates.

#### G-25
`!archController.isBlacklistedAsset(parameters.asset)` · `src/HooksFactory.sol:690-701` · Prevents new markets using an asset rejected by protocol governance.

#### G-26
`runtime origination terms == current template terms` · `src/HooksFactory.sol:706-722` · Binds the caller's quoted fee to the template state used at execution.

#### G-27
`create2WithStoredInitCode(...) == predictedMarket` · `src/HooksFactory.sol:765-777` · Fails deployment if stored init code does not create the precomputed market address.

#### G-28
`getHooksTemplateForInstance[hooksInstance] != address(0)` · `src/HooksFactory.sol:445-471` · Authenticates hook-administrator transfer callbacks to instances created by this factory.

#### G-29
`msg.sender == owner()` · `src/WildcatArchController.sol:150-380` · Restricts borrower, blacklist, factory, controller, and market removals to the root owner.

#### G-30
`_controllerFactories.contains(msg.sender)` · `src/WildcatArchController.sol:300-313` · Allows only registered controller factories to register controllers.

#### G-31
`_controllers.contains(msg.sender)` · `src/WildcatArchController.sol:356-369` · Allows only registered controllers to register markets.

#### G-32
`principalOf[account] == address(0)` · `src/WildcatBorrowerIdentityRegistry.sol:98-123` · Makes initial borrower-account attribution permanent and non-overwritable.

#### G-33
`principal is registered && principalOf[principal] == address(0)` · `src/WildcatBorrowerIdentityRegistry.sol:110-116` · Rejects unknown and nested borrower identities at registration.

#### G-34
`msg.sender == currentPrincipal` · `src/WildcatBorrowerIdentityRegistry.sol:126-157` · Gives only the current legal principal control over account-principal transfer requests and cancellation.

#### G-35
`msg.sender == pendingPrincipalOf[account]` · `src/WildcatBorrowerIdentityRegistry.sol:160-170` · Requires the target principal to accept account identity migration.

#### G-36
`msg.sender == administrator` · `src/access/BaseAccessControls.sol:125-128` · Restricts hook policy, provider membership, and lender blocking to the hook administrator.

#### G-37
`msg.sender == pendingAdministrator` · `src/access/BaseAccessControls.sol:202-215` · Makes hook-administrator migration a two-step handoff.

#### G-38
`_roleProviders[msg.sender] != EmptyRoleProvider` · `src/access/BaseAccessControls.sol:516-540` · Allows credentials to be pushed only by providers attached to this hook instance.

#### G-39
`credentialTimestamp != 0 && credentialTimestamp <= block.timestamp` · `src/access/BaseAccessControls.sol:551-558` · Rejects absent and future-dated pushed credentials.

#### G-40
`status.lastProvider == msg.sender || newExpiry > oldExpiry` · `src/access/BaseAccessControls.sol:560-573` · Prevents a provider from shortening another provider's still-valid credential.

#### G-41
`msg.sender == status.lastProvider` · `src/access/BaseAccessControls.sol:579-599` · Restricts credential revocation to the provider that granted the active credential.

#### G-42
`_hookedMarkets[msg.sender].isHooked` · `src/access/OpenTermHooks.sol:251-373` · Authenticates stateful lender-access callbacks to markets initialized on the hook.

#### G-43
`!status.isBlockedFromDeposits && scaledAmount >= scaledMinimum` · `src/access/OpenTermHooks.sol:258-287` · Makes hook-local blocks authoritative and enforces minimum deposits in the market's scaled accounting domain.

#### G-44
`knownLender || _tryValidateAccess(...)` · `src/access/OpenTermHooks.sol:299-314` · Preserves withdrawal availability for previously admitted lenders while gating unknown accounts.

#### G-45
`!transfersDisabled && !toStatus.isBlockedFromDeposits` · `src/access/OpenTermHooks.sol:339-368` · Enforces the market's immutable transfer policy and recipient block state.

#### G-46
`fixedTermEndTime <= block.timestamp` · `src/access/FixedTermHooks.sol:373-393` · Prevents lenders queueing withdrawals before the fixed term ends.

#### G-47
`isClosed || withdrawalWindowOpen(block.timestamp)` · `src/access/PeriodicTermHooks.sol:565-586` · Restricts withdrawal queueing to recurring windows until closure.

#### G-48
`responseWindow ended && proposal unexpired && scaledPendingWithdrawals == 0` · `src/access/PeriodicTermHooks.sol:705-739` · Prevents premature, stale, or withdrawal-conflicting APR reductions.

#### G-49
`msg.sender == wrappedMarket.borrower()` · `src/vault/Wildcat4626Wrapper.sol:432-462` · Makes sweep authority follow the market's live operational borrower.

#### G-50
`wrappedMarket.scaledBalanceOf(address(this)) >= totalSupply()` · `src/vault/Wildcat4626Wrapper.sol:523-540` · Prevents wrapper operations from continuing while scaled backing is below outstanding shares.

---

## 2. Inferred Invariants (Single-Contract)

#### I-1

`Conservation` · On-chain: **Yes**

> A deposit increases both lender scaled balance and `scaledTotalSupply` by the same scaled amount.

**Derivation** — Δ-pair: `src/market/WildcatMarket.sol:77-87` (`accounts[lender] += s` ↔ `scaledTotalSupply += s`)

**If violated** — Market-token balances and the interest-bearing debt denominator diverge.

#### I-2

`Conservation` · On-chain: **Yes**

> Queueing a withdrawal moves, rather than duplicates, a lender's scaled claim into batch and pending-withdrawal accounting.

**Derivation** — Δ-pair: `src/market/WildcatMarketWithdrawals.sol:121-146` (`account.scaledBalance -= s` ↔ `status.scaledAmount += s` ↔ `batch.scaledTotalAmount += s` ↔ `state.scaledPendingWithdrawals += s`)

**If violated** — Withdrawal liabilities can be lost or counted twice.

#### I-3

`Conservation` · On-chain: **Yes**

> Paying a batch burns the same scaled amount from pending withdrawals and total supply while adding the normalized payment to unclaimed liabilities.

**Derivation** — Δ-pair: `src/market/WildcatMarketBase.sol:968-999` (`scaledPendingWithdrawals -= s` ↔ `scaledTotalSupply -= s`; `normalizedUnclaimedWithdrawals += n`)

**If violated** — Paid withdrawals could continue earning interest or become borrowable.

#### I-4

`Ratio` · On-chain: **Yes**

> Each account's withdrawal entitlement is its scaled batch share of total normalized payments, less amounts already withdrawn.

**Derivation** — NatSpec/formula: `src/market/WildcatMarketWithdrawals.sol:281-305`

**If violated** — Same-batch lenders would not receive pro-rata settlement.

#### I-5

`Bound` · On-chain: **Yes**

> `scaleFactor` starts at `RAY`, never decreases, and reverts rather than truncating at the `uint112` horizon.

**Derivation** — guard-lift/write-sites: initialization `src/market/WildcatMarketBase.sol:247-278`; only accrual writer adds a nonnegative delta and checked-casts at `src/libraries/FeeMath.sol:164-171`

**If violated** — All normalized balances, wrapper conversions, and debt obligations can move backwards.

#### I-6

`StateMachine` · On-chain: **Yes**

> A market transitions from open to closed once and cannot reopen.

**Derivation** — edge: `isClosed == false@src/market/WildcatMarket.sol:223 → true@src/market/WildcatMarket.sol:242`; no reverse write exists

**If violated** — Finalized APR, reserves, repayments, and withdrawal settlement assumptions no longer hold.

#### I-7

`StateMachine` · On-chain: **Yes**

> A market has at most one registered wrapper.

**Derivation** — edge: `registeredWrapper == 0@src/market/WildcatMarketConfig.sol:67 → wrapper@src/market/WildcatMarketConfig.sol:68`

**If violated** — Multiple custodial facades could claim canonical integration status.

#### I-8

`StateMachine` · On-chain: **Yes**

> Pending borrower status grants no borrower authority; acceptance atomically clears pending state and replaces borrower plus principal.

**Derivation** — edge: `pending=(b,p)@src/market/WildcatMarketBase.sol:468-469 → pending=(0,0), current=(b,p)@src/market/WildcatMarketBase.sol:506-509`

**If violated** — Operational and legal authority could split or overlap during transfer.

#### I-9

`StateMachine` · On-chain: **Yes**

> `isKnownLenderOnMarket[account][market]` is a one-way latch.

**Derivation** — edge: `false@src/access/BaseAccessControls.sol:943-948 → true@src/access/BaseAccessControls.sol:950`; no false write exists

**If violated** — A previously admitted lender could lose the hook-local ability to exit.

#### I-10

`Bound` · On-chain: **Yes**

> An active cached credential is nonzero, nonfuture, and either controlled by its granting provider or replaced only by a later expiry.

**Derivation** — guard-lift: guards at `src/access/BaseAccessControls.sol:551-573`; credential writers at `src/access/BaseAccessControls.sol:958-973` and clearers at `src/access/BaseAccessControls.sol:591-623`

**If violated** — Provider ordering can shorten or forge another provider's authorization.

#### I-11

`StateMachine` · On-chain: **Yes**

> A periodic hooked market's `isClosed` flag changes only from false to true and cancels its pending APR proposal.

**Derivation** — edge/Δ-pair: `false@src/access/PeriodicTermHooks.sol:255-332 → true@src/access/PeriodicTermHooks.sol:665-678`; `_pendingAprChanges[market] → 0` in the same body

**If violated** — Withdrawal-window and APR-governance behavior could disagree with market closure.

#### I-12

`Temporal` · On-chain: **Yes**

> Periodic withdrawal windows are start-inclusive and end-exclusive, recurring at `periodDuration` until closure.

**Derivation** — temporal: `_isWithdrawalWindowOpen` and queue guard at `src/access/PeriodicTermHooks.sol:467-503,565-586`

**If violated** — Lenders and integrators cannot predict when queueing is callable.

#### I-13

`StateMachine` · On-chain: **Yes**

> A periodic APR proposal is either pending with stored response bounds or absent; overwrite, increase, close, expiry, and execution follow explicit transitions.

**Derivation** — edge: `zero/old@src/access/PeriodicTermHooks.sol:378-392 → proposal`; `proposal → zero@src/access/PeriodicTermHooks.sol:675,737,785`

**If violated** — A stale or differently timed proposal could change borrower APR.

#### I-14

`StateMachine` · On-chain: **Yes**

> A hook template can move from enabled to disabled but cannot be re-enabled.

**Derivation** — edge: `enabled=true@src/HooksFactory.sol:230-241 → false@src/HooksFactory.sol:316-321`; no reverse writer

**If violated** — A retired template could unexpectedly originate new markets.

#### I-15

`StateMachine` · On-chain: **Yes**

> A borrower account's initial factory attribution is immutable while its principal changes only through two-step transfer.

**Derivation** — edge: `principalOf[account]=0@src/WildcatBorrowerIdentityRegistry.sol:106 → principal@118`; transfer edge at `src/WildcatBorrowerIdentityRegistry.sol:126-172`

**If violated** — Identity provenance or principal enumeration becomes ambiguous.

#### I-16

`Bound` · On-chain: **Yes**

> Revolving `drawnAmount` never exceeds outstanding normalized debt and becomes zero on close.

**Derivation** — guard-lift/write-sites: clamped writes at `src/market/WildcatMarketRevolving.sol:75-112`; close write `drawnAmount → 0@106-108`

**If violated** — Revolving lender APR charges could be based on nonexistent borrower principal.

#### I-17

`Conservation` · On-chain: **Yes**

> Every wrapper mint/burn is reconciled against the exact observed change in the market's scaled balance, preserving `scaledBacking >= shareSupply`.

**Derivation** — Δ-pair: deposits/mints `src/vault/Wildcat4626Wrapper.sol:265-329`; withdrawals/redemptions `:333-399`; solvency guard `:523-540`

**If violated** — Wrapper shares cease to represent fully backed scaled market claims.

#### I-18

`Bound` · On-chain: **No**

> No current or future manual-storage code may use the five reserved terminal slots holding borrower, principal, pending transfer, and wrapper state.

**Derivation** — NatSpec: `src/market/WildcatMarketBase.sol:77-93` — “Other manual storage must not use this five-slot range.” No runtime mechanism can police future assembly writers.

**If violated** — Authority or wrapper state can be silently corrupted without changing the sequential storage layout.

---

## 3. Inferred Invariants (Cross-Contract)

#### X-1

On-chain: **Yes**

> A market constructor reads only the parameter tuple transiently staged by its creating factory and that tuple is cleared after deployment.

**Caller side** — `src/market/WildcatMarketBase.sol:202-235` — reads `getMarketParameters()` from constructor caller with exact return size.

**Callee side** — `src/HooksFactory.sol:586-596,765-780` — writes transient parameters/principal before CREATE2 and clears them afterward.

**If violated** — A market can initialize with another deployment's asset, borrower, hooks, or fees.

#### X-2

On-chain: **Yes**

> Factory address prediction rejects zero-prefix salts, deployment requires the explicit salt prefix to equal the immediate factory caller, and stored init-code deployment plus ArchController registration refer to that same market address.

**Caller side** — `src/HooksFactory.sol:628-637,704-785` — rejects zero-prefix predictions, requires an explicit caller prefix during deployment, rejects existing code, verifies CREATE2 return, then registers; the revolving factory mirrors this path. A borrower account is the caller namespace even when its principal changes.

**Callee side** — `src/WildcatArchController.sol:356-369` — only a registered controller may add that exact address to the market set.

**If violated** — Another borrower could consume a counterfactual address, or events, registry state, and deployed bytecode could identify different markets.

#### X-3

On-chain: **Yes**

> A market accepts borrower identities only from a registry bound to its immutable ArchController, and acceptance re-resolves the pending principal.

**Caller side** — `src/market/WildcatMarketBase.sol:292-333,373-456` — validates registry controller, return ABI, principal binding, registration, and sanctions.

**Callee side** — `src/WildcatBorrowerIdentityRegistry.sol:175-189,250-270` — resolves only direct registered principals or registered account principals and fails closed on ambiguity.

**If violated** — Operational borrower powers could become detached from the registered legal identity.

#### X-4

On-chain: **Yes**

> Hook-administrator acceptance and factory enumeration update are atomic.

**Caller side** — `src/access/BaseAccessControls.sol:202-215` — changes local administrator then calls the creating factory; callback failure reverts all writes.

**Callee side** — `src/HooksFactory.sol:440-487` — authenticates instance/current/pending state and repairs both administrator indexes by swap-and-pop.

**If violated** — Factory discovery could attribute a hook to an authority different from the hook's live administrator.

#### X-5

On-chain: **Yes**

> Provider-returned credentials enter hook storage only after provider membership, timestamp, expiry, and replacement checks.

**Caller side** — `src/access/BaseAccessControls.sol:516-599,641-758` — authenticates push providers and treats failed pull/validation calls as no credential.

**Callee side** — `src/providers/AccessListRoleProvider.sol:103-114`, `src/providers/MerkleRoleProvider.sol:41-68`, `src/providers/ERC20RoleProvider.sol:25-41` — known providers derive timestamps from current membership, proof, or balance.

**If violated** — A lender could retain or manufacture access outside configured cache policy.

#### X-6

On-chain: **Yes**

> Enabled market actions invoke the immutable hook address and exact enabled flag set selected at deployment.

**Caller side** — `src/types/HooksConfig.sol:294-880` — packs concrete hook calldata and conditionally calls the stored address.

**Callee side** — `src/access/OpenTermHooks.sol:139-194,251-373` — stores per-market configuration once during factory creation and authenticates stateful callbacks by `msg.sender`.

**If violated** — Market actions and policy state can disagree about which lender restrictions apply.

#### X-7

On-chain: **Yes**

> The wrapper and market use the same floor-scaled transfer identity for every custody operation.

**Caller side** — `src/vault/Wildcat4626Wrapper.sol:247-399` — computes expected scaled deltas and verifies observed `scaledBalanceOf` changes.

**Callee side** — `src/market/WildcatMarketToken.sol:78-100` — converts normalized transfer amounts with `scaleAmountDown` and moves that exact scaled amount.

**If violated** — ERC-4626 shares can diverge from market-token backing through rounding asymmetry.

#### X-8

On-chain: **Yes**

> A sanctions escrow's immutable borrower, account, and asset equal the temporary tuple selected by the sentinel for its deterministic address.

**Caller side** — `src/WildcatSanctionsSentinel.sol:112-133` — computes or creates the escrow, resets temporary parameters, and grants the borrower override.

**Callee side** — `src/WildcatSanctionsEscrow.sol:15-43` — constructor reads the sentinel tuple and release transfers only its immutable asset to its immutable account.

**If violated** — Quarantined funds could be released under the wrong borrower namespace or to the wrong beneficiary.

#### X-9

On-chain: **Yes**

> Accepted borrower transfer immediately changes wrapper sweep authority and sanctions namespace without moving wrapper accounting state.

**Caller side** — `src/vault/Wildcat4626Wrapper.sol:130-133,432-462,503-520` — reads live borrower/principal for authority and sanctions checks.

**Callee side** — `src/market/WildcatMarketBase.sol:494-517` — atomically changes only borrower/principal and pending slots.

**If violated** — An old borrower could retain wrapper authority or new sanctions checks could use stale identity.

#### X-10

On-chain: **Yes**

> Permissionless APR reduction executes only the exact proposal authorized by the periodic hook and only through the market's bound hook address.

**Caller side** — `src/market/WildcatMarketConfig.sol:203-234` — checks hook flag and strictly lower returned APR before applying it.

**Callee side** — `src/access/PeriodicTermHooks.sol:699-739` — matches proposal value, response bounds, validity, and zero pending withdrawals before deletion.

**If violated** — A public executor could apply a stale, early, or unapproved APR change.

#### X-11

On-chain: **Yes**

> Canonical wrapper shares intentionally remain transferable without reproducing market role-provider eligibility, while borrower-scoped sanctions gate share mint, burn, and transfer and every unwrap receiver remains subject to the wrapped market's transfer hook.

**Caller side** — `src/vault/Wildcat4626WrapperFactory.sol:96-155` — rejects markets whose transfers are globally disabled, but does not reject markets whose transfer hooks require credentials.

**Callee side** — `src/vault/Wildcat4626Wrapper.sol:264-399,549-570` — market-token movement uses the normal market transfer path, while wrapper share mint, transfer, and burn enforce borrower-scoped sanctions rather than hook-local lender eligibility.

**If violated** — A sanctioned account could hold or move wrapper shares, or an unwrap could deliver market tokens without the receiver passing through the market's transfer hook.

#### X-12

On-chain: **Yes**

> A canonical wrapper reports nonzero `maxDeposit` or `maxMint` only when it currently passes the wrapped market's recipient-side transfer policy without extra hook data; conversion previews remain independent of access and capacity.

**Caller side** — `src/vault/Wildcat4626Wrapper.sol` — combines sanctions, solvency, capacity, rounding, and the hook policy query in `maxDeposit`; `maxMint` derives from that result while previews remain conversion-only.

**Callee side** — `src/access/{Open,Fixed,Periodic}TermHooks.sol` — reports the same no-data recipient decision used by the transfer hook for unrestricted, credentialed, blocked, and known-lender states. The wrapper treats a failed query as zero capacity.

**If violated** — Routers can size a globally impossible wrapper deposit or mint, or a view failure can make ERC-4626 limit discovery revert.

---

## 4. Economic Invariants

#### E-1

On-chain: **Yes**

> Market debt claims are conserved across lender balances, queued scaled claims, paid-but-unclaimed liabilities, and protocol fees.

**Follows from** — `I-1` + `I-2` + `I-3`

**If violated** — Assets can become borrowable despite an outstanding lender or protocol claim.

#### E-2

On-chain: **Yes**

> Borrowable assets exclude 100% of pending and unclaimed withdrawals, accrued protocol fees, and the configured reserve fraction of remaining supply.

**Follows from** — `I-2` + `I-3` + `I-5`

**If violated** — A borrower can remove liquidity reserved for senior obligations.

#### E-3

On-chain: **Yes**

> Withdrawal batches settle FIFO across batches and pro rata within each batch.

**Follows from** — `I-2` + `I-3` + `I-4`

**If violated** — Later or strategically timed withdrawals can receive value ahead of earlier claims.

#### E-4

On-chain: **Yes**

> One wrapper share remains one exact scaled market-token claim; normalized asset value changes only with the market scale factor.

**Follows from** — `I-5` + `I-17` + `X-7`

**If violated** — Wrapper depositors or redeemers can transfer value between share cohorts.

#### E-5

On-chain: **Yes**

> Revolving lender rate equals commitment fee on supply plus annual interest on `min(drawnAmount,totalSupply)` and accrues nothing while closed or empty.

**Follows from** — `I-5` + `I-16`

**If violated** — Lenders or borrowers are charged on the wrong principal base.

#### E-6

On-chain: **Yes**

> Protocol fees are additional to lender interest but can be collected only after paid withdrawal assets remain reserved.

**Follows from** — `I-3` + `E-1`

**If violated** — Fee collection can subordinate already-paid lender claims.

#### E-7

On-chain: **Yes**

> Floor conversion into scaled units never over-credits an acting depositor, transferee, or withdrawal requester.

**Follows from** — `I-1` + `I-2` + `X-7`

**If violated** — Repeated rounding can manufacture scaled claims or wrapper shares.
