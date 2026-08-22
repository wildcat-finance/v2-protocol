// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IHooks } from 'src/access/IHooks.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { ReentrancyGuard } from 'src/ReentrancyGuard.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { WildcatBorrowerIdentityRegistry } from 'src/WildcatBorrowerIdentityRegistry.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { MarketParameters } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { RAY, MathUtils } from 'src/libraries/MathUtils.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { Bit_Enabled_Deposit, Bit_Enabled_Transfer, HooksConfig } from 'src/types/HooksConfig.sol';
import { ProtocolFeeReadOnDepositHooks } from '../mocks/MarketMocks.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

contract WildcatMarketTest is MarketFixture {
  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);
  address internal constant Delegate = address(0xDE1E6A7E);
  bytes4 internal constant PanicSelector = 0x4e487b71;
  uint256 internal constant ArithmeticPanic = 0x11;

  function _arithmeticPanic() private pure returns (bytes memory) {
    return abi.encodeWithSelector(PanicSelector, ArithmeticPanic);
  }

  function _tokenOptions(HooksKind kind) private pure returns (Options memory options) {
    options = _defaultOptions(kind);
    options.annualInterestBips = 0;
    options.withdrawalBatchDuration = 0;
  }

  function _newTokenMarket(HooksKind kind) private returns (Fixture memory fixture) {
    return _newMarket(_tokenOptions(kind));
  }

  function _mintMarketTokens(Fixture memory fixture, address account, uint256 amount) private {
    _deposit(fixture, account, amount);
  }

  function _assertSupplyAndBalance(
    Fixture memory fixture,
    address account,
    uint256 expected
  ) private view {
    assertEq(fixture.market.totalSupply(), expected, 'total supply');
    assertEq(fixture.market.balanceOf(account), expected, 'account balance');
  }

  function _expectedInitialState(
    Options memory options
  ) private view returns (MarketState memory state) {
    state.maxTotalSupply = options.maxTotalSupply;
    state.protocolFeeBips = options.protocolFeeBips;
    state.annualInterestBips = options.annualInterestBips;
    state.reserveRatioBips = options.reserveRatioBips;
    state.scaleFactor = uint112(RAY);
    state.lastInterestAccruedTimestamp = uint32(vm.getBlockTimestamp());
  }

  function _assertConstructorConfiguration(
    Fixture memory fixture,
    Options memory options
  ) private view {
    assertEq(fixture.market.asset(), address(fixture.asset), 'asset');
    assertEq(fixture.market.borrower(), Borrower, 'borrower');
    assertEq(fixture.market.borrowerPrincipal(), Borrower, 'borrower principal');
    assertEq(
      fixture.market.borrowerIdentityRegistry(),
      address(fixture.registry),
      'borrower registry'
    );
    assertEq(fixture.market.archController(), address(fixture.archController), 'arch controller');
    assertEq(fixture.market.factory(), address(fixture.factory), 'factory');
    assertEq(fixture.market.feeRecipient(), FeeRecipient, 'fee recipient');
    assertEq(fixture.market.sentinel(), address(fixture.sentinel), 'sentinel');
    assertEq(fixture.market.wrapperFactory(), WrapperFactory, 'wrapper factory');
    assertEq(fixture.market.maxTotalSupply(), options.maxTotalSupply, 'maximum supply');
    assertEq(fixture.market.delinquencyFeeBips(), options.delinquencyFeeBips, 'delinquency fee');
    assertEq(
      fixture.market.withdrawalBatchDuration(),
      options.withdrawalBatchDuration,
      'withdrawal duration'
    );
    assertEq(
      fixture.market.delinquencyGracePeriod(),
      options.delinquencyGracePeriod,
      'delinquency grace period'
    );
    assertEq(fixture.market.pendingBorrower(), address(0), 'pending borrower');
    assertEq(fixture.market.pendingBorrowerPrincipal(), address(0), 'pending principal');
    assertEq(fixture.market.registeredWrapper(), address(0), 'registered wrapper');

    MarketState memory expected = _expectedInitialState(options);
    MarketState memory previous = fixture.market.previousState();
    MarketState memory current = fixture.market.currentState();
    assertEq(keccak256(abi.encode(previous)), keccak256(abi.encode(expected)), 'previous state');
    assertEq(keccak256(abi.encode(current)), keccak256(abi.encode(expected)), 'current state');
  }

  function test_constructorAndInitialState_AcrossHookKinds() external {
    for (uint256 i; i < 2; i++) {
      Options memory options = _defaultOptions(HooksKind(i));
      Fixture memory fixture = _newMarket(options);
      _assertConstructorConfiguration(fixture, options);

      assertEq(fixture.market.coverageLiquidity(), 0, 'initial coverage liquidity');
      assertEq(fixture.market.totalAssets(), 0, 'initial assets');
      assertEq(fixture.market.borrowableAssets(), 0, 'initial borrowable assets');
      assertEq(fixture.market.accruedProtocolFees(), 0, 'initial protocol fees');
      assertEq(fixture.market.withdrawableProtocolFees(), 0, 'initial withdrawable fees');
      assertEq(fixture.market.totalDebts(), 0, 'initial debts');
      assertEq(fixture.market.scaledTotalSupply(), 0, 'initial scaled supply');
      assertEq(fixture.market.scaledBalanceOf(Holder), 0, 'initial scaled balance');
    }
  }

  function test_constructorPreservesDistinctBorrowerPrincipalAndParameterLayout_AcrossHookKinds()
    external
  {
    for (uint256 i; i < 2; i++) {
      Options memory options = _defaultOptions(HooksKind(i));
      Fixture memory fixture = _newMarket(options);
      address operationalBorrower = address(uint160(0xD00D + i));
      address principal = address(uint160(0xA110 + i));
      fixture.archController.registerBorrower(principal);

      MarketParameters memory parameters = _buildMarketParameters(
        fixture,
        options,
        fixture.market.hooks()
      );
      parameters.borrower = operationalBorrower;
      parameters.borrowerPrincipal = principal;
      WildcatMarket distinctIdentityMarket = _deployMarketFromParameters(fixture, parameters);

      assertEq(distinctIdentityMarket.borrower(), operationalBorrower, 'operational borrower');
      assertEq(distinctIdentityMarket.borrowerPrincipal(), principal, 'principal');
      assertEq(
        distinctIdentityMarket.borrowerIdentityRegistry(),
        address(fixture.registry),
        'identity registry'
      );
      assertEq(distinctIdentityMarket.factory(), address(fixture.factory), 'parameter factory');
      assertFalse(fixture.archController.isRegisteredBorrower(operationalBorrower));
      assertTrue(fixture.archController.isRegisteredBorrower(principal));

      (bool success, bytes memory encodedParameters) = address(fixture.factory).staticcall(
        abi.encodeCall(fixture.factory.getMarketParameters, ())
      );
      assertTrue(success, 'parameter read');
      assertEq(encodedParameters.length, 0x2c0, 'encoded parameter length');

      uint256 encodedHooks;
      address encodedPrincipal;
      address encodedIdentityRegistry;
      assembly {
        encodedHooks := mload(add(encodedParameters, 0x280))
        encodedPrincipal := mload(add(encodedParameters, 0x2a0))
        encodedIdentityRegistry := mload(add(encodedParameters, 0x2c0))
      }
      assertEq(encodedHooks, HooksConfig.unwrap(parameters.hooks), 'hooks word');
      assertEq(encodedPrincipal, principal, 'principal word');
      assertEq(encodedIdentityRegistry, address(fixture.registry), 'registry word');
    }
  }

  function test_constructorRejectsInvalidIdentityInputs() external {
    Options memory options = _defaultOptions(HooksKind.OpenTerm);
    Fixture memory fixture = _newMarket(options);
    address operationalBorrower = address(0xD00D);
    address principal = address(0xA110);
    fixture.archController.registerBorrower(principal);
    MarketParameters memory parameters = _buildMarketParameters(
      fixture,
      options,
      fixture.market.hooks()
    );
    parameters.borrower = operationalBorrower;
    parameters.borrowerPrincipal = principal;

    parameters.borrowerIdentityRegistry = address(0);
    fixture.factory.setMarketParameters(parameters);
    vm.expectRevert(IMarketEventsAndErrors.InvalidBorrowerIdentityRegistry.selector);
    _deployStoredMarket(fixture);

    WildcatArchController otherController = WildcatArchController(
      _deployCode('src/WildcatArchController.sol:WildcatArchController')
    );
    WildcatBorrowerIdentityRegistry otherRegistry = WildcatBorrowerIdentityRegistry(
      _deployCode(
        'src/WildcatBorrowerIdentityRegistry.sol:WildcatBorrowerIdentityRegistry',
        abi.encode(address(otherController))
      )
    );
    parameters.borrowerIdentityRegistry = address(otherRegistry);
    fixture.factory.setMarketParameters(parameters);
    vm.expectRevert(IMarketEventsAndErrors.InvalidBorrowerIdentityRegistry.selector);
    _deployStoredMarket(fixture);

    parameters.borrowerIdentityRegistry = address(fixture.registry);
    parameters.borrower = address(0);
    fixture.factory.setMarketParameters(parameters);
    vm.expectRevert(IMarketEventsAndErrors.InvalidBorrower.selector);
    _deployStoredMarket(fixture);

    parameters.borrower = operationalBorrower;
    parameters.borrowerPrincipal = address(0xBAD);
    fixture.factory.setMarketParameters(parameters);
    vm.expectRevert(IMarketEventsAndErrors.BorrowerPrincipalNotRegistered.selector);
    _deployStoredMarket(fixture);

    fixture.archController.registerBorrower(address(0));
    parameters.borrowerPrincipal = address(0);
    fixture.factory.setMarketParameters(parameters);
    vm.expectRevert(IMarketEventsAndErrors.BorrowerPrincipalNotRegistered.selector);
    _deployStoredMarket(fixture);
  }

  function test_stateQueriesReflectAccrualWithoutMutatingPreviousState_AcrossHookKinds() external {
    uint256 depositAmount = 50_000e18;
    uint256 expectedInterest = 5_000e18;
    uint256 expectedProtocolFees = 500e18;
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newMarket(HooksKind(i));
      uint32 initialTimestamp = uint32(vm.getBlockTimestamp());
      _deposit(fixture, Holder, depositAmount);

      assertEq(fixture.market.totalAssets(), depositAmount, 'assets after deposit');
      assertEq(fixture.market.scaledTotalSupply(), depositAmount, 'scaled supply after deposit');
      assertEq(fixture.market.scaledBalanceOf(Holder), depositAmount, 'scaled lender balance');
      assertEq(fixture.market.coverageLiquidity(), 10_000e18, 'initial coverage');
      assertEq(fixture.market.borrowableAssets(), 40_000e18, 'initial borrowable');

      vm.warp(initialBlockTimestamp + 365 days);
      MarketState memory previous = fixture.market.previousState();
      MarketState memory current = fixture.market.currentState();
      assertEq(previous.scaleFactor, RAY, 'stored scale factor');
      assertEq(previous.accruedProtocolFees, 0, 'stored protocol fees');
      assertEq(previous.lastInterestAccruedTimestamp, initialTimestamp, 'stored timestamp');
      assertEq(current.scaleFactor, 1.1e27, 'current scale factor');
      assertEq(current.accruedProtocolFees, expectedProtocolFees, 'current protocol fees');
      assertEq(current.lastInterestAccruedTimestamp, vm.getBlockTimestamp(), 'current timestamp');
      assertEq(fixture.market.scaleFactor(), 1.1e27, 'scale-factor getter');
      assertEq(fixture.market.totalSupply(), depositAmount + expectedInterest, 'current supply');
      assertEq(
        fixture.market.totalDebts(),
        depositAmount + expectedInterest + expectedProtocolFees,
        'current debts'
      );
      assertEq(fixture.market.accruedProtocolFees(), expectedProtocolFees, 'fee getter');
      assertEq(
        fixture.market.withdrawableProtocolFees(),
        expectedProtocolFees,
        'withdrawable fees'
      );
      assertEq(fixture.market.coverageLiquidity(), 11_500e18, 'current coverage');
      assertEq(fixture.market.borrowableAssets(), 38_500e18, 'current borrowable');
      assertEq(fixture.market.totalAssets(), depositAmount, 'assets remain unmodified');
    }
  }

  function test_scaleFactorAccruesThroughZeroSupplyAndDelinquencyGrace_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newMarket(HooksKind(i));
      assertEq(fixture.market.scaleFactor(), RAY, 'initial scale factor');
      vm.warp(initialBlockTimestamp + 365 days);
      assertEq(fixture.market.scaleFactor(), 1.1e27, 'zero-supply accrual');

      _deposit(fixture, Holder, 1e18);
      vm.prank(Borrower);
      fixture.market.borrow(8e17);
      vm.prank(Holder);
      fixture.market.queueWithdrawal(1e18);
      assertTrue(fixture.market.currentState().isDelinquent, 'market delinquent');

      vm.warp(vm.getBlockTimestamp() + 2_000);
      uint256 expectedScaleFactor = uint256(1.1e27) +
        MathUtils.rayMul(1.1e27, MathUtils.calculateLinearInterestFromBips(1_000, 2_000));
      MarketState memory current = fixture.market.currentState();
      assertEq(current.scaleFactor, expectedScaleFactor, 'grace-period scale factor');
      assertEq(current.timeDelinquent, 2_000, 'delinquency time');
    }
  }

  function test_withdrawableProtocolFeesRemainCappedAcrossPendingWithdrawals_AcrossHookKinds()
    external
  {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newMarket(HooksKind(i));
      _deposit(fixture, Holder, 1e18);
      vm.prank(Borrower);
      fixture.market.borrow(8e17);
      vm.warp(initialBlockTimestamp + 365 days);
      vm.prank(Holder);
      fixture.market.queueWithdrawal(1e18);

      assertEq(fixture.market.withdrawableProtocolFees(), 1e16, 'fees before donation');
      fixture.asset.mint(address(fixture.market), 8e17 + 1);
      assertEq(fixture.market.withdrawableProtocolFees(), 1e16, 'fees after donation');
      assertEq(fixture.market.currentState().accruedProtocolFees, 1e16, 'current-state fees');
    }
  }

  function test_withdrawableProtocolFeesRejectsStateChangingReentrancy() external {
    ProtocolFeeReadOnDepositHooks testHooks = ProtocolFeeReadOnDepositHooks(
      _deployCode('test-next/mocks/MarketMocks.sol:ProtocolFeeReadOnDepositHooks')
    );
    Options memory options = _defaultOptions(HooksKind.OpenTerm);
    options.requestedHooks = options.requestedHooks.setFlag(Bit_Enabled_Deposit);
    Fixture memory fixture = _newMarket(options, IHooks(address(testHooks)));

    _deposit(fixture, Holder, 1e18);
    assertFalse(testHooks.protocolFeeReadSucceeded(), 'reentrant read succeeded');
    assertEq(
      bytes32(testHooks.protocolFeeReadRevertSelector()),
      bytes32(ReentrancyGuard.NoReentrantCalls.selector),
      'reentrant read selector'
    );
  }

  function test_tokenMetadataAndRoundingMarker_AcrossHookKinds() external {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newTokenMarket(HooksKind(i));
      assertEq(fixture.market.name(), 'Wildcat Token', 'name');
      assertEq(fixture.market.symbol(), 'WCTKN', 'symbol');
      assertEq(fixture.market.decimals(), 18, 'decimals');
      assertEq(fixture.market.version(), '2.5', 'version');
      assertEq(
        fixture.market.scaledTransferRounding(),
        keccak256('scaleAmountDown'),
        'rounding marker'
      );
    }
  }

  function test_tokenMintAndBurnAccounting_AcrossHookKinds(
    uint104 rawMintAmount,
    uint104 rawBurnAmount
  ) external {
    uint256 mintAmount = bound(rawMintAmount, 1, MaximumMarketSupply);
    uint256 burnAmount = bound(rawBurnAmount, 1, mintAmount);
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(fixture, Holder, mintAmount);
      _assertSupplyAndBalance(fixture, Holder, mintAmount);

      _queueAndExecuteWithdrawal(fixture, Holder, burnAmount);
      _assertSupplyAndBalance(fixture, Holder, mintAmount - burnAmount);
    }
  }

  function test_approveStoresExactAllowance_AcrossHookKinds(
    address spender,
    uint256 amount
  ) external {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newTokenMarket(HooksKind(i));
      vm.prank(Holder);
      assertTrue(fixture.market.approve(spender, amount), 'approve result');
      assertEq(fixture.market.allowance(Holder, spender), amount, 'allowance');
    }
  }

  function test_transferMovesBalanceAndPreservesSupply_AcrossHookKinds(
    address fuzzRecipient,
    uint104 rawAmount
  ) external {
    vm.assume(fuzzRecipient != address(0) && fuzzRecipient != Holder);
    uint256 amount = bound(rawAmount, 1, MaximumMarketSupply);

    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(fixture, Holder, amount);

      vm.prank(Holder);
      assertTrue(fixture.market.transfer(fuzzRecipient, amount), 'transfer result');
      assertEq(fixture.market.totalSupply(), amount, 'supply after transfer');
      assertEq(fixture.market.balanceOf(Holder), 0, 'sender after transfer');
      assertEq(fixture.market.balanceOf(fuzzRecipient), amount, 'recipient after transfer');

      vm.prank(fuzzRecipient);
      assertTrue(fixture.market.transfer(fuzzRecipient, amount), 'self-transfer result');
      assertEq(fixture.market.totalSupply(), amount, 'supply after self-transfer');
      assertEq(fixture.market.balanceOf(fuzzRecipient), amount, 'self-transfer balance');
    }
  }

  function test_transferFromHandlesFiniteInfiniteAndSelfTransfer_AcrossHookKinds(
    address fuzzRecipient,
    uint104 rawAmount,
    uint104 rawExtraApproval
  ) external {
    vm.assume(fuzzRecipient != Holder);
    uint256 amount = bound(rawAmount, 1, MaximumMarketSupply);
    uint256 extraApproval = bound(rawExtraApproval, 0, MaximumMarketSupply - amount);
    uint256 finiteApproval = amount + extraApproval;

    for (uint256 i; i < 2; i++) {
      Fixture memory finiteFixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(finiteFixture, Holder, amount);
      vm.prank(Holder);
      finiteFixture.market.approve(Delegate, finiteApproval);
      vm.prank(Delegate);
      assertTrue(
        finiteFixture.market.transferFrom(Holder, fuzzRecipient, amount),
        'finite transferFrom result'
      );
      assertEq(finiteFixture.market.allowance(Holder, Delegate), extraApproval, 'finite allowance');
      assertEq(finiteFixture.market.totalSupply(), amount, 'finite supply');
      assertEq(finiteFixture.market.balanceOf(Holder), 0, 'finite sender');
      assertEq(finiteFixture.market.balanceOf(fuzzRecipient), amount, 'finite recipient');

      Fixture memory infiniteFixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(infiniteFixture, Holder, amount);
      vm.prank(Holder);
      infiniteFixture.market.approve(Delegate, type(uint256).max);
      vm.prank(Delegate);
      assertTrue(
        infiniteFixture.market.transferFrom(Holder, Holder, amount),
        'infinite self transferFrom result'
      );
      assertEq(
        infiniteFixture.market.allowance(Holder, Delegate),
        type(uint256).max,
        'infinite allowance'
      );
      _assertSupplyAndBalance(infiniteFixture, Holder, amount);
    }
  }

  function test_transfersRejectInsufficientBalancesAndAllowances_AcrossHookKinds(
    uint104 rawMintAmount,
    uint104 rawExcess
  ) external {
    uint256 mintAmount = bound(rawMintAmount, 1, MaximumMarketSupply - 1);
    uint256 sendAmount = mintAmount + bound(rawExcess, 1, MaximumMarketSupply - mintAmount);

    for (uint256 i; i < 2; i++) {
      Fixture memory transferFixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(transferFixture, Holder, mintAmount);
      vm.prank(Holder);
      vm.expectRevert(_arithmeticPanic());
      transferFixture.market.transfer(Recipient, sendAmount);

      Fixture memory allowanceFixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(allowanceFixture, Holder, sendAmount);
      vm.prank(Holder);
      allowanceFixture.market.approve(Delegate, sendAmount - 1);
      vm.prank(Delegate);
      vm.expectRevert(_arithmeticPanic());
      allowanceFixture.market.transferFrom(Holder, Recipient, sendAmount);

      Fixture memory balanceFixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(balanceFixture, Holder, mintAmount);
      vm.prank(Holder);
      balanceFixture.market.approve(Delegate, sendAmount);
      vm.prank(Delegate);
      vm.expectRevert(_arithmeticPanic());
      balanceFixture.market.transferFrom(Holder, Recipient, sendAmount);
    }
  }

  function test_zeroTransfersAndBlockedRecipientsRevert_AcrossHookKinds() external {
    for (uint256 i; i < 2; i++) {
      Fixture memory zeroFixture = _newTokenMarket(HooksKind(i));
      vm.expectRevert(IMarketEventsAndErrors.NullTransferAmount.selector);
      zeroFixture.market.transfer(Recipient, 0);
      vm.expectRevert(IMarketEventsAndErrors.NullTransferAmount.selector);
      zeroFixture.market.transferFrom(Holder, Recipient, 0);

      Options memory blockedOptions = _tokenOptions(HooksKind(i));
      blockedOptions.requestedHooks = blockedOptions.requestedHooks.setFlag(Bit_Enabled_Transfer);
      Fixture memory blockedFixture = _newMarket(blockedOptions);
      _mintMarketTokens(blockedFixture, Holder, 1);
      vm.prank(Borrower);
      if (HooksKind(i) == HooksKind.OpenTerm) {
        OpenTermHooks(address(blockedFixture.hooks)).blockFromDeposits(Recipient);
      } else {
        FixedTermHooks(address(blockedFixture.hooks)).blockFromDeposits(Recipient);
      }
      vm.prank(Holder);
      vm.expectRevert(IMarketEventsAndErrors.NotApprovedLender.selector);
      blockedFixture.market.transfer(Recipient, 1);
    }
  }
}
