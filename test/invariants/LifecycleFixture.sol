// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MarketMatrixFixture } from './MarketMatrixFixture.sol';
import { LifecycleHandler } from './LifecycleHandler.sol';
import { MarketMatrixHandler } from './MarketMatrixHandler.sol';

abstract contract LifecycleFixture is MarketMatrixFixture {
  LifecycleHandler internal lifecycle;
  bool private coverageReported;

  function _setupLifecycle() internal {
    vm.warp(1_800_000_000);
    address[] memory actors = _actors();
    MatrixDeployment memory m = _deployMatrix(actors);
    lifecycle = new LifecycleHandler(
      m.markets,
      m.assets,
      m.sentinels,
      m.periodicHooks,
      m.hooksKinds,
      m.revolving,
      m.fixedTermEnds,
      m.commitmentFeeBips,
      actors
    );
    lifecycle.seedAccountingCoverage();
    lifecycle.drawAvailable();
  }

  function _matrixOptions(
    uint8 kind,
    bool isRevolving
  ) internal view virtual override returns (Options memory options) {
    options = super._matrixOptions(kind, isRevolving);
    options.delinquencyFeeBips = kind == FixedTerm ? 0 : 1_000;
    options.repaymentDate = uint32(vm.getBlockTimestamp() + 60 days);
    options.repaymentPeriod = kind == OpenTerm ? 0 : kind == FixedTerm ? 7 days : 90 days;
  }

  function _assertLifecycle() internal view {
    assertEq(lifecycle.firstFailure(), 0, 'lifecycle oracle');
    assertTrue(lifecycle.viewsMatchOracle(), 'lifecycle views');
    assertEq(lifecycle.unexpectedActionFailures(), 0, 'unexpected action');
    assertEq(lifecycle.drawnAmountFailures(), 0, 'drawn principal');
    assertEq(lifecycle.utilizationInterestFailures(), 0, 'utilization interest');
    assertEq(lifecycle.withdrawalGateViolations(), 0, 'withdrawal gate');
    assertEq(lifecycle.arithmeticPanicCount(), 0, 'panic');
    assertEq(lifecycle.sanctionsFailures(), 0, 'sanctions');
    assertTrue(lifecycle.scaleFactorsAreValid(), 'scale factor');
    assertTrue(lifecycle.scaledSupplyIsConserved(), 'scaled supply');
    assertTrue(lifecycle.withdrawalLiabilitiesAreConserved(), 'withdrawal liabilities');
    assertTrue(lifecycle.protocolFeesAreConserved(), 'protocol fees');
  }

  function _lifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
    selectors = new bytes4[](26);
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
    selectors[17] = LifecycleHandler.advance.selector;
    selectors[18] = LifecycleHandler.checkpoint.selector;
    selectors[19] = LifecycleHandler.fund.selector;
    selectors[20] = LifecycleHandler.donate.selector;
    selectors[21] = LifecycleHandler.probeAdmission.selector;
    selectors[22] = LifecycleHandler.changeApr.selector;
    selectors[23] = LifecycleHandler.collectClaim.selector;
    selectors[24] = LifecycleHandler.collectClaims.selector;
    selectors[25] = LifecycleHandler.recoverSurplus.selector;
  }

  function _finishLifecycle(string memory campaign) internal {
    // optional research receipts, captured before the forced final unwind. don't count the
    // liveness proof as randomized coverage, and don't write files in ordinary test runs.
    string memory output = vm.envOr('E17_COVERAGE_FILE', string(''));
    if (!coverageReported && bytes(output).length != 0) {
      for (uint256 i; i < MatrixSize; ++i) {
        vm.writeLine(
          output,
          string.concat(
            '{"campaign":"',
            campaign,
            '","cell":',
            vm.toString(i),
            ',"seeded":"',
            vm.toString(abi.encode(lifecycle.coverageSnapshot(i, true))),
            '","explored":"',
            vm.toString(abi.encode(lifecycle.coverageSnapshot(i, false))),
            '"}'
          )
        );
      }
    }
    coverageReported = true;
    (, uint256 failure) = lifecycle.unwindAndDrain();
    assertEq(failure, 0, 'scheduled unwind');
    _assertLifecycle();
  }
}

abstract contract PenaltyLifecycleFixture is LifecycleFixture {
  function _setupPenaltyLifecycle() internal {
    _setupLifecycle();
    vm.warp(vm.getBlockTimestamp() + 1 days);
    lifecycle.updateState();
  }

  function _matrixOptions(
    uint8 kind,
    bool isRevolving
  ) internal view override returns (Options memory options) {
    options = super._matrixOptions(kind, isRevolving);
    options.repaymentDate = kind == OpenTerm ? 0 : uint32(vm.getBlockTimestamp() + 365 days);
    options.repaymentPeriod = kind == OpenTerm ? 0 : 90 days;
  }

  function _fixedTermDelay() internal pure override returns (uint256) {
    return 180 days;
  }
}
