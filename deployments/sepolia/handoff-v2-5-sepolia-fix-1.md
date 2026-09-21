# Wildcat v2-5-sepolia-fix-1 handoff: sepolia

Chain ID: `11155111`. Generated: `2026-08-28T01:02:41.960Z`.

## Factory indexing

| Label | Kind | Market type | Address | Start block | Lifecycle | Index all | ABI artifact |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| legacy-v2 | hooks-factory | legacy | `0xE3e4B7C9E0Ab4ccbC70e0583Dca7B4Db9B4CFD88` | 6973842 | live | yes | `src/IHooksFactory.sol:IHooksFactory` |
| standard-v2-1 | hooks-factory | legacy | `0x10A64ABa0159720F8a23E1A552800CA4eb21576C` | 7124440 | live | yes | `src/IHooksFactory.sol:IHooksFactory` |
| revolving-sepolia-20260419-233246 | hooks-factory | revolving | `0xF4564015E524cf5629828E61F45ed339D998D85f` | 10695521 | retired | no | `src/IHooksFactoryRevolving.sol:IHooksFactoryRevolving` |
| revolving-sepolia-20260424-140119 | hooks-factory | revolving | `0xb899ba2a5F5b609898A2bABe445Aa31dDf0277e5` | 10725492 | live | yes | `src/IHooksFactoryRevolving.sol:IHooksFactoryRevolving` |
| standard-v2-5-preview-20260727 | hooks-factory | legacy | `0xAa9BbaE0D519e85B6aBEA81aD3C2cBeBfA57696C` | 11363908 | live | yes | `src/IHooksFactory.sol:IHooksFactory` |
| revolving-v2-5-preview-20260727 | hooks-factory | revolving | `0x76Fe050d91940a72133e1819BF34c1042d8DBe73` | 11363912 | live | yes | `src/IHooksFactoryRevolving.sol:IHooksFactoryRevolving` |
| legacy-test-2024-08-05 | hooks-factory | legacy | `0x6Cb3512b541733d340Aa520b63105586588BD600` | 6443857 | retired | no | `src/IHooksFactory.sol:IHooksFactory` |
| legacy-test-2024-09-23 | hooks-factory | legacy | `0xE1d14E8176d27415c204A4F9Ef58E107964CA12C` | 6746262 | retired | no | `src/IHooksFactory.sol:IHooksFactory` |
| legacy-test-2024-11-21 | hooks-factory | legacy | `0xCf872Ac862d2ba97F99804ed25f0dB5F2352933a` | 7123486 | retired | no | `src/IHooksFactory.sol:IHooksFactory` |
| HooksFactory_v2-5 | hooks-factory | legacy | `0xbFbDaFc91977eE599a61B30D9e75788565Ad6d18` | 11559133 | live | yes | `src/IHooksFactory.sol:IHooksFactory` |
| HooksFactoryRevolving_v2-5 | hooks-factory | revolving | `0x190B42942fe9492df9CeA441dA5c43309840E93A` | 11559137 | live | yes | `src/IHooksFactoryRevolving.sol:IHooksFactoryRevolving` |
| HooksFactory_v2-5-sepolia-fix-1 | hooks-factory | legacy | `0x89797b782cA5b4BBFC975146B98ba3941Fe26C56` | 11581361 | canonical | yes | `src/IHooksFactory.sol:IHooksFactory` |
| HooksFactoryRevolving_v2-5-sepolia-fix-1 | hooks-factory | revolving | `0xb3FBD4FBeb1EE4BEE7afdbC4A75C7c4E97CF105C` | 11581363 | canonical | yes | `src/IHooksFactoryRevolving.sol:IHooksFactoryRevolving` |
| wrapper-v1 | wrapper-factory | - | `0x0566Fe57682164af689f1440cb3BCEedEe3bf843` | 10534112 | live | yes | `src/vault/Wildcat4626WrapperFactory.sol:IWildcat4626WrapperFactoryV1` |
| Wildcat4626WrapperFactory_v2-5 | wrapper-factory | - | `0x6B1DD93453584346C530A1646e98aB306fD6D37C` | 11559124 | live | yes | `src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory` |
| Wildcat4626WrapperFactory_v2-5-sepolia-fix-1 | wrapper-factory | - | `0x31D8D5564Ce11f764E74beca5B4e8d363046949f` | 11581359 | canonical | yes | `src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory` |

## Routing

- Use canonical lifecycle records for new deployments and SDK routing. Continue indexing every generation with indexAll=true. Do not index records with indexAll=false; they remain in the append-only inventory.
- 4626: The canonical v2.5 facade serves locally recorded v2.5 floor-rounding markets. Markets without scaledTransferRounding() fall through to v1Factory when configured. Markets declaring an unsupported rounding do not fall through.
- Lens: Treat MarketLens as the public facade. It static-calls the core, aggregation, or live helper selected by the requested method; helper addresses are implementation contracts, not replacement facade addresses.
- Lifecycle: Canonical means the generation selected for new deployments and current aliases. Live means an older generation that remains indexed for its existing markets. Retired generations stay recorded but are excluded from indexing.

