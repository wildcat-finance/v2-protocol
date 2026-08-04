// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../integration/MarketConfigMatrix.sol';
import { ICovenantEvents } from 'src/access/covenants/lib/CovenantEvents.sol';
import { CROSS_MARKET_GATE_LIB, CLEAN_DOWN_LIB } from 'src/access/covenants/lib/CovenantLibraries.sol';
import { RevolvingCleanDownHooks } from 'src/access/RevolvingCleanDownHooks.sol';
import { CleanDownCovenant } from 'src/access/covenants/CleanDownCovenant.sol';

/// @dev Composition tests: a template inheriting one covenant must work
///      standalone and carry none of the other covenant's surface. Behavioural
///      depth for the clean-down covenant itself lives in
///      `RevolvingCovenantHooks.t.sol`; these tests exercise the seam.
contract RevolvingCleanDownHooksTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 100_000e18;
  uint32 internal constant CLEAN_DOWN_DURATION = 5 days;
  uint32 internal constant CLEAN_DOWN_INTERVAL = 90 days;

  address internal cleanDownTemplate;
  RevolvingCleanDownHooks internal hooksInstance;
  uint256 internal deployedAt;


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
    cleanDownTemplate = LibStoredInitCode.deployInitCode(type(RevolvingCleanDownHooks).creationCode);
    _registerTemplateOnRevolving();
    _deploy();
  }

  function _registerTemplateOnRevolving() internal asSelf {
    revolvingFactory.addHooksTemplate(
      cleanDownTemplate,
      'clean-down template',
      address(0),
      address(0),
      0,
      0
    );
  }

  function _deploy() internal {
    deployedAt = block.timestamp;
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(cleanDownTemplate, '');
    hooksInstance = RevolvingCleanDownHooks(instance);

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
      reserveRatioBips: 2_000,
      delinquencyGracePeriod: 1 days,
      hooks: hooksConfig
    });

    market = WildcatMarket(
      revolvingFactory.deployMarket(
        inputs,
        abi.encode(uint128(0), false, CLEAN_DOWN_DURATION, CLEAN_DOWN_INTERVAL),
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

  function test_version_ReturnsTemplateName() external {
    assertEq(hooksInstance.version(), 'RevolvingCleanDownHooks');
  }

  function test_onBorrow_CleanDownOverdue() external {
    _depositAlice(DEPOSIT);
    _borrowBorrower(10_000e18);

    fastForward(CLEAN_DOWN_INTERVAL + 1 days);
    startPrank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        ICovenantEvents.CleanDownOverdue.selector,
        deployedAt + CLEAN_DOWN_INTERVAL
      )
    );
    market.borrow(1_000e18);
    stopPrank();

    // Repay to zero, complete a streak, and drawing resumes.
    market.updateState();
    uint256 debts = market.totalDebts();
    uint256 assets = asset.balanceOf(address(market));
    startPrank(borrower);
    market.repay(debts - assets);
    stopPrank();

    fastForward(CLEAN_DOWN_DURATION + 1);
    _borrowBorrower(1_000e18);
    (, bool overdue, , ) = hooksInstance.getCleanDownStatus(address(market));
    assertFalse(overdue);
  }

  /// @dev Delinquency and its cure must flow through untouched: this template
  ///      compiles in no delinquency gate, so once headroom exists the draw
  ///      proceeds with no covenant consulted beyond clean-down.
  function test_onBorrow_DelinquencyDoesNotGate() external {
    _depositAlice(DEPOSIT);
    _borrowBorrower(market.borrowableAssets());

    // Queue a partial withdrawal to push required liquidity above assets.
    startPrank(alice);
    market.queueWithdrawal(DEPOSIT / 2);
    stopPrank();
    market.updateState();
    assertTrue(market.currentState().isDelinquent, 'expected delinquency');

    // Repay enough to clear the batch and leave borrowing headroom. The
    // market remains marked delinquent by elapsed time.
    startPrank(borrower);
    market.repay(DEPOSIT / 2);
    stopPrank();
    market.updateState();

    uint256 borrowable = market.borrowableAssets();
    assertGt(borrowable, 0, 'expected headroom after repay');
    _borrowBorrower(borrowable);
  }

  /// @dev The watch-list ABI belongs to the cross-market covenant and must be
  ///      absent from this template's bytecode.
  function test_getWatchedMarkets_AbsentFromTemplate() external {
    (bool watchList, ) = address(hooksInstance).call(
      abi.encodeWithSignature('getWatchedMarkets()')
    );
    assertFalse(watchList, 'watch-list ABI should not exist on a clean-down-only template');

    (bool gateConfig, ) = address(hooksInstance).call(
      abi.encodeWithSignature('getCrossMarketGateConfig(address)', address(market))
    );
    assertFalse(gateConfig, 'gate config ABI should not exist on a clean-down-only template');

    (bool watch, ) = address(hooksInstance).call(
      abi.encodeWithSignature('watchMarket(address)', address(market))
    );
    assertFalse(watch, 'watchMarket should not exist on a clean-down-only template');
  }
}
