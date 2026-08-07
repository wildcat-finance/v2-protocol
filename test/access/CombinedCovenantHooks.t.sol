// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../integration/MarketConfigMatrix.sol';
import { ICovenantEvents } from 'src/access/covenants/lib/CovenantEvents.sol';
import { CROSS_MARKET_GATE_LIB, CLEAN_DOWN_LIB } from 'src/access/covenants/lib/CovenantLibraries.sol';
import { CombinedCovenantHooks } from 'src/access/CombinedCovenantHooks.sol';
import { CleanDownCovenant } from 'src/access/covenants/CleanDownCovenant.sol';
import { CrossMarketDelinquencyCovenant } from 'src/access/covenants/CrossMarketDelinquencyCovenant.sol';

/// @dev Integration tests for `CombinedCovenantHooks`: the clean-down
///      covenant and the cross-market delinquency gate, layered on revolving
///      markets. Reuses the matrix harness for factories and actors but
///      deploys covenant markets through a bespoke helper because the
///      template's `hooksData` extends the open-term layout.
/// @dev A factory with the right ABI and the wrong name: constructor must refuse.
contract ImposterFactory {
  address public immutable archController;

  constructor(address _archController) {
    archController = _archController;
  }

  function name() external pure returns (string memory) {
    return 'DefinitelyNotWildcat';
  }

  function tryDeploy(address template) external returns (address instance) {
    bytes32 salt = bytes32(uint256(uint160(msg.sender)) << 96);
    assembly {
      let initCodePointer := mload(0x40)
      let initCodeSize := sub(extcodesize(template), 1)
      extcodecopy(template, initCodePointer, 1, initCodeSize)
      let endInitCodePointer := add(initCodePointer, initCodeSize)
      mstore(endInitCodePointer, caller())
      mstore(add(endInitCodePointer, 0x20), 0x40)
      mstore(add(endInitCodePointer, 0x40), 0)
      instance := create2(0, initCodePointer, add(initCodeSize, 0x60), salt)
      if iszero(instance) {
        revert(0, 0)
      }
    }
  }
}

