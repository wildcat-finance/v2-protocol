// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { CommonBase } from 'forge-std/Base.sol';
import { StdUtils } from 'forge-std/StdUtils.sol';
import './MarketConfigMatrix.sol';

/// @dev Randomized action handler for one deployed matrix cell.
///
///      The suite runs with `fail_on_revert = false`, which also swallows
///      assertion failures raised inside handler calls. Properties checked at
///      action time are therefore recorded as ghost violation counters and
///      asserted by the invariant functions, which do fail properly.
contract MatrixCellHandler is CommonBase, StdUtils {
  using MathUtils for uint256;

  WildcatMarket public market;
  PeriodicTermHooks internal pth;
  Cell internal cell;
  uint256 internal deployedAt;
  MockERC20 internal asset;
  address internal borrower;
  address[] internal lenders;

  uint32[] public trackedExpiries;

  // Ghost state
  uint256 public ghost_gateViolations;
  uint256 public ghost_scaleFactorDecreases;
  uint256 public ghost_drawnExceedsDebts;
  uint256 public ghost_lastScaleFactor;
  uint256 public ghost_depositCount;
  uint256 public ghost_queueCount;
  uint256 public ghost_queueRejections;
  uint256 public ghost_borrowCount;
  uint256 public ghost_warpCount;

  constructor(
    DeployedCell memory d,
    MockERC20 _asset,
    address _borrower,
    address[] memory _lenders
  ) {
    market = d.market;
    cell = d.cell;
    deployedAt = d.deployedAt;
    if (d.cell.hooksKind == MatrixHooksKind.PeriodicTerm) {
      pth = PeriodicTermHooks(d.hooksInstance);
    }
    asset = _asset;
    borrower = _borrower;
    lenders = _lenders;
    ghost_lastScaleFactor = market.scaleFactor();
  }

  function _lender(uint256 seed) internal view returns (address) {
    return lenders[seed % lenders.length];
  }

  /// @dev True if the cell's withdrawal gate is open at the current timestamp.
  function _withdrawalsOpen() internal view returns (bool) {
    if (market.isClosed()) return true;
    if (cell.hooksKind == MatrixHooksKind.FixedTerm) {
      return block.timestamp >= deployedAt + cell.fixedTermDuration;
    }
    if (cell.hooksKind == MatrixHooksKind.PeriodicTerm) {
      return pth.isWithdrawalWindowOpen(address(market));
    }
    return true;
  }

  function _touch() internal {
    uint256 sf = market.scaleFactor();
    if (sf < ghost_lastScaleFactor) ghost_scaleFactorDecreases++;
    ghost_lastScaleFactor = sf;
    if (cell.marketKind == MatrixMarketKind.Revolving) {
      if (IWildcatMarketRevolving(address(market)).drawnAmount() > market.totalDebts()) {
        ghost_drawnExceedsDebts++;
      }
    }
  }

  // ------------------------------- Actions -------------------------------- //

  function deposit(uint256 lenderSeed, uint256 amount) external {
    if (market.isClosed()) return;
    uint256 capacity = uint256(market.maxTotalSupply()).satSub(market.totalSupply());
    if (capacity < 1e18) return;
    amount = bound(amount, 1e18, MathUtils.min(capacity, 50_000e18));
    address lender = _lender(lenderSeed);
    vm.startPrank(lender);
    market.depositUpTo(amount);
    vm.stopPrank();
    ghost_depositCount++;
    _touch();
  }

  function queueWithdrawal(uint256 lenderSeed, uint256 amount) external {
    address lender = _lender(lenderSeed);
    uint256 balance = market.balanceOf(lender);
    // Stay far above the range where the amount scales down to zero, so the
    // only accepted revert is a closed withdrawal gate.
    if (balance < 2e18) return;
    amount = bound(amount, 1e18, balance / 2);
    bool gateOpen = _withdrawalsOpen();
    vm.startPrank(lender);
    try market.queueWithdrawal(amount) returns (uint32 expiry) {
      if (!gateOpen) ghost_gateViolations++;
      trackedExpiries.push(expiry);
      ghost_queueCount++;
    } catch {
      // Amounts are bounded to valid values, so the only accepted failure is
      // a closed withdrawal gate.
      if (gateOpen) ghost_gateViolations++;
      ghost_queueRejections++;
    }
    vm.stopPrank();
    _touch();
  }

  function executeWithdrawal(uint256 lenderSeed, uint256 expirySeed) external {
    if (trackedExpiries.length == 0) return;
    uint32 expiry = trackedExpiries[expirySeed % trackedExpiries.length];
    if (block.timestamp <= expiry) return;
    address lender = _lender(lenderSeed);
    // Tolerated failures: nothing owed to this lender in the batch, or the
    // batch has no paid liquidity yet.
    try market.executeWithdrawal(lender, expiry) {} catch {}
    _touch();
  }

  function borrow(uint256 amount) external {
    if (market.isClosed()) return;
    uint256 borrowable = market.borrowableAssets();
    if (borrowable < 2) return;
    amount = bound(amount, 1, borrowable);
    vm.startPrank(borrower);
    market.borrow(amount);
    vm.stopPrank();
    ghost_borrowCount++;
    _touch();
  }

  function repay(uint256 amount) external {
    if (market.isClosed()) return;
    uint256 debts = market.totalDebts();
    uint256 assets = asset.balanceOf(address(market));
    uint256 owed = debts.satSub(assets);
    if (owed < 2) return;
    amount = bound(amount, 1, owed);
    vm.startPrank(borrower);
    market.repay(amount);
    vm.stopPrank();
    _touch();
  }

  function warp(uint256 duration) external {
    duration = bound(duration, 1 hours, 20 days);
    vm.warp(block.timestamp + duration);
    market.updateState();
    ghost_warpCount++;
    _touch();
  }

  function poke() external {
    market.updateState();
    _touch();
  }

  function proposeAprReduction(uint256 bips) external {
    if (address(pth) == address(0) || market.isClosed()) return;
    uint256 current = market.annualInterestBips();
    if (current < 2) return;
    bips = bound(bips, 1, current - 1);
    vm.startPrank(borrower);
    // Tolerated failure: proposals are rejected inside withdrawal windows.
    try pth.proposeAnnualInterestBips(address(market), uint16(bips)) {} catch {}
    vm.stopPrank();
    _touch();
  }

  function executeAprReduction() external {
    if (address(pth) == address(0)) return;
    // Tolerated failures: no proposal, not ready, expired, unpaid batches.
    try market.executePendingAnnualInterestBipsReduction() {} catch {}
    _touch();
  }

  // ------------------------------- Unwind --------------------------------- //

  /// @dev Drains the market completely: repay all debts, close, queue full
  ///      withdrawals for every lender and execute them. Returns false with a
  ///      reason only on violation of the exit property.
  function unwindAndDrain() external returns (bool ok, string memory reason) {
    if (!market.isClosed()) {
      uint256 debts = market.totalDebts();
      uint256 assets = asset.balanceOf(address(market));
      vm.startPrank(borrower);
      if (debts > assets) {
        market.repay(debts - assets);
      }
      market.closeMarket();
      vm.stopPrank();
    }
    for (uint256 i; i < lenders.length; i++) {
      if (market.balanceOf(lenders[i]) > 0) {
        vm.startPrank(lenders[i]);
        // Track the exact exit expiry: `updateState` clears
        // `pendingWithdrawalExpiry` once the batch is processed, so it cannot
        // be recovered from state afterwards.
        trackedExpiries.push(market.queueFullWithdrawal());
        vm.stopPrank();
      }
    }
    vm.warp(block.timestamp + 2);
    market.updateState();
    // Execute every tracked batch (random-phase and exit) for every lender.
    for (uint256 i; i < trackedExpiries.length; i++) {
      for (uint256 j; j < lenders.length; j++) {
        try market.executeWithdrawal(lenders[j], trackedExpiries[i]) {} catch {}
      }
    }
    // With `maxScaledSettleableAmount` batch settlement, nothing may strand:
    // every batch on a closed, fully-funded market must pay out completely.
    // (An earlier version of this harness tolerated a small scaled-wei
    // remainder here, which masked a real close-settlement regression.)
    uint32[] memory unpaid = market.getUnpaidBatchExpiries();
    if (unpaid.length != 0) return (false, 'unpaid batches after close');
    if (market.scaledTotalSupply() != 0) return (false, 'scaled supply not drained');
    // Lenders must actually have been paid: nothing of value may remain in
    // the market once every batch has been executed. Proportional payouts
    // floor per lender per batch, so legitimate residue is bounded by one
    // wei per (batch, lender) pair — anything above that is a regression.
    uint256 dustBound = (trackedExpiries.length + 1) * lenders.length;
    if (market.totalDebts() > dustBound) return (false, 'debts remain after drain');
    if (asset.balanceOf(address(market)) > dustBound) {
      return (false, 'assets stranded after drain');
    }
    return (true, '');
  }
}

