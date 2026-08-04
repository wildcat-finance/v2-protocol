// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../integration/MarketConfigMatrix.sol';
import { ICovenantEvents } from 'src/access/covenants/lib/CovenantEvents.sol';
import { CROSS_MARKET_GATE_LIB, CLEAN_DOWN_LIB, COMMITMENT_SCHEDULE_LIB, DRAW_TIMELOCK_LIB } from 'src/access/covenants/lib/CovenantLibraries.sol';
import { RevolvingScheduleHooks } from 'src/access/RevolvingScheduleHooks.sol';

contract RevolvingScheduleHooksTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 1_000_000e18;

  address internal scheduleTemplate;
  RevolvingScheduleHooks internal hooksInstance;
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
    scheduleTemplate = LibStoredInitCode.deployInitCode(type(RevolvingScheduleHooks).creationCode);
    _registerTemplate(scheduleTemplate, 'schedule template');
    t0 = block.timestamp;
    steps.push(uint40(t0 + 30 days));
    steps.push(uint40(t0 + 60 days));
    ceilings.push(600_000e18);
    ceilings.push(0);
    _deploy(abi.encode(uint128(0), false, steps, ceilings));
    _depositAlice(DEPOSIT);
  }

  function _registerTemplate(address template, string memory name) internal asSelf {
    revolvingFactory.addHooksTemplate(template, name, address(0), address(0), 0, 0);
  }

  function _deploy(bytes memory hooksData) internal {
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(scheduleTemplate, '');
    hooksInstance = RevolvingScheduleHooks(instance);
    HooksDeploymentConfig deploymentConfig = IHooks(instance).config();
    HooksConfig hooksConfig = deploymentConfig
      .optionalFlags()
      .setHooksAddress(instance)
      .mergeAllFlags(deploymentConfig.requiredFlags());
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
      hooks: hooksConfig
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

  function test_onBorrow_UnlimitedBeforeFirstStep() external {
    _borrowBorrower(700_000e18);
    assertEq(hooksInstance.currentDrawnCeiling(address(market)), type(uint256).max);
  }

  function test_currentDrawnCeiling_TracksSchedule() external {
    vm.warp(t0 + 30 days);
    assertEq(hooksInstance.currentDrawnCeiling(address(market)), 600_000e18);
    vm.warp(t0 + 60 days);
    assertEq(hooksInstance.currentDrawnCeiling(address(market)), 0);
  }

  function test_onBorrow_DrawnCeilingExceeded() external {
    vm.warp(t0 + 30 days);
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(ICovenantEvents.DrawnCeilingExceeded.selector, 700_000e18, 600_000e18)
    );
    market.borrow(700_000e18);
    _borrowBorrower(600_000e18);
  }

  function test_onBorrow_ExpiryCeilingZero() external {
    vm.warp(t0 + 60 days);
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(ICovenantEvents.DrawnCeilingExceeded.selector, 1e18, 0)
    );
    market.borrow(1e18);
  }

  function test_onCreateMarket_InvalidCommitmentSchedule() external {
    uint40[] memory badSteps = new uint40[](2);
    badSteps[0] = uint40(block.timestamp + 10 days);
    badSteps[1] = uint40(block.timestamp + 5 days); // not increasing
    uint128[] memory c = new uint128[](2);
    c[0] = 500e18;
    c[1] = 100e18;
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(scheduleTemplate, '');
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
    vm.expectRevert(ICovenantEvents.InvalidCommitmentSchedule.selector);
    revolvingFactory.deployMarket(
      inputs,
      abi.encode(uint128(0), false, badSteps, c),
      abi.encode(uint8(1), uint16(200)),
      _nextSalt(borrower),
      address(0),
      0
    );
    stopPrank();
  }
}