contract CombinedCovenantHooksTest is MarketConfigMatrix {
  using MathUtils for uint256;

  uint256 internal constant DEPOSIT = 100_000e18;
  uint32 internal constant CLEAN_DOWN_DURATION = 5 days;
  uint32 internal constant CLEAN_DOWN_INTERVAL = 90 days;

  address internal covenantTemplate;

  struct CovenantCell {
    uint16 commitmentFeeBips;
    uint32 cleanDownDuration;
    uint32 cleanDownInterval;
    bool crossMarketGate;
    bool gateOnPenaltyOnly;
  }

  struct CovenantMarket {
    WildcatMarket market;
    CombinedCovenantHooks hooksInstance;
    uint256 deployedAt;
  }


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
    covenantTemplate = LibStoredInitCode.deployInitCode(
      type(CombinedCovenantHooks).creationCode
    );
    _registerCovenantTemplate();
  }

  function _registerCovenantTemplate() internal asSelf {
    revolvingFactory.addHooksTemplate(
      covenantTemplate,
      'covenant template',
      address(0),
      address(0),
      0,
      0
    );
  }

  function _defaultCovenantCell() internal pure returns (CovenantCell memory) {
    return
      CovenantCell({
        commitmentFeeBips: 200,
        cleanDownDuration: CLEAN_DOWN_DURATION,
        cleanDownInterval: CLEAN_DOWN_INTERVAL,
        crossMarketGate: false,
        gateOnPenaltyOnly: false
      });
  }

  function _covenantHooksData(CovenantCell memory cell) internal pure returns (bytes memory) {
    return
      abi.encode(
        uint128(0), // minimumDeposit
        false, // transfersDisabled
        cell.cleanDownDuration,
        cell.cleanDownInterval,
        cell.crossMarketGate,
        cell.gateOnPenaltyOnly
      );
  }

  function _deployCovenantMarket(
    CovenantCell memory cell
  ) internal returns (CovenantMarket memory deployed) {
    deployed.deployedAt = block.timestamp;

    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(covenantTemplate, '');
    deployed.hooksInstance = CombinedCovenantHooks(instance);

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

    deployed.market = WildcatMarket(
      revolvingFactory.deployMarket(
        inputs,
        _covenantHooksData(cell),
        abi.encode(uint8(1), cell.commitmentFeeBips),
        _nextSalt(borrower),
        address(0),
        0
      )
    );

    BaseAccessControls(instance).grantRole(alice, uint32(block.timestamp));
    BaseAccessControls(instance).grantRole(bob, uint32(block.timestamp));
    stopPrank();

    _approveMarket(alice, address(deployed.market));
    _approveMarket(bob, address(deployed.market));
    _approveMarket(borrower, address(deployed.market));
  }

  function _depositTo(CovenantMarket memory d, address lender, uint256 amount) internal {
    startPrank(lender);
    d.market.depositUpTo(amount);
    stopPrank();
  }

  function _borrowOn(CovenantMarket memory d, uint256 amount) internal {
    startPrank(borrower);
    d.market.borrow(amount);
    stopPrank();
  }

  function _repayOn(CovenantMarket memory d, uint256 amount) internal {
    startPrank(borrower);
    d.market.repay(amount);
    stopPrank();
  }

  /// @dev Repay exactly to zero outstanding debt in the current block.
  function _repayToZero(CovenantMarket memory d) internal {
    d.market.updateState();
    uint256 debts = d.market.totalDebts();
    uint256 assets = asset.balanceOf(address(d.market));
    if (debts > assets) {
      _repayOn(d, debts - assets);
    }
    assertEq(
      IWildcatMarketRevolving(address(d.market)).drawnAmount(),
      0,
      'drawn != 0 after repay to zero'
    );
  }

  function _drawn(CovenantMarket memory d) internal view returns (uint256) {
    return IWildcatMarketRevolving(address(d.market)).drawnAmount();
  }

  /// @dev Deploy an open-term standard market for the same borrower and make
  ///      it delinquent: borrow to the reserve limit, then queue a full
  ///      withdrawal so required liquidity outstrips assets.
  function _deployDelinquentSibling() internal returns (DeployedCell memory sibling) {
    Cell memory cell = defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard);
    sibling = deployCell(cell);
    _depositAs(sibling, alice, DEPOSIT);
    uint256 borrowable = sibling.market.borrowableAssets();
    _borrowAs(sibling, borrowable);
    _queueFullWithdrawalAs(sibling, alice);
    sibling.market.updateState();
    assertTrue(sibling.market.currentState().isDelinquent, 'sibling not delinquent');
  }

  /// @dev Deploy an instance and attempt a market deployment with the given
  ///      covenant words, expecting `InvalidCovenantConfiguration`.
  function _expectDeployRevertsWith(CovenantCell memory cell, bytes4 selector) internal {
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(covenantTemplate, '');
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
    vm.expectRevert(selector);
    revolvingFactory.deployMarket(
      inputs,
      _covenantHooksData(cell),
      abi.encode(uint8(1), cell.commitmentFeeBips),
      _nextSalt(borrower),
      address(0),
      0
    );
    stopPrank();
  }

  // ========================================================================== //
  //                            Deployment validation                           //
  // ========================================================================== //

  function test_onCreateMarket_InvalidCleanDownConfigurationIntervalNotAboveDuration() external {
    CovenantCell memory cell = _defaultCovenantCell();
    cell.cleanDownInterval = cell.cleanDownDuration; // must be strictly greater
    _expectDeployRevertsWith(cell, ICovenantEvents.InvalidCleanDownConfiguration.selector);
  }

  function test_onCreateMarket_InvalidCleanDownConfigurationIntervalWithoutDuration() external {
    CovenantCell memory cell = _defaultCovenantCell();
    cell.cleanDownDuration = 0;
    cell.cleanDownInterval = 30 days;
    _expectDeployRevertsWith(cell, ICovenantEvents.InvalidCleanDownConfiguration.selector);
  }

  function test_onCreateMarket_InvalidGateConfiguration() external {
    CovenantCell memory cell = _defaultCovenantCell();
    cell.crossMarketGate = false;
    cell.gateOnPenaltyOnly = true;
    _expectDeployRevertsWith(
      cell,
      ICovenantEvents.InvalidGateConfiguration.selector
    );
  }

  function test_constructor_AcceptsStandardFactory() external {
    // The restriction this test once asserted was bogus: covenants are
    // facility furniture, not revolver furniture. Both wildcat factories
    // are accepted; anything else is not.
    startPrank(address(this));
    hooksFactory.addHooksTemplate(
      covenantTemplate,
      'covenant template',
      address(0),
      address(0),
      0,
      0
    );
    stopPrank();
    startPrank(borrower);
    address instance = hooksFactory.deployHooksInstance(covenantTemplate, '');
    stopPrank();
    assertTrue(instance != address(0));
  }

  function test_constructor_UnknownHooksFactory() external {
    ImposterFactory imposter = new ImposterFactory(address(archController));
    vm.expectRevert();
    imposter.tryDeploy(covenantTemplate);
  }

  function test_onCreateMarket_WatchesMarket() external {
    CovenantMarket memory d = _deployCovenantMarket(_defaultCovenantCell());
    address[] memory watched = d.hooksInstance.getWatchedMarkets();
    assertEq(watched.length, 1);
    assertEq(watched[0], address(d.market));
    assertTrue(d.hooksInstance.isWatchedMarket(address(d.market)));
  }

  // ========================================================================== //
  //                                 Clean-down                                 //
  // ========================================================================== //

  function test_onBorrow_CreditsIdleStreakFromCreation() external {
    CovenantMarket memory d = _deployCovenantMarket(_defaultCovenantCell());
    _depositTo(d, alice, DEPOSIT);

    // Warp past the interval without ever drawing: the idle streak since
    // deployment is a clean-down and is credited at the moment of the draw.
    fastForward(CLEAN_DOWN_INTERVAL + 10 days);
    _borrowOn(d, 1_000e18);
    assertGt(_drawn(d), 0);

    (, bool overdue, uint256 dueBy, uint256 zeroSince) = d.hooksInstance.getCleanDownStatus(
      address(d.market)
    );
    assertFalse(overdue, 'should not be overdue after crediting idle streak');
    assertEq(dueBy, block.timestamp + CLEAN_DOWN_INTERVAL, 'next deadline from credit time');
    assertEq(zeroSince, 0, 'streak should be closed while drawn');
  }

  function test_onBorrow_CleanDownOverdue() external {
    CovenantMarket memory d = _deployCovenantMarket(_defaultCovenantCell());
    _depositTo(d, alice, DEPOSIT);
    _borrowOn(d, 1_000e18);
    uint256 dueBy = d.deployedAt + CLEAN_DOWN_INTERVAL;

    // Still allowed within the interval.
    fastForward(CLEAN_DOWN_INTERVAL - 10 days);
    _borrowOn(d, 1_000e18);

    // Overdue: draws revert.
    fastForward(11 days);
    startPrank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(ICovenantEvents.CleanDownOverdue.selector, dueBy)
    );
    d.market.borrow(1_000e18);
    stopPrank();

    (, bool overdue, , ) = d.hooksInstance.getCleanDownStatus(address(d.market));
    assertTrue(overdue);
  }

  function test_onRepay_PartialRepayDoesNotStartStreak() external {
    CovenantMarket memory d = _deployCovenantMarket(_defaultCovenantCell());
    _depositTo(d, alice, DEPOSIT);
    _borrowOn(d, 10_000e18);
    fastForward(CLEAN_DOWN_INTERVAL + 1);

    _repayOn(d, 5_000e18);
    assertGt(_drawn(d), 0, 'still drawn after partial repay');
    (, , , uint256 zeroSince) = d.hooksInstance.getCleanDownStatus(address(d.market));
    assertEq(zeroSince, 0, 'partial repay must not start a streak');

    fastForward(CLEAN_DOWN_DURATION + 1);
    startPrank(borrower);
    vm.expectRevert(); // CleanDownOverdue
    d.market.borrow(1_000e18);
    stopPrank();
  }

  function test_onRepay_FullRepayStartsStreak() external {
    CovenantMarket memory d = _deployCovenantMarket(_defaultCovenantCell());
    _depositTo(d, alice, DEPOSIT);
    _borrowOn(d, 10_000e18);
    fastForward(CLEAN_DOWN_INTERVAL + 1 days);

    _repayToZero(d);
    (, bool overdue, , uint256 zeroSince) = d.hooksInstance.getCleanDownStatus(address(d.market));
    assertTrue(overdue, 'overdue until streak completes');
    assertEq(zeroSince, block.timestamp, 'streak starts at exact-zero repay');

    // An immature streak does not unblock draws.
    fastForward(CLEAN_DOWN_DURATION - 1);
    startPrank(borrower);
    vm.expectRevert(); // CleanDownOverdue
    d.market.borrow(1_000e18);
    stopPrank();

    // A matured streak is credited at the moment of the draw.
    fastForward(2);
    _borrowOn(d, 1_000e18);
    assertGt(_drawn(d), 0);
    (, bool overdueAfter, uint256 dueBy, ) = d.hooksInstance.getCleanDownStatus(
      address(d.market)
    );
    assertFalse(overdueAfter);
    assertEq(dueBy, block.timestamp + CLEAN_DOWN_INTERVAL);
  }

  function test_onBorrow_ExcessAssetsDrawIsNeutral() external {
    CovenantMarket memory d = _deployCovenantMarket(_defaultCovenantCell());
    _depositTo(d, alice, DEPOSIT);
    _borrowOn(d, 10_000e18);
    fastForward(30 days);

    // Over-repay: outstanding debt hits zero and the excess sits in the market.
    d.market.updateState();
    uint256 debts = d.market.totalDebts();
    uint256 assets = asset.balanceOf(address(d.market));
    uint256 excess = 5_000e18;
    _repayOn(d, (debts - assets) + excess);
    assertEq(_drawn(d), 0);
    (, , , uint256 zeroSince) = d.hooksInstance.getCleanDownStatus(address(d.market));
    uint256 streakStart = zeroSince;
    assertEq(streakStart, block.timestamp);

    // Reclaiming the excess is not credit: the streak survives, drawn stays 0.
    fastForward(1 days);
    _borrowOn(d, excess / 2);
    assertEq(_drawn(d), 0, 'excess reclaim must not register as drawn');
    (, , , uint256 zeroSinceAfter) = d.hooksInstance.getCleanDownStatus(address(d.market));
    assertEq(zeroSinceAfter, streakStart, 'streak must survive excess reclaim');
  }

  function test_onBorrow_CleanDownDisabled() external {
    CovenantCell memory cell = _defaultCovenantCell();
    cell.cleanDownDuration = 0;
    cell.cleanDownInterval = 0;
    CovenantMarket memory d = _deployCovenantMarket(cell);
    _depositTo(d, alice, DEPOSIT);
    _borrowOn(d, 1_000e18);
    fastForward(3650 days);
    _borrowOn(d, 1_000e18); // no covenant, no revert
    (bool enabled, , , ) = d.hooksInstance.getCleanDownStatus(address(d.market));
    assertFalse(enabled);
  }

  // ========================================================================== //
  //                          Cross-market delinquency                          //
  // ========================================================================== //

  function test_onBorrow_HealthySelfDoesNotBlock() external {
    // Regression guard for the reentrancy footgun: the calling market must be
    // checked through the hook's intermediate state, never via its own
    // reentrancy-guarded `currentState()`.
    CovenantCell memory cell = _defaultCovenantCell();
    cell.crossMarketGate = true;
    CovenantMarket memory d = _deployCovenantMarket(cell);
    _depositTo(d, alice, DEPOSIT);
    _borrowOn(d, 1_000e18);
    assertGt(_drawn(d), 0);
  }

  function test_onBorrow_BorrowerDelinquentOnMarket() external {
    CovenantCell memory cell = _defaultCovenantCell();
    cell.crossMarketGate = true;
    CovenantMarket memory d = _deployCovenantMarket(cell);
    _depositTo(d, alice, DEPOSIT);

    DeployedCell memory sibling = _deployDelinquentSibling();
    d.hooksInstance.watchMarket(address(sibling.market));

    startPrank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        ICovenantEvents.BorrowerDelinquentOnMarket.selector,
        address(sibling.market)
      )
    );
    d.market.borrow(1_000e18);
    stopPrank();

    assertEq(
      d.hooksInstance.firstBlockingMarket(address(d.market)),
      address(sibling.market),
      'preview should identify the blocking market'
    );

    // Curing the sibling reopens the facility.
    startPrank(borrower);
    uint256 debts = sibling.market.totalDebts();
    uint256 assets = asset.balanceOf(address(sibling.market));
    sibling.market.repay(debts - assets);
    stopPrank();
    sibling.market.updateState();
    assertFalse(sibling.market.currentState().isDelinquent);

    _borrowOn(d, 1_000e18);
    assertGt(_drawn(d), 0);
  }

  function test_onBorrow_PenaltyOnlyRespectsGracePeriod() external {
    CovenantCell memory cell = _defaultCovenantCell();
    cell.crossMarketGate = true;
    cell.gateOnPenaltyOnly = true;
    CovenantMarket memory d = _deployCovenantMarket(cell);
    _depositTo(d, alice, DEPOSIT);

    DeployedCell memory sibling = _deployDelinquentSibling();
    d.hooksInstance.watchMarket(address(sibling.market));
    uint256 grace = sibling.cell.delinquencyGracePeriod;

    // Delinquent but within grace: penalty-only gate does not block.
    fastForward(grace / 2);
    _borrowOn(d, 1_000e18);

    // Past grace: penalty APR is accruing on the sibling, draws blocked.
    fastForward(grace);
    sibling.market.updateState();
    startPrank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        ICovenantEvents.BorrowerDelinquentOnMarket.selector,
        address(sibling.market)
      )
    );
    d.market.borrow(1_000e18);
    stopPrank();
  }

  function test_watchMarket_NotBorrowerMarket() external {
    CovenantCell memory cell = _defaultCovenantCell();
    cell.crossMarketGate = true;
    CovenantMarket memory d = _deployCovenantMarket(cell);

    vm.expectRevert(ICovenantEvents.NotBorrowerMarket.selector);
    d.hooksInstance.watchMarket(address(0xdead));
  }

  function test_watchMarket_MarketAlreadyWatched() external {
    CovenantMarket memory d = _deployCovenantMarket(_defaultCovenantCell());
    vm.expectRevert(ICovenantEvents.MarketAlreadyWatched.selector);
    d.hooksInstance.watchMarket(address(d.market));
  }

  function test_unwatchClosedMarket_RemovesFromWatchList() external {
    CovenantCell memory cell = _defaultCovenantCell();
    cell.crossMarketGate = true;
    CovenantMarket memory d = _deployCovenantMarket(cell);
    _depositTo(d, alice, DEPOSIT);

    DeployedCell memory sibling = _deployDelinquentSibling();
    d.hooksInstance.watchMarket(address(sibling.market));

    // Cannot prune a live market.
    vm.expectRevert(ICovenantEvents.MarketNotClosed.selector);
    d.hooksInstance.unwatchClosedMarket(address(sibling.market));

    // Close the sibling: while still watched, the gate skips closed markets.
    _closeMarketAs(sibling);
    _borrowOn(d, 1_000e18);

    d.hooksInstance.unwatchClosedMarket(address(sibling.market));
    assertFalse(d.hooksInstance.isWatchedMarket(address(sibling.market)));
    address[] memory watched = d.hooksInstance.getWatchedMarkets();
    assertEq(watched.length, 1);
    assertEq(watched[0], address(d.market));
  }
}
