// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { HookedMarket } from 'src/access/FixedTermHooks.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { CreateProviderInputs } from 'src/access/ProviderStructs.sol';
import { ExistingProviderInputs } from 'src/access/ProviderStructs.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketParameterConstraints } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { RAY } from 'src/libraries/MathUtils.sol';
import { Bit_Enabled_CloseMarket } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetAnnualInterestAndReserveRatioBips } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';
import { NullProviderIndex } from 'src/types/RoleProvider.sol';
import { RoleProvider } from 'src/types/RoleProvider.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { MockRoleProviderFactory } from '../mocks/MockRoleProviderFactory.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract FixedTermHooksTest is TestKernel {
  address internal constant MarketA = address(0x2001);
  address internal constant MarketB = address(0x2002);
  address internal constant MarketC = address(0x2003);
  address internal constant MarketD = address(0x2004);
  address internal constant Lender = address(0xA11CE);
  address internal constant SecondLender = address(0xB0B);
  address internal constant ThirdLender = address(0xCA401);
  address internal constant NewAdministrator = address(0xAD011);

  bytes4 internal constant PanicSelector = 0x4e487b71;
  uint256 internal constant PanicArithmetic = 0x11;

  FixedTermHooks internal hooks;
  MockRoleProvider internal provider1;
  MockRoleProvider internal provider2;
  MockRoleProviderFactory internal providerFactory;
  mapping(address account => bool registered) internal registeredBorrowers;
  address internal callbackPreviousAdministrator;
  address internal callbackNewAdministrator;

  function setUp() external {
    registeredBorrowers[address(this)] = true;
    provider1 = MockRoleProvider(
      _deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider')
    );
    provider2 = MockRoleProvider(
      _deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider')
    );
    providerFactory = MockRoleProviderFactory(
      _deployCode('test/mocks/MockRoleProviderFactory.sol:MockRoleProviderFactory')
    );
    NameAndProviderInputs memory inputs;
    hooks = _newHooks(address(this), inputs);
  }

  function archController() external view returns (address) {
    return address(this);
  }

  function isRegisteredBorrower(address account) external view returns (bool) {
    return registeredBorrowers[account];
  }

  function onHooksAdministratorTransferred(
    address previousAdministrator,
    address newAdministrator
  ) external {
    assertEq(msg.sender, address(hooks), 'callback caller');
    callbackPreviousAdministrator = previousAdministrator;
    callbackNewAdministrator = newAdministrator;
  }

  function _newHooks(
    address administrator,
    NameAndProviderInputs memory inputs
  ) internal returns (FixedTermHooks deployed) {
    deployed = FixedTermHooks(
      _deployCode(
        'src/access/FixedTermHooks.sol:FixedTermHooks',
        abi.encode(administrator, abi.encode(inputs))
      )
    );
  }

  function _term() internal view returns (uint32) {
    return uint32(block.timestamp + 365 days);
  }

  function _requestedConfig(
    FixedTermHooks target,
    bool deposit,
    bool queueWithdrawal,
    bool transfer
  ) internal pure returns (HooksConfig config) {
    config = EmptyHooksConfig.setHooksAddress(address(target));
    if (deposit) config = config.setFlag(Bit_Enabled_Deposit);
    if (queueWithdrawal) config = config.setFlag(Bit_Enabled_QueueWithdrawal);
    if (transfer) config = config.setFlag(Bit_Enabled_Transfer);
  }

  function _createMarket(
    FixedTermHooks target,
    address market,
    HooksConfig requestedConfig,
    bytes memory hooksData
  ) internal returns (HooksConfig effectiveConfig) {
    DeployMarketInputs memory inputs;
    inputs.hooks = requestedConfig;
    effectiveConfig = target.onCreateMarket(address(this), market, inputs, hooksData);
  }

  function _assertConfig(
    HooksConfig actual,
    HooksConfig expected,
    string memory message
  ) internal pure {
    assertEq(HooksConfig.unwrap(actual), HooksConfig.unwrap(expected), message);
  }

  function _assertProvider(
    FixedTermHooks target,
    address providerAddress,
    uint32 timeToLive,
    bool isPullProvider,
    uint24 providerIndex
  ) internal view {
    RoleProvider provider = target.getRoleProvider(providerAddress);
    assertEq(provider.providerAddress(), providerAddress, 'provider address');
    assertEq(provider.timeToLive(), timeToLive, 'provider ttl');
    assertEq(
      provider.pullProviderIndex(),
      isPullProvider ? providerIndex : NullProviderIndex,
      'pull index'
    );
    assertEq(
      provider.pushProviderIndex(),
      isPullProvider ? NullProviderIndex : providerIndex,
      'push index'
    );
    RoleProvider[] memory providers = isPullProvider
      ? target.getPullProviders()
      : target.getPushProviders();
    assertEq(providers[providerIndex].providerAddress(), providerAddress, 'provider list');
  }

  function _assertHookedMarket(
    FixedTermHooks target,
    address market,
    bool transferRequiresAccess,
    bool depositRequiresAccess,
    bool withdrawalRequiresAccess,
    uint128 minimumDeposit,
    uint32 fixedTermEndTime,
    bool transfersDisabled,
    bool allowClosureBeforeTerm,
    bool allowTermReduction
  ) internal view {
    HookedMarket memory config = target.getHookedMarket(market);
    assertTrue(config.isHooked, 'is hooked');
    assertEq(config.transferRequiresAccess, transferRequiresAccess, 'transfer access');
    assertEq(config.depositRequiresAccess, depositRequiresAccess, 'deposit access');
    assertEq(config.withdrawalRequiresAccess, withdrawalRequiresAccess, 'withdrawal access');
    assertEq(config.minimumDeposit, minimumDeposit, 'minimum deposit');
    assertEq(config.fixedTermEndTime, fixedTermEndTime, 'term end');
    assertEq(config.transfersDisabled, transfersDisabled, 'transfers disabled');
    assertEq(config.allowClosureBeforeTerm, allowClosureBeforeTerm, 'early close');
    assertEq(config.allowTermReduction, allowTermReduction, 'term reduction');
  }

  function _addPullProvider(FixedTermHooks target) internal {
    provider1.setIsPullProvider(true);
    target.addRoleProvider(address(provider1), type(uint32).max);
  }

  function _credentialData(bytes memory credential) internal view returns (bytes memory) {
    return abi.encodePacked(address(provider1), credential);
  }

  function test_metadataConfigAndConstraints_AreCanonical() external view {
    assertEq(hooks.factory(), address(this), 'factory');
    assertEq(hooks.administrator(), address(this), 'administrator');
    assertEq(hooks.version(), 'FixedTermHooks', 'version');
    assertEq(hooks.MaximumLoanTerm(), 365 days, 'maximum loan term');

    HooksConfig optionalFlags = EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(
      Bit_Enabled_Transfer
    );
    HooksConfig requiredFlags = EmptyHooksConfig
      .setFlag(Bit_Enabled_QueueWithdrawal)
      .setFlag(Bit_Enabled_CloseMarket)
      .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips);
    HooksDeploymentConfig expectedConfig = encodeHooksDeploymentConfig(
      optionalFlags,
      requiredFlags
    );
    assertEq(
      HooksDeploymentConfig.unwrap(hooks.config()),
      HooksDeploymentConfig.unwrap(expectedConfig),
      'deployment config'
    );

    MarketParameterConstraints memory constraints = hooks.getParameterConstraints();
    assertEq(constraints.minimumDelinquencyGracePeriod, 0, 'minimum grace period');
    assertEq(constraints.maximumDelinquencyGracePeriod, 90 days, 'maximum grace period');
    assertEq(constraints.minimumReserveRatioBips, 0, 'minimum reserve ratio');
    assertEq(constraints.maximumReserveRatioBips, 10_000, 'maximum reserve ratio');
    assertEq(constraints.minimumDelinquencyFeeBips, 0, 'minimum delinquency fee');
    assertEq(constraints.maximumDelinquencyFeeBips, 10_000, 'maximum delinquency fee');
    assertEq(constraints.minimumWithdrawalBatchDuration, 0, 'minimum batch duration');
    assertEq(constraints.maximumWithdrawalBatchDuration, 365 days, 'maximum batch duration');
    assertEq(constraints.minimumAnnualInterestBips, 0, 'minimum APR');
    assertEq(constraints.maximumAnnualInterestBips, 10_000, 'maximum APR');
  }

  function test_constructor_InitializesEveryProviderShape(
    bool firstIsPull,
    bool secondIsPull,
    uint32 firstTtl,
    uint32 secondTtl
  ) external {
    provider1.setIsPullProvider(firstIsPull);
    provider2.setIsPullProvider(secondIsPull);

    _assertExistingProviderConstructor(firstIsPull, secondIsPull, firstTtl, secondTtl);
    _assertNewProviderConstructor(firstIsPull, secondIsPull, firstTtl, secondTtl);
    _assertMixedProviderConstructor(firstIsPull, secondIsPull, firstTtl, secondTtl);
  }

  function _assertExistingProviderConstructor(
    bool firstIsPull,
    bool secondIsPull,
    uint32 firstTtl,
    uint32 secondTtl
  ) internal {
    NameAndProviderInputs memory existingInputs;
    existingInputs.name = 'existing providers';
    existingInputs.existingProviders = new ExistingProviderInputs[](2);
    existingInputs.existingProviders[0] = ExistingProviderInputs(address(provider1), firstTtl);
    existingInputs.existingProviders[1] = ExistingProviderInputs(address(provider2), secondTtl);
    FixedTermHooks existing = _newHooks(address(this), existingInputs);
    _assertProvider(existing, address(provider1), firstTtl, firstIsPull, 0);
    _assertProvider(
      existing,
      address(provider2),
      secondTtl,
      secondIsPull,
      firstIsPull == secondIsPull ? 1 : 0
    );
    assertEq(existing.name(), existingInputs.name, 'existing name');
  }

  function _assertNewProviderConstructor(
    bool firstIsPull,
    bool secondIsPull,
    uint32 firstTtl,
    uint32 secondTtl
  ) internal {
    NameAndProviderInputs memory newInputs;
    newInputs.name = 'new providers';
    newInputs.roleProviderFactory = address(providerFactory);
    newInputs.newProviderInputs = new CreateProviderInputs[](2);
    newInputs.newProviderInputs[0] = CreateProviderInputs(
      firstTtl,
      abi.encode(bytes32(uint256(1)), firstIsPull)
    );
    newInputs.newProviderInputs[1] = CreateProviderInputs(
      secondTtl,
      abi.encode(bytes32(uint256(2)), secondIsPull)
    );
    address firstNewProvider = providerFactory.computeProviderAddress(bytes32(uint256(1)));
    address secondNewProvider = providerFactory.computeProviderAddress(bytes32(uint256(2)));
    FixedTermHooks created = _newHooks(address(this), newInputs);
    _assertProvider(created, firstNewProvider, firstTtl, firstIsPull, 0);
    _assertProvider(
      created,
      secondNewProvider,
      secondTtl,
      secondIsPull,
      firstIsPull == secondIsPull ? 1 : 0
    );
    assertEq(created.name(), newInputs.name, 'new name');
  }

  function _assertMixedProviderConstructor(
    bool firstIsPull,
    bool secondIsPull,
    uint32 firstTtl,
    uint32 secondTtl
  ) internal {
    NameAndProviderInputs memory mixedInputs;
    mixedInputs.name = 'mixed providers';
    mixedInputs.roleProviderFactory = address(providerFactory);
    mixedInputs.existingProviders = new ExistingProviderInputs[](1);
    mixedInputs.existingProviders[0] = ExistingProviderInputs(address(provider1), firstTtl);
    mixedInputs.newProviderInputs = new CreateProviderInputs[](1);
    mixedInputs.newProviderInputs[0] = CreateProviderInputs(
      secondTtl,
      abi.encode(bytes32(uint256(3)), secondIsPull)
    );
    address mixedNewProvider = providerFactory.computeProviderAddress(bytes32(uint256(3)));
    FixedTermHooks mixed = _newHooks(address(this), mixedInputs);
    _assertProvider(mixed, address(provider1), firstTtl, firstIsPull, 0);
    _assertProvider(
      mixed,
      mixedNewProvider,
      secondTtl,
      secondIsPull,
      firstIsPull == secondIsPull ? 1 : 0
    );
    assertEq(mixed.name(), mixedInputs.name, 'mixed name');
  }

  function test_constructor_RejectsFailedProviderCreation() external {
    providerFactory.setNextProviderAddress(address(0));
    NameAndProviderInputs memory inputs;
    inputs.roleProviderFactory = address(providerFactory);
    inputs.newProviderInputs = new CreateProviderInputs[](1);
    vm.expectRevert(BaseAccessControls.CreateRoleProviderFailed.selector);
    _newHooks(address(this), inputs);
  }

  function test_onCreateMarket_AuthenticatesAndValidatesTermData() external {
    DeployMarketInputs memory inputs;
    vm.prank(address(0xBAD));
    vm.expectRevert(IHooks.CallerNotFactory.selector);
    hooks.onCreateMarket(address(this), MarketA, inputs, '');

    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.onCreateMarket(address(0xBAD), MarketA, inputs, abi.encode(_term()));

    vm.expectRevert(FixedTermHooks.FixedTermNotProvided.selector);
    hooks.onCreateMarket(address(this), MarketA, inputs, '');

    vm.expectRevert(FixedTermHooks.InvalidFixedTerm.selector);
    hooks.onCreateMarket(address(this), MarketA, inputs, abi.encode(uint32(block.timestamp - 1)));

    vm.expectRevert(FixedTermHooks.InvalidFixedTerm.selector);
    hooks.onCreateMarket(
      address(this),
      MarketA,
      inputs,
      abi.encode(uint32(block.timestamp + 365 days + 1))
    );

    inputs.hooks = _requestedConfig(hooks, false, false, false);
    vm.expectRevert(abi.encodePacked(PanicSelector, PanicArithmetic));
    hooks.onCreateMarket(address(this), MarketA, inputs, abi.encode(_term(), type(uint136).max));

    _createMarket(
      hooks,
      MarketD,
      _requestedConfig(hooks, false, false, false),
      abi.encode(uint32(block.timestamp))
    );
    assertEq(hooks.getHookedMarket(MarketD).fixedTermEndTime, block.timestamp, 'zero term');
  }

  function test_onCreateMarket_ConfigMatrix(
    bool deposit,
    bool queueWithdrawal,
    bool transfer,
    uint128 minimumDeposit,
    bool transfersDisabled,
    bool allowClosureBeforeTerm,
    bool allowTermReduction
  ) external {
    HooksConfig requested = _requestedConfig(hooks, deposit, queueWithdrawal, transfer);
    bytes memory hooksData = abi.encode(
      _term(),
      minimumDeposit,
      transfersDisabled,
      allowClosureBeforeTerm,
      allowTermReduction
    );
    if (queueWithdrawal && (!deposit || (!transfersDisabled && !transfer))) {
      vm.expectRevert(FixedTermHooks.InvalidAccessConfiguration.selector);
      _createMarket(hooks, MarketA, requested, hooksData);
      return;
    }

    HooksConfig actual = _createMarket(hooks, MarketA, requested, hooksData);
    HooksConfig expected = requested;
    if (minimumDeposit > 0) expected = expected.setFlag(Bit_Enabled_Deposit);
    if (transfersDisabled) expected = expected.setFlag(Bit_Enabled_Transfer);
    if (queueWithdrawal) {
      expected = expected.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer);
    }
    expected = expected
      .setFlag(Bit_Enabled_QueueWithdrawal)
      .setFlag(Bit_Enabled_CloseMarket)
      .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips);
    _assertConfig(actual, expected, 'effective config');
    _assertHookedMarket(
      hooks,
      MarketA,
      transfer,
      deposit,
      queueWithdrawal,
      minimumDeposit,
      _term(),
      transfersDisabled,
      allowClosureBeforeTerm,
      allowTermReduction
    );
    assertEq(hooks.isMarketTransferDisabled(MarketA), transfersDisabled, 'transfer-disabled query');

    address[] memory markets = new address[](2);
    markets[0] = MarketA;
    markets[1] = MarketB;
    HookedMarket[] memory configs = hooks.getHookedMarkets(markets);
    assertEq(configs.length, 2, 'market count');
    assertEq(configs[0].fixedTermEndTime, _term(), 'batch term');
    assertFalse(configs[1].isHooked, 'unknown batch market');
  }

  function test_administratorTransfer_PreservesMarketConfigurationAndMovesAuthority() external {
    uint32 term = _term();
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(term, uint128(100), true, true, true)
    );
    bytes32 configBefore = keccak256(abi.encode(hooks.getHookedMarket(MarketA)));
    registeredBorrowers[NewAdministrator] = true;
    hooks.requestAdministratorTransfer(NewAdministrator);
    vm.prank(NewAdministrator);
    hooks.acceptAdministratorTransfer();

    assertEq(hooks.administrator(), NewAdministrator, 'administrator');
    assertEq(callbackPreviousAdministrator, address(this), 'callback previous administrator');
    assertEq(callbackNewAdministrator, NewAdministrator, 'callback new administrator');
    assertEq(keccak256(abi.encode(hooks.getHookedMarket(MarketA))), configBefore, 'market config');
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.setMinimumDeposit(MarketA, 200);
    vm.prank(NewAdministrator);
    hooks.setMinimumDeposit(MarketA, 200);
    assertEq(hooks.getHookedMarket(MarketA).minimumDeposit, 200, 'updated minimum');
  }

  function test_setMinimumDeposit_EnforcesMarketDispatchAndAuthority() external {
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(_term(), uint128(100))
    );
    vm.expectEmit(address(hooks));
    emit FixedTermHooks.MinimumDepositUpdated(MarketA, address(this), 100, 200);
    hooks.setMinimumDeposit(MarketA, 200);
    assertEq(hooks.getHookedMarket(MarketA).minimumDeposit, 200, 'updated minimum');

    _createMarket(
      hooks,
      MarketB,
      _requestedConfig(hooks, false, false, false),
      abi.encode(_term())
    );
    vm.expectRevert(FixedTermHooks.DepositHookNotEnabled.selector);
    hooks.setMinimumDeposit(MarketB, 1);
    hooks.setMinimumDeposit(MarketB, 0);

    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    hooks.setMinimumDeposit(MarketC, 1);
    vm.prank(address(0xBAD));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.setMinimumDeposit(MarketA, 1);
  }

  function test_setFixedTermEndTime_EnforcesReductionPolicyAndAuthority() external {
    uint32 term = _term();
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(term, uint128(0), false, false, true)
    );
    vm.expectEmit(address(hooks));
    emit FixedTermHooks.FixedTermUpdated(MarketA, address(this), term, term - 1 days);
    hooks.setFixedTermEndTime(MarketA, term - 1 days);
    assertEq(hooks.getHookedMarket(MarketA).fixedTermEndTime, term - 1 days, 'reduced term');

    vm.expectRevert(FixedTermHooks.IncreaseFixedTerm.selector);
    hooks.setFixedTermEndTime(MarketA, term);

    _createMarket(hooks, MarketB, _requestedConfig(hooks, false, false, false), abi.encode(term));
    vm.expectRevert(FixedTermHooks.TermReductionDisabled.selector);
    hooks.setFixedTermEndTime(MarketB, term - 1 days);

    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    hooks.setFixedTermEndTime(MarketC, 0);
    vm.prank(address(0xBAD));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.setFixedTermEndTime(MarketA, 0);
  }

  function test_unhookedMarketEndpoints_Reject() external {
    MarketState memory state;
    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    hooks.onDeposit(Lender, 0, state, '');
    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    hooks.onTransfer(Lender, Lender, SecondLender, 0, state, '');
    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    hooks.onCloseMarket(state, '');
    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    hooks.isMarketTransferDisabled(MarketA);
    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    hooks.isMarketTransferRecipientAllowed(MarketA, Lender);
  }

  function test_onDeposit_EnforcesMinimumBlockAndCredentialPolicies() external {
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(_term(), uint128(100))
    );
    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    vm.prank(MarketA);
    vm.expectRevert(FixedTermHooks.DepositBelowMinimum.selector);
    hooks.onDeposit(Lender, 99, state, '');
    vm.prank(MarketA);
    hooks.onDeposit(Lender, 100, state, '');
    assertFalse(hooks.isKnownLenderOnMarket(Lender, MarketA), 'open-deposit known lender');

    hooks.blockFromDeposits(Lender);
    vm.prank(MarketA);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onDeposit(Lender, 100, state, '');

    _createMarket(hooks, MarketB, _requestedConfig(hooks, true, false, false), abi.encode(_term()));
    vm.prank(MarketB);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onDeposit(SecondLender, 1, state, '');

    _addPullProvider(hooks);
    bytes memory credential = abi.encode('deposit');
    provider1.approveCredentialData(keccak256(credential), uint32(block.timestamp));
    vm.prank(MarketB);
    hooks.onDeposit(SecondLender, 1, state, _credentialData(credential));
    assertTrue(hooks.isKnownLenderOnMarket(SecondLender, MarketB), 'restricted known lender');
  }

  function test_onQueueWithdrawal_EnforcesTermAndRequestedAccess() external {
    uint32 term = _term();
    _createMarket(hooks, MarketA, _requestedConfig(hooks, false, false, false), abi.encode(term));
    MarketState memory state;
    vm.prank(MarketA);
    vm.expectRevert(FixedTermHooks.WithdrawBeforeTermEnd.selector);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');

    _createMarket(hooks, MarketB, _requestedConfig(hooks, true, true, true), abi.encode(term));
    _addPullProvider(hooks);
    vm.prank(address(provider1));
    hooks.grantRole(Lender, uint32(block.timestamp));
    state.scaleFactor = uint112(RAY);
    vm.prank(MarketB);
    hooks.onDeposit(Lender, 1, state, '');
    vm.prank(address(provider1));
    hooks.revokeRole(Lender);

    vm.warp(term);
    vm.prank(MarketA);
    hooks.onQueueWithdrawal(ThirdLender, 0, 1, state, '');
    vm.prank(MarketB);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');

    vm.prank(MarketB);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onQueueWithdrawal(SecondLender, 0, 1, state, '');
    bytes memory credential = abi.encode('fixed-term queue');
    provider1.approveCredentialData(keccak256(credential), uint32(block.timestamp));
    vm.prank(MarketB);
    hooks.onQueueWithdrawal(SecondLender, 0, 1, state, _credentialData(credential));
    LenderStatus memory status = hooks.getPreviousLenderStatus(SecondLender);
    assertEq(status.lastProvider, address(provider1), 'last provider');
    assertEq(status.lastApprovalTimestamp, uint32(block.timestamp), 'approval timestamp');
    assertFalse(hooks.isKnownLenderOnMarket(SecondLender, MarketB), 'withdrawal known lender');
  }

  function test_onTransfer_EnforcesDisabledAndCredentialPolicies() external {
    uint32 term = _term();
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, true, true, false),
      abi.encode(term, uint128(0), true)
    );
    MarketState memory state;
    vm.prank(MarketA);
    vm.expectRevert(FixedTermHooks.TransfersDisabled.selector);
    hooks.onTransfer(Lender, Lender, SecondLender, 1, state, '');
    assertFalse(hooks.isMarketTransferRecipientAllowed(MarketA, SecondLender));

    _createMarket(hooks, MarketB, _requestedConfig(hooks, false, false, true), abi.encode(term));
    vm.prank(MarketB);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onTransfer(Lender, Lender, SecondLender, 1, state, '');
    assertFalse(hooks.isMarketTransferRecipientAllowed(MarketB, SecondLender));

    _addPullProvider(hooks);
    bytes memory credential = abi.encode('transfer');
    provider1.approveCredentialData(keccak256(credential), uint32(block.timestamp));
    vm.prank(MarketB);
    hooks.onTransfer(Lender, Lender, SecondLender, 1, state, _credentialData(credential));
    assertTrue(hooks.isKnownLenderOnMarket(SecondLender, MarketB), 'known recipient');
    assertTrue(hooks.isMarketTransferRecipientAllowed(MarketB, SecondLender), 'known allowed');

    vm.prank(address(provider1));
    hooks.revokeRole(SecondLender);
    vm.prank(MarketB);
    hooks.onTransfer(Lender, Lender, SecondLender, 1, state, '');

    hooks.blockFromDeposits(ThirdLender);
    vm.prank(MarketB);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onTransfer(Lender, Lender, ThirdLender, 1, state, '');
  }

  function test_onSetApr_BlocksReductionDuringTermAndDelegatesAllowedChanges() external {
    uint32 term = _term();
    _createMarket(hooks, MarketA, _requestedConfig(hooks, false, false, false), abi.encode(term));
    MarketState memory state;
    state.annualInterestBips = 100;
    state.reserveRatioBips = 1_000;

    vm.prank(MarketA);
    vm.expectRevert(FixedTermHooks.NoReducingAprBeforeTermEnd.selector);
    hooks.onSetAnnualInterestAndReserveRatioBips(99, 500, state, '');

    vm.prank(MarketA);
    (uint16 annualInterestBips, uint16 reserveRatioBips) = hooks
      .onSetAnnualInterestAndReserveRatioBips(101, 500, state, '');
    assertEq(annualInterestBips, 101, 'increased APR');
    assertEq(reserveRatioBips, 1_000, 'increased reserve ratio');

    vm.warp(term);
    vm.prank(MarketA);
    (annualInterestBips, reserveRatioBips) = hooks.onSetAnnualInterestAndReserveRatioBips(
      99,
      500,
      state,
      ''
    );
    assertEq(annualInterestBips, 99, 'post-term APR');
    assertEq(reserveRatioBips, 1_000, 'post-term reserve ratio');
  }

  function test_onCloseMarket_EnforcesEarlyClosurePolicyAndUpdatesTerm() external {
    uint32 term = _term();
    MarketState memory state;
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(term, uint128(0), false, true, false)
    );
    vm.expectEmit(address(hooks));
    emit FixedTermHooks.FixedTermUpdated(MarketA, MarketA, term, uint32(block.timestamp));
    vm.prank(MarketA);
    hooks.onCloseMarket(state, '');
    assertEq(hooks.getHookedMarket(MarketA).fixedTermEndTime, block.timestamp, 'closure term');

    _createMarket(
      hooks,
      MarketB,
      _requestedConfig(hooks, false, false, false),
      abi.encode(term, uint128(0), false, false, true)
    );
    vm.prank(MarketB);
    hooks.onCloseMarket(state, '');
    assertEq(hooks.getHookedMarket(MarketB).fixedTermEndTime, block.timestamp, 'reduction closure');

    _createMarket(hooks, MarketC, _requestedConfig(hooks, false, false, false), abi.encode(term));
    vm.prank(MarketC);
    vm.expectRevert(FixedTermHooks.ClosureDisabledBeforeTerm.selector);
    hooks.onCloseMarket(state, '');

    vm.warp(term);
    vm.prank(MarketC);
    hooks.onCloseMarket(state, '');
    assertEq(hooks.getHookedMarket(MarketC).fixedTermEndTime, term, 'elapsed term');
  }

  function test_unrestrictedCallbacks_AreNoOps() external {
    MarketState memory state;
    bytes memory extraData = abi.encode('unused');
    vm.startPrank(MarketA);
    hooks.onExecuteWithdrawal(Lender, 1, 2, state, extraData);
    hooks.onBorrow(3, state, extraData);
    hooks.onRepay(4, state, extraData);
    hooks.onNukeFromOrbit(Lender, state, extraData);
    hooks.onSetMaxTotalSupply(5, state, extraData);
    hooks.onSetProtocolFeeBips(6, state, extraData);
    vm.stopPrank();
  }
}
