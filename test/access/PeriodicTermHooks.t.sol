// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import '../shared/mocks/MockPeriodicTermHooks.sol';
import { warp } from '../helpers/VmUtils.sol';
import './BaseAccessControls.t.sol';

using MathUtils for uint256;
using BoolUtils for bool;

contract PeriodicTermHooksTest is BaseAccessControlsTest {
  MockPeriodicTermHooks internal hooks;

  uint32 internal constant PeriodStart = 1_714_737_030;
  uint32 internal constant PeriodDuration = 30 days;
  uint32 internal constant WithdrawalWindowDuration = 3 days;
  address internal constant Market = address(1);
  address internal constant Lender = address(2);

  function setUp() external {
    hooks = new MockPeriodicTermHooks(address(this));
    baseHooks = MockBaseAccessControls(address(hooks));
    assertEq(hooks.factory(), address(this), 'factory');
    assertEq(hooks.borrower(), address(this), 'borrower');
    _addExpectedProvider(MockRoleProvider(address(this)), type(uint32).max, false);
    _validateRoleProviders();
    warp(PeriodStart);
  }

  function _encodeHooksData() internal pure returns (bytes memory) {
    return abi.encode(PeriodStart, PeriodDuration, WithdrawalWindowDuration);
  }

  function _encodeHooksData(uint128 minimumDeposit) internal pure returns (bytes memory) {
    return abi.encode(PeriodStart, PeriodDuration, WithdrawalWindowDuration, minimumDeposit);
  }

  function _encodeHooksData(
    uint128 minimumDeposit,
    bool transfersDisabled
  ) internal pure returns (bytes memory) {
    return
      abi.encode(
        PeriodStart,
        PeriodDuration,
        WithdrawalWindowDuration,
        minimumDeposit,
        transfersDisabled
      );
  }

  function _createMarket(HooksConfig inputConfig, bytes memory hooksData) internal {
    DeployMarketInputs memory inputs;
    inputs.hooks = inputConfig.setHooksAddress(address(hooks));
    hooks.onCreateMarket(address(this), Market, inputs, hooksData);
  }

  function _createMarket() internal {
    _createMarket(EmptyHooksConfig, _encodeHooksData());
  }

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  function test_constructor_ExistingProviders(
    bool isPullProvider1,
    uint32 ttl1,
    bool isPullProvider2,
    uint32 ttl2
  ) external {
    NameAndProviderInputs memory inputs;
    inputs.name = 'PeriodicTermHooks Name';
    inputs.existingProviders = new ExistingProviderInputs[](2);
    inputs.existingProviders[0] = ExistingProviderInputs({
      providerAddress: address(mockProvider1),
      timeToLive: ttl1
    });
    inputs.existingProviders[1] = ExistingProviderInputs({
      providerAddress: address(mockProvider2),
      timeToLive: ttl2
    });
    mockProvider1.setIsPullProvider(isPullProvider1);
    mockProvider2.setIsPullProvider(isPullProvider2);
    _addExpectedProvider(mockProvider1, ttl1, isPullProvider1);
    _addExpectedProvider(mockProvider2, ttl2, isPullProvider2);
    hooks = MockPeriodicTermHooks(
      address(new PeriodicTermHooks(address(this), abi.encode(inputs)))
    );
    baseHooks = MockBaseAccessControls(address(hooks));
    _validateRoleProviders();
    assertEq(hooks.name(), inputs.name, 'name');
  }

  function test_constructor_NewProviders(
    bool isPullProvider1,
    uint32 ttl1,
    bool isPullProvider2,
    uint32 ttl2
  ) external {
    bytes32 salt1 = bytes32(uint256(1));
    bytes32 salt2 = bytes32(uint256(2));
    NameAndProviderInputs memory inputs;
    inputs.name = 'PeriodicTermHooks Name';
    inputs.roleProviderFactory = address(providerFactory);
    inputs.newProviderInputs = new CreateProviderInputs[](2);
    inputs.newProviderInputs[0] = CreateProviderInputs({
      providerFactoryCalldata: abi.encode(salt1, isPullProvider1),
      timeToLive: ttl1
    });
    inputs.newProviderInputs[1] = CreateProviderInputs({
      providerFactoryCalldata: abi.encode(salt2, isPullProvider2),
      timeToLive: ttl2
    });
    _addExpectedProvider(
      MockRoleProvider(providerFactory.computeProviderAddress(salt1)),
      ttl1,
      isPullProvider1
    );
    _addExpectedProvider(
      MockRoleProvider(providerFactory.computeProviderAddress(salt2)),
      ttl2,
      isPullProvider2
    );
    hooks = MockPeriodicTermHooks(
      address(new PeriodicTermHooks(address(this), abi.encode(inputs)))
    );
    baseHooks = MockBaseAccessControls(address(hooks));
    _validateRoleProviders();
    assertEq(hooks.name(), inputs.name, 'name');
  }

  function test_constructor_NewAndExistingProviders(
    bool isPullProvider1,
    uint32 ttl1,
    bool isPullProvider2,
    uint32 ttl2
  ) external {
    bytes32 salt = bytes32(uint256(1));
    NameAndProviderInputs memory inputs;
    inputs.name = 'PeriodicTermHooks Name';
    inputs.roleProviderFactory = address(providerFactory);
    inputs.newProviderInputs = new CreateProviderInputs[](1);
    inputs.existingProviders = new ExistingProviderInputs[](1);
    inputs.existingProviders[0].timeToLive = ttl1;
    inputs.existingProviders[0].providerAddress = address(mockProvider1);
    inputs.newProviderInputs[0].providerFactoryCalldata = abi.encode(salt, isPullProvider2);
    inputs.newProviderInputs[0].timeToLive = ttl2;

    _addExpectedProvider(mockProvider1, ttl1, isPullProvider1);
    _addExpectedProvider(
      MockRoleProvider(providerFactory.computeProviderAddress(salt)),
      ttl2,
      isPullProvider2
    );
    hooks = MockPeriodicTermHooks(
      address(new PeriodicTermHooks(address(this), abi.encode(inputs)))
    );
    baseHooks = MockBaseAccessControls(address(hooks));
    _validateRoleProviders();
    assertEq(hooks.name(), inputs.name, 'name');
  }

  function test_constructor_NewProviders_CreateRoleProviderFailed() external {
    providerFactory.setNextProviderAddress(address(0));
    NameAndProviderInputs memory inputs;
    inputs.name = 'PeriodicTermHooks Name';
    inputs.roleProviderFactory = address(providerFactory);
    inputs.newProviderInputs = new CreateProviderInputs[](1);
    inputs.newProviderInputs[0].timeToLive = 1 days;
    inputs.newProviderInputs[0].providerFactoryCalldata = abi.encode(bytes32(0), false);
    vm.expectRevert(BaseAccessControls.CreateRoleProviderFailed.selector);
    new PeriodicTermHooks(address(this), abi.encode(inputs));
  }

  // ========================================================================== //
  //                               onCreateMarket                               //
  // ========================================================================== //

  function test_onCreateMarket_CallerNotFactory() external asAccount(address(1)) {
    vm.expectRevert(IHooks.CallerNotFactory.selector);
    DeployMarketInputs memory inputs;
    hooks.onCreateMarket(address(1), Market, inputs, '');
  }

  function test_onCreateMarket_CallerNotBorrower() external {
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    DeployMarketInputs memory inputs;
    hooks.onCreateMarket(address(1), Market, inputs, '');
  }

  function test_onCreateMarket_PeriodicWindowNotProvided() external {
    vm.expectRevert(PeriodicTermHooks.PeriodicWindowNotProvided.selector);
    DeployMarketInputs memory inputs;
    hooks.onCreateMarket(address(this), Market, inputs, abi.encode(PeriodStart, PeriodDuration));
  }

  function test_onCreateMarket_PeriodStartInFuture() external {
    DeployMarketInputs memory inputs;
    uint32 futurePeriodStart = PeriodStart + 7 days;
    hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      abi.encode(futurePeriodStart, PeriodDuration, WithdrawalWindowDuration)
    );

    HookedMarket memory market = hooks.getHookedMarket(Market);
    assertEq(market.periodStart, futurePeriodStart, 'periodStart');
    assertFalse(hooks.isWithdrawalWindowOpen(Market), 'window closed before future period start');
  }

  function test_onCreateMarket_InitialWithdrawalWindowTooFarInFuture() external {
    uint32 maximumInitialWithdrawalWindowDelay = hooks.MaximumInitialWithdrawalWindowDelay();
    DeployMarketInputs memory inputs;
    uint32 periodStart = uint32(
      PeriodStart + maximumInitialWithdrawalWindowDelay - PeriodDuration + WithdrawalWindowDuration
    );

    hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      abi.encode(periodStart, PeriodDuration, WithdrawalWindowDuration)
    );

    vm.expectRevert(PeriodicTermHooks.InitialWithdrawalWindowTooFarInFuture.selector);
    hooks.onCreateMarket(
      address(this),
      address(2),
      inputs,
      abi.encode(periodStart + 1, PeriodDuration, WithdrawalWindowDuration)
    );
  }

  function test_onCreateMarket_InvalidPeriodDuration() external {
    DeployMarketInputs memory inputs;
    uint32 minimumPeriodDuration = hooks.MinimumPeriodDuration();
    uint32 maximumPeriodDuration = hooks.MaximumPeriodDuration();

    vm.expectRevert(PeriodicTermHooks.PeriodDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      abi.encode(PeriodStart, uint32(0), WithdrawalWindowDuration)
    );

    vm.expectRevert(PeriodicTermHooks.PeriodDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      abi.encode(PeriodStart, minimumPeriodDuration - 1, WithdrawalWindowDuration)
    );

    vm.expectRevert(PeriodicTermHooks.PeriodDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      abi.encode(PeriodStart, maximumPeriodDuration + 1, WithdrawalWindowDuration)
    );
  }

  function test_onCreateMarket_InvalidWithdrawalWindow() external {
    DeployMarketInputs memory inputs;
    uint32 minimumWithdrawalWindowDuration = hooks.MinimumWithdrawalWindowDuration();

    vm.expectRevert(PeriodicTermHooks.WithdrawalWindowDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      abi.encode(PeriodStart, PeriodDuration, uint32(0))
    );

    vm.expectRevert(PeriodicTermHooks.WithdrawalWindowDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      abi.encode(PeriodStart, PeriodDuration, minimumWithdrawalWindowDuration - 1)
    );

    vm.expectRevert(PeriodicTermHooks.WithdrawalWindowDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      abi.encode(PeriodStart, PeriodDuration, PeriodDuration)
    );

    vm.expectRevert(PeriodicTermHooks.WithdrawalWindowDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      abi.encode(PeriodStart, PeriodDuration, PeriodDuration + 1)
    );
  }

  function test_onCreateMarket_setMinimumDeposit() external {
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setHooksAddress(address(hooks));

    vm.expectEmit(address(hooks));
    emit PeriodicTermHooks.PeriodicTermUpdated(
      Market,
      PeriodStart,
      PeriodDuration,
      WithdrawalWindowDuration
    );
    vm.expectEmit(address(hooks));
    emit PeriodicTermHooks.MinimumDepositUpdated(Market, 1e18);
    HooksConfig config = hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      _encodeHooksData(1e18)
    );

    HooksConfig expectedConfig = encodeHooksConfig({
      hooksAddress: address(hooks),
      useOnDeposit: true,
      useOnQueueWithdrawal: true,
      useOnExecuteWithdrawal: false,
      useOnTransfer: false,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: true,
      useOnNukeFromOrbit: false,
      useOnSetMaxTotalSupply: false,
      useOnSetAnnualInterestAndReserveRatioBips: true,
      useOnSetProtocolFeeBips: false
    });
    HookedMarket memory market = hooks.getHookedMarket(Market);
    assertEq(config, expectedConfig, 'config');
    assertEq(market.isHooked, true, 'isHooked');
    assertEq(market.minimumDeposit, 1e18, 'minimumDeposit');
    assertEq(market.periodStart, PeriodStart, 'periodStart');
    assertEq(market.periodDuration, PeriodDuration, 'periodDuration');
    assertEq(market.withdrawalWindowDuration, WithdrawalWindowDuration, 'withdrawalWindowDuration');
  }

  function test_onCreateMarket_disableTransfers() external {
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setHooksAddress(address(hooks));
    HooksConfig config = hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      _encodeHooksData(1e18, true)
    );

    HooksConfig expectedConfig = encodeHooksConfig({
      hooksAddress: address(hooks),
      useOnDeposit: true,
      useOnQueueWithdrawal: true,
      useOnExecuteWithdrawal: false,
      useOnTransfer: true,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: true,
      useOnNukeFromOrbit: false,
      useOnSetMaxTotalSupply: false,
      useOnSetAnnualInterestAndReserveRatioBips: true,
      useOnSetProtocolFeeBips: false
    });
    HookedMarket memory market = hooks.getHookedMarket(Market);
    assertEq(config, expectedConfig, 'config');
    assertEq(market.transfersDisabled, true, 'transfersDisabled');
    assertTrue(config.useOnTransfer(), 'useOnTransfer');
  }

  function test_onTransfer_TransfersDisabled() external {
    _createMarket(EmptyHooksConfig, _encodeHooksData(1e18, true));
    vm.expectRevert(PeriodicTermHooks.TransfersDisabled.selector);
    MarketState memory state;
    vm.prank(Market);
    hooks.onTransfer(address(1), address(2), address(3), 100, state, '');
  }

  function test_onCreateMarket_MinimumDepositOverflow() external {
    DeployMarketInputs memory inputs;
    vm.expectRevert(abi.encodePacked(Panic_ErrorSelector, Panic_Arithmetic));
    hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      abi.encode(PeriodStart, PeriodDuration, WithdrawalWindowDuration, type(uint136).max)
    );
  }

  function test_version() external {
    assertEq(hooks.version(), 'PeriodicTermHooks');
  }

  function test_config() external {
    StandardHooksDeploymentConfig memory expectedConfig;
    expectedConfig.optional = StandardHooksConfig({
      hooksAddress: address(0),
      useOnDeposit: true,
      useOnQueueWithdrawal: false,
      useOnExecuteWithdrawal: false,
      useOnTransfer: true,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
      useOnNukeFromOrbit: false,
      useOnSetMaxTotalSupply: false,
      useOnSetAnnualInterestAndReserveRatioBips: false,
      useOnSetProtocolFeeBips: false
    });
    expectedConfig.required.useOnSetAnnualInterestAndReserveRatioBips = true;
    expectedConfig.required.useOnQueueWithdrawal = true;
    expectedConfig.required.useOnCloseMarket = true;
    assertEq(hooks.config(), expectedConfig, 'config.');
  }

  function test_onCreateMarket_config(
    bool useOnQueueWithdrawal,
    bool useOnDeposit,
    bool useOnTransfer,
    uint128 minimumDeposit
  ) external {
    DeployMarketInputs memory inputs;
    inputs.hooks = encodeHooksConfig({
      hooksAddress: address(hooks),
      useOnQueueWithdrawal: useOnQueueWithdrawal,
      useOnDeposit: useOnDeposit,
      useOnTransfer: useOnTransfer,
      useOnExecuteWithdrawal: false,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
      useOnNukeFromOrbit: false,
      useOnSetMaxTotalSupply: false,
      useOnSetAnnualInterestAndReserveRatioBips: false,
      useOnSetProtocolFeeBips: false
    });
    StandardHooksConfig memory expectedConfig;
    expectedConfig.hooksAddress = address(hooks);
    expectedConfig.useOnQueueWithdrawal = true;
    expectedConfig.useOnCloseMarket = true;
    expectedConfig.useOnTransfer = useOnTransfer || useOnQueueWithdrawal;
    expectedConfig.useOnDeposit = useOnDeposit || useOnQueueWithdrawal || minimumDeposit > 0;
    expectedConfig.useOnSetAnnualInterestAndReserveRatioBips = true;

    HooksConfig config = hooks.onCreateMarket(
      address(this),
      Market,
      inputs,
      _encodeHooksData(minimumDeposit)
    );
    assertEq(config, expectedConfig, 'config');
    HookedMarket memory market = hooks.getHookedMarket(Market);
    assertEq(market.isHooked, true, 'isHooked');
    assertEq(market.transferRequiresAccess, useOnTransfer, 'transferRequiresAccess');
    assertEq(market.depositRequiresAccess, useOnDeposit, 'depositRequiresAccess');
    assertEq(market.withdrawalRequiresAccess, useOnQueueWithdrawal, 'withdrawalRequiresAccess');
    assertEq(market.minimumDeposit, minimumDeposit, 'minimumDeposit');
    assertEq(market.periodStart, PeriodStart, 'periodStart');
    assertEq(market.periodDuration, PeriodDuration, 'periodDuration');
    assertEq(market.withdrawalWindowDuration, WithdrawalWindowDuration, 'withdrawalWindowDuration');
    assertEq(market.transfersDisabled, false, 'transfersDisabled');
  }

  // ========================================================================== //
  //                              Withdrawal Window                             //
  // ========================================================================== //

  function test_isWithdrawalWindowOpen() external {
    _createMarket();
    assertFalse(hooks.isWithdrawalWindowOpen(Market), 'window closed at period start');

    vm.warp(PeriodStart + PeriodDuration - WithdrawalWindowDuration - 1);
    assertFalse(hooks.isWithdrawalWindowOpen(Market), 'window closed before window start');

    vm.warp(PeriodStart + PeriodDuration - WithdrawalWindowDuration);
    assertTrue(hooks.isWithdrawalWindowOpen(Market), 'window open at window start');

    vm.warp(PeriodStart + PeriodDuration - 1);
    assertTrue(hooks.isWithdrawalWindowOpen(Market), 'window open at last second');

    vm.warp(PeriodStart + PeriodDuration);
    assertFalse(hooks.isWithdrawalWindowOpen(Market), 'window closed at next period start');

    vm.warp((PeriodStart + PeriodDuration * 2) - WithdrawalWindowDuration);
    assertTrue(hooks.isWithdrawalWindowOpen(Market), 'window open in next period');
  }

  function test_isWithdrawalWindowOpen_BeforePeriodStart() external {
    _createMarket();
    vm.warp(PeriodStart - 1);
    assertFalse(hooks.isWithdrawalWindowOpen(Market), 'window closed before period start');
  }

  function test_isWithdrawalWindowOpen_NotHookedMarket() external {
    vm.expectRevert(PeriodicTermHooks.NotHookedMarket.selector);
    hooks.isWithdrawalWindowOpen(Market);
  }

  function test_onQueueWithdrawal_WithdrawOutsideWindow() external {
    _createMarket();
    MarketState memory state;
    vm.prank(Market);
    vm.expectRevert(PeriodicTermHooks.WithdrawOutsideWindow.selector);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
  }

  function test_onQueueWithdrawal() external {
    _createMarket();
    vm.warp(PeriodStart + PeriodDuration - WithdrawalWindowDuration);
    vm.prank(Market);
    MarketState memory state;
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
  }

  function test_onQueueWithdrawal_NotHookedMarket() external {
    vm.expectRevert(PeriodicTermHooks.NotHookedMarket.selector);
    MarketState memory state;
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
  }

  function test_onQueueWithdrawal_WithdrawalRequiresAccess() external {
    _createMarket(EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal), _encodeHooksData());
    vm.warp(PeriodStart + PeriodDuration - WithdrawalWindowDuration);
    MarketState memory state;

    vm.prank(Market);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');

    hooks.setIsKnownLender(Lender, Market, true);
    vm.prank(Market);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
  }

  function test_onExecuteWithdrawal_OutsideWindow() external {
    _createMarket();
    MarketState memory state;
    vm.prank(Market);
    hooks.onExecuteWithdrawal(Lender, 1, state, '');
  }

  function test_onCloseMarket_OpensWithdrawals() external {
    _createMarket();
    assertFalse(hooks.isWithdrawalWindowOpen(Market), 'window closed before close');

    MarketState memory state;
    vm.prank(Market);
    vm.expectEmit(address(hooks));
    emit PeriodicTermHooks.PeriodicTermClosed(Market);
    hooks.onCloseMarket(state, '');

    HookedMarket memory market = hooks.getHookedMarket(Market);
    assertTrue(market.isClosed, 'isClosed');
    assertTrue(hooks.isWithdrawalWindowOpen(Market), 'window open after close');

    vm.prank(Market);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
  }

  function test_onQueueWithdrawal_ClosedStateBypassesWindow() external {
    _createMarket();
    MarketState memory state;
    state.isClosed = true;
    vm.prank(Market);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
  }

  function test_onCloseMarket_NotHookedMarket() external {
    MarketState memory state;
    vm.expectRevert(PeriodicTermHooks.NotHookedMarket.selector);
    hooks.onCloseMarket(state, '');
  }

  // ========================================================================== //
  //                                  Deposits                                  //
  // ========================================================================== //

  function test_onDeposit_OutsideWindow() external {
    _createMarket(EmptyHooksConfig, _encodeHooksData(1e18));
    MarketState memory state;
    state.scaleFactor = uint112(RAY);

    vm.prank(Market);
    hooks.onDeposit(Lender, 1e18, state, '');
  }

  function test_onDeposit_BelowMinimum() external {
    _createMarket(EmptyHooksConfig, _encodeHooksData(1e18));
    MarketState memory state;
    state.scaleFactor = uint112(RAY);

    vm.prank(Market);
    vm.expectRevert(PeriodicTermHooks.DepositBelowMinimum.selector);
    hooks.onDeposit(Lender, 1e18 - 1, state, '');
  }

  function test_onDeposit_NotHookedMarket() external {
    MarketState memory state;
    vm.expectRevert(PeriodicTermHooks.NotHookedMarket.selector);
    hooks.onDeposit(Lender, 0, state, '');
  }

  // ========================================================================== //
  //                           getParameterConstraints                          //
  // ========================================================================== //

  function test_getParameterConstraints() external view {
    MarketParameterConstraints memory constraints = hooks.getParameterConstraints();
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

  // ========================================================================== //
  //                              setMinimumDeposit                             //
  // ========================================================================== //

  function test_setMinimumDeposit() external {
    _createMarket(EmptyHooksConfig, _encodeHooksData(1e18));
    HookedMarket memory market = hooks.getHookedMarket(Market);
    assertEq(market.minimumDeposit, 1e18, 'minimumDeposit');

    vm.expectEmit(address(hooks));
    emit PeriodicTermHooks.MinimumDepositUpdated(Market, 2e18);
    hooks.setMinimumDeposit(Market, 2e18);
    assertEq(hooks.getHookedMarket(Market).minimumDeposit, 2e18, 'minimumDeposit');
  }

  function test_setMinimumDeposit_CallerNotBorrower() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    hooks.setMinimumDeposit(Market, 1);
  }

  function test_setMinimumDeposit_NotHookedMarket() external {
    vm.expectRevert(PeriodicTermHooks.NotHookedMarket.selector);
    hooks.setMinimumDeposit(Market, 1);
  }
}
