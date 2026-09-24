// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { AprChange, AprRoute } from 'src/access/BaseHooks.sol';
import { BaseHooks } from 'src/access/BaseHooks.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { FixedTermPolicy } from 'src/access/FixedTermPolicy.sol';
import { TemporaryReserveRatio, MarketConstraintHooks } from 'src/access/MarketConstraintHooks.sol';
import { PeriodicTermPolicy } from 'src/access/PeriodicTermPolicy.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Vm } from 'forge-std/Vm.sol';
import { AprValidationHooks } from '../mocks/AprValidationHooks.sol';
import { AprValidationPolicy } from '../mocks/AprValidationPolicy.sol';
import { AprReplacementPolicy } from '../mocks/AprReplacementPolicy.sol';
import { OpenAprReplacementHooks } from '../mocks/AprReplacementHooks.sol';
import { TransferFeatures } from '../mocks/TransferFeaturePolicies.sol';
import { RecipientRestrictionPolicy } from '../mocks/TransferFeaturePolicies.sol';
import { TransferAmountPolicy } from '../mocks/TransferFeaturePolicies.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { LibStoredInitCodeExternal } from '../libraries/wrappers/LibStoredInitCodeExternal.sol';
import { HookKind, HookTemplateFixture } from '../shared/HookTemplateFixture.sol';

