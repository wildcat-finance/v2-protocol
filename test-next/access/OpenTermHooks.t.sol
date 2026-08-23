// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { HookedMarket, OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { CreateProviderInputs } from 'src/access/ProviderStructs.sol';
import { ExistingProviderInputs } from 'src/access/ProviderStructs.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { RAY } from 'src/libraries/MathUtils.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketParameterConstraints } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetAnnualInterestAndReserveRatioBips } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';
import { NullProviderIndex, RoleProvider } from 'src/types/RoleProvider.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { MockRoleProviderFactory } from '../mocks/MockRoleProviderFactory.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract OpenTermHooksTest is TestKernel {
  event AccountMadeFirstDeposit(address indexed market, address indexed accountAddress);

  address internal constant MarketA = address(0x1001);
  address internal constant MarketB = address(0x1002);
  address internal constant MarketC = address(0x1003);
  address internal constant MarketD = address(0x1004);
  address internal constant Lender = address(0xA11CE);
  address internal constant SecondLender = address(0xB0B);
  address internal constant ThirdLender = address(0xCA401);
  address internal constant NewAdministrator = address(0xAD011);

  bytes4 internal constant PanicSelector = 0x4e487b71;
  uint256 internal constant PanicArithmetic = 0x11;

  OpenTermHooks internal hooks;
  MockRoleProvider internal provider1;
  MockRoleProvider internal provider2;
  MockRoleProviderFactory internal providerFactory;
  mapping(address account => bool registered) internal registeredBorrowers;
  address internal callbackPreviousAdministrator;
  address internal callbackNewAdministrator;

  function setUp() external {
    registeredBorrowers[address(this)] = true;
    provider1 = MockRoleProvider(
      _deployCode('test-next/mocks/MockRoleProvider.sol:MockRoleProvider')
    );
    provider2 = MockRoleProvider(
      _deployCode('test-next/mocks/MockRoleProvider.sol:MockRoleProvider')
    );
    providerFactory = MockRoleProviderFactory(
      _deployCode('test-next/mocks/MockRoleProviderFactory.sol:MockRoleProviderFactory')
    );
    NameAndProviderInputs memory inputs;
    hooks = _newHooks(address(this), inputs);
  }

  function archController() external view returns (address) {
    return address(this);
  }

  function isRegisteredBorrower(address account) external view returns (bool) {
    return registeredBorrowers[account];
  }

  function onHooksAdministratorTransferred(
    address previousAdministrator,
    address newAdministrator
  ) external {
    assertEq(msg.sender, address(hooks), 'callback caller');
    callbackPreviousAdministrator = previousAdministrator;
    callbackNewAdministrator = newAdministrator;
  }

  function _newHooks(
    address administrator,
    NameAndProviderInputs memory inputs
  ) internal returns (OpenTermHooks deployed) {
    deployed = OpenTermHooks(
      _deployCode(
        'src/access/OpenTermHooks.sol:OpenTermHooks',
        abi.encode(administrator, abi.encode(inputs))
      )
    );
  }

  function _requestedConfig(
    OpenTermHooks target,
    bool deposit,
    bool queueWithdrawal,
    bool transfer
  ) internal pure returns (HooksConfig config) {
    config = EmptyHooksConfig.setHooksAddress(address(target));
    if (deposit) config = config.setFlag(Bit_Enabled_Deposit);
    if (queueWithdrawal) config = config.setFlag(Bit_Enabled_QueueWithdrawal);
    if (transfer) config = config.setFlag(Bit_Enabled_Transfer);
  }

  function _createMarket(
    OpenTermHooks target,
    address market,
    HooksConfig requestedConfig,
    bytes memory hooksData
  ) internal returns (HooksConfig effectiveConfig) {
    DeployMarketInputs memory inputs;
    inputs.hooks = requestedConfig;
    effectiveConfig = target.onCreateMarket(address(this), market, inputs, hooksData);
  }

  function _assertConfig(
    HooksConfig actual,
    HooksConfig expected,
    string memory message
  ) internal pure {
    assertEq(HooksConfig.unwrap(actual), HooksConfig.unwrap(expected), message);
  }

  function _assertProvider(
    OpenTermHooks target,
    address providerAddress,
    uint32 timeToLive,
    bool isPullProvider,
    uint24 providerIndex
  ) internal view {
    RoleProvider provider = target.getRoleProvider(providerAddress);
    assertEq(provider.providerAddress(), providerAddress, 'provider address');
    assertEq(provider.timeToLive(), timeToLive, 'provider ttl');
    assertEq(
      provider.pullProviderIndex(),
      isPullProvider ? providerIndex : NullProviderIndex,
      'pull index'
    );
    assertEq(
      provider.pushProviderIndex(),
      isPullProvider ? NullProviderIndex : providerIndex,
      'push index'
    );

    RoleProvider[] memory providers = isPullProvider
      ? target.getPullProviders()
      : target.getPushProviders();
    assertEq(providers[providerIndex].providerAddress(), providerAddress, 'provider list');
  }

  function _assertHookedMarket(
    OpenTermHooks target,
    address market,
    bool transferRequiresAccess,
    bool depositRequiresAccess,
    uint128 minimumDeposit,
    bool transfersDisabled
  ) internal view {
    HookedMarket memory config = target.getHookedMarket(market);
    assertTrue(config.isHooked, 'is hooked');
    assertEq(config.transferRequiresAccess, transferRequiresAccess, 'transfer access');
    assertEq(config.depositRequiresAccess, depositRequiresAccess, 'deposit access');
    assertEq(config.minimumDeposit, minimumDeposit, 'minimum deposit');
    assertEq(config.transfersDisabled, transfersDisabled, 'transfers disabled');
  }

  function _addPullProvider(OpenTermHooks target) internal {
    provider1.setIsPullProvider(true);
    target.addRoleProvider(address(provider1), type(uint32).max);
  }

  function _credentialData(bytes memory credential) internal view returns (bytes memory) {
    return abi.encodePacked(address(provider1), credential);
  }

  function test_metadataConfigAndConstraints_AreCanonical() external view {
    assertEq(hooks.factory(), address(this), 'factory');
    assertEq(hooks.administrator(), address(this), 'administrator');
    assertEq(hooks.version(), 'OpenTermHooks', 'version');

    HooksConfig optionalFlags = EmptyHooksConfig
      .setFlag(Bit_Enabled_Deposit)
      .setFlag(Bit_Enabled_QueueWithdrawal)
      .setFlag(Bit_Enabled_Transfer);
    HooksConfig requiredFlags = EmptyHooksConfig.setFlag(
      Bit_Enabled_SetAnnualInterestAndReserveRatioBips
    );
    HooksDeploymentConfig expectedConfig = encodeHooksDeploymentConfig(
      optionalFlags,
      requiredFlags
    );
    assertEq(
      HooksDeploymentConfig.unwrap(hooks.config()),
      HooksDeploymentConfig.unwrap(expectedConfig),
      'deployment config'
    );

    MarketParameterConstraints memory constraints = hooks.getParameterConstraints();
    assertEq(constraints.minimumDelinquencyGracePeriod, 0, 'minimum grace period');
    assertEq(constraints.maximumDelinquencyGracePeriod, 90 days, 'maximum grace period');
    assertEq(constraints.minimumReserveRatioBips, 0, 'minimum reserve ratio');
    assertEq(constraints.maximumReserveRatioBips, 10_000, 'maximum reserve ratio');
    assertEq(constraints.minimumDelinquencyFeeBips, 0, 'minimum delinquency fee');
    assertEq(constraints.maximumDelinquencyFeeBips, 10_000, 'maximum delinquency fee');
    assertEq(constraints.minimumWithdrawalBatchDuration, 0, 'minimum batch duration');
    assertEq(constraints.maximumWithdrawalBatchDuration, 365 days, 'maximum batch duration');
    assertEq(constraints.minimumAnnualInterestBips, 0, 'minimum APR');
    assertEq(constraints.maximumAnnualInterestBips, 10_000, 'maximum APR');
  }

  function test_constructor_InitializesExistingProviders(
    bool firstIsPull,
    bool secondIsPull,
    uint32 firstTtl,
    uint32 secondTtl
  ) external {
    provider1.setIsPullProvider(firstIsPull);
    provider2.setIsPullProvider(secondIsPull);

    NameAndProviderInputs memory inputs;
    inputs.name = 'existing providers';
    inputs.existingProviders = new ExistingProviderInputs[](2);
    inputs.existingProviders[0] = ExistingProviderInputs(address(provider1), firstTtl);
    inputs.existingProviders[1] = ExistingProviderInputs(address(provider2), secondTtl);
    OpenTermHooks deployed = _newHooks(address(this), inputs);

    _assertProvider(deployed, address(provider1), firstTtl, firstIsPull, 0);
    _assertProvider(
      deployed,
      address(provider2),
      secondTtl,
      secondIsPull,
      firstIsPull == secondIsPull ? 1 : 0
    );
    assertEq(deployed.name(), inputs.name, 'name');
  }

  function test_constructor_CreatesNewProviders(
    bool firstIsPull,
    bool secondIsPull,
    uint32 firstTtl,
    uint32 secondTtl
  ) external {
    bytes32 firstSalt = bytes32(uint256(1));
    bytes32 secondSalt = bytes32(uint256(2));
    NameAndProviderInputs memory inputs;
    inputs.name = 'new providers';
    inputs.roleProviderFactory = address(providerFactory);
    inputs.newProviderInputs = new CreateProviderInputs[](2);
    inputs.newProviderInputs[0] = CreateProviderInputs(
      firstTtl,
      abi.encode(firstSalt, firstIsPull)
    );
    inputs.newProviderInputs[1] = CreateProviderInputs(
      secondTtl,
      abi.encode(secondSalt, secondIsPull)
    );
    address firstProvider = providerFactory.computeProviderAddress(firstSalt);
    address secondProvider = providerFactory.computeProviderAddress(secondSalt);
    OpenTermHooks deployed = _newHooks(address(this), inputs);

    _assertProvider(deployed, firstProvider, firstTtl, firstIsPull, 0);
    _assertProvider(
      deployed,
      secondProvider,
      secondTtl,
      secondIsPull,
      firstIsPull == secondIsPull ? 1 : 0
    );
    assertEq(deployed.name(), inputs.name, 'name');
  }

  function test_constructor_CombinesExistingAndNewProviders(
    bool existingIsPull,
    bool newIsPull,
    uint32 existingTtl,
    uint32 newTtl
  ) external {
    provider1.setIsPullProvider(existingIsPull);
    bytes32 salt = bytes32(uint256(3));
    NameAndProviderInputs memory inputs;
    inputs.name = 'mixed providers';
    inputs.roleProviderFactory = address(providerFactory);
    inputs.existingProviders = new ExistingProviderInputs[](1);
    inputs.existingProviders[0] = ExistingProviderInputs(address(provider1), existingTtl);
    inputs.newProviderInputs = new CreateProviderInputs[](1);
    inputs.newProviderInputs[0] = CreateProviderInputs(newTtl, abi.encode(salt, newIsPull));
    address newProvider = providerFactory.computeProviderAddress(salt);
    OpenTermHooks deployed = _newHooks(address(this), inputs);

    _assertProvider(deployed, address(provider1), existingTtl, existingIsPull, 0);
    _assertProvider(deployed, newProvider, newTtl, newIsPull, existingIsPull == newIsPull ? 1 : 0);
    assertEq(deployed.name(), inputs.name, 'name');
  }

  function test_constructor_RejectsInvalidProviderFactoryResults() external {
    NameAndProviderInputs memory inputs;
    inputs.newProviderInputs = new CreateProviderInputs[](1);
    vm.expectRevert(BaseAccessControls.RoleProviderFactoryRequired.selector);
    _newHooks(address(this), inputs);

    providerFactory.setNextProviderAddress(address(0));
    inputs.roleProviderFactory = address(providerFactory);
    vm.expectRevert(BaseAccessControls.CreateRoleProviderFailed.selector);
    _newHooks(address(this), inputs);
  }

  function test_onCreateMarket_AuthenticatesFactoryAndAdministrator() external {
    DeployMarketInputs memory inputs;
    vm.prank(address(0xBAD));
    vm.expectRevert(IHooks.CallerNotFactory.selector);
    hooks.onCreateMarket(address(this), MarketA, inputs, '');

    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.onCreateMarket(address(0xBAD), MarketA, inputs, '');
  }

  function test_onCreateMarket_ConfiguresFlagsAndMarketPolicies() external {
    HooksConfig aprFlag = EmptyHooksConfig.setHooksAddress(address(hooks)).setFlag(
      Bit_Enabled_SetAnnualInterestAndReserveRatioBips
    );
    HooksConfig actual = _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      ''
    );
    _assertConfig(actual, aprFlag, 'empty config');
    _assertHookedMarket(hooks, MarketA, false, false, 0, false);

    vm.expectEmit(address(hooks));
    emit OpenTermHooks.MinimumDepositUpdated(MarketB, address(this), 0, 100);
    actual = _createMarket(
      hooks,
      MarketB,
      _requestedConfig(hooks, false, false, false),
      abi.encode(uint128(100))
    );
    _assertConfig(actual, aprFlag.setFlag(Bit_Enabled_Deposit), 'minimum config');
    _assertHookedMarket(hooks, MarketB, false, false, 100, false);

    HooksConfig queueConfig = _requestedConfig(hooks, true, true, true);
    actual = _createMarket(hooks, MarketC, queueConfig, abi.encode(uint128(0)));
    _assertConfig(
      actual,
      queueConfig.setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips),
      'queue config'
    );
    _assertHookedMarket(hooks, MarketC, true, true, 0, false);

    HooksConfig disabledConfig = _requestedConfig(hooks, true, true, false);
    actual = _createMarket(hooks, MarketD, disabledConfig, abi.encode(uint128(0), true));
    _assertConfig(
      actual,
      disabledConfig.setFlag(Bit_Enabled_Transfer).setFlag(
        Bit_Enabled_SetAnnualInterestAndReserveRatioBips
      ),
      'disabled config'
    );
    _assertHookedMarket(hooks, MarketD, false, true, 0, true);
    assertFalse(hooks.isMarketTransferDisabled(MarketC), 'enabled transfer query');
    assertTrue(hooks.isMarketTransferDisabled(MarketD), 'disabled transfer query');

    address[] memory markets = new address[](4);
    markets[0] = MarketA;
    markets[1] = MarketB;
    markets[2] = MarketC;
    markets[3] = MarketD;
    HookedMarket[] memory marketConfigs = hooks.getHookedMarkets(markets);
    assertEq(marketConfigs.length, 4, 'market config count');
    assertEq(marketConfigs[1].minimumDeposit, 100, 'batch minimum deposit');
    assertTrue(marketConfigs[3].transfersDisabled, 'batch transfer policy');
  }

  function test_onCreateMarket_RejectsInvalidAccessAndMinimumData() external {
    vm.expectRevert(OpenTermHooks.InvalidAccessConfiguration.selector);
    _createMarket(hooks, MarketA, _requestedConfig(hooks, false, true, false), '');

    vm.expectRevert(OpenTermHooks.InvalidAccessConfiguration.selector);
    _createMarket(hooks, MarketB, _requestedConfig(hooks, true, true, false), '');

    vm.expectRevert(abi.encodePacked(PanicSelector, PanicArithmetic));
    _createMarket(
      hooks,
      MarketC,
      _requestedConfig(hooks, false, false, false),
      abi.encode(type(uint136).max)
    );
  }

  function test_administratorTransfer_PreservesMarketConfigurationAndMovesAuthority() external {
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(uint128(100), true)
    );
    bytes32 configBefore = keccak256(abi.encode(hooks.getHookedMarket(MarketA)));
    registeredBorrowers[NewAdministrator] = true;
    hooks.requestAdministratorTransfer(NewAdministrator);
    vm.prank(NewAdministrator);
    hooks.acceptAdministratorTransfer();

    assertEq(hooks.administrator(), NewAdministrator, 'administrator');
    assertEq(callbackPreviousAdministrator, address(this), 'callback previous administrator');
    assertEq(callbackNewAdministrator, NewAdministrator, 'callback new administrator');
    assertEq(keccak256(abi.encode(hooks.getHookedMarket(MarketA))), configBefore, 'market config');

    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.setMinimumDeposit(MarketA, 200);
    vm.prank(NewAdministrator);
    hooks.setMinimumDeposit(MarketA, 200);
    assertEq(hooks.getHookedMarket(MarketA).minimumDeposit, 200, 'updated minimum');
  }

  function test_setMinimumDeposit_EnforcesMarketDispatchAndAuthority() external {
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(uint128(100))
    );
    vm.expectEmit(address(hooks));
    emit OpenTermHooks.MinimumDepositUpdated(MarketA, address(this), 100, 200);
    hooks.setMinimumDeposit(MarketA, 200);
    assertEq(hooks.getHookedMarket(MarketA).minimumDeposit, 200, 'updated minimum');

    _createMarket(hooks, MarketB, _requestedConfig(hooks, false, false, false), '');
    vm.expectRevert(OpenTermHooks.DepositHookNotEnabled.selector);
    hooks.setMinimumDeposit(MarketB, 1);
    hooks.setMinimumDeposit(MarketB, 0);

    vm.expectRevert(OpenTermHooks.NotHookedMarket.selector);
    hooks.setMinimumDeposit(MarketC, 1);

    vm.prank(address(0xBAD));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.setMinimumDeposit(MarketA, 1);
  }

  function test_unhookedMarketEndpoints_Reject() external {
    MarketState memory state;
    vm.expectRevert(OpenTermHooks.NotHookedMarket.selector);
    hooks.onDeposit(Lender, 0, state, '');
    vm.expectRevert(OpenTermHooks.NotHookedMarket.selector);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.expectRevert(OpenTermHooks.NotHookedMarket.selector);
    hooks.onTransfer(Lender, Lender, SecondLender, 0, state, '');
    vm.expectRevert(OpenTermHooks.NotHookedMarket.selector);
    hooks.isMarketTransferDisabled(MarketA);
    vm.expectRevert(OpenTermHooks.NotHookedMarket.selector);
    hooks.isMarketTransferRecipientAllowed(MarketA, Lender);
  }

  function test_onDeposit_EnforcesMinimumBlockAndCredentialPolicies() external {
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(uint128(100))
    );
    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    vm.prank(MarketA);
    vm.expectRevert(OpenTermHooks.DepositBelowMinimum.selector);
    hooks.onDeposit(Lender, 99, state, '');

    vm.prank(MarketA);
    hooks.onDeposit(Lender, 100, state, '');
    assertFalse(hooks.isKnownLenderOnMarket(Lender, MarketA), 'open-deposit known lender');

    hooks.blockFromDeposits(Lender);
    vm.prank(MarketA);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onDeposit(Lender, 100, state, '');

    _createMarket(hooks, MarketB, _requestedConfig(hooks, true, false, false), '');
    vm.prank(MarketB);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onDeposit(SecondLender, 1, state, '');

    _addPullProvider(hooks);
    bytes memory credential = abi.encode('deposit');
    provider1.approveCredentialData(keccak256(credential), uint32(block.timestamp));
    vm.prank(MarketB);
    hooks.onDeposit(SecondLender, 1, state, _credentialData(credential));
    assertTrue(hooks.isKnownLenderOnMarket(SecondLender, MarketB), 'restricted known lender');
  }

  function test_onQueueWithdrawal_PreservesKnownAccessAndValidatesUnknownLenders() external {
    _createMarket(hooks, MarketA, _requestedConfig(hooks, true, true, true), '');
    _addPullProvider(hooks);
    vm.prank(address(provider1));
    hooks.grantRole(Lender, uint32(block.timestamp));

    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    vm.expectEmit(address(hooks));
    emit AccountMadeFirstDeposit(MarketA, Lender);
    vm.prank(MarketA);
    hooks.onDeposit(Lender, 1, state, '');
    assertTrue(hooks.isKnownLenderOnMarket(Lender, MarketA), 'known lender');
    vm.prank(address(provider1));
    hooks.revokeRole(Lender);
    vm.prank(MarketA);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');

    vm.prank(MarketA);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onQueueWithdrawal(SecondLender, 0, 1, state, '');

    bytes memory credential = abi.encode('queue withdrawal');
    provider1.approveCredentialData(keccak256(credential), uint32(block.timestamp));
    vm.prank(MarketA);
    hooks.onQueueWithdrawal(SecondLender, 0, 1, state, _credentialData(credential));
    LenderStatus memory status = hooks.getPreviousLenderStatus(SecondLender);
    assertEq(status.lastProvider, address(provider1), 'last provider');
    assertEq(status.lastApprovalTimestamp, uint32(block.timestamp), 'approval timestamp');
    assertFalse(
      hooks.isKnownLenderOnMarket(SecondLender, MarketA),
      'withdrawal does not mark known'
    );
  }

  function test_onTransfer_EnforcesDisabledAndCredentialPolicies() external {
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, true, true, false),
      abi.encode(uint128(0), true)
    );
    MarketState memory state;
    vm.prank(MarketA);
    vm.expectRevert(OpenTermHooks.TransfersDisabled.selector);
    hooks.onTransfer(Lender, Lender, SecondLender, 1, state, '');
    assertFalse(hooks.isMarketTransferRecipientAllowed(MarketA, SecondLender));

    _createMarket(hooks, MarketB, _requestedConfig(hooks, false, false, true), '');
    vm.prank(MarketB);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onTransfer(Lender, Lender, SecondLender, 1, state, '');
    assertFalse(hooks.isMarketTransferRecipientAllowed(MarketB, SecondLender));

    _addPullProvider(hooks);
    bytes memory credential = abi.encode('transfer');
    provider1.approveCredentialData(keccak256(credential), uint32(block.timestamp));
    vm.prank(MarketB);
    hooks.onTransfer(Lender, Lender, SecondLender, 1, state, _credentialData(credential));
    assertTrue(hooks.isKnownLenderOnMarket(SecondLender, MarketB), 'known recipient');
    assertTrue(hooks.isMarketTransferRecipientAllowed(MarketB, SecondLender), 'known allowed');

    vm.prank(address(provider1));
    hooks.revokeRole(SecondLender);
    vm.prank(MarketB);
    hooks.onTransfer(Lender, Lender, SecondLender, 1, state, '');

    hooks.blockFromDeposits(ThirdLender);
    vm.prank(MarketB);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onTransfer(Lender, Lender, ThirdLender, 1, state, '');
  }

  function test_unrestrictedCallbacks_AreNoOpsAndAprDelegates() external {
    MarketState memory state;
    state.annualInterestBips = 1_000;
    state.reserveRatioBips = 500;
    bytes memory extraData = abi.encode('unused');

    vm.startPrank(MarketA);
    hooks.onExecuteWithdrawal(Lender, 1, 2, state, extraData);
    hooks.onBorrow(3, state, extraData);
    hooks.onRepay(4, state, extraData);
    hooks.onCloseMarket(state, extraData);
    hooks.onNukeFromOrbit(Lender, state, extraData);
    hooks.onSetMaxTotalSupply(5, state, extraData);
    (uint16 annualInterestBips, uint16 reserveRatioBips) = hooks
      .onSetAnnualInterestAndReserveRatioBips(1_000, 9_999, state, extraData);
    hooks.onSetProtocolFeeBips(6, state, extraData);
    vm.stopPrank();

    assertEq(annualInterestBips, 1_000, 'APR');
    assertEq(reserveRatioBips, 500, 'reserve ratio');
  }
}
