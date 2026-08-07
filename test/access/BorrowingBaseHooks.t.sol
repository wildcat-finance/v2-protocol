// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../integration/MarketConfigMatrix.sol';
import { ICovenantEvents } from 'src/access/covenants/lib/CovenantEvents.sol';
import { CROSS_MARKET_GATE_LIB, CLEAN_DOWN_LIB, COMMITMENT_SCHEDULE_LIB, DRAW_TIMELOCK_LIB, BORROWING_BASE_LIB, CROSS_MARKET_CAP_LIB } from 'src/access/covenants/lib/CovenantLibraries.sol';
import { BorrowingBaseHooks } from 'src/access/BorrowingBaseHooks.sol';

contract BorrowingBaseHooksTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 1_000_000e18;

  address internal template;
  BorrowingBaseHooks internal hooksInstance;
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
    template = LibStoredInitCode.deployInitCode(
      type(BorrowingBaseHooks).creationCode
    );
    _registerTemplate(template, 'borrowing base template');

    address[] memory tokens = new address[](1);
    tokens[0] = address(collateralToken);
    uint16[] memory rates = new uint16[](1);
    rates[0] = 5_000; // 50% advance rate
    _deploy(abi.encode(uint128(0), false, tokens, rates));
    _depositAlice(DEPOSIT);

    collateralToken.mint(borrower, 10_000_000e18);
    vm.prank(borrower);
    collateralToken.approve(address(hooksInstance), type(uint256).max);
  }

  function _registerTemplate(address t, string memory name) internal asSelf {
    revolvingFactory.addHooksTemplate(t, name, address(0), address(0), 0, 0);
  }

  function _deploy(bytes memory hooksData) internal {
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(template, '');
    hooksInstance = BorrowingBaseHooks(instance);
    HooksDeploymentConfig dc = IHooks(instance).config();
    HooksConfig hc = dc.optionalFlags().setHooksAddress(instance).mergeAllFlags(
      dc.requiredFlags()
    );
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

  function _postCollateral(uint256 amount) internal asAccount(borrower) {
    hooksInstance.depositCollateral(address(market), address(collateralToken), amount);
  }

  function test_onBorrow_BorrowingBaseExceeded_NoCollateral() external {
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(ICovenantEvents.BorrowingBaseExceeded.selector, 1e18, 0)
    );
    market.borrow(1e18);
  }

  function test_onBorrow_PassesWithinBase() external {
    _postCollateral(400_000e18); // base = 200k at 50%
    assertEq(hooksInstance.borrowingBase(address(market)), 200_000e18);
    vm.prank(borrower);
    market.borrow(200_000e18);
  }

  function test_onBorrow_BorrowingBaseExceeded_AboveBase() external {
    _postCollateral(400_000e18);
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        ICovenantEvents.BorrowingBaseExceeded.selector,
        200_000e18 + 1e18,
        200_000e18
      )
    );
    market.borrow(200_000e18 + 1e18);
  }

  function test_withdrawCollateral_WithdrawalBreachesBase() external {
    _postCollateral(400_000e18);
    vm.prank(borrower);
    market.borrow(150_000e18);
    // withdrawing 200k collateral leaves base = 100k < 150k drawn
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        ICovenantEvents.WithdrawalBreachesBase.selector,
        100_000e18,
        150_000e18
      )
    );
    hooksInstance.withdrawCollateral(
      address(market),
      address(collateralToken),
      200_000e18,
      borrower
    );
  }

  function test_withdrawCollateral_PassesAboveDrawn() external {
    _postCollateral(400_000e18);
    vm.prank(borrower);
    market.borrow(100_000e18);
    // withdrawing 100k leaves base = 150k >= 100k drawn
    vm.prank(borrower);
    hooksInstance.withdrawCollateral(
      address(market),
      address(collateralToken),
      100_000e18,
      borrower
    );
    assertEq(hooksInstance.borrowingBase(address(market)), 150_000e18);
  }

  function test_withdrawCollateral_CallerNotCovenantBorrower() external {
    _postCollateral(100_000e18);
    vm.prank(alice);
    vm.expectRevert(ICovenantEvents.CallerNotCovenantBorrower.selector);
    hooksInstance.withdrawCollateral(
      address(market),
      address(collateralToken),
      1e18,
      alice
    );
  }

  function test_depositCollateral_InvalidCollateralConfiguration_UnknownToken() external {
    MockERC20 rogue = new MockERC20('Rogue', 'RGE', 18);
    rogue.mint(borrower, 1e18);
    vm.startPrank(borrower);
    rogue.approve(address(hooksInstance), type(uint256).max);
    vm.expectRevert(ICovenantEvents.InvalidCollateralConfiguration.selector);
    hooksInstance.depositCollateral(address(market), address(rogue), 1e18);
    vm.stopPrank();
  }

  function test_onCreateMarket_InvalidCollateralConfiguration() external {
    address[] memory tokens = new address[](1);
    tokens[0] = address(collateralToken);
    uint16[] memory rates = new uint16[](1);
    rates[0] = 10_001; // above 100%
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(template, '');
    HooksDeploymentConfig dc = IHooks(instance).config();
    HooksConfig hc = dc.optionalFlags().setHooksAddress(instance).mergeAllFlags(
      dc.requiredFlags()
    );
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
    vm.expectRevert(ICovenantEvents.InvalidCollateralConfiguration.selector);
    revolvingFactory.deployMarket(
      inputs,
      abi.encode(uint128(0), false, tokens, rates),
      abi.encode(uint8(1), uint16(200)),
      _nextSalt(borrower),
      address(0),
      0
    );
    stopPrank();
  }
}
