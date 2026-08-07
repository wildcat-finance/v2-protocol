// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../integration/MarketConfigMatrix.sol';
import { ICovenantEvents } from 'src/access/covenants/lib/CovenantEvents.sol';
import { CROSS_MARKET_GATE_LIB, CLEAN_DOWN_LIB, COMMITMENT_SCHEDULE_LIB, DRAW_TIMELOCK_LIB } from 'src/access/covenants/lib/CovenantLibraries.sol';
import { PeriodicTimelockHooks } from 'src/access/PeriodicTimelockHooks.sol';
import { PeriodicTermHost } from 'src/access/covenants/PeriodicTermHost.sol';

contract PeriodicTimelockHooksTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 1_000_000e18;
  uint128 internal constant THRESHOLD = 100_000e18;
  uint32 internal constant DELAY = 2 days;
  uint32 internal constant GRACE = 30 days;
  uint32 internal constant FIRST_WINDOW = 10 days; // offset from t0
  uint32 internal constant PERIOD = 30 days;
  uint32 internal constant WINDOW = 3 days;

  address internal template;
  PeriodicTimelockHooks internal hooksInstance;
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
    template = LibStoredInitCode.deployInitCode(type(PeriodicTimelockHooks).creationCode);
    _registerTemplate();
    t0 = block.timestamp;
    _deploy();
    _depositAlice(DEPOSIT);
  }

  function _registerTemplate() internal asSelf {
    revolvingFactory.addHooksTemplate(template, 'periodic timelock', address(0), address(0), 0, 0);
  }

  function _hooksData() internal view returns (bytes memory) {
    return
      abi.encode(
        uint128(0),
        false,
        THRESHOLD,
        DELAY,
        GRACE,
        uint32(t0 + FIRST_WINDOW),
        PERIOD,
        WINDOW
      );
  }

  function _deploy() internal {
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(template, '');
    hooksInstance = PeriodicTimelockHooks(instance);
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
        _hooksData(),
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

  function test_onQueueWithdrawal_WithdrawOutsideWindow() external {
    vm.prank(alice);
    vm.expectRevert(PeriodicTermHost.WithdrawOutsideWindow.selector);
    market.queueWithdrawal(1_000e18);
  }

  function test_onQueueWithdrawal_PassesInsideWindow() external {
    vm.warp(t0 + FIRST_WINDOW + 1);
    vm.prank(alice);
    market.queueWithdrawal(1_000e18);
  }

  function test_announceDraw_ExecutableAtRespectsWindowFloor() external {
    vm.prank(borrower);
    uint256 nonce = hooksInstance.announceDraw(address(market), 500_000e18);
    // floor = firstWindowStart + windowDuration + batchDuration, which
    // dominates the two-day delay
    uint256 expected = t0 + FIRST_WINDOW + WINDOW + 1 days;
    assertEq(hooksInstance.getAnnouncement(address(market), nonce).executableAt, expected);
  }

  function test_onBorrow_AnnouncementNotRipeBeforeWindowFloor() external {
    vm.prank(borrower);
    hooksInstance.announceDraw(address(market), 500_000e18);
    vm.warp(t0 + DELAY + 1); // past the naive delay, before the floor
    vm.prank(borrower);
    vm.expectRevert();
    market.borrow(500_000e18);
  }

  function test_onBorrow_ConsumesAnnouncementAfterFloor() external {
    vm.prank(borrower);
    hooksInstance.announceDraw(address(market), 500_000e18);
    vm.warp(t0 + FIRST_WINDOW + WINDOW + 1 days);
    _borrowBorrower(500_000e18);
  }

  function test_onCreateMarket_InvalidPeriodicTerm() external {
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
    // window duration >= period duration
    vm.expectRevert(PeriodicTermHost.InvalidPeriodicTerm.selector);
    revolvingFactory.deployMarket(
      inputs,
      abi.encode(
        uint128(0),
        false,
        THRESHOLD,
        DELAY,
        GRACE,
        uint32(block.timestamp + 10 days),
        uint32(7 days),
        uint32(7 days)
      ),
      abi.encode(uint8(1), uint16(200)),
      _nextSalt(borrower),
      address(0),
      0
    );
    stopPrank();
  }
  /// @dev The unannounced-headroom window has to respect the exit floor, or a
  ///      borrower dribbles `threshold` per delay-period between windows and
  ///      extracts a multiple of the headroom while nobody can leave.
  function test_onBorrow_HeadroomDoesNotRollBetweenWindows() external {
    _borrowBorrower(THRESHOLD);
    // delay has elapsed, but the first full window after the baseline hasn't
    // closed yet: headroom must NOT refresh
    vm.warp(block.timestamp + DELAY);
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(ICovenantEvents.DrawRequiresAnnouncement.selector, THRESHOLD)
    );
    market.borrow(THRESHOLD);
  }

  function test_onBorrow_HeadroomRollsAfterWindowFloor() external {
    _borrowBorrower(THRESHOLD);
    uint256 floorEnd = hooksInstance.nextWithdrawalWindowStart(address(market), block.timestamp) +
      WINDOW +
      1 days; // the suite deploys with a 1 day withdrawal batch duration
    vm.warp(floorEnd);
    _borrowBorrower(THRESHOLD);
  }
}
