// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { StdInvariant } from 'forge-std/StdInvariant.sol';
import { MarketMatrixFixture } from './MarketMatrixFixture.sol';
import { MarketMatrixHandler } from './MarketMatrixHandler.sol';

/// @dev One concrete invariant suite owns all six built-in hook × market cells.
///      This keeps the action budget per cell while avoiding six copies of the
///      fixture, handler, and invariant bytecode.
contract MarketMatrixInvariantTest is MarketMatrixFixture, StdInvariant {
  MarketMatrixHandler internal handler;

  function setUp() external {
    address[] memory actors = _actors();
    MatrixDeployment memory matrix = _deployMatrix(actors);

    handler = new MarketMatrixHandler(
      matrix.markets,
      matrix.assets,
      matrix.sentinels,
      matrix.periodicHooks,
      matrix.hooksKinds,
      matrix.revolving,
      matrix.fixedTermEnds,
      matrix.commitmentFeeBips,
      actors
    );
    handler.seedAccountingCoverage();

    _targetHandler();
  }

  function _targetHandler() internal {
    bytes4[] memory selectors = new bytes4[](17);
    selectors[0] = MarketMatrixHandler.deposit.selector;
    selectors[1] = MarketMatrixHandler.transfer.selector;
    selectors[2] = MarketMatrixHandler.borrow.selector;
    selectors[3] = MarketMatrixHandler.repay.selector;
    selectors[4] = MarketMatrixHandler.queueWithdrawal.selector;
    selectors[5] = MarketMatrixHandler.queueWithdrawalScaled.selector;
    selectors[6] = MarketMatrixHandler.queueFullWithdrawal.selector;
    selectors[7] = MarketMatrixHandler.executeWithdrawal.selector;
    selectors[8] = MarketMatrixHandler.repayAndProcess.selector;
    selectors[9] = MarketMatrixHandler.updateState.selector;
    selectors[10] = MarketMatrixHandler.collectFees.selector;
    selectors[11] = MarketMatrixHandler.warp.selector;
    selectors[12] = MarketMatrixHandler.sanctionLender.selector;
    selectors[13] = MarketMatrixHandler.sanctionBorrower.selector;
    selectors[14] = MarketMatrixHandler.nukeFromOrbit.selector;
    selectors[15] = MarketMatrixHandler.proposeAprReduction.selector;
    selectors[16] = MarketMatrixHandler.executeAprReduction.selector;
    targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    targetContract(address(handler));
  }

  function invariant_withdrawalGatesAreEnforcedAcrossTheMatrix() external view {
    assertEq(handler.withdrawalGateViolations(), 0, 'withdrawal gate');
  }

  function invariant_scaleFactorsNeverDecreaseAcrossTheMatrix() external view {
    assertTrue(handler.scaleFactorsAreValid(), 'scale factor');
  }

  function invariant_drawnPrincipalFollowsRevolvingRules() external view {
    assertTrue(handler.drawnAmountTransitionsAreValid(), 'drawn principal');
  }

  function invariant_revolvingUtilizationInterestMatchesTheFormula() external view {
    assertEq(handler.utilizationInterestFailures(), 0, 'utilization interest');
  }

  function invariant_scaledSupplyIsConservedAcrossTheMatrix() external view {
    assertTrue(handler.scaledSupplyIsConserved(), 'scaled supply');
  }

  function invariant_withdrawalLiabilitiesAreConservedAcrossTheMatrix() external view {
    assertTrue(handler.withdrawalLiabilitiesAreConserved(), 'withdrawal liabilities');
  }

  function invariant_protocolFeesAreConservedAcrossTheMatrix() external view {
    assertTrue(handler.protocolFeesAreConserved(), 'protocol fee conservation');
  }

  function invariant_underwaterAndRandomizedPathsDoNotPanic() external view {
    assertEq(handler.arithmeticPanicCount(), 0, 'arithmetic panic');
  }

  function invariant_sanctionsAndExpectedActionsRemainSafe() external view {
    assertEq(handler.sanctionsFailures(), 0, 'sanctions');
    assertEq(handler.unexpectedActionFailures(), 0, 'unexpected action failure');
  }

  function afterInvariant() external {
    (, uint256 failureCode) = handler.unwindAndDrain();
    assertEq(failureCode, 0, 'matrix unwind');
  }
}
