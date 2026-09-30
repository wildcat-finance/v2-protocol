// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { MathUtils, RAY, SECONDS_IN_365_DAYS } from 'src/libraries/MathUtils.sol';
import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';

/// @dev Characterizes unchanged revolving interest; no remediation is asserted.
contract RevolvingInterestDustReviewTest is ProductionMatrixFixture {
  function _reviewMarket(
    uint8 decimals,
    uint128 supply,
    MatrixHooksKind hooksKind,
    uint256 drawn
  ) internal returns (MatrixCell memory cell) {
    ProductionStack memory stack = _deployProductionStack();
    stack.asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode('Dust Review Asset', 'DRA', decimals)
      )
    );
    MatrixOptions memory options = _defaultMatrixOptions(hooksKind, MatrixMarketKind.Revolving);
    options.maxTotalSupply = supply;
    options.annualInterestBips = 1;
    options.commitmentFeeBips = 0;
    options.delinquencyFeeBips = 0;
    options.reserveRatioBips = 0;
    cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, 1);
    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, supply);
    vm.prank(MatrixBorrower);
    cell.market.borrow(drawn);
    assertEq(cell.market.decimals(), decimals);
  }

  function test_sixDecimalSmallestDrawHasNonzeroRateAtObservedSizedSupplies() external {
    uint256 start = vm.getBlockTimestamp();
    uint128[2] memory supplies = [uint128(1_000e6), uint128(110_000_000e6)];
    for (uint256 hook; hook < 2; hook++) {
      for (uint256 size; size < supplies.length; size++) {
        vm.warp(start);
        MatrixCell memory cell = _reviewMarket(6, supplies[size], MatrixHooksKind(hook), 1);
        vm.warp(start + 12);
        cell.market.updateState();
        // Fractional interest survives in the stored factor even if it is not
        // yet visible as a whole underlying token unit.
        assertTrue(cell.market.scaleFactor() > RAY);
      }
    }
  }

  function test_eighteenDecimalRepeatedCheckpointsLoseElevenAtomsAcrossHooks() external {
    uint256 start = vm.getBlockTimestamp();
    uint128 supply = 110_000_000e18;
    uint256 interestRay = MathUtils.calculateLinearInterestFromBips(1, 12);
    uint256 threshold = MathUtils.mulDivUp(supply, 1, interestRay);
    assertEq(threshold, 2_890_800_001);
    uint256 drawn = threshold - 1;
    for (uint256 hook; hook < 2; hook++) {
      vm.warp(start);
      MatrixCell memory frequent = _reviewMarket(18, supply, MatrixHooksKind(hook), drawn);
      MatrixCell memory once = _reviewMarket(18, supply, MatrixHooksKind(hook), drawn);
      for (uint256 interval = 1; interval <= 100; interval++) {
        vm.warp(start + interval * 12);
        frequent.market.updateState();
      }
      once.market.updateState();
      assertEq(frequent.market.scaleFactor(), RAY);
      assertEq(frequent.market.totalSupply(), supply);
      // Fixed drawn principal, no commitment/protocol/penalty rate: the ideal
      // interest for the same 1,200 seconds is exactly eleven atomic units.
      assertEq((drawn * 1_200) / (10_000 * SECONDS_IN_365_DAYS), 11);
      assertEq(once.market.totalSupply(), uint256(supply) + 11);
    }
  }

  function test_eighteenDecimalExactThresholdRetainsOneRayAcrossHooks() external {
    uint256 start = vm.getBlockTimestamp();
    uint128 supply = 110_000_000e18;
    uint256 threshold = MathUtils.mulDivUp(
      supply,
      1,
      MathUtils.calculateLinearInterestFromBips(1, 12)
    );
    for (uint256 hook; hook < 2; hook++) {
      vm.warp(start);
      MatrixCell memory cell = _reviewMarket(18, supply, MatrixHooksKind(hook), threshold);
      vm.warp(start + 12);
      cell.market.updateState();
      assertEq(cell.market.scaleFactor(), RAY + 1);
      assertEq(cell.market.totalSupply(), supply);
    }
  }

  function test_representationBoundaryIsNotAUniversalEconomicBound() external pure {
    // Synthetic arithmetic boundary at the initial factor, not a deployed or
    // economically representative market. The production utilization division
    // can discard thousands of atoms here while discarding less than one ray.
    uint256 supply = type(uint104).max;
    uint256 interestRay = MathUtils.calculateLinearInterestFromBips(1, 12);
    uint256 drawn = MathUtils.mulDivUp(supply, 1, interestRay) - 1;
    assertEq(MathUtils.mulDiv(interestRay, drawn, supply), 0);
    uint256 idealWholeAtoms = (drawn * 12) / (10_000 * SECONDS_IN_365_DAYS);
    assertEq(idealWholeAtoms, 20_282);
    assertTrue(idealWholeAtoms * RAY < supply);
  }
}
