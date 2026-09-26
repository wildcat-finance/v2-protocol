// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MarketMatrixFixture } from './MarketMatrixFixture.sol';
import { LifecycleHandler } from './LifecycleHandler.sol';

abstract contract LifecycleFixture is MarketMatrixFixture {
  LifecycleHandler internal lifecycle;

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
    lifecycle.borrow(type(uint256).max);
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
    assertTrue(lifecycle.scaledSupplyIsConserved(), 'scaled supply');
    assertTrue(lifecycle.withdrawalLiabilitiesAreConserved(), 'withdrawal liabilities');
    assertTrue(lifecycle.protocolFeesAreConserved(), 'protocol fees');
  }
}
