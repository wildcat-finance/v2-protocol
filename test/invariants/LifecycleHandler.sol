// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { Vm } from 'forge-std/Vm.sol';
import { MarketMatrixHandler } from './MarketMatrixHandler.sol';
import { LifecycleOracle, LifecycleReference } from './LifecycleOracle.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { MathUtils } from 'src/libraries/MathUtils.sol';
import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { WildcatMarketWithdrawals } from 'src/market/WildcatMarketWithdrawals.sol';
import { WildcatMarketConfig } from 'src/market/WildcatMarketConfig.sol';
import { AccountWithdrawalStatus } from 'src/libraries/Withdrawal.sol';

/// @dev reuse the matrix's actions and conservation checks. only the timeline oracle and
///      scheduled exit differ; don't fork a second copy of the general-purpose handler.
contract LifecycleHandler is MarketMatrixHandler {
  using MathUtils for uint256;
  LifecycleReference internal immutable referenceModel = new LifecycleReference();

  struct Coverage {
    uint256 writes;
    uint256 idleCrossings;
    uint256 activations;
    uint256 deadlineDefaults;
    uint256 penaltyDefaults;
    uint256 cures;
    uint256 closures;
    uint256 lateClosures;
    uint256 donations;
    uint256 rejectedAdmission;
    uint256 collections;
    uint256 escrowCollections;
    uint256 partialBatches;
    uint256 surplusRecoveries;
  }

  LifecycleOracle.Terms[] internal terms;
  LifecycleOracle.Observation[] internal observations;
  mapping(uint256 => mapping(uint32 => WithdrawalBatch)) internal observedBatches;
  mapping(uint256 => uint32[]) internal observedUnpaid;
  mapping(uint256 => Coverage) public seeded;
  mapping(uint256 => Coverage) public explored;
  bool internal exploring;
  uint256 public lifecycleFailures;
  uint256 public firstFailure;
  uint256 public firstFailureCell;

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
  )
    MarketMatrixHandler(
      markets_,
      assets_,
      sentinels_,
      periodicHooks_,
      hooksKinds_,
      revolving_,
      fixedTermEnds_,
      commitmentFeeBips_,
      actors_
    )
  {
    for (uint256 i; i < markets.length; ++i) {
      WildcatMarket m = markets[i];
      terms.push(
        LifecycleOracle.Terms({
          date: m.repaymentDate(),
          period: m.repaymentPeriod(),
          grace: m.delinquencyGracePeriod(),
          penaltyBips: m.delinquencyFeeBips(),
          commitmentBips: commitmentFeeBips[i],
          revolving: revolving[i]
        })
      );
      observations.push();
      observations[i].state = m.previousState();
      observations[i].cash = m.totalAssets();
    }
  }

  function beginExploration() external {
    exploring = true;
  }

  function drawAvailable() external {
    for (uint256 i; i < markets.length; ++i) {
      uint256 amount = markets[i].borrowableAssets();
      if (amount == 0) continue;
      uint256 expected = revolving[i] ? _expectedDrawnAfterBorrow(i, amount) : 0;
      (bool success,) = _callAs(i, _borrower(), address(markets[i]), abi.encodeCall(WildcatMarket.borrow, (amount)));
      _check(i, success && (!revolving[i] || _drawnAmount(i) == expected), 34);
    }
  }

  function coverageSnapshot(uint256 i, bool seed) external view returns (Coverage memory) {
    return seed ? seeded[i] : explored[i];
  }

  function trackedExpiryCount(uint256 i) external view returns (uint256) {
    return trackedExpiries[i].length;
  }

  /// @dev recovery must leave the entire liability ledger backed, including old unpaid batches.
  function recoverSurplus(uint256 cellSeed) public {
    uint256 i = cellSeed % markets.length;
    WildcatMarket m = markets[i];
    if (!m.isClosed()) return;
    uint256 debts = m.totalDebts();
    uint256 surplus = m.totalAssets().satSub(debts);
    uint256 borrowerBefore = assets[i].balanceOf(_borrower());
    (bool success,) =
      _callAs(i, _borrower(), address(m), abi.encodeCall(WildcatMarket.rescueTokens, (address(assets[i]))));
    _check(i, success && m.totalAssets() == debts && m.totalDebts() == debts, 47);
    _check(i, assets[i].balanceOf(_borrower()) == borrowerBefore + surplus, 48);
    if (success && surplus != 0) {
      Coverage storage c = exploring ? explored[i] : seeded[i];
      ++c.surplusRecoveries;
    }
  }

  /// @dev leave storage alone when time moves. the next action must resolve every crossed
  ///      boundary itself, including when that action transfers repayment before accrual.
  function advance(uint256 cellSeed, uint256 boundarySeed, uint256 offsetSeed) external {
    uint256 i = cellSeed % markets.length;
    uint256 nowTime = vm.getBlockTimestamp();
    uint256 boundary;
    uint256 kind = boundarySeed % 7;
    if (kind == 0) {
      boundary = terms[i].date;
    } else if (kind == 1) {
      boundary = terms[i].date + terms[i].period;
    } else if (kind == 2) {
      boundary = _preview(i, markets[i].totalAssets()).cutoff;
    } else if (kind == 3) {
      boundary = observations[i].state.pendingWithdrawalExpiry;
    } else if (kind == 4) {
      boundary = fixedTermEnds[i];
    } else if (kind == 5 && address(periodicHooks[i]) != address(0)) {
      (,, uint32 end) = periodicHooks[i].getPendingAprChange(address(markets[i]));
      boundary = end;
    }
    if (boundary != 0) boundary = boundary - 1 + (offsetSeed % 3);
    if (boundary < nowTime || boundary == 0) boundary = nowTime + _bound(offsetSeed, 1, 120 days);
    vm.warp(MathUtils.min(boundary, 2_000_000_000));
  }

  function checkpoint(uint256 cellSeed) public {
    uint256 i = cellSeed % markets.length;
    WildcatMarket m = markets[i];
    MarketState memory expected = m.currentState();
    bytes32 stored = keccak256(abi.encode(m.previousState()));
    vm.recordLogs();
    _check(i, keccak256(abi.encode(m.currentState())) == keccak256(abi.encode(expected)), 20);
    _check(i, vm.getRecordedLogs().length == 0, 21);
    _check(i, keccak256(abi.encode(m.previousState())) == stored, 22);
    expected.isDelinquent = expected.liquidityRequired() > m.totalAssets();
    (bool success,) = _callAs(i, address(this), address(m), abi.encodeCall(WildcatMarket.updateState, ()));
    _check(i, success, 23);
    _check(i, keccak256(abi.encode(m.previousState())) == keccak256(abi.encode(expected)), 24);
  }

  /// @dev partial, exact, one wei short, excess, or just enough to cure current reserves.
  ///      use both repayment entrypoints, including bounded maintenance after closure.
  function fund(uint256 cellSeed, uint256 mode, uint256 amountSeed, bool process) public {
    uint256 i = cellSeed % markets.length;
    WildcatMarket m = markets[i];
    uint256 cash = m.totalAssets();
    uint256 due = m.totalDebts().satSub(cash);
    uint256 amount;
    if (!m.isClosed()) {
      mode %= 5;
      if (mode == 0) amount = due / _bound(amountSeed, 2, 20);
      else if (mode == 1) amount = due;
      else if (mode == 2) amount = due.satSub(1);
      else if (mode == 3) amount = due + _bound(amountSeed, 1, 1_000e18);
      else amount = m.currentState().liquidityRequired().satSub(cash);
    }
    uint256 expectedDrawn = _repaymentExpectation(i, cash, amount);
    if (amount != 0) _fundBorrower(i, amount);
    bytes memory data = process || amount == 0
      ? abi.encodeCall(WildcatMarketWithdrawals.repayAndProcessUnpaidWithdrawalBatches, (amount, amountSeed % 3))
      : abi.encodeCall(WildcatMarket.repay, (amount));
    (bool success,) = _callAs(i, _borrower(), address(m), data);
    _check(i, success, 25);
    _check(i, !revolving[i] || _drawnAmount(i) == _finalRepaymentDrawn(i, expectedDrawn), 26);
  }

  function donate(uint256 cellSeed, uint256 mode, uint256 amountSeed) external {
    uint256 i = cellSeed % markets.length;
    WildcatMarket m = markets[i];
    uint256 due = m.totalDebts().satSub(m.totalAssets());
    uint256 amount = mode % 3 == 0 ? due / 2 : mode % 3 == 1 ? due : _bound(amountSeed, 1, 1_000e18);
    bytes32 beforeDonation = this.storedAccountingHash(i);
    this.transferDonation(i, amount);
    _check(i, this.storedAccountingHash(i) == beforeDonation, 28);
    if (amount != 0) ++_coverage(i).donations;
  }

  function storedAccountingHash(uint256 i) external view returns (bytes32) {
    return keccak256(abi.encode(markets[i].previousState(), markets[i].defaultedAt(), _drawnAmountIfRevolving(i)));
  }

  function transferDonation(uint256 i, uint256 amount) external {
    require(msg.sender == address(this), 'handler only');
    assets[i].mint(address(this), amount);
    vm.recordLogs();
    assets[i].transfer(address(markets[i]), amount);
    Vm.Log[] memory logs = vm.getRecordedLogs();
    for (uint256 j; j < logs.length; ++j) {
      _check(i, logs[j].emitter != address(markets[i]), 27);
    }
  }

  function probeAdmission(uint256 cellSeed) external {
    uint256 i = cellSeed % markets.length;
    if (!_inRepayment(i)) return;
    WildcatMarket m = markets[i];
    assets[i].mint(actors[0], 1e18);
    vm.prank(actors[0]);
    assets[i].approve(address(m), 1e18);
    (bool deposited,) = _callAs(i, actors[0], address(m), abi.encodeCall(WildcatMarket.depositUpTo, (1e18)));
    (bool borrowed,) = _callAs(i, _borrower(), address(m), abi.encodeCall(WildcatMarket.borrow, (0)));
    _check(i, !deposited && !borrowed && m.maximumDeposit() == 0 && m.borrowableAssets() == 0, 30);
    if (!deposited && !borrowed) ++_coverage(i).rejectedAdmission;
  }

  function changeApr(uint256 cellSeed, uint256 bipsSeed, uint256 ratioSeed) external {
    uint256 i = cellSeed % markets.length;
    WildcatMarket m = markets[i];
    MarketState memory beforeState = m.currentState();
    bool forbidden = beforeState.isClosed || (_inRepayment(i) && beforeState.liquidityRequired() > m.totalAssets());
    uint16 rate = uint16(_bound(bipsSeed, 1, 2_000));
    uint16 ratio = ratioSeed % 2 == 0 ? 10_000 : 0;
    (bool success,) = _callAs(
      i,
      _borrower(),
      address(m),
      abi.encodeCall(WildcatMarketConfig.setAnnualInterestAndReserveRatioBips, (rate, ratio))
    );
    if (forbidden) _check(i, !success, 31);
  }

  struct ClaimCheck {
    address actor;
    address recipient;
    uint32 expiry;
    uint256 amount;
    uint256 balance;
  }

  function collectClaim(uint256 cellSeed, uint256 actorSeed, uint256 expirySeed) public {
    uint256 i = cellSeed % markets.length;
    if (trackedExpiries[i].length == 0) return;
    WildcatMarket m = markets[i];
    ClaimCheck memory claim;
    claim.expiry = trackedExpiries[i][expirySeed % trackedExpiries[i].length];
    if (!_claimable(i, claim.expiry)) return;
    claim.actor = _actor(actorSeed);
    {
      WithdrawalBatch memory batch = m.getWithdrawalBatch(claim.expiry);
      AccountWithdrawalStatus memory status = m.getAccountWithdrawalStatus(claim.actor, claim.expiry);
      if (status.scaledAmount == 0) return;
      claim.amount = MathUtils.mulDiv(batch.normalizedAmountPaid, status.scaledAmount, batch.scaledTotalAmount)
        - status.normalizedAmountWithdrawn;
    }
    claim.recipient = sanctionedActors[claim.actor] ? sentinels[i].EscrowAddress() : claim.actor;
    claim.balance = assets[i].balanceOf(claim.recipient);
    (bool success, bytes memory result) = _callAs(
      i,
      address(this),
      address(m),
      abi.encodeCall(WildcatMarketWithdrawals.executeWithdrawal, (claim.actor, claim.expiry))
    );
    _check(i, success == (claim.amount != 0), 32);
    if (success) {
      _check(
        i,
        abi.decode(result, (uint256)) == claim.amount
          && assets[i].balanceOf(claim.recipient) == claim.balance + claim.amount,
        33
      );
    }
  }

  function _claimable(uint256 i, uint32 expiry) internal view returns (bool) {
    MarketState memory s = _preview(i, markets[i].totalAssets()).state;
    return expiry != s.pendingWithdrawalExpiry && (expiry < vm.getBlockTimestamp() || s.isClosed);
  }

  function collectClaims(uint256 cellSeed, uint256 actorSeed, uint256 expirySeed) external {
    uint256 i = cellSeed % markets.length;
    if (trackedExpiries[i].length == 0) return;
    uint32 expiry = trackedExpiries[i][expirySeed % trackedExpiries[i].length];
    if (!_claimable(i, expiry)) return;
    address[] memory accounts = new address[](2);
    uint32[] memory expiries = new uint32[](2);
    ClaimCheck[2] memory claims;
    for (uint256 j; j < 2; ++j) {
      accounts[j] = _actor((actorSeed % actors.length) + j);
      expiries[j] = expiry;
      claims[j] = _claimSnapshot(i, accounts[j], expiry);
    }
    (bool success, bytes memory result) = _callAs(
      i,
      address(this),
      address(markets[i]),
      abi.encodeCall(WildcatMarketWithdrawals.executeWithdrawals, (accounts, expiries))
    );
    _check(i, success == (claims[0].amount != 0 && claims[1].amount != 0), 40);
    if (!success) return;
    uint256[] memory received = abi.decode(result, (uint256[]));
    _check(i, received.length == 2, 41);
    for (uint256 j; j < 2; ++j) {
      uint256 increase = claims[j].amount;
      if (claims[0].recipient == claims[1].recipient) increase += claims[1 - j].amount;
      _check(i, received[j] == claims[j].amount, 42);
      _check(i, assets[i].balanceOf(claims[j].recipient) == claims[j].balance + increase, 43);
    }
  }

  function _claimSnapshot(uint256 i, address actor, uint32 expiry) internal view returns (ClaimCheck memory c) {
    c.actor = actor;
    c.expiry = expiry;
    c.recipient = sanctionedActors[actor] ? sentinels[i].EscrowAddress() : actor;
    c.balance = assets[i].balanceOf(c.recipient);
    WithdrawalBatch memory batch = markets[i].getWithdrawalBatch(expiry);
    AccountWithdrawalStatus memory status = markets[i].getAccountWithdrawalStatus(actor, expiry);
    if (status.scaledAmount != 0) {
      c.amount = MathUtils.mulDiv(batch.normalizedAmountPaid, status.scaledAmount, batch.scaledTotalAmount)
        - status.normalizedAmountWithdrawn;
    }
  }

  function _coverage(uint256 i) internal view returns (Coverage storage c) {
    return exploring ? explored[i] : seeded[i];
  }

  function _check(uint256 i, bool condition, uint256 code) internal {
    if (condition) return;
    if (lifecycleFailures++ == 0) {
      firstFailure = code;
      firstFailureCell = i;
    }
  }

  function _preview(uint256 i, uint256 cash) internal view returns (LifecycleOracle.Preview memory) {
    return referenceModel.preview(observations[i], terms[i], vm.getBlockTimestamp(), cash);
  }

  function expectedDefault(uint256 i) external view returns (uint256) {
    return _preview(i, markets[i].totalAssets()).defaultedAt;
  }

  function viewStates(uint256 i) external view returns (MarketState memory expected, MarketState memory actual) {
    expected = _preview(i, markets[i].totalAssets()).state;
    actual = markets[i].currentState();
  }

  function penaltyCutoff(uint256 i) external view returns (uint256) {
    return _preview(i, markets[i].totalAssets()).cutoff;
  }

  function viewsMatchOracle() external view returns (bool) {
    for (uint256 i; i < markets.length; ++i) {
      WildcatMarket m = markets[i];
      LifecycleOracle.Preview memory p = _preview(i, m.totalAssets());
      uint256 aggregateRemainder;
      for (uint256 j; j < trackedExpiries[i].length; ++j) {
        aggregateRemainder += observedBatches[i][trackedExpiries[i][j]].paymentRemainder;
      }
      if (aggregateRemainder != m.previousState().withdrawalRemainder) return false;
      if (keccak256(abi.encode(p.state)) != keccak256(abi.encode(m.currentState()))) return false;
      if (m.defaultedAt() != observations[i].defaultedAt) return false;
      if (m.repaymentDate() != terms[i].date || m.repaymentPeriod() != terms[i].period) {
        return false;
      }
      if (m.repaymentDeadline() != terms[i].date + terms[i].period) return false;
      if (p.state.isClosed != m.isClosed()) return false;
      if (_inRepayment(i) && (m.maximumDeposit() != 0 || m.borrowableAssets() != 0)) return false;
    }
    return true;
  }

  function _recordCallResult(CallRecord memory record, Vm.Log[] memory logs) internal override {
    this.checkRecordedCall(record, logs);
  }

  // keep nested struct copies out of inherited action bodies. no protocol calls happen here.
  function checkRecordedCall(CallRecord memory record, Vm.Log[] memory logs) external {
    require(msg.sender == address(this), 'handler only');
    uint256 i = record.cellIndex;
    LifecycleOracle.Observation memory old = observations[i];
    if (!record.success) {
      _check(i, keccak256(abi.encode(markets[i].previousState())) == keccak256(abi.encode(old.state)), 1);
      _check(i, markets[i].defaultedAt() == old.defaultedAt, 2);
      return;
    }
    if (!_hasStateWrite(logs, address(markets[i]))) return;
    uint256 cash = record.beforeCall.marketAssets;
    bytes4 selector = _selector(record.data);
    if (
      selector == WildcatMarket.repay.selector
        || selector == WildcatMarketWithdrawals.repayAndProcessUnpaidWithdrawalBatches.selector
    ) cash += _firstWord(record.data);
    LifecycleOracle.Preview memory p = _preview(i, cash);
    _recordBatches(record, logs);
    _recordLifecycle(i, old, p, logs, selector == WildcatMarket.closeMarket.selector);
  }

  // getWithdrawalBatch includes a simulated payment, even just after a write: floor-rounded
  // payments can leave one more scaled unit payable. reconstruct stored batches from events
  // instead of accidentally treating that preview as already committed accounting.
  function _recordBatches(CallRecord memory record, Vm.Log[] memory logs) internal {
    uint256 i = record.cellIndex;
    for (uint256 j; j < logs.length; ++j) {
      Vm.Log memory entry = logs[j];
      if (entry.emitter != address(markets[i]) || entry.topics.length < 2) continue;
      uint32 expiry = uint32(uint256(entry.topics[1]));
      WithdrawalBatch storage batch = observedBatches[i][expiry];
      if (entry.topics[0] == keccak256('WithdrawalQueued(uint256,address,uint256,uint256)')) {
        // the same call can close the market and clear pendingWithdrawalExpiry. retain the
        // emitted key even when nukeFromOrbit has no return value to recover it from.
        _trackExpiry(i, expiry);
        (uint256 amount,) = abi.decode(entry.data, (uint256, uint256));
        batch.scaledTotalAmount += uint104(amount);
      } else if (entry.topics[0] == keccak256('WithdrawalBatchPayment(uint256,uint256,uint256)')) {
        (uint256 burned, uint256 paid) = abi.decode(entry.data, (uint256, uint256));
        batch.scaledAmountBurned += uint104(burned);
        batch.normalizedAmountPaid += uint128(paid);
        // Payment events omit the retained fraction. Read the committed extra word;
        // the oracle still independently predicts subsequent payment transitions.
        bytes32 slot = keccak256(abi.encode(uint256(expiry), uint256(8)));
        batch.paymentRemainder = uint128(uint256(vm.load(address(markets[i]), bytes32(uint256(slot) + 1))) >> 128);
        if (burned != 0 && batch.scaledAmountBurned < batch.scaledTotalAmount) {
          ++_coverage(i).partialBatches;
        }
      } else if (entry.topics[0] == keccak256('WithdrawalExecuted(uint256,address,uint256)')) {
        ++_coverage(i).collections;
        if (sanctionedActors[address(uint160(uint256(entry.topics[2])))]) {
          ++_coverage(i).escrowCollections;
        }
      } else if (
        entry.topics[0] == keccak256('WithdrawalBatchClosed(uint256)')
          || entry.topics[0] == keccak256('WithdrawalBatchExpired(uint256,uint256,uint256,uint256)')
      ) {
        if (batch.scaledAmountBurned == batch.scaledTotalAmount) batch.paymentRemainder = 0;
      } else if (entry.topics[0] == keccak256('WithdrawalBatchCreated(uint256)')) {
        _check(i, batch.scaledTotalAmount == 0, 35);
      }
    }
    uint32[] memory afterQueue = markets[i].getUnpaidBatchExpiries();
    uint32[] storage beforeQueue = observedUnpaid[i];
    uint256 removed;
    while (removed < beforeQueue.length && (afterQueue.length == 0 || beforeQueue[removed] != afterQueue[0])) ++removed;
    bytes4 selector = _selector(record.data);
    uint256 limit;
    if (selector == WildcatMarket.closeMarket.selector) {
      limit = beforeQueue.length;
    } else if (selector == WildcatMarketWithdrawals.repayAndProcessUnpaidWithdrawalBatches.selector) {
      (, limit) = abi.decode(_arguments(record.data), (uint256, uint256));
    }
    _check(i, removed <= limit, 36);
    _check(i, afterQueue.length >= beforeQueue.length - removed, 37);
    for (uint256 j = removed; j < beforeQueue.length; ++j) {
      _check(i, j - removed < afterQueue.length && beforeQueue[j] == afterQueue[j - removed], 38);
    }
    for (uint256 j = 1; j < afterQueue.length; ++j) {
      _check(i, afterQueue[j] > afterQueue[j - 1], 39);
    }
    observedUnpaid[i] = afterQueue;
  }

  function _arguments(bytes memory data) internal pure returns (bytes memory args) {
    args = new bytes(data.length - 4);
    for (uint256 i; i < args.length; ++i) {
      args[i] = data[i + 4];
    }
  }

  function _recordLifecycle(
    uint256 i,
    LifecycleOracle.Observation memory old,
    LifecycleOracle.Preview memory p,
    Vm.Log[] memory logs,
    bool manualClose
  )
    internal
  {
    WildcatMarket m = markets[i];
    MarketState memory nowState = m.previousState();
    Coverage storage c = _coverage(i);
    ++c.writes;
    _check(i, nowState.scaleFactor == p.state.scaleFactor, 3);
    _check(i, _protocolFeesFromLogs(logs, address(m)) == p.fees, 4);
    _check(i, m.defaultedAt() == p.defaultedAt, 5);
    _check(i, nowState.lastInterestAccruedTimestamp == vm.getBlockTimestamp(), 6);
    _check(i, !old.state.isClosed || nowState.isClosed, 7);
    if (_inRepayment(i)) _check(i, nowState.reserveRatioBips == 10_000, 8);
    bool funded = m.totalAssets() >= nowState.totalDebts();
    _check(i, nowState.isClosed == (manualClose || old.state.isClosed || (_inRepayment(i) && funded)), 9);
    if (nowState.isClosed) {
      _check(i, nowState.annualInterestBips == 0 && !nowState.isDelinquent && nowState.timeDelinquent == 0, 10);
      _check(i, _drawnAmountIfRevolving(i) == 0, 11);
    } else {
      _check(i, nowState.timeDelinquent == p.state.timeDelinquent, 12);
    }
    _checkTransitionEvents(i, old, p, nowState, logs);
    if (p.dateReached) ++c.activations;
    if (old.defaultedAt == 0 && p.defaultedAt != 0) {
      if (p.defaultedAt == terms[i].date + terms[i].period) ++c.deadlineDefaults;
      else ++c.penaltyDefaults;
    }
    if (old.state.isDelinquent && !nowState.isDelinquent) ++c.cures;
    if (!old.state.isClosed && nowState.isClosed) {
      ++c.closures;
      if (p.defaultedAt != 0) ++c.lateClosures;
    }
    if (vm.getBlockTimestamp() > uint256(old.state.lastInterestAccruedTimestamp) + 1 days) {
      ++c.idleCrossings;
    }

    observations[i].state = nowState;
    observations[i].cash = m.totalAssets();
    observations[i].defaultedAt = p.defaultedAt;
    observations[i].cutoff = nowState.isClosed || !nowState.isDelinquent ? 0 : p.cutoff;
    observations[i].drawn = _drawnAmountIfRevolving(i);
    if (nowState.pendingWithdrawalExpiry != 0) {
      observations[i].batch = observedBatches[i][nowState.pendingWithdrawalExpiry];
    } else {
      delete observations[i].batch;
    }
  }

  function _checkTransitionEvents(
    uint256 i,
    LifecycleOracle.Observation memory old,
    LifecycleOracle.Preview memory p,
    MarketState memory nowState,
    Vm.Log[] memory logs
  )
    internal
  {
    uint256 dates;
    uint256 defaults;
    uint256 closures;
    uint256 previousTo = old.state.lastInterestAccruedTimestamp;
    for (uint256 j; j < logs.length; ++j) {
      Vm.Log memory entry = logs[j];
      if (entry.emitter != address(markets[i]) || entry.topics.length == 0) continue;
      bytes32 topic = entry.topics[0];
      if (topic == keccak256('RepaymentDateReached(uint256)')) {
        ++dates;
        _check(i, abi.decode(entry.data, (uint256)) == terms[i].date, 13);
      } else if (topic == keccak256('DefaultRecorded(uint256)')) {
        ++defaults;
        _check(i, abi.decode(entry.data, (uint256)) == p.defaultedAt, 14);
      } else if (topic == keccak256('MarketClosed(address,uint256)')) {
        ++closures;
        uint256 at = p.closedAt == 0 ? vm.getBlockTimestamp() : p.closedAt;
        _check(i, abi.decode(entry.data, (uint256)) == at, 15);
      } else if (topic == InterestAndFeesAccruedTopic) {
        uint256[6] memory fields = abi.decode(entry.data, (uint256[6]));
        _check(i, fields[0] == previousTo && fields[1] > fields[0], 16);
        previousTo = fields[1];
      }
    }
    _check(i, dates == (p.dateReached ? 1 : 0), 17);
    _check(i, defaults == (old.defaultedAt == 0 && p.defaultedAt != 0 ? 1 : 0), 18);
    _check(i, closures == (!old.state.isClosed && nowState.isClosed ? 1 : 0), 19);
    _check(i, previousTo == (p.closedAt == 0 ? vm.getBlockTimestamp() : p.closedAt), 44);
  }

  function _hasStateWrite(Vm.Log[] memory logs, address market) internal pure returns (bool) {
    for (uint256 j; j < logs.length; ++j) {
      if (
        logs[j].emitter == market && logs[j].topics.length != 0
          && logs[j].topics[0] == keccak256('StateUpdated(uint256,bool)')
      ) return true;
    }
    return false;
  }

  function _firstWord(bytes memory data) internal pure returns (uint256 word) {
    assembly ('memory-safe') {
      word := mload(add(data, 0x24))
    }
  }

  function _inRepayment(uint256 i) internal view returns (bool) {
    return terms[i].date != 0 && vm.getBlockTimestamp() >= terms[i].date;
  }

  function _withdrawalsOpen(uint256 i) internal view override returns (bool) {
    return _inRepayment(i) || super._withdrawalsOpen(i);
  }

  function _checkDrawnUnchanged(uint256 i, uint256 beforeDrawn) internal override {
    if (revolving[i] && _drawnAmount(i) != (markets[i].previousState().isClosed ? 0 : beforeDrawn)) {
      drawnAmountFailures++;
    }
  }

  function _expectedUpdatedRevolvingState(
    uint256 i,
    MarketState memory,
    uint256 cash
  )
    internal
    view
    override
    returns (MarketState memory)
  {
    return _preview(i, cash).state;
  }

  function _expectedDrawnAfterRepay(
    uint256 i,
    MarketState memory s,
    uint256 cash,
    uint256 amount
  )
    internal
    view
    override
    returns (uint256)
  {
    if (s.isClosed || (_inRepayment(i) && cash + amount >= s.totalDebts())) return 0;
    return super._expectedDrawnAfterRepay(i, s, cash, amount);
  }

  // paying old batches can lower totalDebts by a rounding unit after _onRepay runs. if that
  // finishes funding, automatic closure settles the remaining principal too. closure/backing
  // and every batch liability are checked separately; don't leave phantom principal here.
  function _finalRepaymentDrawn(uint256 i, uint256 expected) internal view override returns (uint256) {
    return markets[i].previousState().isClosed ? 0 : expected;
  }

  function _getRawPendingBatch(
    uint256 i,
    MarketState memory,
    uint32
  )
    internal
    view
    override
    returns (WithdrawalBatch memory)
  {
    return observations[i].batch;
  }

  function _recoverSurplusAfterDrain(uint256 i) internal override returns (bool) {
    uint256 failuresBefore = lifecycleFailures;
    recoverSurplus(i);
    return lifecycleFailures == failuresBefore;
  }

  /// @dev no manual close to rescue this campaign. reach the date, fully back the debt, and
  ///      process exactly one old batch per call before the shared drain collects every claim.
  function _closeCell(uint256 i) internal override returns (bool) {
    if (terms[i].date == 0) return super._closeCell(i);
    if (vm.getBlockTimestamp() < terms[i].date) vm.warp(terms[i].date);
    WildcatMarket m = markets[i];
    uint256 amount = m.totalDebts().satSub(m.totalAssets());
    if (amount != 0) _fundBorrower(i, amount);
    (bool success,) = _callAs(
      i,
      _borrower(),
      address(m),
      amount == 0 ? abi.encodeCall(WildcatMarket.updateState, ()) : abi.encodeCall(WildcatMarket.repay, (amount))
    );
    if (!success) return false;
    if (!m.previousState().isClosed) {
      // totalDebts() includes a simulated pending payment. repayment can allocate in one
      // payment instead of two, leaving a one-unit rounding shortfall against that quote.
      // allow exactly that bound, then require closure; don't paper over a larger deficit.
      if (m.previousState().totalDebts() != m.totalAssets() + 1) return false;
      _fundBorrower(i, 1);
      (success,) = _callAs(i, _borrower(), address(m), abi.encodeCall(WildcatMarket.repay, (1)));
      if (!success || !m.previousState().isClosed) return false;
    }
    uint256 length = m.getUnpaidBatchExpiries().length;
    for (uint256 j; j < length; ++j) {
      (success,) = _callAs(
        i,
        _borrower(),
        address(m),
        abi.encodeCall(WildcatMarketWithdrawals.repayAndProcessUnpaidWithdrawalBatches, (0, 1))
      );
      if (!success || m.getUnpaidBatchExpiries().length != length - j - 1) return false;
    }
    return true;
  }
}
