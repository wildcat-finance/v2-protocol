// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MarketRescueGuard.t
//  \ ^ /   Recovery callbacks and branch-scoped market reentrancy protection.
//    V
//
//  FIXTURE AND CALLBACKS
//  _deployFixtureDependencies()
//  _fixture(...)
//  _configureProbe(...)
//  onTokenTransfer()
//  rescueAndUpdate(...)
//  _assertGuardedCallback()
//
//  RECOVERY GUARDS
//  test_underlyingRescueIsGuarded()
//  test_borrowBlocksNestedRescue()
//  test_unrelatedRescueAllowsCallbacks()
// ═════

import { MarketFixture } from '../shared/MarketFixture.sol';
import { RescueCallbackERC20 } from '../mocks/RescueCallbackERC20.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { ReentrancyGuard } from 'src/ReentrancyGuard.sol';

// ┌─ MarketRescueGuardTest ────────────────────────────────────────────────────
contract MarketRescueGuardTest is MarketFixture {
  address internal constant Holder = address(0xA11CE);

  WildcatMarket private _probeMarket;
  address private _callbackToken;
  address private _nestedRescueToken;
  uint256 private _callbackCount;
  bool private _readSucceeded;
  bool private _rescueSucceeded;
  bool private _updateSucceeded;
  bytes4 private _readError;
  bytes4 private _rescueError;
  bytes4 private _updateError;

  // ░░▒▒▓▓██ [ FIXTURE AND CALLBACKS ] ────────────────────────────────────────

  // ┌─ _deployFixtureDependencies ─────
  function _deployFixtureDependencies() internal override returns (Fixture memory fixture) {
    fixture = super._deployFixtureDependencies();
    fixture.asset = RescueCallbackERC20(_deployCode('test/mocks/RescueCallbackERC20.sol:RescueCallbackERC20'));
  }

  // ┌─ _fixture ─────
  function _fixture(bool revolving) private returns (Fixture memory fixture, MockERC20 stray) {
    Options memory options = _defaultOptions(HooksKind.OpenTerm);
    options.revolving = revolving;
    fixture = _newMarket(options);
    _deposit(fixture, Holder, 1_000e18);
    fixture.archController.registerBorrower(address(this));
    vm.prank(Borrower);
    fixture.market.requestBorrowerTransfer(address(this));
    fixture.market.acceptBorrowerTransfer();
    stray = MockERC20(
      _deployCode('lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20', abi.encode('Stray', 'STRAY', uint8(18)))
    );
    stray.mint(address(fixture.market), 7e18);
  }

  // ┌─ _configureProbe ─────
  function _configureProbe(Fixture memory fixture, RescueCallbackERC20 token, address nestedRescueToken) private {
    _probeMarket = fixture.market;
    _callbackToken = address(token);
    _nestedRescueToken = nestedRescueToken;
    _callbackCount = 0;
    token.setCallback(address(this));
  }

  // ┌─ onTokenTransfer ─────
  function onTokenTransfer() external {
    assertEq(msg.sender, _callbackToken, 'callback token');
    ++_callbackCount;
    bytes memory data;
    (_readSucceeded, data) =
      address(_probeMarket).staticcall(abi.encodeWithSelector(_probeMarket.scaledBalanceOf.selector, Holder));
    _readError = bytes4(data);
    (_rescueSucceeded, data) =
      address(_probeMarket).call(abi.encodeCall(_probeMarket.rescueTokens, (_nestedRescueToken)));
    _rescueError = bytes4(data);
    // this second guarded probe must still fail if the nested rescue was rejected.
    (_updateSucceeded, data) = address(_probeMarket).call(abi.encodeCall(_probeMarket.updateState, ()));
    _updateError = bytes4(data);
  }

  // ┌─ rescueAndUpdate ─────
  function rescueAndUpdate(address token) external {
    _probeMarket.rescueTokens(token);
    // both calls share one transaction, so this also checks successful guard cleanup.
    _probeMarket.updateState();
  }

  // ┌─ _assertGuardedCallback ─────
  function _assertGuardedCallback() private view {
    assertEq(_callbackCount, 1, 'callback exercised');
    assertFalse(_readSucceeded, 'guarded read rejected');
    assertFalse(_rescueSucceeded, 'nested rescue rejected');
    assertFalse(_updateSucceeded, 'outer guard remains held');
    assertEq(bytes32(_readError), bytes32(ReentrancyGuard.NoReentrantCalls.selector), 'read error');
    assertEq(bytes32(_rescueError), bytes32(ReentrancyGuard.NoReentrantCalls.selector), 'rescue error');
    assertEq(bytes32(_updateError), bytes32(ReentrancyGuard.NoReentrantCalls.selector), 'update error');
  }

  // ░░▒▒▓▓██ [ RECOVERY GUARDS ] ──────────────────────────────────────────────

  // ┌─ test_underlyingRescueIsGuarded ─────
  function test_underlyingRescueIsGuarded() external {
    for (uint256 model; model < 2; ++model) {
      (Fixture memory fixture, MockERC20 stray) = _fixture(model != 0);
      fixture.market.closeMarket();
      fixture.asset.mint(address(fixture.market), 50e18);
      _configureProbe(fixture, RescueCallbackERC20(address(fixture.asset)), address(stray));

      this.rescueAndUpdate(address(fixture.asset));

      _assertGuardedCallback();
      assertEq(fixture.asset.balanceOf(address(this)), 50e18, 'only surplus recovered');
      assertEq(fixture.market.totalAssets(), fixture.market.totalDebts(), 'lender backing retained');
      assertEq(stray.balanceOf(address(fixture.market)), 7e18, 'nested rescue transferred nothing');
    }
  }

  // ┌─ test_borrowBlocksNestedRescue ─────
  function test_borrowBlocksNestedRescue() external {
    for (uint256 model; model < 2; ++model) {
      (Fixture memory fixture, MockERC20 stray) = _fixture(model != 0);
      _configureProbe(fixture, RescueCallbackERC20(address(fixture.asset)), address(stray));

      fixture.market.borrow(100e18);

      _assertGuardedCallback();
      assertEq(fixture.asset.balanceOf(address(this)), 100e18, 'authorized borrow succeeds');
      assertEq(stray.balanceOf(address(fixture.market)), 7e18, 'locked action cannot rescue unrelated tokens');
    }
  }

  // ┌─ test_unrelatedRescueAllowsCallbacks ─────
  function test_unrelatedRescueAllowsCallbacks() external {
    for (uint256 model; model < 2; ++model) {
      (Fixture memory fixture, MockERC20 stray) = _fixture(model != 0);
      RescueCallbackERC20 token =
        RescueCallbackERC20(_deployCode('test/mocks/RescueCallbackERC20.sol:RescueCallbackERC20'));
      token.mint(address(fixture.market), 10e18);
      _configureProbe(fixture, token, address(stray));
      uint256 timestamp = vm.getBlockTimestamp() + 1 days;
      vm.warp(timestamp);

      fixture.market.rescueTokens(address(token));

      assertEq(_callbackCount, 1, 'callback exercised');
      assertTrue(_readSucceeded, 'committed market state readable');
      assertTrue(_rescueSucceeded, 'authorized nested rescue succeeds outside lock');
      assertTrue(_updateSucceeded, 'nested state update succeeds outside lock');
      assertEq(token.balanceOf(address(this)), 10e18, 'outer token recovered');
      assertEq(stray.balanceOf(address(this)), 7e18, 'nested token recovered');
      assertEq(fixture.market.previousState().lastInterestAccruedTimestamp, timestamp, 'callback state persists');
      assertEq(fixture.market.scaledBalanceOf(Holder), 1_000e18, 'lender shares retained');
      assertTrue(fixture.market.totalDebts() > 1_000e18, 'callback accrual persists');
    }
  }
}
