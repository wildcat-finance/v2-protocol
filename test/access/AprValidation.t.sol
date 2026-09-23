// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { AprChange, AprRoute } from 'src/access/BaseHooks.sol';
import { TemporaryReserveRatio, MarketConstraintHooks } from 'src/access/MarketConstraintHooks.sol';
import { PeriodicTermPolicy } from 'src/access/PeriodicTermPolicy.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { Vm } from 'forge-std/Vm.sol';
import { AprValidationHooks } from '../mocks/AprValidationHooks.sol';
import { HookKind, HookTemplateFixture } from '../shared/HookTemplateFixture.sol';

contract AprValidationTest is HookTemplateFixture {
  AprValidationHooks internal target;

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
        ? abi.encodeWithSelector(AprValidationHooks.AprBelowFloor.selector, uint16(700))
        : abi.encodeWithSelector(AprValidationHooks.ReserveAboveCeiling.selector, uint16(2_000))
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
      abi.encodeWithSelector(AprValidationHooks.ReserveAboveCeiling.selector, uint16(2_000))
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
      abi.encodeWithSelector(AprValidationHooks.ReserveAboveCeiling.selector, uint16(2_000))
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
