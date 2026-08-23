// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { HooksInstanceKind } from 'src/lens/HooksConfigData.sol';
import { LenderAccountData } from 'src/lens/LenderAccountData.sol';
import { LenderAccountQuery, LenderAccountQueryResult } from 'src/lens/MarketData.sol';
import { MarketData, MarketDataLib, MarketDataV2_5 } from 'src/lens/MarketData.sol';
import { MarketDataWithLenderStatus } from 'src/lens/MarketData.sol';
import { MarketLiveDataV2_5 } from 'src/lens/MarketLiveData.sol';
import { MarketLiveDataWithLenderStatusV2_5 } from 'src/lens/MarketLiveData.sol';
import { MarketLensCore } from 'src/lens/MarketLensCore.sol';
import { MarketLensLive } from 'src/lens/MarketLensLive.sol';
import { TokenMetadata } from 'src/lens/TokenData.sol';
import { BatchStatus, WithdrawalBatchData } from 'src/lens/WithdrawalBatchData.sol';
import { WithdrawalBatchDataWithLenderStatus } from 'src/lens/WithdrawalBatchData.sol';
import { WithdrawalBatchLenderStatus } from 'src/lens/WithdrawalBatchData.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

contract MarketLensCoreTest is MarketFixture {
  using MarketDataLib for MarketData;

  address internal constant Lender = address(0x1EAD);
  address internal constant SecondLender = address(0xB0B);
  address internal constant NewBorrower = address(0xCAFE);

  Fixture internal fixture;
  MarketLensCore internal core;
  MarketLensLive internal live;

  function setUp() external {
    fixture = _newMarket(HooksKind.OpenTerm);
    core = MarketLensCore(
      _deployCode(
        'src/lens/MarketLensCore.sol:MarketLensCore',
        abi.encode(address(fixture.archController), address(fixture.factory))
      )
    );
    live = MarketLensLive(
      _deployCode(
        'src/lens/MarketLensLive.sol:MarketLensLive',
        abi.encode(address(fixture.archController), address(fixture.factory))
      )
    );
  }

  function test_tokenAndMarketReads_MapCanonicalStateAndBatchEndpoints() external {
    _deposit(fixture, Lender, 100e18);
    vm.prank(Borrower);
    fixture.market.borrow(40e18);

    TokenMetadata memory asset = core.getTokenInfo(address(fixture.asset));
    assertEq(asset.token, address(fixture.asset), 'asset');
    assertEq(asset.name, 'Token', 'asset name');
    assertEq(asset.symbol, 'TKN', 'asset symbol');
    assertEq(asset.decimals, 18, 'asset decimals');

    address[] memory tokens = new address[](2);
    tokens[0] = address(fixture.asset);
    tokens[1] = address(fixture.market);
    TokenMetadata[] memory tokenData = core.getTokensInfo(tokens);
    assertEq(tokenData.length, 2, 'token count');
    assertEq(tokenData[1].token, address(fixture.market), 'market token');
    assertEq(tokenData[1].name, 'Wildcat Token', 'market name');
    assertEq(tokenData[1].symbol, 'WCTKN', 'market symbol');

    MarketData memory data = core.getMarketData(address(fixture.market));
    MarketState memory state = fixture.market.currentState();
    assertEq(data.marketToken.token, address(fixture.market), 'market');
    assertEq(data.underlyingToken.token, address(fixture.asset), 'underlying');
    assertEq(data.hooksFactory, address(fixture.factory), 'factory');
    assertEq(data.borrower, Borrower, 'borrower');
    assertEq(data.hooksConfig.hooksAddress, address(fixture.hooks), 'hooks');
    assertEq(uint256(data.hooksConfig.kind), uint256(HooksInstanceKind.OpenTerm), 'kind');
    assertEq(data.hooks.administrator, Borrower, 'administrator');
    assertEq(data.hooks.hooksTemplate.hooksTemplate, address(0x7E4), 'template');
    assertEq(data.hooks.totalMarkets, 1, 'hooks markets');
    assertEq(data.totalSupply, state.totalSupply(), 'supply');
    assertEq(data.totalAssets, fixture.market.totalAssets(), 'assets');
    assertEq(data.scaleFactor, state.scaleFactor, 'scale factor');
    assertEq(data.coverageLiquidity, state.liquidityRequired(), 'coverage');

    address[] memory markets = new address[](1);
    markets[0] = address(fixture.market);
    assertEq(abi.encode(core.getMarketsData(markets)[0]), abi.encode(data), 'market list parity');
    MarketDataV2_5 memory v2 = core.getMarketDataV2(address(fixture.market));
    assertEq(v2.borrowerPrincipal, Borrower, 'principal');
    assertEq(v2.borrowerIdentityRegistry, address(fixture.registry), 'registry');
    assertFalse(v2.commitmentFeeBips.isPresent, 'standard commitment fee');
    assertFalse(v2.drawnAmount.isPresent, 'standard drawn amount');
    assertEq(abi.encode(core.getMarketsDataV2(markets)[0]), abi.encode(v2), 'v2 list parity');

    uint32[] memory noExpiries = new uint32[](0);
    LenderAccountQuery memory query = LenderAccountQuery(
      Lender,
      address(fixture.market),
      noExpiries
    );
    LenderAccountQueryResult memory result = core.queryLenderAccount(query);
    assertEq(abi.encode(result.market), abi.encode(data), 'query market');
    assertEq(result.withdrawalBatches.length, 0, 'query batches');
    LenderAccountQuery[] memory queries = new LenderAccountQuery[](1);
    queries[0] = query;
    assertEq(
      abi.encode(core.queryLenderAccounts(queries)[0]),
      abi.encode(result),
      'query list parity'
    );
  }

  function test_v2AndLiveReads_TrackRevolvingFieldsAndBorrowerIdentity() external {
    Fixture memory revolving = _newRevolvingMarket(HooksKind.OpenTerm);
    _deposit(revolving, Lender, 100e18);
    vm.prank(Borrower);
    revolving.market.borrow(25e18);

    address[] memory markets = new address[](2);
    markets[0] = address(fixture.market);
    markets[1] = address(revolving.market);
    MarketDataV2_5[] memory full = core.getMarketsDataV2(markets);
    MarketLiveDataV2_5[] memory current = live.getMarketsLiveDataV2(markets);

    assertFalse(full[0].commitmentFeeBips.isPresent, 'standard fee absent');
    assertFalse(full[0].drawnAmount.isPresent, 'standard draw absent');
    assertTrue(full[1].commitmentFeeBips.isPresent, 'revolving fee present');
    assertEq(full[1].commitmentFeeBips.value, 500, 'revolving fee');
    assertTrue(full[1].drawnAmount.isPresent, 'revolving draw present');
    assertEq(full[1].drawnAmount.value, 25e18, 'revolving draw');
    assertEq(current[1].commitmentFeeBips.value, 500, 'live fee');
    assertEq(current[1].drawnAmount.value, 25e18, 'live draw');
    _assertLiveParity(full[0].market, current[0]);
    _assertLiveParity(full[1].market, current[1]);

    fixture.archController.registerBorrower(NewBorrower);
    vm.prank(Borrower);
    fixture.market.requestBorrowerTransfer(NewBorrower);
    MarketDataV2_5 memory pending = core.getMarketDataV2(address(fixture.market));
    assertEq(pending.pendingBorrower, NewBorrower, 'pending borrower');
    assertEq(pending.pendingBorrowerPrincipal, NewBorrower, 'pending principal');
    assertEq(pending.market.borrower, Borrower, 'current borrower');
    assertEq(pending.market.hooks.administrator, Borrower, 'hooks administrator');

    vm.prank(NewBorrower);
    fixture.market.acceptBorrowerTransfer();
    MarketDataV2_5 memory accepted = core.getMarketDataV2(address(fixture.market));
    assertEq(accepted.market.borrower, NewBorrower, 'accepted borrower');
    assertEq(accepted.borrowerPrincipal, NewBorrower, 'accepted principal');
    assertEq(accepted.pendingBorrower, address(0), 'cleared pending borrower');
    assertEq(accepted.market.hooks.administrator, Borrower, 'hooks remain administered');
  }

  function test_periodicMarketRead_MapsTermConfigurationAndClosure() external {
    Fixture memory periodic = _newPeriodicMarketForLens();
    MarketData memory data = core.getMarketData(address(periodic.market));

    assertEq(uint256(data.hooksConfig.kind), uint256(HooksInstanceKind.PeriodicTerm), 'kind');
    assertTrue(
      data.hooksConfig.firstWithdrawalWindowStart > vm.getBlockTimestamp(),
      'first window'
    );
    assertEq(data.hooksConfig.periodDuration, 7 days, 'period');
    assertEq(data.hooksConfig.withdrawalWindowDuration, 2 days, 'window');
    assertFalse(data.hooksConfig.periodicTermClosed, 'term open');

    vm.prank(Borrower);
    periodic.market.closeMarket();
    data = core.getMarketData(address(periodic.market));
    assertTrue(data.hooksConfig.periodicTermClosed, 'term closed');
  }

  function _newPeriodicMarketForLens() internal returns (Fixture memory periodic) {
    IHooks hooks = IHooks(
      _deployCode(
        'src/access/PeriodicTermHooks.sol:PeriodicTermHooks',
        abi.encode(Borrower, bytes(''))
      )
    );
    uint32 periodDuration = 7 days;
    uint32 withdrawalWindowDuration = 2 days;
    uint32 firstWithdrawalWindowStart = uint32(
      vm.getBlockTimestamp() + periodDuration - withdrawalWindowDuration
    );
    periodic = _newMarket(
      _defaultOptions(HooksKind.OpenTerm),
      hooks,
      abi.encode(
        firstWithdrawalWindowStart,
        periodDuration,
        withdrawalWindowDuration,
        uint128(0),
        false
      )
    );
  }

  function test_lenderAccountReads_MapBalancesApprovalAndDepositBlock() external {
    _fundAndApprove(fixture, Lender, 10e18);
    vm.prank(Lender);
    fixture.market.deposit(4e18);

    LenderAccountData memory account = core.getLenderAccountData(Lender, address(fixture.market));
    _assertLenderAccount(account, Lender);
    assertEq(account.underlyingBalance, 6e18, 'underlying balance');
    assertEq(account.underlyingApproval, 6e18, 'approval');
    assertFalse(account.isBlockedFromDeposits, 'not blocked');

    vm.prank(Borrower);
    OpenTermHooks(address(fixture.hooks)).blockFromDeposits(Lender);
    account = core.getLenderAccountData(Lender, address(fixture.market));
    assertTrue(account.isBlockedFromDeposits, 'blocked');
    assertEq(account.lastProvider.providerAddress, address(0), 'no provider');

    address[] memory markets = new address[](1);
    markets[0] = address(fixture.market);
    assertEq(
      abi.encode(core.getLenderAccountData(Lender, markets)[0]),
      abi.encode(account),
      'account by markets'
    );
    address[] memory lenders = new address[](2);
    lenders[0] = Lender;
    lenders[1] = SecondLender;
    LenderAccountData[] memory accounts = core.getLenderAccountsData(
      address(fixture.market),
      lenders
    );
    assertEq(accounts.length, 2, 'account count');
    _assertLenderAccount(accounts[0], Lender);
    _assertLenderAccount(accounts[1], SecondLender);

    MarketDataWithLenderStatus memory marketAccount = core.getMarketDataWithLenderStatus(
      Lender,
      address(fixture.market)
    );
    assertEq(abi.encode(marketAccount.lenderStatus), abi.encode(account), 'market account');
    assertEq(
      abi.encode(core.getMarketsDataWithLenderStatus(Lender, markets)[0]),
      abi.encode(marketAccount),
      'market account list'
    );

    MarketLiveDataWithLenderStatusV2_5[] memory liveAccounts = live
      .getMarketsLiveDataWithLenderStatusV2(Lender, markets);
    assertEq(abi.encode(liveAccounts[0].lenderStatus), abi.encode(account), 'live account');
  }

  function test_withdrawalReads_MapPendingExpiredUnpaidCompleteAndUnknown() external {
    _deposit(fixture, Lender, 100e18);
    vm.prank(Borrower);
    fixture.market.borrow(80e18);
    uint256 queuedAmount = fixture.market.scaledBalanceOf(Lender);
    vm.prank(Lender);
    uint32 expiry = fixture.market.queueFullWithdrawal();

    WithdrawalBatchData memory batch = core.getWithdrawalBatchData(address(fixture.market), expiry);
    assertEq(uint256(batch.status), uint256(BatchStatus.Pending), 'pending');
    assertEq(batch.scaledTotalAmount, queuedAmount, 'queued amount');

    uint32[] memory expiries = new uint32[](1);
    expiries[0] = expiry;
    assertEq(
      abi.encode(core.getWithdrawalBatchesData(address(fixture.market), expiries)[0]),
      abi.encode(batch),
      'batch list'
    );
    WithdrawalBatchDataWithLenderStatus memory lenderBatch = core
      .getWithdrawalBatchDataWithLenderStatus(address(fixture.market), expiry, Lender);
    assertEq(lenderBatch.lenderStatus.lender, Lender, 'lender');
    assertEq(lenderBatch.lenderStatus.scaledAmount, batch.scaledTotalAmount, 'lender amount');
    assertEq(
      abi.encode(
        core.getWithdrawalBatchesDataWithLenderStatus(address(fixture.market), expiries, Lender)[0]
      ),
      abi.encode(lenderBatch),
      'lender batch list'
    );

    address[] memory lenders = new address[](2);
    lenders[0] = Lender;
    lenders[1] = SecondLender;
    (WithdrawalBatchData memory sharedBatch, WithdrawalBatchLenderStatus[] memory statuses) = core
      .getWithdrawalBatchDataWithLendersStatus(address(fixture.market), expiry, lenders);
    assertEq(abi.encode(sharedBatch), abi.encode(batch), 'shared batch');
    assertEq(statuses.length, 2, 'status count');
    assertEq(statuses[0].scaledAmount, batch.scaledTotalAmount, 'first status');
    assertEq(statuses[1].scaledAmount, 0, 'second status');

    vm.warp(uint256(expiry) + 1);
    batch = core.getWithdrawalBatchData(address(fixture.market), expiry);
    assertEq(uint256(batch.status), uint256(BatchStatus.Expired), 'expired');
    fixture.market.updateState();
    batch = core.getWithdrawalBatchData(address(fixture.market), expiry);
    assertEq(uint256(batch.status), uint256(BatchStatus.Unpaid), 'unpaid');

    fixture.asset.mint(address(fixture.market), 100e18);
    fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
    batch = core.getWithdrawalBatchData(address(fixture.market), expiry);
    assertEq(uint256(batch.status), uint256(BatchStatus.Complete), 'complete');

    WithdrawalBatchDataWithLenderStatus memory unknown = core
      .getWithdrawalBatchDataWithLenderStatus(
        address(fixture.market),
        type(uint32).max,
        SecondLender
      );
    assertEq(uint256(unknown.batch.status), uint256(BatchStatus.Complete), 'unknown status');
    assertEq(unknown.lenderStatus.lender, SecondLender, 'unknown lender');
    assertEq(unknown.lenderStatus.scaledAmount, 0, 'unknown amount');

    MarketData memory data = core.getMarketData(address(fixture.market));
    WithdrawalBatchData[] memory outstanding = data.getUnpaidAndPendingWithdrawalBatches();
    assertEq(outstanding.length, 0, 'no outstanding batches');
  }

  function _assertLenderAccount(LenderAccountData memory account, address lender) internal view {
    assertEq(account.lender, lender, 'lender address');
    assertEq(account.scaledBalance, fixture.market.scaledBalanceOf(lender), 'scaled balance');
    assertEq(account.normalizedBalance, fixture.market.balanceOf(lender), 'normalized balance');
    assertEq(account.underlyingBalance, fixture.asset.balanceOf(lender), 'underlying balance');
    assertEq(
      account.underlyingApproval,
      fixture.asset.allowance(lender, address(fixture.market)),
      'underlying approval'
    );
  }

  function _assertLiveParity(
    MarketData memory full,
    MarketLiveDataV2_5 memory current
  ) internal pure {
    assertEq(current.market, full.marketToken.token, 'live market');
    assertEq(current.isClosed, full.isClosed, 'live closed');
    assertEq(current.protocolFeeBips, full.protocolFeeBips, 'live protocol fee');
    assertEq(current.reserveRatioBips, full.reserveRatioBips, 'live reserve ratio');
    assertEq(current.annualInterestBips, full.annualInterestBips, 'live apr');
    assertEq(current.scaleFactor, full.scaleFactor, 'live scale factor');
    assertEq(current.totalSupply, full.totalSupply, 'live supply');
    assertEq(current.totalAssets, full.totalAssets, 'live assets');
    assertEq(current.scaledPendingWithdrawals, full.scaledPendingWithdrawals, 'live pending');
    assertEq(current.pendingWithdrawalExpiry, full.pendingWithdrawalExpiry, 'live expiry');
    assertEq(current.timeDelinquent, full.timeDelinquent, 'live delinquency');
    assertEq(current.coverageLiquidity, full.coverageLiquidity, 'live coverage');
  }
}