/// @dev One invariant suite per matrix cell; concrete cells at the bottom.
abstract contract MatrixInvariantBase is MarketConfigMatrix {
  MatrixCellHandler internal handler;

  function _cellUnderTest() internal pure virtual returns (Cell memory);

  function setUp() public override {
    super.setUp();
    DeployedCell memory d = deployCell(_cellUnderTest());
    address[] memory lenders = new address[](2);
    lenders[0] = alice;
    lenders[1] = bob;
    handler = new MatrixCellHandler(d, asset, borrower, lenders);

    // Seed liquidity so early borrow/withdraw actions have something to act on.
    _depositAs(d, alice, 10_000e18);

    targetContract(address(handler));
    bytes4[] memory selectors = new bytes4[](9);
    selectors[0] = MatrixCellHandler.deposit.selector;
    selectors[1] = MatrixCellHandler.queueWithdrawal.selector;
    selectors[2] = MatrixCellHandler.executeWithdrawal.selector;
    selectors[3] = MatrixCellHandler.borrow.selector;
    selectors[4] = MatrixCellHandler.repay.selector;
    selectors[5] = MatrixCellHandler.warp.selector;
    selectors[6] = MatrixCellHandler.poke.selector;
    selectors[7] = MatrixCellHandler.proposeAprReduction.selector;
    selectors[8] = MatrixCellHandler.executeAprReduction.selector;
    targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
  }

  function invariant_withdrawalGateEnforced() external view {
    assertEq(handler.ghost_gateViolations(), 0, 'withdrawal gate violated');
  }

  function invariant_scaleFactorMonotone() external view {
    assertEq(handler.ghost_scaleFactorDecreases(), 0, 'scale factor decreased');
  }

  function invariant_drawnAmountBounded() external view {
    assertEq(handler.ghost_drawnExceedsDebts(), 0, 'drawn amount exceeded total debts');
  }

  /// @dev After every run: the market must be fully unwindable — all debts
  ///      repayable, closable, and every lender able to exit completely.
  function afterInvariant() external {
    (bool ok, string memory reason) = handler.unwindAndDrain();
    assertTrue(ok, reason);
  }
}

contract MatrixInvariant_Open_Standard is MatrixInvariantBase {
  function _cellUnderTest() internal pure override returns (Cell memory) {
    return defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard);
  }
}

contract MatrixInvariant_Fixed_Standard is MatrixInvariantBase {
  function _cellUnderTest() internal pure override returns (Cell memory) {
    return defaultCell(MatrixHooksKind.FixedTerm, MatrixMarketKind.Standard);
  }
}

contract MatrixInvariant_Periodic_Standard is MatrixInvariantBase {
  function _cellUnderTest() internal pure override returns (Cell memory) {
    return defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Standard);
  }
}

contract MatrixInvariant_Open_Revolving is MatrixInvariantBase {
  function _cellUnderTest() internal pure override returns (Cell memory) {
    return defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Revolving);
  }
}

contract MatrixInvariant_Fixed_Revolving is MatrixInvariantBase {
  function _cellUnderTest() internal pure override returns (Cell memory) {
    return defaultCell(MatrixHooksKind.FixedTerm, MatrixMarketKind.Revolving);
  }
}

contract MatrixInvariant_Periodic_Revolving is MatrixInvariantBase {
  function _cellUnderTest() internal pure override returns (Cell memory) {
    return defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Revolving);
  }
}