## Release contracts

| Deployment key | Kind | Address | Start block | ABI artifact |
| --- | --- | --- | ---: | --- |
| WildcatBorrowerIdentityRegistry_v2-5-sepolia-fix-1 | borrower-identity-registry | `0xc2cF90781595203D1e75c28246b306C95d4b8b21` | - | `src/interfaces/IBorrowerIdentityRegistry.sol:IBorrowerIdentityRegistry` |
| AccessListRoleProviderFactory_v2-5-sepolia-fix-1 | role-provider-factory | `0x92995EA2ba572E4Cb8bB41E30f813BeB77FD4974` | - | `src/providers/IAccessListRoleProviderFactory.sol:IAccessListRoleProviderFactory` |
| WildcatMarket_initCodeStorage_v2-5-sepolia-fix-1 | market-init-code-storage | `0x0514795F0A7CBb754f0B7Da92e1B2ce2FD13Bd90` | 11581360 | `src/market/WildcatMarket.sol:WildcatMarket` |
| HooksFactory_v2-5-sepolia-fix-1 | hooks-factory | `0x89797b782cA5b4BBFC975146B98ba3941Fe26C56` | 11581361 | `src/IHooksFactory.sol:IHooksFactory` |
| WildcatMarketRevolving_initCodeStorage_v2-5-sepolia-fix-1 | market-init-code-storage | `0x3B6eBDb29c937340568Ee90a4577BB0bB7535447` | 11581362 | `src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving` |
| HooksFactoryRevolving_v2-5-sepolia-fix-1 | hooks-factory | `0xb3FBD4FBeb1EE4BEE7afdbC4A75C7c4E97CF105C` | 11581363 | `src/IHooksFactoryRevolving.sol:IHooksFactoryRevolving` |
| MarketLensCore_v2-5-sepolia-fix-1 | lens-helper-core | `0xa12e227A67e4678A2428eD550df9564C7aFfB76E` | 11581364 | `src/lens/MarketLensCore.sol:MarketLensCore` |
| MarketLensAggregator_v2-5-sepolia-fix-1 | lens-helper-aggregator | `0xf86A8C0a7A167b695cF7E7eE2e1950Ddd0e4eD06` | 11581365 | `src/lens/MarketLensAggregator.sol:MarketLensAggregator` |
| MarketLensLive_v2-5-sepolia-fix-1 | lens-helper-live | `0x7491353fC4BB349c41f43122aaF9993cDa8E4dc3` | 11581366 | `src/lens/MarketLensLive.sol:MarketLensLive` |
| MarketLens_v2-5-sepolia-fix-1 | lens-facade | `0x3e0A214d105463719F18DaA850246E770c9c7BDb` | 11581367 | `src/lens/MarketLens.sol:MarketLens` |
| Wildcat4626WrapperFactory_v2-5-sepolia-fix-1 | wrapper-factory | `0x31D8D5564Ce11f764E74beca5B4e8d363046949f` | 11581359 | `src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory` |
| OpenTermHooks_initCodeStorage_v2-5-sepolia-fix-1 | hooks-template-init-code-storage | `0xae00f2c2fd926007beF2EeC2B2204A4c3528b401` | 11581368 | `src/access/OpenTermHooks.sol:OpenTermHooks` |
| FixedTermHooks_initCodeStorage_v2-5-sepolia-fix-1 | hooks-template-init-code-storage | `0xEB2f6c7DF8b760542e5b4ba509f4347252bdE4b8` | 11581369 | `src/access/FixedTermHooks.sol:FixedTermHooks` |
| PeriodicTermHooks_initCodeStorage_v2-5-sepolia-fix-1 | hooks-template-init-code-storage | `0x931329D440E66f22F1CcDCe73C1049DBf5C35659` | 11581371 | `src/access/PeriodicTermHooks.sol:PeriodicTermHooks` |

## ABI changes since deployed v2

### WildcatMarket and WildcatMarketRevolving

- Changed: version() return value changed from '2' to '2.5'.
- Added: borrower(), borrowerPrincipal(), borrowerIdentityRegistry(), pendingBorrower(), pendingBorrowerPrincipal(), requestBorrowerTransfer(address), cancelBorrowerTransfer(), and acceptBorrowerTransfer().
- Added: wrapperFactory(), registerWrapper(address), and registeredWrapper().
- Added: WrapperRegistered(address) event plus NotWrapperFactory, WrapperAlreadyRegistered, and CannotNukeWrapper errors.
- Added: queueWithdrawalScaled(uint256) queues an exact scaled withdrawal amount.
- Added: scaledTransferRounding() returns keccak256('scaleAmountDown').
- Added: executePendingAnnualInterestBipsReduction() applies a matured hooks proposal.
- Added: AprReductionNotReduction error.
- Added: ExecutePendingAprReductionNotEnabled error.
- Added: WithdrawalBatchKeyAlreadyExists error.
- Removed: NullBuyBackAmount and BuyBackOnDelinquentMarket errors.

