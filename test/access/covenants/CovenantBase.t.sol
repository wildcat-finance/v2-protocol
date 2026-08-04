// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../../integration/MarketConfigMatrix.sol';
import { RevolvingCovenantHooks } from 'src/access/RevolvingCovenantHooks.sol';
import { RevolvingDrawnMath } from 'src/libraries/RevolvingDrawnMath.sol';
import { CROSS_MARKET_GATE_LIB, CLEAN_DOWN_LIB } from 'src/access/covenants/lib/CovenantLibraries.sol';

/// @dev Pins `RevolvingDrawnMath` to `WildcatMarketRevolving`'s actual
///      drawn-amount transitions.
///
///      The covenant hooks predict the post-transition drawn amount from
///      inside `onBorrow`/`onRepay`, which run *before* the market updates its
///      own value. The library holds that arithmetic; the market applies its
///      own copy inline. Nothing in the type system keeps the two in step.
///
///      Every test here reads the exact inputs the hook would see, computes
///      the library's answer, performs the operation, and asserts the market
///      agreed. If either copy of the formula is changed without the other,
///      these fail immediately rather than silently mis-timing clean-down
///      streaks in production.
contract CovenantBaseTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 100_000e18;

  address internal covenantTemplate;
  RevolvingCovenantHooks internal hooksInstance;


  /// @dev Covenant bodies live in external libraries linked at fixed CREATE2
  ///      addresses (see `libraries` in foundry.toml). Nothing is deployed
  ///      there in a fresh test EVM, so place the runtime code before any
  ///      template is exercised.
  function _deployCovenantLibraries() internal {
    deployCodeTo('CrossMarketGateLib.sol:CrossMarketGateLib', CROSS_MARKET_GATE_LIB);
    deployCodeTo('CleanDownLib.sol:CleanDownLib', CLEAN_DOWN_LIB);
  }

  function setUp() public override {
    super.setUp();
    _deployCovenantLibraries();
    covenantTemplate = LibStoredInitCode.deployInitCode(type(RevolvingCovenantHooks).creationCode);
    _register();
    _deploy();
  }

  function _register() internal asSelf {
    revolvingFactory.addHooksTemplate(
      covenantTemplate,
      'covenant template',
      address(0),
      address(0),
      0,
      0
    );
  }

  function _deploy() internal {
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(covenantTemplate, '');
    hooksInstance = RevolvingCovenantHooks(instance);

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

    // Covenants disabled: this fixture exercises the arithmetic, not the gates.
    market = WildcatMarket(
      revolvingFactory.deployMarket(
        inputs,
        abi.encode(uint128(0), false, uint32(0), uint32(0), false, false),
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

  function _drawn() internal view returns (uint256) {
    return IWildcatMarketRevolving(address(market)).drawnAmount();
  }

  /// @dev Borrow `amount`, asserting the library predicted the market's result.
  function _borrowAndAssert(uint256 amount) internal {
    MarketState memory state = market.currentState();
    uint256 predicted = RevolvingDrawnMath.drawnAfterBorrow(
      _drawn(),
      market.totalAssets(),
      state,
      amount
    );
    startPrank(borrower);
    market.borrow(amount);
    stopPrank();
    assertEq(_drawn(), predicted, 'borrow: library disagrees with market');
  }

  /// @dev Repay `amount`, asserting the library predicted the market's result.
  ///      `currentTotalAssets` in the library is the balance *including* the
  ///      repayment, matching what the market sees in its own hook.
  function _repayAndAssert(uint256 amount) internal {
    MarketState memory state = market.currentState();
    uint256 predicted = RevolvingDrawnMath.drawnAfterRepay(
      _drawn(),
      market.totalAssets() + amount,
      state
    );
    startPrank(borrower);
    market.repay(amount);
    stopPrank();
    assertEq(_drawn(), predicted, 'repay: library disagrees with market');
  }

  function test_drawnAfterBorrow_MatchesMarket() external {
    startPrank(alice);
    market.depositUpTo(DEPOSIT);
    stopPrank();

    _borrowAndAssert(10_000e18);
    fastForward(30 days);
    _borrowAndAssert(5_000e18);
    fastForward(1 days);
    _borrowAndAssert(1);
  }

  function test_drawnAfterRepay_MatchesMarket() external {
    startPrank(alice);
    market.depositUpTo(DEPOSIT);
    stopPrank();

    _borrowAndAssert(50_000e18);
    fastForward(45 days);
    _repayAndAssert(10_000e18);
    fastForward(10 days);
    _repayAndAssert(1);
  }

  /// @dev Over-repayment then reclaim: the branch where the drawn amount is
  ///      clamped to outstanding debt rather than tracking the raw balance.
  function test_drawnAfterBorrow_MatchesMarketOnExcessReclaim() external {
    startPrank(alice);
    market.depositUpTo(DEPOSIT);
    stopPrank();

    _borrowAndAssert(20_000e18);
    fastForward(20 days);

    market.updateState();
    uint256 owed = market.totalDebts() - asset.balanceOf(address(market));
    _repayAndAssert(owed + 5_000e18);
    assertEq(_drawn(), 0, 'expected zero drawn after over-repayment');

    fastForward(1 days);
    _borrowAndAssert(2_500e18);
  }

  /// @dev Fuzzed over borrow size and elapsed time. Bounds keep the market
  ///      solvent and inside the accepted scale-factor horizon.
  function testFuzz_drawnAfterBorrow_MatchesMarket(
    uint128 depositAmount,
    uint128 borrowAmount,
    uint32 elapsed
  ) external {
    depositAmount = uint128(bound(depositAmount, 1e18, 500_000e18));
    elapsed = uint32(bound(elapsed, 0, 365 days));

    startPrank(alice);
    market.depositUpTo(depositAmount);
    stopPrank();

    fastForward(elapsed);
    borrowAmount = uint128(bound(borrowAmount, 0, market.borrowableAssets()));
    if (borrowAmount == 0) return;
    _borrowAndAssert(borrowAmount);
  }

  /// @dev Fuzzed repayment against a drawn market.
  function testFuzz_drawnAfterRepay_MatchesMarket(
    uint128 borrowAmount,
    uint128 repayAmount,
    uint32 elapsed
  ) external {
    startPrank(alice);
    market.depositUpTo(DEPOSIT);
    stopPrank();

    borrowAmount = uint128(bound(borrowAmount, 1e18, market.borrowableAssets()));
    _borrowAndAssert(borrowAmount);

    fastForward(uint32(bound(elapsed, 0, 365 days)));
    repayAmount = uint128(bound(repayAmount, 1, uint256(borrowAmount) * 2));
    _repayAndAssert(repayAmount);
  }
}
