// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../integration/MarketConfigMatrix.sol';
import { ICovenantEvents } from 'src/access/covenants/lib/CovenantEvents.sol';
import { CROSS_MARKET_GATE_LIB, CLEAN_DOWN_LIB, COMMITMENT_SCHEDULE_LIB, DRAW_TIMELOCK_LIB } from 'src/access/covenants/lib/CovenantLibraries.sol';
import { FixedTermScheduleHooks } from 'src/access/FixedTermScheduleHooks.sol';
import { FixedTermHost } from 'src/access/covenants/FixedTermHost.sol';

contract FixedTermScheduleHooksTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 1_000_000e18;
  uint32 internal constant TERM = 90 days;

  address internal template;
  FixedTermScheduleHooks internal hooksInstance;
  uint40[] internal steps;
  uint128[] internal ceilings;
  uint256 internal t0;

  function _deployCovenantLibraries() internal {
    deployCodeTo('CrossMarketGateLib.sol:CrossMarketGateLib', CROSS_MARKET_GATE_LIB);
    deployCodeTo('CleanDownLib.sol:CleanDownLib', CLEAN_DOWN_LIB);
    deployCodeTo('CommitmentScheduleLib.sol:CommitmentScheduleLib', COMMITMENT_SCHEDULE_LIB);
    deployCodeTo('DrawTimelockLib.sol:DrawTimelockLib', DRAW_TIMELOCK_LIB);
  }

  function setUp() public override {
    super.setUp();
    _deployCovenantLibraries();
    template = LibStoredInitCode.deployInitCode(type(FixedTermScheduleHooks).creationCode);
    _registerTemplate();
    t0 = block.timestamp;
    steps.push(uint40(t0 + 30 days));
    ceilings.push(600_000e18);
    _deploy(abi.encode(uint128(0), false, uint32(t0 + TERM), steps, ceilings));
    _depositAlice(DEPOSIT);
  }

  function _registerTemplate() internal asSelf {
    revolvingFactory.addHooksTemplate(template, 'fixed schedule', address(0), address(0), 0, 0);
  }

  function _deploy(bytes memory hooksData) internal {
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(template, '');
    hooksInstance = FixedTermScheduleHooks(instance);
    HooksDeploymentConfig dc = IHooks(instance).config();
    HooksConfig hc = dc.optionalFlags().setHooksAddress(instance).mergeAllFlags(dc.requiredFlags());
    DeployMarketInputs memory inputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: 'Wildcat ',
      symbolPrefix: 'wc',
      maxTotalSupply: 1_000_000e18,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 1_000,
      withdrawalBatchDuration: 1 days,
      reserveRatioBips: 0,
      delinquencyGracePeriod: 1 days,
      hooks: hc
    });
    market = WildcatMarket(
      revolvingFactory.deployMarket(
        inputs,
        hooksData,
        abi.encode(uint8(1), uint16(200)),
        _nextSalt(borrower),
        address(0),
        0
      )
    );
    BaseAccessControls(instance).grantRole(alice, uint32(block.timestamp));
    stopPrank();
    _approveMarket(alice, address(market));
    _approveMarket(borrower, address(market));
  }

  function _depositAlice(uint256 amount) internal asAccount(alice) {
    market.depositUpTo(amount);
  }

  function _borrowBorrower(uint256 amount) internal asAccount(borrower) {
    market.borrow(amount);
  }

  function test_onQueueWithdrawal_WithdrawBeforeTermEnd() external {
    vm.prank(alice);
    vm.expectRevert(FixedTermHost.WithdrawBeforeTermEnd.selector);
    market.queueWithdrawal(1_000e18);
  }

  function test_onQueueWithdrawal_PassesAfterTermEnd() external {
    vm.warp(t0 + TERM);
    vm.prank(alice);
    market.queueWithdrawal(1_000e18);
  }

  function test_onBorrow_ScheduleStillEnforced() external {
    vm.warp(t0 + 30 days);
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(ICovenantEvents.DrawnCeilingExceeded.selector, 700_000e18, 600_000e18)
    );
    market.borrow(700_000e18);
    _borrowBorrower(600_000e18);
  }

  function test_getFixedTermEndTime_Set() external {
    assertEq(hooksInstance.getFixedTermEndTime(address(market)), uint32(t0 + TERM));
  }

  function test_onCreateMarket_InvalidFixedTerm() external {
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(template, '');
    HooksDeploymentConfig dc = IHooks(instance).config();
    HooksConfig hc = dc.optionalFlags().setHooksAddress(instance).mergeAllFlags(dc.requiredFlags());
    DeployMarketInputs memory inputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: 'Wildcat2 ',
      symbolPrefix: 'wc2',
      maxTotalSupply: 1_000_000e18,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 1_000,
      withdrawalBatchDuration: 1 days,
      reserveRatioBips: 0,
      delinquencyGracePeriod: 1 days,
      hooks: hc
    });
    uint40[] memory noSteps;
    uint128[] memory noCeilings;
    vm.expectRevert(FixedTermHost.InvalidFixedTerm.selector);
    revolvingFactory.deployMarket(
      inputs,
      abi.encode(uint128(0), false, uint32(block.timestamp + 366 days), noSteps, noCeilings),
      abi.encode(uint8(1), uint16(200)),
      _nextSalt(borrower),
      address(0),
      0
    );
    stopPrank();
  }
}
