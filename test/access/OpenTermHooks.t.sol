// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/access/OpenTermHooks.sol';
import '../shared/mocks/MockOpenTermHooks.sol';
import { VmSafe } from 'forge-std/Vm.sol';
import './BaseAccessControls.t.sol';

using LibString for uint256;
using LibString for address;
using MathUtils for uint256;
using BoolUtils for bool;

contract OpenTermHooksTest is BaseAccessControlsTest {
  MockOpenTermHooks internal hooks;

  function setUp() external {
    hooks = new MockOpenTermHooks(address(this));
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
    inputs.name = 'Some Name';
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
    hooks = MockOpenTermHooks(
      address(new OpenTermHooks(address(this), abi.encode(inputs)))
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
    inputs.name = 'OpenTermHooks Name';
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
    hooks = MockOpenTermHooks(
      address(new OpenTermHooks(address(this), abi.encode(inputs)))
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
    inputs.name = 'OpenTermHooks Name';
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
    hooks = MockOpenTermHooks(
      address(new OpenTermHooks(address(this), abi.encode(inputs)))
    );
    baseHooks = MockBaseAccessControls(address(hooks));
    _validateRoleProviders();
    assertEq(hooks.name(), inputs.name, 'name');
  }

  function test_constructor_NewProviders_CreateRoleProviderFailed() external {
    providerFactory.setNextProviderAddress(address(0));
    NameAndProviderInputs memory inputs;
    inputs.name = 'OpenTermHooks Name';
    inputs.roleProviderFactory = address(providerFactory);
    inputs.newProviderInputs = new CreateProviderInputs[](1);
    inputs.newProviderInputs[0].timeToLive = 1 days;
    inputs.newProviderInputs[0].providerFactoryCalldata = abi.encode(bytes32(0), false);
    vm.expectRevert(BaseAccessControls.CreateRoleProviderFailed.selector);
    new OpenTermHooks(address(this), abi.encode(inputs));
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

  function test_onCreateMarket_ForceEnableDepositTransferHooks() external {
    DeployMarketInputs memory inputs;

    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    HooksConfig config = hooks.onCreateMarket(address(this), address(1), inputs, '');
    HooksConfig expectedConfig = encodeHooksConfig({
      hooksAddress: address(hooks),
      useOnDeposit: true,
      useOnQueueWithdrawal: true,
      useOnExecuteWithdrawal: false,
      useOnTransfer: true,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
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
  }

  function test_onCreateMarket_setMinimumDeposit() external {
    DeployMarketInputs memory inputs;

    inputs.hooks = EmptyHooksConfig.setHooksAddress(address(hooks));
    HooksConfig config = hooks.onCreateMarket(address(this), address(1), inputs, abi.encode(1e18));
    HooksConfig expectedConfig = encodeHooksConfig({
      hooksAddress: address(hooks),
      useOnDeposit: true,
      useOnQueueWithdrawal: false,
      useOnExecuteWithdrawal: false,
      useOnTransfer: false,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
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
  }

  function test_onCreateMarket_setMinimumDeposit_Zero() external {
    DeployMarketInputs memory inputs;

    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    HooksConfig config = hooks.onCreateMarket(address(this), address(1), inputs, abi.encode(0));
    HooksConfig expectedConfig = encodeHooksConfig({
      hooksAddress: address(hooks),
      useOnDeposit: true,
      useOnQueueWithdrawal: true,
      useOnExecuteWithdrawal: false,
      useOnTransfer: true,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
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
    assertEq(market.minimumDeposit, 0, 'minimumDeposit');
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
      abi.encode(0, true)
    );
    HooksConfig expectedConfig = encodeHooksConfig({
      hooksAddress: address(hooks),
      useOnDeposit: true,
      useOnQueueWithdrawal: true,
      useOnExecuteWithdrawal: false,
      useOnTransfer: true,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
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
    assertEq(market.minimumDeposit, 0, 'minimumDeposit');
    assertEq(market.transfersDisabled, true, 'transfersDisabled');
    assertTrue(config.useOnTransfer(), 'useOnTransfer');
  }

  function test_onTransfer_TransfersDisabled() external {
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_QueueWithdrawal).setHooksAddress(
      address(hooks)
    );
    hooks.onCreateMarket(address(this), address(1), inputs, abi.encode(1e18, true));
    vm.expectRevert(OpenTermHooks.TransfersDisabled.selector);
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
      abi.encode(type(uint136).max)
    );
  }

  function test_version() external {
    assertEq(hooks.version(), 'OpenTermHooks');
  }

  function test_config() external {
    StandardHooksDeploymentConfig memory expectedConfig;
    expectedConfig.optional = StandardHooksConfig({
      hooksAddress: address(0),
      useOnDeposit: true,
      useOnQueueWithdrawal: true,
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
    assertEq(hooks.config(), expectedConfig, 'config.');
  }

  // ========================================================================== //
  //                          Role provider management                          //
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
    HooksConfig config = hooks.onCreateMarket(address(this), address(1), inputs, abi.encode(1e18));
    HooksConfig expectedConfig = encodeHooksConfig({
      hooksAddress: address(hooks),
      useOnDeposit: true,
      useOnQueueWithdrawal: true,
      useOnExecuteWithdrawal: false,
      useOnTransfer: true,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
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
    emit OpenTermHooks.MinimumDepositUpdated(address(1), 2e18);
    hooks.setMinimumDeposit(address(1), 2e18);
    assertEq(hooks.getHookedMarket(address(1)).minimumDeposit, 2e18, 'minimumDeposit');
  }

  function test_setMinimumDeposit_CallerNotBorrower() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    hooks.setMinimumDeposit(address(1), 1);
  }

  function test_setMinimumDeposit_NotHookedMarket() external {
    vm.expectRevert(OpenTermHooks.NotHookedMarket.selector);
    hooks.setMinimumDeposit(address(1), 1);
  }

  // ========================================================================== //
  //                               NotHookedMarket                              //
  // ========================================================================== //

  function test_onDeposit_NotHookedMarket() external {
    vm.expectRevert(OpenTermHooks.NotHookedMarket.selector);
    MarketState memory state;
    hooks.onDeposit(address(1), 0, state, '');
  }

  function test_onTransfer_NotHookedMarket() external {
    MarketState memory state;
    vm.expectRevert(OpenTermHooks.NotHookedMarket.selector);
    hooks.onTransfer(address(1), address(1), address(1), 0, state, '');
  }
}
