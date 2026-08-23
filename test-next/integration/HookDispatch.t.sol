// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IHooks } from 'src/access/IHooks.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { WildcatMarketConfig } from 'src/market/WildcatMarketConfig.sol';
import { WildcatMarketToken } from 'src/market/WildcatMarketToken.sol';
import { WildcatMarketWithdrawals } from 'src/market/WildcatMarketWithdrawals.sol';
import { MarketParameters } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { Bit_Enabled_Borrow } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_CloseMarket } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_ExecuteWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_NukeFromOrbit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Repay } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetAnnualInterestAndReserveRatioBips } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetMaxTotalSupply } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetProtocolFeeBips } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { HookDispatchArchControllerMock } from '../mocks/HookDispatchMocks.sol';
import { HookDispatchBorrowerRegistryMock } from '../mocks/HookDispatchMocks.sol';
import { HookDispatchFactoryMock } from '../mocks/HookDispatchMocks.sol';
import { HookDispatchMock } from '../mocks/HookDispatchMocks.sol';
import { HookDispatchSentinelMock } from '../mocks/HookDispatchMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract HookDispatchTest is TestKernel {
  struct Fixture {
    WildcatMarket market;
    MockERC20 asset;
    HookDispatchMock hooks;
    HookDispatchSentinelMock sentinel;
    HookDispatchFactoryMock factory;
  }

  address internal constant Borrower = address(0xB0);
  address internal constant Lender = address(0xA11CE);
  address internal constant SecondLender = address(0xB0B);
  address internal constant ThirdLender = address(0xCA401);
  address internal constant Recipient = address(0xD00D);
  address internal constant Delegate = address(0xDE1E6A7E);
  address internal constant Launcher = address(0x1A0C4);
  uint32 internal constant WithdrawalBatchDuration = 1 days;

  function _flag(uint256 bit) internal pure returns (HooksConfig) {
    return EmptyHooksConfig.setFlag(bit);
  }

  function _newFixture(HooksConfig enabledFlags) internal returns (Fixture memory fixture) {
    HookDispatchArchControllerMock archController = HookDispatchArchControllerMock(
      _deployCode('test-next/mocks/HookDispatchMocks.sol:HookDispatchArchControllerMock')
    );
    HookDispatchBorrowerRegistryMock registry = HookDispatchBorrowerRegistryMock(
      _deployCode(
        'test-next/mocks/HookDispatchMocks.sol:HookDispatchBorrowerRegistryMock',
        abi.encode(address(archController))
      )
    );
    fixture.asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode('Underlying', 'UND', uint8(18))
      )
    );
    fixture.hooks = HookDispatchMock(
      _deployCode('test-next/mocks/HookDispatchMocks.sol:HookDispatchMock')
    );
    fixture.sentinel = HookDispatchSentinelMock(
      _deployCode('test-next/mocks/HookDispatchMocks.sol:HookDispatchSentinelMock')
    );
    fixture.factory = HookDispatchFactoryMock(
      _deployCode('test-next/mocks/HookDispatchMocks.sol:HookDispatchFactoryMock')
    );

    MarketParameters memory parameters = MarketParameters({
      asset: address(fixture.asset),
      decimals: 18,
      packedNameWord0: bytes32(0),
      packedNameWord1: bytes32(0),
      packedSymbolWord0: bytes32(0),
      packedSymbolWord1: bytes32(0),
      borrower: Borrower,
      feeRecipient: address(0xFEE),
      sentinel: address(fixture.sentinel),
      wrapperFactory: address(0x4626),
      maxTotalSupply: 1_000_000e18,
      protocolFeeBips: 0,
      annualInterestBips: 0,
      delinquencyFeeBips: 0,
      withdrawalBatchDuration: WithdrawalBatchDuration,
      reserveRatioBips: 0,
      delinquencyGracePeriod: 0,
      archController: address(archController),
      sphereXEngine: address(0),
      hooks: enabledFlags.setHooksAddress(address(fixture.hooks)),
      borrowerPrincipal: Borrower,
      borrowerIdentityRegistry: address(registry)
    });
    fixture.factory.setMarketParameters(parameters);
    fixture.market = WildcatMarket(
      fixture.factory.deployMarket(vm.getCode('src/market/WildcatMarket.sol:WildcatMarket'))
    );
  }

  function _callMarket(
    WildcatMarket market,
    address caller,
    bytes memory data
  ) internal returns (bytes memory result) {
    vm.prank(caller);
    bool success;
    (success, result) = address(market).call(data);
    if (!success) {
      assembly {
        revert(add(result, 0x20), mload(result))
      }
    }
  }

  function _assertCall(HookDispatchMock hooks, uint256 index, bytes memory expected) internal view {
    assertEq(hooks.callAt(index), expected);
  }

  function _fundAndApprove(Fixture memory fixture, address account, uint256 amount) internal {
    fixture.asset.mint(account, amount);
    vm.prank(account);
    fixture.asset.approve(address(fixture.market), amount);
  }

  function _deposit(Fixture memory fixture, address account, uint256 amount) internal {
    _fundAndApprove(fixture, account, amount);
    _callMarket(
      fixture.market,
      account,
      abi.encodeWithSelector(WildcatMarket.deposit.selector, amount)
    );
  }

  function _append(bytes memory data, bytes memory extraData) internal pure returns (bytes memory) {
    return abi.encodePacked(data, extraData);
  }

  function test_depositEntrypoints_DispatchExactCalldata(bytes memory extraData) external {
    Fixture memory fixture = _newFixture(_flag(Bit_Enabled_Deposit));
    _fundAndApprove(fixture, Lender, 200);

    MarketState memory expectedState = fixture.market.currentState();
    bytes memory result = _callMarket(
      fixture.market,
      Lender,
      _append(abi.encodeWithSelector(WildcatMarket.deposit.selector, 100), extraData)
    );
    assertEq(result, '');
    _assertCall(
      fixture.hooks,
      0,
      abi.encodeWithSelector(IHooks.onDeposit.selector, Lender, 100, expectedState, extraData)
    );

    expectedState = fixture.market.currentState();
    result = _callMarket(
      fixture.market,
      Lender,
      _append(abi.encodeWithSelector(WildcatMarket.depositUpTo.selector, 100), extraData)
    );
    assertEq(result, abi.encode(100));
    _assertCall(
      fixture.hooks,
      1,
      abi.encodeWithSelector(IHooks.onDeposit.selector, Lender, 100, expectedState, extraData)
    );

    Fixture memory disabled = _newFixture(EmptyHooksConfig);
    _fundAndApprove(disabled, Lender, 200);
    _callMarket(
      disabled.market,
      Lender,
      _append(abi.encodeWithSelector(WildcatMarket.deposit.selector, 100), extraData)
    );
    _callMarket(
      disabled.market,
      Lender,
      _append(abi.encodeWithSelector(WildcatMarket.depositUpTo.selector, 100), extraData)
    );
    assertEq(disabled.hooks.callCount(), 0);
  }

  function test_queueWithdrawalEntrypoints_DispatchExactCalldata(bytes memory extraData) external {
    Fixture memory fixture = _newFixture(_flag(Bit_Enabled_QueueWithdrawal));
    _deposit(fixture, Lender, 100);
    _deposit(fixture, SecondLender, 100);
    _deposit(fixture, ThirdLender, 100);

    MarketState memory expectedState = fixture.market.currentState();
    uint32 expiry = uint32(block.timestamp + WithdrawalBatchDuration);
    expectedState.pendingWithdrawalExpiry = expiry;
    bytes memory result = _callMarket(
      fixture.market,
      Lender,
      _append(
        abi.encodeWithSelector(WildcatMarketWithdrawals.queueWithdrawal.selector, 20),
        extraData
      )
    );
    assertEq(result, abi.encode(expiry));
    _assertCall(
      fixture.hooks,
      0,
      abi.encodeWithSelector(
        IHooks.onQueueWithdrawal.selector,
        Lender,
        expiry,
        20,
        expectedState,
        extraData
      )
    );

    expectedState = fixture.market.currentState();
    result = _callMarket(
      fixture.market,
      SecondLender,
      _append(
        abi.encodeWithSelector(WildcatMarketWithdrawals.queueFullWithdrawal.selector),
        extraData
      )
    );
    assertEq(result, abi.encode(expiry));
    _assertCall(
      fixture.hooks,
      1,
      abi.encodeWithSelector(
        IHooks.onQueueWithdrawal.selector,
        SecondLender,
        expiry,
        100,
        expectedState,
        extraData
      )
    );

    expectedState = fixture.market.currentState();
    result = _callMarket(
      fixture.market,
      ThirdLender,
      _append(
        abi.encodeWithSelector(WildcatMarketWithdrawals.queueWithdrawalScaled.selector, 30),
        extraData
      )
    );
    assertEq(result, abi.encode(expiry));
    _assertCall(
      fixture.hooks,
      2,
      abi.encodeWithSelector(
        IHooks.onQueueWithdrawal.selector,
        ThirdLender,
        expiry,
        30,
        expectedState,
        extraData
      )
    );

    Fixture memory disabled = _newFixture(EmptyHooksConfig);
    _deposit(disabled, Lender, 100);
    _callMarket(
      disabled.market,
      Lender,
      _append(
        abi.encodeWithSelector(WildcatMarketWithdrawals.queueWithdrawal.selector, 20),
        extraData
      )
    );
    _callMarket(
      disabled.market,
      Lender,
      _append(
        abi.encodeWithSelector(WildcatMarketWithdrawals.queueWithdrawalScaled.selector, 20),
        extraData
      )
    );
    _callMarket(
      disabled.market,
      Lender,
      _append(
        abi.encodeWithSelector(WildcatMarketWithdrawals.queueFullWithdrawal.selector),
        extraData
      )
    );
    assertEq(disabled.hooks.callCount(), 0);
  }

  function test_nukeFromOrbit_DispatchesEnabledCallbacksAndIsolatesQueueExtraData(
    bytes memory extraData
  ) external {
    for (uint256 mask; mask < 4; mask++) {
      HooksConfig flags = EmptyHooksConfig;
      if (mask & 1 != 0) flags = flags.setFlag(Bit_Enabled_NukeFromOrbit);
      if (mask & 2 != 0) flags = flags.setFlag(Bit_Enabled_QueueWithdrawal);
      Fixture memory fixture = _newFixture(flags);
      _deposit(fixture, Lender, 100);
      fixture.sentinel.setSanctioned(Lender, true);

      MarketState memory initialState = fixture.market.currentState();
      bytes memory expectedNukeCall = abi.encodeWithSelector(
        IHooks.onNukeFromOrbit.selector,
        Lender,
        initialState,
        extraData
      );
      MarketState memory queueState = fixture.market.currentState();
      uint32 expiry = uint32(block.timestamp + WithdrawalBatchDuration);
      queueState.pendingWithdrawalExpiry = expiry;
      _callMarket(
        fixture.market,
        Launcher,
        _append(
          abi.encodeWithSelector(WildcatMarketConfig.nukeFromOrbit.selector, Lender),
          extraData
        )
      );

      uint256 nextCall;
      if (mask & 1 != 0) {
        _assertCall(fixture.hooks, nextCall++, expectedNukeCall);
      }
      if (mask & 2 != 0) {
        _assertCall(
          fixture.hooks,
          nextCall++,
          abi.encodeWithSelector(
            IHooks.onQueueWithdrawal.selector,
            Lender,
            expiry,
            100,
            queueState,
            bytes('')
          )
        );
      }
      assertEq(fixture.hooks.callCount(), nextCall);
    }
  }

  function test_executeWithdrawal_DispatchesExactCalldata(bytes memory extraData) external {
    Fixture memory fixture = _newFixture(_flag(Bit_Enabled_ExecuteWithdrawal));
    _deposit(fixture, Lender, 100);
    bytes memory result = _callMarket(
      fixture.market,
      Lender,
      abi.encodeWithSelector(WildcatMarketWithdrawals.queueFullWithdrawal.selector)
    );
    uint32 expiry = abi.decode(result, (uint32));
    fastForward(WithdrawalBatchDuration + 1);

    MarketState memory expectedState = fixture.market.currentState();
    result = _callMarket(
      fixture.market,
      Launcher,
      _append(
        abi.encodeWithSelector(WildcatMarketWithdrawals.executeWithdrawal.selector, Lender, expiry),
        extraData
      )
    );
    assertEq(result, abi.encode(100));
    _assertCall(
      fixture.hooks,
      0,
      abi.encodeWithSelector(
        IHooks.onExecuteWithdrawal.selector,
        Lender,
        expiry,
        uint128(100),
        expectedState,
        extraData
      )
    );

    Fixture memory disabled = _newFixture(EmptyHooksConfig);
    _deposit(disabled, Lender, 100);
    result = _callMarket(
      disabled.market,
      Lender,
      abi.encodeWithSelector(WildcatMarketWithdrawals.queueFullWithdrawal.selector)
    );
    expiry = abi.decode(result, (uint32));
    fastForward(WithdrawalBatchDuration + 1);
    _callMarket(
      disabled.market,
      Launcher,
      _append(
        abi.encodeWithSelector(WildcatMarketWithdrawals.executeWithdrawal.selector, Lender, expiry),
        extraData
      )
    );
    assertEq(disabled.hooks.callCount(), 0);
  }

  function test_executeWithdrawals_DispatchesEachEntryWithoutBatchExtraData(
    bytes memory extraData
  ) external {
    Fixture memory fixture = _newFixture(_flag(Bit_Enabled_ExecuteWithdrawal));
    _deposit(fixture, Lender, 100);
    _deposit(fixture, SecondLender, 100);

    bytes memory result = _callMarket(
      fixture.market,
      Lender,
      abi.encodeWithSelector(WildcatMarketWithdrawals.queueWithdrawal.selector, 50)
    );
    uint32 firstExpiry = abi.decode(result, (uint32));
    _callMarket(
      fixture.market,
      SecondLender,
      abi.encodeWithSelector(WildcatMarketWithdrawals.queueWithdrawal.selector, 50)
    );
    fastForward(WithdrawalBatchDuration + 1);

    result = _callMarket(
      fixture.market,
      Lender,
      abi.encodeWithSelector(WildcatMarketWithdrawals.queueWithdrawal.selector, 50)
    );
    uint32 secondExpiry = abi.decode(result, (uint32));
    _callMarket(
      fixture.market,
      SecondLender,
      abi.encodeWithSelector(WildcatMarketWithdrawals.queueWithdrawal.selector, 50)
    );
    fastForward(WithdrawalBatchDuration + 1);

    address[] memory accounts = new address[](4);
    accounts[0] = Lender;
    accounts[1] = SecondLender;
    accounts[2] = Lender;
    accounts[3] = SecondLender;
    uint32[] memory expiries = new uint32[](4);
    expiries[0] = firstExpiry;
    expiries[1] = firstExpiry;
    expiries[2] = secondExpiry;
    expiries[3] = secondExpiry;

    MarketState memory expectedState = fixture.market.currentState();
    result = _callMarket(
      fixture.market,
      Launcher,
      _append(
        abi.encodeWithSelector(
          WildcatMarketWithdrawals.executeWithdrawals.selector,
          accounts,
          expiries
        ),
        extraData
      )
    );
    uint256[] memory expectedAmounts = new uint256[](4);
    for (uint256 i; i < 4; i++) {
      expectedAmounts[i] = 50;
      _assertCall(
        fixture.hooks,
        i,
        abi.encodeWithSelector(
          IHooks.onExecuteWithdrawal.selector,
          accounts[i],
          expiries[i],
          uint128(50),
          expectedState,
          bytes('')
        )
      );
      expectedState.normalizedUnclaimedWithdrawals -= 50;
    }
    assertEq(result, abi.encode(expectedAmounts));
  }

  function test_transferEntrypoints_DispatchExactCallerAndCalldata(
    bytes memory extraData
  ) external {
    Fixture memory fixture = _newFixture(_flag(Bit_Enabled_Transfer));
    _deposit(fixture, Lender, 200);

    MarketState memory expectedState = fixture.market.currentState();
    bytes memory result = _callMarket(
      fixture.market,
      Lender,
      _append(
        abi.encodeWithSelector(WildcatMarketToken.transfer.selector, Recipient, 50),
        extraData
      )
    );
    assertEq(result, abi.encode(true));
    _assertCall(
      fixture.hooks,
      0,
      abi.encodeWithSelector(
        IHooks.onTransfer.selector,
        Lender,
        Lender,
        Recipient,
        50,
        expectedState,
        extraData
      )
    );

    vm.prank(Lender);
    fixture.market.approve(Delegate, 50);
    expectedState = fixture.market.currentState();
    result = _callMarket(
      fixture.market,
      Delegate,
      _append(
        abi.encodeWithSelector(WildcatMarketToken.transferFrom.selector, Lender, Recipient, 50),
        extraData
      )
    );
    assertEq(result, abi.encode(true));
    _assertCall(
      fixture.hooks,
      1,
      abi.encodeWithSelector(
        IHooks.onTransfer.selector,
        Delegate,
        Lender,
        Recipient,
        50,
        expectedState,
        extraData
      )
    );

    Fixture memory disabled = _newFixture(EmptyHooksConfig);
    _deposit(disabled, Lender, 100);
    _callMarket(
      disabled.market,
      Lender,
      _append(
        abi.encodeWithSelector(WildcatMarketToken.transfer.selector, Recipient, 25),
        extraData
      )
    );
    vm.prank(Lender);
    disabled.market.approve(Delegate, 25);
    _callMarket(
      disabled.market,
      Delegate,
      _append(
        abi.encodeWithSelector(WildcatMarketToken.transferFrom.selector, Lender, Recipient, 25),
        extraData
      )
    );
    assertEq(disabled.hooks.callCount(), 0);
  }

  function test_borrow_DispatchesExactCalldata(bytes memory extraData) external {
    Fixture memory fixture = _newFixture(_flag(Bit_Enabled_Borrow));
    _deposit(fixture, Lender, 100);
    MarketState memory expectedState = fixture.market.currentState();
    _callMarket(
      fixture.market,
      Borrower,
      _append(abi.encodeWithSelector(WildcatMarket.borrow.selector, 40), extraData)
    );
    _assertCall(
      fixture.hooks,
      0,
      abi.encodeWithSelector(IHooks.onBorrow.selector, 40, expectedState, extraData)
    );

    Fixture memory disabled = _newFixture(EmptyHooksConfig);
    _deposit(disabled, Lender, 100);
    _callMarket(
      disabled.market,
      Borrower,
      _append(abi.encodeWithSelector(WildcatMarket.borrow.selector, 40), extraData)
    );
    assertEq(disabled.hooks.callCount(), 0);
  }

  function test_repayEntrypoints_DispatchExactCalldata(bytes memory extraData) external {
    Fixture memory fixture = _newFixture(_flag(Bit_Enabled_Repay));
    _deposit(fixture, Lender, 100);
    _callMarket(
      fixture.market,
      Borrower,
      abi.encodeWithSelector(WildcatMarket.borrow.selector, 80)
    );
    _fundAndApprove(fixture, Borrower, 40);

    MarketState memory expectedState = fixture.market.currentState();
    _callMarket(
      fixture.market,
      Borrower,
      _append(abi.encodeWithSelector(WildcatMarket.repay.selector, 20), extraData)
    );
    _assertCall(
      fixture.hooks,
      0,
      abi.encodeWithSelector(IHooks.onRepay.selector, 20, expectedState, extraData)
    );

    expectedState = fixture.market.currentState();
    _callMarket(
      fixture.market,
      Borrower,
      _append(
        abi.encodeWithSelector(
          WildcatMarketWithdrawals.repayAndProcessUnpaidWithdrawalBatches.selector,
          20,
          1
        ),
        extraData
      )
    );
    _assertCall(
      fixture.hooks,
      1,
      abi.encodeWithSelector(IHooks.onRepay.selector, 20, expectedState, extraData)
    );

    Fixture memory disabled = _newFixture(EmptyHooksConfig);
    _fundAndApprove(disabled, Borrower, 40);
    _callMarket(
      disabled.market,
      Borrower,
      _append(abi.encodeWithSelector(WildcatMarket.repay.selector, 20), extraData)
    );
    _callMarket(
      disabled.market,
      Borrower,
      _append(
        abi.encodeWithSelector(
          WildcatMarketWithdrawals.repayAndProcessUnpaidWithdrawalBatches.selector,
          20,
          1
        ),
        extraData
      )
    );
    assertEq(disabled.hooks.callCount(), 0);
  }

  function test_closeMarket_DispatchesExactCalldata(bytes memory extraData) external {
    Fixture memory fixture = _newFixture(_flag(Bit_Enabled_CloseMarket));
    MarketState memory expectedState = fixture.market.currentState();
    _callMarket(
      fixture.market,
      Borrower,
      _append(abi.encodeWithSelector(WildcatMarket.closeMarket.selector), extraData)
    );
    _assertCall(
      fixture.hooks,
      0,
      abi.encodeWithSelector(IHooks.onCloseMarket.selector, expectedState, extraData)
    );

    Fixture memory disabled = _newFixture(EmptyHooksConfig);
    _callMarket(
      disabled.market,
      Borrower,
      _append(abi.encodeWithSelector(WildcatMarket.closeMarket.selector), extraData)
    );
    assertEq(disabled.hooks.callCount(), 0);
  }

  function test_setMaxTotalSupply_DispatchesExactCalldata(bytes memory extraData) external {
    Fixture memory fixture = _newFixture(_flag(Bit_Enabled_SetMaxTotalSupply));
    MarketState memory expectedState = fixture.market.currentState();
    _callMarket(
      fixture.market,
      Borrower,
      _append(
        abi.encodeWithSelector(WildcatMarketConfig.setMaxTotalSupply.selector, 5_000),
        extraData
      )
    );
    _assertCall(
      fixture.hooks,
      0,
      abi.encodeWithSelector(IHooks.onSetMaxTotalSupply.selector, 5_000, expectedState, extraData)
    );

    Fixture memory disabled = _newFixture(EmptyHooksConfig);
    _callMarket(
      disabled.market,
      Borrower,
      _append(
        abi.encodeWithSelector(WildcatMarketConfig.setMaxTotalSupply.selector, 5_000),
        extraData
      )
    );
    assertEq(disabled.hooks.callCount(), 0);
  }

  function test_setProtocolFeeBips_DispatchesExactCalldata(bytes memory extraData) external {
    Fixture memory fixture = _newFixture(_flag(Bit_Enabled_SetProtocolFeeBips));
    MarketState memory expectedState = fixture.market.currentState();
    fixture.factory.callMarket(
      address(fixture.market),
      _append(
        abi.encodeWithSelector(WildcatMarketConfig.setProtocolFeeBips.selector, 500),
        extraData
      )
    );
    _assertCall(
      fixture.hooks,
      0,
      abi.encodeWithSelector(
        IHooks.onSetProtocolFeeBips.selector,
        uint16(500),
        expectedState,
        extraData
      )
    );
    assertEq(uint256(fixture.market.previousState().protocolFeeBips), 500);

    Fixture memory disabled = _newFixture(EmptyHooksConfig);
    disabled.factory.callMarket(
      address(disabled.market),
      _append(
        abi.encodeWithSelector(WildcatMarketConfig.setProtocolFeeBips.selector, 500),
        extraData
      )
    );
    assertEq(disabled.hooks.callCount(), 0);
  }

  function test_setAnnualInterestAndReserveRatioBips_UsesHookReturnValues(
    bytes memory extraData
  ) external {
    Fixture memory fixture = _newFixture(_flag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips));
    fixture.hooks.setAnnualInterestAndReserveRatioBips(800, 300);
    MarketState memory expectedState = fixture.market.currentState();
    _callMarket(
      fixture.market,
      Borrower,
      _append(
        abi.encodeWithSelector(
          WildcatMarketConfig.setAnnualInterestAndReserveRatioBips.selector,
          700,
          200
        ),
        extraData
      )
    );
    _assertCall(
      fixture.hooks,
      0,
      abi.encodeWithSelector(
        IHooks.onSetAnnualInterestAndReserveRatioBips.selector,
        uint16(700),
        uint16(200),
        expectedState,
        extraData
      )
    );
    assertEq(fixture.market.annualInterestBips(), 800);
    assertEq(fixture.market.reserveRatioBips(), 300);

    Fixture memory disabled = _newFixture(EmptyHooksConfig);
    _callMarket(
      disabled.market,
      Borrower,
      _append(
        abi.encodeWithSelector(
          WildcatMarketConfig.setAnnualInterestAndReserveRatioBips.selector,
          700,
          200
        ),
        extraData
      )
    );
    assertEq(disabled.hooks.callCount(), 0);
    assertEq(disabled.market.annualInterestBips(), 700);
    assertEq(disabled.market.reserveRatioBips(), 200);
  }
}
