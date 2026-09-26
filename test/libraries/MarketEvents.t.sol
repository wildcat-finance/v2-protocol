// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import 'src/interfaces/IMarketEventsAndErrors.sol';
import 'src/libraries/MarketEvents.sol';
import 'src/libraries/MarketErrors.sol';
import { WildcatMarketBase } from 'src/market/WildcatMarketBase.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract MarketEventsHarness {
  function emitRepaymentDateReached(uint256 timestamp) external {
    emit_RepaymentDateReached(timestamp);
  }

  function emitDefaultRecorded(uint256 timestamp) external {
    emit_DefaultRecorded(timestamp);
  }

  function emitLifecycleAccrual(
    uint32 from,
    uint32 to,
    uint112 scaleFactor,
    uint256 baseInterestRay,
    uint256 delinquencyFeeRay,
    uint256 protocolFee,
    uint256 dirty
  ) external {
    LifecycleAccrual memory accrual = LifecycleAccrual(
      from,
      to,
      scaleFactor,
      baseInterestRay,
      delinquencyFeeRay,
      protocolFee
    );
    // make the upper bits dirty deliberately. the encoder still owes us canonical ABI words.
    assembly {
      mstore(accrual, or(mload(accrual), and(dirty, not(0xffffffff))))
      mstore(add(accrual, 0x20), or(mload(add(accrual, 0x20)), and(dirty, not(0xffffffff))))
      mstore(
        add(accrual, 0x40),
        or(mload(add(accrual, 0x40)), and(dirty, not(sub(shl(112, 1), 1))))
      )
    }
    emit_InterestAndFeesAccrued(accrual);
  }

  function revertLifecycle(uint256 kind) external pure {
    if (kind == 0) revert_InvalidRepaymentTerms();
    if (kind == 1) revert_UnsupportedExecuteWithdrawalHook();
    if (kind == 2) revert_MarketInRepayment();
    revert_RepaymentReserveRequired();
  }

  function emitMaxTotalSupplyUpdated(
    address caller,
    uint256 previousValue,
    uint256 newValue
  ) external {
    emit_MaxTotalSupplyUpdated(caller, previousValue, newValue);
  }

  function emitProtocolFeeBipsUpdated(
    address caller,
    uint256 previousValue,
    uint256 newValue
  ) external {
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

contract MarketEventsTest is TestKernel, IMarketEventsAndErrors {
  event RepaymentDateReached(uint256 effectiveTimestamp);
  event DefaultRecorded(uint256 effectiveTimestamp);
  event DrawnAmountUpdated(uint256 previousDrawnAmount, uint256 newDrawnAmount);

  MarketEventsHarness internal harness;

  function setUp() external {
    harness = MarketEventsHarness(
      _deployCode('test/libraries/MarketEvents.t.sol:MarketEventsHarness')
    );
  }

  function testFuzz_emitRepaymentEvents_matchesSolidityEncoding(uint256 timestamp) external {
    vm.expectEmit(address(harness));
    emit RepaymentDateReached(timestamp);
    harness.emitRepaymentDateReached(timestamp);
    vm.expectEmit(address(harness));
    emit DefaultRecorded(timestamp);
    harness.emitDefaultRecorded(timestamp);
  }

  function testFuzz_emitAccrualRecord_matchesSolidityEncoding(
    uint32 from,
    uint32 to,
    uint112 scaleFactor,
    uint256 baseInterestRay,
    uint256 delinquencyFeeRay,
    uint256 protocolFee,
    uint256 dirty
  ) external {
    vm.expectEmit(address(harness));
    emit InterestAndFeesAccrued(
      from,
      to,
      scaleFactor,
      baseInterestRay,
      delinquencyFeeRay,
      protocolFee
    );
    harness.emitLifecycleAccrual(
      from,
      to,
      scaleFactor,
      baseInterestRay,
      delinquencyFeeRay,
      protocolFee,
      dirty
    );
  }

  function test_repaymentErrorsMatchSolidityEncoding() external {
    bytes4[4] memory selectors = [
      WildcatMarketBase.InvalidRepaymentTerms.selector,
      WildcatMarketBase.UnsupportedExecuteWithdrawalHook.selector,
      WildcatMarketBase.MarketInRepayment.selector,
      WildcatMarketBase.RepaymentReserveRequired.selector
    ];
    for (uint256 i; i < selectors.length; ++i) {
      vm.expectRevert(abi.encodeWithSelector(selectors[i]));
      harness.revertLifecycle(i);
    }
  }

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
