// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { IHooks } from 'src/access/IHooks.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { MarketConstraintHooks } from 'src/access/MarketConstraintHooks.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { ReentrancyGuard } from 'src/ReentrancyGuard.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { WildcatBorrowerIdentityRegistry } from 'src/WildcatBorrowerIdentityRegistry.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { IWildcatMarketRevolving } from 'src/interfaces/IWildcatMarketRevolving.sol';
import { MarketParameters } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { FeeMath } from 'src/libraries/FeeMath.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { LibERC20 } from 'src/libraries/LibERC20.sol';
import { RAY, MathUtils } from 'src/libraries/MathUtils.sol';
import { AccountWithdrawalStatus, WithdrawalBatch } from 'src/libraries/Withdrawal.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { Bit_Enabled_Deposit, Bit_Enabled_Transfer, HooksConfig } from 'src/types/HooksConfig.sol';
import { Vm } from 'forge-std/Vm.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { MarketConfigHooks, ProtocolFeeReadOnDepositHooks } from '../mocks/MarketMocks.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

contract WildcatMarketTest is MarketFixture {
  using FeeMath for MarketState;

  error RevolvingFeeReadFailed();

  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);
  address internal constant Delegate = address(0xDE1E6A7E);
  bytes32 internal constant BorrowerStorageSlot = bytes32(type(uint256).max);
  bytes4 internal constant PanicSelector = 0x4e487b71;
  uint256 internal constant ArithmeticPanic = 0x11;
  bytes32 internal constant RevolvingDrawnAmountSlot = bytes32(uint256(10));

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

  function _withdrawalOptions(HooksKind kind) private pure returns (Options memory options) {
    options = _defaultOptions(kind);
    options.protocolFeeBips = 0;
    options.annualInterestBips = 0;
    options.delinquencyFeeBips = 0;
  }

  function _newWithdrawalMarket(HooksKind kind) private returns (Fixture memory fixture) {
    return _newMarket(_withdrawalOptions(kind));
  }

  function _newConfigMarket()
    private
    returns (Fixture memory fixture, MarketConfigHooks configHooks)
  {
    configHooks = MarketConfigHooks(
      _deployCode('test/mocks/MarketMocks.sol:MarketConfigHooks')
    );
    fixture = _newMarket(_defaultOptions(HooksKind.OpenTerm), IHooks(address(configHooks)));
  }

  function _revolvingOptions(
    uint16 commitmentFeeBips,
    uint16 annualInterestBips,
    uint16 protocolFeeBips
  ) private pure returns (Options memory options) {
    options = _defaultRevolvingOptions(HooksKind.OpenTerm);
    options.commitmentFeeBips = commitmentFeeBips;
    options.annualInterestBips = annualInterestBips;
    options.protocolFeeBips = protocolFeeBips;
    options.delinquencyFeeBips = 0;
  }

  function _revolving(Fixture memory fixture) private pure returns (IWildcatMarketRevolving) {
    return IWildcatMarketRevolving(address(fixture.market));
  }

  function _approveBorrower(Fixture memory fixture) private {
    vm.prank(Borrower);
    fixture.asset.approve(address(fixture.market), type(uint256).max);
  }

  function _accruedDebtAboveDrawn(Fixture memory fixture) private view returns (uint256) {
    return
      fixture.market.totalDebts() -
      fixture.market.totalAssets() -
      _revolving(fixture).drawnAmount();
  }

  function _assertNoDrawnAmountUpdate(Vm.Log[] memory logs) private pure {
    bytes32 eventSignature = keccak256('DrawnAmountUpdated(uint256,uint256)');
    for (uint256 i; i < logs.length; i++) {
      assertFalse(
        logs[i].topics.length > 0 && logs[i].topics[0] == eventSignature,
        'unexpected drawn amount update'
      );
    }
  }

  function _utilizationInterestRay(
    uint256 totalSupply,
    uint256 drawn,
    uint16 annualInterestBips,
    uint32 elapsed
  ) private pure returns (uint256) {
    return
      MathUtils.mulDiv(
        MathUtils.calculateLinearInterestFromBips(annualInterestBips, elapsed),
        drawn,
        totalSupply
      );
  }

  function _minimumDrawForInterest(
    uint256 totalSupply,
    uint16 annualInterestBips,
    uint32 elapsed
  ) private pure returns (uint256) {
    uint256 annualInterestRay = MathUtils.calculateLinearInterestFromBips(
      annualInterestBips,
      elapsed
    );
    return totalSupply / annualInterestRay + 1;
  }

  function _assertObservedRevolvingDust(
    uint128 totalSupply,
    uint16 annualInterestBips,
    uint32 elapsed
  ) private {
    assertEq(
      _minimumDrawForInterest(totalSupply, annualInterestBips, elapsed),
      1,
      'observed minimum draw'
    );
    uint256 expectedInterest = _utilizationInterestRay(totalSupply, 1, annualInterestBips, elapsed);
    assertTrue(expectedInterest > 0, 'observed utilization interest');

    Options memory options = _revolvingOptions(0, annualInterestBips, 0);
    options.maxTotalSupply = totalSupply;
    Fixture memory fixture = _newMarket(options);
    _deposit(fixture, Holder, totalSupply);
    vm.prank(Borrower);
    fixture.market.borrow(1);
    vm.warp(vm.getBlockTimestamp() + elapsed);
    fixture.market.updateState();
    assertEq(fixture.market.scaleFactor(), RAY + expectedInterest, 'observed dust accrual');
  }

  function _assertRevolvingDustBoundary(
    uint128 totalSupply,
    uint16 annualInterestBips,
    uint32 elapsed
  ) private {
    uint256 minimumDraw = _minimumDrawForInterest(totalSupply, annualInterestBips, elapsed);
    assertTrue(minimumDraw > 1, 'stress minimum draw');
    assertTrue(minimumDraw < totalSupply, 'stress borrowable threshold');
    assertEq(
      _utilizationInterestRay(totalSupply, minimumDraw - 1, annualInterestBips, elapsed),
      0,
      'below-threshold interest'
    );
    assertEq(
      _utilizationInterestRay(totalSupply, minimumDraw, annualInterestBips, elapsed),
      1,
      'boundary interest'
    );

    Options memory options = _revolvingOptions(0, annualInterestBips, 0);
    options.maxTotalSupply = totalSupply;
    Fixture memory belowFixture = _newMarket(options);
    _deposit(belowFixture, Holder, totalSupply);
    vm.prank(Borrower);
    belowFixture.market.borrow(minimumDraw - 1);
    vm.warp(vm.getBlockTimestamp() + elapsed);
    belowFixture.market.updateState();
    assertEq(belowFixture.market.scaleFactor(), RAY, 'below dust boundary');

    Fixture memory boundaryFixture = _newMarket(options);
    _deposit(boundaryFixture, Holder, totalSupply);
    vm.prank(Borrower);
    boundaryFixture.market.borrow(minimumDraw);
    vm.warp(vm.getBlockTimestamp() + elapsed);
    boundaryFixture.market.updateState();
    assertEq(boundaryFixture.market.scaleFactor(), RAY + 1, 'exact dust boundary');
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

  function _forceWithdrawalBatchExists(WildcatMarket market, uint32 expiry) private {
    // `_withdrawalData` starts at slot 5 and its `batches` mapping is the third slot.
    // Writing one to the first packed batch word gives it a nonzero scaled total.
    bytes32 batchSlot = keccak256(abi.encode(uint256(expiry), uint256(7)));
    vm.store(address(market), batchSlot, bytes32(uint256(1)));
    assertEq(market.getWithdrawalBatch(expiry).scaledTotalAmount, 1, 'forced batch');
  }

  function _assertClosedMarket(Fixture memory fixture) private view {
    MarketState memory state = fixture.market.previousState();
    assertTrue(state.isClosed, 'closed');
    assertEq(state.annualInterestBips, 0, 'closed APR');
    assertEq(state.reserveRatioBips, 10_000, 'closed reserve ratio');
    assertEq(state.timeDelinquent, 0, 'closed delinquency time');
  }

  function _storedMarketStateHash(Fixture memory fixture) private view returns (bytes32) {
    return keccak256(abi.encode(fixture.market.previousState()));
  }

  function _temporaryReserveRatioHash(Fixture memory fixture) private view returns (bytes32) {
    (uint16 originalApr, uint16 originalReserveRatio, uint32 expiry) = MarketConstraintHooks(
      address(fixture.hooks)
    ).temporaryExcessReserveRatio(address(fixture.market));
    return keccak256(abi.encode(originalApr, originalReserveRatio, expiry));
  }

  function _borrow(Fixture memory fixture, uint256 amount) private {
    vm.prank(Borrower);
    fixture.market.borrow(amount);
  }

  function _assertBatch(
    Fixture memory fixture,
    uint32 expiry,
    uint256 scaledTotal,
    uint256 scaledBurned,
    uint256 normalizedPaid
  ) private view {
    WithdrawalBatch memory batch = fixture.market.getWithdrawalBatch(expiry);
    assertEq(batch.scaledTotalAmount, scaledTotal, 'batch scaled total');
    assertEq(batch.scaledAmountBurned, scaledBurned, 'batch scaled burn');
    assertEq(batch.normalizedAmountPaid, normalizedPaid, 'batch normalized payment');
  }

  function _makeUnpaidBatch(
    Fixture memory fixture,
    address lender
  ) private returns (uint32 expiry) {
    _deposit(fixture, lender, 1e18);
    _borrow(fixture, 8e17);
    vm.prank(lender);
    expiry = fixture.market.queueFullWithdrawal();
    vm.warp(uint256(expiry) + 1);
    fixture.market.updateState();
    assertEq(fixture.market.getUnpaidBatchExpiries().length, 1, 'unpaid batch');
  }

  function _makeTwoUnpaidBatches(
    Fixture memory fixture,
    address lender
  ) private returns (uint32 firstExpiry, uint32 secondExpiry) {
    _deposit(fixture, lender, 2e18);
    _borrow(fixture, 16e17);
    vm.prank(lender);
    firstExpiry = fixture.market.queueWithdrawal(1e18);
    vm.warp(uint256(firstExpiry) + 1);
    fixture.market.updateState();
    vm.prank(lender);
    secondExpiry = fixture.market.queueFullWithdrawal();
    vm.warp(uint256(secondExpiry) + 1);
    fixture.market.updateState();
    assertEq(fixture.market.getUnpaidBatchExpiries().length, 2, 'two unpaid batches');
  }

  function _assertLargeFifoDrainToClose(bool revolving) private {
    uint256 batchCount = 32;
    uint256 batchAmount = 1e18;
    uint256 maxBatches = 7;

    Options memory options = _withdrawalOptions(HooksKind.OpenTerm);
    options.reserveRatioBips = 0;
    options.withdrawalBatchDuration = 1;
    options.revolving = revolving;
    options.commitmentFeeBips = 0;
    Fixture memory fixture = _newMarket(options);

    uint256 totalAmount = batchCount * batchAmount;
    _deposit(fixture, Holder, totalAmount);
    _borrow(fixture, totalAmount);

    uint32[] memory expectedExpiries = new uint32[](batchCount);
    for (uint256 i; i < batchCount; i++) {
      vm.prank(Holder);
      uint32 expiry = fixture.market.queueWithdrawal(batchAmount);
      if (i > 0) assertTrue(expiry > expectedExpiries[i - 1], 'strict expiry order');
      expectedExpiries[i] = expiry;
      vm.warp(uint256(expiry) + 1);
      fixture.market.updateState();
    }

    uint32[] memory unpaidExpiries = fixture.market.getUnpaidBatchExpiries();
    assertEq(unpaidExpiries.length, batchCount, 'large unpaid queue');
    for (uint256 i; i < batchCount; i++) {
      assertEq(unpaidExpiries[i], expectedExpiries[i], 'initial FIFO order');
      _assertBatch(fixture, expectedExpiries[i], batchAmount, 0, 0);
    }

    _fundAndApprove(fixture, Borrower, totalAmount);
    uint256 processed;
    while (processed < batchCount) {
      uint256 previousLength = unpaidExpiries.length;
      uint256 chunkSize = MathUtils.min(maxBatches, previousLength);

      if (processed == 0) {
        vm.prank(Borrower);
        fixture.market.repayAndProcessUnpaidWithdrawalBatches(totalAmount, maxBatches);
      } else {
        fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, maxBatches);
      }

      processed += chunkSize;
      unpaidExpiries = fixture.market.getUnpaidBatchExpiries();
      assertTrue(unpaidExpiries.length < previousLength, 'queue shrinks monotonically');
      assertEq(unpaidExpiries.length, batchCount - processed, 'bounded chunk size');

      for (uint256 i; i < processed; i++) {
        _assertBatch(fixture, expectedExpiries[i], batchAmount, batchAmount, batchAmount);
      }
      for (uint256 i; i < unpaidExpiries.length; i++) {
        assertEq(unpaidExpiries[i], expectedExpiries[processed + i], 'remaining FIFO order');
        _assertBatch(fixture, unpaidExpiries[i], batchAmount, 0, 0);
      }
    }

    MarketState memory drainedState = fixture.market.previousState();
    assertEq(drainedState.scaledPendingWithdrawals, 0, 'drained pending withdrawals');
    assertEq(drainedState.scaledTotalSupply, 0, 'drained total supply');
    if (revolving) assertEq(_revolving(fixture).drawnAmount(), 0, 'drained drawn amount');

    vm.prank(Borrower);
    fixture.market.closeMarket();
    _assertClosedMarket(fixture);
    assertEq(fixture.market.getUnpaidBatchExpiries().length, 0, 'closed unpaid queue');
  }

  function _assertNoWithdrawalPayment(Vm.Log[] memory logs) private pure {
    bytes32 paymentSignature = keccak256('WithdrawalBatchPayment(uint256,uint256,uint256)');
    for (uint256 i; i < logs.length; i++) {
      assertFalse(
        logs[i].topics.length > 0 && logs[i].topics[0] == paymentSignature,
        'unexpected withdrawal payment'
      );
    }
  }

  function _addressTopic(address value) private pure returns (bytes32) {
    return bytes32(uint256(uint160(value)));
  }

  function _singleTopic(bytes32 signature) private pure returns (bytes32[] memory topics) {
    topics = new bytes32[](1);
    topics[0] = signature;
  }

  function _twoTopics(
    bytes32 signature,
    bytes32 indexedValue
  ) private pure returns (bytes32[] memory topics) {
    topics = new bytes32[](2);
    topics[0] = signature;
    topics[1] = indexedValue;
  }

  function _threeTopics(
    bytes32 signature,
    bytes32 firstIndexedValue,
    bytes32 secondIndexedValue
  ) private pure returns (bytes32[] memory topics) {
    topics = new bytes32[](3);
    topics[0] = signature;
    topics[1] = firstIndexedValue;
    topics[2] = secondIndexedValue;
  }

  function _assertExactEvent(
    Vm.Log[] memory logs,
    address emitter,
    bytes32[] memory expectedTopics,
    bytes memory expectedData,
    string memory message
  ) private pure {
    bytes32 topicsHash = keccak256(abi.encode(expectedTopics));
    bytes32 dataHash = keccak256(expectedData);
    uint256 matches;
    for (uint256 i; i < logs.length; i++) {
      if (
        logs[i].emitter == emitter &&
        keccak256(abi.encode(logs[i].topics)) == topicsHash &&
        keccak256(logs[i].data) == dataHash
      ) {
        matches++;
      }
    }
    assertEq(matches, 1, message);
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
      _deployCode('test/mocks/MarketMocks.sol:ProtocolFeeReadOnDepositHooks')
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

  function test_configurationGettersAndMaximumDeposit_AcrossHookKinds(
    uint104 rawDepositAmount
  ) external {
    uint256 depositAmount = bound(rawDepositAmount, 1, MaximumMarketSupply);
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Options memory options = _defaultOptions(HooksKind(i));
      Fixture memory fixture = _newMarket(options);

      assertEq(fixture.market.maxTotalSupply(), MaximumMarketSupply, 'maximum supply getter');
      assertEq(fixture.market.annualInterestBips(), options.annualInterestBips, 'APR getter');
      assertEq(fixture.market.reserveRatioBips(), options.reserveRatioBips, 'reserve getter');
      assertFalse(fixture.market.isClosed(), 'initial closed state');
      assertEq(fixture.market.maximumDeposit(), MaximumMarketSupply, 'initial deposit capacity');

      _deposit(fixture, Holder, depositAmount);
      assertEq(
        fixture.market.maximumDeposit(),
        MaximumMarketSupply - depositAmount,
        'remaining deposit capacity'
      );

      uint256 remainingCapacity = MaximumMarketSupply - depositAmount;
      if (remainingCapacity != 0) _deposit(fixture, Holder, remainingCapacity);
      assertEq(fixture.market.maximumDeposit(), 0, 'filled deposit capacity');

      vm.warp(initialBlockTimestamp + 365 days);
      assertEq(fixture.market.maximumDeposit(), 0, 'interest cannot restore deposit capacity');
    }
  }

  function test_borrowerReservedStorageControlsAuthority_AcrossHookKinds() external {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      assertEq(
        address(uint160(uint256(vm.load(address(fixture.market), BorrowerStorageSlot)))),
        Borrower,
        'stored borrower'
      );

      address newBorrower = address(uint160(0xB0B0 + i));
      vm.store(
        address(fixture.market),
        BorrowerStorageSlot,
        bytes32(uint256(uint160(newBorrower)))
      );
      assertEq(fixture.market.borrower(), newBorrower, 'borrower getter');

      vm.prank(Borrower);
      vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
      fixture.market.setMaxTotalSupply(1);

      vm.prank(newBorrower);
      fixture.market.setMaxTotalSupply(1);
      assertEq(fixture.market.maxTotalSupply(), 1, 'new borrower authority');
    }
  }

  function test_setMaxTotalSupplyAcceptsCapacityAboveAndBelowSupply_AcrossHookKinds(
    uint104 rawSupply,
    uint128 rawHighCapacity,
    uint104 rawLowCapacity
  ) external {
    uint256 supply = bound(rawSupply, 1, MaximumMarketSupply);
    uint256 highCapacity = bound(rawHighCapacity, supply, type(uint128).max);
    uint256 lowCapacity = bound(rawLowCapacity, 0, supply - 1);

    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      _deposit(fixture, Holder, supply);

      vm.expectEmit(address(fixture.market));
      emit IMarketEventsAndErrors.MaxTotalSupplyUpdated(
        Borrower,
        MaximumMarketSupply,
        highCapacity
      );
      vm.prank(Borrower);
      fixture.market.setMaxTotalSupply(highCapacity);
      assertEq(fixture.market.maxTotalSupply(), highCapacity, 'high capacity');

      vm.expectEmit(address(fixture.market));
      emit IMarketEventsAndErrors.MaxTotalSupplyUpdated(Borrower, highCapacity, lowCapacity);
      vm.prank(Borrower);
      fixture.market.setMaxTotalSupply(lowCapacity);
      assertEq(fixture.market.maxTotalSupply(), lowCapacity, 'low capacity');
      assertEq(fixture.market.maximumDeposit(), 0, 'capacity below supply');
    }
  }

  function test_setMaxTotalSupplyRejectsInvalidCallerClosedMarketAndOverflow_AcrossHookKinds()
    external
  {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
      fixture.market.setMaxTotalSupply(1);

      vm.prank(Borrower);
      fixture.market.closeMarket();
      assertTrue(fixture.market.isClosed(), 'closed state getter');
      vm.prank(Borrower);
      vm.expectRevert(IMarketEventsAndErrors.CapacityChangeOnClosedMarket.selector);
      fixture.market.setMaxTotalSupply(1);

      Fixture memory overflowFixture = _newMarket(HooksKind(i));
      vm.prank(Borrower);
      vm.expectRevert(_arithmeticPanic());
      overflowFixture.market.setMaxTotalSupply(uint256(type(uint128).max) + 1);
    }
  }

  function test_setProtocolFeeBipsUpdatesFromFactory_AcrossHookKinds(
    uint16 rawProtocolFee
  ) external {
    uint16 protocolFee = uint16(bound(rawProtocolFee, 0, 999));

    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      vm.expectEmit(address(fixture.market));
      emit IMarketEventsAndErrors.ProtocolFeeBipsUpdated(
        address(fixture.factory),
        1_000,
        protocolFee
      );
      fixture.factory.callMarket(
        address(fixture.market),
        abi.encodeCall(fixture.market.setProtocolFeeBips, (protocolFee))
      );
      assertEq(fixture.market.previousState().protocolFeeBips, protocolFee, 'protocol fee');

      fixture.factory.callMarket(
        address(fixture.market),
        abi.encodeCall(fixture.market.setProtocolFeeBips, (protocolFee))
      );
      assertEq(fixture.market.previousState().protocolFeeBips, protocolFee, 'unchanged fee');
    }
  }

  function test_setProtocolFeeBipsRejectsInvalidCallerFeeAndClosedMarket_AcrossHookKinds()
    external
  {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      vm.expectRevert(IMarketEventsAndErrors.NotFactory.selector);
      fixture.market.setProtocolFeeBips(0);

      vm.expectRevert(IMarketEventsAndErrors.ProtocolFeeTooHigh.selector);
      fixture.factory.callMarket(
        address(fixture.market),
        abi.encodeCall(fixture.market.setProtocolFeeBips, (1_001))
      );

      vm.prank(Borrower);
      fixture.market.closeMarket();
      vm.expectRevert(IMarketEventsAndErrors.ProtocolFeeChangeOnClosedMarket.selector);
      fixture.factory.callMarket(
        address(fixture.market),
        abi.encodeCall(fixture.market.setProtocolFeeBips, (0))
      );
    }
  }

  function test_nukeFromOrbitQueuesEntireSanctionedBalanceAndIsIdempotent_AcrossHookKinds(
    address lender
  ) external {
    vm.assume(lender != address(0) && lender != Borrower);
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newMarket(HooksKind(i));
      _deposit(fixture, lender, 1e18);
      fixture.sentinel.setSanctioned(lender, true);
      uint32 expiry = uint32(initialBlockTimestamp + 1 days);

      vm.expectEmit(address(fixture.market));
      emit IMarketEventsAndErrors.SanctionedAccountAssetsQueuedForWithdrawal(
        lender,
        expiry,
        1e18,
        1e18
      );
      fixture.market.nukeFromOrbit(lender);

      assertEq(fixture.market.balanceOf(lender), 0, 'sanctioned lender balance');
      assertEq(
        fixture.market.getAccountWithdrawalStatus(lender, expiry).scaledAmount,
        1e18,
        'sanctions withdrawal amount'
      );
      assertEq(fixture.market.currentState().pendingWithdrawalExpiry, expiry, 'pending expiry');

      vm.warp(uint256(expiry) + 1);
      fixture.market.executeWithdrawal(lender, expiry);
      assertEq(
        fixture.asset.balanceOf(fixture.sentinel.EscrowAddress()),
        1e18,
        'sanctions escrow balance'
      );
      assertEq(fixture.sentinel.createEscrowCalls(), 1, 'sanctions escrow calls');
      assertEq(
        fixture.market.getAccountWithdrawalStatus(lender, expiry).normalizedAmountWithdrawn,
        1e18,
        'sanctions withdrawal executed'
      );

      fixture.market.nukeFromOrbit(lender);
      assertEq(
        fixture.market.getAccountWithdrawalStatus(lender, expiry).scaledAmount,
        1e18,
        'idempotent sanctions withdrawal'
      );
    }
  }

  function test_nukeFromOrbitHandlesEmptyBalancesAndRejectsUnsanctionedAccounts_AcrossHookKinds()
    external
  {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      vm.expectRevert(IMarketEventsAndErrors.BadLaunchCode.selector);
      fixture.market.nukeFromOrbit(Holder);

      fixture.sentinel.setSanctioned(Holder, true);
      fixture.market.nukeFromOrbit(Holder);
      assertEq(fixture.sentinel.createEscrowCalls(), 0, 'empty sanctions escrow calls');
      assertEq(fixture.market.currentState().pendingWithdrawalExpiry, 0, 'empty pending expiry');
      assertEq(
        fixture.market.getAccountWithdrawalStatus(Holder, 0).scaledAmount,
        0,
        'empty sanctions withdrawal'
      );

      fixture.sentinel.setSanctioned(address(0), true);
      fixture.market.nukeFromOrbit(address(0));
    }
  }

  function test_registerWrapperAuthenticatesFactoryAndProtectsCanonicalWrapper_AcrossHookKinds()
    external
  {
    address wrapper = address(0xA4626);

    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      vm.expectRevert(IMarketEventsAndErrors.NotWrapperFactory.selector);
      fixture.market.registerWrapper(wrapper);

      vm.expectEmit(address(fixture.market));
      emit IMarketEventsAndErrors.WrapperRegistered(wrapper);
      vm.prank(WrapperFactory);
      fixture.market.registerWrapper(wrapper);
      assertEq(fixture.market.registeredWrapper(), wrapper, 'registered wrapper');

      vm.prank(WrapperFactory);
      vm.expectRevert(IMarketEventsAndErrors.WrapperAlreadyRegistered.selector);
      fixture.market.registerWrapper(address(0xB4626));

      fixture.sentinel.setSanctioned(wrapper, true);
      vm.expectRevert(IMarketEventsAndErrors.CannotNukeWrapper.selector);
      fixture.market.nukeFromOrbit(wrapper);
    }
  }

  function test_nukeFromOrbitPreservesFixedTermWithdrawalRestriction() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();
    Options memory options = _defaultOptions(HooksKind.FixedTerm);
    options.fixedTermEndTime = uint32(initialBlockTimestamp + 365 days);
    Fixture memory fixture = _newMarket(options);
    _deposit(fixture, Holder, 1e18);
    fixture.sentinel.setSanctioned(Holder, true);

    vm.expectRevert(FixedTermHooks.WithdrawBeforeTermEnd.selector);
    fixture.market.nukeFromOrbit(Holder);
    assertEq(fixture.market.balanceOf(Holder), 1e18, 'balance after rejected nuke');
    assertEq(fixture.market.currentState().pendingWithdrawalExpiry, 0, 'pending after rejection');
  }

  function test_setAnnualInterestAndReserveRatioBipsAppliesProductionConstraints_AcrossHookKinds(
    uint16 rawAnnualInterestBips,
    uint16 requestedReserveRatioBips
  ) external {
    uint16 annualInterestBips = uint16(bound(rawAnnualInterestBips, 1, 10_000));
    uint256 reserveRatioBips = 2_000;
    if (annualInterestBips < 750) {
      uint256 temporaryReserveRatio = MathUtils.mulDiv(
        20_000,
        1_000 - uint256(annualInterestBips),
        1_000
      );
      reserveRatioBips = MathUtils.min(10_000, temporaryReserveRatio);
    }

    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      vm.expectEmit(address(fixture.market));
      emit IMarketEventsAndErrors.AnnualInterestAndReserveRatioBipsUpdated(
        Borrower,
        1_000,
        annualInterestBips,
        2_000,
        reserveRatioBips
      );
      vm.prank(Borrower);
      fixture.market.setAnnualInterestAndReserveRatioBips(
        annualInterestBips,
        requestedReserveRatioBips
      );

      assertEq(fixture.market.annualInterestBips(), annualInterestBips, 'updated APR');
      assertEq(fixture.market.reserveRatioBips(), reserveRatioBips, 'updated reserve ratio');
    }
  }

  function test_setAprRejectsAuthorityBoundsAndClosure_AcrossHookKinds() external {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
      fixture.market.setAnnualInterestAndReserveRatioBips(1_000, 2_000);

      vm.prank(Borrower);
      vm.expectRevert(MarketConstraintHooks.AnnualInterestBipsOutOfBounds.selector);
      fixture.market.setAnnualInterestAndReserveRatioBips(10_001, 0);

      vm.prank(Borrower);
      fixture.market.closeMarket();
      vm.prank(Borrower);
      vm.expectRevert(IMarketEventsAndErrors.AprChangeOnClosedMarket.selector);
      fixture.market.setAnnualInterestAndReserveRatioBips(1_000, 2_000);
    }

    (Fixture memory aprFixture, MarketConfigHooks aprHooks) = _newConfigMarket();
    aprHooks.setAprAndReserveRatioReturn(10_001, 0);
    vm.prank(Borrower);
    vm.expectRevert(IMarketEventsAndErrors.AnnualInterestBipsTooHigh.selector);
    aprFixture.market.setAnnualInterestAndReserveRatioBips(1_000, 2_000);

    (Fixture memory reserveFixture, MarketConfigHooks reserveHooks) = _newConfigMarket();
    reserveHooks.setAprAndReserveRatioReturn(1_000, 10_001);
    vm.prank(Borrower);
    vm.expectRevert(IMarketEventsAndErrors.ReserveRatioBipsTooHigh.selector);
    reserveFixture.market.setAnnualInterestAndReserveRatioBips(1_000, 2_000);
  }

  function test_setAnnualInterestAndReserveRatioBipsEnforcesLiquidityBeforeAndAfterChange()
    external
  {
    (Fixture memory oldRatioFixture, MarketConfigHooks oldRatioHooks) = _newConfigMarket();
    _deposit(oldRatioFixture, Holder, 1e18);
    vm.prank(Borrower);
    oldRatioFixture.market.borrow(8e17);
    vm.prank(Holder);
    oldRatioFixture.market.queueWithdrawal(1e18);
    assertTrue(oldRatioFixture.market.currentState().isDelinquent, 'old-ratio delinquency');

    oldRatioHooks.setAprAndReserveRatioReturn(1_000, 2_000);
    vm.prank(Borrower);
    vm.expectRevert(IMarketEventsAndErrors.InsufficientReservesForOldLiquidityRatio.selector);
    oldRatioFixture.market.setAnnualInterestAndReserveRatioBips(1_000, 2_000);

    (Fixture memory newRatioFixture, MarketConfigHooks newRatioHooks) = _newConfigMarket();
    _deposit(newRatioFixture, Holder, 1e18);
    vm.prank(Borrower);
    newRatioFixture.market.borrow(5e17);
    vm.prank(Holder);
    newRatioFixture.market.queueWithdrawal(1e18);
    newRatioHooks.setAprAndReserveRatioReturn(1_000, 5_020);
    vm.prank(Borrower);
    vm.expectRevert(IMarketEventsAndErrors.InsufficientReservesForNewLiquidityRatio.selector);
    newRatioFixture.market.setAnnualInterestAndReserveRatioBips(1_000, 2_000);

    Fixture memory healthyFixture = _newMarket(HooksKind.OpenTerm);
    _deposit(healthyFixture, Holder, 50_000e18);
    vm.prank(Borrower);
    healthyFixture.market.borrow(5_000e18 + 1);
    vm.prank(Borrower);
    healthyFixture.market.setAnnualInterestAndReserveRatioBips(1_000, 1);
    assertEq(healthyFixture.market.reserveRatioBips(), 2_000, 'borrower reserve input ignored');
    assertFalse(healthyFixture.market.currentState().isDelinquent, 'healthy after APR update');
  }

  function test_setAprRollsBackMarketAndHookStateWhenPostHookLiquidityCheckReverts() external {
    Fixture memory fixture = _newMarket(HooksKind.OpenTerm);
    _deposit(fixture, Holder, 1e18);
    _borrow(fixture, 5e17);

    bytes32 marketStateBefore = _storedMarketStateHash(fixture);
    bytes32 hookStateBefore = _temporaryReserveRatioHash(fixture);
    uint256 marketAssetsBefore = fixture.asset.balanceOf(address(fixture.market));

    vm.prank(Borrower);
    vm.expectRevert(IMarketEventsAndErrors.InsufficientReservesForNewLiquidityRatio.selector);
    fixture.market.setAnnualInterestAndReserveRatioBips(500, 0);

    assertEq(_storedMarketStateHash(fixture), marketStateBefore, 'market state rollback');
    assertEq(_temporaryReserveRatioHash(fixture), hookStateBefore, 'hook state rollback');
    assertEq(
      fixture.asset.balanceOf(address(fixture.market)),
      marketAssetsBefore,
      'market assets rollback'
    );
  }

  function test_setAprRollsBackActiveTemporaryReserveWindowWhenLiquidityCheckReverts()
    external
  {
    Fixture memory fixture = _newMarket(HooksKind.OpenTerm);
    _deposit(fixture, Holder, 1e18);

    vm.prank(Borrower);
    fixture.market.setAnnualInterestAndReserveRatioBips(500, 0);
    assertEq(fixture.market.reserveRatioBips(), 10_000, 'temporary reserve ratio');

    (, , uint32 originalExpiry) = MarketConstraintHooks(address(fixture.hooks))
      .temporaryExcessReserveRatio(address(fixture.market));
    fixture.asset.burn(address(fixture.market), 1e17);
    vm.warp(vm.getBlockTimestamp() + 1 days);
    assertTrue(originalExpiry > vm.getBlockTimestamp(), 'temporary window active');
    assertTrue(
      originalExpiry < vm.getBlockTimestamp() + 2 weeks,
      'further reduction would extend window'
    );

    bytes32 marketStateBefore = _storedMarketStateHash(fixture);
    bytes32 hookStateBefore = _temporaryReserveRatioHash(fixture);
    uint256 marketAssetsBefore = fixture.asset.balanceOf(address(fixture.market));

    vm.prank(Borrower);
    vm.expectRevert(IMarketEventsAndErrors.InsufficientReservesForOldLiquidityRatio.selector);
    fixture.market.setAnnualInterestAndReserveRatioBips(400, 0);

    assertEq(_storedMarketStateHash(fixture), marketStateBefore, 'active market state rollback');
    assertEq(_temporaryReserveRatioHash(fixture), hookStateBefore, 'active hook state rollback');
    assertEq(
      fixture.asset.balanceOf(address(fixture.market)),
      marketAssetsBefore,
      'active market assets rollback'
    );
  }

  function test_executePendingAnnualInterestBipsReductionIsPermissionlessAndUsesHookState()
    external
  {
    (Fixture memory fixture, MarketConfigHooks configHooks) = _newConfigMarket();
    configHooks.setPendingAnnualInterestBipsReduction(999);

    vm.expectEmit(address(fixture.market));
    emit IMarketEventsAndErrors.AnnualInterestAndReserveRatioBipsUpdated(
      Holder,
      1_000,
      999,
      2_000,
      2_000
    );
    vm.prank(Holder);
    fixture.market.executePendingAnnualInterestBipsReduction();

    assertEq(fixture.market.annualInterestBips(), 999, 'executed pending APR');
    assertEq(fixture.market.reserveRatioBips(), 2_000, 'preserved reserve ratio');
    assertEq(configHooks.lastIntermediateAnnualInterestBips(), 1_000, 'intermediate APR');
    assertEq(configHooks.lastIntermediateReserveRatioBips(), 2_000, 'intermediate reserve ratio');
  }

  function test_executePendingAnnualInterestBipsReductionRejectsInvalidMarketAndHookStates()
    external
  {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      vm.expectRevert(IMarketEventsAndErrors.ExecutePendingAprReductionNotEnabled.selector);
      fixture.market.executePendingAnnualInterestBipsReduction();

      vm.prank(Borrower);
      fixture.market.closeMarket();
      vm.expectRevert(IMarketEventsAndErrors.AprChangeOnClosedMarket.selector);
      fixture.market.executePendingAnnualInterestBipsReduction();
    }

    (Fixture memory equalFixture, MarketConfigHooks equalHooks) = _newConfigMarket();
    equalHooks.setPendingAnnualInterestBipsReduction(1_000);
    vm.expectRevert(IMarketEventsAndErrors.AprReductionNotReduction.selector);
    equalFixture.market.executePendingAnnualInterestBipsReduction();
    equalHooks.setPendingAnnualInterestBipsReduction(1_001);
    vm.expectRevert(IMarketEventsAndErrors.AprReductionNotReduction.selector);
    equalFixture.market.executePendingAnnualInterestBipsReduction();

    (Fixture memory delinquentFixture, MarketConfigHooks delinquentHooks) = _newConfigMarket();
    _deposit(delinquentFixture, Holder, 1e18);
    vm.prank(Borrower);
    delinquentFixture.market.borrow(8e17);
    vm.prank(Holder);
    delinquentFixture.market.queueWithdrawal(1e18);
    delinquentHooks.setPendingAnnualInterestBipsReduction(999);
    vm.expectRevert(IMarketEventsAndErrors.InsufficientReservesForOldLiquidityRatio.selector);
    delinquentFixture.market.executePendingAnnualInterestBipsReduction();
  }

  function test_updateStatePersistsAccrualAndNoChange_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newMarket(HooksKind(i));
      _deposit(fixture, Holder, 1e18);
      vm.warp(initialBlockTimestamp + 365 days);

      MarketState memory expected = fixture.market.currentState();
      fixture.market.updateState();
      assertEq(
        keccak256(abi.encode(fixture.market.previousState())),
        keccak256(abi.encode(expected)),
        'persisted current state'
      );

      bytes32 stateHash = keccak256(abi.encode(expected));
      fixture.market.updateState();
      assertEq(
        keccak256(abi.encode(fixture.market.previousState())),
        stateHash,
        'same-block state'
      );
    }
  }

  function test_updateStateProcessesExpiredBatchesWithDistinctAndSameBlockAccrual() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Options memory options = _defaultOptions(HooksKind.OpenTerm);
      options.annualInterestBips = 3_650;
      options.withdrawalBatchDuration = i == 0 ? 1 days : 0;
      Fixture memory fixture = _newMarket(options);
      _deposit(fixture, Holder, 1e18);
      vm.prank(Holder);
      uint32 expiry = fixture.market.queueFullWithdrawal();

      vm.warp(initialBlockTimestamp + 2 days);
      fixture.market.updateState();

      WithdrawalBatch memory batch = fixture.market.getWithdrawalBatch(expiry);
      assertEq(batch.scaledTotalAmount, 1e18, 'expired scaled total');
      assertEq(batch.scaledAmountBurned, 1e18, 'expired scaled burn');
      assertEq(batch.normalizedAmountPaid, 1e18, 'expired normalized payment');
      assertEq(fixture.market.previousState().pendingWithdrawalExpiry, 0, 'expired pending batch');
      assertEq(fixture.market.getUnpaidBatchExpiries().length, 0, 'expired unpaid batches');
      assertEq(
        fixture.market.previousState().lastInterestAccruedTimestamp,
        initialBlockTimestamp + 2 days,
        'expired accrual timestamp'
      );
    }
  }

  function test_expiredBatchSettlementRefreshesDelinquency_AcrossMarketTypes() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();
    uint256 liveScaledSupply = 1_000_000e18;

    for (uint256 marketKind; marketKind < 2; marketKind++) {
      vm.warp(initialBlockTimestamp);
      Options memory options = _defaultOptions(HooksKind.OpenTerm);
      options.revolving = marketKind == 1;
      options.maxTotalSupply = uint128(liveScaledSupply + 2);
      options.protocolFeeBips = 0;
      options.annualInterestBips = marketKind == 0 ? 10_000 : 0;
      options.commitmentFeeBips = marketKind == 1 ? 10_000 : 0;
      options.delinquencyFeeBips = 10_000;
      options.delinquencyGracePeriod = 0;
      options.withdrawalBatchDuration = 1;
      options.reserveRatioBips = 0;
      Fixture memory fixture = _newMarket(options);

      uint256 initialSupply = liveScaledSupply + 2;
      _deposit(fixture, Holder, initialSupply);
      vm.prank(Borrower);
      fixture.market.borrow(initialSupply);

      vm.warp(initialBlockTimestamp + 146 days);
      vm.prank(Holder);
      uint32 firstExpiry = fixture.market.queueWithdrawalScaled(1);
      assertEq(fixture.market.scaleFactor(), 1.4e27, 'scale factor setup');
      assertTrue(fixture.market.previousState().isDelinquent, 'first batch delinquency');

      vm.warp(uint256(firstExpiry) + 1);
      vm.prank(Holder);
      uint32 secondExpiry = fixture.market.queueWithdrawalScaled(1);
      MarketState memory beforeSecondExpiry = fixture.market.previousState();
      assertEq(beforeSecondExpiry.scaledPendingWithdrawals, 2, 'two pending scaled units');
      assertTrue(beforeSecondExpiry.isDelinquent, 'pre-settlement delinquency');

      fixture.asset.mint(Recipient, 2);
      vm.prank(Recipient);
      fixture.asset.transfer(address(fixture.market), 2);
      assertEq(beforeSecondExpiry.liquidityRequired(), 3, 'pre-settlement requirement');

      uint256 checkpointTimestamp = uint256(secondExpiry) + 4 days;
      uint256 firstSegmentDuration = secondExpiry - beforeSecondExpiry.lastInterestAccruedTimestamp;
      uint256 firstSegmentBaseInterest = MathUtils.calculateLinearInterestFromBips(
        10_000,
        firstSegmentDuration
      );
      uint256 firstSegmentDelinquencyFee = MathUtils.calculateLinearInterestFromBips(
        10_000,
        firstSegmentDuration
      );
      uint256 expectedScaleFactor = beforeSecondExpiry.scaleFactor;
      expectedScaleFactor += MathUtils.rayMul(
        expectedScaleFactor,
        firstSegmentBaseInterest + firstSegmentDelinquencyFee
      );
      uint256 secondSegmentDuration = checkpointTimestamp - secondExpiry;
      uint256 secondSegmentBaseInterest = MathUtils.calculateLinearInterestFromBips(
        10_000,
        secondSegmentDuration
      );
      uint256 recoveryPenaltyDuration = MathUtils.min(
        uint256(beforeSecondExpiry.timeDelinquent) + firstSegmentDuration,
        secondSegmentDuration
      );
      uint256 secondSegmentDelinquencyFee = MathUtils.calculateLinearInterestFromBips(
        10_000,
        recoveryPenaltyDuration
      );
      expectedScaleFactor += MathUtils.rayMul(
        expectedScaleFactor,
        secondSegmentBaseInterest + secondSegmentDelinquencyFee
      );

      vm.warp(checkpointTimestamp);
      MarketState memory current = fixture.market.currentState();
      assertFalse(current.isDelinquent, 'post-settlement delinquency');
      assertEq(current.timeDelinquent, 0, 'post-settlement delinquency clock');
      assertEq(current.liquidityRequired(), 2, 'post-settlement requirement');
      assertEq(current.scaleFactor, expectedScaleFactor, 'post-settlement scale factor');

      fixture.market.updateState();
      assertEq(
        keccak256(abi.encode(fixture.market.previousState())),
        keccak256(abi.encode(current)),
        'persisted current state'
      );
      WithdrawalBatch memory paidBatch = fixture.market.getWithdrawalBatch(secondExpiry);
      assertEq(paidBatch.scaledAmountBurned, 1, 'settled scaled amount');
      assertEq(paidBatch.normalizedAmountPaid, 1, 'settled normalized amount');
    }
  }

  function test_marketLifecycleEmitsCanonicalIndexerEvents() external {
    uint256 initialTimestamp = vm.getBlockTimestamp();
    Options memory options = _defaultOptions(HooksKind.OpenTerm);
    options.protocolFeeBips = 0;
    options.annualInterestBips = 3_650;
    options.delinquencyFeeBips = 0;
    Fixture memory fixture = _newMarket(options);
    _fundAndApprove(fixture, Holder, 1e18);

    vm.recordLogs();
    vm.prank(Holder);
    fixture.market.deposit(1e18);
    Vm.Log[] memory logs = vm.getRecordedLogs();
    _assertExactEvent(
      logs,
      address(fixture.market),
      _threeTopics(
        keccak256('Transfer(address,address,uint256)'),
        _addressTopic(address(0)),
        _addressTopic(Holder)
      ),
      abi.encode(1e18),
      'market-token mint event'
    );

    vm.recordLogs();
    vm.prank(Holder);
    uint32 expiry = fixture.market.queueFullWithdrawal();
    logs = vm.getRecordedLogs();
    _assertExactEvent(
      logs,
      address(fixture.market),
      _threeTopics(
        keccak256('Transfer(address,address,uint256)'),
        _addressTopic(Holder),
        _addressTopic(address(fixture.market))
      ),
      abi.encode(1e18),
      'withdrawal transfer event'
    );
    _assertExactEvent(
      logs,
      address(fixture.market),
      _threeTopics(
        keccak256('WithdrawalQueued(uint256,address,uint256,uint256)'),
        bytes32(uint256(expiry)),
        _addressTopic(Holder)
      ),
      abi.encode(1e18, 1e18),
      'withdrawal queued event'
    );

    vm.warp(initialTimestamp + 2 days);
    vm.recordLogs();
    fixture.market.updateState();
    logs = vm.getRecordedLogs();
    uint256 scaleAtExpiry = 1.001e27;
    uint256 scaleAtUpdate = 1.002001e27;
    _assertExactEvent(
      logs,
      address(fixture.market),
      _singleTopic(
        keccak256('InterestAndFeesAccrued(uint256,uint256,uint256,uint256,uint256,uint256)')
      ),
      abi.encode(initialTimestamp, expiry, scaleAtExpiry, 1e24, 0, 0),
      'first accrual event'
    );
    _assertExactEvent(
      logs,
      address(fixture.market),
      _twoTopics(
        keccak256('WithdrawalBatchExpired(uint256,uint256,uint256,uint256)'),
        bytes32(uint256(expiry))
      ),
      abi.encode(1e18, 1e18, 1e18),
      'batch expired event'
    );
    _assertExactEvent(
      logs,
      address(fixture.market),
      _twoTopics(keccak256('WithdrawalBatchClosed(uint256)'), bytes32(uint256(expiry))),
      '',
      'batch closed event'
    );
    _assertExactEvent(
      logs,
      address(fixture.market),
      _singleTopic(
        keccak256('InterestAndFeesAccrued(uint256,uint256,uint256,uint256,uint256,uint256)')
      ),
      abi.encode(expiry, initialTimestamp + 2 days, scaleAtUpdate, 1e24, 0, 0),
      'second accrual event'
    );
    _assertExactEvent(
      logs,
      address(fixture.market),
      _singleTopic(keccak256('StateUpdated(uint256,bool)')),
      abi.encode(scaleAtUpdate, false),
      'state updated event'
    );

    fixture.sentinel.setSanctioned(Holder, true);
    vm.recordLogs();
    fixture.market.executeWithdrawal(Holder, expiry);
    logs = vm.getRecordedLogs();
    _assertExactEvent(
      logs,
      address(fixture.market),
      _twoTopics(
        keccak256('SanctionedAccountWithdrawalSentToEscrow(address,address,uint32,uint256)'),
        _addressTopic(Holder)
      ),
      abi.encode(fixture.sentinel.EscrowAddress(), expiry, 1e18),
      'sanctioned escrow event'
    );
    _assertExactEvent(
      logs,
      address(fixture.market),
      _threeTopics(
        keccak256('WithdrawalExecuted(uint256,address,uint256)'),
        bytes32(uint256(expiry)),
        _addressTopic(Holder)
      ),
      abi.encode(1e18),
      'withdrawal executed event'
    );
  }

  function test_depositEntrypointsApplyCapacityExactnessAndRounding_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Options memory options = _defaultOptions(HooksKind(i));
      options.maxTotalSupply = 1e18;
      Fixture memory cappedFixture = _newMarket(options);
      _fundAndApprove(cappedFixture, Holder, 2e18);
      vm.prank(Holder);
      cappedFixture.market.deposit(1e18 - 1);
      vm.prank(Holder);
      assertEq(cappedFixture.market.depositUpTo(2), 1, 'capped deposit amount');
      assertEq(cappedFixture.market.balanceOf(Holder), 1e18, 'capped market balance');
      assertEq(cappedFixture.asset.balanceOf(Holder), 1e18, 'capped asset balance');

      vm.warp(initialBlockTimestamp);
      Fixture memory exactFixture = _newMarket(options);
      _fundAndApprove(exactFixture, Holder, 2e18);
      vm.prank(Holder);
      exactFixture.market.deposit(1e18 - 1);
      vm.prank(Holder);
      vm.expectRevert(IMarketEventsAndErrors.MaxSupplyExceeded.selector);
      exactFixture.market.deposit(2);
      assertEq(exactFixture.market.balanceOf(Holder), 1e18 - 1, 'reverted exact deposit');

      vm.warp(initialBlockTimestamp);
      Fixture memory roundingFixture = _newMarket(HooksKind(i));
      _deposit(roundingFixture, Holder, 1e18);
      vm.warp(initialBlockTimestamp + 1 days);
      _fundAndApprove(roundingFixture, Holder, 1);
      vm.prank(Holder);
      vm.expectRevert(IMarketEventsAndErrors.NullMintAmount.selector);
      roundingFixture.market.depositUpTo(1);

      vm.warp(initialBlockTimestamp);
      Fixture memory closedFixture = _newMarket(HooksKind(i));
      vm.prank(Borrower);
      closedFixture.market.closeMarket();
      _fundAndApprove(closedFixture, Holder, 1);
      vm.prank(Holder);
      vm.expectRevert(IMarketEventsAndErrors.DepositToClosedMarket.selector);
      closedFixture.market.deposit(1);

      vm.warp(initialBlockTimestamp);
      Fixture memory transferFixture = _newMarket(HooksKind(i));
      transferFixture.asset.mint(Holder, 1e18);
      vm.prank(Holder);
      vm.expectRevert(LibERC20.TransferFromFailed.selector);
      transferFixture.market.depositUpTo(1e18);

      vm.prank(Holder);
      vm.expectRevert(IMarketEventsAndErrors.NullMintAmount.selector);
      transferFixture.market.depositUpTo(0);
    }
  }

  function test_depositEntrypointsEnforceProductionMinimumAcrossHookKinds() external {
    for (uint256 i; i < 2; i++) {
      Options memory options = _defaultOptions(HooksKind(i));
      options.requestedHooks = options.requestedHooks.setFlag(Bit_Enabled_Deposit);
      options.minimumDeposit = 101;
      Fixture memory fixture = _newMarket(options);
      _fundAndApprove(fixture, Holder, 100);

      vm.prank(Holder);
      vm.expectRevert(OpenTermHooks.DepositBelowMinimum.selector);
      fixture.market.deposit(100);
    }
  }

  function test_collectFeesHandlesEmptyAvailableAndUnavailableFees_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory emptyFixture = _newMarket(HooksKind(i));
      vm.expectRevert(IMarketEventsAndErrors.NullFeeAmount.selector);
      emptyFixture.market.collectFees();

      vm.warp(initialBlockTimestamp);
      Fixture memory fundedFixture = _newMarket(HooksKind(i));
      _deposit(fundedFixture, Holder, 1e18);
      vm.warp(initialBlockTimestamp + 365 days);
      vm.prank(Recipient);
      fundedFixture.market.collectFees();
      assertEq(fundedFixture.asset.balanceOf(FeeRecipient), 1e16, 'collected fees');
      assertEq(fundedFixture.market.previousState().accruedProtocolFees, 0, 'fees cleared');

      vm.warp(initialBlockTimestamp);
      Fixture memory unavailableFixture = _newMarket(HooksKind(i));
      _deposit(unavailableFixture, Holder, 1e18);
      vm.warp(initialBlockTimestamp + 1);
      unavailableFixture.asset.burn(address(unavailableFixture.market), 1e18);
      vm.expectRevert(IMarketEventsAndErrors.InsufficientReservesForFeeWithdrawal.selector);
      unavailableFixture.market.collectFees();
    }
  }

  function test_borrowAppliesLiquidityAuthorityClosureAndSanctions_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newMarket(HooksKind(i));
      _deposit(fixture, Holder, 50_000e18);
      assertEq(fixture.market.borrowableAssets(), 40_000e18, 'borrowable before draw');

      vm.prank(Borrower);
      fixture.market.borrow(40_000e18);
      assertEq(fixture.asset.balanceOf(Borrower), 40_000e18, 'borrower assets');
      assertEq(fixture.market.borrowableAssets(), 0, 'borrowable after draw');

      vm.prank(Borrower);
      vm.expectRevert(IMarketEventsAndErrors.BorrowAmountTooHigh.selector);
      fixture.market.borrow(1);

      vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
      fixture.market.borrow(0);

      vm.warp(initialBlockTimestamp);
      Fixture memory sanctionedFixture = _newMarket(HooksKind(i));
      _deposit(sanctionedFixture, Holder, 1e18);
      sanctionedFixture.sentinel.setSanctioned(Borrower, true);
      vm.prank(Borrower);
      vm.expectRevert(IMarketEventsAndErrors.BorrowWhileSanctioned.selector);
      sanctionedFixture.market.borrow(1);

      vm.warp(initialBlockTimestamp);
      Fixture memory closedFixture = _newMarket(HooksKind(i));
      vm.prank(Borrower);
      closedFixture.market.closeMarket();
      vm.prank(Borrower);
      vm.expectRevert(IMarketEventsAndErrors.BorrowFromClosedMarket.selector);
      closedFixture.market.borrow(1);
    }
  }

  function test_repayHandlesSuccessZeroClosedAndTransferFailure_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newMarket(HooksKind(i));
      _deposit(fixture, Holder, 1e18);
      vm.prank(Borrower);
      fixture.market.borrow(8e17);
      _fundAndApprove(fixture, Recipient, 2e17);
      vm.expectEmit(address(fixture.market));
      emit IMarketEventsAndErrors.DebtRepaid(Recipient, 2e17);
      vm.prank(Recipient);
      fixture.market.repay(2e17);
      assertEq(fixture.asset.balanceOf(address(fixture.market)), 4e17, 'assets after repay');

      vm.expectRevert(IMarketEventsAndErrors.NullRepayAmount.selector);
      fixture.market.repay(0);

      vm.warp(initialBlockTimestamp);
      Fixture memory transferFixture = _newMarket(HooksKind(i));
      vm.expectRevert(LibERC20.TransferFromFailed.selector);
      transferFixture.market.repay(1);

      vm.warp(initialBlockTimestamp);
      Fixture memory closedFixture = _newMarket(HooksKind(i));
      vm.prank(Borrower);
      closedFixture.market.closeMarket();
      _fundAndApprove(closedFixture, Recipient, 1);
      vm.prank(Recipient);
      vm.expectRevert(IMarketEventsAndErrors.RepayToClosedMarket.selector);
      closedFixture.market.repay(1);
      assertEq(closedFixture.asset.balanceOf(Recipient), 1, 'closed repay rollback');
    }
  }

  function test_closeMarketBalancesDebtAndExcessAssets_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory debtFixture = _newMarket(HooksKind(i));
      _deposit(debtFixture, Holder, 1e18);
      vm.prank(Borrower);
      debtFixture.market.borrow(8e17);
      _fundAndApprove(debtFixture, Borrower, 8e17);
      vm.prank(Borrower);
      debtFixture.market.closeMarket();
      _assertClosedMarket(debtFixture);
      assertEq(
        debtFixture.asset.balanceOf(address(debtFixture.market)),
        1e18,
        'closed debt assets'
      );

      vm.warp(initialBlockTimestamp);
      Fixture memory excessFixture = _newMarket(HooksKind(i));
      _deposit(excessFixture, Holder, 1e18);
      excessFixture.asset.mint(address(excessFixture.market), 5e17);
      uint256 borrowerBalanceBefore = excessFixture.asset.balanceOf(Borrower);
      vm.prank(Borrower);
      excessFixture.market.closeMarket();
      _assertClosedMarket(excessFixture);
      assertEq(
        excessFixture.asset.balanceOf(Borrower),
        borrowerBalanceBefore + 5e17,
        'returned excess assets'
      );

      vm.warp(initialBlockTimestamp);
      Fixture memory transferFailureFixture = _newMarket(HooksKind(i));
      _deposit(transferFailureFixture, Holder, 1e18);
      vm.prank(Borrower);
      transferFailureFixture.market.borrow(8e17);
      vm.prank(Borrower);
      vm.expectRevert(LibERC20.TransferFromFailed.selector);
      transferFailureFixture.market.closeMarket();
      assertFalse(transferFailureFixture.market.isClosed(), 'failed close state');

      vm.warp(initialBlockTimestamp);
      Fixture memory authorityFixture = _newMarket(HooksKind(i));
      vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
      authorityFixture.market.closeMarket();
      vm.prank(Borrower);
      authorityFixture.market.closeMarket();
      vm.prank(Borrower);
      vm.expectRevert(IMarketEventsAndErrors.MarketAlreadyClosed.selector);
      authorityFixture.market.closeMarket();
    }
  }

  function test_closeMarketSettlesPendingAndUnpaidWithdrawalBatches_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory pendingFixture = _newMarket(HooksKind(i));
      _deposit(pendingFixture, Holder, 1e18);
      vm.prank(Borrower);
      pendingFixture.market.borrow(8e17);
      vm.prank(Holder);
      uint32 pendingExpiry = pendingFixture.market.queueFullWithdrawal();
      _fundAndApprove(pendingFixture, Borrower, 8e17);
      vm.prank(Borrower);
      pendingFixture.market.closeMarket();
      WithdrawalBatch memory pendingBatch = pendingFixture.market.getWithdrawalBatch(pendingExpiry);
      assertEq(pendingBatch.scaledAmountBurned, 1e18, 'closed pending batch burn');
      assertEq(pendingBatch.normalizedAmountPaid, 1e18, 'closed pending batch payment');
      assertEq(pendingFixture.market.getUnpaidBatchExpiries().length, 0, 'closed pending unpaid');
      assertEq(pendingFixture.market.previousState().scaledPendingWithdrawals, 0, 'closed pending');

      vm.warp(initialBlockTimestamp);
      Fixture memory mixedFixture = _newMarket(HooksKind(i));
      _deposit(mixedFixture, Holder, 2e18);
      vm.prank(Borrower);
      mixedFixture.market.borrow(16e17);
      vm.prank(Holder);
      uint32 unpaidExpiry = mixedFixture.market.queueWithdrawal(1e18);
      vm.warp(uint256(unpaidExpiry) + 1);
      mixedFixture.market.updateState();
      assertEq(mixedFixture.market.getUnpaidBatchExpiries().length, 1, 'pre-close unpaid');

      vm.prank(Holder);
      uint32 nextExpiry = mixedFixture.market.queueFullWithdrawal();
      _fundAndApprove(mixedFixture, Borrower, 2e18);
      vm.prank(Borrower);
      mixedFixture.market.closeMarket();

      assertEq(mixedFixture.market.getUnpaidBatchExpiries().length, 0, 'post-close unpaid');
      assertEq(
        mixedFixture.market.previousState().scaledPendingWithdrawals,
        0,
        'post-close pending'
      );
      assertEq(
        mixedFixture.market.getWithdrawalBatch(unpaidExpiry).scaledAmountBurned,
        1e18,
        'closed unpaid batch burn'
      );
      assertEq(
        mixedFixture.market.getWithdrawalBatch(nextExpiry).scaledAmountBurned,
        1e18,
        'closed next batch burn'
      );

      vm.warp(initialBlockTimestamp);
      Fixture memory failedFixture = _newMarket(HooksKind(i));
      _deposit(failedFixture, Holder, 1e18);
      vm.prank(Borrower);
      failedFixture.market.borrow(8e17);
      vm.prank(Holder);
      uint32 failedExpiry = failedFixture.market.queueFullWithdrawal();
      vm.warp(uint256(failedExpiry) + 1);
      failedFixture.market.updateState();
      assertEq(failedFixture.market.getUnpaidBatchExpiries().length, 1, 'failed pre-close unpaid');
      vm.prank(Borrower);
      vm.expectRevert(LibERC20.TransferFromFailed.selector);
      failedFixture.market.closeMarket();
      assertFalse(failedFixture.market.isClosed(), 'failed unpaid close state');
      assertEq(failedFixture.market.getUnpaidBatchExpiries().length, 1, 'failed unpaid retained');
    }
  }

  function test_closeMarketCreatesFreshBatchKeyAtExactExpiry_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newMarket(HooksKind(i));
      _deposit(fixture, Holder, 1e18);
      vm.prank(Holder);
      uint32 expiry = fixture.market.queueFullWithdrawal();

      vm.warp(expiry);
      vm.expectEmit(address(fixture.market));
      emit IMarketEventsAndErrors.WithdrawalBatchCreated(uint256(expiry) + 1);
      vm.prank(Borrower);
      fixture.market.closeMarket();

      assertEq(fixture.market.previousState().pendingWithdrawalExpiry, expiry + 1, 'fresh expiry');
      assertEq(fixture.market.getWithdrawalBatch(expiry).scaledAmountBurned, 1e18, 'closed batch');
    }
  }

  function test_closedMarketWithdrawalRejectsFallbackBatchKeyCollision_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newMarket(HooksKind(i));
      _deposit(fixture, Holder, 1e18);
      _deposit(fixture, Recipient, 1e18);
      vm.prank(Holder);
      uint32 oldExpiry = fixture.market.queueFullWithdrawal();

      vm.warp(uint256(oldExpiry) - 1 hours);
      _fundAndApprove(fixture, Borrower, 1e18);
      vm.prank(Borrower);
      fixture.market.closeMarket();
      fixture.market.executeWithdrawal(Holder, oldExpiry);

      uint32 fallbackExpiry = oldExpiry + 1;
      _forceWithdrawalBatchExists(fixture.market, fallbackExpiry);
      bytes32 stateHash = keccak256(abi.encode(fixture.market.previousState()));
      uint256 recipientBalance = fixture.market.scaledBalanceOf(Recipient);

      vm.warp(oldExpiry);
      vm.prank(Recipient);
      vm.expectRevert(IMarketEventsAndErrors.WithdrawalBatchKeyAlreadyExists.selector);
      fixture.market.queueFullWithdrawal();

      assertEq(keccak256(abi.encode(fixture.market.previousState())), stateHash, 'collision state');
      assertEq(fixture.market.scaledBalanceOf(Recipient), recipientBalance, 'collision balance');
    }
  }

  function test_closedMarketWithdrawalUsesFreshFallbackBatchKey_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newMarket(HooksKind(i));
      _deposit(fixture, Holder, 1e18);
      _deposit(fixture, Recipient, 1e18);
      vm.prank(Holder);
      uint32 oldExpiry = fixture.market.queueFullWithdrawal();

      vm.warp(uint256(oldExpiry) - 1 hours);
      _fundAndApprove(fixture, Borrower, 1e18);
      vm.prank(Borrower);
      fixture.market.closeMarket();
      fixture.market.executeWithdrawal(Holder, oldExpiry);

      bytes32 oldBatchHash = keccak256(abi.encode(fixture.market.getWithdrawalBatch(oldExpiry)));
      bytes32 oldStatusHash = keccak256(
        abi.encode(fixture.market.getAccountWithdrawalStatus(Holder, oldExpiry))
      );
      uint256 recipientScaledBalance = fixture.market.scaledBalanceOf(Recipient);
      uint256 recipientAssetBalance = fixture.asset.balanceOf(Recipient);

      vm.warp(oldExpiry);
      vm.prank(Recipient);
      uint32 newExpiry = fixture.market.queueFullWithdrawal();

      assertEq(newExpiry, oldExpiry + 1, 'fallback expiry');
      assertEq(
        fixture.market.previousState().pendingWithdrawalExpiry,
        newExpiry,
        'fallback pending'
      );
      assertEq(
        keccak256(abi.encode(fixture.market.getWithdrawalBatch(oldExpiry))),
        oldBatchHash,
        'fallback old batch'
      );
      assertEq(
        keccak256(abi.encode(fixture.market.getAccountWithdrawalStatus(Holder, oldExpiry))),
        oldStatusHash,
        'fallback old status'
      );
      WithdrawalBatch memory newBatch = fixture.market.getWithdrawalBatch(newExpiry);
      assertEq(newBatch.scaledTotalAmount, recipientScaledBalance, 'fallback scaled total');
      assertEq(newBatch.scaledAmountBurned, recipientScaledBalance, 'fallback scaled burn');
      assertEq(fixture.market.scaledBalanceOf(Recipient), 0, 'fallback lender balance');

      vm.warp(uint256(newExpiry) + 1);
      uint256 payout = fixture.market.executeWithdrawal(Recipient, newExpiry);
      assertEq(
        fixture.asset.balanceOf(Recipient),
        recipientAssetBalance + payout,
        'fallback payout'
      );
    }
  }

  function test_closedMarketWithdrawalRejectsFallbackBatchKeyOverflow_AcrossHookKinds() external {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      _deposit(fixture, Recipient, 1e18);
      vm.prank(Borrower);
      fixture.market.closeMarket();

      uint32 maximumExpiry = type(uint32).max;
      _forceWithdrawalBatchExists(fixture.market, maximumExpiry);
      vm.warp(maximumExpiry);
      bytes32 stateHash = keccak256(abi.encode(fixture.market.previousState()));
      uint256 recipientBalance = fixture.market.scaledBalanceOf(Recipient);

      vm.prank(Recipient);
      vm.expectRevert(_arithmeticPanic());
      fixture.market.queueFullWithdrawal();

      assertEq(keccak256(abi.encode(fixture.market.previousState())), stateHash, 'overflow state');
      assertEq(fixture.market.scaledBalanceOf(Recipient), recipientBalance, 'overflow balance');
    }
  }

  function test_openMarketWithdrawalRejectsExpiryOverflowWithoutMutatingState() external {
    vm.warp(uint256(type(uint32).max) - 12 hours);
    Fixture memory fixture = _newWithdrawalMarket(HooksKind.OpenTerm);
    _deposit(fixture, Holder, 1e18);

    bytes32 stateHash = keccak256(abi.encode(fixture.market.previousState()));
    uint256 scaledBalance = fixture.market.scaledBalanceOf(Holder);

    vm.prank(Holder);
    vm.expectRevert(_arithmeticPanic());
    fixture.market.queueFullWithdrawal();

    assertEq(keccak256(abi.encode(fixture.market.previousState())), stateHash, 'overflow state');
    assertEq(fixture.market.scaledBalanceOf(Holder), scaledBalance, 'overflow balance');
  }

  function test_rescueTokensAuthenticatesBorrowerAndProtectsMarketAssets_AcrossHookKinds()
    external
  {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newMarket(HooksKind(i));
      MockERC20 stray = MockERC20(
        _deployCode(
          'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
          abi.encode('Stray', 'STRAY', uint8(18))
        )
      );
      stray.mint(address(fixture.market), 1e18);

      vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
      fixture.market.rescueTokens(address(stray));

      vm.startPrank(Borrower);
      vm.expectRevert(IMarketEventsAndErrors.BadRescueAsset.selector);
      fixture.market.rescueTokens(address(fixture.market));
      vm.expectRevert(IMarketEventsAndErrors.BadRescueAsset.selector);
      fixture.market.rescueTokens(address(fixture.asset));
      fixture.market.rescueTokens(address(stray));
      vm.stopPrank();

      assertEq(stray.balanceOf(Borrower), 1e18, 'rescued balance');
      assertEq(stray.balanceOf(address(fixture.market)), 0, 'market stray balance');
    }
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

      Fixture memory roundingFixture = _newMarket(HooksKind(i));
      _mintMarketTokens(roundingFixture, Holder, 1e18);
      vm.warp(vm.getBlockTimestamp() + 1 days);
      vm.prank(Holder);
      roundingFixture.market.approve(Delegate, 1);
      vm.prank(Delegate);
      vm.expectRevert(IMarketEventsAndErrors.NullTransferAmount.selector);
      roundingFixture.market.transferFrom(Holder, Recipient, 1);
      assertEq(roundingFixture.market.allowance(Holder, Delegate), 1, 'rounded allowance');
      assertEq(roundingFixture.market.scaledBalanceOf(Recipient), 0, 'rounded recipient');
    }
  }

  function test_queueWithdrawalEntrypointsRejectInvalidAmounts_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));

      vm.startPrank(Holder);
      vm.expectRevert(IMarketEventsAndErrors.NullBurnAmount.selector);
      fixture.market.queueWithdrawal(0);
      vm.expectRevert(IMarketEventsAndErrors.NullBurnAmount.selector);
      fixture.market.queueWithdrawalScaled(0);
      vm.expectRevert(IMarketEventsAndErrors.NullBurnAmount.selector);
      fixture.market.queueFullWithdrawal();
      vm.expectRevert(_arithmeticPanic());
      fixture.market.queueWithdrawalScaled(uint256(type(uint104).max) + 1);
      vm.stopPrank();

      _deposit(fixture, Holder, 1e18);
      bytes32 stateHash = keccak256(abi.encode(fixture.market.currentState()));
      uint256 scaledBalance = fixture.market.scaledBalanceOf(Holder);

      vm.prank(Holder);
      vm.expectRevert(_arithmeticPanic());
      fixture.market.queueWithdrawal(1e18 + 1);
      vm.prank(Holder);
      vm.expectRevert(_arithmeticPanic());
      fixture.market.queueWithdrawalScaled(scaledBalance + 1);

      assertEq(
        keccak256(abi.encode(fixture.market.currentState())),
        stateHash,
        'failed queue state'
      );
      assertEq(fixture.market.scaledBalanceOf(Holder), scaledBalance, 'failed queue balance');
    }
  }

  function test_queueWithdrawalEntrypointsShareAndAccumulateOneBatch_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      _deposit(fixture, Holder, 3e18);
      _deposit(fixture, Recipient, 2e18);

      vm.prank(Holder);
      uint32 expiry = fixture.market.queueWithdrawal(1e18);
      vm.prank(Holder);
      assertEq(fixture.market.queueWithdrawalScaled(1e18), expiry, 'scaled batch expiry');
      vm.prank(Holder);
      assertEq(fixture.market.queueFullWithdrawal(), expiry, 'full batch expiry');
      vm.prank(Recipient);
      assertEq(fixture.market.queueFullWithdrawal(), expiry, 'second lender expiry');

      _assertBatch(fixture, expiry, 5e18, 5e18, 5e18);
      AccountWithdrawalStatus memory holderStatus = fixture.market.getAccountWithdrawalStatus(
        Holder,
        expiry
      );
      AccountWithdrawalStatus memory recipientStatus = fixture.market.getAccountWithdrawalStatus(
        Recipient,
        expiry
      );
      assertEq(holderStatus.scaledAmount, 3e18, 'holder status');
      assertEq(recipientStatus.scaledAmount, 2e18, 'recipient status');
      MarketState memory state = fixture.market.previousState();
      assertEq(state.scaledPendingWithdrawals, 0, 'pending withdrawal scale');
      assertEq(state.scaledTotalSupply, 0, 'remaining supply');
      assertEq(state.normalizedUnclaimedWithdrawals, 5e18, 'unclaimed withdrawals');
      assertEq(fixture.market.scaledBalanceOf(Holder), 0, 'holder balance');
      assertEq(fixture.market.scaledBalanceOf(Recipient), 0, 'recipient balance');
    }
  }

  function test_queueWithdrawalTracksLiquidityShortfall_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      _deposit(fixture, Holder, 1e18);
      _borrow(fixture, 8e17);
      vm.prank(Holder);
      uint32 expiry = fixture.market.queueFullWithdrawal();

      _assertBatch(fixture, expiry, 1e18, 2e17, 2e17);
      MarketState memory state = fixture.market.previousState();
      assertTrue(state.isDelinquent, 'shortfall delinquency');
      assertEq(state.timeDelinquent, 0, 'shortfall delinquency time');
      assertEq(state.scaledPendingWithdrawals, 8e17, 'shortfall pending');
      assertEq(state.scaledTotalSupply, 8e17, 'shortfall supply');
      assertEq(state.normalizedUnclaimedWithdrawals, 2e17, 'shortfall unclaimed');
    }
  }

  function test_queueScaledUsesLiveScaleFactorAndMatchesFullWithdrawal_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Options memory options = _withdrawalOptions(HooksKind(i));
      options.annualInterestBips = 1_000;
      Fixture memory fullFixture = _newMarket(options);
      Fixture memory scaledFixture = _newMarket(options);
      _deposit(fullFixture, Holder, 100e18);
      _deposit(scaledFixture, Holder, 100e18);
      _borrow(fullFixture, 60e18);
      _borrow(scaledFixture, 60e18);
      vm.warp(initialBlockTimestamp + 30 days);

      uint256 scaledBalance = scaledFixture.market.scaledBalanceOf(Holder);
      assertTrue(fullFixture.market.currentState().scaleFactor > RAY, 'live scale factor');
      vm.prank(Holder);
      uint32 fullExpiry = fullFixture.market.queueFullWithdrawal();
      vm.prank(Holder);
      uint32 scaledExpiry = scaledFixture.market.queueWithdrawalScaled(scaledBalance);

      assertEq(scaledExpiry, fullExpiry, 'equivalent expiry');
      assertEq(
        keccak256(abi.encode(scaledFixture.market.previousState())),
        keccak256(abi.encode(fullFixture.market.previousState())),
        'equivalent state'
      );
      assertEq(
        keccak256(abi.encode(scaledFixture.market.getWithdrawalBatch(scaledExpiry))),
        keccak256(abi.encode(fullFixture.market.getWithdrawalBatch(fullExpiry))),
        'equivalent batch'
      );
      assertEq(
        keccak256(
          abi.encode(scaledFixture.market.getAccountWithdrawalStatus(Holder, scaledExpiry))
        ),
        keccak256(abi.encode(fullFixture.market.getAccountWithdrawalStatus(Holder, fullExpiry))),
        'equivalent account status'
      );
    }
  }

  function test_closedMarketWithdrawalsDrainAcrossFreshBatches_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      _deposit(fixture, Holder, 6e18);
      _borrow(fixture, 3e18);

      vm.prank(Holder);
      uint32 firstExpiry = fixture.market.queueWithdrawal(2e18);
      vm.warp(uint256(firstExpiry) + 1);
      fixture.market.updateState();
      vm.prank(Holder);
      uint32 secondExpiry = fixture.market.queueWithdrawal(2e18);
      vm.warp(uint256(secondExpiry) + 1);
      fixture.market.updateState();

      uint256 remainingDebt = fixture.market.totalDebts() - fixture.market.totalAssets();
      _fundAndApprove(fixture, Borrower, remainingDebt);
      vm.prank(Borrower);
      fixture.market.closeMarket();

      vm.prank(Holder);
      uint32 thirdExpiry = fixture.market.queueWithdrawal(1e18);
      vm.warp(uint256(thirdExpiry) + 1);
      fixture.market.updateState();
      vm.prank(Holder);
      uint32 fourthExpiry = fixture.market.queueFullWithdrawal();
      vm.warp(uint256(fourthExpiry) + 1);
      fixture.market.updateState();

      MarketState memory state = fixture.market.currentState();
      assertTrue(state.isClosed, 'closed drain state');
      assertFalse(state.isDelinquent, 'closed drain delinquency');
      assertEq(state.scaledPendingWithdrawals, 0, 'closed drain pending');
      assertEq(state.scaledTotalSupply, 0, 'closed drain supply');
      assertEq(fixture.market.scaledBalanceOf(Holder), 0, 'closed drain balance');
      assertEq(fixture.market.getUnpaidBatchExpiries().length, 0, 'closed drain unpaid');
    }
  }

  function test_executeWithdrawalRejectsPendingAndDuplicateThenPays_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      _deposit(fixture, Holder, 1e18);
      vm.prank(Holder);
      uint32 expiry = fixture.market.queueWithdrawal(6e17);

      vm.expectRevert(IMarketEventsAndErrors.WithdrawalBatchNotExpired.selector);
      fixture.market.executeWithdrawal(Holder, expiry);
      vm.warp(uint256(expiry) + 1);
      assertEq(fixture.market.getAvailableWithdrawalAmount(Holder, expiry), 6e17, 'available');
      uint256 payout = fixture.market.executeWithdrawal(Holder, expiry);
      assertEq(payout, 6e17, 'payout');
      assertEq(fixture.asset.balanceOf(Holder), 6e17, 'holder assets');
      assertEq(
        fixture.market.getAccountWithdrawalStatus(Holder, expiry).normalizedAmountWithdrawn,
        6e17,
        'withdrawn status'
      );

      vm.expectRevert(IMarketEventsAndErrors.NullWithdrawalAmount.selector);
      fixture.market.executeWithdrawal(Holder, expiry);
    }
  }

  function test_executeWithdrawalAllowsClosedMarketBeforeAndAfterExpiry_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory earlyFixture = _newWithdrawalMarket(HooksKind(i));
      _deposit(earlyFixture, Holder, 1e18);
      vm.prank(Holder);
      uint32 earlyExpiry = earlyFixture.market.queueFullWithdrawal();
      vm.prank(Borrower);
      earlyFixture.market.closeMarket();
      assertEq(earlyFixture.market.executeWithdrawal(Holder, earlyExpiry), 1e18, 'early payout');

      vm.warp(initialBlockTimestamp);
      Fixture memory expiredFixture = _newWithdrawalMarket(HooksKind(i));
      _deposit(expiredFixture, Holder, 1e18);
      vm.prank(Holder);
      uint32 expiredExpiry = expiredFixture.market.queueFullWithdrawal();
      vm.prank(Borrower);
      expiredFixture.market.closeMarket();
      vm.warp(uint256(expiredExpiry) + 1);
      assertEq(
        expiredFixture.market.executeWithdrawal(Holder, expiredExpiry),
        1e18,
        'expired payout'
      );
    }
  }

  function test_executeWithdrawalsValidatesAndAtomicallyPaysBatches_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      address[] memory mismatchedAccounts = new address[](1);
      uint32[] memory mismatchedExpiries = new uint32[](2);
      vm.expectRevert(IMarketEventsAndErrors.InvalidArrayLength.selector);
      fixture.market.executeWithdrawals(mismatchedAccounts, mismatchedExpiries);

      _deposit(fixture, Holder, 1e18);
      _deposit(fixture, Recipient, 1e18);
      vm.prank(Holder);
      uint32 firstExpiry = fixture.market.queueWithdrawal(5e17);
      vm.prank(Recipient);
      fixture.market.queueWithdrawal(5e17);
      vm.warp(uint256(firstExpiry) + 1);
      vm.prank(Holder);
      uint32 secondExpiry = fixture.market.queueFullWithdrawal();
      vm.prank(Recipient);
      fixture.market.queueFullWithdrawal();
      vm.warp(uint256(secondExpiry) + 1);

      address[] memory accounts = new address[](4);
      accounts[0] = Holder;
      accounts[1] = Recipient;
      accounts[2] = Holder;
      accounts[3] = Recipient;
      uint32[] memory expiries = new uint32[](4);
      expiries[0] = firstExpiry;
      expiries[1] = firstExpiry;
      expiries[2] = secondExpiry;
      expiries[3] = secondExpiry;
      uint256[] memory payouts = fixture.market.executeWithdrawals(accounts, expiries);
      for (uint256 j; j < payouts.length; j++) {
        assertEq(payouts[j], 5e17, 'batch payout');
      }
      assertEq(fixture.asset.balanceOf(Holder), 1e18, 'holder batch assets');
      assertEq(fixture.asset.balanceOf(Recipient), 1e18, 'recipient batch assets');

      vm.warp(initialBlockTimestamp);
      Fixture memory duplicateFixture = _newWithdrawalMarket(HooksKind(i));
      _deposit(duplicateFixture, Holder, 1e18);
      vm.prank(Holder);
      uint32 duplicateExpiry = duplicateFixture.market.queueFullWithdrawal();
      vm.warp(uint256(duplicateExpiry) + 1);
      address[] memory duplicateAccounts = new address[](2);
      duplicateAccounts[0] = Holder;
      duplicateAccounts[1] = Holder;
      uint32[] memory duplicateExpiries = new uint32[](2);
      duplicateExpiries[0] = duplicateExpiry;
      duplicateExpiries[1] = duplicateExpiry;
      vm.expectRevert(IMarketEventsAndErrors.NullWithdrawalAmount.selector);
      duplicateFixture.market.executeWithdrawals(duplicateAccounts, duplicateExpiries);
      assertEq(duplicateFixture.asset.balanceOf(Holder), 0, 'atomic payout rollback');
      assertEq(
        duplicateFixture
          .market
          .getAccountWithdrawalStatus(Holder, duplicateExpiry)
          .normalizedAmountWithdrawn,
        0,
        'atomic status rollback'
      );
    }
  }

  function test_executeSanctionedWithdrawalsRouteToEscrow_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      _deposit(fixture, Holder, 1e18);
      _deposit(fixture, Recipient, 1e18);
      vm.prank(Holder);
      uint32 expiry = fixture.market.queueWithdrawal(5e17);
      vm.prank(Recipient);
      fixture.market.queueWithdrawal(5e17);
      vm.warp(uint256(expiry) + 1);
      fixture.sentinel.setSanctioned(Holder, true);

      address[] memory accounts = new address[](2);
      accounts[0] = Holder;
      accounts[1] = Recipient;
      uint32[] memory expiries = new uint32[](2);
      expiries[0] = expiry;
      expiries[1] = expiry;
      fixture.market.executeWithdrawals(accounts, expiries);

      assertEq(
        fixture.asset.balanceOf(fixture.sentinel.EscrowAddress()),
        5e17,
        'escrowed withdrawal'
      );
      assertEq(fixture.asset.balanceOf(Recipient), 5e17, 'ordinary withdrawal');
      assertEq(fixture.sentinel.createEscrowCalls(), 1, 'escrow calls');
    }
  }

  function test_processUnpaidBatchHandlesNoLiquidityAndOneWeiBoundary_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory emptyFixture = _newWithdrawalMarket(HooksKind(i));
      emptyFixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);

      vm.warp(initialBlockTimestamp);
      Options memory options = _withdrawalOptions(HooksKind(i));
      options.reserveRatioBips = 0;
      options.annualInterestBips = 1_000;
      Fixture memory boundaryFixture = _newMarket(options);
      _deposit(boundaryFixture, Holder, 1e18);
      _borrow(boundaryFixture, 1e18);
      vm.prank(Holder);
      uint32 expiry = boundaryFixture.market.queueFullWithdrawal();
      vm.warp(uint256(expiry) + 1);
      boundaryFixture.market.updateState();
      boundaryFixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      assertEq(boundaryFixture.market.getUnpaidBatchExpiries().length, 1, 'no liquidity');

      boundaryFixture.asset.mint(address(boundaryFixture.market), 1);
      boundaryFixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      _assertBatch(boundaryFixture, expiry, 1e18, 1, 1);
      assertEq(boundaryFixture.market.getUnpaidBatchExpiries().length, 1, 'boundary unpaid');
    }
  }

  function test_processUnpaidBatchHandlesLargeAndSubScaledLiquidity_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Options memory largeOptions = _withdrawalOptions(HooksKind(i));
      largeOptions.reserveRatioBips = 0;
      Fixture memory largeFixture = _newMarket(largeOptions);
      _deposit(largeFixture, Holder, 1e18);
      _borrow(largeFixture, 1e18);
      vm.prank(Holder);
      uint32 largeExpiry = largeFixture.market.queueFullWithdrawal();
      vm.warp(uint256(largeExpiry) + 1);
      largeFixture.market.updateState();
      largeFixture.asset.mint(address(largeFixture.market), type(uint256).max / RAY);
      largeFixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      _assertBatch(largeFixture, largeExpiry, 1e18, 1e18, 1e18);
      assertEq(largeFixture.market.getUnpaidBatchExpiries().length, 0, 'large payment');

      vm.warp(initialBlockTimestamp);
      Options memory dustOptions = _withdrawalOptions(HooksKind(i));
      dustOptions.reserveRatioBips = 0;
      dustOptions.annualInterestBips = 10_000;
      dustOptions.withdrawalBatchDuration = 365 days;
      Fixture memory dustFixture = _newMarket(dustOptions);
      _deposit(dustFixture, Holder, 1e18);
      _borrow(dustFixture, 1e18);
      vm.prank(Holder);
      uint32 dustExpiry = dustFixture.market.queueFullWithdrawal();
      vm.warp(uint256(dustExpiry) + 1);
      dustFixture.market.updateState();
      vm.warp(vm.getBlockTimestamp() + 730 days);
      dustFixture.asset.mint(address(dustFixture.market), 1);
      vm.recordLogs();
      dustFixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      _assertNoWithdrawalPayment(vm.getRecordedLogs());
      _assertBatch(dustFixture, dustExpiry, 1e18, 0, 0);
      assertEq(dustFixture.market.getUnpaidBatchExpiries().length, 1, 'dust unpaid');
    }
  }

  function test_processUnpaidBatchProgressesPartialAndFullPayments_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      uint32 expiry = _makeUnpaidBatch(fixture, Holder);
      _assertBatch(fixture, expiry, 1e18, 2e17, 2e17);

      fixture.asset.mint(address(fixture.market), 4e17);
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      _assertBatch(fixture, expiry, 1e18, 6e17, 6e17);
      assertEq(fixture.market.getUnpaidBatchExpiries().length, 1, 'partial unpaid');

      fixture.asset.mint(address(fixture.market), 4e17);
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      _assertBatch(fixture, expiry, 1e18, 1e18, 1e18);
      assertEq(fixture.market.getUnpaidBatchExpiries().length, 0, 'full paid');
    }
  }

  function test_repayAndProcessHonorsLimitsAndAvailableLiquidity_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory limitFixture = _newWithdrawalMarket(HooksKind(i));
      _makeTwoUnpaidBatches(limitFixture, Holder);
      limitFixture.asset.mint(address(limitFixture.market), 2e18);
      limitFixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 0);
      assertEq(limitFixture.market.getUnpaidBatchExpiries().length, 2, 'zero batch limit');
      limitFixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      assertEq(limitFixture.market.getUnpaidBatchExpiries().length, 1, 'one batch limit');

      vm.warp(initialBlockTimestamp);
      Fixture memory partialFixture = _newWithdrawalMarket(HooksKind(i));
      _makeTwoUnpaidBatches(partialFixture, Holder);
      partialFixture.asset.mint(address(partialFixture.market), 7e17);
      partialFixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 10);
      assertEq(partialFixture.market.getUnpaidBatchExpiries().length, 1, 'second batch partial');

      vm.warp(initialBlockTimestamp);
      Fixture memory completeFixture = _newWithdrawalMarket(HooksKind(i));
      _makeTwoUnpaidBatches(completeFixture, Holder);
      completeFixture.asset.mint(address(completeFixture.market), 16e17);
      completeFixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 10);
      assertEq(completeFixture.market.getUnpaidBatchExpiries().length, 0, 'both batches paid');
    }
  }

  function test_repayAndProcessDrainsLargeFifoQueueInBoundedChunksThenCloses() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();
    _assertLargeFifoDrainToClose(false);

    vm.warp(initialBlockTimestamp);
    _assertLargeFifoDrainToClose(true);
  }

  function test_repayAndProcessIncludesRepayAndRejectsClosedMarket_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      _makeTwoUnpaidBatches(fixture, Holder);
      _fundAndApprove(fixture, Recipient, 16e17);
      vm.expectEmit(address(fixture.market));
      emit IMarketEventsAndErrors.DebtRepaid(Recipient, 16e17);
      vm.prank(Recipient);
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(16e17, 10);
      assertEq(fixture.market.getUnpaidBatchExpiries().length, 0, 'repay batches paid');

      vm.warp(initialBlockTimestamp);
      Fixture memory closedFixture = _newWithdrawalMarket(HooksKind(i));
      vm.prank(Borrower);
      closedFixture.market.closeMarket();
      _fundAndApprove(closedFixture, Recipient, 1e18);
      vm.prank(Recipient);
      vm.expectRevert(IMarketEventsAndErrors.RepayToClosedMarket.selector);
      closedFixture.market.repayAndProcessUnpaidWithdrawalBatches(1e18, 10);
      assertEq(closedFixture.asset.balanceOf(Recipient), 1e18, 'closed repay rollback');
    }
  }

  function test_withdrawalViewsReflectMissingPendingPaidAndUnpaidBatches_AcrossHookKinds()
    external
  {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      _assertBatch(fixture, 0, 0, 0, 0);
      _deposit(fixture, Holder, 1e18);
      _borrow(fixture, 8e17);
      vm.prank(Holder);
      uint32 expiry = fixture.market.queueFullWithdrawal();
      _assertBatch(fixture, expiry, 1e18, 2e17, 2e17);
      assertEq(fixture.market.getUnpaidBatchExpiries().length, 0, 'pending unpaid list');

      vm.warp(uint256(expiry) + 1);
      _assertBatch(fixture, expiry, 1e18, 2e17, 2e17);
      fixture.market.updateState();
      assertEq(fixture.market.getUnpaidBatchExpiries().length, 1, 'expired unpaid list');

      vm.warp(initialBlockTimestamp);
      Fixture memory paidFixture = _newWithdrawalMarket(HooksKind(i));
      _deposit(paidFixture, Holder, 2e18);
      vm.prank(Holder);
      uint32 paidExpiry = paidFixture.market.queueWithdrawal(1e18);
      _assertBatch(paidFixture, paidExpiry, 1e18, 1e18, 1e18);
      vm.warp(uint256(paidExpiry) + 1);
      paidFixture.market.updateState();
      assertEq(paidFixture.market.getUnpaidBatchExpiries().length, 0, 'paid unpaid list');
    }
  }

  function test_accountWithdrawalViewsTrackPartialAndCompleteClaims_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      uint32 expiry = _makeUnpaidBatch(fixture, Holder);
      AccountWithdrawalStatus memory status = fixture.market.getAccountWithdrawalStatus(
        Holder,
        expiry
      );
      assertEq(status.scaledAmount, 1e18, 'initial status scale');
      assertEq(status.normalizedAmountWithdrawn, 0, 'initial status withdrawn');
      assertEq(
        fixture.market.getAvailableWithdrawalAmount(Holder, expiry),
        2e17,
        'first available'
      );
      assertEq(fixture.market.executeWithdrawal(Holder, expiry), 2e17, 'first claim');

      fixture.asset.mint(address(fixture.market), 8e17);
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      assertEq(fixture.market.getAvailableWithdrawalAmount(Holder, expiry), 8e17, 'next available');
      assertEq(fixture.market.executeWithdrawal(Holder, expiry), 8e17, 'second claim');
      status = fixture.market.getAccountWithdrawalStatus(Holder, expiry);
      assertEq(status.scaledAmount, 1e18, 'final status scale');
      assertEq(status.normalizedAmountWithdrawn, 1e18, 'final status withdrawn');
      assertEq(fixture.asset.balanceOf(Holder), 1e18, 'complete claim balance');
    }
  }

  function test_availableWithdrawalRejectsPendingAndReadsExpiredView_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      _deposit(fixture, Holder, 1e18);
      _borrow(fixture, 8e17);
      vm.prank(Holder);
      uint32 expiry = fixture.market.queueFullWithdrawal();

      vm.expectRevert(IMarketEventsAndErrors.WithdrawalBatchNotExpired.selector);
      fixture.market.getAvailableWithdrawalAmount(Holder, expiry);
      vm.warp(uint256(expiry) + 1);
      assertEq(
        fixture.market.getAvailableWithdrawalAmount(Holder, expiry),
        2e17,
        'expired view available'
      );
      fixture.market.updateState();
      assertEq(
        fixture.market.getAvailableWithdrawalAmount(Holder, expiry),
        2e17,
        'stored unpaid available'
      );
    }
  }

  function test_pendingBatchUsesIncomingLiquidityBeforeExpiry_AcrossHookKinds() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();

    for (uint256 i; i < 2; i++) {
      vm.warp(initialBlockTimestamp);
      Fixture memory fixture = _newWithdrawalMarket(HooksKind(i));
      _deposit(fixture, Holder, 1e18);
      _borrow(fixture, 8e17);
      vm.prank(Holder);
      uint32 expiry = fixture.market.queueFullWithdrawal();
      _assertBatch(fixture, expiry, 1e18, 2e17, 2e17);

      fixture.asset.mint(address(fixture.market), 8e17);
      _assertBatch(fixture, expiry, 1e18, 1e18, 1e18);
      fixture.market.updateState();
      _assertBatch(fixture, expiry, 1e18, 1e18, 1e18);
      assertEq(fixture.market.previousState().scaledPendingWithdrawals, 0, 'pending paid');
      assertEq(fixture.market.previousState().normalizedUnclaimedWithdrawals, 1e18, 'reserved');
    }
  }

  // ========================================================================== //
  //                         Revolving market behavior                          //
  // ========================================================================== //

  function test_revolvingConstructorValidatesAndStoresCommitmentFee() external {
    Options memory options = _revolvingOptions(200, 1_000, 0);
    Fixture memory fixture = _newMarket(options);
    IWildcatMarketRevolving revolvingMarket = _revolving(fixture);
    assertEq(revolvingMarket.commitmentFeeBips(), 200, 'commitment fee');
    assertEq(revolvingMarket.drawnAmount(), 0, 'initial drawn amount');
    assertEq(fixture.market.borrowerPrincipal(), Borrower, 'borrower principal');

    MarketParameters memory parameters = _buildMarketParameters(
      fixture,
      options,
      fixture.market.hooks()
    );
    fixture.factory.setRevolvingMarketCommitmentFeeResponse(type(uint16).max, 32, false);
    WildcatMarket maximumFeeMarket = _deployMarketFromParameters(fixture, parameters, true);
    assertEq(
      IWildcatMarketRevolving(address(maximumFeeMarket)).commitmentFeeBips(),
      type(uint16).max,
      'maximum commitment fee'
    );

    fixture.factory.setRevolvingMarketCommitmentFeeResponse(200, 31, false);
    vm.expectRevert();
    _deployStoredMarket(fixture, true);

    fixture.factory.setRevolvingMarketCommitmentFeeResponse((uint256(1) << 16) | 200, 32, false);
    vm.expectRevert();
    _deployStoredMarket(fixture, true);

    uint256 errorWord = uint256(uint32(RevolvingFeeReadFailed.selector)) << 224;
    fixture.factory.setRevolvingMarketCommitmentFeeResponse(errorWord, 4, true);
    vm.expectRevert(RevolvingFeeReadFailed.selector);
    _deployStoredMarket(fixture, true);
  }

  function test_revolvingDrawnAmountTracksBorrowAndSaturatingRepayment() external {
    Fixture memory fixture = _newMarket(_revolvingOptions(200, 1_000, 0));
    IWildcatMarketRevolving revolvingMarket = _revolving(fixture);
    _deposit(fixture, Holder, 1_000e18);
    _approveBorrower(fixture);

    vm.expectEmit(address(fixture.market));
    emit IWildcatMarketRevolving.DrawnAmountUpdated(0, 400e18);
    vm.prank(Borrower);
    fixture.market.borrow(400e18);
    assertEq(revolvingMarket.drawnAmount(), 400e18, 'drawn after borrow');

    vm.expectEmit(address(fixture.market));
    emit IWildcatMarketRevolving.DrawnAmountUpdated(400e18, 150e18);
    vm.prank(Borrower);
    fixture.market.repay(250e18);
    assertEq(revolvingMarket.drawnAmount(), 150e18, 'drawn after partial repay');

    fixture.asset.mint(Borrower, 1_000e18);
    vm.expectEmit(address(fixture.market));
    emit IWildcatMarketRevolving.DrawnAmountUpdated(150e18, 0);
    vm.prank(Borrower);
    fixture.market.repay(1_000e18);
    assertEq(revolvingMarket.drawnAmount(), 0, 'drawn after saturated repay');
  }

  function test_revolvingDrawnAmountClampsOverRepayDonationAndLargeValues() external {
    Fixture memory fixture = _newMarket(_revolvingOptions(200, 1_000, 0));
    IWildcatMarketRevolving revolvingMarket = _revolving(fixture);
    _deposit(fixture, Holder, 1_000e18);
    _approveBorrower(fixture);
    vm.prank(Borrower);
    fixture.market.borrow(400e18);

    fixture.asset.mint(Borrower, 200e18);
    vm.expectEmit(address(fixture.market));
    emit IWildcatMarketRevolving.DrawnAmountUpdated(400e18, 0);
    vm.prank(Borrower);
    fixture.market.repay(600e18);

    vm.expectEmit(address(fixture.market));
    emit IWildcatMarketRevolving.DrawnAmountUpdated(0, 200e18);
    vm.prank(Borrower);
    fixture.market.borrow(400e18);
    assertEq(revolvingMarket.drawnAmount(), 200e18, 'drawn after surplus borrow');

    Options memory largeOptions = _revolvingOptions(200, 1_000, 0);
    largeOptions.maxTotalSupply = 1_000;
    Fixture memory largeFixture = _newMarket(largeOptions);
    _deposit(largeFixture, Holder, 1_000);
    vm.prank(Borrower);
    largeFixture.market.borrow(500);
    vm.prank(Borrower);
    largeFixture.asset.transfer(address(largeFixture.market), 500);
    largeFixture.asset.mint(address(largeFixture.market), type(uint256).max - 1_000);

    vm.prank(Borrower);
    largeFixture.market.borrow(type(uint256).max - 499);
    assertEq(largeFixture.market.totalAssets(), 499, 'large assets after borrow');
    assertEq(largeFixture.market.totalDebts(), 1_000, 'large debt after borrow');
    assertEq(_revolving(largeFixture).drawnAmount(), 501, 'large drawn clamp');
  }

  function test_revolvingRepayConsumesInterestBeforePrincipalAcrossBothEntrypoints() external {
    uint256 initialTimestamp = vm.getBlockTimestamp();
    for (uint256 i; i < 2; i++) {
      vm.warp(initialTimestamp);
      Fixture memory fixture = _newMarket(_revolvingOptions(200, 1_000, 0));
      IWildcatMarketRevolving revolvingMarket = _revolving(fixture);
      _deposit(fixture, Holder, 1_000e18);
      _approveBorrower(fixture);
      vm.prank(Borrower);
      fixture.market.borrow(500e18);

      vm.warp(initialTimestamp + 365 days);
      uint256 accruedDebt = _accruedDebtAboveDrawn(fixture);
      assertTrue(accruedDebt > 0, 'accrued debt');
      vm.recordLogs();
      vm.prank(Borrower);
      if (i == 0) {
        fixture.market.repay(accruedDebt);
      } else {
        fixture.market.repayAndProcessUnpaidWithdrawalBatches(accruedDebt, 0);
      }
      _assertNoDrawnAmountUpdate(vm.getRecordedLogs());
      assertEq(revolvingMarket.drawnAmount(), 500e18, 'drawn after interest');

      vm.expectEmit(address(fixture.market));
      emit IWildcatMarketRevolving.DrawnAmountUpdated(500e18, 377e18);
      vm.prank(Borrower);
      if (i == 0) {
        fixture.market.repay(123e18);
      } else {
        fixture.market.repayAndProcessUnpaidWithdrawalBatches(123e18, 0);
      }
      assertEq(revolvingMarket.drawnAmount(), 377e18, 'drawn after principal');
    }
  }

  function test_revolvingCloseZerosDrawnAndFreezesAccrual() external {
    Fixture memory fixture = _newMarket(_revolvingOptions(200, 1_000, 0));
    _deposit(fixture, Holder, 1_000e18);
    _approveBorrower(fixture);
    vm.prank(Borrower);
    fixture.market.borrow(400e18);

    vm.expectEmit(address(fixture.market));
    emit IWildcatMarketRevolving.DrawnAmountUpdated(400e18, 0);
    vm.prank(Borrower);
    fixture.market.closeMarket();
    assertTrue(fixture.market.isClosed(), 'closed');
    assertEq(_revolving(fixture).drawnAmount(), 0, 'closed drawn amount');

    uint256 scaleFactor = fixture.market.scaleFactor();
    uint256 totalDebts = fixture.market.totalDebts();
    vm.warp(vm.getBlockTimestamp() + 365 days);
    fixture.market.updateState();
    assertEq(fixture.market.scaleFactor(), scaleFactor, 'closed scale factor');
    assertEq(fixture.market.totalDebts(), totalDebts, 'closed total debts');
  }

  function test_revolvingAccrualCombinesCommitmentUtilizationAndProtocolFees() external {
    Fixture memory fixture = _newMarket(_revolvingOptions(200, 1_000, 500));
    _deposit(fixture, Holder, 1_000e18);
    vm.prank(Borrower);
    fixture.market.borrow(500e18);

    uint32 elapsed = 365 days;
    vm.warp(vm.getBlockTimestamp() + elapsed);
    MarketState memory state = fixture.market.previousState();
    uint256 commitmentInterest = MathUtils.calculateLinearInterestFromBips(200, elapsed);
    uint256 utilizationInterest = _utilizationInterestRay(1_000e18, 500e18, 1_000, elapsed);
    uint256 baseInterest = commitmentInterest + utilizationInterest;
    uint256 expectedProtocolFees = state.applyProtocolFee(baseInterest);
    fixture.market.updateState();

    assertEq(fixture.market.scaleFactor(), RAY + baseInterest, 'combined scale factor');
    assertEq(
      fixture.market.previousState().accruedProtocolFees,
      expectedProtocolFees,
      'revolving protocol fees'
    );
    assertEq(_revolving(fixture).drawnAmount(), 500e18, 'accrual drawn amount');
  }

  function test_revolvingAccrualAppliesDelinquencyFee() external {
    Options memory options = _revolvingOptions(0, 0, 0);
    options.delinquencyFeeBips = 1_000;
    options.delinquencyGracePeriod = 0;
    Fixture memory fixture = _newMarket(options);
    _deposit(fixture, Holder, 1e18);
    vm.prank(Borrower);
    fixture.market.borrow(8e17);
    vm.prank(Holder);
    fixture.market.queueFullWithdrawal();
    assertTrue(fixture.market.currentState().isDelinquent, 'revolving delinquency');

    uint32 elapsed = 2_000;
    vm.warp(vm.getBlockTimestamp() + elapsed);
    fixture.market.updateState();
    assertEq(
      fixture.market.scaleFactor(),
      RAY + MathUtils.calculateLinearInterestFromBips(1_000, elapsed),
      'revolving delinquency fee'
    );
  }

  function test_zeroDelinquencyFeeStillTracksClockAcrossMarketTypes() external {
    uint256 initialTimestamp = vm.getBlockTimestamp();
    for (uint256 marketKind; marketKind < 2; marketKind++) {
      vm.warp(initialTimestamp);
      Options memory options = _defaultOptions(HooksKind.OpenTerm);
      options.revolving = marketKind == 1;
      options.protocolFeeBips = 0;
      options.annualInterestBips = 0;
      options.delinquencyFeeBips = 0;
      options.commitmentFeeBips = 0;
      Fixture memory fixture = _newMarket(options);
      _deposit(fixture, Holder, 1e18);
      _approveBorrower(fixture);
      vm.prank(Borrower);
      fixture.market.borrow(8e17);
      vm.prank(Holder);
      fixture.market.queueFullWithdrawal();
      assertTrue(fixture.market.currentState().isDelinquent, 'initial delinquency');

      vm.warp(initialTimestamp + 2_000);
      MarketState memory current = fixture.market.currentState();
      assertEq(current.timeDelinquent, 2_000, 'current delinquency clock');
      assertEq(current.scaleFactor, RAY, 'zero-fee scale factor');
      fixture.market.updateState();
      assertEq(fixture.market.previousState().timeDelinquent, 2_000, 'stored delinquency clock');

      vm.prank(Borrower);
      fixture.market.repay(8e17);
      assertFalse(fixture.market.currentState().isDelinquent, 'repaid delinquency');

      vm.warp(initialTimestamp + 2_500);
      current = fixture.market.currentState();
      assertEq(current.timeDelinquent, 1_500, 'current recovery clock');
      fixture.market.updateState();
      assertEq(fixture.market.previousState().timeDelinquent, 1_500, 'stored recovery clock');

      vm.warp(initialTimestamp + 4_500);
      fixture.market.updateState();
      assertEq(fixture.market.previousState().timeDelinquent, 0, 'recovered clock');
    }
  }

  function test_revolvingAccrualHandlesFeeOnlyZeroSupplyAndZeroTime() external {
    Options memory options = _revolvingOptions(500, 1_000, 0);
    Fixture memory feeOnlyFixture = _newMarket(options);
    _deposit(feeOnlyFixture, Holder, 100_000e18);
    uint32 elapsed = 73 days;
    vm.warp(vm.getBlockTimestamp() + elapsed);
    feeOnlyFixture.market.updateState();
    uint256 commitmentInterest = MathUtils.calculateLinearInterestFromBips(500, elapsed);
    assertEq(feeOnlyFixture.market.scaleFactor(), RAY + commitmentInterest, 'fee-only accrual');
    assertTrue(
      feeOnlyFixture.market.scaleFactor() <
        RAY + MathUtils.calculateLinearInterestFromBips(1_000, elapsed),
      'undrawn APR leak'
    );

    uint256 currentTimestamp = vm.getBlockTimestamp();
    Fixture memory zeroSupplyFixture = _newMarket(options);
    vm.warp(currentTimestamp + 365 days);
    zeroSupplyFixture.market.updateState();
    assertEq(zeroSupplyFixture.market.scaleFactor(), RAY, 'zero-supply accrual');

    Fixture memory zeroTimeFixture = _newMarket(options);
    _deposit(zeroTimeFixture, Holder, 1_000e18);
    vm.prank(Borrower);
    zeroTimeFixture.market.borrow(500e18);
    zeroTimeFixture.market.updateState();
    assertEq(zeroTimeFixture.market.scaleFactor(), RAY, 'zero-time accrual');
    assertEq(_revolving(zeroTimeFixture).drawnAmount(), 500e18, 'zero-time drawn amount');
  }

  function test_revolvingAccrualClampsUtilizationAndPreservesDustBoundaries() external {
    Fixture memory clampedFixture = _newMarket(_revolvingOptions(200, 1_000, 0));
    _deposit(clampedFixture, Holder, 1_000e18);
    vm.store(address(clampedFixture.market), RevolvingDrawnAmountSlot, bytes32(uint256(2_000e18)));
    assertEq(_revolving(clampedFixture).drawnAmount(), 2_000e18, 'forced drawn amount');
    vm.warp(vm.getBlockTimestamp() + 365 days);
    clampedFixture.market.updateState();
    uint256 fullUtilization = MathUtils.calculateLinearInterestFromBips(1_000, 365 days);
    uint256 commitmentInterest = MathUtils.calculateLinearInterestFromBips(200, 365 days);
    assertEq(
      clampedFixture.market.scaleFactor(),
      RAY + commitmentInterest + fullUtilization,
      'clamped utilization'
    );

    assertEq(_minimumDrawForInterest(1_000e6, 1, 12), 1, '1k six-decimal threshold');
    assertEq(_minimumDrawForInterest(110_000_000e6, 1, 12), 1, '110m six-decimal threshold');
    assertEq(
      _minimumDrawForInterest(110_000_000e6, 1_000, 12),
      1,
      '110m high-APR six-decimal threshold'
    );
    assertEq(_minimumDrawForInterest(110_000_000e6, 1, 1), 1, 'one-second six-decimal threshold');
    assertEq(_minimumDrawForInterest(110_000_000e18, 1, 12), 2_890_800_001, '18-decimal threshold');
    assertEq(
      _minimumDrawForInterest(110_000_000e18, 1_000, 12),
      2_890_801,
      'high-APR 18-decimal threshold'
    );
    assertEq(
      _minimumDrawForInterest(110_000_000e18, 1, 1),
      34_689_600_001,
      'one-second 18-decimal threshold'
    );

    _assertObservedRevolvingDust(1_000e6, 1, 12);
    _assertObservedRevolvingDust(110_000_000e6, 1, 12);
    _assertObservedRevolvingDust(110_000_000e6, 1_000, 12);

    _assertRevolvingDustBoundary(1_000e18, 1, 12);
    _assertRevolvingDustBoundary(1_000e18, 1_000, 12);
    _assertRevolvingDustBoundary(110_000_000e18, 1, 12);
    _assertRevolvingDustBoundary(110_000_000e18, 1_000, 12);
  }

  function test_revolvingFullyDrawnFirstSegmentMatchesStandardThenDiverges() external {
    uint256 depositAmount = 100_000e18;
    Options memory standardOptions = _defaultOptions(HooksKind.OpenTerm);
    standardOptions.reserveRatioBips = 0;
    standardOptions.protocolFeeBips = 0;
    standardOptions.delinquencyFeeBips = 0;
    Options memory revolvingOptions = _revolvingOptions(0, 1_000, 0);
    revolvingOptions.reserveRatioBips = 0;
    Fixture memory standardFixture = _newMarket(standardOptions);
    Fixture memory revolvingFixture = _newMarket(revolvingOptions);
    _deposit(standardFixture, Holder, depositAmount);
    _deposit(revolvingFixture, Holder, depositAmount);
    vm.prank(Borrower);
    standardFixture.market.borrow(depositAmount);
    vm.prank(Borrower);
    revolvingFixture.market.borrow(depositAmount);

    vm.warp(vm.getBlockTimestamp() + 45 days);
    standardFixture.market.updateState();
    revolvingFixture.market.updateState();
    assertEq(
      revolvingFixture.market.scaleFactor(),
      standardFixture.market.scaleFactor(),
      'first segment differential'
    );
    assertTrue(standardFixture.market.scaleFactor() > RAY, 'first segment accrual');

    uint256 scaleFactorBefore = revolvingFixture.market.scaleFactor();
    uint256 supplyBefore = revolvingFixture.market.totalSupply();
    uint256 secondSegmentInterest = _utilizationInterestRay(
      supplyBefore,
      depositAmount,
      revolvingOptions.annualInterestBips,
      30 days
    );
    uint256 expectedRevolving = scaleFactorBefore +
      MathUtils.rayMul(scaleFactorBefore, secondSegmentInterest);
    vm.warp(vm.getBlockTimestamp() + 30 days);
    standardFixture.market.updateState();
    revolvingFixture.market.updateState();
    assertEq(revolvingFixture.market.scaleFactor(), expectedRevolving, 'second segment oracle');
    assertTrue(
      revolvingFixture.market.scaleFactor() < standardFixture.market.scaleFactor(),
      'second segment differential'
    );
  }

  function test_revolvingFullRepayReturnsToCommitmentOnlyAccrual() external {
    Options memory options = _revolvingOptions(300, 1_000, 0);
    options.reserveRatioBips = 0;
    Fixture memory fixture = _newMarket(options);
    _deposit(fixture, Holder, 100_000e18);
    _approveBorrower(fixture);
    vm.prank(Borrower);
    fixture.market.borrow(100_000e18);

    vm.warp(vm.getBlockTimestamp() + 20 days);
    fixture.market.updateState();
    uint256 owed = fixture.market.totalDebts() - fixture.market.totalAssets();
    fixture.asset.mint(Borrower, owed);
    vm.prank(Borrower);
    fixture.market.repay(owed);
    assertEq(_revolving(fixture).drawnAmount(), 0, 'drawn after full repay');

    uint256 scaleFactorBefore = fixture.market.scaleFactor();
    uint256 commitmentInterest = MathUtils.calculateLinearInterestFromBips(300, 15 days);
    uint256 expectedScaleFactor = scaleFactorBefore +
      MathUtils.rayMul(scaleFactorBefore, commitmentInterest);
    vm.warp(vm.getBlockTimestamp() + 15 days);
    fixture.market.updateState();
    assertEq(fixture.market.scaleFactor(), expectedScaleFactor, 'post-repay fee-only accrual');
  }

  function test_revolvingBorrowerTransferPreservesDrawnAmountAndStorage() external {
    Fixture memory fixture = _newMarket(_revolvingOptions(200, 1_000, 0));
    _deposit(fixture, Holder, 1_000e18);
    vm.prank(Borrower);
    fixture.market.borrow(400e18);
    bytes32 drawnAmountWord = vm.load(address(fixture.market), RevolvingDrawnAmountSlot);
    address newBorrower = address(0xB0B0);
    fixture.archController.registerBorrower(newBorrower);

    vm.prank(Borrower);
    fixture.market.requestBorrowerTransfer(newBorrower);
    vm.prank(newBorrower);
    fixture.market.acceptBorrowerTransfer();

    assertEq(fixture.market.borrower(), newBorrower, 'transferred borrower');
    assertEq(fixture.market.borrowerPrincipal(), newBorrower, 'transferred principal');
    assertEq(_revolving(fixture).drawnAmount(), 400e18, 'transferred drawn amount');
    assertEq(
      vm.load(address(fixture.market), RevolvingDrawnAmountSlot),
      drawnAmountWord,
      'drawn storage word'
    );
  }
}