### Borrower identity registry

- Added: Principal resolution for direct borrowers and borrower accounts.
- Added: Account-factory registration and account-to-principal association events.
- Added: Two-step borrower-account principal transfers.

### Access-list role-provider factory

- Added: Permissionless deterministic deployment of borrower-administered access-list providers.
- Added: Two-step provider administrator transfers and enumerable membership management.

### HooksFactory and HooksFactoryRevolving

- Changed: HooksTemplateAdded, HooksTemplateDisabled, and HooksTemplateFeesUpdated identify the caller and preserve complete fee history.
- Changed: HooksInstanceDeployed identifies the template, administrator, deployer, name, and version.
- Changed: MarketDeployed identifies borrower, principal, identity registry, requested hooks, and accepted hooks; configuration and hook payload move to companion events.
- Changed: getMarketParameters() includes the borrower identity registry and wrapper factory.
- Added: HooksInstanceRoleProviders, HooksInstanceAdministratorTransferred, MarketDeploymentConfig, MarketHooksData, and RevolvingMarketDeployed events.
- Added: borrowerIdentityRegistry(), wrapperFactory(), hook-administrator indexing, and administrator-transfer callback views.

### PeriodicTermHooks

- Added: AnnualInterestBipsReductionProposed event.
- Added: AnnualInterestBipsReductionProposalCancelled event.
- Added: AnnualInterestBipsReductionExecuted event.
- Added: AprReductionProposalDuringWithdrawalWindow error.
- Added: AprReductionProposalNotReduction error.
- Added: NoPendingAprChange error.
- Added: AprChangeDoesNotMatchProposal error.
- Added: AprChangeNotReady error.
- Added: AprReductionProposalExpired error.
- Added: AprReductionProposalOnClosedMarket error.
- Added: UnpaidWithdrawalsExist error.
- Added: templateVersion() returns 2; version() remains 'PeriodicTermHooks'.
- Added: pendingAprChanges(address), getHookedMarket(address), getHookedMarkets(address[]), isWithdrawalWindowOpen(address), and getPendingAprChange(address) views.

### Access-control hook templates

- Added: administrator(), pendingAdministrator(), requestAdministratorTransfer(address), cancelAdministratorTransfer(), and acceptAdministratorTransfer().
- Added: AdministratorTransferRequested, AdministratorTransferCancelled, and AdministratorTransferred events.
- Added: RoleProviderAdded, RoleProviderUpdated, and RoleProviderRemoved carry administrator, TTL, and complete pull/push index history.
- Added: AccountAccessGranted and AccountAccessRevoked identify provider, account, and caller.
- Added: NameUpdated, MinimumDepositUpdated, FixedTermUpdated, and PeriodicTermUpdated carry actor plus previous/new state where applicable.
- Added: isMarketTransferDisabled(address) reports the immutable per-market transfer policy.
- Added: DepositHookNotEnabled error.

### MarketLens

- Changed: HooksConfigData return tuples append useOnExecutePendingAnnualInterestBipsReduction; consumers must regenerate ABI tuple decoders.
- Added: Borrower, principal, pending borrower, hook administrator, provider administration, transfer policy, wrapper, and revolving-credit state in the v2.5 market and hooks views.
- Added: Core, aggregation, and live helper routing behind the MarketLens facade.

### Wildcat4626WrapperFactory

- Added: v1Factory(), wrapperForMarket(address), createWrapper(address), isFloorRoundingMarket(address), and WrapperDeployed(address,address).
- Added: WrapperAlreadyExists, LegacyMarketsNotSupported, UnsupportedMarketRounding, NotRegisteredMarket, InvalidV1Factory, and ZeroAddress errors.
- Added: MarketTransfersDisabled(address) error.
- Added: UnsupportedMarketTransferPolicy(address,address) error.

### WildcatMarketRevolving

- Added: commitmentFeeBips() view.
- Added: drawnAmount() view.
- Added: DrawnAmountUpdated(uint256,uint256) event.

### Market event surface

- Changed: MaxTotalSupplyUpdated, ProtocolFeeBipsUpdated, Borrow, MarketClosed, and FeesCollected identify the acting borrower, caller, collector, or fee recipient and preserve previous/new values where applicable.
- Changed: AnnualInterestBipsUpdated and ReserveRatioBipsUpdated are replaced by the atomic AnnualInterestAndReserveRatioBipsUpdated event.
- Added: BorrowerTransferRequested, BorrowerTransferCancelled, and BorrowerTransferred events preserve operational borrower and principal history.
- Added: WrapperRegistered(address) event.
- Removed: AccountSanctioned event.
- Removed: SanctionedAccountAssetsSentToEscrow event.