contract AprValidationTest is HookTemplateFixture {
  AprValidationHooks internal target;

  function _replacementArtifact(HookKind kind) private pure returns (string memory) {
    return
      kind == HookKind.Open
        ? 'test/mocks/AprReplacementHooks.sol:OpenAprReplacementHooks'
        : kind == HookKind.Fixed
        ? 'test/mocks/AprReplacementHooks.sol:FixedAprReplacementHooks'
        : 'test/mocks/AprReplacementHooks.sol:PeriodicAprReplacementHooks';
  }

  function _newReplacement(HookKind kind) private returns (BaseHooks replacement) {
    vm.warp(StartTimestamp);
    replacement = BaseHooks(
      _deployCode(_replacementArtifact(kind), abi.encode(address(this), bytes('')))
    );
    DeployMarketInputs memory inputs;
    inputs.maxTotalSupply = 1_000;
    inputs.hooks = EmptyHooksConfig
      .setHooksAddress(address(replacement))
      .setFlag(Bit_Enabled_Deposit)
      .setFlag(Bit_Enabled_Transfer)
      .setFlag(Bit_Enabled_QueueWithdrawal);
    replacement.onCreateMarket(address(this), MarketA, inputs, _marketData(kind, 10, false));
    replacement.onCreateMarket(address(this), MarketB, inputs, _marketData(kind, 10, false));
  }

  function _temporaryHashFor(BaseHooks replacement) private view returns (bytes32) {
    (uint16 apr, uint16 reserve, uint32 expiry) = replacement.temporaryExcessReserveRatio(MarketA);
    return keccak256(abi.encode(apr, reserve, expiry));
  }

  function _seedFor(BaseHooks replacement, TemporaryReserveRatio memory value) private {
    // all three replacement assemblies expose the same harness-only seeding API.
    OpenAprReplacementHooks(address(replacement)).seedTemporaryReserve(MarketA, value);
  }

  function _proposeFor(BaseHooks replacement, uint16 currentApr) private {
    vm.mockCall(
      MarketA,
      abi.encodeWithSignature('annualInterestBips()'),
      abi.encode(uint256(currentApr))
    );
    PeriodicTermPolicy(address(replacement)).proposeAnnualInterestBips(MarketA, 700);
  }

  function _proposalHashFor(BaseHooks replacement) private view returns (bytes32) {
    PeriodicTermPolicy periodic = PeriodicTermPolicy(address(replacement));
    (uint16 apr, uint32 timestamp) = periodic.pendingAprChanges(MarketA);
    (, uint32 start, uint32 end) = periodic.getPendingAprChange(MarketA);
    return keccak256(abi.encode(apr, timestamp, start, end));
  }

  function _assertSelectionLogs(
    address replacement,
    Vm.Log[] memory logs,
    uint16 apr,
    bool cancelledProposal
  ) private pure {
    uint256 selectionIndex = cancelledProposal ? 1 : 0;
    assertEq(logs.length, selectionIndex + 1, 'no skipped-default events');
    if (cancelledProposal) {
      assertEq(logs[0].emitter, replacement, 'cancellation owner');
      assertEq(
        logs[0].topics[0],
        keccak256('AnnualInterestBipsReductionProposalCancelled(address)'),
        'proposal cancellation'
      );
    }
    assertEq(logs[selectionIndex].emitter, replacement, 'selected-default event owner');
    assertEq(
      logs[selectionIndex].topics[0],
      keccak256('AprDefaultSelected(address,uint16,uint16)'),
      'selected-default event'
    );
    assertEq(logs[selectionIndex].topics[1], bytes32(uint256(uint160(MarketA))), 'selected market');
    assertEq(logs[selectionIndex].data, abi.encode(apr, uint16(3_333)), 'selected values');
  }

  function test_replacementDefaultSkipsTemporaryReserveEffectsAcrossTerms() external {
    for (uint256 i; i < 3; i++) {
      HookKind kind = HookKind(i);
      BaseHooks replacement = _newReplacement(kind);
      if (kind == HookKind.Fixed) vm.warp(FixedTermEnd);
      // periodic routes an initial reduction through its proposal, not the default helper.
      for (uint256 effect = kind == HookKind.Periodic ? 1 : 0; effect < 4; effect++) {
        MarketState memory state = _state();
        uint16 requestedApr = 600;
        TemporaryReserveRatio memory seeded;
        if (effect != 0) {
          state.annualInterestBips = 800;
          state.reserveRatioBips = 6_000;
          seeded = TemporaryReserveRatio(1_000, 2_000, uint32(vm.getBlockTimestamp() + 7 days));
          requestedApr = effect == 1 ? 900 : effect == 2 ? 1_000 : 800;
          if (effect == 3) seeded.expiry = uint32(vm.getBlockTimestamp());
        }
        // these inputs would activate, update, cancel, or expire the inherited default's period.
        _seedFor(replacement, seeded);
        bytes32 temporaryBefore = _temporaryHashFor(replacement);
        bytes32 proposalBefore;
        if (kind == HookKind.Periodic) {
          _proposeFor(replacement, state.annualInterestBips);
          proposalBefore = _proposalHashFor(replacement);
        }
        vm.recordLogs();
        vm.prank(MarketA);
        (uint16 apr, uint16 reserve) = replacement.onSetAnnualInterestAndReserveRatioBips(
          requestedApr,
          type(uint16).max,
          state,
          abi.encode('selected default')
        );
        _assertSelectionLogs(
          address(replacement),
          vm.getRecordedLogs(),
          requestedApr,
          kind == HookKind.Periodic && effect != 3
        );
        assertEq(apr, requestedApr, 'selected APR');
        assertEq(reserve, 3_333, 'selected reserve');
        assertEq(
          AprReplacementPolicy(address(replacement)).lastSelectedApr(MarketA),
          apr,
          'selected effect'
        );
        assertEq(
          AprReplacementPolicy(address(replacement)).lastSelectedApr(MarketB),
          0,
          'other market unchanged'
        );
        assertEq(
          _temporaryHashFor(replacement),
          temporaryBefore,
          'skipped default state untouched'
        );
        if (kind == HookKind.Periodic) {
          if (effect == 3)
            assertEq(_proposalHashFor(replacement), proposalBefore, 'equality retains proposal');
          else {
            (, uint32 timestamp) = PeriodicTermPolicy(address(replacement)).pendingAprChanges(
              MarketA
            );
            assertEq(timestamp, 0, 'increase cancels proposal');
          }
        }
      }
    }
  }

  function test_replacementDefaultRetainsInclusiveAprBounds() external {
    uint16[4] memory values = [uint16(0), 10_000, 10_001, type(uint16).max];
    for (uint256 i; i < 3; i++) {
      BaseHooks replacement = _newReplacement(HookKind(i));
      MarketState memory state = _state();
      state.annualInterestBips = 0;
      _seedFor(replacement, TemporaryReserveRatio(1_000, 2_000, StartTimestamp));
      bytes32 temporaryBefore = _temporaryHashFor(replacement);
      for (uint256 j; j < values.length; j++) {
        vm.prank(MarketA);
        if (values[j] > 10_000) {
          vm.expectRevert(MarketConstraintHooks.AnnualInterestBipsOutOfBounds.selector);
          replacement.onSetAnnualInterestAndReserveRatioBips(values[j], 0, state, '');
          assertEq(
            AprReplacementPolicy(address(replacement)).lastSelectedApr(MarketA),
            10_000,
            'bounds reject before selected effect'
          );
        } else {
          (uint16 apr, uint16 reserve) = replacement.onSetAnnualInterestAndReserveRatioBips(
            values[j],
            0,
            state,
            ''
          );
          assertEq(apr, values[j], 'inclusive APR boundary');
          assertEq(reserve, 3_333, 'bounded replacement reserve');
        }
        assertEq(_temporaryHashFor(replacement), temporaryBefore, 'bounds preserve default state');
      }
    }
  }

  function test_replacementValidationRejectsEffectiveValuesAndRollsBackSelection() external {
    for (uint256 i; i < 3; i++) {
      BaseHooks replacement = _newReplacement(HookKind(i));
      AprReplacementPolicy feature = AprReplacementPolicy(address(replacement));
      MarketState memory state = _state();
      vm.prank(MarketA);
      replacement.onSetAnnualInterestAndReserveRatioBips(1_000, 0, state, '');
      _seedFor(replacement, TemporaryReserveRatio(2_000, 1_500, StartTimestamp + 7 days));
      bytes32 temporaryBefore = _temporaryHashFor(replacement);
      bytes32 proposalBefore;
      if (i == uint256(HookKind.Periodic)) {
        _proposeFor(replacement, 1_000);
        proposalBefore = _proposalHashFor(replacement);
      }
      for (uint256 rejectApr; rejectApr < 2; rejectApr++) {
        feature.setValidationBounds(rejectApr == 1 ? 1_101 : 0, rejectApr == 1 ? 10_000 : 3_332);
        vm.prank(MarketA);
        vm.expectRevert(
          rejectApr == 1
            ? abi.encodeWithSelector(AprValidationPolicy.AprBelowFloor.selector, uint16(1_100))
            : abi.encodeWithSelector(
              AprValidationPolicy.ReserveAboveCeiling.selector,
              uint16(3_333)
            )
        );
        // requested/current reserves pass. only the selected 3,333 exceeds this ceiling.
        replacement.onSetAnnualInterestAndReserveRatioBips(1_100, 0, state, '');
        assertEq(feature.lastSelectedApr(MarketA), 1_000, 'selected effect rolled back');
        assertEq(_temporaryHashFor(replacement), temporaryBefore, 'seeded default untouched');
        if (i == uint256(HookKind.Periodic))
          assertEq(_proposalHashFor(replacement), proposalBefore, 'cancellation rolled back');
      }
      feature.setValidationBounds(1_100, 3_333);
      // record only this successful call. reverted traces may still contain emitted events.
      vm.recordLogs();
      vm.prank(MarketA);
      (uint16 apr, uint16 reserve) = replacement.onSetAnnualInterestAndReserveRatioBips(
        1_100,
        type(uint16).max,
        state,
        ''
      );
      _assertSelectionLogs(
        address(replacement),
        vm.getRecordedLogs(),
        1_100,
        i == uint256(HookKind.Periodic)
      );
      assertEq(apr, 1_100, 'effective APR at floor');
      assertEq(reserve, 3_333, 'effective reserve at ceiling');
      assertEq(feature.lastSelectedApr(MarketA), 1_100, 'selected effect committed');
      assertEq(
        _temporaryHashFor(replacement),
        temporaryBefore,
        'successful replacement skips default'
      );
    }
  }

  function test_replacementFixedMaturityPrecedesEffectiveValueValidation() external {
    BaseHooks replacement = _newReplacement(HookKind.Fixed);
    AprReplacementPolicy feature = AprReplacementPolicy(address(replacement));
    MarketState memory state = _state();
    vm.prank(MarketA);
    replacement.onSetAnnualInterestAndReserveRatioBips(1_000, 0, state, '');
    feature.setValidationBounds(700, 3_333);
    vm.warp(FixedTermEnd - 1);
    vm.prank(MarketA);
    vm.expectRevert(FixedTermPolicy.NoReducingAprBeforeTermEnd.selector);
    replacement.onSetAnnualInterestAndReserveRatioBips(600, 0, state, '');
    assertEq(feature.lastSelectedApr(MarketA), 1_000, 'maturity guard precedes replacement');

    vm.warp(FixedTermEnd);
    vm.prank(MarketA);
    vm.expectRevert(
      abi.encodeWithSelector(AprValidationPolicy.AprBelowFloor.selector, uint16(600))
    );
    replacement.onSetAnnualInterestAndReserveRatioBips(600, 0, state, '');
    assertEq(
      feature.lastSelectedApr(MarketA),
      1_000,
      'validation rolls back replacement at maturity'
    );
    feature.setValidationBounds(600, 3_333);
    vm.prank(MarketA);
    (uint16 apr, uint16 reserve) = replacement.onSetAnnualInterestAndReserveRatioBips(
      600,
      0,
      state,
      ''
    );
    assertEq(apr, 600, 'reduction allowed at maturity');
    assertEq(reserve, 3_333, 'selected calculation after maturity');
  }

  function _replacementReduction(
    BaseHooks replacement,
    bool dedicated,
    MarketState memory state
  ) private returns (uint16 apr, uint16 reserve) {
    vm.prank(MarketA);
    if (dedicated) {
      return (
        PeriodicTermPolicy(address(replacement)).executePendingAnnualInterestBipsReduction(state),
        state.reserveRatioBips
      );
    }
    return replacement.onSetAnnualInterestAndReserveRatioBips(700, 0, state, 'replacement route');
  }

  function test_replacementPeriodicReductionBypassesDefaultOnBothRoutes(
    bool dedicated,
    bool rejectApr
  ) external {
    BaseHooks replacement = _newReplacement(HookKind.Periodic);
    AprReplacementPolicy feature = AprReplacementPolicy(address(replacement));
    MarketState memory state = _state();
    vm.prank(MarketA);
    replacement.onSetAnnualInterestAndReserveRatioBips(1_000, 0, state, '');
    _seedFor(replacement, TemporaryReserveRatio(1_100, 1_500, StartTimestamp + 7 days));
    _proposeFor(replacement, 1_000);
    _ready();
    bytes32 temporaryBefore = _temporaryHashFor(replacement);
    bytes32 proposalBefore = _proposalHashFor(replacement);
    feature.setValidationBounds(rejectApr ? 701 : 0, rejectApr ? 10_000 : 1_999);
    vm.expectRevert(
      rejectApr
        ? abi.encodeWithSelector(AprValidationPolicy.AprBelowFloor.selector, uint16(700))
        : abi.encodeWithSelector(AprValidationPolicy.ReserveAboveCeiling.selector, uint16(2_000))
    );
    _replacementReduction(replacement, dedicated, state);
    assertEq(_proposalHashFor(replacement), proposalBefore, 'rejected reduction retains proposal');
    assertEq(
      _temporaryHashFor(replacement),
      temporaryBefore,
      'rejected reduction retains default state'
    );
    assertEq(
      feature.lastSelectedApr(MarketA),
      1_000,
      'rejected reduction has no replacement effect'
    );

    feature.setValidationBounds(700, 2_000);
    vm.recordLogs();
    (uint16 apr, uint16 reserve) = _replacementReduction(replacement, dedicated, state);
    Vm.Log[] memory logs = vm.getRecordedLogs();
    assertEq(apr, 700, 'exact proposed APR');
    assertEq(reserve, 2_000, 'current reserves, not replacement reserves');
    assertEq(feature.lastSelectedApr(MarketA), 1_000, 'successful reduction bypasses replacement');
    assertEq(
      _temporaryHashFor(replacement),
      temporaryBefore,
      'successful reduction skips original default'
    );
    (uint16 pendingApr, uint32 timestamp) = PeriodicTermPolicy(address(replacement))
      .pendingAprChanges(MarketA);
    assertEq(pendingApr, 0, 'proposal consumed');
    assertEq(timestamp, 0, 'proposal timestamp cleared');
    assertEq(logs.length, 1, 'no original or replacement default event');
    assertEq(logs[0].emitter, address(replacement), 'execution event owner');
    assertEq(
      logs[0].topics[0],
      keccak256('AnnualInterestBipsReductionExecuted(address,uint16)'),
      'execution event'
    );
    assertEq(logs[0].data, abi.encode(uint16(700)), 'executed APR');
  }

  function test_replacementRetainsAccessTransferScheduleAndManagementChecks() external {
    address lender = address(0xA11CE);
    address restricted = address(0xB0B);
    address outsider = address(0xBAD);
    for (uint256 i; i < 3; i++) {
      HookKind kind = HookKind(i);
      BaseHooks replacement = _newReplacement(kind);
      AprReplacementPolicy feature = AprReplacementPolicy(address(replacement));
      TransferFeatures transfers = TransferFeatures(address(replacement));
      MarketState memory state = _state();
      state.scaleFactor = 1e27;
      vm.prank(MarketA);
      replacement.onSetAnnualInterestAndReserveRatioBips(1_000, 0, state, '');
      vm.prank(outsider);
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      feature.setValidationBounds(9_999, 0);
      assertEq(feature.minimumApr(), 0, 'unauthorized floor unchanged');
      assertEq(feature.maximumReserve(), 10_000, 'unauthorized ceiling unchanged');
      vm.prank(outsider);
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      transfers.setTransferAmountLimit(MarketA, 10);
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      transfers.setRestrictedRecipient(MarketC, restricted);
      vm.prank(outsider);
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      _seedFor(replacement, TemporaryReserveRatio(1_000, 2_000, StartTimestamp));

      vm.prank(MarketA);
      vm.expectRevert(BaseHooks.DepositBelowMinimum.selector);
      replacement.onDeposit(lender, 9, state, '');
      vm.prank(MarketA);
      vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      replacement.onDeposit(lender, 10, state, '');
      MockRoleProvider provider = MockRoleProvider(
        _deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider')
      );
      replacement.addRoleProvider(address(provider), type(uint32).max);
      vm.startPrank(address(provider));
      replacement.grantRole(lender, StartTimestamp);
      replacement.grantRole(restricted, StartTimestamp);
      vm.stopPrank();
      vm.prank(MarketA);
      replacement.onDeposit(lender, 10, state, '');
      assertTrue(
        replacement.isKnownLenderOnMarket(lender, MarketA),
        'deposit bookkeeping retained'
      );
      transfers.setRestrictedRecipient(MarketA, restricted);
      transfers.setTransferAmountLimit(MarketA, 10);
      vm.prank(MarketA);
      vm.expectRevert(RecipientRestrictionPolicy.RecipientRestricted.selector);
      replacement.onTransfer(lender, lender, restricted, 10, state, '');
      assertEq(transfers.scaledTransferVolume(MarketA), 0, 'recipient rejection restores volume');
      vm.prank(MarketA);
      vm.expectRevert(TransferAmountPolicy.TransferAmountLimitExceeded.selector);
      replacement.onTransfer(lender, lender, lender, 11, state, '');
      vm.prank(MarketA);
      replacement.onTransfer(lender, lender, lender, 10, state, '');
      assertEq(
        transfers.scaledTransferVolume(MarketA),
        10,
        'both transfer rules allow valid action'
      );

      if (kind != HookKind.Open) {
        vm.prank(MarketA);
        vm.expectRevert(
          kind == HookKind.Fixed
            ? FixedTermPolicy.WithdrawBeforeTermEnd.selector
            : PeriodicTermPolicy.WithdrawOutsideWindow.selector
        );
        replacement.onQueueWithdrawal(lender, 0, 1, state, '');
        vm.warp(kind == HookKind.Fixed ? FixedTermEnd : FirstWindowStart);
      }
      vm.prank(MarketA);
      vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      replacement.onQueueWithdrawal(outsider, 0, 1, state, '');
      vm.prank(MarketA);
      replacement.onQueueWithdrawal(lender, 0, 1, state, '');
    }
  }

  function test_replacementArtifactsFitRuntimeAndStoredInitcodeLimits() external {
    LibStoredInitCodeExternal storageDeployer = LibStoredInitCodeExternal(
      _deployCode('test/libraries/wrappers/LibStoredInitCodeExternal.sol:LibStoredInitCodeExternal')
    );
    for (uint256 i; i < 3; i++) {
      HookKind kind = HookKind(i);
      BaseHooks replacement = _newReplacement(kind);
      bytes memory creation = vm.getCode(_replacementArtifact(kind));
      address stored = storageDeployer.deployInitCode(creation);
      assertEq(stored.code, abi.encodePacked(hex'00', creation), 'actual stored initcode');
      assertTrue(stored.code.length <= 24_576, 'stored initcode limit');
      assertTrue(address(replacement).code.length <= 24_576, 'runtime limit');
      assertTrue(
        abi.encodePacked(creation, abi.encode(address(this), bytes(''))).length <= 49_152,
        'constructor payload limit'
      );
    }
  }

  function setUp() external {
    vm.warp(StartTimestamp);
    target = AprValidationHooks(
      _deployCode('test/mocks/AprValidationHooks.sol:AprValidationHooks', abi.encode(address(this)))
    );
    _createMarket(target, MarketA, EmptyHooksConfig, _termData(HookKind.Periodic));
    vm.mockCall(
      MarketA,
      abi.encodeWithSignature('annualInterestBips()'),
      abi.encode(uint256(1_000))
    );
    target.proposeAnnualInterestBips(MarketA, 700);
  }

  function _state() internal pure returns (MarketState memory state) {
    state.annualInterestBips = 1_000;
    state.reserveRatioBips = 2_000;
  }

  function _ready() internal {
    vm.warp(FirstWindowStart + WindowDuration);
  }

  function _proposalHash() internal view returns (bytes32) {
    (uint16 apr, uint32 timestamp) = target.pendingAprChanges(MarketA);
    (, uint32 start, uint32 end) = target.getPendingAprChange(MarketA);
    return keccak256(abi.encode(apr, timestamp, start, end));
  }

  function _temporaryHash() internal view returns (bytes32) {
    (uint16 apr, uint16 reserve, uint32 expiry) = target.temporaryExcessReserveRatio(MarketA);
    return keccak256(abi.encode(apr, reserve, expiry));
  }

  function _seedTemporaryReserve(uint32 expiry) internal {
    target.seedTemporaryReserve(MarketA, TemporaryReserveRatio(1_000, 2_000, expiry));
  }

  function _reduce(
    bool dedicated,
    uint16 requestedReserve,
    MarketState memory state,
    bytes memory data
  ) internal returns (uint16 apr, uint16 reserve) {
    vm.prank(MarketA);
    if (dedicated) {
      return (target.executePendingAnnualInterestBipsReduction(state), state.reserveRatioBips);
    }
    return target.onSetAnnualInterestAndReserveRatioBips(700, requestedReserve, state, data);
  }

  function _assertChange(
    AprRoute route,
    uint16 requestedApr,
    uint16 requestedReserve,
    uint16 effectiveApr,
    uint16 effectiveReserve,
    MarketState memory state,
    bytes memory data
  ) internal view {
    AprChange memory expected = AprChange(
      MarketA,
      route,
      requestedApr,
      requestedReserve,
      effectiveApr,
      effectiveReserve
    );
    assertEq(abi.encode(target.lastChange()), abi.encode(expected), 'applied change context');
    assertEq(target.lastStateHash(), keccak256(abi.encode(state)), 'original market state');
    assertEq(target.lastData(), data, 'callback data');
  }

  function test_periodicReduction_ValidatesBothRoutesWithoutDefaultEffects(
    bool dedicated,
    bool seeded,
    uint16 requestedReserve,
    bytes calldata data
  ) external {
    _ready();
    if (seeded) _seedTemporaryReserve(uint32(block.timestamp + 1 days));
    bytes32 temporaryBefore = _temporaryHash();
    MarketState memory state = _state();
    vm.recordLogs();
    (uint16 apr, uint16 reserve) = _reduce(dedicated, requestedReserve, state, data);
    assertEq(apr, 700, 'proposal APR');
    assertEq(reserve, state.reserveRatioBips, 'current reserves');
    assertEq(_temporaryHash(), temporaryBefore, 'default state untouched');
    assertEq(target.proposalTimestampAtValidation(), 0, 'proposal removed before validation');
    _assertChange(
      dedicated ? AprRoute.PendingReduction : AprRoute.Ordinary,
      700,
      dedicated ? state.reserveRatioBips : requestedReserve,
      apr,
      reserve,
      state,
      dedicated ? bytes('') : data
    );
    Vm.Log[] memory logs = vm.getRecordedLogs();
    assertEq(logs.length, 1, 'execution event only');
    assertEq(logs[0].emitter, address(target), 'event owner');
    assertEq(
      logs[0].topics[0],
      keccak256('AnnualInterestBipsReductionExecuted(address,uint16)'),
      'execution event'
    );
  }

  function test_periodicReduction_RejectionRestoresProposalOnBothRoutes(
    bool dedicated,
    bool rejectApr
  ) external {
    _ready();
    _seedTemporaryReserve(uint32(block.timestamp + 1 days));
    bytes32 proposalBefore = _proposalHash();
    bytes32 temporaryBefore = _temporaryHash();
    MarketState memory state = _state();
    target.setValidationBounds(rejectApr ? 701 : 0, rejectApr ? 10_000 : 1_999);
    vm.expectRevert(
      rejectApr
        ? abi.encodeWithSelector(AprValidationPolicy.AprBelowFloor.selector, uint16(700))
        : abi.encodeWithSelector(AprValidationPolicy.ReserveAboveCeiling.selector, uint16(2_000))
    );
    _reduce(dedicated, 0, state, '');
    assertEq(_proposalHash(), proposalBefore, 'proposal deletion rolled back');
    assertEq(_temporaryHash(), temporaryBefore, 'temporary state preserved');
    assertEq(target.lastChange().market, address(0), 'no accepted change');

    target.setValidationBounds(0, 10_000);
    _reduce(dedicated, 0, state, '');
    (uint16 apr, uint32 timestamp) = target.pendingAprChanges(MarketA);
    assertEq(apr, 0, 'proposal consumed on retry');
    assertEq(timestamp, 0, 'timestamp cleared');
  }

  function test_periodicIncrease_ValidatesEffectiveReservesAndRollsBackCancellation() external {
    MarketState memory state = _state();
    bytes32 proposalBefore = _proposalHash();
    target.setValidationBounds(0, 1_999);
    vm.prank(MarketA);
    vm.expectRevert(
      abi.encodeWithSelector(AprValidationPolicy.ReserveAboveCeiling.selector, uint16(2_000))
    );
    target.onSetAnnualInterestAndReserveRatioBips(1_100, 0, state, '');
    assertEq(_proposalHash(), proposalBefore, 'cancellation rolled back');

    target.setValidationBounds(0, 2_000);
    bytes memory data = abi.encode('increase');
    vm.expectEmit(address(target));
    emit PeriodicTermPolicy.AnnualInterestBipsReductionProposalCancelled(MarketA);
    vm.prank(MarketA);
    (uint16 apr, uint16 reserve) = target.onSetAnnualInterestAndReserveRatioBips(
      1_100,
      type(uint16).max,
      state,
      data
    );
    assertEq(apr, 1_100, 'increased APR');
    assertEq(reserve, 2_000, 'requested reserves ignored');
    assertEq(target.proposalTimestampAtValidation(), 0, 'cancellation before validation');
    _assertChange(AprRoute.Ordinary, 1_100, type(uint16).max, apr, reserve, state, data);
  }

  function test_periodicEquality_ValidatesRestoredReserveAndRollsBackDefaultEffects() external {
    _seedTemporaryReserve(StartTimestamp);
    MarketState memory state = _state();
    state.annualInterestBips = 800;
    state.reserveRatioBips = 6_000;
    bytes32 proposalBefore = _proposalHash();
    bytes32 temporaryBefore = _temporaryHash();
    target.setValidationBounds(0, 1_999);
    vm.prank(MarketA);
    vm.expectRevert(
      abi.encodeWithSelector(AprValidationPolicy.ReserveAboveCeiling.selector, uint16(2_000))
    );
    target.onSetAnnualInterestAndReserveRatioBips(800, 0, state, '');
    assertEq(_temporaryHash(), temporaryBefore, 'default expiry rolled back');
    assertEq(_proposalHash(), proposalBefore, 'equality retains proposal');

    target.setValidationBounds(0, 2_000);
    vm.expectEmit(address(target));
    emit MarketConstraintHooks.TemporaryExcessReserveRatioExpired(MarketA);
    vm.prank(MarketA);
    (uint16 apr, uint16 reserve) = target.onSetAnnualInterestAndReserveRatioBips(
      800,
      type(uint16).max,
      state,
      ''
    );
    assertEq(reserve, 2_000, 'restored reserves pass despite requested and current reserves');
    assertEq(_temporaryHash(), keccak256(abi.encode(uint16(0), uint16(0), uint32(0))), 'expired');
    assertEq(_proposalHash(), proposalBefore, 'proposal still retained');
    assertEq(target.proposalTimestampAtValidation(), StartTimestamp, 'proposal visible to check');
    _assertChange(AprRoute.Ordinary, 800, type(uint16).max, apr, reserve, state, '');
  }

  function test_dedicatedReduction_PassesEmptyDataEvenWithTrailingCalldata(
    bytes calldata data
  ) external {
    _ready();
    MarketState memory state = _state();
    bytes memory payload = bytes.concat(
      abi.encodeCall(target.executePendingAnnualInterestBipsReduction, (state)),
      data
    );
    vm.prank(MarketA);
    (bool success, bytes memory result) = address(target).call(payload);
    assertTrue(success, 'dedicated execution');
    assertEq(abi.decode(result, (uint16)), 700, 'dedicated APR');
    _assertChange(AprRoute.PendingReduction, 700, 2_000, 700, 2_000, state, '');
  }
}
