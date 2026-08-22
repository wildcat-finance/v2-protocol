// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IHooks } from 'src/access/IHooks.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { MarketConstraintHooks } from 'src/access/MarketConstraintHooks.sol';
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
import { MarketConfigHooks, ProtocolFeeReadOnDepositHooks } from '../mocks/MarketMocks.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

contract WildcatMarketTest is MarketFixture {
  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);
  address internal constant Delegate = address(0xDE1E6A7E);
  bytes32 internal constant BorrowerStorageSlot = bytes32(type(uint256).max);
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

  function _newConfigMarket()
    private
    returns (Fixture memory fixture, MarketConfigHooks configHooks)
  {
    configHooks = MarketConfigHooks(
      _deployCode('test-next/mocks/MarketMocks.sol:MarketConfigHooks')
    );
    fixture = _newMarket(_defaultOptions(HooksKind.OpenTerm), IHooks(address(configHooks)));
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
      uint256 relativeReduction = MathUtils.mulDiv(
        10_000,
        1_000 - uint256(annualInterestBips),
        1_000
      );
      reserveRatioBips = MathUtils.min(10_000, 2 * relativeReduction);
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
