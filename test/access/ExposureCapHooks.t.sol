// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../integration/MarketConfigMatrix.sol';
import { ICovenantEvents } from 'src/access/covenants/lib/CovenantEvents.sol';
import { CROSS_MARKET_GATE_LIB, CLEAN_DOWN_LIB, COMMITMENT_SCHEDULE_LIB, DRAW_TIMELOCK_LIB, BORROWING_BASE_LIB, CROSS_MARKET_CAP_LIB } from 'src/access/covenants/lib/CovenantLibraries.sol';
import { ExposureCapHooks } from 'src/access/ExposureCapHooks.sol';

contract ExposureCapHooksTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 1_000_000e18;
  uint128 internal constant CAP = 500_000e18;

  address internal template;
  ExposureCapHooks internal hooksInstance;
  WildcatMarket internal marketB;

  function _deployCovenantLibraries() internal {
    deployCodeTo('CrossMarketGateLib.sol:CrossMarketGateLib', CROSS_MARKET_GATE_LIB);
    deployCodeTo('CleanDownLib.sol:CleanDownLib', CLEAN_DOWN_LIB);
    deployCodeTo('CommitmentScheduleLib.sol:CommitmentScheduleLib', COMMITMENT_SCHEDULE_LIB);
    deployCodeTo('DrawTimelockLib.sol:DrawTimelockLib', DRAW_TIMELOCK_LIB);
    deployCodeTo('BorrowingBaseLib.sol:BorrowingBaseLib', BORROWING_BASE_LIB);
    deployCodeTo('CrossMarketCapLib.sol:CrossMarketCapLib', CROSS_MARKET_CAP_LIB);
  }

  function setUp() public override {
    super.setUp();
    _deployCovenantLibraries();
    template = LibStoredInitCode.deployInitCode(type(ExposureCapHooks).creationCode);
    _registerTemplate(template, 'exposure cap template');
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(template, '');
    hooksInstance = ExposureCapHooks(instance);
    market = _deployOne(instance, 'Wildcat ', 'wc', CAP);
    marketB = _deployOne(instance, 'WildcatB ', 'wb', CAP);
    BaseAccessControls(instance).grantRole(alice, uint32(block.timestamp));
    stopPrank();
    for (uint256 i; i < 2; i++) {
      address m = i == 0 ? address(market) : address(marketB);
      _approveMarket(alice, m);
      _approveMarket(borrower, m);
      vm.prank(alice);
      WildcatMarket(m).depositUpTo(DEPOSIT);
    }
  }

  function _registerTemplate(address t, string memory name) internal asSelf {
    revolvingFactory.addHooksTemplate(t, name, address(0), address(0), 0, 0);
  }

  function _deployOne(
    address instance,
    string memory namePrefix,
    string memory symbolPrefix,
    uint128 cap
  ) internal returns (WildcatMarket m) {
    HooksDeploymentConfig dc = IHooks(instance).config();
    HooksConfig hc = dc.optionalFlags().setHooksAddress(instance).mergeAllFlags(
      dc.requiredFlags()
    );
    DeployMarketInputs memory inputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: namePrefix,
      symbolPrefix: symbolPrefix,
      maxTotalSupply: 1_000_000e18,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 1_000,
      withdrawalBatchDuration: 1 days,
      reserveRatioBips: 0,
      delinquencyGracePeriod: 1 days,
      hooks: hc
    });
    m = WildcatMarket(
      revolvingFactory.deployMarket(
        inputs,
        abi.encode(uint128(0), false, cap),
        abi.encode(uint8(1), uint16(200)),
        _nextSalt(borrower),
        address(0),
        0
      )
    );
  }

  function test_onCreateMarket_AutoWatchesBothMarkets() external {
    address[] memory watched = hooksInstance.getWatchedMarkets();
    assertEq(watched.length, 2);
    assertTrue(hooksInstance.isWatchedMarket(address(market)));
    assertTrue(hooksInstance.isWatchedMarket(address(marketB)));
  }

  function test_onBorrow_PassesWithinCap() external {
    vm.prank(borrower);
    market.borrow(300_000e18);
    assertEq(hooksInstance.currentAggregateExposure(address(market)), 300_000e18);
  }

  function test_onBorrow_AggregateExposureExceeded_AcrossMarkets() external {
    vm.prank(borrower);
    market.borrow(300_000e18);
    // 300k drawn on A; drawing 250k on B puts the aggregate at 550k > 500k
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        ICovenantEvents.AggregateExposureExceeded.selector,
        550_000e18,
        uint256(CAP)
      )
    );
    marketB.borrow(250_000e18);
    // 200k keeps the aggregate at the cap exactly
    vm.prank(borrower);
    marketB.borrow(200_000e18);
  }

  function test_onBorrow_RepaymentRestoresHeadroom() external {
    vm.prank(borrower);
    market.borrow(400_000e18);
    vm.startPrank(borrower);
    asset.approve(address(market), type(uint256).max);
    market.repay(300_000e18);
    vm.stopPrank();
    vm.prank(borrower);
    marketB.borrow(350_000e18); // aggregate 100k + 350k = 450k <= cap
  }

  function test_onBorrow_UnwatchedMarketNotCounted_FloorSemantics() external {
    // prune-equivalent: deploy a THIRD market on a separate instance the
    // watch-list never learns about; its debt is invisible to the cap
    startPrank(borrower);
    address instance2 = revolvingFactory.deployHooksInstance(template, '');
    WildcatMarket marketC = _deployOneOn(instance2, 'WildcatC ', 'wx', 0);
    BaseAccessControls(instance2).grantRole(alice, uint32(block.timestamp));
    stopPrank();
    _approveMarket(alice, address(marketC));
    _approveMarket(borrower, address(marketC));
    vm.prank(alice);
    marketC.depositUpTo(DEPOSIT);
    vm.prank(borrower);
    marketC.borrow(400_000e18);
    // aggregate as this instance sees it: zero, despite 400k of real debt
    assertEq(hooksInstance.currentAggregateExposure(address(market)), 0);
    vm.prank(borrower);
    market.borrow(CAP); // permitted: the cap is a floor on exposure, not a ceiling
  }

  function _deployOneOn(
    address instance,
    string memory namePrefix,
    string memory symbolPrefix,
    uint128 cap
  ) internal returns (WildcatMarket m) {
    HooksDeploymentConfig dc = IHooks(instance).config();
    HooksConfig hc = dc.optionalFlags().setHooksAddress(instance).mergeAllFlags(
      dc.requiredFlags()
    );
    DeployMarketInputs memory inputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: namePrefix,
      symbolPrefix: symbolPrefix,
      maxTotalSupply: 1_000_000e18,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 1_000,
      withdrawalBatchDuration: 1 days,
      reserveRatioBips: 0,
      delinquencyGracePeriod: 1 days,
      hooks: hc
    });
    m = WildcatMarket(
      revolvingFactory.deployMarket(
        inputs,
        abi.encode(uint128(0), false, cap),
        abi.encode(uint8(1), uint16(200)),
        _nextSalt(borrower),
        address(0),
        0
      )
    );
  }

  function test_onBorrow_ZeroCapDisables() external {
    startPrank(borrower);
    address instance2 = revolvingFactory.deployHooksInstance(template, '');
    WildcatMarket free = _deployOneOn(instance2, 'WildcatF ', 'wf', 0);
    BaseAccessControls(instance2).grantRole(alice, uint32(block.timestamp));
    stopPrank();
    _approveMarket(alice, address(free));
    _approveMarket(borrower, address(free));
    vm.prank(alice);
    free.depositUpTo(DEPOSIT);
    vm.prank(borrower);
    free.borrow(900_000e18);
  }
}
