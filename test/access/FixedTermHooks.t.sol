// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseHooks } from 'src/access/BaseHooks.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { FixedTermPolicy } from 'src/access/FixedTermPolicy.sol';
import { HookedMarket } from 'src/access/FixedTermHooks.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { FixedTermManagementHooks } from '../mocks/FixedTermManagementHooks.sol';
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

  function _newManagementHooks() internal returns (FixedTermManagementHooks target) {
    target = FixedTermManagementHooks(
      _deployCode(
        'test/mocks/FixedTermManagementHooks.sol:FixedTermManagementHooks',
        abi.encode(address(this))
      )
    );
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
    vm.expectRevert(FixedTermPolicy.FixedTermNotProvided.selector);
    hooks.onCreateMarket(address(this), MarketA, inputs, '');

    vm.expectRevert(FixedTermPolicy.InvalidFixedTerm.selector);
    hooks.onCreateMarket(address(this), MarketA, inputs, abi.encode(uint32(block.timestamp - 1)));

    vm.expectRevert(FixedTermPolicy.InvalidFixedTerm.selector);
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
    vm.expectRevert(FixedTermPolicy.FixedTermNotProvided.selector);
    hooks.onCreateMarket(address(this), MarketA, inputs, new bytes(31));
    vm.expectRevert(FixedTermPolicy.InvalidFixedTerm.selector);
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
    emit FixedTermPolicy.FixedTermUpdated(MarketA, address(this), term, term - 1 days);
    hooks.setFixedTermEndTime(MarketA, term - 1 days);
    assertEq(hooks.getHookedMarket(MarketA).fixedTermEndTime, term - 1 days, 'reduced term');

    vm.expectRevert(FixedTermPolicy.IncreaseFixedTerm.selector);
    hooks.setFixedTermEndTime(MarketA, term);

    _createMarket(hooks, MarketB, _requestedConfig(hooks, false, false, false), abi.encode(term));
    vm.expectRevert(FixedTermPolicy.TermReductionDisabled.selector);
    hooks.setFixedTermEndTime(MarketB, term - 1 days);

    vm.expectRevert(BaseHooks.NotHookedMarket.selector);
    hooks.setFixedTermEndTime(MarketC, 0);
    vm.prank(address(0xBAD));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.setFixedTermEndTime(MarketA, 0);
  }

  function test_setFixedTermEndTime_PreservesEqualAndPastTimeBehavior() external {
    uint32 term = _term();
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(term, uint128(0), false, false, true)
    );
    _createMarket(hooks, MarketB, _requestedConfig(hooks, false, false, false), abi.encode(term));

    vm.expectEmit(address(hooks));
    emit FixedTermPolicy.FixedTermUpdated(MarketA, address(this), term, term);
    hooks.setFixedTermEndTime(MarketA, term);
    assertEq(hooks.getHookedMarket(MarketA).fixedTermEndTime, term, 'equal term');
    vm.expectRevert(FixedTermPolicy.TermReductionDisabled.selector);
    hooks.setFixedTermEndTime(MarketB, term);
    vm.expectRevert(FixedTermPolicy.IncreaseFixedTerm.selector);
    hooks.setFixedTermEndTime(MarketB, term + 1);

    uint32 currentTime = uint32(vm.getBlockTimestamp());
    vm.expectEmit(address(hooks));
    emit FixedTermPolicy.FixedTermUpdated(MarketA, address(this), term, currentTime);
    hooks.setFixedTermEndTime(MarketA, currentTime);
    assertEq(hooks.getHookedMarket(MarketA).fixedTermEndTime, currentTime, 'term ends now');
    vm.expectEmit(address(hooks));
    emit FixedTermPolicy.FixedTermUpdated(MarketA, address(this), currentTime, currentTime - 1);
    hooks.setFixedTermEndTime(MarketA, currentTime - 1);
    assertEq(hooks.getHookedMarket(MarketA).fixedTermEndTime, currentTime - 1, 'past term');

    // queueing and APR read the reduced maturity, not the original creation timestamp.
    MarketState memory state;
    state.annualInterestBips = 100;
    state.reserveRatioBips = 1_000;
    vm.prank(MarketA);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.prank(MarketA);
    (uint16 apr, uint16 reserve) = hooks.onSetAnnualInterestAndReserveRatioBips(99, 0, state, '');
    assertEq(apr, 99, 'APR reduction after shortened term');
    assertEq(reserve, 1_000, 'current reserves');
  }

  function test_setFixedTermEndTime_ExtensionAcceptsAndObservesUpdatedTerm(
    uint32 reductionSeed
  ) external {
    FixedTermManagementHooks target = _newManagementHooks();
    uint32 term = _term();
    uint32 reduction = uint32(_bound(reductionSeed, 1, 30 days));
    _createMarket(
      target,
      MarketA,
      _requestedConfig(target, false, false, false),
      abi.encode(term, uint128(0), false, false, true)
    );
    target.setTermChangeLimits(MarketA, term - 2 * reduction, 2 * reduction);

    uint32 previousTime = term;
    for (uint32 i = 1; i <= 2; i++) {
      uint32 newTime = term - i * reduction;
      vm.expectEmit(address(target));
      emit FixedTermPolicy.FixedTermUpdated(MarketA, address(this), previousTime, newTime);
      vm.expectEmit(address(target));
      emit FixedTermManagementHooks.TermReductionRecorded(
        MarketA,
        previousTime,
        newTime,
        i * reduction
      );
      target.setFixedTermEndTime(MarketA, newTime);
      assertEq(target.getHookedMarket(MarketA).fixedTermEndTime, newTime, 'updated maturity');
      assertEq(target.totalTermReduction(MarketA), i * reduction, 'accumulated reduction');
      previousTime = newTime;
    }
  }

  function test_setFixedTermEndTime_ExtensionRejectsBeforeMaturityWrite() external {
    FixedTermManagementHooks target = _newManagementHooks();
    uint32 term = _term();
    _createMarket(
      target,
      MarketA,
      _requestedConfig(target, false, false, false),
      abi.encode(term, uint128(0), false, false, true)
    );
    target.setTermChangeLimits(MarketA, term - 10 days, 20 days);
    target.setFixedTermEndTime(MarketA, term - 5 days);
    bytes memory configBefore = abi.encode(target.getHookedMarket(MarketA));

    vm.expectRevert(FixedTermManagementHooks.InsufficientTermNotice.selector);
    target.setFixedTermEndTime(MarketA, term - 10 days - 1);
    assertEq(abi.encode(target.getHookedMarket(MarketA)), configBefore, 'configuration preserved');
    assertEq(target.totalTermReduction(MarketA), 5 days, 'prior feature state preserved');

    target.setFixedTermEndTime(MarketA, term - 10 days);
    assertEq(target.getHookedMarket(MarketA).fixedTermEndTime, term - 10 days, 'notice boundary');
    assertEq(target.totalTermReduction(MarketA), 10 days, 'accepted retry');
  }

  function test_setFixedTermEndTime_NativeChecksPrecedeExtensionRejection() external {
    FixedTermManagementHooks target = _newManagementHooks();
    uint32 term = _term();
    _createMarket(
      target,
      MarketA,
      _requestedConfig(target, false, false, false),
      abi.encode(term, uint128(0), false, false, true)
    );
    _createMarket(target, MarketB, _requestedConfig(target, false, false, false), abi.encode(term));
    // every attempted update also fails the feature rule if it gets that far.
    target.setTermChangeLimits(MarketA, term + 2, 0);
    target.setTermChangeLimits(MarketB, term + 2, 0);
    target.setTermChangeLimits(MarketC, term + 2, 0);

    vm.prank(address(0xBAD));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    target.setFixedTermEndTime(MarketC, 0);
    vm.expectRevert(BaseHooks.NotHookedMarket.selector);
    target.setFixedTermEndTime(MarketC, 0);
    vm.expectRevert(FixedTermPolicy.TermReductionDisabled.selector);
    target.setFixedTermEndTime(MarketB, term - 1);
    vm.expectRevert(FixedTermPolicy.TermReductionDisabled.selector);
    target.setFixedTermEndTime(MarketB, term);
    vm.expectRevert(FixedTermPolicy.IncreaseFixedTerm.selector);
    target.setFixedTermEndTime(MarketB, term + 1);
    vm.expectRevert(FixedTermPolicy.IncreaseFixedTerm.selector);
    target.setFixedTermEndTime(MarketA, term + 1);
    vm.expectRevert(FixedTermManagementHooks.InsufficientTermNotice.selector);
    target.setFixedTermEndTime(MarketA, term);

    assertEq(target.getHookedMarket(MarketA).fixedTermEndTime, term, 'enabled market unchanged');
    assertEq(target.getHookedMarket(MarketB).fixedTermEndTime, term, 'disabled market unchanged');
    assertFalse(target.getHookedMarket(MarketC).isHooked, 'unknown market stays unknown');
    assertEq(target.totalTermReduction(MarketA), 0, 'no enabled-market feature effects');
    assertEq(target.totalTermReduction(MarketB), 0, 'no disabled-market feature effects');
    assertEq(target.totalTermReduction(MarketC), 0, 'no unknown-market feature effects');
  }

  function test_setFixedTermEndTime_AfterExtensionRejectionRollsBackTermAndBudget() external {
    FixedTermManagementHooks target = _newManagementHooks();
    uint32 term = _term();
    _createMarket(
      target,
      MarketA,
      _requestedConfig(target, false, false, false),
      abi.encode(term, uint128(0), false, false, true)
    );
    target.setTermChangeLimits(MarketA, 0, 10 days);
    target.setFixedTermEndTime(MarketA, term - 5 days);
    bytes memory configBefore = abi.encode(target.getHookedMarket(MarketA));

    vm.expectRevert(FixedTermManagementHooks.TermReductionBudgetExceeded.selector);
    target.setFixedTermEndTime(MarketA, term - 10 days - 1);
    assertEq(abi.encode(target.getHookedMarket(MarketA)), configBefore, 'maturity rolled back');
    assertEq(target.totalTermReduction(MarketA), 5 days, 'feature write rolled back');

    target.setFixedTermEndTime(MarketA, term - 10 days);
    assertEq(target.getHookedMarket(MarketA).fixedTermEndTime, term - 10 days, 'accepted retry');
    assertEq(target.totalTermReduction(MarketA), 10 days, 'budget charged only once');
  }

  function test_termChangeExtensions_DoNotRunOnCreationOrEarlyClosure() external {
    FixedTermManagementHooks target = _newManagementHooks();
    uint32 term = _term();
    target.setTermChangeLimits(MarketA, term + 1, 0);
    _createMarket(
      target,
      MarketA,
      _requestedConfig(target, false, false, false),
      abi.encode(term, uint128(0), false, true, false)
    );
    assertEq(target.getHookedMarket(MarketA).fixedTermEndTime, term, 'creation keeps its rules');

    MarketState memory state;
    vm.expectEmit(address(target));
    emit FixedTermPolicy.FixedTermUpdated(MarketA, MarketA, term, uint32(block.timestamp));
    vm.prank(MarketA);
    target.onCloseMarket(state, '');
    assertEq(target.getHookedMarket(MarketA).fixedTermEndTime, block.timestamp, 'closure maturity');
    assertEq(target.totalTermReduction(MarketA), 0, 'closure does not consume setter budget');
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
    vm.expectRevert(FixedTermPolicy.WithdrawBeforeTermEnd.selector);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.prank(MarketA);
    vm.expectRevert(FixedTermPolicy.WithdrawBeforeTermEnd.selector);
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
    vm.expectRevert(FixedTermPolicy.NoReducingAprBeforeTermEnd.selector);
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
    emit FixedTermPolicy.FixedTermUpdated(MarketA, MarketA, term, uint32(block.timestamp));
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
    vm.expectRevert(FixedTermPolicy.ClosureDisabledBeforeTerm.selector);
    hooks.onCloseMarket(state, '');

    vm.warp(term);
    vm.prank(MarketC);
    hooks.onCloseMarket(state, '');
    assertEq(hooks.getHookedMarket(MarketC).fixedTermEndTime, term, 'elapsed term');
  }
}
