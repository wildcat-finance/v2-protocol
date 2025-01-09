// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../BaseMarketTest.sol';
import 'src/interfaces/IMarketEventsAndErrors.sol';
import 'src/libraries/MathUtils.sol';
import 'src/libraries/SafeCastLib.sol';
import 'src/libraries/MarketState.sol';
import 'src/libraries/LibERC20.sol';
import 'solady/utils/LibPRNG.sol';
import 'src/lens/MarketData.sol';
import '../helpers/fuzz/MarketConfigFuzzInputs.sol';
import 'src/lens/MarketLens.sol';

enum FuzzConditions {
  Default,
  DepositOnly,
  DepositBorrow,
  DepositBorrowWithdraw
}

contract MarketDataTest is BaseMarketTest {
  using stdStorage for StdStorage;
  using MathUtils for int256;
  using MathUtils for uint256;
  using SafeCastLib for uint256;
  using LibPRNG for LibPRNG.PRNG;

  MarketLens internal lens;
  MockERC20 originationFeeAsset = new MockERC20('Origination Fee Asset', 'OFA', 18);

  function setUp() public override {
    super.setUp();

    lens = new MarketLens(address(archController), address(hooksFactory));
    originationFeeAsset.mint(address(this), 1e18);
    originationFeeAsset.approve(address(hooksFactory), 1e18);
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
  }

  function applyFuzzInputs(MarketConfigFuzzInputs memory inputs) internal {
    inputs.updateParameters(parameters, hooksTemplate, fixedTermHooksTemplate);
    hooks = AccessControlHooks(address(0));
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
      90 days,
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
  }

  function checkPullProviders(RoleProviderData[] memory datas) internal view {
    RoleProvider[] memory providers = hooks.getPullProviders();
    for (uint i; i < providers.length; i++) {
      checkRoleProviderData(datas[i], providers[i], 'provider');
    }
  }

  function checkHooksInstance(
    HooksInstanceData memory data,
    MarketConfigFuzzInputs memory inputs
  ) internal {
    assertEq(data.hooksAddress, address(hooks), 'hooksAddress');
    assertEq(data.borrower, borrower, 'borrower');
    assertEq(
      uint256(data.kind),
      inputs.isAccessControlHooks
        ? uint256(HooksInstanceKind.AccessControl)
        : uint256(HooksInstanceKind.FixedTermLoan),
      'kind'
    );
    assertEq(data.hooksTemplate, parameters.hooksTemplate, 'hooksTemplate');
    assertEq(
      data.hooksTemplateName,
      inputs.isAccessControlHooks ? 'SingleBorrowerAccessControlHooks' : 'FixedTermLoanHooks',
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

  function test_getMarketData(MarketConfigFuzzInputs memory inputs, uint8 conditions) external {
    FuzzConditions condition = FuzzConditions(bound(conditions, 0, 3));
    if (condition != FuzzConditions.Default) {
      inputs.maxTotalSupply = 100e18;
    }
    applyFuzzInputs(inputs);
    if (condition != FuzzConditions.Default) {
      uint depositAmount = parameters.minimumDeposit > 0
        ? MathUtils.max(1e19, parameters.minimumDeposit) + 1
        : 1e19;
      if (condition == FuzzConditions.DepositOnly) {
        _deposit(alice, depositAmount);
      } else if (condition == FuzzConditions.DepositBorrow) {
        _deposit(alice, depositAmount);
        uint borrowAmount = depositAmount.bipMul(10_000 - parameters.reserveRatioBips);
        if (borrowAmount > 1) {
          _borrow(borrowAmount - 1);
        }
      } else if (condition == FuzzConditions.DepositBorrowWithdraw) {
        if (!inputs.isAccessControlHooks) fastForward(inputs.fixedTermDuration);
        // uint borrowAmount = depositAmount.bipMul(10_000 - parameters.reserveRatioBips);
        uint borrowAmount = depositAmount.bipMul(10_000 - parameters.reserveRatioBips);
        if (borrowAmount > 1) {
          _deposit(alice, depositAmount);
          _borrow(borrowAmount - 1);
          uint withdrawalAmount = market.balanceOf(alice);
          _requestWithdrawal(alice, withdrawalAmount);
        }
      }
    }
    console2.log('Got past deposit/borrow/withdraw');
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

  function checkWithdrawalBatchData(WithdrawalBatchData memory data, uint32 expiry) internal view {
    WithdrawalBatch memory batch = market.getWithdrawalBatch(expiry);
    assertEq(data.expiry, expiry, 'expiry');

    assertEq(
      uint256(data.status),
      uint256(
        expiry > block.timestamp
          ? BatchStatus.Pending
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

  function checkFeeConfiguration(FeeConfiguration memory config) internal view {
    assertEq(config.feeRecipient, parameters.feeRecipient, 'feeRecipient');
    assertEq(config.protocolFeeBips, parameters.protocolFeeBips, 'protocolFeeBips');
    assertEq(config.originationFeeToken.token, address(originationFeeAsset), 'originationFeeToken');
    assertEq(config.originationFeeAmount, 1e18, 'originationFeeAmount');
    assertEq(
      config.borrowerOriginationFeeBalance,
      originationFeeAsset.balanceOf(address(this)),
      'borrowerOriginationFeeBalance'
    );
    assertEq(
      config.borrowerOriginationFeeApproval,
      originationFeeAsset.allowance(address(this), address(hooksFactory)),
      'borrowerOriginationFeeApproval'
    );
  }

  function checkHooksTemplateData(HooksTemplateData memory data, bool isAccessControl) internal view {
    (address template, string memory name, uint index) = isAccessControl
      ? (hooksTemplate, 'SingleBorrowerAccessControlHooks', 0)
      : (fixedTermHooksTemplate, 'FixedTermLoanHooks', 1);
    checkHooksTemplateData(
      data,
      template,
      name,
      index
    );
  }

  function checkHooksTemplateData(
    HooksTemplateData memory data,
    address template,
    string memory name,
    uint index
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
}
