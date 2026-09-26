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
  }

  LifecycleOracle.Terms[] internal terms;
  LifecycleOracle.Observation[] internal observations;
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

  function _preview(
    uint256 i,
    uint256 cash
  ) internal view returns (LifecycleOracle.Preview memory) {
    return referenceModel.preview(observations[i], terms[i], vm.getBlockTimestamp(), cash);
  }

  function expectedDefault(uint256 i) external view returns (uint256) {
    return _preview(i, markets[i].totalAssets()).defaultedAt;
  }

  function penaltyCutoff(uint256 i) external view returns (uint256) {
    return _preview(i, markets[i].totalAssets()).cutoff;
  }

  function viewsMatchOracle() external view returns (bool) {
    for (uint256 i; i < markets.length; ++i) {
      WildcatMarket m = markets[i];
      LifecycleOracle.Preview memory p = _preview(i, m.totalAssets());
      if (keccak256(abi.encode(p.state)) != keccak256(abi.encode(m.currentState()))) return false;
      if (m.defaultedAt() != observations[i].defaultedAt) return false;
      if (m.repaymentDate() != terms[i].date || m.repaymentPeriod() != terms[i].period)
        return false;
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
      _check(
        i,
        keccak256(abi.encode(markets[i].previousState())) == keccak256(abi.encode(old.state)),
        1
      );
      _check(i, markets[i].defaultedAt() == old.defaultedAt, 2);
      return;
    }
    if (!_hasStateWrite(logs, address(markets[i]))) return;
    uint256 cash = record.beforeCall.marketAssets;
    bytes4 selector = _selector(record.data);
    if (
      selector == WildcatMarket.repay.selector ||
      selector == WildcatMarketWithdrawals.repayAndProcessUnpaidWithdrawalBatches.selector
    ) cash += _firstWord(record.data);
    LifecycleOracle.Preview memory p = _preview(i, cash);
    _recordLifecycle(i, old, p, logs);
  }

  function _recordLifecycle(
    uint256 i,
    LifecycleOracle.Observation memory old,
    LifecycleOracle.Preview memory p,
    Vm.Log[] memory logs
  ) internal {
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
    _check(i, nowState.isClosed == (old.state.isClosed || (_inRepayment(i) && funded)), 9);
    if (nowState.isClosed) {
      _check(
        i,
        nowState.annualInterestBips == 0 && !nowState.isDelinquent && nowState.timeDelinquent == 0,
        10
      );
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
    if (vm.getBlockTimestamp() > uint256(old.state.lastInterestAccruedTimestamp) + 1 days)
      ++c.idleCrossings;

    observations[i].state = nowState;
    observations[i].cash = m.totalAssets();
    observations[i].defaultedAt = p.defaultedAt;
    observations[i].cutoff = nowState.isClosed || !nowState.isDelinquent ? 0 : p.cutoff;
    observations[i].drawn = _drawnAmountIfRevolving(i);
    if (nowState.pendingWithdrawalExpiry != 0) {
      observations[i].batch = m.getWithdrawalBatch(nowState.pendingWithdrawalExpiry);
      WithdrawalBatch memory b = observations[i].batch;
      if (b.scaledAmountBurned != 0 && b.scaledAmountBurned < b.scaledTotalAmount)
        ++c.partialBatches;
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
  ) internal {
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
  }

  function _hasStateWrite(Vm.Log[] memory logs, address market) internal pure returns (bool) {
    for (uint256 j; j < logs.length; ++j) {
      if (
        logs[j].emitter == market &&
        logs[j].topics.length != 0 &&
        logs[j].topics[0] == keccak256('StateUpdated(uint256,bool)')
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
    if (
      revolving[i] && _drawnAmount(i) != (markets[i].previousState().isClosed ? 0 : beforeDrawn)
    ) {
      drawnAmountFailures++;
    }
  }

  function _expectedUpdatedRevolvingState(
    uint256 i,
    MarketState memory,
    uint256 cash
  ) internal view override returns (MarketState memory) {
    return _preview(i, cash).state;
  }

  function _expectedDrawnAfterRepay(
    uint256 i,
    MarketState memory s,
    uint256 cash,
    uint256 amount
  ) internal view override returns (uint256) {
    if (s.isClosed || (_inRepayment(i) && cash + amount >= s.totalDebts())) return 0;
    return super._expectedDrawnAfterRepay(i, s, cash, amount);
  }

  function _getRawPendingBatch(
    uint256 i,
    MarketState memory,
    uint32
  ) internal view override returns (WithdrawalBatch memory) {
    return observations[i].batch;
  }

  /// @dev no manual close to rescue this campaign. reach the date, fully back the debt, and
  ///      process exactly one old batch per call before the shared drain collects every claim.
  function _closeCell(uint256 i) internal override returns (bool) {
    if (terms[i].date == 0) return super._closeCell(i);
    if (vm.getBlockTimestamp() < terms[i].date) vm.warp(terms[i].date);
    WildcatMarket m = markets[i];
    uint256 amount = m.totalDebts().satSub(m.totalAssets());
    if (amount != 0) _fundBorrower(i, amount);
    (bool success, ) = _callAs(
      i,
      _borrower(),
      address(m),
      amount == 0
        ? abi.encodeCall(WildcatMarket.updateState, ())
        : abi.encodeCall(WildcatMarket.repay, (amount))
    );
    if (!success || !m.previousState().isClosed) return false;
    uint256 length = m.getUnpaidBatchExpiries().length;
    for (uint256 j; j < length; ++j) {
      (success, ) = _callAs(
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
