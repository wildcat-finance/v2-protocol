// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../integration/MarketConfigMatrix.sol';
import { ICovenantEvents } from 'src/access/covenants/lib/CovenantEvents.sol';
import { CROSS_MARKET_GATE_LIB, CLEAN_DOWN_LIB, COMMITMENT_SCHEDULE_LIB, DRAW_TIMELOCK_LIB, BORROWING_BASE_LIB, CROSS_MARKET_CAP_LIB } from 'src/access/covenants/lib/CovenantLibraries.sol';
import { BorrowingBaseHooks } from 'src/access/BorrowingBaseHooks.sol';
import { ExposureCapHooks } from 'src/access/ExposureCapHooks.sol';

/// @dev Covenant hooks were once restricted to the revolving factory. The
///      premise was bogus: covenants are facility furniture, not revolver
///      furniture, and the drawn-amount prediction converges to the same
///      value for both market kinds. This suite proves the templates bind
///      and enforce on markets deployed through the STANDARD factory.
contract CovenantHooksOnStandardMarketsTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 1_000_000e18;

  MockERC20 internal collateralToken;

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
    collateralToken = new MockERC20('Collateral', 'COL', 18);
  }

  function _registerOnStandard(address t, string memory name) internal asSelf {
    hooksFactory.addHooksTemplate(t, name, address(0), address(0), 0, 0);
  }

  function _deployStandardMarket(
    address instance,
    bytes memory hooksData,
    string memory namePrefix,
    string memory symbolPrefix
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
      hooksFactory.deployMarket(inputs, hooksData, _nextSalt(borrower), address(0), 0)
    );
  }

  function test_borrowingBase_EnforcesOnStandardMarket() external {
    address template = LibStoredInitCode.deployInitCode(
      type(BorrowingBaseHooks).creationCode
    );
    _registerOnStandard(template, 'bb on standard');

    address[] memory tokens = new address[](1);
    tokens[0] = address(collateralToken);
    uint16[] memory rates = new uint16[](1);
    rates[0] = 5_000;

    startPrank(borrower);
    address instance = hooksFactory.deployHooksInstance(template, '');
    BorrowingBaseHooks bb = BorrowingBaseHooks(instance);
    market = _deployStandardMarket(
      instance,
      abi.encode(uint128(0), false, tokens, rates),
      'Wildcat ',
      'wc'
    );
    BaseAccessControls(instance).grantRole(alice, uint32(block.timestamp));
    stopPrank();
    _approveMarket(alice, address(market));
    _approveMarket(borrower, address(market));
    vm.prank(alice);
    market.depositUpTo(DEPOSIT);

    // no collateral: standard-market draw is gated exactly like a revolving one
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(ICovenantEvents.BorrowingBaseExceeded.selector, 1e18, 0)
    );
    market.borrow(1e18);

    // post collateral, base = 200k; draws pass to the base and not beyond
    collateralToken.mint(borrower, 400_000e18);
    vm.startPrank(borrower);
    collateralToken.approve(instance, type(uint256).max);
    bb.depositCollateral(address(market), address(collateralToken), 400_000e18);
    market.borrow(200_000e18);
    vm.expectRevert(
      abi.encodeWithSelector(
        ICovenantEvents.BorrowingBaseExceeded.selector,
        200_000e18 + 1e18,
        200_000e18
      )
    );
    market.borrow(1e18);
    vm.stopPrank();
  }

  function test_exposureCap_CountsStandardMarketExposureAsNetDrawn() external {
    address template = LibStoredInitCode.deployInitCode(
      type(ExposureCapHooks).creationCode
    );
    _registerOnStandard(template, 'cap on standard');

    startPrank(borrower);
    address instance = hooksFactory.deployHooksInstance(template, '');
    ExposureCapHooks cap = ExposureCapHooks(instance);
    market = _deployStandardMarket(
      instance,
      abi.encode(uint128(0), false, uint128(500_000e18)),
      'Wildcat ',
      'wc'
    );
    BaseAccessControls(instance).grantRole(alice, uint32(block.timestamp));
    stopPrank();
    _approveMarket(alice, address(market));
    _approveMarket(borrower, address(market));
    vm.prank(alice);
    market.depositUpTo(DEPOSIT);

    // deposits the borrower never touched are not exposure
    assertEq(cap.currentAggregateExposure(address(market)), 0);

    vm.prank(borrower);
    market.borrow(300_000e18);
    // exposure = debt not covered by assets still in the market
    assertApproxEqAbs(cap.currentAggregateExposure(address(market)), 300_000e18, 1e6);

    vm.prank(borrower);
    vm.expectRevert(); // AggregateExposureExceeded, interest drift aside
    market.borrow(250_000e18);
  }
}
