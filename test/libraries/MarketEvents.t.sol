// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/interfaces/IMarketEventsAndErrors.sol';
import 'src/libraries/MarketEvents.sol';

contract MarketEventsHarness {
  function emitMaxTotalSupplyUpdated(address caller, uint256 previousValue, uint256 newValue) external {
    emit_MaxTotalSupplyUpdated(caller, previousValue, newValue);
  }

  function emitProtocolFeeBipsUpdated(address caller, uint256 previousValue, uint256 newValue) external {
    emit_ProtocolFeeBipsUpdated(caller, previousValue, newValue);
  }

  function emitAnnualInterestAndReserveRatioBipsUpdated(
    address caller,
    uint256 previousAnnualInterestBips,
    uint256 newAnnualInterestBips,
    uint256 previousReserveRatioBips,
    uint256 newReserveRatioBips
  ) external {
    emit_AnnualInterestAndReserveRatioBipsUpdated(
      caller,
      previousAnnualInterestBips,
      newAnnualInterestBips,
      previousReserveRatioBips,
      newReserveRatioBips
    );
  }

  function emitBorrow(address borrower, uint256 amount) external {
    emit_Borrow(borrower, amount);
  }

  function emitDrawnAmountUpdated(uint256 previousValue, uint256 newValue) external {
    emit_DrawnAmountUpdated(previousValue, newValue);
  }

  function emitMarketClosed(address borrower, uint256 timestamp) external {
    emit_MarketClosed(borrower, timestamp);
  }

  function emitFeesCollected(address collector, address recipient, uint256 amount) external {
    emit_FeesCollected(collector, recipient, amount);
  }
}

contract MarketEventsTest is Test, IMarketEventsAndErrors {
  event DrawnAmountUpdated(uint256 previousDrawnAmount, uint256 newDrawnAmount);

  MarketEventsHarness internal harness = new MarketEventsHarness();

  function test_emitMaxTotalSupplyUpdated_matchesSolidityEncoding() external {
    address caller = address(0xCA11E2);
    vm.expectEmit(address(harness));
    emit MaxTotalSupplyUpdated(caller, 12, 34);
    harness.emitMaxTotalSupplyUpdated(caller, 12, 34);
  }

  function test_emitProtocolFeeBipsUpdated_matchesSolidityEncoding() external {
    address caller = address(0xCA11E2);
    vm.expectEmit(address(harness));
    emit ProtocolFeeBipsUpdated(caller, 50, 75);
    harness.emitProtocolFeeBipsUpdated(caller, 50, 75);
  }

  function test_emitAnnualInterestAndReserveRatioBipsUpdated_matchesSolidityEncoding() external {
    address caller = address(0xCA11E2);
    vm.expectEmit(address(harness));
    emit AnnualInterestAndReserveRatioBipsUpdated(caller, 500, 600, 1_000, 2_000);
    harness.emitAnnualInterestAndReserveRatioBipsUpdated(caller, 500, 600, 1_000, 2_000);
  }

  function test_emitBorrow_matchesSolidityEncoding() external {
    address borrower = address(0xB0220);
    vm.expectEmit(address(harness));
    emit Borrow(borrower, 123e18);
    harness.emitBorrow(borrower, 123e18);
  }

  function test_emitDrawnAmountUpdated_matchesSolidityEncoding() external {
    vm.expectEmit(address(harness));
    emit DrawnAmountUpdated(123e18, 100e18);
    harness.emitDrawnAmountUpdated(123e18, 100e18);
  }

  function test_emitMarketClosed_matchesSolidityEncoding() external {
    address borrower = address(0xB0220);
    vm.expectEmit(address(harness));
    emit MarketClosed(borrower, 1_234_567);
    harness.emitMarketClosed(borrower, 1_234_567);
  }

  function test_emitFeesCollected_matchesSolidityEncoding() external {
    address collector = address(0xC011EC7);
    address recipient = address(0xFEE);
    vm.expectEmit(address(harness));
    emit FeesCollected(collector, recipient, 123e18);
    harness.emitFeesCollected(collector, recipient, 123e18);
  }
}
