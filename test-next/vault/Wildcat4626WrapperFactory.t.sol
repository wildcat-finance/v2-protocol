// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { Wildcat4626WrapperFactory } from 'src/vault/Wildcat4626WrapperFactory.sol';
import { IncompleteWrapperTransferPolicyMock } from '../mocks/WrapperMocks.sol';
import { WrapperArchControllerMock, WrapperFactoryMarketMock } from '../mocks/WrapperMocks.sol';
import { WrapperReturnBombMock, WrapperSentinelMock } from '../mocks/WrapperMocks.sol';
import { WrapperShortReturnMock, WrapperV1FactoryMock } from '../mocks/WrapperMocks.sol';
import { WrapperWrongRoundingMock } from '../mocks/WrapperMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';
import { Vm } from 'forge-std/Vm.sol';

contract Wildcat4626WrapperFactoryTest is TestKernel {
  event WrapperDeployed(address indexed market, address indexed wrapper);

  bytes32 internal constant FloorRounding = keccak256('scaleAmountDown');
  address internal constant Borrower = address(0xB0123);

  struct Fixture {
    WrapperArchControllerMock archController;
    WrapperV1FactoryMock v1Factory;
    Wildcat4626WrapperFactory factory;
    WrapperSentinelMock sentinel;
    WrapperFactoryMarketMock market;
  }

  function _deployFactory(
    address archController,
    address v1Factory
  ) private returns (Wildcat4626WrapperFactory) {
    return
      Wildcat4626WrapperFactory(
        _deployCode(
          'src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory',
          abi.encode(archController, v1Factory)
        )
      );
  }

  function _deployMarket(
    Fixture memory fixture,
    Wildcat4626WrapperFactory factory,
    bool declaresRounding,
    bytes32 rounding
  ) private returns (WrapperFactoryMarketMock market) {
    market = WrapperFactoryMarketMock(
      _deployCode(
        'test-next/mocks/WrapperMocks.sol:WrapperFactoryMarketMock',
        abi.encode(
          Borrower,
          address(fixture.sentinel),
          address(factory),
          declaresRounding,
          rounding
        )
      )
    );
  }

  function _newFixture() private returns (Fixture memory fixture) {
    fixture.archController = WrapperArchControllerMock(
      _deployCode('test-next/mocks/WrapperMocks.sol:WrapperArchControllerMock')
    );
    fixture.v1Factory = WrapperV1FactoryMock(
      _deployCode('test-next/mocks/WrapperMocks.sol:WrapperV1FactoryMock')
    );
    fixture.sentinel = WrapperSentinelMock(
      _deployCode('test-next/mocks/WrapperMocks.sol:WrapperSentinelMock')
    );
    fixture.factory = _deployFactory(address(fixture.archController), address(fixture.v1Factory));
    fixture.market = _deployMarket(fixture, fixture.factory, true, FloorRounding);
    fixture.archController.setRegisteredMarket(address(fixture.market), true);
  }

  function test_constructorAcceptsZeroOrValidV1AndRejectsMalformedFactory() external {
    Fixture memory fixture = _newFixture();
    Wildcat4626WrapperFactory noLegacy = _deployFactory(
      address(fixture.archController),
      address(0)
    );

    assertEq(address(fixture.factory.v1Factory()), address(fixture.v1Factory), 'valid v1');
    assertEq(address(noLegacy.v1Factory()), address(0), 'zero v1');

    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626WrapperFactory.InvalidV1Factory.selector, address(0xDEAD))
    );
    _deployFactory(address(fixture.archController), address(0xDEAD));

    address shortReturner = _deployCode('test-next/mocks/WrapperMocks.sol:WrapperShortReturnMock');
    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626WrapperFactory.InvalidV1Factory.selector, shortReturner)
    );
    _deployFactory(address(fixture.archController), shortReturner);
  }

  function test_roundingProbeIsTotalAndRecognizesOnlyFloorMarkets() external {
    Fixture memory fixture = _newFixture();
    WrapperFactoryMarketMock legacy = _deployMarket(fixture, fixture.factory, false, bytes32(0));
    address shortReturner = _deployCode('test-next/mocks/WrapperMocks.sol:WrapperShortReturnMock');
    address wrongRounding = _deployCode(
      'test-next/mocks/WrapperMocks.sol:WrapperWrongRoundingMock'
    );
    address returnBomb = _deployCode('test-next/mocks/WrapperMocks.sol:WrapperReturnBombMock');

    assertTrue(fixture.factory.isFloorRoundingMarket(address(fixture.market)), 'floor market');
    assertFalse(fixture.factory.isFloorRoundingMarket(address(legacy)), 'legacy market');
    assertFalse(fixture.factory.isFloorRoundingMarket(address(0xE0A0)), 'codeless account');
    assertFalse(fixture.factory.isFloorRoundingMarket(shortReturner), 'short response');
    assertFalse(fixture.factory.isFloorRoundingMarket(wrongRounding), 'wrong rounding');
    assertFalse(fixture.factory.isFloorRoundingMarket(returnBomb), 'return bomb');
  }

  function test_legacyCreationAndDiscoveryRouteThroughV1() external {
    Fixture memory fixture = _newFixture();
    WrapperFactoryMarketMock legacy = _deployMarket(fixture, fixture.factory, false, bytes32(0));
    fixture.archController.setRegisteredMarket(address(legacy), true);

    address wrapper = fixture.factory.createWrapper(address(legacy));
    assertEq(fixture.v1Factory.createCalls(), 1, 'v1 call count');
    assertEq(wrapper, fixture.v1Factory.wrapperForMarket(address(legacy)), 'v1 wrapper');
    assertEq(fixture.factory.wrapperForMarket(address(legacy)), wrapper, 'routed discovery');

    vm.expectRevert(
      abi.encodeWithSelector(WrapperV1FactoryMock.WrapperAlreadyExists.selector, address(legacy))
    );
    fixture.factory.createWrapper(address(legacy));
  }

  function test_factoryWithoutV1RejectsLegacyButStillCreatesFloorWrapper() external {
    Fixture memory fixture = _newFixture();
    Wildcat4626WrapperFactory noLegacy = _deployFactory(
      address(fixture.archController),
      address(0)
    );
    WrapperFactoryMarketMock legacy = _deployMarket(fixture, noLegacy, false, bytes32(0));
    WrapperFactoryMarketMock floor = _deployMarket(fixture, noLegacy, true, FloorRounding);
    fixture.archController.setRegisteredMarket(address(legacy), true);
    fixture.archController.setRegisteredMarket(address(floor), true);

    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.LegacyMarketsNotSupported.selector,
        address(legacy)
      )
    );
    noLegacy.createWrapper(address(legacy));
    assertEq(noLegacy.wrapperForMarket(address(legacy)), address(0), 'legacy discovery');

    address wrapper = noLegacy.createWrapper(address(floor));
    assertEq(noLegacy.wrapperForMarket(address(floor)), wrapper, 'floor wrapper');
  }

  function test_declaredMarketsNeverFallThroughToV1() external {
    Fixture memory fixture = _newFixture();
    fixture.v1Factory.seedWrapper(address(fixture.market), address(0xBAD));
    assertEq(fixture.factory.wrapperForMarket(address(fixture.market)), address(0), 'crossed v1');

    address wrapper = fixture.factory.createWrapper(address(fixture.market));
    assertEq(fixture.factory.wrapperForMarket(address(fixture.market)), wrapper, 'local wrapper');

    address future = _deployCode('test-next/mocks/WrapperMocks.sol:WrapperWrongRoundingMock');
    fixture.archController.setRegisteredMarket(future, true);
    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.UnsupportedMarketRounding.selector,
        future,
        keccak256('somethingElse')
      )
    );
    fixture.factory.createWrapper(future);
    assertEq(fixture.factory.wrapperForMarket(future), address(0), 'future wrapper');
  }

  function test_floorCreationDeploysRecordsRegistersAndRejectsDuplicates() external {
    Fixture memory fixture = _newFixture();
    vm.recordLogs();
    address wrapperAddress = fixture.factory.createWrapper(address(fixture.market));
    Vm.Log[] memory logs = vm.getRecordedLogs();

    assertEq(logs.length, 1, 'event count');
    assertEq(logs[0].emitter, address(fixture.factory), 'event emitter');
    assertEq(logs[0].topics.length, 3, 'event topics');
    assertEq(logs[0].topics[0], keccak256('WrapperDeployed(address,address)'), 'event signature');
    assertEq(address(uint160(uint256(logs[0].topics[1]))), address(fixture.market), 'event market');
    assertEq(address(uint160(uint256(logs[0].topics[2]))), wrapperAddress, 'event wrapper');

    Wildcat4626Wrapper wrapper = Wildcat4626Wrapper(wrapperAddress);
    assertEq(fixture.factory.wrapperForMarket(address(fixture.market)), wrapperAddress, 'record');
    assertEq(fixture.market.registeredWrapper(), wrapperAddress, 'registration');
    assertEq(wrapper.asset(), address(fixture.market), 'asset');
    assertEq(wrapper.name(), 'factoryUSDC [4626 Vault Shares]', 'name');
    assertEq(wrapper.symbol(), 'v-factoryUSDC', 'symbol');
    assertEq(wrapper.decimals(), 18, 'decimals');

    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.WrapperAlreadyExists.selector,
        address(fixture.market)
      )
    );
    fixture.factory.createWrapper(address(fixture.market));

    vm.expectRevert(Wildcat4626Wrapper.NotWrapperFactory.selector);
    _deployCode(
      'src/vault/Wildcat4626Wrapper.sol:Wildcat4626Wrapper',
      abi.encode(address(fixture.market))
    );
  }

  function test_createRejectsZeroAndUnregisteredMarketsWithoutSideEffects() external {
    Fixture memory fixture = _newFixture();

    vm.expectRevert(Wildcat4626WrapperFactory.ZeroAddress.selector);
    fixture.factory.createWrapper(address(0));

    fixture.archController.setRegisteredMarket(address(fixture.market), false);
    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.NotRegisteredMarket.selector,
        address(fixture.market)
      )
    );
    fixture.factory.createWrapper(address(fixture.market));
    assertEq(fixture.factory.wrapperForMarket(address(fixture.market)), address(0), 'record');
    assertEq(fixture.market.registeredWrapper(), address(0), 'registration');
  }

  function test_createValidatesCompleteAndEnabledTransferPolicy() external {
    Fixture memory disabledFixture = _newFixture();
    disabledFixture.market.setTransferPolicy(true, true, false);
    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.MarketTransfersDisabled.selector,
        address(disabledFixture.market)
      )
    );
    disabledFixture.factory.createWrapper(address(disabledFixture.market));

    Fixture memory missingFixture = _newFixture();
    missingFixture.market.setHooksAddress(address(missingFixture.sentinel));
    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.UnsupportedMarketTransferPolicy.selector,
        address(missingFixture.market),
        address(missingFixture.sentinel)
      )
    );
    missingFixture.factory.createWrapper(address(missingFixture.market));

    Fixture memory incompleteFixture = _newFixture();
    address incompletePolicy = _deployCode(
      'test-next/mocks/WrapperMocks.sol:IncompleteWrapperTransferPolicyMock'
    );
    incompleteFixture.market.setHooksAddress(incompletePolicy);
    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.UnsupportedMarketTransferPolicy.selector,
        address(incompleteFixture.market),
        incompletePolicy
      )
    );
    incompleteFixture.factory.createWrapper(address(incompleteFixture.market));

    assertEq(disabledFixture.factory.wrapperForMarket(address(disabledFixture.market)), address(0));
    assertEq(missingFixture.factory.wrapperForMarket(address(missingFixture.market)), address(0));
    assertEq(
      incompleteFixture.factory.wrapperForMarket(address(incompleteFixture.market)),
      address(0)
    );
  }

  function test_wrapperCapacityFailsClosedWhenRecipientPolicyBreaksOrDenies() external {
    Fixture memory fixture = _newFixture();
    Wildcat4626Wrapper wrapper = Wildcat4626Wrapper(
      fixture.factory.createWrapper(address(fixture.market))
    );
    assertTrue(wrapper.maxDeposit(Borrower) > 0, 'initial deposit capacity');
    assertTrue(wrapper.maxMint(Borrower) > 0, 'initial mint capacity');

    fixture.market.setTransferPolicy(false, false, false);
    assertEq(wrapper.maxDeposit(Borrower), 0, 'denied deposit capacity');
    assertEq(wrapper.maxMint(Borrower), 0, 'denied mint capacity');

    fixture.market.setTransferPolicy(false, true, true);
    assertEq(wrapper.maxDeposit(Borrower), 0, 'broken deposit capacity');
    assertEq(wrapper.maxMint(Borrower), 0, 'broken mint capacity');
  }
}
