// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { Test as ForgeTest } from 'forge-std/Test.sol';

import { WildcatMarket } from 'src/market/WildcatMarket.sol';

import '../BaseMarketTest.sol';

contract WithdrawalBatchIdentityHandler is ForgeTest {
  WildcatMarket public immutable market;
  address public immutable lender;
  uint32 public immutable historicalExpiry;

  bool public queued;
  uint32 public queuedExpiry;

  constructor(WildcatMarket market_, address lender_, uint32 historicalExpiry_) {
    market = market_;
    lender = lender_;
    historicalExpiry = historicalExpiry_;
  }

  function queueFullWithdrawalAtHistoricalExpiry() external {
    if (queued || market.scaledBalanceOf(lender) == 0) return;

    vm.warp(historicalExpiry);
    vm.prank(lender);
    queuedExpiry = market.queueFullWithdrawal();
    queued = true;
  }
}

contract WithdrawalBatchIdentityInvariant is BaseMarketTest {
  WithdrawalBatchIdentityHandler internal handler;
  uint32 internal historicalExpiry;
  bytes32 internal historicalBatchHash;
  bytes32 internal historicalStatusHash;

  function setUp() public override {
    super.setUp();

    _deposit(alice, 1e18);
    _deposit(bob, 1e18);
    historicalExpiry = _requestWithdrawal(alice, 1e18);

    fastForward(parameters.withdrawalBatchDuration - 1 hours);
    _closeMarket();
    market.executeWithdrawal(alice, historicalExpiry);

    historicalBatchHash = keccak256(abi.encode(market.getWithdrawalBatch(historicalExpiry)));
    historicalStatusHash = keccak256(
      abi.encode(market.getAccountWithdrawalStatus(alice, historicalExpiry))
    );

    handler = new WithdrawalBatchIdentityHandler(market, bob, historicalExpiry);

    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = WithdrawalBatchIdentityHandler
      .queueFullWithdrawalAtHistoricalExpiry
      .selector;
    targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    targetContract(address(handler));
  }

  function invariant_historicalWithdrawalBatchIsImmutable() public view {
    assertEq(
      keccak256(abi.encode(market.getWithdrawalBatch(historicalExpiry))),
      historicalBatchHash,
      'historical batch mutated'
    );
    assertEq(
      keccak256(abi.encode(market.getAccountWithdrawalStatus(alice, historicalExpiry))),
      historicalStatusHash,
      'historical lender status mutated'
    );
  }

  function invariant_newWithdrawalBatchUsesFreshKey() public view {
    if (!handler.queued()) return;

    assertEq(handler.queuedExpiry(), historicalExpiry + 1, 'new batch reused historical key');
    assertEq(
      market.previousState().pendingWithdrawalExpiry,
      historicalExpiry + 1,
      'pending batch key'
    );
  }
}
