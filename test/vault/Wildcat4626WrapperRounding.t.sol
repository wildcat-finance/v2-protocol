// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'forge-std/Test.sol';
import { MathUtils, RAY } from 'src/libraries/MathUtils.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { IWildcatMarketToken } from 'src/vault/Wildcat4626Wrapper.sol';

contract MockSanctionsSentinel {
  mapping(address => bool) public sanctioned;

  function isSanctioned(address, address account) external view returns (bool) {
    return sanctioned[account];
  }
}

contract MockMarketToken is IWildcatMarketToken {
  using MathUtils for uint256;

  string public constant name = 'HEX Token';
  string public constant symbol = 'HEX';
  uint8 public constant override decimals = 18;

  uint256 public override scaleFactor = RAY;
  address public immutable override borrower;
  address public immutable override sentinel;

  mapping(address => uint256) internal _scaledBalances;
  mapping(address => mapping(address => uint256)) public override allowance;

  constructor(address borrower_, address sentinel_) {
    borrower = borrower_;
    sentinel = sentinel_;
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _scaledBalances[account].rayMul(scaleFactor);
  }

  function totalSupply() external view returns (uint256) {
    return 0;
  }

  function scaledBalanceOf(address account) external view override returns (uint256) {
    return _scaledBalances[account];
  }

  function maxTotalSupply() external pure override returns (uint256) {
    return type(uint128).max;
  }

  function setScaleFactor(uint256 newScaleFactor) external {
    scaleFactor = newScaleFactor;
  }

  function mint(address to, uint256 assets) external {
    uint256 scaled = assets.rayDiv(scaleFactor);
    _scaledBalances[to] += scaled;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    _transfer(msg.sender, to, amount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    uint256 allowed = allowance[from][msg.sender];
    if (allowed != type(uint256).max) {
      require(allowed >= amount, 'ALLOWANCE');
      allowance[from][msg.sender] = allowed - amount;
    }
    _transfer(from, to, amount);
    return true;
  }

  function _transfer(address from, address to, uint256 amount) internal {
    uint256 scaled = amount.rayDiv(scaleFactor);
    require(scaled != 0, 'SCALED_ZERO');
    uint256 fromBalance = _scaledBalances[from];
    require(fromBalance >= scaled, 'BALANCE');
    unchecked {
      _scaledBalances[from] = fromBalance - scaled;
      _scaledBalances[to] += scaled;
    }
  }
}

contract Wildcat4626WrapperRoundingTest is Test {
  MockMarketToken internal market;
  Wildcat4626Wrapper internal wrapper;
  address internal constant ALICE = address(0xA11CE);
  MockSanctionsSentinel internal sanctionsSentinel;

  function setUp() external {
    sanctionsSentinel = new MockSanctionsSentinel();
    market = new MockMarketToken(address(this), address(sanctionsSentinel));
    wrapper = new Wildcat4626Wrapper(address(market));
  }

  // mostly utils for making sure that the conversions match eip-4626 rounding rules

  function test_previewRedeem_RoundsDown() external {
    market.setScaleFactor(RAY + 1e7);
    uint256 shares = 50e18;
    uint256 expectedAssets = 50e18;
    uint256 assets = wrapper.previewRedeem(shares);
    assertEq(assets, expectedAssets, 'previewRedeem should round down (floor)');
  }

  function test_previewDeposit_RoundsDown() external {
    market.setScaleFactor(RAY - 1e7);
    uint256 assets = 50e18;
    uint256 expectedShares = 50e18;
    uint256 shares = wrapper.previewDeposit(assets);
    assertEq(shares, expectedShares, 'previewDeposit should round down (floor)');
  }

  function test_previewMint_RoundsUp() external {
    market.setScaleFactor(RAY - 1e7);
    uint256 shares = 50e18;
    uint256 expectedAssets = 50e18;
    uint256 assets = wrapper.previewMint(shares);
    assertEq(assets, expectedAssets, 'previewMint should round up to ensure sufficient assets');
    uint256 resultingShares = MathUtils.rayDiv(assets, market.scaleFactor());
    assertGe(resultingShares, shares, 'returned assets must yield at least requested shares');
  }

  function test_previewWithdraw_RoundsUp() external {
    market.setScaleFactor(RAY + 1e7);
    uint256 assets = 50e18;
    uint256 expectedShares = 50e18;
    uint256 shares = wrapper.previewWithdraw(assets);
    assertEq(shares, expectedShares, 'previewWithdraw should round up (ceiling)');
  }

  /// @notice convertToShares MUST round DOWN per EIP-4626
  function test_EIP4626_convertToShares_roundsDown() external {
    market.setScaleFactor(RAY + 1e7);

    uint256 assets = 50e18;
    uint256 actualShares = wrapper.convertToShares(assets);
    uint256 floorShares = MathUtils.mulDiv(assets, RAY, market.scaleFactor());

    assertEq(actualShares, floorShares, 'convertToShares must equal floor');
  }

  /// @notice convertToAssets MUST round DOWN per EIP-4626
  function test_EIP4626_convertToAssets_roundsDown() external {
    market.setScaleFactor(RAY + 1e7);

    uint256 shares = 50e18;
    uint256 actualAssets = wrapper.convertToAssets(shares);
    uint256 floorAssets = MathUtils.mulDiv(shares, market.scaleFactor(), RAY);

    assertEq(actualAssets, floorAssets, 'convertToAssets must equal floor');
  }

  /// @notice previewDeposit MUST round DOWN (user gets ≤ previewed shares)
  function test_EIP4626_previewDeposit_roundsDown() external {
    market.setScaleFactor(RAY + 1e7);

    uint256 assets = 50e18;
    uint256 previewShares = wrapper.previewDeposit(assets);
    uint256 floorShares = MathUtils.mulDiv(assets, RAY, market.scaleFactor());

    assertEq(previewShares, floorShares, 'previewDeposit must equal floor');
  }

  /// @notice previewMint MUST round UP (user pays ≥ previewed assets)
  function test_EIP4626_previewMint_roundsUp() external {
    market.setScaleFactor(RAY + 1e7);

    uint256 shares = 50e18;
    uint256 previewAssets = wrapper.previewMint(shares);
    uint256 ceilingAssets = MathUtils.mulDivUp(shares, market.scaleFactor(), RAY);

    assertEq(previewAssets, ceilingAssets, 'previewMint must equal ceiling');
  }

  /// @notice previewWithdraw MUST round UP (user burns ≥ previewed shares)
  function test_EIP4626_previewWithdraw_roundsUp() external {
    market.setScaleFactor(RAY + 4e8);

    uint256 assets = 100e18;
    uint256 previewShares = wrapper.previewWithdraw(assets);
    uint256 ceilingShares = MathUtils.mulDivUp(assets, RAY, market.scaleFactor());

    assertEq(previewShares, ceilingShares, 'previewWithdraw must equal ceiling');
  }

  /// @notice previewRedeem MUST round DOWN (user receives ≤ previewed assets)
  function test_EIP4626_previewRedeem_roundsDown() external {
    market.setScaleFactor(RAY + 1e7);

    uint256 shares = 50e18;
    uint256 previewAssets = wrapper.previewRedeem(shares);
    uint256 floorAssets = MathUtils.mulDiv(shares, market.scaleFactor(), RAY);

    assertEq(previewAssets, floorAssets, 'previewRedeem must equal floor');
  }

  // fuzzzzzes (not perfect)

  /// @notice Fuzz: convertToShares always equals floor
  function testFuzz_EIP4626_convertToShares_equalsFloor(
    uint256 assets,
    uint256 scaleOffset
  ) external {
    assets = bound(assets, 1, 1e30);
    scaleOffset = bound(scaleOffset, 1, RAY / 2);
    market.setScaleFactor(RAY + scaleOffset);

    uint256 actual = wrapper.convertToShares(assets);
    uint256 floor = MathUtils.mulDiv(assets, RAY, market.scaleFactor());

    assertEq(actual, floor, 'convertToShares must equal floor');
  }

  /// @notice Fuzz: convertToAssets always equals floor
  function testFuzz_EIP4626_convertToAssets_equalsFloor(
    uint256 shares,
    uint256 scaleOffset
  ) external {
    shares = bound(shares, 1, 1e30);
    scaleOffset = bound(scaleOffset, 1, RAY / 2);
    market.setScaleFactor(RAY + scaleOffset);

    uint256 actual = wrapper.convertToAssets(shares);
    uint256 floor = MathUtils.mulDiv(shares, market.scaleFactor(), RAY);

    assertEq(actual, floor, 'convertToAssets must equal floor');
  }

  /// @notice Fuzz: previewMint always equals ceiling
  function testFuzz_EIP4626_previewMint_equalsCeiling(
    uint256 shares,
    uint256 scaleOffset
  ) external {
    shares = bound(shares, 1, 1e30);
    scaleOffset = bound(scaleOffset, 1, RAY / 2);
    market.setScaleFactor(RAY + scaleOffset);

    uint256 actual = wrapper.previewMint(shares);
    uint256 ceiling = MathUtils.mulDivUp(shares, market.scaleFactor(), RAY);

    assertEq(actual, ceiling, 'previewMint must equal ceiling');
  }

  /// @notice Fuzz: previewWithdraw always equals ceiling
  function testFuzz_EIP4626_previewWithdraw_equalsCeiling(
    uint256 assets,
    uint256 scaleOffset
  ) external {
    assets = bound(assets, 1, 1e30);
    scaleOffset = bound(scaleOffset, 1, RAY / 2);
    market.setScaleFactor(RAY + scaleOffset);

    uint256 actual = wrapper.previewWithdraw(assets);
    uint256 ceiling = MathUtils.mulDivUp(assets, RAY, market.scaleFactor());

    assertEq(actual, ceiling, 'previewWithdraw must equal ceiling');
  }

  /// @notice Fuzz: previewRedeem always equals floor
  function testFuzz_EIP4626_previewRedeem_equalsFloor(
    uint256 shares,
    uint256 scaleOffset
  ) external {
    shares = bound(shares, 1, 1e30);
    scaleOffset = bound(scaleOffset, 1, RAY / 2);
    market.setScaleFactor(RAY + scaleOffset);

    uint256 actual = wrapper.previewRedeem(shares);
    uint256 floor = MathUtils.mulDiv(shares, market.scaleFactor(), RAY);

    assertEq(actual, floor, 'previewRedeem must equal floor');
  }
}

//  fuzz tests for actual deposit/mint/withdraw/redeem execution
contract Wildcat4626WrapperExecutionFuzzTest is Test {
  using MathUtils for uint256;

  MockSanctionsSentinel internal sanctionsSentinel;
  MockMarketToken internal market;
  Wildcat4626Wrapper internal wrapper;

  address internal constant ALICE = address(0xA11CE);
  address internal constant BORROWER = address(0xB0123123);

  function setUp() external {
    sanctionsSentinel = new MockSanctionsSentinel();
    market = new MockMarketToken(BORROWER, address(sanctionsSentinel));
    wrapper = new Wildcat4626Wrapper(address(market));

    // Give ALICE tokens and approve wrapper
    market.mint(ALICE, 1000e18);
    vm.prank(ALICE);
    market.approve(address(wrapper), type(uint256).max);
  }

  /// @notice Fuzz: deposit() should never revert with SharesMismatch for valid inputs
  function testFuzz_deposit_neverSharesMismatch(
    uint256 assets,
    uint256 scaleOffset
  ) external {
    assets = bound(assets, 1e9, 100e18); // min 1 gwei to avoid ZeroShares
    scaleOffset = bound(scaleOffset, 0, RAY); // 1x to 2x scale factor
    market.setScaleFactor(RAY + scaleOffset);

    vm.prank(ALICE);
    uint256 shares = wrapper.deposit(assets, ALICE);

    assertEq(wrapper.balanceOf(ALICE), shares, 'balance must match returned shares');
    assertEq(market.scaledBalanceOf(address(wrapper)), shares, 'wrapper scaled balance must match');
  }

  /// @notice Fuzz: mint() should never revert with SharesMismatch for valid inputs
  function testFuzz_mint_neverSharesMismatch(
    uint256 shares,
    uint256 scaleOffset
  ) external {
    shares = bound(shares, 1e9, 100e18); // min 1 gwei
    scaleOffset = bound(scaleOffset, 0, RAY); // 1x to 2x scale factor
    market.setScaleFactor(RAY + scaleOffset);

    vm.prank(ALICE);
    uint256 assets = wrapper.mint(shares, ALICE);

    // Verify wrapper received the shares
    assertEq(wrapper.balanceOf(ALICE), shares, 'balance must match requested shares');
    assertEq(market.scaledBalanceOf(address(wrapper)), shares, 'wrapper scaled balance must match');
    assertGt(assets, 0, 'assets spent must be non-zero');
  }

  function testFuzz_withdraw_neverSharesMismatch(
    uint256 depositAssets,
    uint256 withdrawAssets,
    uint256 scaleOffset
  ) external {
    depositAssets = bound(depositAssets, 1e12, 100e18);
    scaleOffset = bound(scaleOffset, 0, RAY);
    market.setScaleFactor(RAY + scaleOffset);

    vm.prank(ALICE);
    uint256 depositedShares = wrapper.deposit(depositAssets, ALICE);

    // get max withdrawable and bound withdraw amount
    uint256 maxWithdraw = wrapper.maxWithdraw(ALICE);
    withdrawAssets = bound(withdrawAssets, 1e9, maxWithdraw);

    // Skip if would result in zero shares burned
    uint256 scaleFactor = market.scaleFactor();
    uint256 expectedSharesBurn = (withdrawAssets * RAY + scaleFactor / 2) / scaleFactor;
    vm.assume(expectedSharesBurn > 0);

    vm.prank(ALICE);
    uint256 sharesBurned = wrapper.withdraw(withdrawAssets, ALICE, ALICE);

    assertLe(sharesBurned, depositedShares, 'cannot burn more than deposited');
    assertEq(
      wrapper.balanceOf(ALICE),
      depositedShares - sharesBurned,
      'balance must decrease by burned shares'
    );
  }

  /// @notice Fuzz: redeem() should never revert with SharesMismatch for valid inputs
  function testFuzz_redeem_neverSharesMismatch(
    uint256 depositAssets,
    uint256 redeemShares,
    uint256 scaleOffset
  ) external {
    depositAssets = bound(depositAssets, 1e12, 100e18);
    scaleOffset = bound(scaleOffset, 0, RAY);
    market.setScaleFactor(RAY + scaleOffset);

    // First deposit
    vm.prank(ALICE);
    uint256 depositedShares = wrapper.deposit(depositAssets, ALICE);

    // Bound redeem shares to what ALICE has
    redeemShares = bound(redeemShares, 1, depositedShares);

    // Skip if would result in zero assets
    uint256 scaleFactor = market.scaleFactor();
    uint256 expectedAssets = (redeemShares * scaleFactor) / RAY;
    vm.assume(expectedAssets > 0);

    vm.prank(ALICE);
    uint256 assetsReceived = wrapper.redeem(redeemShares, ALICE, ALICE);

    assertEq(
      wrapper.balanceOf(ALICE),
      depositedShares - redeemShares,
      'balance must decrease by redeemed shares'
    );
    assertGt(assetsReceived, 0, 'must receive assets');
  }

  /// @notice Fuzz: Full round-trip deposit→redeem should work at any scale factor
  function testFuzz_depositRedeem_roundTrip(
    uint256 assets,
    uint256 scaleOffset
  ) external {
    assets = bound(assets, 1e12, 100e18);
    scaleOffset = bound(scaleOffset, 0, RAY);
    market.setScaleFactor(RAY + scaleOffset);

    uint256 aliceBalanceBefore = market.balanceOf(ALICE);

    vm.startPrank(ALICE);
    uint256 shares = wrapper.deposit(assets, ALICE);
    uint256 assetsBack = wrapper.redeem(shares, ALICE, ALICE);
    vm.stopPrank();

    // Should get back close to original (may lose 1wei to rounding)
    assertLe(aliceBalanceBefore - market.balanceOf(ALICE), 2, 'round-trip loss should be minimal');
    assertEq(wrapper.balanceOf(ALICE), 0, 'should have no shares left');
  }

  /// @notice Fuzz: Full round-trip mint→withdraw should work at any scale factor
  function testFuzz_mintWithdraw_roundTrip(
    uint256 shares,
    uint256 scaleOffset
  ) external {
    shares = bound(shares, 1e12, 100e18);
    scaleOffset = bound(scaleOffset, 0, RAY);
    market.setScaleFactor(RAY + scaleOffset);

    uint256 aliceBalanceBefore = market.balanceOf(ALICE);

    vm.startPrank(ALICE);
    uint256 assetsPaid = wrapper.mint(shares, ALICE);

    // Withdraw the equivalent assets
    uint256 maxWithdraw = wrapper.maxWithdraw(ALICE);
    uint256 sharesBurned = wrapper.withdraw(maxWithdraw, ALICE, ALICE);
    vm.stopPrank();

    assertLe(
      shares > sharesBurned ? shares - sharesBurned : sharesBurned - shares,
      1,
      'round-trip shares variance should be at most 1 wei'
    );
    uint256 aliceBalanceAfter = market.balanceOf(ALICE);
    assertLe(
      aliceBalanceBefore > aliceBalanceAfter
        ? aliceBalanceBefore - aliceBalanceAfter
        : aliceBalanceAfter - aliceBalanceBefore,
      2,
      'round-trip asset loss should be minimal'
    );
  }
}
