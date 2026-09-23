// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseHooks } from 'src/access/BaseHooks.sol';
import { Vm } from 'forge-std/Vm.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { HookedMarket } from 'src/access/PeriodicTermHooks.sol';
import { PendingAprChange } from 'src/access/PeriodicTermHooks.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { PeriodicAprMarketMock } from '../mocks/PeriodicAprMarketMock.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract PeriodicTermHooksTest is TestKernel {
  address internal constant MarketA = address(0x3001);
  address internal constant MarketB = address(0x3002);
  address internal constant MarketC = address(0x3003);
  address internal constant MarketD = address(0x3004);
  address internal constant Lender = address(0xA11CE);
  address internal constant SecondLender = address(0xB0B);
  address internal constant ThirdLender = address(0xCA401);
  address internal constant NewAdministrator = address(0xAD011);

  uint32 internal constant PeriodStart = 1_724_284_800;
  uint32 internal constant PeriodDuration = 30 days;
  uint32 internal constant WithdrawalWindowDuration = 3 days;
  uint32 internal constant FirstWithdrawalWindowStart =
    PeriodStart + PeriodDuration - WithdrawalWindowDuration;
  bytes4 internal constant PanicSelector = 0x4e487b71;
  uint256 internal constant PanicArithmetic = 0x11;
  bytes32 internal constant ProposalCancelledTopic =
    keccak256('AnnualInterestBipsReductionProposalCancelled(address)');

  PeriodicTermHooks internal hooks;
  MockRoleProvider internal provider1;
  MockRoleProvider internal provider2;
  mapping(address account => bool registered) internal registeredBorrowers;
  address internal callbackPreviousAdministrator;
  address internal callbackNewAdministrator;

  function setUp() external {
    vm.warp(PeriodStart);
    registeredBorrowers[address(this)] = true;
    provider1 = MockRoleProvider(_deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider'));
    provider2 = MockRoleProvider(_deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider'));
    hooks = _newHooks(address(this));
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

  function _newHooks(address administrator) internal returns (PeriodicTermHooks deployed) {
    deployed = PeriodicTermHooks(
      _deployCode(
        'src/access/PeriodicTermHooks.sol:PeriodicTermHooks',
        abi.encode(administrator, bytes(''))
      )
    );
  }

  function _newHooks(
    address administrator,
    NameAndProviderInputs memory inputs
  ) internal returns (PeriodicTermHooks deployed) {
    deployed = PeriodicTermHooks(
      _deployCode(
        'src/access/PeriodicTermHooks.sol:PeriodicTermHooks',
        abi.encode(administrator, abi.encode(inputs))
      )
    );
  }

  function _newAprMarket(uint16 annualInterestBips) internal returns (address market) {
    market = _deployCode(
      'test/mocks/PeriodicAprMarketMock.sol:PeriodicAprMarketMock',
      abi.encode(uint256(annualInterestBips))
    );
  }

  function _hooksData() internal pure returns (bytes memory) {
    return abi.encode(FirstWithdrawalWindowStart, PeriodDuration, WithdrawalWindowDuration);
  }

  function _hooksData(
    uint96 minimumDeposit,
    bool transfersDisabled
  ) internal pure returns (bytes memory) {
    return
      abi.encode(
        FirstWithdrawalWindowStart,
        PeriodDuration,
        WithdrawalWindowDuration,
        minimumDeposit,
        transfersDisabled
      );
  }

  function _requestedConfig(
    PeriodicTermHooks target,
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
    PeriodicTermHooks target,
    address market,
    HooksConfig requestedConfig,
    bytes memory hooksData
  ) internal returns (HooksConfig effectiveConfig) {
    DeployMarketInputs memory inputs;
    inputs.hooks = requestedConfig;
    effectiveConfig = target.onCreateMarket(address(this), market, inputs, hooksData);
  }

  function _createMarket(address market) internal returns (HooksConfig effectiveConfig) {
    return _createMarket(hooks, market, _requestedConfig(hooks, false, false, false), _hooksData());
  }

  function _assertPendingAprChange(
    address market,
    uint16 annualInterestBips,
    uint32 proposalTimestamp,
    uint32 responseWindowStart,
    uint32 responseWindowEnd
  ) internal view {
    (
      PendingAprChange memory pending,
      uint32 actualResponseWindowStart,
      uint32 actualResponseWindowEnd
    ) = hooks.getPendingAprChange(market);
    assertEq(pending.annualInterestBips, annualInterestBips, 'pending APR');
    assertEq(pending.proposalTimestamp, proposalTimestamp, 'proposal timestamp');
    assertEq(actualResponseWindowStart, responseWindowStart, 'response window start');
    assertEq(actualResponseWindowEnd, responseWindowEnd, 'response window end');
  }

  function _assertNoPendingAprChange(address market) internal view {
    _assertPendingAprChange(market, 0, 0, 0, 0);
    (uint16 annualInterestBips, uint32 proposalTimestamp) = hooks.pendingAprChanges(market);
    assertEq(annualInterestBips, 0, 'getter APR');
    assertEq(proposalTimestamp, 0, 'getter timestamp');
  }

  function _assertNoCancelledEventRecorded() internal {
    Vm.Log[] memory logs = vm.getRecordedLogs();
    for (uint256 i; i < logs.length; i++) {
      assertTrue(logs[i].topics[0] != ProposalCancelledTopic, 'unexpected cancellation event');
    }
  }

  function _addPullProvider(PeriodicTermHooks target) internal {
    provider1.setIsPullProvider(true);
    target.addRoleProvider(address(provider1), type(uint32).max);
  }

  function _expectedWindowOpen(uint256 timestamp) internal pure returns (bool) {
    if (timestamp < FirstWithdrawalWindowStart) return false;
    return (timestamp - FirstWithdrawalWindowStart) % PeriodDuration < WithdrawalWindowDuration;
  }

  function _expectedNextWindowStart(uint256 timestamp) internal pure returns (uint256) {
    if (timestamp < FirstWithdrawalWindowStart) return FirstWithdrawalWindowStart;
    uint256 periodsElapsed = (timestamp - FirstWithdrawalWindowStart) / PeriodDuration;
    return FirstWithdrawalWindowStart + ((periodsElapsed + 1) * PeriodDuration);
  }

  function test_metadata_IsCanonical() external view {
    assertEq(hooks.version(), 'PeriodicTermHooks', 'version');
    assertEq(hooks.templateVersion(), 2, 'template version');
    assertEq(hooks.MinimumPeriodDuration(), 6 minutes, 'minimum period');
    assertEq(hooks.MaximumPeriodDuration(), 365 days, 'maximum period');
    assertEq(hooks.MinimumWithdrawalWindowDuration(), 1 minutes, 'minimum window');
    assertEq(hooks.MaximumInitialWithdrawalWindowDelay(), 365 days, 'maximum delay');
    assertEq(hooks.AprReductionProposalValidityPeriods(), 1, 'proposal periods');
    (uint16 pendingApr, uint32 pendingTimestamp) = hooks.pendingAprChanges(MarketA);
    assertEq(pendingApr, 0, 'initial pending APR');
    assertEq(pendingTimestamp, 0, 'initial pending timestamp');
  }

  function test_onCreateMarket_RequiresPeriodicData() external {
    DeployMarketInputs memory inputs;
    vm.expectRevert(PeriodicTermHooks.PeriodicWindowNotProvided.selector);
    hooks.onCreateMarket(
      address(this),
      MarketA,
      inputs,
      abi.encode(FirstWithdrawalWindowStart, PeriodDuration)
    );
  }

  function test_onCreateMarket_ValidatesScheduleBounds() external {
    DeployMarketInputs memory inputs;
    uint32 minimumPeriod = hooks.MinimumPeriodDuration();
    uint32 maximumPeriod = hooks.MaximumPeriodDuration();
    uint32 minimumWindow = hooks.MinimumWithdrawalWindowDuration();
    uint32 maximumDelay = hooks.MaximumInitialWithdrawalWindowDelay();

    hooks.onCreateMarket(
      address(this),
      MarketA,
      inputs,
      abi.encode(PeriodStart + maximumDelay, minimumPeriod, minimumWindow)
    );
    hooks.onCreateMarket(
      address(this),
      MarketB,
      inputs,
      abi.encode(PeriodStart - maximumPeriod, maximumPeriod, maximumPeriod - 1)
    );

    vm.expectRevert(PeriodicTermHooks.InitialWithdrawalWindowTooFarInFuture.selector);
    hooks.onCreateMarket(
      address(this),
      MarketC,
      inputs,
      abi.encode(PeriodStart + maximumDelay + 1, PeriodDuration, WithdrawalWindowDuration)
    );
    vm.expectRevert(PeriodicTermHooks.PeriodDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      MarketC,
      inputs,
      abi.encode(FirstWithdrawalWindowStart, minimumPeriod - 1, minimumWindow)
    );
    vm.expectRevert(PeriodicTermHooks.PeriodDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      MarketC,
      inputs,
      abi.encode(FirstWithdrawalWindowStart, maximumPeriod + 1, minimumWindow)
    );
    vm.expectRevert(PeriodicTermHooks.WithdrawalWindowDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      MarketC,
      inputs,
      abi.encode(FirstWithdrawalWindowStart, PeriodDuration, minimumWindow - 1)
    );
    vm.expectRevert(PeriodicTermHooks.WithdrawalWindowDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      MarketC,
      inputs,
      abi.encode(FirstWithdrawalWindowStart, PeriodDuration, PeriodDuration)
    );
  }

  function test_onCreateMarket_PreservesScheduleDecodeAndMinimumFailureOrder() external {
    DeployMarketInputs memory inputs;
    vm.expectRevert(PeriodicTermHooks.PeriodicWindowNotProvided.selector);
    hooks.onCreateMarket(address(this), MarketA, inputs, new bytes(95));
    vm.expectRevert(PeriodicTermHooks.PeriodDurationOutOfBounds.selector);
    hooks.onCreateMarket(
      address(this),
      MarketA,
      inputs,
      abi.encode(
        FirstWithdrawalWindowStart,
        uint256(0),
        WithdrawalWindowDuration,
        uint256(type(uint96).max) + 1
      )
    );
    vm.expectRevert(abi.encodePacked(PanicSelector, PanicArithmetic));
    hooks.onCreateMarket(
      address(this),
      MarketA,
      inputs,
      abi.encode(
        FirstWithdrawalWindowStart,
        uint256(type(uint32).max) + 1,
        WithdrawalWindowDuration,
        uint256(type(uint96).max) + 1
      )
    );
  }

  function test_onCreateMarket_PreservesScheduleAndBatchReads() external {
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      _hooksData(100, false)
    );
    _createMarket(
      hooks,
      MarketB,
      _requestedConfig(hooks, false, false, false),
      _hooksData(200, true)
    );

    HookedMarket memory config = hooks.getHookedMarket(MarketA);
    assertEq(config.firstWithdrawalWindowStart, FirstWithdrawalWindowStart, 'first window');
    assertEq(config.periodDuration, PeriodDuration, 'period duration');
    assertEq(config.withdrawalWindowDuration, WithdrawalWindowDuration, 'window duration');
    assertFalse(config.isClosed, 'initial closed state');

    address[] memory markets = new address[](3);
    markets[0] = MarketA;
    markets[1] = MarketB;
    markets[2] = MarketC;
    HookedMarket[] memory configs = hooks.getHookedMarkets(markets);
    assertEq(configs.length, 3, 'market count');
    assertEq(configs[0].minimumDeposit, 100, 'first minimum');
    assertEq(configs[1].minimumDeposit, 200, 'second minimum');
    assertTrue(configs[1].transfersDisabled, 'second transfers');
    HookedMarket memory empty;
    assertEq(abi.encode(configs[2]), abi.encode(empty), 'unknown batch configuration');
    assertEq(
      abi.encode(hooks.getHookedMarket(MarketC)),
      abi.encode(empty),
      'unknown single configuration'
    );
  }

  function test_administratorTransfer_PreservesConfigurationAndMovesAuthority() external {
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      _hooksData(100, true)
    );
    bytes32 configBefore = keccak256(abi.encode(hooks.getHookedMarket(MarketA)));
    registeredBorrowers[NewAdministrator] = true;
    hooks.requestAdministratorTransfer(NewAdministrator);
    vm.prank(NewAdministrator);
    hooks.acceptAdministratorTransfer();

    assertEq(hooks.administrator(), NewAdministrator, 'administrator');
    assertEq(callbackPreviousAdministrator, address(this), 'previous administrator');
    assertEq(callbackNewAdministrator, NewAdministrator, 'new administrator');
    assertEq(keccak256(abi.encode(hooks.getHookedMarket(MarketA))), configBefore, 'market config');
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.setMinimumDeposit(MarketA, 200);
    vm.prank(NewAdministrator);
    hooks.setMinimumDeposit(MarketA, 200);
    assertEq(hooks.getHookedMarket(MarketA).minimumDeposit, 200, 'updated minimum');
  }

  function test_withdrawalWindow_TracksEveryBoundaryAndRecurringPeriod(
    uint256 periodIndex,
    uint256 offsetInPeriod
  ) external {
    periodIndex = bound(periodIndex, 0, 900);
    offsetInPeriod = bound(offsetInPeriod, 0, PeriodDuration - 1);
    _createMarket(MarketA);

    vm.warp(FirstWithdrawalWindowStart - 1);
    assertFalse(hooks.isWithdrawalWindowOpen(MarketA), 'before first window');
    vm.warp(FirstWithdrawalWindowStart);
    assertTrue(hooks.isWithdrawalWindowOpen(MarketA), 'window start');
    vm.warp(FirstWithdrawalWindowStart + WithdrawalWindowDuration - 1);
    assertTrue(hooks.isWithdrawalWindowOpen(MarketA), 'last open second');
    vm.warp(FirstWithdrawalWindowStart + WithdrawalWindowDuration);
    assertFalse(hooks.isWithdrawalWindowOpen(MarketA), 'window end');

    uint256 timestamp = FirstWithdrawalWindowStart + periodIndex * PeriodDuration + offsetInPeriod;
    vm.warp(timestamp);
    assertEq(
      hooks.isWithdrawalWindowOpen(MarketA),
      _expectedWindowOpen(timestamp),
      'window oracle'
    );

    vm.expectRevert(BaseHooks.NotHookedMarket.selector);
    hooks.isWithdrawalWindowOpen(MarketB);
  }

  function test_onCreateMarket_PreservesPastAndCurrentSchedules() external {
    vm.warp(FirstWithdrawalWindowStart + PeriodDuration * 3 - 1);
    _createMarket(MarketA);
    assertFalse(hooks.isWithdrawalWindowOpen(MarketA), 'before recurring window');
    vm.warp(FirstWithdrawalWindowStart + PeriodDuration * 3);
    assertTrue(hooks.isWithdrawalWindowOpen(MarketA), 'recurring window');

    vm.warp(FirstWithdrawalWindowStart + PeriodDuration * 4 + 1);
    _createMarket(MarketB);
    assertTrue(hooks.isWithdrawalWindowOpen(MarketB), 'deployed during recurring window');
  }

  function test_onQueueWithdrawal_EnforcesWindowClosedStateAndRequestedAccess(
    uint256 periodIndex,
    uint256 offsetInPeriod,
    bool stateIsClosed
  ) external {
    periodIndex = bound(periodIndex, 0, 900);
    offsetInPeriod = bound(offsetInPeriod, 0, PeriodDuration - 1);
    _createMarket(MarketA);
    MarketState memory state;
    state.isClosed = stateIsClosed;
    uint256 timestamp = FirstWithdrawalWindowStart + periodIndex * PeriodDuration + offsetInPeriod;
    vm.warp(timestamp);

    bool shouldAllow = stateIsClosed || _expectedWindowOpen(timestamp);
    vm.prank(MarketA);
    if (!shouldAllow) vm.expectRevert(PeriodicTermHooks.WithdrawOutsideWindow.selector);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
  }

  function test_onQueueWithdrawal_ChecksWindowBeforeAccessAndRetainsAccessAfterClosure() external {
    _createMarket(hooks, MarketA, _requestedConfig(hooks, true, true, true), _hooksData());
    _addPullProvider(hooks);
    vm.prank(address(provider1));
    hooks.grantRole(Lender, uint32(block.timestamp));
    MarketState memory state;
    vm.prank(MarketA);
    hooks.onDeposit(Lender, 1, state, '');
    hooks.blockFromDeposits(Lender);

    vm.prank(MarketA);
    vm.expectRevert(PeriodicTermHooks.WithdrawOutsideWindow.selector);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.prank(MarketA);
    vm.expectRevert(PeriodicTermHooks.WithdrawOutsideWindow.selector);
    hooks.onQueueWithdrawal(SecondLender, 0, 1, state, '');
    state.isClosed = true;
    vm.prank(MarketA);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.prank(MarketA);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onQueueWithdrawal(SecondLender, 0, 1, state, '');

    state.isClosed = false;
    vm.warp(FirstWithdrawalWindowStart);
    vm.prank(MarketA);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.warp(FirstWithdrawalWindowStart + WithdrawalWindowDuration);
    vm.prank(MarketA);
    vm.expectRevert(PeriodicTermHooks.WithdrawOutsideWindow.selector);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.prank(MarketA);
    hooks.onCloseMarket(state, '');
    vm.prank(MarketA);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.prank(MarketA);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    hooks.onQueueWithdrawal(SecondLender, 0, 1, state, '');
  }

  function test_onCloseMarket_OpensWithdrawalsAndHandlesProposalLifecycle() external {
    address market = _newAprMarket(1_000);
    _createMarket(market);
    hooks.proposeAnnualInterestBips(market, 900);
    assertFalse(hooks.isWithdrawalWindowOpen(market), 'window before close');

    MarketState memory state;
    vm.expectEmit(address(hooks));
    emit PeriodicTermHooks.AnnualInterestBipsReductionProposalCancelled(market);
    vm.expectEmit(address(hooks));
    emit PeriodicTermHooks.PeriodicTermClosed(market);
    vm.prank(market);
    hooks.onCloseMarket(state, '');
    assertTrue(hooks.getHookedMarket(market).isClosed, 'hook state closed');
    assertTrue(hooks.isWithdrawalWindowOpen(market), 'withdrawals open');
    _assertNoPendingAprChange(market);

    vm.prank(market);
    hooks.onQueueWithdrawal(Lender, 0, 1, state, '');
    vm.expectRevert(PeriodicTermHooks.AprReductionProposalOnClosedMarket.selector);
    hooks.proposeAnnualInterestBips(market, 800);

    _createMarket(MarketA);
    vm.recordLogs();
    vm.prank(MarketA);
    hooks.onCloseMarket(state, '');
    _assertNoCancelledEventRecorded();

    vm.expectRevert(BaseHooks.NotHookedMarket.selector);
    hooks.onCloseMarket(state, '');
  }

  function test_proposeAnnualInterestBips_AuthenticatesAndRejectsInvalidReductions() external {
    address market = _newAprMarket(1_000);
    _createMarket(market);

    vm.prank(address(0xBAD));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.proposeAnnualInterestBips(market, 900);

    address unknownMarket = _newAprMarket(1_000);
    vm.expectRevert(BaseHooks.NotHookedMarket.selector);
    hooks.proposeAnnualInterestBips(unknownMarket, 900);

    vm.expectRevert(PeriodicTermHooks.AprReductionProposalNotReduction.selector);
    hooks.proposeAnnualInterestBips(market, 1_000);
    vm.expectRevert(PeriodicTermHooks.AprReductionProposalNotReduction.selector);
    hooks.proposeAnnualInterestBips(market, 1_001);

    address highAprMarket = _newAprMarket(20_000);
    _createMarket(highAprMarket);
    vm.expectRevert(bytes4(keccak256('AnnualInterestBipsOutOfBounds()')));
    hooks.proposeAnnualInterestBips(highAprMarket, 10_001);

    vm.warp(FirstWithdrawalWindowStart);
    vm.expectRevert(PeriodicTermHooks.AprReductionProposalDuringWithdrawalWindow.selector);
    hooks.proposeAnnualInterestBips(market, 900);
    vm.warp(FirstWithdrawalWindowStart + WithdrawalWindowDuration - 1);
    vm.expectRevert(PeriodicTermHooks.AprReductionProposalDuringWithdrawalWindow.selector);
    hooks.proposeAnnualInterestBips(market, 900);

    vm.expectRevert(BaseHooks.NotHookedMarket.selector);
    hooks.getPendingAprChange(MarketA);
  }

  function test_proposeAnnualInterestBips_EnforcesStrictReduction(
    uint16 currentAnnualInterestBips,
    uint16 proposedAnnualInterestBips
  ) external {
    currentAnnualInterestBips = uint16(bound(currentAnnualInterestBips, 0, 10_000));
    proposedAnnualInterestBips = uint16(bound(proposedAnnualInterestBips, 0, 10_000));
    address market = _newAprMarket(currentAnnualInterestBips);
    _createMarket(market);

    if (proposedAnnualInterestBips < currentAnnualInterestBips) {
      hooks.proposeAnnualInterestBips(market, proposedAnnualInterestBips);
      _assertPendingAprChange(
        market,
        proposedAnnualInterestBips,
        PeriodStart,
        FirstWithdrawalWindowStart,
        FirstWithdrawalWindowStart + WithdrawalWindowDuration
      );
    } else {
      vm.expectRevert(PeriodicTermHooks.AprReductionProposalNotReduction.selector);
      hooks.proposeAnnualInterestBips(market, proposedAnnualInterestBips);
    }
  }

  function test_proposalTiming_UsesNextScheduledWindowAndOverwriteEvents(
    uint256 periodIndex,
    uint256 offsetAfterWindow
  ) external {
    periodIndex = bound(periodIndex, 0, 900);
    offsetAfterWindow = bound(offsetAfterWindow, WithdrawalWindowDuration, PeriodDuration - 1);
    address market = _newAprMarket(1_000);
    _createMarket(market);

    vm.recordLogs();
    hooks.proposeAnnualInterestBips(market, 900);
    _assertNoCancelledEventRecorded();
    _assertPendingAprChange(
      market,
      900,
      PeriodStart,
      FirstWithdrawalWindowStart,
      FirstWithdrawalWindowStart + WithdrawalWindowDuration
    );
    (uint16 getterApr, uint32 getterTimestamp) = hooks.pendingAprChanges(market);
    assertEq(getterApr, 900, 'mapping getter APR');
    assertEq(getterTimestamp, PeriodStart, 'mapping getter timestamp');

    uint256 proposalTimestamp = FirstWithdrawalWindowStart +
      periodIndex *
      PeriodDuration +
      offsetAfterWindow;
    uint256 responseWindowStart = _expectedNextWindowStart(proposalTimestamp);
    uint256 responseWindowEnd = responseWindowStart + WithdrawalWindowDuration;
    vm.warp(proposalTimestamp);
    vm.expectEmit(address(hooks));
    emit PeriodicTermHooks.AnnualInterestBipsReductionProposalCancelled(market);
    vm.expectEmit(address(hooks));
    emit PeriodicTermHooks.AnnualInterestBipsReductionProposed(
      market,
      800,
      uint32(proposalTimestamp),
      uint32(responseWindowStart),
      uint32(responseWindowEnd)
    );
    hooks.proposeAnnualInterestBips(market, 800);
    _assertPendingAprChange(
      market,
      800,
      uint32(proposalTimestamp),
      uint32(responseWindowStart),
      uint32(responseWindowEnd)
    );
  }

  function test_aprReduction_EnforcesExecutionStateMachine() external {
    _assertReductionWithoutProposalReverts();
    _assertMismatchedReductionReverts();
    _assertEarlyReductionReverts();
    _assertUnpaidWithdrawalReductionReverts();
    _assertExpiredReductionReverts();
    _assertReductionAtLastValidSecondExecutes();
  }

  function _assertReductionWithoutProposalReverts() internal {
    vm.warp(PeriodStart);
    _createMarket(MarketA);
    MarketState memory state;
    state.annualInterestBips = 1_000;
    vm.prank(MarketA);
    vm.expectRevert(PeriodicTermHooks.NoPendingAprChange.selector);
    hooks.onSetAnnualInterestAndReserveRatioBips(900, 0, state, '');
  }

  function _assertMismatchedReductionReverts() internal {
    vm.warp(PeriodStart);
    address market = _newAprMarket(1_000);
    _createMarket(market);
    hooks.proposeAnnualInterestBips(market, 900);
    MarketState memory state;
    state.annualInterestBips = 1_000;
    vm.warp(FirstWithdrawalWindowStart + WithdrawalWindowDuration);
    vm.prank(market);
    vm.expectRevert(PeriodicTermHooks.AprChangeDoesNotMatchProposal.selector);
    hooks.onSetAnnualInterestAndReserveRatioBips(899, 0, state, '');
    _assertPendingAprChange(
      market,
      900,
      PeriodStart,
      FirstWithdrawalWindowStart,
      FirstWithdrawalWindowStart + WithdrawalWindowDuration
    );
  }

  function _assertEarlyReductionReverts() internal {
    vm.warp(PeriodStart);
    address market = _newAprMarket(1_000);
    _createMarket(market);
    hooks.proposeAnnualInterestBips(market, 900);
    MarketState memory state;
    state.annualInterestBips = 1_000;
    vm.warp(FirstWithdrawalWindowStart + WithdrawalWindowDuration - 1);
    vm.prank(market);
    vm.expectRevert(PeriodicTermHooks.AprChangeNotReady.selector);
    hooks.onSetAnnualInterestAndReserveRatioBips(900, 0, state, '');
    _assertPendingAprChange(
      market,
      900,
      PeriodStart,
      FirstWithdrawalWindowStart,
      FirstWithdrawalWindowStart + WithdrawalWindowDuration
    );
  }

  function _assertUnpaidWithdrawalReductionReverts() internal {
    vm.warp(PeriodStart);
    address market = _newAprMarket(1_000);
    _createMarket(market);
    hooks.proposeAnnualInterestBips(market, 900);
    MarketState memory state;
    state.annualInterestBips = 1_000;
    state.scaledPendingWithdrawals = 1;
    vm.warp(FirstWithdrawalWindowStart + WithdrawalWindowDuration);
    vm.prank(market);
    vm.expectRevert(PeriodicTermHooks.UnpaidWithdrawalsExist.selector);
    hooks.onSetAnnualInterestAndReserveRatioBips(900, 0, state, '');
    _assertPendingAprChange(
      market,
      900,
      PeriodStart,
      FirstWithdrawalWindowStart,
      FirstWithdrawalWindowStart + WithdrawalWindowDuration
    );
  }

  function _assertExpiredReductionReverts() internal {
    vm.warp(PeriodStart);
    address market = _newAprMarket(1_000);
    _createMarket(market);
    hooks.proposeAnnualInterestBips(market, 900);
    MarketState memory state;
    state.annualInterestBips = 1_000;
    uint256 expiry = FirstWithdrawalWindowStart +
      uint256(PeriodDuration) *
      hooks.AprReductionProposalValidityPeriods();
    vm.warp(expiry);
    vm.prank(market);
    vm.expectRevert(PeriodicTermHooks.AprReductionProposalExpired.selector);
    hooks.onSetAnnualInterestAndReserveRatioBips(900, 0, state, '');
    _assertPendingAprChange(
      market,
      900,
      PeriodStart,
      FirstWithdrawalWindowStart,
      FirstWithdrawalWindowStart + WithdrawalWindowDuration
    );
  }

  function _assertReductionAtLastValidSecondExecutes() internal {
    vm.warp(PeriodStart);
    address market = _newAprMarket(1_000);
    _createMarket(market);
    hooks.proposeAnnualInterestBips(market, 900);
    MarketState memory state;
    state.annualInterestBips = 1_000;
    state.reserveRatioBips = 1_000;
    uint256 expiry = FirstWithdrawalWindowStart +
      uint256(PeriodDuration) *
      hooks.AprReductionProposalValidityPeriods();
    vm.warp(expiry - 1);
    vm.expectEmit(address(hooks));
    emit PeriodicTermHooks.AnnualInterestBipsReductionExecuted(market, 900);
    vm.prank(market);
    (uint16 annualInterestBips, uint16 reserveRatioBips) = hooks
      .onSetAnnualInterestAndReserveRatioBips(900, 0, state, '');
    assertEq(annualInterestBips, 900, 'executed APR');
    assertEq(reserveRatioBips, 1_000, 'preserved reserve ratio');
    _assertNoPendingAprChange(market);
    (uint16 originalApr, uint16 originalReserve, uint32 temporaryExpiry) = hooks
      .temporaryExcessReserveRatio(market);
    assertEq(originalApr, 0, 'temporary original APR');
    assertEq(originalReserve, 0, 'temporary original reserve');
    assertEq(temporaryExpiry, 0, 'temporary expiry');
  }

  function test_executePendingAnnualInterestBipsReduction_UsesTheSameGates() external {
    vm.warp(PeriodStart);
    address market = _newAprMarket(1_000);
    _createMarket(market);
    hooks.proposeAnnualInterestBips(market, 900);
    MarketState memory state;
    state.annualInterestBips = 1_000;

    vm.warp(FirstWithdrawalWindowStart + WithdrawalWindowDuration - 1);
    vm.prank(market);
    vm.expectRevert(PeriodicTermHooks.AprChangeNotReady.selector);
    hooks.executePendingAnnualInterestBipsReduction(state);

    state.annualInterestBips = 900;
    vm.warp(FirstWithdrawalWindowStart + WithdrawalWindowDuration);
    vm.prank(market);
    vm.expectRevert(PeriodicTermHooks.AprReductionProposalNotReduction.selector);
    hooks.executePendingAnnualInterestBipsReduction(state);

    state.annualInterestBips = 1_000;
    vm.expectEmit(address(hooks));
    emit PeriodicTermHooks.AnnualInterestBipsReductionExecuted(market, 900);
    vm.prank(market);
    uint16 annualInterestBips = hooks.executePendingAnnualInterestBipsReduction(state);
    assertEq(annualInterestBips, 900, 'executed APR');
    _assertNoPendingAprChange(market);

    vm.prank(market);
    vm.expectRevert(PeriodicTermHooks.NoPendingAprChange.selector);
    hooks.executePendingAnnualInterestBipsReduction(state);
    vm.expectRevert(BaseHooks.NotHookedMarket.selector);
    hooks.executePendingAnnualInterestBipsReduction(state);
  }

  function test_onSetAnnualInterestBips_IncreasesAndEqualityDelegateAndCancelPrecisely() external {
    address market = _newAprMarket(1_000);
    _createMarket(market);
    hooks.proposeAnnualInterestBips(market, 900);
    MarketState memory state;
    state.annualInterestBips = 1_000;
    state.reserveRatioBips = 1_000;

    vm.expectEmit(address(hooks));
    emit PeriodicTermHooks.AnnualInterestBipsReductionProposalCancelled(market);
    vm.prank(market);
    (uint16 annualInterestBips, uint16 reserveRatioBips) = hooks
      .onSetAnnualInterestAndReserveRatioBips(1_001, 500, state, '');
    assertEq(annualInterestBips, 1_001, 'increased APR');
    assertEq(reserveRatioBips, 1_000, 'increased reserve ratio');
    _assertNoPendingAprChange(market);

    vm.recordLogs();
    vm.prank(market);
    (annualInterestBips, reserveRatioBips) = hooks.onSetAnnualInterestAndReserveRatioBips(
      1_001,
      500,
      state,
      ''
    );
    _assertNoCancelledEventRecorded();
    assertEq(annualInterestBips, 1_001, 'second increased APR');
    assertEq(reserveRatioBips, 1_000, 'second reserve ratio');

    hooks.proposeAnnualInterestBips(market, 900);
    vm.prank(market);
    (annualInterestBips, reserveRatioBips) = hooks.onSetAnnualInterestAndReserveRatioBips(
      1_000,
      500,
      state,
      ''
    );
    assertEq(annualInterestBips, 1_000, 'unchanged APR');
    assertEq(reserveRatioBips, 1_000, 'unchanged reserve ratio');
    _assertPendingAprChange(
      market,
      900,
      PeriodStart,
      FirstWithdrawalWindowStart,
      FirstWithdrawalWindowStart + WithdrawalWindowDuration
    );

    vm.expectRevert(BaseHooks.NotHookedMarket.selector);
    hooks.onSetAnnualInterestAndReserveRatioBips(999, 0, state, '');
  }
}
