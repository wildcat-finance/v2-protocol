# Entry Point Map

> Wildcat V2.5 | Grouped state-changing public and external surfaces at `215f441` (`feat/v2.5-gas-optimizations-reviewed`)

## Protocol Flow Paths

### Setup (ArchController owner)

`registerBorrower()` → `registerControllerFactory()` → `HooksFactory.registerWithArchController()` → `addHooksTemplate()`

### Borrower Origination

`[owner setup above]` → `deployHooksInstance()` → `deployMarket()`  ◄── borrower identity registered; asset not blacklisted; template enabled

### Lender Lifecycle

`[borrower origination above]` → `deposit()` → `transfer()` → `queueWithdrawal()`  ◄── hook access and term/window checks pass
                                                         └─→ [batch expires] → `executeWithdrawal()`

### Borrower Credit Lifecycle

`[lender deposit above]` → `borrow()` → `repay()`
                                  ├─→ `repayAndProcessUnpaidWithdrawalBatches()`
                                  └─→ `closeMarket()`  ◄── borrower funds total debts

### Wrapper Lifecycle

`[market deployment above]` → `Wildcat4626WrapperFactory.createWrapper()` → `deposit()` / `mint()`
                                                                           └─→ `withdraw()` / `redeem()`

### Borrower Identity Migration

`requestBorrowerTransfer()` → `acceptBorrowerTransfer()`  ◄── target identity, principal registration, and sanctions rechecked at acceptance

### Periodic APR Reduction

`PeriodicTermHooks.proposeAnnualInterestBips()` → [response window ends] → `WildcatMarket.executePendingAnnualInterestBipsReduction()`  ◄── no pending withdrawals

---

## Permissionless

### `WildcatMarket.deposit()` / `depositUpTo()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, SphereX guarded; internal deposit path is `nonReentrant` |
| Caller | Lender |
| Parameters | `amount` (user-controlled); trailing hook data (user-controlled) |
| Call chain | `WildcatMarket._depositUpTo()` → sanctions check → `Open/Fixed/PeriodicTermHooks.onDeposit()` → asset `transferFrom()` |
| State modified | lender scaled balance; scaled total supply; accrued state and possibly batch state |
| Value flow | Underlying: lender → market |
| Reentrancy guard | yes |

### `WildcatMarket.repay()` / `repayAndProcessUnpaidWithdrawalBatches()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `nonReentrant`, SphereX guarded |
| Caller | Payer / borrower automation |
| Parameters | `amount`, `maxBatches`, trailing hook data (user-controlled) |
| Call chain | asset `transferFrom()` → repay hook → optional FIFO batch processing → state write |
| State modified | accrued state; revolving drawn amount; withdrawal batch payments/FIFO head |
| Value flow | Underlying: caller → market; amount becomes liquidity or reserved withdrawals |
| Reentrancy guard | yes |

### `WildcatMarket.queueWithdrawal()` / `queueWithdrawalScaled()` / `queueFullWithdrawal()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `nonReentrant`, SphereX guarded |
| Caller | Market-token holder |
| Parameters | normalized or scaled amount (user-controlled); trailing hook data (user-controlled) |
| Call chain | state accrual → queue hook → account scaled balance → withdrawal batch |
| State modified | account balance/status; batch totals; pending scaled withdrawals; possibly batch payment |
| Value flow | No underlying transfer; scaled claim moves from account to batch |
| Reentrancy guard | yes |

### `WildcatMarket.executeWithdrawal()` / `executeWithdrawals()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `nonReentrant`, SphereX guarded |
| Caller | Executor acting for any lender |
| Parameters | account(s), expiry(s), trailing hook data (user-controlled) |
| Call chain | state accrual → pro-rata entitlement → execution hook → sanctions/escrow routing → asset `transfer()` |
| State modified | account withdrawn amount; normalized unclaimed withdrawals; accrued state |
| Value flow | Underlying: market → lender or sanctions escrow |
| Reentrancy guard | yes |

