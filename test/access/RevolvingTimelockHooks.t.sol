// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../integration/MarketConfigMatrix.sol';
import { ICovenantEvents } from 'src/access/covenants/lib/CovenantEvents.sol';
import { CROSS_MARKET_GATE_LIB, CLEAN_DOWN_LIB, COMMITMENT_SCHEDULE_LIB, DRAW_TIMELOCK_LIB } from 'src/access/covenants/lib/CovenantLibraries.sol';
import { RevolvingTimelockHooks } from 'src/access/RevolvingTimelockHooks.sol';

contract RevolvingTimelockHooksTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 1_000_000e18;
  uint128 internal constant THRESHOLD = 100_000e18;
  uint32 internal constant DELAY = 2 days; // batch duration is 1 day
  uint32 internal constant GRACE = 1 days;

  address internal timelockTemplate;
  RevolvingTimelockHooks internal hooksInstance;

  function _deployCovenantLibraries() internal {
    deployCodeTo('CrossMarketGateLib.sol:CrossMarketGateLib', CROSS_MARKET_GATE_LIB);
    deployCodeTo('CleanDownLib.sol:CleanDownLib', CLEAN_DOWN_LIB);
    deployCodeTo('CommitmentScheduleLib.sol:CommitmentScheduleLib', COMMITMENT_SCHEDULE_LIB);
    deployCodeTo('DrawTimelockLib.sol:DrawTimelockLib', DRAW_TIMELOCK_LIB);
  }

  function setUp() public override {
    super.setUp();
    _deployCovenantLibraries();
    timelockTemplate = LibStoredInitCode.deployInitCode(type(RevolvingTimelockHooks).creationCode);
    _registerTemplate(timelockTemplate, 'timelock template');
    _deploy(THRESHOLD, DELAY, GRACE, 1 days);
    _depositAlice(DEPOSIT);
  }

  function _registerTemplate(address template, string memory name) internal asSelf {
    revolvingFactory.addHooksTemplate(template, name, address(0), address(0), 0, 0);
  }

  function _deploy(
    uint128 threshold,
    uint32 delay_,
    uint32 grace,
    uint32 batchDuration
  ) internal {
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(timelockTemplate, '');
    hooksInstance = RevolvingTimelockHooks(instance);
    HooksDeploymentConfig dc = IHooks(instance).config();
    HooksConfig hc = dc.optionalFlags().setHooksAddress(instance).mergeAllFlags(dc.requiredFlags());
    DeployMarketInputs memory inputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: 'Wildcat ',
      symbolPrefix: 'wc',
      maxTotalSupply: 1_000_000e18,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 1_000,
      withdrawalBatchDuration: batchDuration,
      reserveRatioBips: 0,
      delinquencyGracePeriod: 1 days,
      hooks: hc
    });
    market = WildcatMarket(
      revolvingFactory.deployMarket(
        inputs,
        abi.encode(uint128(0), false, threshold, delay_, grace),
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

  function test_onBorrow_WithinHeadroomPasses() external {
    _borrowBorrower(THRESHOLD);
  }

  function test_onBorrow_DrawRequiresAnnouncement() external {
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(ICovenantEvents.DrawRequiresAnnouncement.selector, THRESHOLD)
    );
    market.borrow(THRESHOLD + 1e18);
  }

  function test_onBorrow_SplitDrawsShareHeadroom() external {
    _borrowBorrower(60_000e18);
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(ICovenantEvents.DrawRequiresAnnouncement.selector, THRESHOLD)
    );
    market.borrow(60_000e18);
  }

  function test_onBorrow_HeadroomRollsAfterDelay() external {
    _borrowBorrower(THRESHOLD);
    vm.warp(block.timestamp + DELAY);
    _borrowBorrower(THRESHOLD);
  }

  function test_announceDraw_CallerNotCovenantBorrower() external {
    vm.prank(alice);
    vm.expectRevert(ICovenantEvents.CallerNotCovenantBorrower.selector);
    hooksInstance.announceDraw(address(market), 500_000e18);
  }

  function test_onBorrow_AnnouncementNotRipe() external {
    vm.prank(borrower);
    hooksInstance.announceDraw(address(market), 500_000e18);
    vm.prank(borrower);
    vm.expectRevert();
    market.borrow(500_000e18);
  }

  function test_onBorrow_ConsumesAnnouncement() external {
    vm.prank(borrower);
    hooksInstance.announceDraw(address(market), 500_000e18);
    vm.warp(block.timestamp + DELAY);
    _borrowBorrower(400_000e18);
    // announcement consumed: another gated draw now needs a fresh one
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(ICovenantEvents.DrawRequiresAnnouncement.selector, THRESHOLD)
    );
    market.borrow(200_000e18);
  }

  function test_onBorrow_ExpiredAnnouncementSkipped() external {
    vm.prank(borrower);
    hooksInstance.announceDraw(address(market), 500_000e18);
    vm.warp(block.timestamp + DELAY + GRACE + 1);
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(ICovenantEvents.DrawRequiresAnnouncement.selector, THRESHOLD)
    );
    market.borrow(400_000e18);
  }

  function test_onCreateMarket_InvalidTimelockConfiguration() external {
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(timelockTemplate, '');
    HooksDeploymentConfig dc = IHooks(instance).config();
    HooksConfig hc = dc.optionalFlags().setHooksAddress(instance).mergeAllFlags(dc.requiredFlags());
    DeployMarketInputs memory inputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: 'Wildcat2 ',
      symbolPrefix: 'wc2',
      maxTotalSupply: 1_000_000e18,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 1_000,
      withdrawalBatchDuration: 3 days, // delay below batch duration
      reserveRatioBips: 0,
      delinquencyGracePeriod: 1 days,
      hooks: hc
    });
    vm.expectRevert(ICovenantEvents.InvalidTimelockConfiguration.selector);
    revolvingFactory.deployMarket(
      inputs,
      abi.encode(uint128(0), false, THRESHOLD, DELAY, GRACE),
      abi.encode(uint8(1), uint16(200)),
      _nextSalt(borrower),
      address(0),
      0
    );
    stopPrank();
  }
}
