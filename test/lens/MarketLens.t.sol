// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../BaseMarketTest.sol';
import 'src/interfaces/IMarketEventsAndErrors.sol';
import 'src/libraries/MathUtils.sol';
import 'src/libraries/SafeCastLib.sol';
import 'src/libraries/MarketState.sol';
import 'src/libraries/LibERC20.sol';
import 'src/lens/interfaces/IMarketLensCore.sol';
import 'src/lens/interfaces/IMarketLensLive.sol';
import 'solady/utils/LibPRNG.sol';
import 'src/lens/MarketData.sol';
import 'src/lens/MarketLiveData.sol';
import 'src/lens/MarketLensAggregator.sol';
import 'src/lens/MarketLensCore.sol';
import 'src/lens/MarketLensLive.sol';
import '../helpers/fuzz/MarketConfigFuzzInputs.sol';
import 'src/lens/MarketLens.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { AccessListRoleProvider } from 'src/providers/AccessListRoleProvider.sol';
import 'src/IHooksFactory.sol';
import 'src/interfaces/IBorrowerIdentityRegistry.sol';

enum FuzzConditions {
  Default,
  DepositOnly,
  DepositBorrow,
  DepositBorrowWithdraw
}

struct PeriodicTermLensFixture {
  WildcatMarket market;
  PeriodicTermHooks hooks;
  address template;
  uint32 firstWithdrawalWindowStart;
  uint32 periodDuration;
  uint32 withdrawalWindowDuration;
  uint128 minimumDeposit;
  bool transfersDisabled;
}

contract MockV1MarketLike {
  address public immutable asset;
  string public constant name = 'Wildcat V1';
  string public constant symbol = 'WCV1';
  uint8 public constant decimals = 18;

  constructor(address asset_) {
    asset = asset_;
  }

  function version() external pure returns (string memory) {
    return '1.0.0';
  }
}

contract HooksInstanceDataHarness {
  function fill(
    address hooksAddress,
    IHooksFactory factory
  ) external view returns (HooksInstanceData memory data) {
    data.fill(hooksAddress, factory);
  }
}

contract MarketLensBorrowerAccount {}

contract MarketLensBorrowerAccountFactory {
  IBorrowerIdentityRegistry public immutable registry;

  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  function deployAccount(address principal) external returns (address account) {
    account = address(new MarketLensBorrowerAccount());
    registry.registerBorrowerAccount(account, principal);
  }
}

