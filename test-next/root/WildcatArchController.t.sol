// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { Ownable } from 'solady/auth/Ownable.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { ArchControllerEngineMock } from '../mocks/ArchControllerMocks.sol';
import { ArchControllerRegisteredTargetMock } from '../mocks/ArchControllerMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract WildcatArchControllerTest is TestKernel {
  enum RegistryKind {
    ControllerFactory,
    Controller,
    Market,
    Borrower,
    Blacklist
  }

  struct RegistryFixture {
    WildcatArchController archController;
    address registrar;
    address first;
    address second;
  }

  event MarketAdded(address indexed controller, address market);
  event MarketRemoved(address market);
  event ControllerFactoryAdded(address controllerFactory);
  event ControllerFactoryRemoved(address controllerFactory);
  event BorrowerAdded(address borrower);
  event BorrowerRemoved(address borrower);
  event ControllerAdded(address indexed controllerFactory, address controller);
  event ControllerRemoved(address controller);
  event AssetBlacklisted(address asset);
  event AssetPermitted(address asset);
  event NewAllowedSenderOnchain(address sender);

  error SphereXOperatorOrAdminRequired();

  address internal constant BadCaller = address(0xBAD);
  address internal constant Factory = address(0xFAC7);
  address internal constant Controller = address(0xC017);
  address internal constant FirstEntry = address(0x1001);
  address internal constant SecondEntry = address(0x1002);
  address internal constant SphereXOperator = address(0x5EED);

  function _deployArchController() internal returns (WildcatArchController archController) {
    archController = WildcatArchController(
      _deployCode('src/WildcatArchController.sol:WildcatArchController')
    );
  }

  function _newRegistryFixture(
    RegistryKind kind
  ) internal returns (RegistryFixture memory fixture) {
    fixture.archController = _deployArchController();
    fixture.first = FirstEntry;
    fixture.second = SecondEntry;

    if (kind == RegistryKind.Controller) {
      fixture.registrar = Factory;
      fixture.archController.registerControllerFactory(Factory);
    } else if (kind == RegistryKind.Market) {
      fixture.registrar = Controller;
      fixture.archController.registerControllerFactory(Factory);
      vm.prank(Factory);
      fixture.archController.registerController(Controller);
    } else {
      fixture.registrar = address(this);
    }
  }

  function _add(
    RegistryKind kind,
    RegistryFixture memory fixture,
    address entry,
    address caller
  ) internal {
    vm.prank(caller);
    if (kind == RegistryKind.ControllerFactory) {
      fixture.archController.registerControllerFactory(entry);
    } else if (kind == RegistryKind.Controller) {
      fixture.archController.registerController(entry);
    } else if (kind == RegistryKind.Market) {
      fixture.archController.registerMarket(entry);
    } else if (kind == RegistryKind.Borrower) {
      fixture.archController.registerBorrower(entry);
    } else {
      fixture.archController.addBlacklist(entry);
    }
  }

  function _remove(
    RegistryKind kind,
    RegistryFixture memory fixture,
    address entry,
    address caller
  ) internal {
    vm.prank(caller);
    if (kind == RegistryKind.ControllerFactory) {
      fixture.archController.removeControllerFactory(entry);
    } else if (kind == RegistryKind.Controller) {
      fixture.archController.removeController(entry);
    } else if (kind == RegistryKind.Market) {
      fixture.archController.removeMarket(entry);
    } else if (kind == RegistryKind.Borrower) {
      fixture.archController.removeBorrower(entry);
    } else {
      fixture.archController.removeBlacklist(entry);
    }
  }

  function _isRegistered(
    RegistryKind kind,
    WildcatArchController archController,
    address entry
  ) internal view returns (bool) {
    if (kind == RegistryKind.ControllerFactory) {
      return archController.isRegisteredControllerFactory(entry);
    }
    if (kind == RegistryKind.Controller) return archController.isRegisteredController(entry);
    if (kind == RegistryKind.Market) return archController.isRegisteredMarket(entry);
    if (kind == RegistryKind.Borrower) return archController.isRegisteredBorrower(entry);
    return archController.isBlacklistedAsset(entry);
  }

  function _getAll(
    RegistryKind kind,
    WildcatArchController archController
  ) internal view returns (address[] memory entries) {
    if (kind == RegistryKind.ControllerFactory) {
      return archController.getRegisteredControllerFactories();
    }
    if (kind == RegistryKind.Controller) return archController.getRegisteredControllers();
    if (kind == RegistryKind.Market) return archController.getRegisteredMarkets();
    if (kind == RegistryKind.Borrower) return archController.getRegisteredBorrowers();
    return archController.getBlacklistedAssets();
  }

  function _getPage(
    RegistryKind kind,
    WildcatArchController archController,
    uint256 start,
    uint256 end
  ) internal view returns (address[] memory entries) {
    if (kind == RegistryKind.ControllerFactory) {
      return archController.getRegisteredControllerFactories(start, end);
    }
    if (kind == RegistryKind.Controller) {
      return archController.getRegisteredControllers(start, end);
    }
    if (kind == RegistryKind.Market) return archController.getRegisteredMarkets(start, end);
    if (kind == RegistryKind.Borrower) return archController.getRegisteredBorrowers(start, end);
    return archController.getBlacklistedAssets(start, end);
  }

  function _getCount(
    RegistryKind kind,
    WildcatArchController archController
  ) internal view returns (uint256) {
    if (kind == RegistryKind.ControllerFactory) {
      return archController.getRegisteredControllerFactoriesCount();
    }
    if (kind == RegistryKind.Controller) return archController.getRegisteredControllersCount();
    if (kind == RegistryKind.Market) return archController.getRegisteredMarketsCount();
    if (kind == RegistryKind.Borrower) return archController.getRegisteredBorrowersCount();
    return archController.getBlacklistedAssetsCount();
  }

  function _duplicateError(RegistryKind kind) internal pure returns (bytes4) {
    if (kind == RegistryKind.ControllerFactory) {
      return WildcatArchController.ControllerFactoryAlreadyExists.selector;
    }
    if (kind == RegistryKind.Controller) {
      return WildcatArchController.ControllerAlreadyExists.selector;
    }
    if (kind == RegistryKind.Market) return WildcatArchController.MarketAlreadyExists.selector;
    if (kind == RegistryKind.Borrower) {
      return WildcatArchController.BorrowerAlreadyExists.selector;
    }
    return WildcatArchController.AssetAlreadyBlacklisted.selector;
  }

  function _missingError(RegistryKind kind) internal pure returns (bytes4) {
    if (kind == RegistryKind.ControllerFactory) {
      return WildcatArchController.ControllerFactoryDoesNotExist.selector;
    }
    if (kind == RegistryKind.Controller)
      return WildcatArchController.ControllerDoesNotExist.selector;
    if (kind == RegistryKind.Market) return WildcatArchController.MarketDoesNotExist.selector;
    if (kind == RegistryKind.Borrower) return WildcatArchController.BorrowerDoesNotExist.selector;
    return WildcatArchController.AssetNotBlacklisted.selector;
  }

  function _unauthorizedAddError(RegistryKind kind) internal pure returns (bytes4) {
    if (kind == RegistryKind.Controller) return WildcatArchController.NotControllerFactory.selector;
    if (kind == RegistryKind.Market) return WildcatArchController.NotController.selector;
    return Ownable.Unauthorized.selector;
  }

  function _expectAddedEvent(
    RegistryKind kind,
    RegistryFixture memory fixture,
    address entry
  ) internal {
    vm.expectEmit(address(fixture.archController));
    if (kind == RegistryKind.ControllerFactory) {
      emit ControllerFactoryAdded(entry);
    } else if (kind == RegistryKind.Controller) {
      emit ControllerAdded(fixture.registrar, entry);
    } else if (kind == RegistryKind.Market) {
      emit MarketAdded(fixture.registrar, entry);
    } else if (kind == RegistryKind.Borrower) {
      emit BorrowerAdded(entry);
    } else {
      emit AssetBlacklisted(entry);
    }
  }

  function _expectRemovedEvent(
    RegistryKind kind,
    RegistryFixture memory fixture,
    address entry
  ) internal {
    vm.expectEmit(address(fixture.archController));
    if (kind == RegistryKind.ControllerFactory) {
      emit ControllerFactoryRemoved(entry);
    } else if (kind == RegistryKind.Controller) {
      emit ControllerRemoved(entry);
    } else if (kind == RegistryKind.Market) {
      emit MarketRemoved(entry);
    } else if (kind == RegistryKind.Borrower) {
      emit BorrowerRemoved(entry);
    } else {
      emit AssetPermitted(entry);
    }
  }

  // ========================================================================== //
  //                              Registry matrix                               //
  // ========================================================================== //

  function test_registryMatrix_AddEmitsAndRegisters() external {
    for (uint8 i; i <= uint8(RegistryKind.Blacklist); i++) {
      RegistryKind kind = RegistryKind(i);
      RegistryFixture memory fixture = _newRegistryFixture(kind);
      _expectAddedEvent(kind, fixture, fixture.first);
      _add(kind, fixture, fixture.first, fixture.registrar);

      assertTrue(_isRegistered(kind, fixture.archController, fixture.first), 'registered');
      assertEq(_getCount(kind, fixture.archController), 1, 'count');
    }
  }

  function test_registryMatrix_AddRejectsUnauthorizedCaller() external {
    for (uint8 i; i <= uint8(RegistryKind.Blacklist); i++) {
      RegistryKind kind = RegistryKind(i);
      RegistryFixture memory fixture = _newRegistryFixture(kind);
      vm.expectRevert(_unauthorizedAddError(kind));
      _add(kind, fixture, fixture.first, BadCaller);
    }
  }

  function test_registryMatrix_AddRejectsDuplicateEntry() external {
    for (uint8 i; i <= uint8(RegistryKind.Blacklist); i++) {
      RegistryKind kind = RegistryKind(i);
      RegistryFixture memory fixture = _newRegistryFixture(kind);
      _add(kind, fixture, fixture.first, fixture.registrar);

      vm.expectRevert(_duplicateError(kind));
      _add(kind, fixture, fixture.first, fixture.registrar);
    }
  }

  function test_registryMatrix_RemoveEmitsAndUnregisters() external {
    for (uint8 i; i <= uint8(RegistryKind.Blacklist); i++) {
      RegistryKind kind = RegistryKind(i);
      RegistryFixture memory fixture = _newRegistryFixture(kind);
      _add(kind, fixture, fixture.first, fixture.registrar);

      _expectRemovedEvent(kind, fixture, fixture.first);
      _remove(kind, fixture, fixture.first, address(this));
      assertFalse(_isRegistered(kind, fixture.archController, fixture.first), 'unregistered');
      assertEq(_getCount(kind, fixture.archController), 0, 'count');
    }
  }

  function test_registryMatrix_RemoveRejectsMissingEntry() external {
    for (uint8 i; i <= uint8(RegistryKind.Blacklist); i++) {
      RegistryKind kind = RegistryKind(i);
      RegistryFixture memory fixture = _newRegistryFixture(kind);

      vm.expectRevert(_missingError(kind));
      _remove(kind, fixture, fixture.first, address(this));
    }
  }

  function test_registryMatrix_RemoveRequiresOwner() external {
    for (uint8 i; i <= uint8(RegistryKind.Blacklist); i++) {
      RegistryKind kind = RegistryKind(i);
      RegistryFixture memory fixture = _newRegistryFixture(kind);
      _add(kind, fixture, fixture.first, fixture.registrar);

      vm.expectRevert(Ownable.Unauthorized.selector);
      _remove(kind, fixture, fixture.first, BadCaller);
    }
  }

  function test_registryMatrix_EnumerationPaginationAndSwapPop() external {
    for (uint8 i; i <= uint8(RegistryKind.Blacklist); i++) {
      RegistryKind kind = RegistryKind(i);
      RegistryFixture memory fixture = _newRegistryFixture(kind);
      _add(kind, fixture, fixture.first, fixture.registrar);
      _add(kind, fixture, fixture.second, fixture.registrar);

      address[] memory entries = _getAll(kind, fixture.archController);
      assertEq(entries.length, 2, 'all length');
      assertEq(entries[0], fixture.first, 'all first');
      assertEq(entries[1], fixture.second, 'all second');

      entries = _getPage(kind, fixture.archController, 0, 3);
      assertEq(entries.length, 2, 'clamped page length');
      assertEq(entries[0], fixture.first, 'clamped first');
      assertEq(entries[1], fixture.second, 'clamped second');

      entries = _getPage(kind, fixture.archController, 1, 2);
      assertEq(entries.length, 1, 'partial page length');
      assertEq(entries[0], fixture.second, 'partial entry');
      assertEq(_getCount(kind, fixture.archController), 2, 'count before removal');

      _remove(kind, fixture, fixture.first, address(this));
      entries = _getAll(kind, fixture.archController);
      assertEq(entries.length, 1, 'post-removal length');
      assertEq(entries[0], fixture.second, 'swap-pop entry');
      assertEq(_getCount(kind, fixture.archController), 1, 'count after removal');
    }
  }

  // ========================================================================== //
  //                       Registered SphereX propagation                       //
  // ========================================================================== //

  function _deployRegisteredTarget(
    bool blockEngineUpdates
  ) internal returns (ArchControllerRegisteredTargetMock target) {
    target = ArchControllerRegisteredTargetMock(
      _deployCode(
        'test-next/mocks/ArchControllerMocks.sol:ArchControllerRegisteredTargetMock',
        abi.encode(blockEngineUpdates)
      )
    );
  }

  function _deployEngine() internal returns (ArchControllerEngineMock engine) {
    engine = ArchControllerEngineMock(
      _deployCode('test-next/mocks/ArchControllerMocks.sol:ArchControllerEngineMock')
    );
  }

  function _registerSphereXTargets(
    WildcatArchController archController,
    bool blockControllerUpdates
  )
    internal
    returns (
      ArchControllerRegisteredTargetMock factory,
      ArchControllerRegisteredTargetMock controller,
      ArchControllerRegisteredTargetMock market
    )
  {
    factory = _deployRegisteredTarget(false);
    controller = _deployRegisteredTarget(blockControllerUpdates);
    market = _deployRegisteredTarget(false);
    archController.registerControllerFactory(address(factory));
    vm.prank(address(factory));
    archController.registerController(address(controller));
    vm.prank(address(controller));
    archController.registerMarket(address(market));
  }

  function _setArchControllerEngine(WildcatArchController archController, address engine) internal {
    archController.changeSphereXOperator(SphereXOperator);
    vm.prank(SphereXOperator);
    archController.changeSphereXEngine(engine);
  }

  function _singleton(address account) internal pure returns (address[] memory accounts) {
    accounts = new address[](1);
    accounts[0] = account;
  }

  function test_updateSphereXEngine_UpdatesEveryRegistryAndEngineAllowlist() external {
    WildcatArchController archController = _deployArchController();
    (
      ArchControllerRegisteredTargetMock factory,
      ArchControllerRegisteredTargetMock controller,
      ArchControllerRegisteredTargetMock market
    ) = _registerSphereXTargets(archController, false);
    ArchControllerEngineMock engine = _deployEngine();
    _setArchControllerEngine(archController, address(engine));

    address[] memory factories = _singleton(address(factory));
    address[] memory controllers = _singleton(address(controller));
    address[] memory markets = _singleton(address(market));

    vm.expectEmit(address(factory));
    emit ArchControllerRegisteredTargetMock.ChangedSpherexEngineAddress(
      address(0),
      address(engine)
    );
    vm.expectEmit(address(engine));
    emit ArchControllerEngineMock.NewSenderOnEngine(address(factory));
    vm.expectEmit(address(archController));
    emit NewAllowedSenderOnchain(address(factory));

    vm.expectEmit(address(controller));
    emit ArchControllerRegisteredTargetMock.ChangedSpherexEngineAddress(
      address(0),
      address(engine)
    );
    vm.expectEmit(address(engine));
    emit ArchControllerEngineMock.NewSenderOnEngine(address(controller));
    vm.expectEmit(address(archController));
    emit NewAllowedSenderOnchain(address(controller));

    vm.expectEmit(address(market));
    emit ArchControllerRegisteredTargetMock.ChangedSpherexEngineAddress(
      address(0),
      address(engine)
    );
    vm.expectEmit(address(engine));
    emit ArchControllerEngineMock.NewSenderOnEngine(address(market));
    vm.expectEmit(address(archController));
    emit NewAllowedSenderOnchain(address(market));

    vm.prank(SphereXOperator);
    archController.updateSphereXEngineOnRegisteredContracts(factories, controllers, markets);

    assertEq(factory.sphereXEngine(), address(engine), 'factory engine');
    assertEq(controller.sphereXEngine(), address(engine), 'controller engine');
    assertEq(market.sphereXEngine(), address(engine), 'market engine');
    assertEq(engine.allowedSenderCalls(address(factory)), 1, 'factory allowlist calls');
    assertEq(engine.allowedSenderCalls(address(controller)), 1, 'controller allowlist calls');
    assertEq(engine.allowedSenderCalls(address(market)), 1, 'market allowlist calls');
  }

  function test_updateSphereXEngine_NullEngineStillUpdatesRegisteredContracts() external {
    WildcatArchController archController = _deployArchController();
    (
      ArchControllerRegisteredTargetMock factory,
      ArchControllerRegisteredTargetMock controller,
      ArchControllerRegisteredTargetMock market
    ) = _registerSphereXTargets(archController, false);
    ArchControllerEngineMock engine = _deployEngine();
    _setArchControllerEngine(archController, address(engine));

    address[] memory factories = _singleton(address(factory));
    address[] memory controllers = _singleton(address(controller));
    address[] memory markets = _singleton(address(market));
    vm.prank(SphereXOperator);
    archController.updateSphereXEngineOnRegisteredContracts(factories, controllers, markets);

    vm.prank(SphereXOperator);
    archController.changeSphereXEngine(address(0));
    vm.prank(SphereXOperator);
    archController.updateSphereXEngineOnRegisteredContracts(factories, controllers, markets);

    assertEq(factory.sphereXEngine(), address(0), 'factory engine');
    assertEq(controller.sphereXEngine(), address(0), 'controller engine');
    assertEq(market.sphereXEngine(), address(0), 'market engine');
    assertEq(factory.updateCount(), 2, 'factory updates');
    assertEq(controller.updateCount(), 2, 'controller updates');
    assertEq(market.updateCount(), 2, 'market updates');
    assertEq(engine.allowedSenderCalls(address(factory)), 1, 'factory allowlist calls');
    assertEq(engine.allowedSenderCalls(address(controller)), 1, 'controller allowlist calls');
    assertEq(engine.allowedSenderCalls(address(market)), 1, 'market allowlist calls');
  }

  function test_updateSphereXEngine_RejectsMissingRegistryEntries() external {
    WildcatArchController archController = _deployArchController();
    address[] memory empty = new address[](0);
    address[] memory missing = _singleton(address(0xDEAD));

    vm.expectRevert(WildcatArchController.ControllerFactoryDoesNotExist.selector);
    archController.updateSphereXEngineOnRegisteredContracts(missing, empty, empty);
    vm.expectRevert(WildcatArchController.ControllerDoesNotExist.selector);
    archController.updateSphereXEngineOnRegisteredContracts(empty, missing, empty);
    vm.expectRevert(WildcatArchController.MarketDoesNotExist.selector);
    archController.updateSphereXEngineOnRegisteredContracts(empty, empty, missing);
  }

  function testFuzz_updateSphereXEngine_RequiresOperatorOrAdmin(address account) external {
    WildcatArchController archController = _deployArchController();
    archController.changeSphereXOperator(SphereXOperator);
    vm.assume(account != address(this) && account != SphereXOperator);
    address[] memory empty = new address[](0);

    vm.expectRevert(SphereXOperatorOrAdminRequired.selector);
    vm.prank(account);
    archController.updateSphereXEngineOnRegisteredContracts(empty, empty, empty);
  }

  function test_updateSphereXEngine_BubblesRegisteredContractRevert() external {
    WildcatArchController archController = _deployArchController();
    (, ArchControllerRegisteredTargetMock controller, ) = _registerSphereXTargets(
      archController,
      true
    );
    address[] memory empty = new address[](0);
    address[] memory controllers = _singleton(address(controller));

    vm.expectRevert(ArchControllerRegisteredTargetMock.ChangeSphereXEngineBlocked.selector);
    archController.updateSphereXEngineOnRegisteredContracts(empty, controllers, empty);
  }
}
