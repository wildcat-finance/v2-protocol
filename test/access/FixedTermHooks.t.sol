// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import '../shared/mocks/MockFixedTermHooks.sol';
import { bound, warp } from '../helpers/VmUtils.sol';
import { VmSafe } from 'forge-std/Vm.sol';
import './BaseAccessControls.t.sol';

using LibString for uint256;
using LibString for address;
using MathUtils for uint256;
using BoolUtils for bool;

contract FixedTermHooksTest is BaseAccessControlsTest {
  MockFixedTermHooks internal hooks;

  function setUp() external {
    hooks = new MockFixedTermHooks(address(this));
    baseHooks = MockBaseAccessControls(address(hooks));
    assertEq(hooks.factory(), address(this), 'factory');
    assertEq(hooks.borrower(), address(this), 'borrower');
    _addExpectedProvider(MockRoleProvider(address(this)), type(uint32).max, false);
    _validateRoleProviders();
    // Set block.timestamp to 4:50 am, May 3 2024
    warp(1714737030);
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
    inputs.name = 'FixedTermHooks Name';
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
    hooks = MockFixedTermHooks(
      address(new FixedTermHooks(address(this), abi.encode(inputs)))
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
    inputs.name = 'FixedTermHooks Name';
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
    hooks = MockFixedTermHooks(
      address(new FixedTermHooks(address(this), abi.encode(inputs)))
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
    inputs.name = 'FixedTermHooks Name';
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
    hooks = MockFixedTermHooks(
      address(new FixedTermHooks(address(this), abi.encode(inputs)))
    );
    baseHooks = MockBaseAccessControls(address(hooks));
    _validateRoleProviders();
    assertEq(hooks.name(), inputs.name, 'name');
  }

  function test_constructor_NewProviders_CreateRoleProviderFailed() external {
    providerFactory.setNextProviderAddress(address(0));
    NameAndProviderInputs memory inputs;
    inputs.name = 'FixedTermHooks Name';
    inputs.roleProviderFactory = address(providerFactory);
    inputs.newProviderInputs = new CreateProviderInputs[](1);
    inputs.newProviderInputs[0].timeToLive = 1 days;
    inputs.newProviderInputs[0].providerFactoryCalldata = abi.encode(bytes32(0), false);
    vm.expectRevert(BaseAccessControls.CreateRoleProviderFailed.selector);
    new FixedTermHooks(address(this), abi.encode(inputs));
  }

  // ========================================================================== //
  //                               onCreateMarket                               //
  // ========================================================================== //

  function test_onCreateMarket_CallerNotFactory() external asAccount(address(1)) {
    vm.expectRevert(IHooks.CallerNotFactory.selector);
    DeployMarketInputs memory inputs;
    hooks.onCreateMarket(address(1), address(1), inputs, '');
  }

  function test_onCreateMarket_CallerNotBorrower() external {
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    DeployMarketInputs memory inputs;
    hooks.onCreateMarket(address(1), address(1), inputs, '');
  }

  function test_onCreateMarket_FixedTermNotProvided() external {
    vm.expectRevert(FixedTermHooks.FixedTermNotProvided.selector);
    DeployMarketInputs memory inputs;
    hooks.onCreateMarket(address(this), address(1), inputs, '');
  }

  function test_onCreateMarket_ForceEnableDepositTransferHooks() external {
    DeployMarketInputs memory inputs;

    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    vm.expectEmit(address(hooks));
    emit FixedTermHooks.FixedTermUpdated(address(1), uint32(block.timestamp + 365 days));
    HooksConfig config = hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + (365 days))
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
    HookedMarket memory market = hooks.getHookedMarket(address(1));
    assertEq(config, expectedConfig, 'config');
    assertEq(market.isHooked, true, 'isHooked');
    assertEq(market.transferRequiresAccess, false, 'transferRequiresAccess');
    assertEq(market.depositRequiresAccess, false, 'depositRequiresAccess');
    assertEq(market.withdrawalRequiresAccess, true, 'withdrawalRequiresAccess');
  }

  function test_onCreateMarket_InvalidFixedTerm() external {
    DeployMarketInputs memory inputs;

    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    vm.expectRevert(FixedTermHooks.InvalidFixedTerm.selector);
    hooks.onCreateMarket(address(this), address(1), inputs, abi.encode(0));
    vm.expectRevert(FixedTermHooks.InvalidFixedTerm.selector);
    hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + (366 days))
    );
  }

  function test_onCreateMarket_setMinimumDeposit() external {
    DeployMarketInputs memory inputs;

    inputs.hooks = EmptyHooksConfig.setHooksAddress(address(hooks));
    HooksConfig config = hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18)
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
    HookedMarket memory market = hooks.getHookedMarket(address(1));
    assertEq(config, expectedConfig, 'config');
    assertEq(market.isHooked, true, 'isHooked');
    assertEq(market.transferRequiresAccess, false, 'transferRequiresAccess');
    assertEq(market.depositRequiresAccess, false, 'depositRequiresAccess');
    assertEq(market.minimumDeposit, 1e18, 'minimumDeposit');
    assertEq(market.fixedTermEndTime, uint32(block.timestamp + 365 days), 'fixedTermEndTime');
  }

  function test_onCreateMarket_disableTransfers() external {
    DeployMarketInputs memory inputs;

    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    HooksConfig config = hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18, true)
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
    HookedMarket memory market = hooks.getHookedMarket(address(1));
    assertEq(config, expectedConfig, 'config');
    assertEq(market.isHooked, true, 'isHooked');
    assertEq(market.transferRequiresAccess, false, 'transferRequiresAccess');
    assertEq(market.depositRequiresAccess, false, 'depositRequiresAccess');
    assertEq(market.minimumDeposit, 1e18, 'minimumDeposit');
    assertEq(market.fixedTermEndTime, uint32(block.timestamp + 365 days), 'fixedTermEndTime');
    assertEq(market.transfersDisabled, true, 'transfersDisabled');
    assertTrue(config.useOnTransfer(), 'useOnTransfer');
  }

  function test_onTransfer_TransfersDisabled() external {
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18, true)
    );
    vm.expectRevert(FixedTermHooks.TransfersDisabled.selector);
    MarketState memory state;
    vm.prank(address(1));
    hooks.onTransfer(address(1), address(2), address(3), 100, state, '');
  }

  function test_onCreateMarket_MinimumDepositOverflow() external {
    DeployMarketInputs memory inputs;

    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    vm.expectRevert(abi.encodePacked(Panic_ErrorSelector, Panic_Arithmetic));
    HooksConfig config = hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, type(uint136).max)
    );
  }

  function test_version() external {
    assertEq(hooks.version(), 'FixedTermHooks');
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
      useOnCloseMarket: true,
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
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, minimumDeposit)
    );
    assertEq(config, expectedConfig, 'config');
    HookedMarket memory market = hooks.getHookedMarket(address(1));
    assertEq(market.isHooked, true, 'isHooked');
    assertEq(market.transferRequiresAccess, useOnTransfer, 'transferRequiresAccess');
    assertEq(market.depositRequiresAccess, useOnDeposit, 'depositRequiresAccess');
    assertEq(market.withdrawalRequiresAccess, useOnQueueWithdrawal, 'withdrawalRequiresAccess');
    assertEq(market.fixedTermEndTime, uint32(block.timestamp + 365 days), 'fixedTermEndTime');
    assertEq(market.minimumDeposit, minimumDeposit, 'minimumDeposit');
    assertEq(market.transfersDisabled, false, 'transfersDisabled');
  }

  function test_onDeposit_NotHookedMarket() external {
    MarketState memory state;
    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    hooks.onDeposit(address(1), 0, state, '');
  }

  function test_setFixedTermEndTime_NotHookedMarket() external {
    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    hooks.setFixedTermEndTime(address(1), 0);
  }

  function test_setFixedTermEndTime_CallerNotBorrower() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    hooks.setFixedTermEndTime(address(1), 0);
  }

  function test_setFixedTermEndTime_IncreaseFixedTerm() external {
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18)
    );
    vm.expectRevert(FixedTermHooks.IncreaseFixedTerm.selector);
    hooks.setFixedTermEndTime(address(1), uint32(block.timestamp + 366 days));
  }

  function test_setFixedTermEndTime() external {
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18, false, false, true)
    );
    vm.expectEmit(address(hooks));
    emit FixedTermHooks.FixedTermUpdated(address(1), uint32(block.timestamp + 364 days));
    hooks.setFixedTermEndTime(address(1), uint32(block.timestamp + 364 days));
    HookedMarket memory market = hooks.getHookedMarket(address(1));
    assertEq(market.fixedTermEndTime, uint32(block.timestamp + 364 days), 'fixedTermEndTime');
  }

  function test_setFixedTermEndTime_ReductionDisabled() external {
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18, false, false, false, false)
    );
    vm.expectRevert(FixedTermHooks.TermReductionDisabled.selector);
    hooks.setFixedTermEndTime(address(1), uint32(block.timestamp + 364 days));
  }

  function test_onQueueWithdrawal_WithdrawBeforeTermEnd() external {
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setHooksAddress(address(hooks));
    hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18)
    );
    vm.prank(address(1));
    MarketState memory state;
    vm.expectRevert(FixedTermHooks.WithdrawBeforeTermEnd.selector);
    hooks.onQueueWithdrawal(address(1), 0, 1, state, '');
  }

  function test_onQueueWithdrawal() external {
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setHooksAddress(address(hooks));
    hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18)
    );
    vm.prank(address(1));
    MarketState memory state;
    vm.warp(block.timestamp + 366 days);
    hooks.onQueueWithdrawal(address(1), 0, 1, state, '');
  }

  function test_onQueueWithdrawal_NotHookedMarket() external {
    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    MarketState memory state;
    hooks.onQueueWithdrawal(address(1), 0, 1, state, '');
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
    DeployMarketInputs memory inputs;

    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    HooksConfig config = hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18)
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
    HookedMarket memory market = hooks.getHookedMarket(address(1));
    assertEq(config, expectedConfig, 'config');
    assertEq(market.isHooked, true, 'isHooked');
    assertEq(market.transferRequiresAccess, false, 'transferRequiresAccess');
    assertEq(market.depositRequiresAccess, false, 'depositRequiresAccess');
    assertEq(market.minimumDeposit, 1e18, 'minimumDeposit');

    vm.expectEmit(address(hooks));
    emit FixedTermHooks.MinimumDepositUpdated(address(1), 2e18);
    hooks.setMinimumDeposit(address(1), 2e18);
    assertEq(hooks.getHookedMarket(address(1)).minimumDeposit, 2e18, 'minimumDeposit');
  }

  function test_setMinimumDeposit_CallerNotBorrower() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    hooks.setMinimumDeposit(address(1), 1);
  }

  function test_setMinimumDeposit_NotHookedMarket() external {
    vm.expectRevert(FixedTermHooks.NotHookedMarket.selector);
    hooks.setMinimumDeposit(address(1), 1);
  }

  // ========================================================================== //
  //                    setAnnualInterestAndReserveRatioBips                    //
  // ========================================================================== //

  function test_setAnnualInterestAndReserveRatioBips_ReducingAprDuringFixedTerm() external {
    DeployMarketInputs memory inputs;

    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    HooksConfig config = hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18)
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
    HookedMarket memory market = hooks.getHookedMarket(address(1));
    MarketState memory state;

    state.annualInterestBips = 101;
    state.reserveRatioBips = 1000;

    vm.prank(address(1));
    vm.expectRevert(FixedTermHooks.NoReducingAprBeforeTermEnd.selector);
    hooks.onSetAnnualInterestAndReserveRatioBips(100, 1000, state, '');
  }

  // ========================================================================== //
  //                                 closeMarket                                //
  // ========================================================================== //

  function test_closeMarket() external {
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18, false, true)
    );
    vm.prank(address(1));
    vm.expectEmit(address(hooks));
    emit FixedTermHooks.FixedTermUpdated(address(1), uint32(block.timestamp));
    MarketState memory state;
    hooks.onCloseMarket(state, '');
    HookedMarket memory market = hooks.getHookedMarket(address(1));
    assertEq(market.fixedTermEndTime, uint32(block.timestamp), 'fixedTermEndTime');
  }

  function test_closeMarket_ClosureDisabledBeforeTerm() external {
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    hooks.onCreateMarket(
      address(this),
      address(1),
      inputs,
      abi.encode(block.timestamp + 365 days, 1e18, false, false)
    );
    vm.prank(address(1));
    vm.expectRevert(FixedTermHooks.ClosureDisabledBeforeTerm.selector);
    MarketState memory state;
    hooks.onCloseMarket(state, '');
  }
}