### `WildcatMarket.collectFees()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `nonReentrant`, SphereX guarded |
| Caller | Fee collection executor |
| Parameters | none |
| Call chain | state accrual → withdrawable-fee bound → asset `transfer(feeRecipient)` |
| State modified | accrued protocol fees; accrued state |
| Value flow | Underlying: market → immutable fee recipient |
| Reentrancy guard | yes |

### `WildcatMarket.nukeFromOrbit()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `nonReentrant`, SphereX guarded |
| Caller | Sanctions executor |
| Parameters | account and trailing hook data (user-controlled) |
| Call chain | sentinel status → nuke hook → full scaled queue withdrawal |
| State modified | sanctioned account balance; withdrawal batch/account status; pending withdrawals |
| Value flow | No immediate underlying transfer; claim enters ordinary withdrawal path |
| Reentrancy guard | yes |

### `WildcatMarket.executePendingAnnualInterestBipsReduction()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `nonReentrant`, SphereX guarded |
| Caller | APR proposal executor |
| Parameters | none |
| Call chain | state accrual → periodic hook proposal validation/deletion → APR/reserve application |
| State modified | annual interest; reserve ratio; periodic pending proposal; accrued state |
| Value flow | None |
| Reentrancy guard | yes |

### `WildcatMarket.updateState()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | State-update executor |
| Parameters | none |
| Call chain | interest/fee accrual → expired batch processing → packed state write |
| State modified | scale factor, fees, delinquency, timestamps, batches, pending expiry |
| Value flow | None |
| Reentrancy guard | no external-call guard; state path may query asset balance |

### `WildcatMarket.approve()` / `transfer()` / `transferFrom()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `nonReentrant`, SphereX guarded |
| Caller | Token holder / approved spender |
| Parameters | spender/from/to/amount and trailing hook data (user-controlled) |
| Call chain | allowance update or state accrual → floor scaling → transfer hook → scaled balance move |
| State modified | allowances; sender/recipient scaled balances; accrued state |
| Value flow | Market-token claim: sender → recipient |
| Reentrancy guard | yes |

### `Wildcat4626Wrapper.deposit()` / `mint()`

| Aspect | Detail |
|--------|--------|
| Visibility | public, `nonReentrant` |
| Caller | Market-token holder |
| Parameters | assets/shares and receiver (user-controlled) |
| Call chain | sanctions/solvency/cap reads → market-token `transferFrom()` → scaled-delta verification → share mint |
| State modified | wrapper share supply/balances/allowances; external market-token custody |
| Value flow | Market tokens: caller → wrapper; shares: wrapper → receiver |
| Reentrancy guard | yes |

### `Wildcat4626Wrapper.withdraw()` / `redeem()`

| Aspect | Detail |
|--------|--------|
| Visibility | public, `nonReentrant` |
| Caller | Share owner or approved spender |
| Parameters | assets/shares, receiver, owner (user-controlled) |
| Call chain | sanctions/solvency → allowance → share burn → market-token transfer → scaled-delta verification |
| State modified | wrapper share supply/balances/allowances; external market-token custody |
| Value flow | Shares burned; market tokens: wrapper → receiver |
| Reentrancy guard | yes |

### `Wildcat4626Wrapper.nukeFromOrbit()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `nonReentrant` |
| Caller | Sanctions executor |
| Parameters | sanctioned account and trailing market hook data (user-controlled) |
| Call chain | wrapper sanctions check → forwarded market nuke → sentinel escrow creation → all wrapper shares to escrow |
| State modified | account/escrow wrapper balances; market withdrawal state through forwarded call |
| Value flow | Wrapper shares: sanctioned account → escrow |
| Reentrancy guard | yes |

### `Wildcat4626WrapperFactory.createWrapper()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Wrapper deployment executor |
| Parameters | market (user-controlled, then registry-validated) |
| Call chain | rounding marker probe → market registration/transfer-policy reads → local CREATE2 or legacy factory call → market `registerWrapper()` |
| State modified | local wrapper mapping and market wrapper slot, or legacy factory state |
| Value flow | None |
| Reentrancy guard | no; local mapping is written before market callback and a revert rolls it back |

