// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { Vm } from 'forge-std/Vm.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { IWildcatMarketRevolving } from 'src/interfaces/IWildcatMarketRevolving.sol';
import { FeeMath } from 'src/libraries/FeeMath.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { MathUtils, RAY } from 'src/libraries/MathUtils.sol';
import { AccountWithdrawalStatus, WithdrawalBatch } from 'src/libraries/Withdrawal.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { HookDispatchSentinelMock } from '../mocks/HookDispatchMocks.sol';

/// @dev Stateful action driver for the complete built-in hook × market matrix.
///      Every public action receives one generated input and applies it to all
///      six cells. Foundry is configured to tolerate action reverts, so any
///      unexpected result is recorded in a ghost counter and asserted by the
///      invariant contract after the generated sequence finishes.
contract MarketMatrixHandler {
  using FeeMath for MarketState;
  using MathUtils for uint256;

  struct ProtocolFeeSnapshot {
    uint256 accrued;
    uint256 recipientBalance;
    uint256 marketAssets;
  }

  uint8 internal constant OpenTerm = 0;
  uint8 internal constant FixedTerm = 1;
  uint8 internal constant PeriodicTerm = 2;
  uint256 internal constant MaximumActionAmount = 50_000e18;
  bytes32 internal constant InterestAndFeesAccruedTopic =
    0x18247a393d0531b65fbd94f5e78bc5639801a4efda62ae7b43533c4442116c3a;

  address internal constant VmAddress = address(uint160(uint256(keccak256('hevm cheat code'))));
  Vm internal constant vm = Vm(VmAddress);

  WildcatMarket[] internal markets;
  MockERC20[] internal assets;
  HookDispatchSentinelMock[] internal sentinels;
  PeriodicTermHooks[] internal periodicHooks;
  uint8[] internal hooksKinds;
  bool[] internal revolving;
  uint32[] internal fixedTermEnds;
  uint16[] internal commitmentFeeBips;
  uint256[] internal lastScaleFactors;
  uint256[] internal initialProtocolFeeLiabilities;
  uint256[] internal observedProtocolFeesAccrued;
  address[] internal actors;

  mapping(uint256 cellIndex => uint32[] expiries) internal trackedExpiries;
  mapping(uint256 cellIndex => mapping(uint32 expiry => bool tracked)) internal isTrackedExpiry;
  mapping(address actor => bool sanctioned) internal sanctionedActors;
  bool internal borrowerSanctioned;

  // Action-time assertions cannot revert safely while fail_on_revert is false.
  // Keep durable counters instead so the invariant entrypoints own the failure.
  uint256 public withdrawalGateViolations;
  uint256 public scaleFactorDecreases;
  uint256 public drawnAmountFailures;
  uint256 public utilizationInterestFailures;
  uint256 public arithmeticPanicCount;
  uint256 public protocolFeeConservationFailures;
  uint256 public nonzeroProtocolFeeAccruals;
  uint256 public nonzeroProtocolFeeCollections;
  uint256 public partialProtocolFeeCollections;
  uint256 public sanctionsFailures;
  uint256 public unexpectedActionFailures;

  constructor(
    address[] memory markets_,
    address[] memory assets_,
    address[] memory sentinels_,
    address[] memory periodicHooks_,
    uint8[] memory hooksKinds_,
    bool[] memory revolving_,
    uint32[] memory fixedTermEnds_,
    uint16[] memory commitmentFeeBips_,
    address[] memory actors_
  ) {
    uint256 length = markets_.length;
    require(length != 0 && actors_.length != 0, 'empty matrix');
    require(
      assets_.length == length &&
        sentinels_.length == length &&
        periodicHooks_.length == length &&
        hooksKinds_.length == length &&
        revolving_.length == length &&
        fixedTermEnds_.length == length &&
        commitmentFeeBips_.length == length,
      'matrix length'
    );

    for (uint256 i; i < length; i++) {
      WildcatMarket market = WildcatMarket(markets_[i]);
      markets.push(market);
      assets.push(MockERC20(assets_[i]));
      sentinels.push(HookDispatchSentinelMock(sentinels_[i]));
      periodicHooks.push(PeriodicTermHooks(periodicHooks_[i]));
      hooksKinds.push(hooksKinds_[i]);
      revolving.push(revolving_[i]);
      fixedTermEnds.push(fixedTermEnds_[i]);
      commitmentFeeBips.push(commitmentFeeBips_[i]);
      lastScaleFactors.push(market.scaleFactor());
      initialProtocolFeeLiabilities.push(
        market.previousState().accruedProtocolFees +
          MockERC20(assets_[i]).balanceOf(market.feeRecipient())
      );
      observedProtocolFeesAccrued.push(0);
    }
    actors = actors_;
  }

  function cellCount() external view returns (uint256) {
    return markets.length;
  }

  function marketAt(uint256 cellIndex) external view returns (address) {
    return address(markets[cellIndex]);
  }

  function seedAccountingCoverage() external {
    require(nonzeroProtocolFeeAccruals == 0, 'accounting already seeded');

    vm.warp(vm.getBlockTimestamp() + 1 days);
    for (uint256 i; i < markets.length; i++) {
      (bool updated, ) = _callAs(
        i,
        address(this),
        address(markets[i]),
        abi.encodeCall(WildcatMarket.updateState, ())
      );
      require(updated, 'seed update');
      (bool collected, ) = _callAs(
        i,
        address(this),
        address(markets[i]),
        abi.encodeCall(WildcatMarket.collectFees, ())
      );
      require(collected, 'seed collection');
    }
    require(nonzeroProtocolFeeAccruals == markets.length, 'seed accrual coverage');
    require(nonzeroProtocolFeeCollections == markets.length, 'seed collection coverage');

    WildcatMarket market = markets[0];
    uint256 borrowable = market.borrowableAssets();
    (bool borrowed, ) = _callAs(
      0,
      _borrower(),
      address(market),
      abi.encodeCall(WildcatMarket.borrow, (borrowable))
    );
    require(borrowed, 'seed borrow');

    (bool queued, bytes memory result) = _callAs(
      0,
      actors[0],
      address(market),
      abi.encodeWithSignature('queueFullWithdrawal()')
    );
    require(queued && result.length == 32, 'seed queue');
    _trackExpiry(0, abi.decode(result, (uint32)));

    vm.warp(vm.getBlockTimestamp() + 1 days);
    (bool updated, ) = _callAs(
      0,
      address(this),
      address(market),
      abi.encodeCall(WildcatMarket.updateState, ())
    );
    require(updated, 'underfunded update');

    uint256 partialFeePayment = market.previousState().accruedProtocolFees / 2;
    require(partialFeePayment != 0, 'zero partial fee');
    _fundBorrower(0, partialFeePayment);
    (bool repaid, ) = _callAs(
      0,
      _borrower(),
      address(market),
      abi.encodeCall(WildcatMarket.repay, (partialFeePayment))
    );
    require(repaid, 'seed repay');
    (bool partiallyCollected, ) = _callAs(
      0,
      address(this),
      address(market),
      abi.encodeCall(WildcatMarket.collectFees, ())
    );
    require(partiallyCollected && partialProtocolFeeCollections != 0, 'partial collection');
  }

  // ----------------------------------------------------------------------- //
  // Generated actions
  // ----------------------------------------------------------------------- //

  function deposit(uint256 actorSeed, uint256 amountSeed) external {
    address actor = _actor(actorSeed);
    for (uint256 i; i < markets.length; i++) {
      WildcatMarket market = markets[i];
      if (market.isClosed()) continue;
      uint256 maximumDeposit = market.maximumDeposit();
      uint256 minimumDeposit = MathUtils.mulDivUp(1, market.scaleFactor(), RAY);
      if (maximumDeposit < minimumDeposit) continue;

      uint256 amount = _bound(
        amountSeed,
        minimumDeposit,
        MathUtils.min(maximumDeposit, MaximumActionAmount)
      );
      uint256 drawnBefore = _drawnAmountIfRevolving(i);
      assets[i].mint(actor, amount);
      vm.prank(actor);
      assets[i].approve(address(market), amount);
      (bool success, ) = _callAs(
        i,
        actor,
        address(market),
        abi.encodeCall(WildcatMarket.depositUpTo, (amount))
      );
      if (!success && !sanctionedActors[actor]) unexpectedActionFailures++;
      _checkDrawnUnchanged(i, drawnBefore);
      _observe(i);
    }
  }

  function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
    address from = _actor(fromSeed);
    address to = _actor(toSeed);
    if (from == to) return;

    for (uint256 i; i < markets.length; i++) {
      WildcatMarket market = markets[i];
      uint256 balance = market.balanceOf(from);
      uint256 minimumTransfer = MathUtils.mulDivUp(1, market.scaleFactor(), RAY);
      if (balance < minimumTransfer) continue;
      uint256 amount = _bound(amountSeed, minimumTransfer, balance);
      uint256 drawnBefore = _drawnAmountIfRevolving(i);
      (bool success, ) = _callAs(
        i,
        from,
        address(market),
        abi.encodeWithSignature('transfer(address,uint256)', to, amount)
      );
      if (!success && !sanctionedActors[from] && !sanctionedActors[to]) {
        unexpectedActionFailures++;
      }
      _checkDrawnUnchanged(i, drawnBefore);
      _observe(i);
    }
  }

  function borrow(uint256 amountSeed) external {
    for (uint256 i; i < markets.length; i++) {
      WildcatMarket market = markets[i];
      if (market.isClosed() || market.scaledTotalSupply() == 0) continue;
      uint256 borrowable = market.borrowableAssets();
      if (borrowable == 0) continue;

      uint256 amount = _bound(amountSeed, 1, MathUtils.min(borrowable, MaximumActionAmount));
      uint256 expectedDrawn = revolving[i] ? _expectedDrawnAfterBorrow(i, amount) : 0;
      (bool success, ) = _callAs(
        i,
        _borrower(),
        address(market),
        abi.encodeCall(WildcatMarket.borrow, (amount))
      );
      if (success) {
        if (borrowerSanctioned) sanctionsFailures++;
        if (revolving[i] && _drawnAmount(i) != expectedDrawn) drawnAmountFailures++;
      } else if (!borrowerSanctioned) {
        unexpectedActionFailures++;
      }
      _observe(i);
    }
  }

  function repay(uint256 amountSeed) external {
    for (uint256 i; i < markets.length; i++) {
      _repayCell(i, amountSeed);
    }
  }

  function _repayCell(uint256 cellIndex, uint256 amountSeed) internal {
    WildcatMarket market = markets[cellIndex];
    if (market.isClosed()) return;

    uint256 marketAssets = market.totalAssets();
    uint256 outstandingDebt = market.totalDebts().satSub(marketAssets);
    uint256 amount = _bound(amountSeed, 1, _maximumRepayWithSurplus(outstandingDebt));
    uint256 expectedDrawn;
    MarketState memory expectedState;
    if (revolving[cellIndex]) {
      expectedState = _expectedUpdatedRevolvingState(
        cellIndex,
        market.previousState(),
        marketAssets + amount
      );
      expectedDrawn = MathUtils.min(
        _drawnAmount(cellIndex),
        expectedState.totalDebts().satSub(marketAssets + amount)
      );
    }

    _fundBorrower(cellIndex, amount);
    (bool success, ) = _callAs(
      cellIndex,
      _borrower(),
      address(market),
      abi.encodeCall(WildcatMarket.repay, (amount))
    );
    if (!success) {
      unexpectedActionFailures++;
    } else if (revolving[cellIndex] && _drawnAmount(cellIndex) != expectedDrawn) {
      drawnAmountFailures++;
    }
    _observe(cellIndex);
  }

  function queueWithdrawal(uint256 actorSeed, uint256 amountSeed) external {
    address actor = _actor(actorSeed);
    for (uint256 i; i < markets.length; i++) {
      WildcatMarket market = markets[i];
      uint256 balance = market.balanceOf(actor);
      if (balance < 2e18) continue;

      uint256 amount = _bound(amountSeed, 1e18, balance / 2);
      bool gateOpen = _withdrawalsOpen(i) && !sanctionedActors[actor];
      uint256 drawnBefore = _drawnAmountIfRevolving(i);
      (bool success, bytes memory result) = _callAs(
        i,
        actor,
        address(market),
        abi.encodeWithSignature('queueWithdrawal(uint256)', amount)
      );
      _recordGateResult(i, gateOpen, success, result);
      _checkDrawnUnchanged(i, drawnBefore);
      _observe(i);
    }
  }

  function queueWithdrawalScaled(uint256 actorSeed, uint256 amountSeed) external {
    address actor = _actor(actorSeed);
    for (uint256 i; i < markets.length; i++) {
      WildcatMarket market = markets[i];
      uint256 balance = market.scaledBalanceOf(actor);
      if (balance == 0) continue;

      uint256 amount = _bound(amountSeed, 1, balance);
      bool gateOpen = _withdrawalsOpen(i) && !sanctionedActors[actor];
      uint256 drawnBefore = _drawnAmountIfRevolving(i);
      (bool success, bytes memory result) = _callAs(
        i,
        actor,
        address(market),
        abi.encodeWithSignature('queueWithdrawalScaled(uint256)', amount)
      );
      _recordGateResult(i, gateOpen, success, result);
      _checkDrawnUnchanged(i, drawnBefore);
      _observe(i);
    }
  }

  function queueFullWithdrawal(uint256 actorSeed) external {
    address actor = _actor(actorSeed);
    for (uint256 i; i < markets.length; i++) {
      WildcatMarket market = markets[i];
      if (market.scaledBalanceOf(actor) == 0) continue;

      bool gateOpen = _withdrawalsOpen(i) && !sanctionedActors[actor];
      uint256 drawnBefore = _drawnAmountIfRevolving(i);
      (bool success, bytes memory result) = _callAs(
        i,
        actor,
        address(market),
        abi.encodeWithSignature('queueFullWithdrawal()')
      );
      _recordGateResult(i, gateOpen, success, result);
      _checkDrawnUnchanged(i, drawnBefore);
      _observe(i);
    }
  }

  function executeWithdrawal(uint256 actorSeed, uint256 expirySeed) external {
    address actor = _actor(actorSeed);
    for (uint256 i; i < markets.length; i++) {
      uint256 length = trackedExpiries[i].length;
      if (length == 0) continue;
      uint32 expiry = trackedExpiries[i][expirySeed % length];
      if (expiry >= vm.getBlockTimestamp()) continue;

      uint256 drawnBefore = _drawnAmountIfRevolving(i);
      _callAs(
        i,
        actor,
        address(markets[i]),
        abi.encodeWithSignature('executeWithdrawal(address,uint32)', actor, expiry)
      );
      _checkDrawnUnchanged(i, drawnBefore);
      _observe(i);
    }
  }

  function repayAndProcess(uint256 amountSeed, uint256 batchSeed) external {
    for (uint256 i; i < markets.length; i++) {
      WildcatMarket market = markets[i];
      if (market.isClosed()) continue;

      uint256 outstandingDebt = market.totalDebts().satSub(market.totalAssets());
      uint256 amount = _bound(amountSeed, 0, _maximumRepayWithSurplus(outstandingDebt));
      uint256 maximumBatches = _bound(batchSeed, 0, 8);
      uint256 drawnBefore = revolving[i] ? _drawnAmount(i) : 0;
      uint256 expectedDrawn = drawnBefore;
      if (revolving[i] && amount != 0) {
        MarketState memory expectedState = _expectedUpdatedRevolvingState(
          i,
          market.previousState(),
          market.totalAssets() + amount
        );
        expectedDrawn = MathUtils.min(
          drawnBefore,
          expectedState.totalDebts().satSub(market.totalAssets() + amount)
        );
      }
      if (amount != 0) _fundBorrower(i, amount);
      (bool success, ) = _callAs(
        i,
        _borrower(),
        address(market),
        abi.encodeWithSignature(
          'repayAndProcessUnpaidWithdrawalBatches(uint256,uint256)',
          amount,
          maximumBatches
        )
      );
      if (!success) {
        unexpectedActionFailures++;
      } else if (revolving[i]) {
        if (_drawnAmount(i) != expectedDrawn) {
          drawnAmountFailures++;
        }
      }
      _observe(i);
    }
  }

  function updateState() external {
    for (uint256 i; i < markets.length; i++) {
      WildcatMarket market = markets[i];
      MarketState memory stateBefore = market.previousState();
      uint256 expectedScaleFactor = revolving[i]
        ? _expectedScaleFactorAfterUpdate(i, stateBefore)
        : 0;
      uint256 drawnBefore = revolving[i] ? _drawnAmount(i) : 0;
      (bool success, ) = _callAs(
        i,
        _borrower(),
        address(market),
        abi.encodeCall(WildcatMarket.updateState, ())
      );
      if (!success) {
        unexpectedActionFailures++;
      } else if (revolving[i]) {
        if (market.previousState().scaleFactor != expectedScaleFactor) {
          utilizationInterestFailures++;
        }
        if (_drawnAmount(i) != drawnBefore) drawnAmountFailures++;
      }
      _observe(i);
    }
  }

  function collectFees() external {
    for (uint256 i; i < markets.length; i++) {
      uint256 drawnBefore = _drawnAmountIfRevolving(i);
      _callAs(i, _borrower(), address(markets[i]), abi.encodeCall(WildcatMarket.collectFees, ()));
      _checkDrawnUnchanged(i, drawnBefore);
      _observe(i);
    }
  }

  function warp(uint256 timeDeltaSeed) external {
    uint256 timeDelta = _bound(timeDeltaSeed, 1 hours, 20 days);
    vm.warp(vm.getBlockTimestamp() + timeDelta);
    for (uint256 i; i < markets.length; i++) {
      MarketState memory stateBefore = markets[i].previousState();
      uint256 expectedScaleFactor = revolving[i]
        ? _expectedScaleFactorAfterUpdate(i, stateBefore)
        : 0;
      uint256 drawnBefore = revolving[i] ? _drawnAmount(i) : 0;
      (bool success, ) = _callAs(
        i,
        _borrower(),
        address(markets[i]),
        abi.encodeCall(WildcatMarket.updateState, ())
      );
      if (!success) {
        unexpectedActionFailures++;
      } else if (revolving[i]) {
        if (markets[i].previousState().scaleFactor != expectedScaleFactor) {
          utilizationInterestFailures++;
        }
        if (_drawnAmount(i) != drawnBefore) drawnAmountFailures++;
      }
      _observe(i);
    }
  }

  function sanctionLender(uint256 actorSeed) external {
    address actor = _actor(actorSeed);
    sanctionedActors[actor] = true;
    for (uint256 i; i < sentinels.length; i++) {
      sentinels[i].setSanctioned(actor, true);
    }
  }

  function sanctionBorrower() external {
    borrowerSanctioned = true;
    for (uint256 i; i < sentinels.length; i++) {
      sentinels[i].setSanctioned(_borrower(), true);
    }
  }

  function nukeFromOrbit(uint256 actorSeed) external {
    address actor = _actor(actorSeed);
    if (!sanctionedActors[actor]) return;

    for (uint256 i; i < markets.length; i++) {
      WildcatMarket market = markets[i];
      uint256 balanceBefore = market.scaledBalanceOf(actor);
      bool gateOpen = balanceBefore == 0 || _withdrawalsOpen(i);
      uint256 drawnBefore = _drawnAmountIfRevolving(i);
      (bool success, ) = _callAs(
        i,
        actor,
        address(market),
        abi.encodeWithSignature('nukeFromOrbit(address)', actor)
      );
      if (success != gateOpen) withdrawalGateViolations++;
      if (success) {
        if (balanceBefore != 0 && market.scaledBalanceOf(actor) != 0) sanctionsFailures++;
        uint32 expiry = market.previousState().pendingWithdrawalExpiry;
        if (expiry != 0) _trackExpiry(i, expiry);
      }
      _checkDrawnUnchanged(i, drawnBefore);
      _observe(i);
    }
  }

  function proposeAprReduction(uint256 bipsSeed) external {
    for (uint256 i; i < markets.length; i++) {
      PeriodicTermHooks hooks = periodicHooks[i];
      WildcatMarket market = markets[i];
      if (address(hooks) == address(0) || market.isClosed()) continue;
      uint256 currentBips = market.annualInterestBips();
      if (currentBips < 2) continue;
      uint16 bips = uint16(_bound(bipsSeed, 1, currentBips - 1));
      uint256 drawnBefore = _drawnAmountIfRevolving(i);
      _callAs(
        i,
        _borrower(),
        address(hooks),
        abi.encodeCall(PeriodicTermHooks.proposeAnnualInterestBips, (address(market), bips))
      );
      _checkDrawnUnchanged(i, drawnBefore);
      _observe(i);
    }
  }

  function executeAprReduction() external {
    for (uint256 i; i < markets.length; i++) {
      if (address(periodicHooks[i]) == address(0)) continue;
      uint256 drawnBefore = _drawnAmountIfRevolving(i);
      _callAs(
        i,
        address(this),
        address(markets[i]),
        abi.encodeWithSignature('executePendingAnnualInterestBipsReduction()')
      );
      _checkDrawnUnchanged(i, drawnBefore);
      _observe(i);
    }
  }

  // ----------------------------------------------------------------------- //
  // Invariant views and exit proof
  // ----------------------------------------------------------------------- //

  function scaledSupplyIsConserved() external view returns (bool) {
    for (uint256 i; i < markets.length; i++) {
      MarketState memory state = markets[i].currentState();
      uint256 actorBalances;
      for (uint256 j; j < actors.length; j++) {
        actorBalances += markets[i].scaledBalanceOf(actors[j]);
      }
      if (actorBalances + state.scaledPendingWithdrawals != state.scaledTotalSupply) return false;
    }
    return true;
  }

  function withdrawalLiabilitiesAreConserved() external view returns (bool) {
    for (uint256 i; i < markets.length; i++) {
      MarketState memory state = markets[i].currentState();
      uint256 scaledPending;
      uint256 normalizedLiabilities;
      uint32[] storage expiries = trackedExpiries[i];
      for (uint256 j; j < expiries.length; j++) {
        WithdrawalBatch memory batch = markets[i].getWithdrawalBatch(expiries[j]);
        if (batch.scaledAmountBurned > batch.scaledTotalAmount) return false;
        scaledPending += batch.scaledTotalAmount - batch.scaledAmountBurned;
        (bool valid, uint256 normalizedLiability) = _batchLiabilityMatchesAccounts(
          i,
          expiries[j],
          batch
        );
        if (!valid) return false;
        normalizedLiabilities += normalizedLiability;
      }
      if (scaledPending != state.scaledPendingWithdrawals) return false;
      if (normalizedLiabilities != state.normalizedUnclaimedWithdrawals) return false;
    }
    return true;
  }

  function _batchLiabilityMatchesAccounts(
    uint256 cellIndex,
    uint32 expiry,
    WithdrawalBatch memory batch
  ) internal view returns (bool valid, uint256 normalizedLiability) {
    uint256 accountScaledTotal;
    uint256 accountWithdrawnTotal;
    uint256 accountAllocatedTotal;
    uint256 participants;
    for (uint256 i; i < actors.length; i++) {
      AccountWithdrawalStatus memory status = markets[cellIndex].getAccountWithdrawalStatus(
        actors[i],
        expiry
      );
      accountScaledTotal += status.scaledAmount;
      accountWithdrawnTotal += status.normalizedAmountWithdrawn;
      if (status.scaledAmount == 0) continue;

      participants++;
      uint256 allocated = MathUtils.mulDiv(
        batch.normalizedAmountPaid,
        status.scaledAmount,
        batch.scaledTotalAmount
      );
      if (status.normalizedAmountWithdrawn > allocated) return (false, 0);
      if (expiry < vm.getBlockTimestamp()) {
        try markets[cellIndex].getAvailableWithdrawalAmount(actors[i], expiry) returns (
          uint256 available
        ) {
          if (available != allocated - status.normalizedAmountWithdrawn) return (false, 0);
        } catch {
          return (false, 0);
        }
      }
      accountAllocatedTotal += allocated;
    }
    if (
      accountScaledTotal != batch.scaledTotalAmount ||
      accountWithdrawnTotal > batch.normalizedAmountPaid
    ) return (false, 0);

    uint256 allocationDust = batch.normalizedAmountPaid - accountAllocatedTotal;
    if (allocationDust > (participants == 0 ? 0 : participants - 1)) return (false, 0);
    return (true, batch.normalizedAmountPaid - accountWithdrawnTotal);
  }

  function protocolFeesAreConserved() external view returns (bool) {
    if (protocolFeeConservationFailures != 0) return false;
    if (
      nonzeroProtocolFeeAccruals < markets.length ||
      nonzeroProtocolFeeCollections < markets.length ||
      partialProtocolFeeCollections == 0
    ) return false;
    for (uint256 i; i < markets.length; i++) {
      uint256 liveLiability = markets[i].previousState().accruedProtocolFees +
        assets[i].balanceOf(markets[i].feeRecipient());
      if (liveLiability != initialProtocolFeeLiabilities[i] + observedProtocolFeesAccrued[i])
        return false;
    }
    return true;
  }

  function scaleFactorsAreValid() external view returns (bool) {
    if (scaleFactorDecreases != 0) return false;
    for (uint256 i; i < markets.length; i++) {
      if (markets[i].scaleFactor() < RAY) return false;
    }
    return true;
  }

  function drawnAmountTransitionsAreValid() external view returns (bool) {
    if (drawnAmountFailures != 0) return false;
    for (uint256 i; i < markets.length; i++) {
      if (!revolving[i]) continue;
      // Lender exits and donated liquidity deliberately do not repay borrower
      // principal, so drawn amount is not globally bounded by live lender debt.
      if (markets[i].isClosed() && _drawnAmount(i) != 0) return false;
    }
    return true;
  }

  function unwindAndDrain() external returns (uint256 failureCell, uint256 failureCode) {
    // This is the liveness half of the matrix: every randomized state must still
    // close, settle each historical batch, and let every lender leave.
    for (uint256 i; i < markets.length; i++) {
      WildcatMarket market = markets[i];
      if (!_closeCell(i)) return (i, 5);
      for (uint256 j; j < actors.length; j++) {
        address actor = actors[j];
        if (market.scaledBalanceOf(actor) == 0) continue;
        if (sanctionedActors[actor]) {
          market.nukeFromOrbit(actor);
          _trackExpiry(i, market.previousState().pendingWithdrawalExpiry);
        } else {
          vm.prank(actor);
          _trackExpiry(i, market.queueFullWithdrawal());
        }
      }
    }

    vm.warp(vm.getBlockTimestamp() + 2);
    for (uint256 i; i < markets.length; i++) {
      WildcatMarket market = markets[i];
      market.updateState();
      uint32[] storage expiries = trackedExpiries[i];
      for (uint256 j; j < expiries.length; j++) {
        for (uint256 k; k < actors.length; k++) {
          try market.executeWithdrawal(actors[k], expiries[j]) {} catch {}
        }
      }

      if (!_collectFeesAfterDrain(i)) return (i, 6);

      if (market.getUnpaidBatchExpiries().length != 0) return (i, 1);
      if (market.scaledTotalSupply() != 0) return (i, 2);
      uint256 dustBound = (expiries.length + 1) * actors.length;
      if (market.totalDebts() > dustBound) return (i, 3);
      if (assets[i].balanceOf(address(market)) > dustBound) return (i, 4);
      if (!_protocolFeesAreConserved(i)) return (i, 7);
    }
    return (type(uint256).max, 0);
  }

  function _closeCell(uint256 cellIndex) internal returns (bool) {
    WildcatMarket market = markets[cellIndex];
    if (market.isClosed()) return true;

    MockERC20 asset = assets[cellIndex];
    asset.mint(_borrower(), market.totalDebts());
    vm.prank(_borrower());
    asset.approve(address(market), type(uint256).max);
    (bool success, ) = _callAs(
      cellIndex,
      _borrower(),
      address(market),
      abi.encodeCall(WildcatMarket.closeMarket, ())
    );
    return success;
  }

  function _collectFeesAfterDrain(uint256 cellIndex) internal returns (bool) {
    WildcatMarket market = markets[cellIndex];
    if (market.previousState().accruedProtocolFees == 0) return true;
    (bool success, ) = _callAs(
      cellIndex,
      address(this),
      address(market),
      abi.encodeCall(WildcatMarket.collectFees, ())
    );
    return success;
  }

  // ----------------------------------------------------------------------- //
  // Matrix bookkeeping
  // ----------------------------------------------------------------------- //

  function _recordGateResult(
    uint256 cellIndex,
    bool gateOpen,
    bool success,
    bytes memory result
  ) internal {
    if (success != gateOpen) withdrawalGateViolations++;
    if (success && result.length == 32) {
      _trackExpiry(cellIndex, abi.decode(result, (uint32)));
    }
  }

  function _trackExpiry(uint256 cellIndex, uint32 expiry) internal {
    if (expiry == 0 || isTrackedExpiry[cellIndex][expiry]) return;
    isTrackedExpiry[cellIndex][expiry] = true;
    trackedExpiries[cellIndex].push(expiry);
  }

  function _withdrawalsOpen(uint256 cellIndex) internal view returns (bool) {
    WildcatMarket market = markets[cellIndex];
    if (market.isClosed() || hooksKinds[cellIndex] == OpenTerm) return true;
    if (hooksKinds[cellIndex] == FixedTerm) {
      return vm.getBlockTimestamp() >= fixedTermEnds[cellIndex];
    }
    return periodicHooks[cellIndex].isWithdrawalWindowOpen(address(market));
  }

  function _observe(uint256 cellIndex) internal {
    WildcatMarket market = markets[cellIndex];
    uint256 scaleFactor = market.scaleFactor();
    if (scaleFactor < lastScaleFactors[cellIndex]) scaleFactorDecreases++;
    lastScaleFactors[cellIndex] = scaleFactor;
  }

  function _drawnAmountIfRevolving(uint256 cellIndex) internal view returns (uint256) {
    return revolving[cellIndex] ? _drawnAmount(cellIndex) : 0;
  }

  function _checkDrawnUnchanged(uint256 cellIndex, uint256 drawnBefore) internal {
    if (revolving[cellIndex] && _drawnAmount(cellIndex) != drawnBefore) {
      drawnAmountFailures++;
    }
  }

  function _expectedDrawnAfterBorrow(
    uint256 cellIndex,
    uint256 amount
  ) internal view returns (uint256) {
    WildcatMarket market = markets[cellIndex];
    MarketState memory state = _expectedUpdatedRevolvingState(
      cellIndex,
      market.previousState(),
      market.totalAssets()
    );
    uint256 assetsAfterBorrow = market.totalAssets().satSub(amount);
    uint256 debtsAfterBorrow = state.totalDebts().satSub(assetsAfterBorrow);
    return MathUtils.min(_drawnAmount(cellIndex) + amount, debtsAfterBorrow);
  }

  // ----------------------------------------------------------------------- //
  // Revolving state oracle
  // ----------------------------------------------------------------------- //

  function _expectedScaleFactorAfterUpdate(
    uint256 cellIndex,
    MarketState memory state
  ) internal view returns (uint256 expectedScaleFactor) {
    state = _expectedUpdatedRevolvingState(
      cellIndex,
      state,
      assets[cellIndex].balanceOf(address(markets[cellIndex]))
    );
    return state.scaleFactor;
  }

  function _expectedUpdatedRevolvingState(
    uint256 cellIndex,
    MarketState memory state,
    uint256 totalAssets
  ) internal view returns (MarketState memory) {
    uint256 timestamp = vm.getBlockTimestamp();
    uint32 expiry = state.pendingWithdrawalExpiry;
    WithdrawalBatch memory batch;
    if (expiry != 0) batch = _getRawPendingBatch(cellIndex, state, expiry);

    // Accrue to the batch boundary first. Settlement changes supply, so folding
    // both time segments together would calculate utilization from the wrong base.
    if (expiry != 0 && expiry < timestamp) {
      if (expiry != state.lastInterestAccruedTimestamp) {
        _accrueExpectedRevolvingInterest(cellIndex, state, expiry);
      }
      _applyExpectedPendingBatchPayment(state, batch, totalAssets);
      state.pendingWithdrawalExpiry = 0;
    }

    if (state.lastInterestAccruedTimestamp != timestamp) {
      _accrueExpectedRevolvingInterest(cellIndex, state, timestamp);
    }

    if (state.pendingWithdrawalExpiry != 0) {
      _applyExpectedPendingBatchPayment(state, batch, totalAssets);
    }
    return state;
  }

  function _getRawPendingBatch(
    uint256 cellIndex,
    MarketState memory previousState,
    uint32 expiry
  ) internal view returns (WithdrawalBatch memory batch) {
    WildcatMarket market = markets[cellIndex];
    MarketState memory calculatedState = market.currentState();
    batch = market.getWithdrawalBatch(expiry);

    // Both public views include the pending payment they can calculate from live
    // liquidity. Back that simulated delta out so the oracle starts from the
    // stored batch and independently applies the transition below.
    uint256 scaledAmountBurned = previousState.scaledTotalSupply -
      calculatedState.scaledTotalSupply;
    uint256 normalizedAmountPaid = calculatedState.normalizedUnclaimedWithdrawals -
      previousState.normalizedUnclaimedWithdrawals;
    batch.scaledAmountBurned -= uint104(scaledAmountBurned);
    batch.normalizedAmountPaid -= uint128(normalizedAmountPaid);
  }

  function _applyExpectedPendingBatchPayment(
    MarketState memory state,
    WithdrawalBatch memory batch,
    uint256 totalAssets
  ) internal pure {
    if (batch.scaledAmountBurned >= batch.scaledTotalAmount) return;
    uint256 availableLiquidity = batch.availableLiquidityForPendingBatch(state, totalAssets);
    if (availableLiquidity == 0) return;

    uint256 scaledAmountOwed = batch.scaledTotalAmount - batch.scaledAmountBurned;
    uint256 scaledAmountBurned = MathUtils.min(
      state.maxScaledSettleableAmount(availableLiquidity),
      scaledAmountOwed
    );
    if (scaledAmountBurned == 0) return;

    uint256 normalizedAmountPaid = MathUtils.mulDiv(scaledAmountBurned, state.scaleFactor, RAY);
    state.scaledPendingWithdrawals -= uint104(scaledAmountBurned);
    state.normalizedUnclaimedWithdrawals += uint128(normalizedAmountPaid);
    state.scaledTotalSupply -= uint104(scaledAmountBurned);
  }

  function _accrueExpectedRevolvingInterest(
    uint256 cellIndex,
    MarketState memory state,
    uint256 timestamp
  ) internal view {
    uint256 timeDelta = timestamp - state.lastInterestAccruedTimestamp;
    state.lastInterestAccruedTimestamp = uint32(timestamp);
    if (timeDelta == 0 || state.scaledTotalSupply == 0 || state.isClosed) return;

    uint256 baseInterestRay = MathUtils.calculateLinearInterestFromBips(
      commitmentFeeBips[cellIndex],
      timeDelta
    );
    uint256 drawn = _drawnAmount(cellIndex);
    if (state.annualInterestBips != 0 && drawn != 0) {
      uint256 annualInterestRay = MathUtils.calculateLinearInterestFromBips(
        state.annualInterestBips,
        timeDelta
      );
      uint256 totalSupply = state.totalSupply();
      uint256 drawnClamped = MathUtils.min(drawn, totalSupply);
      baseInterestRay += MathUtils.mulDiv(annualInterestRay, drawnClamped, totalSupply);
    }
    if (state.protocolFeeBips != 0) state.applyProtocolFee(baseInterestRay);
    state.scaleFactor = uint112(
      uint256(state.scaleFactor) + uint256(state.scaleFactor).rayMul(baseInterestRay)
    );
  }

  // ----------------------------------------------------------------------- //
  // Call and input helpers
  // ----------------------------------------------------------------------- //

  function _callAs(
    uint256 cellIndex,
    address caller,
    address target,
    bytes memory data
  ) internal returns (bool success, bytes memory result) {
    WildcatMarket market = markets[cellIndex];
    ProtocolFeeSnapshot memory beforeCall = ProtocolFeeSnapshot({
      accrued: market.previousState().accruedProtocolFees,
      recipientBalance: assets[cellIndex].balanceOf(market.feeRecipient()),
      marketAssets: assets[cellIndex].balanceOf(address(market))
    });

    vm.recordLogs();
    vm.prank(caller);
    (success, result) = target.call(data);
    Vm.Log[] memory logs = vm.getRecordedLogs();

    if (success) _recordProtocolFeeTransition(cellIndex, target, data, logs, beforeCall);
    if (!success && _isArithmeticPanic(result)) arithmeticPanicCount++;
  }

  function _recordProtocolFeeTransition(
    uint256 cellIndex,
    address target,
    bytes memory data,
    Vm.Log[] memory logs,
    ProtocolFeeSnapshot memory beforeCall
  ) internal {
    WildcatMarket market = markets[cellIndex];
    uint256 newlyAccrued = _protocolFeesFromLogs(logs, address(market));
    observedProtocolFeesAccrued[cellIndex] += newlyAccrued;
    if (newlyAccrued != 0) nonzeroProtocolFeeAccruals++;

    MarketState memory stateAfter = market.previousState();
    uint256 recipientBalanceAfter = assets[cellIndex].balanceOf(market.feeRecipient());
    if (
      beforeCall.accrued + beforeCall.recipientBalance + newlyAccrued !=
      stateAfter.accruedProtocolFees + recipientBalanceAfter
    ) protocolFeeConservationFailures++;

    if (target == address(market) && _selector(data) == WildcatMarket.collectFees.selector) {
      uint256 collected = recipientBalanceAfter - beforeCall.recipientBalance;
      uint256 available = beforeCall.marketAssets.satSub(stateAfter.normalizedUnclaimedWithdrawals);
      uint256 expected = MathUtils.min(available, beforeCall.accrued + newlyAccrued);
      if (collected != expected) protocolFeeConservationFailures++;
      if (collected != 0) {
        nonzeroProtocolFeeCollections++;
        if (collected < beforeCall.accrued + newlyAccrued) partialProtocolFeeCollections++;
      }
    }
  }

  function _protocolFeesFromLogs(
    Vm.Log[] memory logs,
    address market
  ) internal pure returns (uint256 total) {
    for (uint256 i; i < logs.length; i++) {
      if (
        logs[i].emitter != market ||
        logs[i].topics.length == 0 ||
        logs[i].topics[0] != InterestAndFeesAccruedTopic
      ) continue;
      uint256[6] memory fields = abi.decode(logs[i].data, (uint256[6]));
      total += fields[5];
    }
  }

  function _protocolFeesAreConserved(uint256 cellIndex) internal view returns (bool) {
    WildcatMarket market = markets[cellIndex];
    return
      market.previousState().accruedProtocolFees +
        assets[cellIndex].balanceOf(market.feeRecipient()) ==
      initialProtocolFeeLiabilities[cellIndex] + observedProtocolFeesAccrued[cellIndex];
  }

  function _selector(bytes memory data) internal pure returns (bytes4 selector) {
    if (data.length < 4) return bytes4(0);
    assembly ('memory-safe') {
      selector := mload(add(data, 0x20))
    }
  }

  function _isArithmeticPanic(bytes memory result) internal pure returns (bool) {
    if (result.length != 0x24) return false;
    bytes4 selector;
    uint256 panicCode;
    assembly ('memory-safe') {
      selector := mload(add(result, 0x20))
      panicCode := mload(add(result, 0x24))
    }
    return selector == bytes4(0x4e487b71) && panicCode == 0x11;
  }

  function _fundBorrower(uint256 cellIndex, uint256 amount) internal {
    assets[cellIndex].mint(_borrower(), amount);
    vm.prank(_borrower());
    assets[cellIndex].approve(address(markets[cellIndex]), amount);
  }

  function _drawnAmount(uint256 cellIndex) internal view returns (uint256) {
    return IWildcatMarketRevolving(address(markets[cellIndex])).drawnAmount();
  }

  function _maximumRepayWithSurplus(uint256 outstandingDebt) internal pure returns (uint256) {
    return MathUtils.min(outstandingDebt, 49_000e18) + 1_000e18;
  }

  function _actor(uint256 seed) internal view returns (address) {
    return actors[seed % actors.length];
  }

  function _borrower() internal pure returns (address) {
    return address(0xB04405E4);
  }

  function _bound(uint256 value, uint256 minimum, uint256 maximum) internal pure returns (uint256) {
    if (value >= minimum && value <= maximum) return value;
    return minimum + (value % (maximum - minimum + 1));
  }
}
