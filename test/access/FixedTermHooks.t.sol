// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseHooks } from 'src/access/BaseHooks.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { HookedMarket } from 'src/access/FixedTermHooks.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract FixedTermHooksTest is TestKernel {
  address internal constant MarketA = address(0x2001);
  address internal constant MarketB = address(0x2002);
  address internal constant MarketC = address(0x2003);
  address internal constant MarketD = address(0x2004);
  address internal constant Lender = address(0xA11CE);
  address internal constant SecondLender = address(0xB0B);
  address internal constant ThirdLender = address(0xCA401);
  address internal constant NewAdministrator = address(0xAD011);

  bytes4 internal constant PanicSelector = 0x4e487b71;
  uint256 internal constant PanicArithmetic = 0x11;

  FixedTermHooks internal hooks;
  MockRoleProvider internal provider1;
  MockRoleProvider internal provider2;
  mapping(address account => bool registered) internal registeredBorrowers;
  address internal callbackPreviousAdministrator;
  address internal callbackNewAdministrator;

  function setUp() external {
    registeredBorrowers[address(this)] = true;
    provider1 = MockRoleProvider(_deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider'));
    provider2 = MockRoleProvider(_deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider'));
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
  ) internal returns (FixedTermHooks deployed) {
    deployed = FixedTermHooks(
      _deployCode(
        'src/access/FixedTermHooks.sol:FixedTermHooks',
        abi.encode(administrator, abi.encode(inputs))
      )
    );
  }

  function _term() internal view returns (uint32) {
    return uint32(block.timestamp + 365 days);
  }

  function _requestedConfig(
    FixedTermHooks target,
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
    FixedTermHooks target,
    address market,
    HooksConfig requestedConfig,
    bytes memory hooksData
  ) internal returns (HooksConfig effectiveConfig) {
    DeployMarketInputs memory inputs;
    inputs.hooks = requestedConfig;
    effectiveConfig = target.onCreateMarket(address(this), market, inputs, hooksData);
  }

  function _addPullProvider(FixedTermHooks target) internal {
    provider1.setIsPullProvider(true);
    target.addRoleProvider(address(provider1), type(uint32).max);
  }

  function test_metadata_IsCanonical() external view {
    assertEq(hooks.version(), 'FixedTermHooks', 'version');
    assertEq(hooks.MaximumLoanTerm(), 365 days, 'maximum loan term');
  }

  function test_onCreateMarket_ValidatesTermData() external {
    DeployMarketInputs memory inputs;
    vm.expectRevert(FixedTermHooks.FixedTermNotProvided.selector);
    hooks.onCreateMarket(address(this), MarketA, inputs, '');

    vm.expectRevert(FixedTermHooks.InvalidFixedTerm.selector);
    hooks.onCreateMarket(address(this), MarketA, inputs, abi.encode(uint32(block.timestamp - 1)));

    vm.expectRevert(FixedTermHooks.InvalidFixedTerm.selector);
    hooks.onCreateMarket(
      address(this),
      MarketA,
      inputs,
      abi.encode(uint32(block.timestamp + 365 days + 1))
    );

    _createMarket(
      hooks,
      MarketD,
      _requestedConfig(hooks, false, false, false),
      abi.encode(uint32(block.timestamp))
    );
    assertEq(hooks.getHookedMarket(MarketD).fixedTermEndTime, block.timestamp, 'zero term');
  }

  function test_onCreateMarket_PreservesTermPermissionsAndBatchReads(
    bool allowClosureBeforeTerm,
    bool allowTermReduction
  ) external {
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(_term(), uint128(0), false, allowClosureBeforeTerm, allowTermReduction)
    );
    HookedMarket memory config = hooks.getHookedMarket(MarketA);
    assertEq(config.fixedTermEndTime, _term(), 'term');
    assertEq(config.allowClosureBeforeTerm, allowClosureBeforeTerm, 'closure permission');
    assertEq(config.allowTermReduction, allowTermReduction, 'term permission');
    address[] memory markets = new address[](2);
    markets[0] = MarketA;
    markets[1] = MarketB;
    HookedMarket[] memory configs = hooks.getHookedMarkets(markets);
    assertEq(configs.length, 2, 'market count');
    assertEq(abi.encode(configs[0]), abi.encode(config), 'batch configuration');
    HookedMarket memory empty;
    assertEq(abi.encode(configs[1]), abi.encode(empty), 'unknown batch configuration');
    assertEq(
      abi.encode(hooks.getHookedMarket(MarketB)),
      abi.encode(empty),
      'unknown single configuration'
    );
  }

  function test_onCreateMarket_PreservesTermDecodeAndMinimumFailureOrder() external {
    DeployMarketInputs memory inputs;
    vm.expectRevert(FixedTermHooks.FixedTermNotProvided.selector);
    hooks.onCreateMarket(address(this), MarketA, inputs, new bytes(31));
    vm.expectRevert(FixedTermHooks.InvalidFixedTerm.selector);
    hooks.onCreateMarket(
      address(this),
      MarketA,
      inputs,
      abi.encode(uint256(vm.getBlockTimestamp()) - 1, uint256(type(uint128).max) + 1)
    );
    vm.expectRevert(abi.encodePacked(PanicSelector, PanicArithmetic));
    hooks.onCreateMarket(
      address(this),
      MarketA,
      inputs,
      abi.encode(uint256(type(uint32).max) + 1, uint256(type(uint128).max) + 1)
    );
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(_term(), uint128(1), uint256(2), uint256(3), uint256(2))
    );
    HookedMarket memory config = hooks.getHookedMarket(MarketA);
    assertFalse(config.transfersDisabled, 'even transfer flag');
    assertTrue(config.allowClosureBeforeTerm, 'odd closure flag');
    assertFalse(config.allowTermReduction, 'even term flag');
  }

  function test_administratorTransfer_PreservesMarketConfigurationAndMovesAuthority() external {
    uint32 term = _term();
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(term, uint128(100), true, true, true)
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

  function test_setFixedTermEndTime_EnforcesReductionPolicyAndAuthority() external {
    uint32 term = _term();
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(term, uint128(0), false, false, true)
    );
    vm.expectEmit(address(hooks));
    emit FixedTermHooks.FixedTermUpdated(MarketA, address(this), term, term - 1 days);
    hooks.setFixedTermEndTime(MarketA, term - 1 days);
    assertEq(hooks.getHookedMarket(MarketA).fixedTermEndTime, term - 1 days, 'reduced term');

    vm.expectRevert(FixedTermHooks.IncreaseFixedTerm.selector);
    hooks.setFixedTermEndTime(MarketA, term);

    _createMarket(hooks, MarketB, _requestedConfig(hooks, false, false, false), abi.encode(term));
    vm.expectRevert(FixedTermHooks.TermReductionDisabled.selector);
    hooks.setFixedTermEndTime(MarketB, term - 1 days);

    vm.expectRevert(BaseHooks.NotHookedMarket.selector);
    hooks.setFixedTermEndTime(MarketC, 0);
    vm.prank(address(0xBAD));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.setFixedTermEndTime(MarketA, 0);
  }

  function test_unhookedCloseMarket_Rejects() external {
    MarketState memory state;
    vm.expectRevert(BaseHooks.NotHookedMarket.selector);
    hooks.onCloseMarket(state, '');
  }

  function test_onQueueWithdrawal_ChecksMaturityBeforeKnownOrCredentialAccess() external {
    uint32 term = _term();
    _createMarket(hooks, MarketA, _requestedConfig(hooks, true, true, true), abi.encode(term));
    _createMarket(hooks, MarketB, _requestedConfig(hooks, false, false, false), abi.encode(term));
    _addPullProvider(hooks);
    vm.prank(address(provider1));
    hooks.grantRole(Lender, uint32(block.timestamp));
    MarketState memory state;
    vm.prank(MarketA);
    hooks.onDeposit(Lender, 1, state, '');
    hooks.blockFromDeposits(Lender);

    vm.warp(term - 1);
    state.isClosed = true;
    vm.prank(MarketA);
    vm.expectRevert(FixedTermHooks.WithdrawBeforeTermEnd.selector);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.prank(MarketA);
    vm.expectRevert(FixedTermHooks.WithdrawBeforeTermEnd.selector);
    hooks.onQueueWithdrawal(SecondLender, 0, 1, state, '');

    vm.warp(term);
    state.isClosed = false;
    vm.prank(MarketA);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.prank(MarketA);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onQueueWithdrawal(SecondLender, 0, 1, state, '');
    vm.prank(MarketB);
    hooks.onQueueWithdrawal(ThirdLender, 0, 1, state, '');
  }

  function test_onSetApr_BlocksReductionDuringTermAndDelegatesAllowedChanges() external {
    uint32 term = _term();
    _createMarket(hooks, MarketA, _requestedConfig(hooks, false, false, false), abi.encode(term));
    MarketState memory state;
    state.annualInterestBips = 100;
    state.reserveRatioBips = 1_000;

    vm.prank(MarketA);
    vm.expectRevert(FixedTermHooks.NoReducingAprBeforeTermEnd.selector);
    hooks.onSetAnnualInterestAndReserveRatioBips(99, 500, state, '');

    vm.prank(MarketA);
    (uint16 annualInterestBips, uint16 reserveRatioBips) = hooks
      .onSetAnnualInterestAndReserveRatioBips(101, 500, state, '');
    assertEq(annualInterestBips, 101, 'increased APR');
    assertEq(reserveRatioBips, 1_000, 'increased reserve ratio');

    vm.warp(term);
    vm.prank(MarketA);
    (annualInterestBips, reserveRatioBips) = hooks.onSetAnnualInterestAndReserveRatioBips(
      99,
      500,
      state,
      ''
    );
    assertEq(annualInterestBips, 99, 'post-term APR');
    assertEq(reserveRatioBips, 1_000, 'post-term reserve ratio');
  }

  function test_onCloseMarket_EnforcesEarlyClosurePolicyAndUpdatesTerm() external {
    uint32 term = _term();
    MarketState memory state;
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(term, uint128(0), false, true, false)
    );
    vm.expectEmit(address(hooks));
    emit FixedTermHooks.FixedTermUpdated(MarketA, MarketA, term, uint32(block.timestamp));
    vm.prank(MarketA);
    hooks.onCloseMarket(state, '');
    assertEq(hooks.getHookedMarket(MarketA).fixedTermEndTime, block.timestamp, 'closure term');

    _createMarket(
      hooks,
      MarketB,
      _requestedConfig(hooks, false, false, false),
      abi.encode(term, uint128(0), false, false, true)
    );
    vm.prank(MarketB);
    hooks.onCloseMarket(state, '');
    assertEq(hooks.getHookedMarket(MarketB).fixedTermEndTime, block.timestamp, 'reduction closure');

    _createMarket(hooks, MarketC, _requestedConfig(hooks, false, false, false), abi.encode(term));
    vm.prank(MarketC);
    vm.expectRevert(FixedTermHooks.ClosureDisabledBeforeTerm.selector);
    hooks.onCloseMarket(state, '');

    vm.warp(term);
    vm.prank(MarketC);
    hooks.onCloseMarket(state, '');
    assertEq(hooks.getHookedMarket(MarketC).fixedTermEndTime, term, 'elapsed term');
  }
}