### `WildcatSanctionsSentinel.overrideSanction()` / `removeSanctionOverride()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Borrower controlling its own namespace |
| Parameters | account (user-controlled) |
| Call chain | direct mapping update |
| State modified | `sanctionOverrides[msg.sender][account]` |
| Value flow | None |
| Reentrancy guard | no external call |

### `WildcatSanctionsSentinel.createEscrow()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Market/wrapper or escrow deployment executor |
| Parameters | borrower, account, asset (user-controlled; deterministic tuple) |
| Call chain | deterministic address → temporary constructor tuple → CREATE2 escrow → borrower override |
| State modified | temporary tuple (set then reset); escrow override |
| Value flow | None at creation |
| Reentrancy guard | no; only known escrow constructor callback occurs |

### `WildcatSanctionsEscrow.releaseEscrow()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Escrow release executor |
| Parameters | none |
| Call chain | sentinel sanctions check → asset balance → asset `transfer(account)` |
| State modified | external token balances only |
| Value flow | Escrowed token: escrow → immutable beneficiary |
| Reentrancy guard | no |

### `HooksFactory.registerWithArchController()` / `pushProtocolFeeBipsUpdates()`

| Aspect | Detail |
|--------|--------|
| Visibility | external; fee push range overload is `nonReentrant` |
| Caller | Registration / fee-update executor |
| Parameters | template and pagination range (user-controlled, storage-bounded) |
| Call chain | ArchController `registerController()` or selected markets `setProtocolFeeBips()` |
| State modified | ArchController registry or existing market protocol-fee state |
| Value flow | None |
| Reentrancy guard | fee push yes; registration no |

### `*RoleProviderFactory.createRoleProvider()` / typed create functions

Applies to AccessList, Merkle, ERC20, ERC4626-assets, ERC721, and ERC1155 factories.

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Provider deployer or hook instance |
| Parameters | typed configuration and caller-scoped salt (user-controlled) |
| Call chain | decode → caller-namespaced CREATE2 → provider constructor → deployment event |
| State modified | New provider contract only; factory retains no authority |
| Value flow | None |
| Reentrancy guard | no |

### Hook callback stubs with no local writes

`onExecuteWithdrawal`, `onBorrow`, `onRepay`, `onNukeFromOrbit`, `onSetMaxTotalSupply`, and `onSetProtocolFeeBips` are externally callable in one or more Open/Fixed/Periodic hook templates without a caller check when their implementation is empty. They modify no hook storage and move no value; stateful deposit/queue/transfer/close/APR paths are listed under Contract-Gated below.

---

## Role-Gated

### Borrower

| Contract | Function | State Modified / Value Flow |
|----------|----------|-----------------------------|
| WildcatMarket | `rescueTokens(token)` | Non-asset/non-market token balance → current borrower |
| WildcatMarket | `borrow(amount)` | Underlying market → borrower; revolving drawn amount; accrued state |
| WildcatMarket | `closeMarket()` | Final liability funding/settlement; `isClosed`, APR, reserves, batches |
| WildcatMarket | `setMaxTotalSupply(value)` | Market cap and accrued state |
| WildcatMarket | `setAnnualInterestAndReserveRatioBips(apr,reserve)` | APR/reserve and hook temporary-reserve/proposal state |
| WildcatMarket | `requestBorrowerTransfer(target)` / `cancelBorrowerTransfer()` | Pending borrower and principal slots |
| Wildcat4626Wrapper | `sweep(token,to)` | Surplus market tokens or arbitrary ERC20 → selected recipient |
| HooksFactory / Revolving | `deployHooksInstance`, `deployMarket`, `deployMarketAndHooks` | Hook/market registries, deployment nonces, CREATE2 contracts, optional origination fee |

### Pending authority