contract MarketDataTest is BaseMarketTest {
  using stdStorage for StdStorage;
  using MathUtils for int256;
  using MathUtils for uint256;
  using SafeCastLib for uint256;
  using LibPRNG for LibPRNG.PRNG;

  MarketLens internal lens;
  MarketLensCore internal lensCore;
  MarketLensAggregator internal lensAggregator;
  MarketLensLive internal lensLive;
  MockERC20 originationFeeAsset = new MockERC20('Origination Fee Asset', 'OFA', 18);

  function setUp() public override {
    super.setUp();

    lensCore = new MarketLensCore(address(archController), address(hooksFactory));
    lensAggregator = new MarketLensAggregator(address(archController), address(hooksFactory));
    lensLive = new MarketLensLive(address(archController), address(hooksFactory));
    lens = new MarketLens(
      address(archController),
      address(hooksFactory),
      address(lensCore),
      address(lensAggregator),
      address(lensLive)
    );
    originationFeeAsset.mint(address(this), 1e18);
    originationFeeAsset.approve(address(hooksFactory), 1e18);
  }

  function test_constructorStoresFacadeHelpers() external view {
    assertEq(address(lens.archController()), address(archController), 'archController');
    assertEq(address(lens.hooksFactory()), address(hooksFactory), 'hooksFactory');
    assertEq(address(lens.coreHelper()), address(lensCore), 'coreHelper');
    assertEq(address(lens.aggregationHelper()), address(lensAggregator), 'aggregationHelper');
    assertEq(address(lens.liveHelper()), address(lensLive), 'liveHelper');
  }

  function test_getMarketData_bubblesNotV2MarketRevert() external {
    MockV1MarketLike v1Market = new MockV1MarketLike(address(asset));

    vm.expectRevert(MarketLens.NotV2Market.selector);
    lens.getMarketData(address(v1Market));
  }

  /// Every function in the aggregator section of the facade must forward to
  /// the aggregation helper with an exact selector match. Calls each endpoint
  /// on the facade and on the helper directly and requires identical results,
  /// so a mis-routed stub or signature drift fails here rather than in prod.
  function test_aggregatorDelegation_facadeParityForAllEndpoints() external {
    address factory_ = address(hooksFactory);
    address template_ = hooksTemplate;
    address[] memory templates = new address[](1);
    templates[0] = template_;

    bytes[] memory calls = new bytes[](27);
    calls[0] = abi.encodeWithSignature('getHooksDataForBorrower(address)', borrower);
    calls[1] = abi.encodeWithSignature(
      'getHooksDataForBorrower(address,address)',
      factory_,
      borrower
    );
    calls[2] = abi.encodeWithSignature('getHooksInstancesForBorrower(address)', borrower);
    calls[3] = abi.encodeWithSignature(
      'getHooksInstancesForBorrower(address,address)',
      factory_,
      borrower
    );
    calls[4] = abi.encodeWithSignature(
      'getHooksTemplateForBorrower(address,address)',
      borrower,
      template_
    );
    calls[5] = abi.encodeWithSignature(
      'getHooksTemplateForBorrower(address,address,address)',
      factory_,
      borrower,
      template_
    );
    calls[6] = abi.encodeWithSignature(
      'getHooksTemplatesForBorrower(address,address[])',
      borrower,
      templates
    );
    calls[7] = abi.encodeWithSignature(
      'getHooksTemplatesForBorrower(address,address,address[])',
      factory_,
      borrower,
      templates
    );
    calls[8] = abi.encodeWithSignature('getAllHooksTemplatesForBorrower(address)', borrower);
    calls[9] = abi.encodeWithSignature(
      'getAllHooksTemplatesForBorrower(address,address)',
      factory_,
      borrower
    );
    calls[10] = abi.encodeWithSignature('getMarketsForHooksTemplateCount(address)', template_);
    calls[11] = abi.encodeWithSignature(
      'getMarketsForHooksTemplateCount(address,address)',
      factory_,
      template_
    );
    calls[12] = abi.encodeWithSignature(
      'getPaginatedMarketsDataForHooksTemplate(address,uint256,uint256)',
      template_,
      0,
      10
    );
    calls[13] = abi.encodeWithSignature(
      'getPaginatedMarketsDataForHooksTemplate(address,address,uint256,uint256)',
      factory_,
      template_,
      0,
      10
    );
    calls[14] = abi.encodeWithSignature(
      'getPaginatedMarketsDataV2ForHooksTemplate(address,uint256,uint256)',
      template_,
      0,
      10
    );
    calls[15] = abi.encodeWithSignature(
      'getPaginatedMarketsDataV2ForHooksTemplate(address,address,uint256,uint256)',
      factory_,
      template_,
      0,
      10
    );
    calls[16] = abi.encodeWithSignature('getAllMarketsDataForHooksTemplate(address)', template_);
    calls[17] = abi.encodeWithSignature(
      'getAllMarketsDataForHooksTemplate(address,address)',
      factory_,
      template_
    );
    calls[18] = abi.encodeWithSignature('getAllMarketsDataV2ForHooksTemplate(address)', template_);
    calls[19] = abi.encodeWithSignature(
      'getAllMarketsDataV2ForHooksTemplate(address,address)',
      factory_,
      template_
    );
    calls[20] = abi.encodeWithSignature('getAggregatedHooksDataForBorrower(address)', borrower);
    calls[21] = abi.encodeWithSignature(
      'getAggregatedHooksInstancesForBorrower(address)',
      borrower
    );
    calls[22] = abi.encodeWithSignature(
      'getAggregatedAllHooksTemplatesForBorrower(address)',
      borrower
    );
    calls[23] = abi.encodeWithSignature(
      'getAggregatedHooksTemplatesForBorrowerWithFactory(address)',
      borrower
    );
    calls[24] = abi.encodeWithSignature(
      'getAggregatedMarketsForHooksTemplateCount(address)',
      template_
    );
    calls[25] = abi.encodeWithSignature(
      'getAggregatedAllMarketsDataForHooksTemplate(address)',
      template_
    );
    calls[26] = abi.encodeWithSignature(
      'getAggregatedAllMarketsDataV2ForHooksTemplate(address)',
      template_
    );

    for (uint256 i; i < calls.length; i++) {
      (bool facadeOk, bytes memory facadeResult) = address(lens).staticcall(calls[i]);
      (bool helperOk, bytes memory helperResult) = address(lensAggregator).staticcall(calls[i]);
      assertTrue(facadeOk, string.concat('facade call failed: ', vm.toString(i)));
      assertTrue(helperOk, string.concat('helper call failed: ', vm.toString(i)));
      assertEq(
        keccak256(facadeResult),
        keccak256(helperResult),
        string.concat('facade/helper mismatch: ', vm.toString(i))
      );
    }
  }

  function test_coreDelegation_forTokenAndMarketReads() external {
    address[] memory singleToken = new address[](1);
    singleToken[0] = address(asset);
    address[] memory singleMarket = new address[](1);
    singleMarket[0] = address(market);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(IMarketLensCore.getTokenInfo.selector, address(asset))
    );
    lens.getTokenInfo(address(asset));

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(IMarketLensCore.getTokensInfo.selector, singleToken)
    );
    lens.getTokensInfo(singleToken);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(IMarketLensCore.getMarketData.selector, address(market))
    );
    lens.getMarketData(address(market));

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(IMarketLensCore.getMarketsData.selector, singleMarket)
    );
    lens.getMarketsData(singleMarket);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(IMarketLensCore.getMarketDataV2.selector, address(market))
    );
    lens.getMarketDataV2(address(market));

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(IMarketLensCore.getMarketsDataV2.selector, singleMarket)
    );
    lens.getMarketsDataV2(singleMarket);
  }

  function test_liveDelegation_forMarketReads() external {
    address[] memory singleMarket = new address[](1);
    singleMarket[0] = address(market);

    vm.expectCall(
      address(lensLive),
      abi.encodeWithSelector(IMarketLensLive.getMarketsLiveDataV2.selector, singleMarket)
    );
    lens.getMarketsLiveDataV2(singleMarket);

    vm.expectCall(
      address(lensLive),
      abi.encodeWithSelector(
        IMarketLensLive.getMarketsLiveDataWithLenderStatusV2.selector,
        alice,
        singleMarket
      )
    );
    lens.getMarketsLiveDataWithLenderStatusV2(alice, singleMarket);
  }

  function test_liveData_matchesMarketDataV2LiveFields() external {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);

    address[] memory singleMarket = new address[](1);
    singleMarket[0] = address(market);

    MarketDataV2_5 memory full = lens.getMarketDataV2(address(market));
    MarketLiveDataV2_5 memory live = lens.getMarketsLiveDataV2(singleMarket)[0];
    _assertLiveDataMatches(full, live);

    MarketLiveDataWithLenderStatusV2_5 memory withStatus = lens
      .getMarketsLiveDataWithLenderStatusV2(alice, singleMarket)[0];
    LenderAccountData memory lenderStatus = lens.getLenderAccountData(alice, address(market));

    assertEq(withStatus.lenderStatus.lender, lenderStatus.lender, 'lender');
    assertEq(withStatus.lenderStatus.scaledBalance, lenderStatus.scaledBalance, 'scaledBalance');
    assertEq(
      withStatus.lenderStatus.normalizedBalance,
      lenderStatus.normalizedBalance,
      'normalizedBalance'
    );
    assertEq(
      withStatus.lenderStatus.underlyingBalance,
      lenderStatus.underlyingBalance,
      'underlyingBalance'
    );
    assertEq(
      withStatus.lenderStatus.underlyingApproval,
      lenderStatus.underlyingApproval,
      'underlyingApproval'
    );
    assertEq(withStatus.lenderStatus.isKnownLender, lenderStatus.isKnownLender, 'isKnownLender');
  }

  function test_getMarketDataV2_treatsMissingTemporaryReserveRatioGetterAsInactive() external {
    resetWithMockHooks();

    MarketDataV2_5 memory data = lens.getMarketDataV2(address(market));

    assertEq(data.market.marketToken.token, address(market), 'market');
    assertEq(data.market.temporaryReserveRatio, false, 'temporaryReserveRatio');
    assertEq(data.market.originalAnnualInterestBips, 0, 'originalAnnualInterestBips');
    assertEq(data.market.originalReserveRatioBips, 0, 'originalReserveRatioBips');
    assertEq(data.market.temporaryReserveRatioExpiry, 0, 'temporaryReserveRatioExpiry');
  }

  function test_getMarketDataV2_tracksBorrowerTransferWithoutRelabelingHooks() external {
    MarketLensBorrowerAccountFactory accountFactory = new MarketLensBorrowerAccountFactory(
      address(borrowerIdentityRegistry)
    );
    borrowerIdentityRegistry.addAccountFactory(address(accountFactory));
    address nextBorrower = accountFactory.deployAccount(borrower);

    vm.prank(borrower);
    market.requestBorrowerTransfer(nextBorrower);

    MarketDataV2_5 memory pendingData = lens.getMarketDataV2(address(market));
    assertEq(pendingData.market.borrower, borrower, 'pending market borrower');
    assertEq(pendingData.borrowerPrincipal, borrower, 'pending market principal');
    assertEq(pendingData.pendingBorrower, nextBorrower, 'pending borrower');
    assertEq(pendingData.pendingBorrowerPrincipal, borrower, 'pending borrower principal');
    assertEq(
      pendingData.borrowerIdentityRegistry,
      address(borrowerIdentityRegistry),
      'identity registry'
    );
    assertEq(pendingData.market.hooks.administrator, borrower, 'pending hook administrator');

    vm.prank(nextBorrower);
    market.acceptBorrowerTransfer();

    MarketDataV2_5 memory acceptedData = lens.getMarketDataV2(address(market));
    assertEq(acceptedData.market.borrower, nextBorrower, 'accepted market borrower');
    assertEq(acceptedData.borrowerPrincipal, borrower, 'accepted market principal');
    assertEq(acceptedData.pendingBorrower, address(0), 'accepted pending borrower');
    assertEq(
      acceptedData.pendingBorrowerPrincipal,
      address(0),
      'accepted pending borrower principal'
    );
    assertEq(
      acceptedData.borrowerIdentityRegistry,
      address(borrowerIdentityRegistry),
      'accepted identity registry'
    );
    assertEq(acceptedData.market.hooks.administrator, borrower, 'accepted hook administrator');
  }

  function test_getMarketDataV2_tracksSameAccountPrincipalMigration() external {
    MarketLensBorrowerAccountFactory accountFactory = new MarketLensBorrowerAccountFactory(
      address(borrowerIdentityRegistry)
    );
    borrowerIdentityRegistry.addAccountFactory(address(accountFactory));
    address account = accountFactory.deployAccount(borrower);
    address newPrincipal = address(0xB0B);
    archController.registerBorrower(newPrincipal);

    vm.prank(borrower);
    market.requestBorrowerTransfer(account);
    vm.prank(account);
    market.acceptBorrowerTransfer();

    vm.prank(borrower);
    borrowerIdentityRegistry.requestBorrowerAccountPrincipalTransfer(account, newPrincipal);
    vm.prank(newPrincipal);
    borrowerIdentityRegistry.acceptBorrowerAccountPrincipalTransfer(account);
    vm.prank(account);
    market.requestBorrowerTransfer(account);

    MarketDataV2_5 memory pendingData = lens.getMarketDataV2(address(market));
    assertEq(pendingData.market.borrower, account, 'pending market borrower');
    assertEq(pendingData.borrowerPrincipal, borrower, 'pending market principal');
    assertEq(pendingData.pendingBorrower, account, 'pending borrower');
    assertEq(pendingData.pendingBorrowerPrincipal, newPrincipal, 'pending borrower principal');

    vm.prank(account);
    market.acceptBorrowerTransfer();

    MarketDataV2_5 memory acceptedData = lens.getMarketDataV2(address(market));
    assertEq(acceptedData.market.borrower, account, 'accepted market borrower');
    assertEq(acceptedData.borrowerPrincipal, newPrincipal, 'accepted market principal');
    assertEq(acceptedData.pendingBorrower, address(0), 'accepted pending borrower');
    assertEq(
      acceptedData.pendingBorrowerPrincipal,
      address(0),
      'accepted pending borrower principal'
    );
  }

  function test_coreDelegation_forAccountAndWithdrawalReads() external {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);

    address[] memory singleMarket = new address[](1);
    singleMarket[0] = address(market);
    address[] memory lenders = new address[](1);
    lenders[0] = alice;
    uint32[] memory expiries = new uint32[](1);
    expiries[0] = uint32(block.timestamp + parameters.withdrawalBatchDuration);
    LenderAccountQuery memory query = LenderAccountQuery({
      lender: alice,
      market: address(market),
      withdrawalBatchExpiries: expiries
    });
    LenderAccountQuery[] memory queries = new LenderAccountQuery[](1);
    queries[0] = query;

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(
        IMarketLensCore.getMarketDataWithLenderStatus.selector,
        alice,
        address(market)
      )
    );
    lens.getMarketDataWithLenderStatus(alice, address(market));

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(
        IMarketLensCore.getMarketsDataWithLenderStatus.selector,
        alice,
        singleMarket
      )
    );
    lens.getMarketsDataWithLenderStatus(alice, singleMarket);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(
        bytes4(keccak256('getLenderAccountData(address,address)')),
        alice,
        address(market)
      )
    );
    lens.getLenderAccountData(alice, address(market));

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(
        bytes4(keccak256('getLenderAccountData(address,address[])')),
        alice,
        singleMarket
      )
    );
    lens.getLenderAccountData(alice, singleMarket);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(
        IMarketLensCore.getLenderAccountsData.selector,
        address(market),
        lenders
      )
    );
    lens.getLenderAccountsData(address(market), lenders);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(IMarketLensCore.queryLenderAccount.selector, query)
    );
    lens.queryLenderAccount(query);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(IMarketLensCore.queryLenderAccounts.selector, queries)
    );
    lens.queryLenderAccounts(queries);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(
        IMarketLensCore.getWithdrawalBatchData.selector,
        address(market),
        expiries[0]
      )
    );
    lens.getWithdrawalBatchData(address(market), expiries[0]);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(
        IMarketLensCore.getWithdrawalBatchesData.selector,
        address(market),
        expiries
      )
    );
    lens.getWithdrawalBatchesData(address(market), expiries);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(
        IMarketLensCore.getWithdrawalBatchesDataWithLenderStatus.selector,
        address(market),
        expiries,
        alice
      )
    );
    lens.getWithdrawalBatchesDataWithLenderStatus(address(market), expiries, alice);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(
        IMarketLensCore.getWithdrawalBatchDataWithLenderStatus.selector,
        address(market),
        expiries[0],
        alice
      )
    );
    lens.getWithdrawalBatchDataWithLenderStatus(address(market), expiries[0], alice);

    vm.expectCall(
      address(lensCore),
      abi.encodeWithSelector(
        IMarketLensCore.getWithdrawalBatchDataWithLendersStatus.selector,
        address(market),
        expiries[0],
        lenders
      )
    );
    lens.getWithdrawalBatchDataWithLendersStatus(address(market), expiries[0], lenders);
  }

  function checkToken(
    TokenMetadata memory data,
    IERC20 token,
    string memory message
  ) internal view {
    assertEq(data.token, address(token), string.concat(message, ' address'));
    assertEq(data.name, token.name(), string.concat(message, ' name'));
    assertEq(data.symbol, token.symbol(), string.concat(message, ' symbol'));
    assertEq(data.decimals, token.decimals(), string.concat(message, ' decimals'));
  }

  function _assertLiveDataMatches(
    MarketDataV2_5 memory full,
    MarketLiveDataV2_5 memory live
  ) internal pure {
    MarketData memory fullMarket = full.market;
    assertEq(live.market, fullMarket.marketToken.token, 'market');
    assertEq(live.isClosed, fullMarket.isClosed, 'isClosed');
    assertEq(live.protocolFeeBips, fullMarket.protocolFeeBips, 'protocolFeeBips');
    assertEq(live.reserveRatioBips, fullMarket.reserveRatioBips, 'reserveRatioBips');
    assertEq(live.annualInterestBips, fullMarket.annualInterestBips, 'annualInterestBips');
    assertEq(live.scaleFactor, fullMarket.scaleFactor, 'scaleFactor');
    assertEq(live.totalSupply, fullMarket.totalSupply, 'totalSupply');
    assertEq(live.maxTotalSupply, fullMarket.maxTotalSupply, 'maxTotalSupply');
    assertEq(live.scaledTotalSupply, fullMarket.scaledTotalSupply, 'scaledTotalSupply');
    assertEq(live.totalAssets, fullMarket.totalAssets, 'totalAssets');
    assertEq(
      live.lastAccruedProtocolFees,
      fullMarket.lastAccruedProtocolFees,
      'lastAccruedProtocolFees'
    );
    assertEq(
      live.normalizedUnclaimedWithdrawals,
      fullMarket.normalizedUnclaimedWithdrawals,
      'normalizedUnclaimedWithdrawals'
    );
    assertEq(
      live.scaledPendingWithdrawals,
      fullMarket.scaledPendingWithdrawals,
      'scaledPendingWithdrawals'
    );
    assertEq(
      live.pendingWithdrawalExpiry,
      fullMarket.pendingWithdrawalExpiry,
      'pendingWithdrawalExpiry'
    );
    assertEq(live.isDelinquent, fullMarket.isDelinquent, 'isDelinquent');
    assertEq(live.timeDelinquent, fullMarket.timeDelinquent, 'timeDelinquent');
    assertEq(
      live.lastInterestAccruedTimestamp,
      fullMarket.lastInterestAccruedTimestamp,
      'lastInterestAccruedTimestamp'
    );
    assertEq(live.coverageLiquidity, fullMarket.coverageLiquidity, 'coverageLiquidity');
    assertEq(
      live.commitmentFeeBips.isPresent,
      full.commitmentFeeBips.isPresent,
      'commitment presence'
    );
    assertEq(live.commitmentFeeBips.value, full.commitmentFeeBips.value, 'commitment value');
    assertEq(live.drawnAmount.isPresent, full.drawnAmount.isPresent, 'drawn presence');
    assertEq(live.drawnAmount.value, full.drawnAmount.value, 'drawn value');
  }

  function checkHooksConfigFlags(
    HooksConfigData memory actual,
    HooksConfig expected,
    string memory labelPrefix
  ) internal pure {
    assertEq(
      expected.useOnDeposit(),
      actual.useOnDeposit,
      string.concat(labelPrefix, 'useOnDeposit')
    );
    assertEq(
      expected.useOnQueueWithdrawal(),
      actual.useOnQueueWithdrawal,
      string.concat(labelPrefix, 'useOnQueueWithdrawal')
    );
    assertEq(
      expected.useOnExecuteWithdrawal(),
      actual.useOnExecuteWithdrawal,
      string.concat(labelPrefix, 'useOnExecuteWithdrawal')
    );
    assertEq(
      expected.useOnTransfer(),
      actual.useOnTransfer,
      string.concat(labelPrefix, 'useOnTransfer')
    );
    assertEq(expected.useOnBorrow(), actual.useOnBorrow, string.concat(labelPrefix, 'useOnBorrow'));
    assertEq(expected.useOnRepay(), actual.useOnRepay, string.concat(labelPrefix, 'useOnRepay'));
    assertEq(
      expected.useOnCloseMarket(),
      actual.useOnCloseMarket,
      string.concat(labelPrefix, 'useOnCloseMarket')
    );
    assertEq(
      expected.useOnNukeFromOrbit(),
      actual.useOnNukeFromOrbit,
      string.concat(labelPrefix, 'useOnNukeFromOrbit')
    );
    assertEq(
      expected.useOnSetMaxTotalSupply(),
      actual.useOnSetMaxTotalSupply,
      string.concat(labelPrefix, 'useOnSetMaxTotalSupply')
    );
    assertEq(
      expected.useOnSetAnnualInterestAndReserveRatioBips(),
      actual.useOnSetAnnualInterestAndReserveRatioBips,
      string.concat(labelPrefix, 'useOnSetAnnualInterestAndReserveRatioBips')
    );
    assertEq(
      expected.useOnSetProtocolFeeBips(),
      actual.useOnSetProtocolFeeBips,
      string.concat(labelPrefix, 'useOnSetProtocolFeeBips')
    );
    assertEq(
      expected.useOnExecutePendingAnnualInterestBipsReduction(),
      actual.useOnExecutePendingAnnualInterestBipsReduction,
      string.concat(labelPrefix, 'useOnExecutePendingAnnualInterestBipsReduction')
    );
  }

  function test_HooksConfigDataFill_IncludesExecutePendingAprReductionFlag() external pure {
    HooksConfigData memory data;
    data.fill(EmptyHooksConfig.setFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction));
    assertEq(abi.encode(data).length, 12 * 32, 'encoded flag count');
    assertTrue(
      data.useOnExecutePendingAnnualInterestBipsReduction,
      'execute pending APR reduction flag'
    );
  }

  function applyFuzzInputs(MarketConfigFuzzInputs memory inputs) internal {
    inputs.updateParameters(parameters, hooksTemplate, fixedTermHooksTemplate);
    hooks = OpenTermHooks(address(0));
    setUpContracts(false);
  }

  function checkConstraints(MarketParameterConstraints memory constraints) internal view {
    assertEq(constraints.minimumDelinquencyGracePeriod, 0, 'minimumDelinquencyGracePeriod');
    assertEq(constraints.maximumDelinquencyGracePeriod, 90 days, 'maximumDelinquencyGracePeriod');
    assertEq(constraints.minimumReserveRatioBips, 0, 'minimumReserveRatioBips');
    assertEq(constraints.maximumReserveRatioBips, 10_000, 'maximumReserveRatioBips');
    assertEq(constraints.minimumDelinquencyFeeBips, 0, 'minimumDelinquencyFeeBips');
    assertEq(constraints.maximumDelinquencyFeeBips, 10_000, 'maximumDelinquencyFeeBips');
    assertEq(constraints.minimumWithdrawalBatchDuration, 0, 'minimumWithdrawalBatchDuration');
    assertEq(
      constraints.maximumWithdrawalBatchDuration,
      365 days,
      'maximumWithdrawalBatchDuration'
    );
    assertEq(constraints.minimumAnnualInterestBips, 0, 'minimumAnnualInterestBips');
    assertEq(constraints.maximumAnnualInterestBips, 10_000, 'maximumAnnualInterestBips');
  }

  function checkRoleProviderData(
    RoleProviderData memory data,
    RoleProvider provider,
    string memory labelPrefix
  ) internal pure {
    assertEq(data.timeToLive, provider.timeToLive(), string.concat(labelPrefix, ' timeToLive'));
    assertEq(
      data.providerAddress,
      provider.providerAddress(),
      string.concat(labelPrefix, ' providerAddress')
    );
    assertEq(
      data.pullProviderIndex,
      provider.pullProviderIndex(),
      string.concat(labelPrefix, ' pullProviderIndex')
    );
    assertEq(
      data.pushProviderIndex,
      provider.pushProviderIndex(),
      string.concat(labelPrefix, ' pushProviderIndex')
    );
    assertFalse(data.isManaged, string.concat(labelPrefix, ' isManaged'));
    assertEq(data.administrator, address(0), string.concat(labelPrefix, ' administrator'));
    assertEq(
      data.pendingAdministrator,
      address(0),
      string.concat(labelPrefix, ' pendingAdministrator')
    );
  }

  function checkPullProviders(RoleProviderData[] memory datas) internal view {
    RoleProvider[] memory providers = hooks.getPullProviders();
    for (uint256 i; i < providers.length; i++) {
      checkRoleProviderData(datas[i], providers[i], 'provider');
    }
  }

  function checkHooksInstance(
    HooksInstanceData memory data,
    MarketConfigFuzzInputs memory inputs
  ) internal {
    assertEq(data.hooksAddress, address(hooks), 'hooksAddress');
    assertEq(data.administrator, borrower, 'administrator');
    assertEq(data.pendingAdministrator, address(0), 'pendingAdministrator');
    assertEq(
      uint256(data.kind),
      inputs.isOpenTermHooks
        ? uint256(HooksInstanceKind.OpenTerm)
        : uint256(HooksInstanceKind.FixedTermLoan),
      'kind'
    );
    assertEq(data.hooksTemplate.hooksTemplate, parameters.hooksTemplate, 'hooksTemplate');
    assertEq(
      data.hooksTemplate.name,
      inputs.isOpenTermHooks ? 'OpenTermHooks' : 'FixedTermHooks',
      'hooksTemplateName'
    );
    checkConstraints(data.constraints);
    HooksDeploymentConfig deploymentConfig = hooks.config();
    checkHooksConfigFlags(
      data.deploymentFlags.optional,
      deploymentConfig.optionalFlags(),
      'optional '
    );
    checkHooksConfigFlags(
      data.deploymentFlags.required,
      deploymentConfig.requiredFlags(),
      'required '
    );
    checkPullProviders(data.pullProviders);
    assertEq(data.totalMarkets, 1, 'totalMarkets');
  }

  function deployPeriodicTermMarket() internal returns (PeriodicTermLensFixture memory fixture) {
    fixture.template = LibStoredInitCode.deployInitCode(type(PeriodicTermHooks).creationCode);
    hooksFactory.addHooksTemplate(
      fixture.template,
      'PeriodicTermHooks',
      address(0),
      address(0),
      0,
      0
    );

    startPrank(borrower);
    fixture.hooks = PeriodicTermHooks(hooksFactory.deployHooksInstance(fixture.template, ''));
    HooksDeploymentConfig deploymentConfig = fixture.hooks.config();
    HooksConfig hooksConfig = deploymentConfig
      .optionalFlags()
      .setHooksAddress(address(fixture.hooks))
      .mergeAllFlags(deploymentConfig.requiredFlags());

    fixture.firstWithdrawalWindowStart = uint32(block.timestamp + 25 days);
    fixture.periodDuration = 30 days;
    fixture.withdrawalWindowDuration = 7 days;
    fixture.minimumDeposit = 2e18;
    fixture.transfersDisabled = true;

    DeployMarketInputs memory deployInputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: parameters.namePrefix,
      symbolPrefix: parameters.symbolPrefix,
      maxTotalSupply: parameters.maxTotalSupply,
      annualInterestBips: parameters.annualInterestBips,
      delinquencyFeeBips: parameters.delinquencyFeeBips,
      withdrawalBatchDuration: parameters.withdrawalBatchDuration,
      reserveRatioBips: parameters.reserveRatioBips,
      delinquencyGracePeriod: parameters.delinquencyGracePeriod,
      hooks: hooksConfig
    });

    bytes memory hooksData = abi.encode(
      fixture.firstWithdrawalWindowStart,
      fixture.periodDuration,
      fixture.withdrawalWindowDuration,
      fixture.minimumDeposit,
      fixture.transfersDisabled
    );
    fixture.market = WildcatMarket(
      hooksFactory.deployMarket(deployInputs, hooksData, _nextSalt(borrower), address(0), 0)
    );
    stopPrank();
  }

  function test_getMarketData(MarketConfigFuzzInputs memory inputs, uint8 conditions) external {
    FuzzConditions condition = FuzzConditions(bound(conditions, 0, 3));
    if (condition != FuzzConditions.Default) {
      inputs.maxTotalSupply = 100e18;
      // Keep non-default lens scenarios away from min/cap boundary behavior.
      inputs.minimumDeposit = uint128(bound(inputs.minimumDeposit, 0, 90e18));
    }
    applyFuzzInputs(inputs);
    if (condition != FuzzConditions.Default) {
      uint256 depositAmount = parameters.minimumDeposit > 0
        ? MathUtils.max(1e19, parameters.minimumDeposit + 1e18)
        : 1e19;
      if (condition == FuzzConditions.DepositOnly) {
        _deposit(alice, depositAmount);
      } else if (condition == FuzzConditions.DepositBorrow) {
        _deposit(alice, depositAmount);
        uint256 borrowAmount = depositAmount.bipMul(10_000 - parameters.reserveRatioBips);
        if (borrowAmount > 1) {
          _borrow(borrowAmount - 1);
        }
      } else if (condition == FuzzConditions.DepositBorrowWithdraw) {
        if (!inputs.isOpenTermHooks) fastForward(inputs.fixedTermDuration);
        // uint borrowAmount = depositAmount.bipMul(10_000 - parameters.reserveRatioBips);
        uint256 borrowAmount = depositAmount.bipMul(10_000 - parameters.reserveRatioBips);
        if (borrowAmount > 1) {
          _deposit(alice, depositAmount);
          _borrow(borrowAmount - 1);
          uint256 withdrawalAmount = market.balanceOf(alice);
          _requestWithdrawal(alice, withdrawalAmount);
        }
      }
    }
    MarketData memory data = lens.getMarketData(address(market));

    checkToken(data.marketToken, IERC20(address(market)), 'marketToken');
    checkToken(data.underlyingToken, IERC20(address(asset)), 'underlyingToken');
    assertEq(data.hooksFactory, address(hooksFactory), 'hooksFactory');
    assertEq(data.borrower, borrower, 'borrower');
    assertEq(
      data.withdrawalBatchDuration,
      parameters.withdrawalBatchDuration,
      'withdrawalBatchDuration'
    );
    assertEq(data.feeRecipient, parameters.feeRecipient, 'feeRecipient');
    assertEq(data.delinquencyFeeBips, parameters.delinquencyFeeBips, 'delinquencyFeeBips');
    assertEq(
      data.delinquencyGracePeriod,
      parameters.delinquencyGracePeriod,
      'delinquencyGracePeriod'
    );

    // Check hooks config
    assertEq(data.hooksConfig.hooksAddress, address(hooks), 'hooksAddress');
    checkHooksConfigFlags(data.hooksConfig.flags, market.hooks(), 'hooksConfig');

    // Check market state
    MarketState memory state = market.currentState();
    assertEq(data.isClosed, false, 'isClosed');
    assertEq(data.protocolFeeBips, parameters.protocolFeeBips, 'protocolFeeBips');
    assertEq(data.reserveRatioBips, parameters.reserveRatioBips, 'reserveRatioBips');
    assertEq(data.annualInterestBips, parameters.annualInterestBips, 'annualInterestBips');
    assertEq(data.scaleFactor, market.scaleFactor(), 'scaleFactor');
    assertEq(data.totalSupply, market.totalSupply(), 'totalSupply');
    assertEq(data.maxTotalSupply, parameters.maxTotalSupply, 'maxTotalSupply');
    assertEq(data.scaledTotalSupply, market.scaledTotalSupply(), 'scaledTotalSupply');
    assertEq(data.totalAssets, lastTotalAssets, 'totalAssets');
    assertEq(data.lastAccruedProtocolFees, state.accruedProtocolFees, 'lastAccruedProtocolFees');
    assertEq(
      data.normalizedUnclaimedWithdrawals,
      state.normalizedUnclaimedWithdrawals,
      'normalizedUnclaimedWithdrawals'
    );
    assertEq(
      data.scaledPendingWithdrawals,
      state.scaledPendingWithdrawals,
      'scaledPendingWithdrawals'
    );
    assertEq(
      data.pendingWithdrawalExpiry,
      state.pendingWithdrawalExpiry,
      'pendingWithdrawalExpiry'
    );
    assertEq(data.isDelinquent, state.isDelinquent, 'isDelinquent');
    assertEq(data.timeDelinquent, state.timeDelinquent, 'timeDelinquent');
    assertEq(
      data.lastInterestAccruedTimestamp,
      state.lastInterestAccruedTimestamp,
      'lastInterestAccruedTimestamp'
    );
    assertEq(
      data.unpaidWithdrawalBatchExpiries.length,
      _withdrawalData.unpaidBatches.length(),
      'unpaidWithdrawalBatchExpiries'
    );
    assertEq(data.coverageLiquidity, state.liquidityRequired(), 'coverageLiquidity');

    // Test temporary excess reserve ratio
    assertEq(data.temporaryReserveRatio, false, 'temporaryReserveRatio');
    assertEq(data.originalAnnualInterestBips, 0, 'originalAnnualInterestBips');
    assertEq(data.originalReserveRatioBips, 0, 'originalReserveRatioBips');
    assertEq(data.temporaryReserveRatioExpiry, 0, 'temporaryReserveRatioExpiry');

    // Test getUnpaidAndPendingWithdrawalBatches
    // WithdrawalBatchData[] memory batches = data.getUnpaidAndPendingWithdrawalBatches();
    // assertEq(batches.length, 0, 'unpaid and pending withdrawal batches');

    checkHooksInstance(data.hooks, inputs);
  }

  function test_getMarketData_includesStoredUnpaidWithdrawalBatchExpiries() external {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    fastForward(parameters.withdrawalBatchDuration + 1);
    market.updateState();
    updateState(pendingState());

    uint32[] memory unpaidBatchExpiries = market.getUnpaidBatchExpiries();
    assertEq(unpaidBatchExpiries.length, 1, 'expected unpaid batch');

    MarketData memory data = lens.getMarketData(address(market));
    assertEq(
      data.unpaidWithdrawalBatchExpiries.length,
      unpaidBatchExpiries.length,
      'unpaid expiry count'
    );
    assertEq(data.unpaidWithdrawalBatchExpiries[0], unpaidBatchExpiries[0], 'unpaid expiry');
  }

  function test_getMarketData_includesVirtualExpiredPendingWithdrawalBatch() external {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    uint32 expiry = uint32(block.timestamp + parameters.withdrawalBatchDuration);
    fastForward(parameters.withdrawalBatchDuration + 1);

    assertEq(market.getUnpaidBatchExpiries().length, 0, 'stored unpaid before update');

    MarketData memory data = lens.getMarketData(address(market));
    assertEq(data.unpaidWithdrawalBatchExpiries.length, 1, 'unpaid expiry count');
    assertEq(data.unpaidWithdrawalBatchExpiries[0], expiry, 'unpaid expiry');
  }

  function test_getMarketData_treatsFullyPaidExpiredPendingWithdrawalBatchAsPending() external {
    _deposit(alice, 1e18);
    uint32 expiry = _requestWithdrawal(alice, 1e18);
    fastForward(parameters.withdrawalBatchDuration + 1);

    MarketData memory data = lens.getMarketData(address(market));
    assertEq(data.pendingWithdrawalExpiry, expiry, 'pending expiry');
    assertEq(data.unpaidWithdrawalBatchExpiries.length, 0, 'unpaid expiry count');

    address[] memory markets = new address[](1);
    markets[0] = address(market);
    MarketLiveDataV2_5 memory liveData = lens.getMarketsLiveDataV2(markets)[0];
    assertEq(liveData.pendingWithdrawalExpiry, expiry, 'live pending expiry');
  }

  function test_getMarketsLiveDataV2_ignoresUnpaidExpiredPendingWithdrawalBatch() external {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    fastForward(parameters.withdrawalBatchDuration + 1);

    address[] memory markets = new address[](1);
    markets[0] = address(market);
    MarketLiveDataV2_5 memory liveData = lens.getMarketsLiveDataV2(markets)[0];
    assertEq(liveData.pendingWithdrawalExpiry, 0, 'live pending expiry');
  }

  function test_getMarketData_supportsPeriodicTermHooks() external {
    PeriodicTermLensFixture memory fixture = deployPeriodicTermMarket();

    MarketData memory data = lens.getMarketData(address(fixture.market));
    checkHooksConfigFlags(data.hooksConfig.flags, fixture.market.hooks(), 'periodic market ');

    assertEq(
      uint256(data.hooksConfig.kind),
      uint256(HooksInstanceKind.PeriodicTerm),
      'hooksConfig kind'
    );
    assertEq(uint256(data.hooks.kind), uint256(HooksInstanceKind.PeriodicTerm), 'hooks kind');
    assertEq(data.hooks.hooksAddress, address(fixture.hooks), 'hooks instance address');
    assertEq(data.hooks.administrator, borrower, 'hooks administrator');
    assertEq(data.hooks.totalMarkets, 1, 'hooks totalMarkets');
    assertEq(
      data.hooksConfig.firstWithdrawalWindowStart,
      fixture.firstWithdrawalWindowStart,
      'firstWithdrawalWindowStart'
    );
    assertEq(data.hooksConfig.periodDuration, fixture.periodDuration, 'periodDuration');
    assertEq(
      data.hooksConfig.withdrawalWindowDuration,
      fixture.withdrawalWindowDuration,
      'withdrawalWindowDuration'
    );
    assertEq(data.hooksConfig.minimumDeposit, fixture.minimumDeposit, 'minimumDeposit');
    assertEq(data.hooksConfig.transfersDisabled, fixture.transfersDisabled, 'transfersDisabled');
    assertEq(data.hooksConfig.transferRequiresAccess, true, 'transferRequiresAccess');
    assertEq(data.hooksConfig.depositRequiresAccess, true, 'depositRequiresAccess');
    assertEq(data.hooksConfig.withdrawalRequiresAccess, true, 'withdrawalRequiresAccess');
    assertEq(data.hooksConfig.periodicTermClosed, false, 'periodicTermClosed');

    vm.prank(borrower);
    fixture.market.closeMarket();
    data = lens.getMarketData(address(fixture.market));
    assertEq(data.hooksConfig.periodicTermClosed, true, 'periodicTermClosed after close');
  }

  function test_getHooksInstancesForBorrower_supportsPeriodicTermHooks() external {
    PeriodicTermLensFixture memory fixture = deployPeriodicTermMarket();

    HooksInstanceData[] memory data = lens.getHooksInstancesForBorrower(borrower);
    assertEq(data.length, 2, 'length');

    bool found;
    for (uint256 i; i < data.length; i++) {
      if (data[i].hooksAddress == address(fixture.hooks)) {
        found = true;
        assertEq(uint256(data[i].kind), uint256(HooksInstanceKind.PeriodicTerm), 'periodic kind');
        assertEq(data[i].administrator, borrower, 'periodic administrator');
        assertEq(data[i].hooksTemplate.hooksTemplate, fixture.template, 'periodic template');
        assertEq(data[i].hooksTemplate.name, 'PeriodicTermHooks', 'periodic template name');
        HooksDeploymentConfig deploymentConfig = fixture.hooks.config();
        checkHooksConfigFlags(
          data[i].deploymentFlags.optional,
          deploymentConfig.optionalFlags(),
          'periodic optional '
        );
        checkHooksConfigFlags(
          data[i].deploymentFlags.required,
          deploymentConfig.requiredFlags(),
          'periodic required '
        );
        assertEq(data[i].totalMarkets, 1, 'periodic totalMarkets');
      }
    }
    assertTrue(found, 'periodic hooks instance not found');
  }

  function test_HooksInstanceDataFill_readsAdministratorWhenNotProvided() external {
    HooksInstanceDataHarness harness = new HooksInstanceDataHarness();

    HooksInstanceData memory data = harness.fill(address(hooks), hooksFactory);

    assertEq(data.hooksAddress, address(hooks), 'hooksAddress');
    assertEq(data.administrator, borrower, 'administrator');
    assertEq(data.pendingAdministrator, address(0), 'pendingAdministrator');
  }

  function test_HooksInstanceDataFill_readsPendingAdministrator() external {
    address nextAdministrator = address(0xB0B);
    archController.registerBorrower(nextAdministrator);
    vm.prank(borrower);
    hooks.requestAdministratorTransfer(nextAdministrator);

    HooksInstanceDataHarness harness = new HooksInstanceDataHarness();
    HooksInstanceData memory data = harness.fill(address(hooks), hooksFactory);

    assertEq(data.administrator, borrower, 'administrator');
    assertEq(data.pendingAdministrator, nextAdministrator, 'pendingAdministrator');
  }

  function test_HooksInstanceDataFill_readsManagedProviderAdministration() external {
    AccessListRoleProvider provider = new AccessListRoleProvider(borrower, new address[](0));
    vm.prank(borrower);
    hooks.addRoleProvider(address(provider), 7 days);

    address newAdministrator = address(0xB0B);
    vm.prank(borrower);
    provider.requestAdministratorTransfer(newAdministrator);

    HooksInstanceDataHarness harness = new HooksInstanceDataHarness();
    HooksInstanceData memory data = harness.fill(address(hooks), hooksFactory);
    RoleProviderData memory providerData = data.pullProviders[data.pullProviders.length - 1];

    assertEq(providerData.providerAddress, address(provider), 'provider');
    assertTrue(providerData.isManaged, 'isManaged');
    assertEq(providerData.administrator, borrower, 'provider administrator');
    assertEq(
      providerData.pendingAdministrator,
      newAdministrator,
      'provider pending administrator'
    );
  }

  function test_getMarketsData() external view {
    address[] memory markets = new address[](1);
    markets[0] = address(market);
    MarketData[] memory data = lens.getMarketsData(markets);
    assertEq(data.length, 1, 'length');
    assertEq(
      keccak256(abi.encode(data[0])),
      keccak256(abi.encode(lens.getMarketData(address(market)))),
      'markets'
    );
  }

  function test_getAllMarketsDataForHooksTemplate() external view {
    MarketData[] memory data = lens.getAllMarketsDataForHooksTemplate(parameters.hooksTemplate);
    assertEq(data.length, 1, 'length');
    assertEq(
      keccak256(abi.encode(data[0])),
      keccak256(abi.encode(lens.getMarketData(address(market)))),
      'markets'
    );
  }

  function test_getUnpaidAndPendingWithdrawalBatches_includesPendingBatch() external {
    _deposit(alice, 1e18);
    uint32 expiry = _requestWithdrawal(alice, 1e18);

    MarketData memory data = lens.getMarketData(address(market));
    WithdrawalBatchData[] memory batches = data.getUnpaidAndPendingWithdrawalBatches();

    assertEq(batches.length, 1, 'batch count');
    assertEq(batches[0].expiry, expiry, 'expiry');
    assertEq(uint256(batches[0].status), uint256(BatchStatus.Pending), 'status');
  }

  function checkWithdrawalBatchData(WithdrawalBatchData memory data, uint32 expiry) internal view {
    WithdrawalBatch memory batch = market.getWithdrawalBatch(expiry);
    bool isPendingBatch = expiry != 0 && expiry == market.previousState().pendingWithdrawalExpiry;
    assertEq(data.expiry, expiry, 'expiry');

    assertEq(
      uint256(data.status),
      uint256(
        isPendingBatch
          ? expiry >= block.timestamp ? BatchStatus.Pending : BatchStatus.Expired
          : batch.scaledTotalAmount == batch.scaledAmountBurned
          ? BatchStatus.Complete
          : BatchStatus.Unpaid
      ),
      'status'
    );
    assertEq(data.scaledTotalAmount, batch.scaledTotalAmount, 'scaledTotalAmount');
    assertEq(data.scaledAmountBurned, batch.scaledAmountBurned, 'scaledAmountBurned');
    assertEq(data.normalizedAmountPaid, batch.normalizedAmountPaid, 'normalizedAmountPaid');
    uint256 remainder = MathUtils.rayMul(
      batch.scaledTotalAmount - batch.scaledAmountBurned,
      market.scaleFactor()
    );

    assertEq(
      data.normalizedTotalAmount,
      data.normalizedAmountPaid + remainder,
      'normalizedTotalAmount'
    );
  }

  function test_getWithdrawalBatchData() external {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    uint32 expiry = uint32(block.timestamp + parameters.withdrawalBatchDuration);
    checkWithdrawalBatchData(lens.getWithdrawalBatchData(address(market), expiry), expiry);
    fastForward(parameters.withdrawalBatchDuration + 1);
    market.updateState();
    checkWithdrawalBatchData(lens.getWithdrawalBatchData(address(market), expiry), expiry);
    asset.mint(address(market), 1e18);
    market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
    checkWithdrawalBatchData(lens.getWithdrawalBatchData(address(market), expiry), expiry);
  }

  function test_getWithdrawalBatchData_StatusExpiredBeforeStateUpdate() external {
    _deposit(alice, 1e18);
    uint32 expiry = _requestWithdrawal(alice, 1e18);
    fastForward(parameters.withdrawalBatchDuration + 1);

    WithdrawalBatchData memory data = lens.getWithdrawalBatchData(address(market), expiry);

    assertEq(uint256(data.status), uint256(BatchStatus.Expired), 'status');
  }

  function test_getWithdrawalBatchData_StatusCompleteWhenClosedBeforeExpiry() external {
    _deposit(alice, 1e18);
    uint32 expiry = _requestWithdrawal(alice, 1e18);
    assertGt(expiry, block.timestamp, 'batch is not future-dated');

    _closeMarket();
    assertEq(market.previousState().pendingWithdrawalExpiry, 0, 'batch is still pending');

    WithdrawalBatchData memory data = lens.getWithdrawalBatchData(address(market), expiry);
    assertEq(uint256(data.status), uint256(BatchStatus.Complete), 'status');

    vm.prank(alice);
    assertEq(market.executeWithdrawal(alice, expiry), data.normalizedAmountPaid, 'withdrawal');
  }

  function test_getWithdrawalBatchData_StatusPendingForNewClosedMarketBatch() external {
    _deposit(alice, 1e18);
    _closeMarket();

    vm.prank(alice);
    uint32 expiry = market.queueFullWithdrawal();
    assertEq(expiry, uint32(block.timestamp), 'batch expiry');

    WithdrawalBatchData memory data = lens.getWithdrawalBatchData(address(market), expiry);
    assertEq(uint256(data.status), uint256(BatchStatus.Pending), 'status');
  }

  function checkWithdrawalBatchLenderStatus(
    WithdrawalBatchLenderStatus memory data,
    uint32 expiry,
    address lender
  ) internal view {
    assertEq(data.lender, lender, 'lender');
    AccountWithdrawalStatus memory status = market.getAccountWithdrawalStatus(lender, expiry);
    assertEq(data.scaledAmount, status.scaledAmount, 'scaledAmount');
    assertEq(
      data.normalizedAmountWithdrawn,
      status.normalizedAmountWithdrawn,
      'normalizedAmountWithdrawn'
    );
    WithdrawalBatch memory batch = market.getWithdrawalBatch(expiry);
    uint256 scaledAmountOwed = batch.scaledTotalAmount - batch.scaledAmountBurned;

    uint256 normalizedAmountOwed = MathUtils.rayMul(scaledAmountOwed, market.scaleFactor());
    uint256 normalizedTotalAmount = batch.normalizedAmountPaid + normalizedAmountOwed;
    assertEq(
      data.normalizedAmountOwed,
      MathUtils.mulDiv(normalizedTotalAmount, data.scaledAmount, batch.scaledTotalAmount) -
        status.normalizedAmountWithdrawn,
      'normalizedAmountOwed'
    );
    assertEq(
      data.availableWithdrawalAmount,
      expiry > block.timestamp
        ? MathUtils.mulDiv(batch.normalizedAmountPaid, data.scaledAmount, batch.scaledTotalAmount)
        : market.getAvailableWithdrawalAmount(lender, expiry),
      'availableWithdrawalAmount'
    );
  }

  function checkWithdrawalBatchDataWithLenderStatus(
    WithdrawalBatchDataWithLenderStatus memory data,
    uint32 expiry
  ) internal {
    checkWithdrawalBatchData(data.batch, expiry);
    checkWithdrawalBatchLenderStatus(data.lenderStatus, expiry, data.lenderStatus.lender);
  }

  function checkEmptyWithdrawalBatchLenderStatus(
    WithdrawalBatchLenderStatus memory data,
    address lender
  ) internal pure {
    assertEq(data.lender, lender, 'lender');
    assertEq(data.scaledAmount, 0, 'scaledAmount');
    assertEq(data.normalizedAmountWithdrawn, 0, 'normalizedAmountWithdrawn');
    assertEq(data.normalizedAmountOwed, 0, 'normalizedAmountOwed');
    assertEq(data.availableWithdrawalAmount, 0, 'availableWithdrawalAmount');
  }

  function test_getLenderWithdrawalStatusForNonexistentBatch() external view {
    uint32 unknownExpiry = type(uint32).max;
    WithdrawalBatchDataWithLenderStatus memory data = lens
      .getWithdrawalBatchDataWithLenderStatus(address(market), unknownExpiry, alice);
    checkWithdrawalBatchData(data.batch, unknownExpiry);
    checkEmptyWithdrawalBatchLenderStatus(data.lenderStatus, alice);

    uint32[] memory expiries = new uint32[](2);
    expiries[0] = 0;
    expiries[1] = unknownExpiry;
    WithdrawalBatchDataWithLenderStatus[] memory batches = lens
      .getWithdrawalBatchesDataWithLenderStatus(address(market), expiries, alice);
    for (uint256 i; i < expiries.length; i++) {
      checkWithdrawalBatchData(batches[i].batch, expiries[i]);
      checkEmptyWithdrawalBatchLenderStatus(batches[i].lenderStatus, alice);
    }

    address[] memory lenders = new address[](2);
    lenders[0] = alice;
    lenders[1] = bob;
    (WithdrawalBatchData memory batch, WithdrawalBatchLenderStatus[] memory statuses) = lens
      .getWithdrawalBatchDataWithLendersStatus(address(market), unknownExpiry, lenders);
    checkWithdrawalBatchData(batch, unknownExpiry);
    for (uint256 i; i < lenders.length; i++) {
      checkEmptyWithdrawalBatchLenderStatus(statuses[i], lenders[i]);
    }
  }

  function test_getLenderWithdrawalStatus() external {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    uint32 expiry = uint32(block.timestamp + parameters.withdrawalBatchDuration);
    checkWithdrawalBatchDataWithLenderStatus(
      lens.getWithdrawalBatchDataWithLenderStatus(address(market), uint32(expiry), address(alice)),
      expiry
    );
    fastForward(parameters.withdrawalBatchDuration + 1);

    vm.prank(alice);
    market.executeWithdrawal(alice, expiry);
    checkWithdrawalBatchDataWithLenderStatus(
      lens.getWithdrawalBatchDataWithLenderStatus(address(market), uint32(expiry), address(alice)),
      expiry
    );

    asset.mint(address(market), 1e18);
    market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
    checkWithdrawalBatchDataWithLenderStatus(
      lens.getWithdrawalBatchDataWithLenderStatus(address(market), uint32(expiry), address(alice)),
      expiry
    );

    vm.prank(alice);
    market.executeWithdrawal(alice, expiry);
    checkWithdrawalBatchDataWithLenderStatus(
      lens.getWithdrawalBatchDataWithLenderStatus(address(market), uint32(expiry), address(alice)),
      expiry
    );
  }

  function test_getHooksTemplateForBorrower() external {
    originationFeeAsset.mint(address(this), 1e18);
    originationFeeAsset.approve(address(hooksFactory), 1e18);
    hooksFactory.updateHooksTemplateFees(
      hooksTemplate,
      address(this),
      address(originationFeeAsset),
      1e18,
      1_000
    );
    parameters.feeRecipient = address(this);

    HooksTemplateData memory data = lens.getHooksTemplateForBorrower(
      address(this),
      address(hooksTemplate)
    );

    checkHooksTemplateData(data, true);
  }

  function test_getHooksTemplateForBorrower_withUnknownTemplate() external {
    originationFeeAsset.mint(address(this), 1e18);
    originationFeeAsset.approve(address(hooksFactory), 1e18);
    hooksFactory.updateHooksTemplateFees(
      hooksTemplate,
      address(this),
      address(originationFeeAsset),
      1e18,
      1_000
    );
    parameters.feeRecipient = address(this);
    address mockTemplate = LibStoredInitCode.deployInitCode(type(MockHooks).creationCode);
    hooksFactory.addHooksTemplate(
      mockTemplate,
      'MockHooks',
      address(this),
      address(originationFeeAsset),
      1e18,
      1_000
    );

    HooksTemplateData memory data = lens.getHooksTemplateForBorrower(
      address(this),
      address(mockTemplate)
    );

    checkHooksTemplateData(data, mockTemplate, 'MockHooks', 2);
  }

  function configureBorrowerOriginationFee() internal {
    originationFeeAsset.mint(borrower, 2e18);
    vm.prank(borrower);
    originationFeeAsset.approve(address(hooksFactory), 3e18);
    hooksFactory.updateHooksTemplateFees(
      hooksTemplate,
      address(this),
      address(originationFeeAsset),
      1e18,
      1_000
    );
    parameters.feeRecipient = address(this);
  }

  function test_getHooksInstancesForBorrower_includesBorrowerFeeData() external {
    configureBorrowerOriginationFee();

    HooksInstanceData[] memory data = lens.getHooksInstancesForBorrower(borrower);

    assertEq(data.length, 1, 'hooks instances length');
    checkFeeConfiguration(data[0].hooksTemplate.fees, borrower);
  }

  function test_getHooksDataForBorrower_includesBorrowerFeeData() external {
    configureBorrowerOriginationFee();

    HooksDataForBorrower memory data = lens.getHooksDataForBorrower(borrower);

    assertEq(data.hooksInstances.length, 1, 'hooks instances length');
    checkFeeConfiguration(data.hooksInstances[0].hooksTemplate.fees, borrower);
  }

  function test_getAggregatedHooksInstancesForBorrower_includesBorrowerFeeData() external {
    configureBorrowerOriginationFee();

    HooksInstanceData[] memory data = lens.getAggregatedHooksInstancesForBorrower(borrower);

    assertEq(data.length, 1, 'hooks instances length');
    checkFeeConfiguration(data[0].hooksTemplate.fees, borrower);
  }

  function test_getMarketData_includesBorrowerFeeDataForHooksInstance() external {
    configureBorrowerOriginationFee();

    MarketData memory data = lens.getMarketData(address(market));

    checkFeeConfiguration(data.hooks.hooksTemplate.fees, borrower);
  }

  function checkFeeConfiguration(FeeConfiguration memory config) internal view {
    checkFeeConfiguration(config, address(this));
  }

  function checkFeeConfiguration(FeeConfiguration memory config, address account) internal view {
    assertEq(config.feeRecipient, parameters.feeRecipient, 'feeRecipient');
    assertEq(config.protocolFeeBips, parameters.protocolFeeBips, 'protocolFeeBips');
    assertEq(config.originationFeeToken.token, address(originationFeeAsset), 'originationFeeToken');
    assertEq(config.originationFeeAmount, 1e18, 'originationFeeAmount');
    assertEq(
      config.borrowerOriginationFeeBalance,
      originationFeeAsset.balanceOf(account),
      'borrowerOriginationFeeBalance'
    );
    assertEq(
      config.borrowerOriginationFeeApproval,
      originationFeeAsset.allowance(account, address(hooksFactory)),
      'borrowerOriginationFeeApproval'
    );
  }

  function checkHooksTemplateData(
    HooksTemplateData memory data,
    bool isAccessControl
  ) internal view {
    (address template, string memory name, uint256 index) = isAccessControl
      ? (hooksTemplate, 'OpenTermHooks', 0)
      : (fixedTermHooksTemplate, 'FixedTermHooks', 1);
    checkHooksTemplateData(data, template, name, index);
  }

  function checkHooksTemplateData(
    HooksTemplateData memory data,
    address template,
    string memory name,
    uint256 index
  ) internal view {
    assertEq(data.hooksTemplate, template, 'hooksTemplate');
    assertEq(data.exists, true, 'exists');
    assertEq(data.enabled, true, 'enabled');
    assertEq(data.index, index, 'index');
    assertEq(data.name, name, 'name');
    assertEq(
      data.totalMarkets,
      hooksFactory.getMarketsForHooksTemplateCount(data.hooksTemplate),
      'totalMarkets'
    );
    checkFeeConfiguration(data.fees);
  }

  function test_getHooksTemplatesForBorrower() external {
    address[] memory hooksTemplates = new address[](2);
    hooksTemplates[0] = hooksTemplate;
    hooksTemplates[1] = fixedTermHooksTemplate;
    parameters.feeRecipient = address(this);

    hooksFactory.updateHooksTemplateFees(
      hooksTemplate,
      parameters.feeRecipient,
      address(originationFeeAsset),
      1e18,
      1_000
    );
    hooksFactory.updateHooksTemplateFees(
      fixedTermHooksTemplate,
      parameters.feeRecipient,
      address(originationFeeAsset),
      1e18,
      1_000
    );

    HooksTemplateData[] memory data = lens.getHooksTemplatesForBorrower(
      address(this),
      hooksTemplates
    );
    assertEq(data.length, 2, 'length');
    checkHooksTemplateData(data[0], true);
    checkHooksTemplateData(data[1], false);
  }

  function checkLenderStatus(LenderAccountData memory data) internal view {
    LenderStatus memory status = hooks.getLenderStatus(data.lender);
    assertEq(data.scaledBalance, market.scaledBalanceOf(data.lender), 'scaledBalance');
    assertEq(data.normalizedBalance, market.balanceOf(data.lender), 'normalizedBalance');
    assertEq(data.underlyingBalance, asset.balanceOf(data.lender), 'underlyingBalance');
    assertEq(
      data.underlyingApproval,
      asset.allowance(data.lender, address(market)),
      'underlyingApproval'
    );
    assertEq(data.isBlockedFromDeposits, status.isBlockedFromDeposits, 'isBlockedFromDeposits');
    checkRoleProviderData(
      data.lastProvider,
      hooks.getRoleProvider(status.lastProvider),
      'lastProvider'
    );
    assertEq(data.canRefresh, status.canRefresh, 'canRefresh');
    assertEq(data.lastApprovalTimestamp, status.lastApprovalTimestamp, 'lastApprovalTimestamp');
    assertEq(
      data.isKnownLender,
      hooks.isKnownLenderOnMarket(data.lender, address(market)),
      'isKnownLender'
    );
  }

  function test_getLenderAccountData() external view {
    LenderAccountData memory data = lens.getLenderAccountData(alice, address(market));
    checkLenderStatus(data);
  }

  function test_getLenderAccountData_BlockedFromDepositsWithoutProvider() external {
    _blockLender(alice);

    LenderStatus memory status = hooks.getLenderStatus(alice);
    assertTrue(status.isBlockedFromDeposits, 'hooks status is not blocked');
    assertEq(status.lastProvider, address(0), 'hooks status has provider');

    LenderAccountData memory data = lens.getLenderAccountData(alice, address(market));
    checkLenderStatus(data);
  }
}
