// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseHooks, AccessConfig } from 'src/access/BaseHooks.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { MarketConstraintHooks } from 'src/access/MarketConstraintHooks.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { CreateProviderInputs } from 'src/access/ProviderStructs.sol';
import { ExistingProviderInputs } from 'src/access/ProviderStructs.sol';
import { FixedTermHooks, HookedMarket as FixedMarket } from 'src/access/FixedTermHooks.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { HookedMarket as PeriodicMarket } from 'src/access/PeriodicTermHooks.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { RAY } from 'src/libraries/MathUtils.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_CloseMarket } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetAnnualInterestAndReserveRatioBips } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_ExecutePendingAnnualInterestBipsReduction } from 'src/types/HooksConfig.sol';
import { RoleProvider, NullProviderIndex } from 'src/types/RoleProvider.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { MockRoleProviderFactory } from '../mocks/MockRoleProviderFactory.sol';
import { MarketConfigurationHooks } from '../mocks/MarketConfigurationHooks.sol';
import { HookTemplateFixture, HookKind } from '../shared/HookTemplateFixture.sol';

contract BaseHooksTest is HookTemplateFixture {
  address internal constant Lender = address(0xA11CE);
  address internal constant SecondLender = address(0xB0B);
  address internal constant Wrapper = address(0x4626);

  MockRoleProvider internal provider1;
  MockRoleProvider internal provider2;
  MockRoleProviderFactory internal providerFactory;

  function setUp() external {
    _setUpHooks();
    provider1 = MockRoleProvider(_deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider'));
    provider2 = MockRoleProvider(_deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider'));
    providerFactory = MockRoleProviderFactory(
      _deployCode('test/mocks/MockRoleProviderFactory.sol:MockRoleProviderFactory')
    );
  }

  function _requiredFlags(HookKind kind) internal pure returns (HooksConfig flags) {
    flags = EmptyHooksConfig.setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips);
    if (kind != HookKind.Open)
      flags = flags.setFlag(Bit_Enabled_CloseMarket).setFlag(Bit_Enabled_QueueWithdrawal);
    if (kind == HookKind.Periodic)
      flags = flags.setFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction);
  }

  function _addPullProvider(BaseHooks target) internal {
    provider1.setIsPullProvider(true);
    target.addRoleProvider(address(provider1), type(uint32).max);
  }

  function _expectCredentialEntry(BaseHooks target, address market, address lender) internal {
    vm.expectEmit(address(target));
    emit BaseAccessControls.AccountAccessGranted(
      address(provider1),
      lender,
      market,
      uint32(block.timestamp)
    );
    vm.expectEmit(address(target));
    emit BaseAccessControls.AccountMadeFirstDeposit(market, lender);
  }

  function _assertCachedCredential(BaseHooks target, address lender) internal view {
    LenderStatus memory status = target.getPreviousLenderStatus(lender);
    assertEq(status.lastProvider, address(provider1), 'cached provider');
    assertEq(status.lastApprovalTimestamp, block.timestamp, 'cached timestamp');
    assertTrue(status.canRefresh, 'refreshable');
    assertFalse(status.isBlockedFromDeposits, 'not blocked');
  }

  function _assertProvider(
    BaseHooks target,
    address account,
    uint32 ttl,
    bool pull,
    uint24 index
  ) internal view {
    RoleProvider provider = target.getRoleProvider(account);
    assertEq(provider.providerAddress(), account, 'provider address');
    assertEq(provider.timeToLive(), ttl, 'provider ttl');
    assertEq(provider.pullProviderIndex(), pull ? index : NullProviderIndex, 'pull index');
    assertEq(provider.pushProviderIndex(), pull ? NullProviderIndex : index, 'push index');
    RoleProvider[] memory providers = pull ? target.getPullProviders() : target.getPushProviders();
    assertEq(providers[index].providerAddress(), account, 'provider list');
  }

  function test_constructor_PreservesFactoryAdministratorFlagsAndEmptyArgs() external {
    for (uint256 i; i < hooks.length; i++) {
      HookKind kind = HookKind(i);
      BaseHooks target = hooks[i];
      HooksConfig optional = EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(
        Bit_Enabled_Transfer
      );
      if (kind == HookKind.Open) optional = optional.setFlag(Bit_Enabled_QueueWithdrawal);
      HooksDeploymentConfig expected = encodeHooksDeploymentConfig(optional, _requiredFlags(kind));
      assertEq(
        HooksDeploymentConfig.unwrap(target.config()),
        HooksDeploymentConfig.unwrap(expected),
        'deployment flags'
      );
      assertEq(target.factory(), address(this), 'factory');
      assertEq(target.administrator(), address(this), 'administrator');
      assertEq(target.name(), '', 'empty name');
      assertEq(target.getPullProviders().length, 0, 'empty pull providers');
      assertEq(target.getPushProviders().length, 0, 'empty push providers');
      NameAndProviderInputs memory inputs;
      BaseHooks encoded = _newHooks(kind, abi.encode(inputs));
      assertEq(encoded.name(), '', 'encoded empty name');
      assertEq(encoded.getPullProviders().length, 0, 'encoded pull providers');
      assertEq(encoded.getPushProviders().length, 0, 'encoded push providers');
    }
  }

  function test_constructor_InitializesExistingProviders(
    bool firstPull,
    bool secondPull,
    uint32 firstTtl,
    uint32 secondTtl
  ) external {
    provider1.setIsPullProvider(firstPull);
    provider2.setIsPullProvider(secondPull);
    NameAndProviderInputs memory inputs;
    inputs.name = 'existing providers';
    inputs.existingProviders = new ExistingProviderInputs[](2);
    inputs.existingProviders[0] = ExistingProviderInputs(address(provider1), firstTtl);
    inputs.existingProviders[1] = ExistingProviderInputs(address(provider2), secondTtl);
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = _newHooks(HookKind(i), abi.encode(inputs));
      _assertProvider(target, address(provider1), firstTtl, firstPull, 0);
      _assertProvider(
        target,
        address(provider2),
        secondTtl,
        secondPull,
        firstPull == secondPull ? 1 : 0
      );
      assertEq(target.name(), inputs.name, 'name');
    }
  }

  function test_constructor_CreatesNewProviders(
    bool firstPull,
    bool secondPull,
    uint32 firstTtl,
    uint32 secondTtl
  ) external {
    for (uint256 i; i < hooks.length; i++) {
      bytes32 firstSalt = bytes32(i * 2 + 1);
      bytes32 secondSalt = bytes32(i * 2 + 2);
      NameAndProviderInputs memory inputs;
      inputs.name = 'new providers';
      inputs.roleProviderFactory = address(providerFactory);
      inputs.newProviderInputs = new CreateProviderInputs[](2);
      inputs.newProviderInputs[0] = CreateProviderInputs(
        firstTtl,
        abi.encode(firstSalt, firstPull)
      );
      inputs.newProviderInputs[1] = CreateProviderInputs(
        secondTtl,
        abi.encode(secondSalt, secondPull)
      );
      address first = providerFactory.computeProviderAddress(firstSalt);
      address second = providerFactory.computeProviderAddress(secondSalt);
      BaseHooks target = _newHooks(HookKind(i), abi.encode(inputs));
      _assertProvider(target, first, firstTtl, firstPull, 0);
      _assertProvider(target, second, secondTtl, secondPull, firstPull == secondPull ? 1 : 0);
      assertEq(target.name(), inputs.name, 'name');
    }
  }

  function test_constructor_CombinesExistingAndNewProviders(
    bool firstPull,
    bool secondPull,
    uint32 firstTtl,
    uint32 secondTtl
  ) external {
    provider1.setIsPullProvider(firstPull);
    for (uint256 i; i < hooks.length; i++) {
      bytes32 salt = bytes32(i + 1);
      NameAndProviderInputs memory inputs;
      inputs.name = 'mixed providers';
      inputs.roleProviderFactory = address(providerFactory);
      inputs.existingProviders = new ExistingProviderInputs[](1);
      inputs.existingProviders[0] = ExistingProviderInputs(address(provider1), firstTtl);
      inputs.newProviderInputs = new CreateProviderInputs[](1);
      inputs.newProviderInputs[0] = CreateProviderInputs(secondTtl, abi.encode(salt, secondPull));
      address created = providerFactory.computeProviderAddress(salt);
      BaseHooks target = _newHooks(HookKind(i), abi.encode(inputs));
      _assertProvider(target, address(provider1), firstTtl, firstPull, 0);
      _assertProvider(target, created, secondTtl, secondPull, firstPull == secondPull ? 1 : 0);
      assertEq(target.name(), inputs.name, 'name');
    }
  }

  function test_constructor_RejectsMalformedArgsAndInvalidProviderFactoryResults() external {
    for (uint256 i; i < hooks.length; i++) {
      HookKind kind = HookKind(i);
      vm.expectRevert();
      _newHooks(kind, hex'01');
      NameAndProviderInputs memory inputs;
      inputs.newProviderInputs = new CreateProviderInputs[](1);
      vm.expectRevert(BaseAccessControls.RoleProviderFactoryRequired.selector);
      _newHooks(kind, abi.encode(inputs));
      inputs.roleProviderFactory = address(providerFactory);
      providerFactory.setNextProviderAddress(address(0));
      vm.expectRevert(BaseAccessControls.CreateRoleProviderFailed.selector);
      _newHooks(kind, abi.encode(inputs));
    }
  }

  function test_onCreateMarket_OrdersFactoryBoundsAdministratorAndTemplateValidation() external {
    for (uint256 i; i < hooks.length; i++) {
      DeployMarketInputs memory inputs;
      inputs.annualInterestBips = 10_001;
      vm.prank(address(0xBAD));
      vm.expectRevert(IHooks.CallerNotFactory.selector);
      hooks[i].onCreateMarket(address(0xBAD), MarketA, inputs, '');
      vm.expectRevert(MarketConstraintHooks.AnnualInterestBipsOutOfBounds.selector);
      hooks[i].onCreateMarket(address(0xBAD), MarketA, inputs, '');
      inputs.annualInterestBips = 0;
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      hooks[i].onCreateMarket(address(0xBAD), MarketA, inputs, '');
      assertFalse(_access(HookKind(i), hooks[i], MarketA).isHooked, 'no failed registration');
    }
  }

  function test_onCreateMarket_ConfigMatrix(
    bool deposit,
    bool queue,
    bool transfer,
    uint128 requestedMinimum,
    bool disabled
  ) external {
    for (uint256 i; i < hooks.length; i++) {
      HookKind kind = HookKind(i);
      uint128 minimum = kind == HookKind.Periodic
        ? uint128(uint96(requestedMinimum))
        : requestedMinimum;
      HooksConfig requested = EmptyHooksConfig;
      if (deposit) requested = requested.setFlag(Bit_Enabled_Deposit);
      if (queue) requested = requested.setFlag(Bit_Enabled_QueueWithdrawal);
      if (transfer) requested = requested.setFlag(Bit_Enabled_Transfer);
      if (queue && (!deposit || (!disabled && !transfer))) {
        vm.expectRevert(BaseHooks.InvalidAccessConfiguration.selector);
        _createMarket(hooks[i], MarketA, requested, _marketData(kind, minimum, disabled));
        assertFalse(_access(kind, hooks[i], MarketA).isHooked, 'invalid config not stored');
        continue;
      }
      HooksConfig actual = _createMarket(
        hooks[i],
        MarketA,
        requested,
        _marketData(kind, minimum, disabled)
      );
      HooksConfig expected = HooksConfig.wrap(
        HooksConfig.unwrap(requested) | HooksConfig.unwrap(_requiredFlags(kind))
      );
      expected = expected.setHooksAddress(address(hooks[i]));
      if (minimum > 0 || queue) expected = expected.setFlag(Bit_Enabled_Deposit);
      if (disabled || queue) expected = expected.setFlag(Bit_Enabled_Transfer);
      assertEq(HooksConfig.unwrap(actual), HooksConfig.unwrap(expected), 'effective flags');
      AccessConfig memory access = _access(kind, hooks[i], MarketA);
      assertTrue(access.isHooked, 'registered');
      assertEq(access.depositRequiresAccess, deposit, 'requested deposit access');
      assertEq(access.transferRequiresAccess, transfer, 'requested transfer access');
      if (kind != HookKind.Open)
        assertEq(access.withdrawalRequiresAccess, queue, 'requested queue access');
      assertEq(access.minimumDeposit, minimum, 'minimum');
      assertEq(access.transfersDisabled, disabled, 'disabled');
      assertEq(hooks[i].isMarketTransferDisabled(MarketA), disabled, 'disabled query');
      if (kind == HookKind.Periodic) {
        assertEq(
          PeriodicTermHooks(address(hooks[i])).getHookedMarket(MarketA).depositHookEnabled,
          actual.useOnDeposit(),
          'stored dispatch'
        );
      }
    }
  }

  function test_onCreateMarket_PreservesMissingPartialAndLowBitOptionalWords() external {
    for (uint256 i; i < hooks.length; i++) {
      HookKind kind = HookKind(i);
      _createMarket(hooks[i], MarketA, EmptyHooksConfig, _termData(kind));
      assertEq(_access(kind, hooks[i], MarketA).minimumDeposit, 0, 'missing minimum');
      assertFalse(_access(kind, hooks[i], MarketA).transfersDisabled, 'missing bool');
      uint256 padding = kind == HookKind.Periodic ? 20 : 16;
      bytes memory partialData = bytes.concat(_termData(kind), new bytes(padding), hex'01');
      _createMarket(hooks[i], MarketB, EmptyHooksConfig, partialData);
      assertEq(
        _access(kind, hooks[i], MarketB).minimumDeposit,
        uint256(1) << ((31 - padding) * 8),
        'partial minimum'
      );
      bytes memory boolData = bytes.concat(_termData(kind), abi.encode(uint256(0), uint256(2)));
      _createMarket(hooks[i], MarketC, EmptyHooksConfig, boolData);
      assertFalse(_access(kind, hooks[i], MarketC).transfersDisabled, 'even low bit');
      boolData = bytes.concat(_termData(kind), abi.encode(uint256(0), uint256(3)));
      _createMarket(hooks[i], address(0x1004), EmptyHooksConfig, boolData);
      assertTrue(_access(kind, hooks[i], address(0x1004)).transfersDisabled, 'odd low bit');
    }
  }

  function test_onCreateMarket_ChecksMinimumWidthBeforeAccessConfiguration() external {
    for (uint256 i; i < hooks.length; i++) {
      HookKind kind = HookKind(i);
      uint256 overflow = kind == HookKind.Periodic
        ? uint256(type(uint96).max) + 1
        : uint256(type(uint128).max) + 1;
      bytes memory data = _marketData(kind, overflow, false);
      vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
      _createMarket(hooks[i], MarketA, EmptyHooksConfig, data);
      vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
      _createMarket(hooks[i], MarketA, EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal), data);
    }
  }

  function test_onCreateMarket_EmitsScheduleBeforeMinimum() external {
    for (uint256 i; i < hooks.length; i++) {
      HookKind kind = HookKind(i);
      if (kind == HookKind.Fixed) {
        vm.expectEmit(address(hooks[i]));
        emit FixedTermHooks.FixedTermUpdated(MarketA, address(this), 0, FixedTermEnd);
      } else if (kind == HookKind.Periodic) {
        vm.expectEmit(address(hooks[i]));
        emit PeriodicTermHooks.PeriodicTermUpdated(
          MarketA,
          address(this),
          FirstWindowStart,
          PeriodDuration,
          WindowDuration
        );
      }
      vm.expectEmit(address(hooks[i]));
      emit BaseHooks.MinimumDepositUpdated(MarketA, address(this), 0, 100);
      _createMarket(hooks[i], MarketA, EmptyHooksConfig, _marketData(kind, 100, false));
    }
  }

  function test_setMinimumDeposit_PreservesAuthorityDispatchWidthAndOtherFields() external {
    for (uint256 i; i < hooks.length; i++) {
      HookKind kind = HookKind(i);
      _createMarket(hooks[i], MarketA, EmptyHooksConfig, _marketData(kind, 100, true));
      _createMarket(hooks[i], MarketB, EmptyHooksConfig, _termData(kind));
      vm.expectEmit(address(hooks[i]));
      emit BaseHooks.MinimumDepositUpdated(MarketA, address(this), 100, 200);
      hooks[i].setMinimumDeposit(MarketA, 200);
      assertEq(_access(kind, hooks[i], MarketA).minimumDeposit, 200, 'updated minimum');
      assertTrue(_access(kind, hooks[i], MarketA).transfersDisabled, 'preserve disabled');
      uint128 maximum = kind == HookKind.Periodic ? type(uint96).max : type(uint128).max;
      hooks[i].setMinimumDeposit(MarketA, maximum);
      assertEq(_access(kind, hooks[i], MarketA).minimumDeposit, maximum, 'full width');
      hooks[i].setMinimumDeposit(MarketA, 0);
      hooks[i].setMinimumDeposit(MarketA, 1);
      assertEq(
        _access(kind, hooks[i], MarketA).minimumDeposit,
        1,
        'dispatch survives zero minimum'
      );
      uint128 tooWide = uint128(type(uint96).max) + 1;
      vm.expectRevert(BaseHooks.DepositHookNotEnabled.selector);
      hooks[i].setMinimumDeposit(MarketB, tooWide);
      hooks[i].setMinimumDeposit(MarketB, 0);
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      hooks[i].setMinimumDeposit(MarketC, tooWide);
      vm.prank(address(0xBAD));
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      hooks[i].setMinimumDeposit(MarketC, tooWide);
      _assertUnchangedTermFields(kind, hooks[i]);
    }
    vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
    hooks[2].setMinimumDeposit(MarketA, uint128(type(uint96).max) + 1);
    assertEq(
      _access(HookKind.Periodic, hooks[2], MarketA).minimumDeposit,
      1,
      'overflow rolls back'
    );
  }

  function _assertUnchangedTermFields(HookKind kind, BaseHooks target) internal view {
    AccessConfig memory access = _access(kind, target, MarketA);
    assertTrue(access.isHooked, 'still registered');
    assertFalse(access.depositRequiresAccess, 'deposit access unchanged');
    assertFalse(access.transferRequiresAccess, 'transfer access unchanged');
    if (kind == HookKind.Fixed) {
      FixedMarket memory config = FixedTermHooks(address(target)).getHookedMarket(MarketA);
      assertEq(config.fixedTermEndTime, FixedTermEnd, 'maturity unchanged');
      assertFalse(config.withdrawalRequiresAccess, 'queue access unchanged');
      assertFalse(config.allowClosureBeforeTerm, 'closure permission unchanged');
      assertFalse(config.allowTermReduction, 'term permission unchanged');
    } else if (kind == HookKind.Periodic) {
      PeriodicMarket memory config = PeriodicTermHooks(address(target)).getHookedMarket(MarketA);
      assertEq(config.firstWithdrawalWindowStart, FirstWindowStart, 'window anchor unchanged');
      assertEq(config.periodDuration, PeriodDuration, 'period unchanged');
      assertEq(config.withdrawalWindowDuration, WindowDuration, 'window unchanged');
      assertFalse(config.withdrawalRequiresAccess, 'queue access unchanged');
      assertFalse(config.isClosed, 'closed unchanged');
      assertTrue(config.depositHookEnabled, 'dispatch unchanged');
    }
  }

  function test_onMarketConfigured_SeesBoundStateBeforeDeploymentAndRevertsAtomically() external {
    MarketConfigurationHooks target = MarketConfigurationHooks(
      _deployCode(
        'test/mocks/MarketConfigurationHooks.sol:MarketConfigurationHooks',
        abi.encode(address(this))
      )
    );
    HooksConfig effective = _createMarket(
      target,
      MarketA,
      EmptyHooksConfig,
      _marketData(HookKind.Periodic, 100, false)
    );
    assertEq(target.configuredMarket(), MarketA, 'configured market');
    assertEq(target.configuredMinimum(), 100, 'configured minimum');
    assertEq(
      HooksConfig.unwrap(target.configuredFlags()),
      HooksConfig.unwrap(effective),
      'configured flags'
    );
    assertEq(MarketA.code.length, 0, 'market has no code');
    target.setRejectConfiguration(true);
    vm.expectRevert(MarketConfigurationHooks.ConfigurationRejected.selector);
    _createMarket(target, MarketB, EmptyHooksConfig, _marketData(HookKind.Periodic, 200, true));
    assertFalse(target.getHookedMarket(MarketB).isHooked, 'registration rolled back');
    assertEq(target.configuredMarket(), MarketA, 'feature state rolled back');
    assertEq(target.configuredMinimum(), 100, 'feature minimum rolled back');
    assertEq(
      HooksConfig.unwrap(target.configuredFlags()),
      HooksConfig.unwrap(effective),
      'feature flags rolled back'
    );
  }

  function test_lenderActionsAndTransferViews_RejectUnregisteredMarkets() external {
    MarketState memory state;
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      target.onDeposit(Lender, 0, state, '');
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      target.onTransfer(Lender, Lender, SecondLender, 0, state, '');
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      target.onQueueWithdrawal(Lender, 0, 1, state, '');
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      target.isMarketTransferDisabled(MarketA);
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      target.isMarketTransferRecipientAllowed(MarketA, Lender);
    }
  }

  function test_onDeposit_FloorsMinimumAndChecksLocalBlockFirst() external {
    MarketState memory state;
    state.scaleFactor = uint112((RAY * 3) / 2);
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      _createMarket(target, MarketA, EmptyHooksConfig, _marketData(HookKind(i), 100, false));
      vm.prank(MarketA);
      vm.expectRevert(BaseHooks.DepositBelowMinimum.selector);
      target.onDeposit(Lender, 65, state, '');
      // 100 normalized floors to 66 scaled, which converts back to only 99 normalized.
      vm.prank(MarketA);
      target.onDeposit(Lender, 66, state, '');
      assertFalse(target.isKnownLenderOnMarket(Lender, MarketA), 'uncredentialed entry');

      target.blockFromDeposits(Lender);
      vm.prank(MarketA);
      vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      target.onDeposit(Lender, 0, state, '');

      _createMarket(target, MarketB, EmptyHooksConfig, _termData(HookKind(i)));
      MarketState memory zeroScale;
      vm.prank(MarketB);
      target.onDeposit(SecondLender, 1, zeroScale, '');
    }
  }

  function test_onDeposit_ResolvesOptionalOrRequiredCredentialsAndRecordsEntry(
    bool requiresAccess
  ) external {
    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    bytes memory credential = abi.encode('deposit');
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      HooksConfig requested = requiresAccess
        ? EmptyHooksConfig.setFlag(Bit_Enabled_Deposit)
        : EmptyHooksConfig;
      _createMarket(target, MarketA, requested, _termData(HookKind(i)));
      _createMarket(target, MarketB, requested, _termData(HookKind(i)));
      vm.prank(MarketA);
      if (requiresAccess) vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      target.onDeposit(Lender, 1, state, '');
      assertFalse(target.isKnownLenderOnMarket(Lender, MarketA), 'no credential yet');

      _addPullProvider(target);
      provider1.approveCredentialData(keccak256(credential), uint32(block.timestamp));
      _expectCredentialEntry(target, MarketA, Lender);
      vm.prank(MarketA);
      target.onDeposit(Lender, 1, state, abi.encodePacked(address(provider1), credential));
      _assertCachedCredential(target, Lender);
      assertTrue(target.isKnownLenderOnMarket(Lender, MarketA), 'first entry');
      assertFalse(target.isKnownLenderOnMarket(Lender, MarketB), 'known status stays local');

      vm.recordLogs();
      vm.prank(MarketA);
      target.onDeposit(Lender, 1, state, '');
      assertEq(vm.getRecordedLogs().length, 0, 'cached repeat emits no entry or grant');
      vm.expectEmit(address(target));
      emit BaseAccessControls.AccountMadeFirstDeposit(MarketB, Lender);
      vm.prank(MarketB);
      target.onDeposit(Lender, 1, state, '');
      assertTrue(target.isKnownLenderOnMarket(Lender, MarketB), 'cached credential permits entry');

      vm.prank(address(provider1));
      target.revokeRole(Lender);
      vm.prank(MarketA);
      if (requiresAccess) vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      target.onDeposit(Lender, 1, state, '');
      target.blockFromDeposits(Lender);
      vm.prank(MarketA);
      vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      target.onDeposit(Lender, 1, state, '');
    }
  }

  function test_onTransfer_DisabledWinsOverKnownAndWrapperExemptions() external {
    MarketState memory state;
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      _createMarket(target, MarketA, EmptyHooksConfig, _marketData(HookKind(i), 0, true));
      _addPullProvider(target);
      vm.prank(address(provider1));
      target.grantRole(Lender, uint32(block.timestamp));
      vm.prank(MarketA);
      target.onDeposit(Lender, 1, state, '');
      target.blockFromDeposits(Lender);
      target.blockFromDeposits(Wrapper);
      vm.mockCall(MarketA, abi.encodeWithSignature('registeredWrapper()'), abi.encode(Wrapper));
      assertTrue(target.isMarketTransferDisabled(MarketA), 'global flag');
      assertFalse(target.isMarketTransferRecipientAllowed(MarketA, Lender), 'disabled known');
      assertFalse(target.isMarketTransferRecipientAllowed(MarketA, Wrapper), 'disabled wrapper');
      vm.prank(MarketA);
      vm.expectRevert(BaseHooks.TransfersDisabled.selector);
      target.onTransfer(SecondLender, SecondLender, Lender, 1, state, '');
      vm.prank(MarketA);
      vm.expectRevert(BaseHooks.TransfersDisabled.selector);
      target.onTransfer(SecondLender, SecondLender, Wrapper, 1, state, '');
    }
  }

  function test_onTransfer_ResolvesCredentialsAndPreservesKnownRecipientExemption(
    bool requiresAccess
  ) external {
    MarketState memory state;
    bytes memory credential = abi.encode('transfer');
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      HooksConfig requested = requiresAccess
        ? EmptyHooksConfig.setFlag(Bit_Enabled_Transfer)
        : EmptyHooksConfig;
      _createMarket(target, MarketA, requested, _termData(HookKind(i)));
      _createMarket(target, MarketB, requested, _termData(HookKind(i)));
      assertFalse(target.isMarketTransferDisabled(MarketA), 'global transfers enabled');
      assertEq(target.isMarketTransferRecipientAllowed(MarketA, Lender), !requiresAccess);
      vm.prank(MarketA);
      if (requiresAccess) vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      target.onTransfer(SecondLender, SecondLender, Lender, 1, state, '');
      assertFalse(target.isKnownLenderOnMarket(Lender, MarketA), 'uncredentialed entry');

      _addPullProvider(target);
      provider1.approveCredentialData(keccak256(credential), uint32(block.timestamp));
      assertEq(target.isMarketTransferRecipientAllowed(MarketA, Lender), !requiresAccess);
      _expectCredentialEntry(target, MarketA, Lender);
      vm.prank(MarketA);
      target.onTransfer(
        SecondLender,
        SecondLender,
        Lender,
        1,
        state,
        abi.encodePacked(address(provider1), credential)
      );
      _assertCachedCredential(target, Lender);
      assertTrue(target.isKnownLenderOnMarket(Lender, MarketA), 'credentialed entry');
      assertTrue(target.isMarketTransferRecipientAllowed(MarketB, Lender), 'cached credential');
      assertFalse(target.isKnownLenderOnMarket(Lender, MarketB), 'view does not mark known');

      vm.prank(address(provider1));
      target.revokeRole(Lender);
      target.blockFromDeposits(Lender);
      assertTrue(target.isMarketTransferRecipientAllowed(MarketA, Lender), 'known exemption');
      assertFalse(target.isMarketTransferRecipientAllowed(MarketB, Lender), 'unknown and blocked');
      vm.recordLogs();
      vm.prank(MarketA);
      target.onTransfer(SecondLender, SecondLender, Lender, 1, state, '');
      assertEq(vm.getRecordedLogs().length, 0, 'known exemption emits nothing');
      assertFalse(target.getPreviousLenderStatus(Lender).hasCredential(), 'no credential needed');

      vm.prank(MarketB);
      vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      target.onTransfer(
        SecondLender,
        SecondLender,
        Lender,
        1,
        state,
        abi.encodePacked(address(provider1), credential)
      );
      assertFalse(target.isMarketTransferDisabled(MarketA), 'recipient block keeps global promise');
    }
  }

  function test_transferRecipientView_UsesPullCredentialsWithoutCachingThem() external {
    MarketState memory state;
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      _createMarket(
        target,
        MarketA,
        EmptyHooksConfig.setFlag(Bit_Enabled_Transfer),
        _termData(HookKind(i))
      );
      _addPullProvider(target);
      provider1.setCredential(Lender, uint32(block.timestamp));
      assertTrue(target.isMarketTransferRecipientAllowed(MarketA, Lender), 'pull view');
      assertFalse(target.getPreviousLenderStatus(Lender).hasCredential(), 'view does not cache');
      assertFalse(target.isKnownLenderOnMarket(Lender, MarketA), 'view does not mark known');
      _expectCredentialEntry(target, MarketA, Lender);
      vm.prank(MarketA);
      target.onTransfer(SecondLender, SecondLender, Lender, 1, state, '');
      _assertCachedCredential(target, Lender);
      assertTrue(target.isKnownLenderOnMarket(Lender, MarketA), 'transfer records entry');
    }
  }

  function _createQueueMarkets(
    uint256 i,
    HooksConfig requested
  ) internal returns (BaseHooks target) {
    vm.warp(StartTimestamp);
    target = hooks[i];
    _createMarket(target, MarketA, requested, _termData(HookKind(i)));
    _createMarket(target, MarketB, requested, _termData(HookKind(i)));
    if (HookKind(i) == HookKind.Fixed) vm.warp(FixedTermEnd);
    if (HookKind(i) == HookKind.Periodic) vm.warp(FirstWindowStart);
  }

  function test_onQueueWithdrawal_ValidatesCredentialsWithoutMarkingKnown() external {
    MarketState memory state;
    HooksConfig requested = EmptyHooksConfig
      .setFlag(Bit_Enabled_Deposit)
      .setFlag(Bit_Enabled_Transfer)
      .setFlag(Bit_Enabled_QueueWithdrawal);
    bytes memory credential = abi.encode('queue');
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = _createQueueMarkets(i, requested);
      vm.prank(MarketA);
      vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      target.onQueueWithdrawal(Lender, 12, 34, state, '');

      _addPullProvider(target);
      target.blockFromDeposits(Lender);
      provider1.approveCredentialData(keccak256(credential), uint32(block.timestamp));
      vm.expectEmit(address(target));
      emit BaseAccessControls.AccountAccessGranted(
        address(provider1),
        Lender,
        MarketA,
        uint32(block.timestamp)
      );
      vm.prank(MarketA);
      target.onQueueWithdrawal(
        Lender,
        12,
        34,
        state,
        abi.encodePacked(address(provider1), credential)
      );
      LenderStatus memory status = target.getPreviousLenderStatus(Lender);
      assertEq(status.lastProvider, address(provider1), 'queue caches provider');
      assertEq(status.lastApprovalTimestamp, block.timestamp, 'queue caches credential');
      assertTrue(status.canRefresh, 'pull credential');
      assertTrue(status.isBlockedFromDeposits, 'deposit block survives queue');
      assertFalse(target.isKnownLenderOnMarket(Lender, MarketA), 'queue is not entry');

      vm.prank(address(provider1));
      target.revokeRole(Lender);
      vm.prank(MarketA);
      vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      target.onQueueWithdrawal(Lender, 12, 34, state, '');
    }
  }

  function test_onQueueWithdrawal_PreservesKnownAccessAndRequestedGating(bool gated) external {
    MarketState memory state;
    HooksConfig requested = gated
      ? EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer).setFlag(
        Bit_Enabled_QueueWithdrawal
      )
      : EmptyHooksConfig;
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = _createQueueMarkets(i, requested);
      _addPullProvider(target);
      vm.prank(address(provider1));
      target.grantRole(Lender, uint32(block.timestamp));
      vm.prank(MarketA);
      target.onDeposit(Lender, 1, state, '');
      target.blockFromDeposits(Lender);
      target.removeRoleProvider(address(provider1));
      assertFalse(target.getPreviousLenderStatus(Lender).hasCredential(), 'credential removed');
      vm.prank(MarketA);
      target.onQueueWithdrawal(Lender, 12, 34, state, '');

      // open-term access is required whenever its callback runs, even if dispatch wasn't requested.
      bool requiresAccess = gated || HookKind(i) == HookKind.Open;
      vm.prank(MarketB);
      if (requiresAccess) vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      target.onQueueWithdrawal(Lender, 12, 34, state, '');
      assertFalse(target.isKnownLenderOnMarket(Lender, MarketB), 'known status stays market-local');
    }
  }

  function test_emptyCallbacks_StayUnguardedAndHaveNoEffects(
    bool registeredCaller,
    bytes calldata extraData
  ) external {
    MarketState memory state;
    state.annualInterestBips = 1_000;
    state.reserveRatioBips = 500;
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      _createMarket(
        target,
        MarketA,
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer).setFlag(
          Bit_Enabled_QueueWithdrawal
        ),
        _termData(HookKind(i))
      );
      target.blockFromDeposits(Lender);
      vm.record();
      vm.recordLogs();
      vm.startPrank(registeredCaller ? MarketA : MarketB);
      target.onExecuteWithdrawal(Lender, 1, 2, state, extraData);
      target.onBorrow(3, state, extraData);
      target.onRepay(4, state, extraData);
      target.onNukeFromOrbit(Lender, state, extraData);
      target.onSetMaxTotalSupply(5, state, extraData);
      target.onSetProtocolFeeBips(6, state, extraData);
      if (HookKind(i) == HookKind.Open) target.onCloseMarket(state, extraData);
      vm.stopPrank();
      (, bytes32[] memory writes) = vm.accesses(address(target));
      assertEq(writes.length, 0, 'no storage effects');
      assertEq(vm.getRecordedLogs().length, 0, 'no events');
    }
  }

  function test_onCloseMarket_DoesNotClearTemporaryReserves() external {
    MarketState memory state;
    state.annualInterestBips = 1_000;
    state.reserveRatioBips = 2_000;
    for (uint256 i; i < uint256(HookKind.Periodic); i++) {
      BaseHooks target = _createQueueMarkets(i, EmptyHooksConfig);
      vm.prank(MarketA);
      target.onSetAnnualInterestAndReserveRatioBips(700, 0, state, '');
      (uint16 originalApr, uint16 originalReserve, uint32 expiry) = target
        .temporaryExcessReserveRatio(MarketA);
      assertTrue(expiry > block.timestamp, 'active temporary reserves before close');
      vm.prank(MarketA);
      target.onCloseMarket(state, '');
      (uint16 afterApr, uint16 afterReserve, uint32 afterExpiry) = target
        .temporaryExcessReserveRatio(MarketA);
      assertEq(afterApr, originalApr, 'original APR retained');
      assertEq(afterReserve, originalReserve, 'original reserve retained');
      assertEq(afterExpiry, expiry, 'expiry retained');
    }
  }

  function test_onSetApr_OpenAndFixedDoNotRequireRegistration() external {
    MarketState memory state;
    state.annualInterestBips = 1_000;
    state.reserveRatioBips = 500;
    for (uint256 i; i < uint256(HookKind.Periodic); i++) {
      vm.prank(MarketA);
      (uint16 apr, uint16 reserve) = hooks[i].onSetAnnualInterestAndReserveRatioBips(
        1_000,
        9_999,
        state,
        abi.encode('unused')
      );
      assertEq(apr, 1_000, 'APR');
      assertEq(reserve, 500, 'requested reserves ignored');
    }
  }
}
