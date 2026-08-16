// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './MarketConfigMatrix.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { IMarketRounding, Wildcat4626WrapperFactory } from 'src/vault/Wildcat4626WrapperFactory.sol';

/// @dev Scenarios anchored to the largest live production market: 130M
///      capacity, ~70M utilized, open-term standard, 8.5% APR, 5% penalty APR,
///      48h grace period, 24h withdrawal cycle, with a 4626 wrapper on top.
///
///      The standard configuration is the production control; the same market
///      re-imagined as a revolving facility with a 4% commitment fee is the
///      what-if with no production data. The crossover tests isolate the
///      economic relationship between the two models at utilization extremes.
contract ProductionMirrorTest is MarketConfigMatrix {
  using MathUtils for uint256;

  uint256 internal constant TOTAL_DEPOSITS = 130_000_000e18;
  uint256 internal constant UTILIZED = 70_000_000e18;

  function _mirrorCell(MatrixMarketKind marketKind) internal pure returns (Cell memory cell) {
    cell = defaultCell(MatrixHooksKind.OpenTerm, marketKind);
    cell.maxTotalSupply = uint128(TOTAL_DEPOSITS);
    cell.annualInterestBips = 850;
    cell.delinquencyFeeBips = 500;
    cell.delinquencyGracePeriod = 48 hours;
    cell.withdrawalBatchDuration = 24 hours;
    cell.reserveRatioBips = 2_000;
    cell.commitmentFeeBips = 400;
  }

  function _deployMirror(MatrixMarketKind marketKind) internal returns (DeployedCell memory d) {
    d = deployCell(_mirrorCell(marketKind));
    _depositAs(d, alice, 80_000_000e18);
    _depositAs(d, bob, 50_000_000e18);
    _borrowAs(d, UTILIZED);
  }

  // ========================================================================== //
  //                   Production control and RCF what-if runs                  //
  // ========================================================================== //

  function test_mirror_standard_productionControl() external {
    DeployedCell memory d = _deployMirror(MatrixMarketKind.Standard);
    // v2.5 identity: bumped version string and the transfer-rounding marker
    // the 4626 wrapper factory routes on.
    assertEq(d.market.version(), '2.5', 'market version');
    assertEq(
      IMarketRounding(address(d.market)).scaledTransferRounding(),
      keccak256('scaleAmountDown'),
      'rounding marker'
    );
    _runMirrorLifecycle(d);
  }

  /// @dev The what-if: the same market as a revolving facility with a 4%
  ///      commitment fee. Exercises the commitment fee + drawn APR + penalty
  ///      APR triple stack, which no production market has ever run.
  function test_mirror_revolving_whatIf() external {
    DeployedCell memory d = _deployMirror(MatrixMarketKind.Revolving);
    assertEq(
      IWildcatMarketRevolving(address(d.market)).drawnAmount(),
      UTILIZED,
      'drawn != utilized'
    );
    // Revolving markets inherit the v2.5 identity, and the wrapper factory's
    // rounding constant must match the marker on real market bytecode.
    assertEq(d.market.version(), '2.5', 'market version');
    Wildcat4626WrapperFactory wrapperFactory = new Wildcat4626WrapperFactory(
      address(archController),
      address(0)
    );
    assertTrue(
      wrapperFactory.isFloorRoundingMarket(address(d.market)),
      'facade should accept a real v2.5 revolving market'
    );
    _runMirrorLifecycle(d);
  }

  function _runMirrorLifecycle(DeployedCell memory d) internal {
    // A production-quiet month, oracle-checked.
    _accrueAndCheck(d, 30 days);
    assertFalse(d.market.previousState().isDelinquent, 'delinquent in quiet month');

    // Borrower stops covering: draw everything, let interest push the market
    // under its reserve requirement.
    uint256 remaining = d.market.borrowableAssets();
    if (remaining > 0) _borrowAs(d, remaining);
    _accrueAndCheck(d, 12 hours);
    assertTrue(d.market.previousState().isDelinquent, 'should be delinquent');

    // Inside the 48h grace period: delinquent but no penalty yet. The oracle
    // models penalty time exactly, so these checks pin grace behavior.
    _accrueAndCheck(d, 24 hours);

    // Past grace: the 5% penalty APR stacks on top (and on revolving, on top
    // of the commitment fee and drawn APR).
    _accrueAndCheck(d, 5 days);
    assertGt(d.market.previousState().timeDelinquent, 48 hours, 'penalty time not accrued');

    // Borrower recovers: repay well past the requirement, then watch the
    // penalty clock decay through the grace period (still oracle-exact).
    uint256 debts = d.market.totalDebts();
    uint256 assets = asset.balanceOf(address(d.market));
    _repayAs(d, debts.satSub(assets));
    _accrueAndCheck(d, 24 hours);
    _accrueAndCheck(d, 7 days);
    assertFalse(d.market.previousState().isDelinquent, 'should have recovered');
    assertEq(d.market.previousState().timeDelinquent, 0, 'penalty clock not fully decayed');
  }

  // ========================================================================== //
  //                     Lender yield crossover: std vs RCF                     //
  // ========================================================================== //

  /// @dev With commitment fee C and APR R, revolving lender yield equals
  ///      C + R * utilization. The crossover against a standard market's flat
  ///      R sits at utilization (R - C) / R — for 8.5% and 4%, ~52.9%.
  ///      Production's ~54% utilization lands just above it: the what-if is
  ///      nearly yield-neutral. Isolate the ordering at both extremes and at
  ///      the production point.
  function test_mirror_lenderYieldCrossover() external {
    // 10% utilization: revolving must yield less than standard.
    _assertYieldOrdering(13_000_000e18, false);
    // Production (~53.8%, just above the 52.9% crossover): revolving edges out.
    _assertYieldOrdering(UTILIZED, true);
    // 95% utilization: revolving yields strictly more.
    _assertYieldOrdering(123_500_000e18, true);
  }

  function _assertYieldOrdering(uint256 draw, bool revolvingWins) internal {
    // Zero reserve ratio isolates the yield math from borrowing constraints
    // (the production 20% reserve would cap utilization at 80%).
    Cell memory stdCell = _mirrorCell(MatrixMarketKind.Standard);
    Cell memory rcfCell = _mirrorCell(MatrixMarketKind.Revolving);
    stdCell.reserveRatioBips = 0;
    rcfCell.reserveRatioBips = 0;
    DeployedCell memory std = deployCell(stdCell);
    DeployedCell memory rcf = deployCell(rcfCell);
    _depositAs(std, alice, TOTAL_DEPOSITS);
    _depositAs(rcf, alice, TOTAL_DEPOSITS);
    _borrowAs(std, draw);
    _borrowAs(rcf, draw);

    // Single segment so both oracles are exact and drawn == initial ratio.
    uint256 expectedStd = _expectedScaleFactorAt(std, block.timestamp + 30 days);
    uint256 expectedRcf = _expectedScaleFactorAt(rcf, block.timestamp + 30 days);
    fastForward(30 days);
    std.market.updateState();
    rcf.market.updateState();
    assertEq(uint256(std.market.scaleFactor()), expectedStd, 'std oracle');
    assertEq(uint256(rcf.market.scaleFactor()), expectedRcf, 'rcf oracle');

    if (revolvingWins) {
      assertGt(expectedRcf, expectedStd, 'revolving should out-yield standard');
    } else {
      assertLt(expectedRcf, expectedStd, 'revolving should under-yield standard');
    }
  }

  // ========================================================================== //
  //                            4626 wrapper layering                           //
  // ========================================================================== //

  function test_mirror_wrapper_standard() external {
    _runWrapperLayer(_deployMirror(MatrixMarketKind.Standard));
  }

  function test_mirror_wrapper_revolvingWhatIf() external {
    _runWrapperLayer(_deployMirror(MatrixMarketKind.Revolving));
  }

  /// @dev The wrapper wraps MARKET tokens, so on a credential-gated market it
  ///      is itself a lender: transfers into it hit the transfer hook and it
  ///      must be credentialed before deposits can flow.
  function _runWrapperLayer(DeployedCell memory d) internal {
    Wildcat4626Wrapper wrapper = Wildcat4626Wrapper(
      wrapperFactory.createWrapper(address(d.market))
    );
    uint256 wrapAmount = 30_000_000e18;

    startPrank(alice);
    d.market.approve(address(wrapper), type(uint256).max);
    // ERC-4626 previews intentionally ignore deposit limits, but maxDeposit
    // and maxMint must report that this transfer-gated wrapper is not ready.
    assertGt(wrapper.previewDeposit(wrapAmount), 0, 'preview unexpectedly gated');
    assertEq(wrapper.maxDeposit(alice), 0, 'maxDeposit ignored wrapper access');
    assertEq(wrapper.maxMint(alice), 0, 'maxMint ignored wrapper access');
    // Without a credential the wrapper cannot receive market tokens. The
    // hook's NotApprovedLender revert is swallowed by the wrapper's safe
    // transfer library and resurfaces as TransferFromFailed.
    vm.expectRevert(LibERC20.TransferFromFailed.selector);
    wrapper.deposit(wrapAmount, alice);
    stopPrank();

    _grantHookRole(d.hooksInstance, address(wrapper));
    assertGe(wrapper.maxDeposit(alice), wrapAmount, 'credential did not enable maxDeposit');
    assertGt(wrapper.maxMint(alice), 0, 'credential did not enable maxMint');

    uint256 marketBalanceBefore = d.market.balanceOf(alice);
    startPrank(alice);
    uint256 shares = wrapper.deposit(wrapAmount, alice);
    stopPrank();
    assertGt(shares, 0, 'no shares minted');

    // The successful transfer makes the wrapper a known lender. Revoking its
    // credential must not hide capacity that the transfer hook will accept.
    vm.prank(address(ecdsaRoleProvider));
    BaseAccessControls(d.hooksInstance).revokeRole(address(wrapper));
    assertGe(wrapper.maxDeposit(alice), wrapAmount, 'known wrapper lost maxDeposit');

    // A month of interest accrues to the wrapper's rebasing market-token
    // balance, moving the scale factor off RAY: all four execution paths must
    // work at a fractional scale factor (the pre-fix wrapper reverted on
    // roughly half of them).
    _accrueQuietly(d, 30 days);
    assertGt(uint256(d.market.scaleFactor()), RAY, 'scale factor still RAY');

    startPrank(alice);
    uint256 mintCost = wrapper.mint(1_000_000e18, alice);
    assertGe(mintCost, wrapper.previewRedeem(1_000_000e18), 'mint cost below share value');
    uint256 withdrawnShares = wrapper.withdraw(500_000e18, alice, alice);
    assertLe(withdrawnShares, wrapper.previewWithdraw(500_000e18), 'withdraw burned over preview');
    uint256 redeemed = wrapper.redeem(wrapper.balanceOf(alice), alice, alice);
    stopPrank();

    assertGe(redeemed, wrapAmount, 'wrapper redemption below principal');
    assertEq(wrapper.totalSupply(), 0, 'shares outstanding after full exit');
    assertGe(
      d.market.balanceOf(alice) + DUST,
      marketBalanceBefore,
      'alice lost market tokens through the wrapper round-trip'
    );
  }

  function _accrueQuietly(DeployedCell memory d, uint256 duration) internal {
    fastForward(duration);
    d.market.updateState();
  }
}
