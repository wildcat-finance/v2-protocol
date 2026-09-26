// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { BaseHooks } from 'src/access/BaseHooks.sol';
import { FixedTermPolicy } from 'src/access/FixedTermPolicy.sol';
import { PeriodicTermPolicy } from 'src/access/PeriodicTermPolicy.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { LibStoredInitCodeExternal } from '../libraries/wrappers/LibStoredInitCodeExternal.sol';
import { RAY } from 'src/libraries/MathUtils.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';
import { RecipientRestrictionPolicy } from '../mocks/TransferFeaturePolicies.sol';
import { TransferAmountPolicy } from '../mocks/TransferFeaturePolicies.sol';
import { TransferFeatures } from '../mocks/TransferFeaturePolicies.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { HookTemplateFixture, HookKind } from '../shared/HookTemplateFixture.sol';

contract HookExtensionsTest is HookTemplateFixture {
  address internal constant Allowed = address(0xA11CE);
  address internal constant Restricted = address(0xB0B);
  address internal constant NewAdministrator = address(0xAD1111);
  uint128 internal constant InitialLimit = 100;
  MockRoleProvider[3] internal providers;

  function _artifact(HookKind kind) internal pure returns (string memory) {
    return
      kind == HookKind.Open
        ? 'test/mocks/TransferFeatureHooks.sol:OpenTransferHooks'
        : kind == HookKind.Fixed
        ? 'test/mocks/TransferFeatureHooks.sol:FixedTransferHooks'
        : 'test/mocks/TransferFeatureHooks.sol:PeriodicTransferHooks';
  }

  function _createCompositionMarket(
    HookKind kind,
    address market,
    HooksConfig requested,
    uint128 initialLimit,
    uint128 minimum,
    bool disabled
  ) internal returns (HooksConfig) {
    BaseHooks target = hooks[uint256(kind)];
    DeployMarketInputs memory inputs;
    inputs.hooks = requested.setHooksAddress(address(target));
    inputs.maxTotalSupply = initialLimit;
    return
      target.onCreateMarket(address(this), market, inputs, _marketData(kind, minimum, disabled));
  }

  function setUp() external {
    vm.warp(StartTimestamp);
    for (uint256 i; i < hooks.length; i++) {
      HookKind kind = HookKind(i);
      BaseHooks target = BaseHooks(
        _deployCode(_artifact(kind), abi.encode(address(this), bytes('')))
      );
      hooks[i] = target;
      MockRoleProvider provider = MockRoleProvider(
        _deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider')
      );
      providers[i] = provider;
      provider.setIsPullProvider(true);
      target.addRoleProvider(address(provider), type(uint32).max);
      HooksConfig requested = EmptyHooksConfig
        .setFlag(Bit_Enabled_Transfer)
        .setFlag(Bit_Enabled_Deposit)
        .setFlag(Bit_Enabled_QueueWithdrawal);
      _createCompositionMarket(kind, MarketA, requested, InitialLimit, 0, false);
      _createCompositionMarket(kind, MarketB, requested, InitialLimit, 0, false);
      TransferFeatures(address(target)).setRestrictedRecipient(MarketA, Restricted);
    }
  }

  // only the authority handoff is under test here; the real factory index has its own suite.
  function archController() external view returns (address) {
    return address(this);
  }

  function isRegisteredBorrower(address account) external pure returns (bool) {
    return account == NewAdministrator;
  }

  function onHooksAdministratorTransferred(address previous, address next) external view {
    assertTrue(
      msg.sender == address(hooks[0]) ||
        msg.sender == address(hooks[1]) ||
        msg.sender == address(hooks[2])
    );
    assertEq(previous, address(this));
    assertEq(next, NewAdministrator);
  }

  function test_transferRule_AcceptsAndRejectsAfterCredentialProcessingWithRollback() external {
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      TransferFeatures features = TransferFeatures(address(target));
      MockRoleProvider provider = providers[i];
      MarketState memory state;
      vm.prank(MarketA);
      vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      target.onTransfer(Allowed, Allowed, Restricted, 1, state, '');

      bytes memory credential = abi.encode('recipient rule');
      provider.approveCredentialData(keccak256(credential), uint32(block.timestamp));
      bytes memory data = abi.encodePacked(address(provider), credential);
      vm.prank(MarketA);
      target.onTransfer(Allowed, Allowed, Allowed, 1, state, data);
      assertTrue(target.isKnownLenderOnMarket(Allowed, MarketA), 'accepted entry');
      assertTrue(target.isMarketTransferRecipientAllowed(MarketA, Allowed), 'accepted view');

      // make the default no-data view accept too, so only the feature can explain this denial.
      provider.setCredential(Restricted, uint32(block.timestamp));
      assertFalse(target.isMarketTransferRecipientAllowed(MarketA, Restricted), 'feature view');
      uint256 beforeVolume = features.scaledTransferVolume(MarketA);
      LenderStatus memory beforeStatus = target.getPreviousLenderStatus(Restricted);
      vm.prank(MarketA);
      vm.expectRevert(RecipientRestrictionPolicy.RecipientRestricted.selector);
      target.onTransfer(Allowed, Allowed, Restricted, 1, state, data);
      assertEq(abi.encode(target.getPreviousLenderStatus(Restricted)), abi.encode(beforeStatus));
      assertFalse(target.isKnownLenderOnMarket(Restricted, MarketA), 'entry rolled back');
      assertTrue(target.isKnownLenderOnMarket(Allowed, MarketA), 'other entry retained');

      assertEq(features.scaledTransferVolume(MarketA), beforeVolume, 'feature write rolled back');
    }
  }

  function test_transferRule_StillChecksKnownRecipientsWithoutCredentials() external {
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      TransferFeatures features = TransferFeatures(address(target));
      MockRoleProvider provider = providers[i];
      MarketState memory state;
      provider.setCredential(Restricted, uint32(block.timestamp));
      vm.prank(MarketA);
      target.onDeposit(Restricted, 1, state, '');
      target.blockFromDeposits(Restricted);
      assertTrue(target.isKnownLenderOnMarket(Restricted, MarketA), 'known before transfer');
      assertFalse(target.getPreviousLenderStatus(Restricted).hasCredential(), 'credential cleared');
      assertFalse(target.isMarketTransferRecipientAllowed(MarketA, Restricted), 'feature view');
      vm.prank(MarketA);
      vm.expectRevert(RecipientRestrictionPolicy.RecipientRestricted.selector);
      target.onTransfer(Allowed, Allowed, Restricted, 1, state, '');
      assertTrue(target.isKnownLenderOnMarket(Restricted, MarketA), 'prior known state retained');

      features.setRestrictedRecipient(MarketA, address(0));
      vm.prank(MarketA);
      vm.expectRevert(TransferAmountPolicy.TransferAmountLimitExceeded.selector);
      target.onTransfer(Allowed, Allowed, Restricted, InitialLimit + 1, state, '');
      vm.prank(MarketA);
      target.onTransfer(Allowed, Allowed, Restricted, 1, state, '');
      assertEq(
        features.scaledTransferVolume(MarketA),
        1,
        'known recipient still faces amount rule'
      );
    }
  }

  function test_transferRule_StillChecksTheRegisteredWrapper() external {
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      TransferFeatures features = TransferFeatures(address(target));
      MockRoleProvider provider = providers[i];
      MarketState memory state;
      target.blockFromDeposits(Restricted);
      vm.mockCall(MarketA, abi.encodeWithSignature('registeredWrapper()'), abi.encode(Restricted));
      assertFalse(
        target.isMarketTransferRecipientAllowed(MarketA, Restricted),
        'restricted wrapper'
      );
      vm.prank(MarketA);
      vm.expectRevert(RecipientRestrictionPolicy.RecipientRestricted.selector);
      target.onTransfer(Allowed, Allowed, Restricted, 1, state, '');

      target.blockFromDeposits(Allowed);
      vm.mockCall(MarketA, abi.encodeWithSignature('registeredWrapper()'), abi.encode(Allowed));
      assertTrue(target.isMarketTransferRecipientAllowed(MarketA, Allowed), 'allowed wrapper');
      vm.prank(MarketA);
      vm.expectRevert(TransferAmountPolicy.TransferAmountLimitExceeded.selector);
      target.onTransfer(Allowed, Allowed, Allowed, InitialLimit + 1, state, '');
      vm.prank(MarketA);
      target.onTransfer(Allowed, Allowed, Allowed, 1, state, '');
      assertEq(
        features.scaledTransferVolume(MarketA),
        1,
        'only accepted wrapper transfer recorded'
      );
      assertFalse(target.isKnownLenderOnMarket(Allowed, MarketA), 'wrapper stays unknown');
      assertFalse(
        target.getPreviousLenderStatus(Allowed).hasCredential(),
        'wrapper stays uncredentialed'
      );
      assertFalse(target.isMarketTransferDisabled(MarketA), 'recipient rule keeps global promise');
    }
  }

  function test_transferRule_IsScopedToItsMarket() external {
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      MockRoleProvider provider = providers[i];
      MarketState memory state;
      provider.setCredential(Restricted, uint32(block.timestamp));
      assertFalse(
        target.isMarketTransferRecipientAllowed(MarketA, Restricted),
        'restricted market'
      );
      assertTrue(target.isMarketTransferRecipientAllowed(MarketB, Restricted), 'other market');
      vm.prank(MarketB);
      target.onTransfer(Allowed, Allowed, Restricted, 1, state, '');
      assertTrue(target.isKnownLenderOnMarket(Restricted, MarketB), 'other market entry');
      assertFalse(
        target.isKnownLenderOnMarket(Restricted, MarketA),
        'restricted market still unknown'
      );
      vm.prank(MarketA);
      vm.expectRevert(RecipientRestrictionPolicy.RecipientRestricted.selector);
      target.onTransfer(Allowed, Allowed, Restricted, 1, state, '');
      assertFalse(target.isKnownLenderOnMarket(Restricted, MarketA), 'cached entry rolled back');
    }
  }

  function test_composition_DeclaresTransferWithoutRequiringCredentials() external {
    for (uint256 i; i < hooks.length; i++) {
      HookKind kind = HookKind(i);
      BaseHooks target = hooks[i];
      BaseHooks original = _newHooks(kind, '');
      HooksConfig effective = _createCompositionMarket(
        kind,
        MarketC,
        EmptyHooksConfig,
        InitialLimit,
        5,
        false
      );
      assertEq(
        HooksConfig.unwrap(target.config().optionalFlags()),
        HooksConfig.unwrap(original.config().optionalFlags())
      );
      assertEq(
        HooksConfig.unwrap(target.config().requiredFlags()),
        HooksConfig.unwrap(original.config().requiredFlags().setFlag(Bit_Enabled_Transfer))
      );
      assertTrue(effective.useOnTransfer(), 'required dispatch');
      assertTrue(effective.useOnDeposit(), 'minimum forces deposit dispatch');
      assertFalse(effective.useOnBorrow(), 'fourth feature not installed yet');
      assertFalse(
        _access(kind, target, MarketC).transferRequiresAccess,
        'dispatch is not transfer access'
      );
      assertFalse(
        _access(kind, target, MarketC).depositRequiresAccess,
        'dispatch is not deposit access'
      );
      assertEq(MarketC.code.length, 0, 'configuration precedes market deployment');

      MarketState memory state;
      state.scaleFactor = uint112(RAY);
      vm.prank(MarketC);
      target.onDeposit(Allowed, 5, state, '');
      vm.prank(MarketC);
      target.onTransfer(Allowed, Allowed, Allowed, 1, state, '');
      assertFalse(
        target.isKnownLenderOnMarket(Allowed, MarketC),
        'optional entry without credentials stays unknown'
      );
      assertTrue(
        target.isMarketTransferRecipientAllowed(MarketC, Allowed),
        'ungated recipient view'
      );
      assertEq(TransferFeatures(address(target)).scaledTransferVolume(MarketC), 1);
    }
  }

  function test_composition_RejectsCreationAfterTermSetupWithoutPartialState() external {
    for (uint256 i; i < hooks.length; i++) {
      HookKind kind = HookKind(i);
      BaseHooks target = hooks[i];
      TransferFeatures features = TransferFeatures(address(target));
      vm.expectRevert(TransferAmountPolicy.ZeroTransferAmountLimit.selector);
      _createCompositionMarket(kind, MarketC, EmptyHooksConfig, 0, 5, false);
      assertFalse(_access(kind, target, MarketC).isHooked, 'registration rolled back');
      assertEq(
        _access(kind, target, MarketC).minimumDeposit,
        0,
        'packed configuration rolled back'
      );
      assertEq(features.maximumScaledTransfer(MarketC), 0, 'no feature setup');
      assertEq(features.scaledTransferVolume(MarketC), 0, 'no feature activity');
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      target.isMarketTransferRecipientAllowed(MarketC, Allowed);

      _createCompositionMarket(kind, MarketC, EmptyHooksConfig, 7, 5, false);
      assertTrue(
        _access(kind, target, MarketC).isHooked,
        'same market can be configured after rejection'
      );
      assertEq(_access(kind, target, MarketC).minimumDeposit, 5);
      assertEq(features.maximumScaledTransfer(MarketC), 7);
      assertEq(features.maximumScaledTransfer(MarketA), InitialLimit, 'other market unchanged');
    }
  }

  function test_transferAmount_BoundariesAndVolumeAreIndependent(uint128 rawLimit) external {
    uint256 maximum = rawLimit == 0 ? 1 : uint256(rawLimit);
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      TransferFeatures features = TransferFeatures(address(target));
      providers[i].setCredential(Allowed, uint32(block.timestamp));
      vm.expectEmit(address(target));
      emit TransferAmountPolicy.TransferAmountLimitUpdated(MarketA, maximum);
      features.setTransferAmountLimit(MarketA, maximum);
      assertEq(features.maximumScaledTransfer(MarketA), maximum);
      MarketState memory state;

      vm.prank(MarketA);
      vm.expectEmit(address(target));
      emit TransferAmountPolicy.TransferVolumeRecorded(MarketA, maximum - 1, maximum - 1);
      target.onTransfer(Allowed, Allowed, Allowed, maximum - 1, state, '');
      vm.prank(MarketA);
      vm.expectEmit(address(target));
      emit TransferAmountPolicy.TransferVolumeRecorded(MarketA, maximum, maximum * 2 - 1);
      target.onTransfer(Allowed, Allowed, Allowed, maximum, state, '');
      vm.prank(MarketA);
      target.onTransfer(Allowed, Allowed, Allowed, maximum, state, '');
      assertEq(features.scaledTransferVolume(MarketA), maximum * 3 - 1, 'volume is not a quota');
      assertEq(features.scaledTransferVolume(MarketB), 0, 'other market isolated');
      assertTrue(
        target.isMarketTransferRecipientAllowed(MarketA, Allowed),
        'view does not validate amount'
      );
      vm.prank(MarketA);
      vm.expectRevert(TransferAmountPolicy.TransferAmountLimitExceeded.selector);
      target.onTransfer(Allowed, Allowed, Allowed, maximum + 1, state, '');
      assertEq(
        features.scaledTransferVolume(MarketA),
        maximum * 3 - 1,
        'rejected amount not recorded'
      );
      assertFalse(
        target.isMarketTransferDisabled(MarketA),
        'positive limit keeps transfer promise'
      );
    }
  }

  function test_transferAmount_ObservationalVolumeCannotOverflowIntoTransferLock() external {
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      TransferFeatures features = TransferFeatures(address(target));
      providers[i].setCredential(Allowed, uint32(block.timestamp));
      features.setTransferAmountLimit(MarketA, type(uint256).max);
      MarketState memory state;
      vm.prank(MarketA);
      target.onTransfer(Allowed, Allowed, Allowed, type(uint256).max, state, '');
      vm.prank(MarketA);
      target.onTransfer(Allowed, Allowed, Allowed, 1, state, '');
      assertEq(
        features.scaledTransferVolume(MarketA),
        type(uint256).max,
        'observational total saturates'
      );
      assertFalse(target.isMarketTransferDisabled(MarketA));
    }
  }

  function test_transferRules_AmountFailurePrecedesRecipientFailureAndRollsBackCredentials()
    external
  {
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      TransferFeatures features = TransferFeatures(address(target));
      providers[i].setCredential(Restricted, uint32(block.timestamp));
      LenderStatus memory beforeStatus = target.getPreviousLenderStatus(Restricted);
      MarketState memory state;
      vm.prank(MarketA);
      vm.expectRevert(TransferAmountPolicy.TransferAmountLimitExceeded.selector);
      target.onTransfer(Allowed, Allowed, Restricted, InitialLimit + 1, state, '');
      assertEq(abi.encode(target.getPreviousLenderStatus(Restricted)), abi.encode(beforeStatus));
      assertFalse(target.isKnownLenderOnMarket(Restricted, MarketA), 'failed entry not known');
      assertEq(features.scaledTransferVolume(MarketA), 0);
      vm.prank(MarketA);
      vm.expectRevert(RecipientRestrictionPolicy.RecipientRestricted.selector);
      target.onTransfer(Allowed, Allowed, Restricted, InitialLimit, state, '');
      assertEq(features.scaledTransferVolume(MarketA), 0, 'later rule rolls back amount effect');
      assertEq(abi.encode(target.getPreviousLenderStatus(Restricted)), abi.encode(beforeStatus));
    }
  }

  function test_featureManagement_RequiresAdministratorAndRegistrationAndIsolatesMarkets()
    external
  {
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      TransferFeatures features = TransferFeatures(address(target));
      vm.prank(Allowed);
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      features.setTransferAmountLimit(MarketC, 0);
      vm.prank(Allowed);
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      features.setRestrictedRecipient(MarketC, Allowed);
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      features.setTransferAmountLimit(MarketC, 0);
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      features.setRestrictedRecipient(MarketC, Allowed);
      vm.expectRevert(TransferAmountPolicy.ZeroTransferAmountLimit.selector);
      features.setTransferAmountLimit(MarketA, 0);
      assertEq(features.maximumScaledTransfer(MarketA), InitialLimit);
      vm.expectEmit(address(target));
      emit RecipientRestrictionPolicy.RecipientRestrictionUpdated(MarketB, Allowed);
      features.setRestrictedRecipient(MarketB, Allowed);
      features.setTransferAmountLimit(MarketB, 7);
      assertEq(features.restrictedRecipient(MarketA), Restricted);
      assertEq(features.restrictedRecipient(MarketB), Allowed);
      assertEq(features.maximumScaledTransfer(MarketA), InitialLimit);
      assertEq(features.maximumScaledTransfer(MarketB), 7);
      features.setRestrictedRecipient(MarketB, address(0));
      assertEq(
        features.restrictedRecipient(MarketB),
        address(0),
        'restriction cleared only on this market'
      );
      MarketState memory state;
      vm.prank(MarketC);
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      target.onTransfer(Allowed, Allowed, Allowed, 0, state, '');
      assertEq(
        features.scaledTransferVolume(MarketC),
        0,
        'unregistered caller cannot write feature state'
      );
    }
  }

  function test_featureManagement_FollowsAdministratorTransferWithoutResettingState() external {
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      TransferFeatures features = TransferFeatures(address(target));
      providers[i].setCredential(Allowed, uint32(block.timestamp));
      MarketState memory state;
      vm.prank(MarketA);
      target.onTransfer(Allowed, Allowed, Allowed, 3, state, '');
      target.requestAdministratorTransfer(NewAdministrator);
      vm.prank(NewAdministrator);
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      features.setTransferAmountLimit(MarketA, 11);
      vm.prank(NewAdministrator);
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      features.setRestrictedRecipient(MarketA, Allowed);
      vm.prank(NewAdministrator);
      target.acceptAdministratorTransfer();
      assertEq(features.scaledTransferVolume(MarketA), 3);
      assertEq(features.restrictedRecipient(MarketA), Restricted);
      assertTrue(target.isKnownLenderOnMarket(Allowed, MarketA));
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      features.setTransferAmountLimit(MarketA, 11);
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      features.setRestrictedRecipient(MarketA, Allowed);
      vm.prank(NewAdministrator);
      features.setTransferAmountLimit(MarketA, 11);
      vm.prank(NewAdministrator);
      features.setRestrictedRecipient(MarketA, Allowed);
      assertEq(features.maximumScaledTransfer(MarketA), 11);
      assertEq(features.restrictedRecipient(MarketA), Allowed);
      assertEq(features.scaledTransferVolume(MarketA), 3, 'management does not erase activity');
      assertEq(features.maximumScaledTransfer(MarketB), InitialLimit);
    }
  }

  function test_composition_RetainsDepositQueueAprAndClosureRules() external {
    for (uint256 i; i < hooks.length; i++) {
      vm.warp(StartTimestamp);
      BaseHooks target = hooks[i];
      TransferFeatures features = TransferFeatures(address(target));
      providers[i].setCredential(Allowed, uint32(vm.getBlockTimestamp()));
      target.setMinimumDeposit(MarketA, 10);
      MarketState memory state;
      state.scaleFactor = uint112(RAY);
      state.annualInterestBips = 1_000;
      state.reserveRatioBips = 1_000;
      vm.prank(MarketA);
      vm.expectRevert(BaseHooks.DepositBelowMinimum.selector);
      target.onDeposit(Allowed, 9, state, '');
      vm.prank(MarketA);
      target.onDeposit(Allowed, 10, state, '');
      assertTrue(target.isKnownLenderOnMarket(Allowed, MarketA));
      if (i == uint256(HookKind.Fixed)) {
        vm.prank(MarketA);
        vm.expectRevert(FixedTermPolicy.NoReducingAprBeforeTermEnd.selector);
        target.onSetAnnualInterestAndReserveRatioBips(500, 0, state, '');
        vm.prank(MarketA);
        vm.expectRevert(FixedTermPolicy.WithdrawBeforeTermEnd.selector);
        target.onQueueWithdrawal(Allowed, 0, 1, state, '');
        vm.warp(FixedTermEnd);
      } else if (i == uint256(HookKind.Periodic)) {
        vm.prank(MarketA);
        vm.expectRevert(PeriodicTermPolicy.WithdrawOutsideWindow.selector);
        target.onQueueWithdrawal(Allowed, 0, 1, state, '');
        vm.warp(FirstWindowStart);
      }
      vm.prank(MarketA);
      target.onQueueWithdrawal(Allowed, 0, 1, state, '');
      vm.prank(MarketA);
      target.onCloseMarket(state, '');
      vm.warp(FixedTermEnd + PeriodDuration + WindowDuration);
      vm.prank(MarketA);
      target.onQueueWithdrawal(Allowed, 0, 1, state, '');
      vm.prank(MarketA);
      vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      target.onQueueWithdrawal(Restricted, 0, 1, state, '');
      assertEq(features.scaledTransferVolume(MarketA), 0, 'other actions do not record transfers');
      assertEq(features.maximumScaledTransfer(MarketA), InitialLimit);
    }
  }

  function test_composition_DisabledTransfersKeepPriorityOverBothFeatures() external {
    for (uint256 i; i < hooks.length; i++) {
      BaseHooks target = hooks[i];
      TransferFeatures features = TransferFeatures(address(target));
      _createCompositionMarket(HookKind(i), MarketC, EmptyHooksConfig, 7, 0, true);
      features.setRestrictedRecipient(MarketC, Restricted);
      vm.mockCall(MarketC, abi.encodeWithSignature('registeredWrapper()'), abi.encode(Restricted));
      assertTrue(target.isMarketTransferDisabled(MarketC));
      MarketState memory state;
      vm.prank(MarketC);
      vm.expectRevert(BaseHooks.TransfersDisabled.selector);
      target.onTransfer(Allowed, Allowed, Restricted, 8, state, '');
      assertEq(features.scaledTransferVolume(MarketC), 0);
    }
  }

  function test_composition_FitsRuntimeAndStoredInitcodeLimits() external {
    LibStoredInitCodeExternal lib = LibStoredInitCodeExternal(
      _deployCode('test/libraries/wrappers/LibStoredInitCodeExternal.sol:LibStoredInitCodeExternal')
    );
    for (uint256 i; i < hooks.length; i++) {
      bytes memory initCode = vm.getCode(_artifact(HookKind(i)));
      assertTrue(address(hooks[i]).code.length <= 24_576, 'runtime limit');
      assertTrue(initCode.length + 1 <= 24_576, 'stored initcode limit');
      assertTrue(
        initCode.length + abi.encode(address(this), bytes('')).length <= 49_152,
        'creation payload limit'
      );
      address stored = lib.deployInitCode(initCode);
      assertEq(
        stored.code,
        abi.encodePacked(bytes1(0), initCode),
        'actual STOP plus initcode deployment'
      );
    }
  }
}