| Contract | Function | Caller restriction | State Modified |
|----------|----------|--------------------|----------------|
| WildcatMarket | `acceptBorrowerTransfer()` | exact pending borrower | current/pending borrower and principal slots |
| BaseAccessControls | `acceptAdministratorTransfer()` | exact pending hook administrator | hook administrator plus factory indexes |
| ManagedRoleProvider | `acceptAdministratorTransfer()` | exact pending provider administrator | provider administrator/pending slot |
| BorrowerIdentityRegistry | `acceptBorrowerAccountPrincipalTransfer(account)` | exact pending principal | principal sets/mapping and pending slot |
| SphereXConfig | `acceptSphereXAdminRole()` | exact pending SphereX admin | SphereX admin/pending slots |

### Contract-gated

| Contract | Function | Caller restriction | State Modified |
|----------|----------|--------------------|----------------|
| WildcatMarket | `registerWrapper(wrapper)` | immutable wrapper factory | canonical wrapper slot |
| WildcatMarket | `setProtocolFeeBips(value)` | creating hooks factory | market protocol fee |
| WildcatArchController | `registerController(controller)` | registered controller factory | controller set / SphereX allowlist |
| WildcatArchController | `registerMarket(market)` | registered controller | market set / SphereX allowlist |
| BaseAccessControls | `grantRole(s)`, `revokeRole(s)` | attached provider / last granting provider | lender credential state |
| HooksFactory / Revolving | `onHooksAdministratorTransferred(...)` | registered hooks instance with state consistency | administrator indexes/mappings |
| Open/Fixed/PeriodicTermHooks | stateful `onDeposit`, `onQueueWithdrawal`, `onTransfer` | configured market | credential cache and known-lender state |
| Fixed/PeriodicTermHooks | `onCloseMarket` | configured market | term/closure/proposal state |
| PeriodicTermHooks | `executePendingAnnualInterestBipsReduction(state)` / APR callback | configured market | pending proposal and temporary reserve state |
| SphereXProtectedRegisteredBase | `changeSphereXEngine(engine)` | immutable ArchController | SphereX engine slot |

---

## Admin-Only

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| WildcatArchController | `registerBorrower`, `removeBorrower` | borrower | borrower set |
| WildcatArchController | `addBlacklist`, `removeBlacklist` | asset | asset blacklist |
| WildcatArchController | `registerControllerFactory`, `removeControllerFactory` | factory | controller-factory set / SphereX allowlist |
| WildcatArchController | `removeController`, `removeMarket` | address | controller/market sets |
| WildcatArchController | `updateSphereXEngineOnRegisteredContracts` | none | registered contracts' engine slots |
| HooksFactory / Revolving | `addHooksTemplate`, `updateHooksTemplateFees`, `disableHooksTemplate` | template/config/fees | template list and details |
| BorrowerIdentityRegistry | `addAccountFactory`, `removeAccountFactory` | account factory | approved factory set |
| BaseAccessControls | `requestAdministratorTransfer`, `cancelAdministratorTransfer`, `setName` | administrator/name | hook authority and metadata |
| BaseAccessControls | `createRoleProvider`, `addRoleProvider`, `removeRoleProvider` | factory/provider/TTL/data | provider arrays and packed metadata |
| BaseAccessControls | `blockFromDeposits`, `unblockFromDeposits` | lender(s) | hook-local block and credential state |
| Open/Fixed/PeriodicTermHooks | `setMinimumDeposit` | market/minimum | market hook configuration |
| FixedTermHooks | `setFixedTermEndTime` | market/time | monotonic fixed-term deadline |
| PeriodicTermHooks | `proposeAnnualInterestBips` | market/APR | pending APR proposal and response bounds |
| AccessListRoleProvider | `addMember(s)`, `removeMember(s)` | accounts | enumerable membership set |
| MerkleRoleProvider | `updateRoot` | root | Merkle root |
| ManagedRoleProvider | `requestAdministratorTransfer`, `cancelAdministratorTransfer` | administrator | provider pending authority |
| SphereXConfig | `transferSphereXAdminRole`, `changeSphereXOperator` | address | SphereX pending admin/operator |
| SphereXConfig | `changeSphereXEngine` | engine | engine slot; operator-gated rather than owner-gated |
