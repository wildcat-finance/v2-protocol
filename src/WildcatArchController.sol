// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // WildcatArchController
//  \ ^ /   Protocol registries and coordinated SphereX configuration.
//    V
//
//  SETUP
//  constructor()
//
//  SPHEREX ENGINE UPDATE
//  updateSphereXEngineOnRegisteredContracts(...)
//  _updateSphereXEngineOnRegisteredContractsInSet(...)
//  _callWith(...)
//
//  BORROWERS
//  registerBorrower(...)
//  removeBorrower(...)
//  isRegisteredBorrower(...)
//  getRegisteredBorrowers()
//  getRegisteredBorrowers(...)
//  getRegisteredBorrowersCount()
//
//  ASSET BLACKLIST
//  addBlacklist(...)
//  removeBlacklist(...)
//  isBlacklistedAsset(...)
//  getBlacklistedAssets()
//  getBlacklistedAssets(...)
//  getBlacklistedAssetsCount()
//
//  CONTROLLER FACTORIES
//  registerControllerFactory(...)
//  removeControllerFactory(...)
//  isRegisteredControllerFactory(...)
//  getRegisteredControllerFactories()
//  getRegisteredControllerFactories(...)
//  getRegisteredControllerFactoriesCount()
//
//  CONTROLLERS
//  onlyControllerFactory()
//  registerController(...)
//  removeController(...)
//  isRegisteredController(...)
//  getRegisteredControllers()
//  getRegisteredControllers(...)
//  getRegisteredControllersCount()
//
//  MARKETS
//  onlyController()
//  registerMarket(...)
//  removeMarket(...)
//  isRegisteredMarket(...)
//  getRegisteredMarkets()
//  getRegisteredMarkets(...)
//  getRegisteredMarketsCount()
// ═════

import { EnumerableSet } from 'openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import 'solady/auth/Ownable.sol';
import './spherex/SphereXConfig.sol';
import './libraries/MathUtils.sol';
import './interfaces/ISphereXProtectedRegisteredBase.sol';

// ┌─ WildcatArchController ────────────────────────────────────────────────────
/// @title Wildcat architecture controller
///
/// @notice owns the protocol registries and coordinates SphereX configuration across them.
///
/// @dev registry membership is an authorization decision. this singleton does not validate the
///      bytecode or reported parent of every address it registers, so operators still have to.
contract WildcatArchController is SphereXConfig, Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  // ░░▒▒▓▓██ [ STORAGE ] ──────────────────────────────────────────────────────

  EnumerableSet.AddressSet internal _markets;
  EnumerableSet.AddressSet internal _controllerFactories;
  EnumerableSet.AddressSet internal _borrowers;
  EnumerableSet.AddressSet internal _controllers;
  EnumerableSet.AddressSet internal _assetBlacklist;

  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev the caller is not a registered controller factory.
  error NotControllerFactory();

  /// @dev the caller is not a registered controller.
  error NotController();

  /// @dev the borrower is already registered.
  error BorrowerAlreadyExists();

  /// @dev the controller factory is already registered.
  error ControllerFactoryAlreadyExists();

  /// @dev the controller is already registered.
  error ControllerAlreadyExists();

  /// @dev the market is already registered.
  error MarketAlreadyExists();

  /// @dev the borrower is not registered.
  error BorrowerDoesNotExist();

  /// @dev the asset is already blacklisted.
  error AssetAlreadyBlacklisted();

  /// @dev the controller factory is not registered.
  error ControllerFactoryDoesNotExist();

  /// @dev the controller is not registered.
  error ControllerDoesNotExist();

  /// @dev the asset is not blacklisted.
  error AssetNotBlacklisted();

  /// @dev the market is not registered.
  error MarketDoesNotExist();

  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  /// @notice emitted when a registered controller adds a market.
  event MarketAdded(address indexed controller, address market);

  /// @notice emitted when the protocol owner removes a market.
  event MarketRemoved(address market);

  /// @notice emitted when the protocol owner adds a controller factory.
  event ControllerFactoryAdded(address controllerFactory);

  /// @notice emitted when the protocol owner removes a controller factory.
  event ControllerFactoryRemoved(address controllerFactory);

  /// @notice emitted when the protocol owner registers a borrower principal.
  event BorrowerAdded(address borrower);

  /// @notice emitted when the protocol owner removes a borrower principal.
  event BorrowerRemoved(address borrower);

  /// @notice emitted when the protocol owner blacklists an asset.
  event AssetBlacklisted(address asset);

  /// @notice emitted when the protocol owner removes an asset from the blacklist.
  event AssetPermitted(address asset);

  /// @notice emitted when a registered factory adds a controller.
  event ControllerAdded(address indexed controllerFactory, address controller);

  /// @notice emitted when the protocol owner removes a controller.
  event ControllerRemoved(address controller);

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor() SphereXConfig(msg.sender, address(0), address(0)) {
    _initializeOwner(msg.sender);
  }

  // ░░▒▒▓▓██ [ SPHEREX ENGINE UPDATE ] ────────────────────────────────────────

  // ┌─ updateSphereXEngineOnRegisteredContracts ─────
  /// @notice push the current SphereX engine to selected registered contracts.
  ///
  /// @dev only the SphereX operator or admin can call this. it also allows each selected contract
  ///      on the nonzero engine. every address must still be present in the matching registry, and
  ///      one failed update reverts the whole batch.
  function updateSphereXEngineOnRegisteredContracts(
    address[] calldata controllerFactories,
    address[] calldata controllers,
    address[] calldata markets
  )
    external
    spherexOnlyOperatorOrAdmin
  {
    address engineAddress = sphereXEngine();
    bytes memory changeSphereXEngineCalldata =
      abi.encodeWithSelector(ISphereXProtectedRegisteredBase.changeSphereXEngine.selector, engineAddress);
    bytes memory addAllowedSenderOnChainCalldata;
    if (engineAddress != address(0)) {
      addAllowedSenderOnChainCalldata =
        abi.encodeWithSelector(ISphereXEngine.addAllowedSenderOnChain.selector, address(0));
    }
    _updateSphereXEngineOnRegisteredContractsInSet(
      _controllerFactories,
      engineAddress,
      controllerFactories,
      changeSphereXEngineCalldata,
      addAllowedSenderOnChainCalldata,
      ControllerFactoryDoesNotExist.selector
    );
    _updateSphereXEngineOnRegisteredContractsInSet(
      _controllers,
      engineAddress,
      controllers,
      changeSphereXEngineCalldata,
      addAllowedSenderOnChainCalldata,
      ControllerDoesNotExist.selector
    );
    _updateSphereXEngineOnRegisteredContractsInSet(
      _markets,
      engineAddress,
      markets,
      changeSphereXEngineCalldata,
      addAllowedSenderOnChainCalldata,
      MarketDoesNotExist.selector
    );
  }

  // ┌─ _updateSphereXEngineOnRegisteredContractsInSet ─────
  function _updateSphereXEngineOnRegisteredContractsInSet(
    EnumerableSet.AddressSet storage set,
    address engineAddress,
    address[] memory contracts,
    bytes memory changeSphereXEngineCalldata,
    bytes memory addAllowedSenderOnChainCalldata,
    bytes4 notInSetErrorSelectorBytes
  )
    internal
  {
    for (uint256 i = 0; i < contracts.length; i++) {
      address account = contracts[i];
      if (!set.contains(account)) {
        uint32 notInSetErrorSelector = uint32(notInSetErrorSelectorBytes);
        assembly {
          mstore(0, notInSetErrorSelector)
          revert(0x1c, 0x04)
        }
      }
      _callWith(account, changeSphereXEngineCalldata);
      if (engineAddress != address(0)) {
        assembly {
          mstore(add(addAllowedSenderOnChainCalldata, 0x24), account)
        }
        _callWith(engineAddress, addAllowedSenderOnChainCalldata);
        emit_NewAllowedSenderOnchain(account);
      }
    }
  }

  // ┌─ _callWith ─────
  function _callWith(address target, bytes memory data) internal {
    assembly {
      if iszero(call(gas(), target, 0, add(data, 0x20), mload(data), 0, 0)) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
  }

  // ░░▒▒▓▓██ [ BORROWERS ] ────────────────────────────────────────────────────

  // ┌─ registerBorrower ─────
  /// @dev owner-only borrower registration. reverts if already registered.
  function registerBorrower(address borrower) external onlyOwner {
    if (!_borrowers.add(borrower)) {
      revert BorrowerAlreadyExists();
    }
    emit BorrowerAdded(borrower);
  }

  // ┌─ removeBorrower ─────
  /// @dev owner-only borrower removal. reverts if not registered.
  function removeBorrower(address borrower) external onlyOwner {
    if (!_borrowers.remove(borrower)) {
      revert BorrowerDoesNotExist();
    }
    emit BorrowerRemoved(borrower);
  }

  // ┌─ isRegisteredBorrower ─────
  /// @notice report whether `borrower` is a currently registered principal.
  function isRegisteredBorrower(address borrower) external view returns (bool) {
    return _borrowers.contains(borrower);
  }

  // ┌─ getRegisteredBorrowers ─────
  /// @notice return every registered borrower in unstable enumeration order.
  function getRegisteredBorrowers() external view returns (address[] memory) {
    return _borrowers.values();
  }

  // ┌─ getRegisteredBorrowers ─────
  /// @notice return borrowers in `[start, min(end, count))` in unstable enumeration order.
  function getRegisteredBorrowers(uint256 start, uint256 end) external view returns (address[] memory arr) {
    // CAF-13 known issue: malformed ranges can panic after `end` is clamped.
    // the singleton keeps deployed behavior; new registries should reject
    // `start >= end` explicitly before subtracting.
    uint256 len = _borrowers.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _borrowers.at(start + i);
    }
  }

  // ┌─ getRegisteredBorrowersCount ─────
  /// @notice return the current number of registered borrowers.
  function getRegisteredBorrowersCount() external view returns (uint256) {
    return _borrowers.length();
  }

  // ░░▒▒▓▓██ [ ASSET BLACKLIST ] ──────────────────────────────────────────────

  // ┌─ addBlacklist ─────
  /// @dev owner-only asset blacklist insertion. reverts if already blacklisted.
  function addBlacklist(address asset) external onlyOwner {
    if (!_assetBlacklist.add(asset)) {
      revert AssetAlreadyBlacklisted();
    }
    emit AssetBlacklisted(asset);
  }

  // ┌─ removeBlacklist ─────
  /// @dev owner-only asset blacklist removal. reverts if not blacklisted.
  function removeBlacklist(address asset) external onlyOwner {
    if (!_assetBlacklist.remove(asset)) {
      revert AssetNotBlacklisted();
    }
    emit AssetPermitted(asset);
  }

  // ┌─ isBlacklistedAsset ─────
  /// @notice report whether `asset` is currently blacklisted.
  function isBlacklistedAsset(address asset) external view returns (bool) {
    return _assetBlacklist.contains(asset);
  }

  // ┌─ getBlacklistedAssets ─────
  /// @notice return every blacklisted asset in unstable enumeration order.
  function getBlacklistedAssets() external view returns (address[] memory) {
    return _assetBlacklist.values();
  }

  // ┌─ getBlacklistedAssets ─────
  /// @notice return assets in `[start, min(end, count))` in unstable enumeration order.
  function getBlacklistedAssets(uint256 start, uint256 end) external view returns (address[] memory arr) {
    // CAF-13: keep singleton pagination behavior; see Known Issues.
    uint256 len = _assetBlacklist.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _assetBlacklist.at(start + i);
    }
  }

  // ┌─ getBlacklistedAssetsCount ─────
  /// @notice return the current number of blacklisted assets.
  function getBlacklistedAssetsCount() external view returns (uint256) {
    return _assetBlacklist.length();
  }

  // ░░▒▒▓▓██ [ CONTROLLER FACTORIES ] ─────────────────────────────────────────

  // ┌─ registerControllerFactory ─────
  /// @dev owner-only controller factory registration. reverts if already registered.
  function registerControllerFactory(address factory) external onlyOwner {
    // CAF-16 known issue: the singleton does not validate that `factory` is a
    // contract or reports this ArchController. operators must validate before
    // registration; new registry bytecode should enforce it.
    if (!_controllerFactories.add(factory)) {
      revert ControllerFactoryAlreadyExists();
    }
    _addAllowedSenderOnChain(factory);
    emit ControllerFactoryAdded(factory);
  }

  // ┌─ removeControllerFactory ─────
  /// @dev owner-only controller factory removal. reverts if not registered.
  function removeControllerFactory(address factory) external onlyOwner {
    if (!_controllerFactories.remove(factory)) {
      revert ControllerFactoryDoesNotExist();
    }
    emit ControllerFactoryRemoved(factory);
  }

  // ┌─ isRegisteredControllerFactory ─────
  /// @notice report whether `factory` is currently registered.
  function isRegisteredControllerFactory(address factory) external view returns (bool) {
    return _controllerFactories.contains(factory);
  }

  // ┌─ getRegisteredControllerFactories ─────
  /// @notice return every controller factory in unstable enumeration order.
  function getRegisteredControllerFactories() external view returns (address[] memory) {
    return _controllerFactories.values();
  }

  // ┌─ getRegisteredControllerFactories ─────
  /// @notice return factories in `[start, min(end, count))` in unstable enumeration order.
  function getRegisteredControllerFactories(uint256 start, uint256 end) external view returns (address[] memory arr) {
    // CAF-13: keep singleton pagination behavior; see Known Issues.
    uint256 len = _controllerFactories.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _controllerFactories.at(start + i);
    }
  }

  // ┌─ getRegisteredControllerFactoriesCount ─────
  /// @notice return the current number of registered controller factories.
  function getRegisteredControllerFactoriesCount() external view returns (uint256) {
    return _controllerFactories.length();
  }

  // ░░▒▒▓▓██ [ CONTROLLERS ] ──────────────────────────────────────────────────

  // ┌─ onlyControllerFactory ─────
  modifier onlyControllerFactory() {
    if (!_controllerFactories.contains(msg.sender)) {
      revert NotControllerFactory();
    }
    _;
  }

  // ┌─ registerController ─────
  /// @dev registered-factory-only controller registration. reverts if already registered.
  function registerController(address controller) external onlyControllerFactory {
    // CAF-16: registered controller addresses are trusted privileged input on
    // the singleton. validate off-chain before registration.
    if (!_controllers.add(controller)) {
      revert ControllerAlreadyExists();
    }
    _addAllowedSenderOnChain(controller);
    emit ControllerAdded(msg.sender, controller);
  }

  // ┌─ removeController ─────
  /// @dev owner-only controller removal. reverts if not registered.
  function removeController(address controller) external onlyOwner {
    if (!_controllers.remove(controller)) {
      revert ControllerDoesNotExist();
    }
    emit ControllerRemoved(controller);
  }

  // ┌─ isRegisteredController ─────
  /// @notice report whether `controller` is currently registered.
  function isRegisteredController(address controller) external view returns (bool) {
    return _controllers.contains(controller);
  }

  // ┌─ getRegisteredControllers ─────
  /// @notice return every controller in unstable enumeration order.
  function getRegisteredControllers() external view returns (address[] memory) {
    return _controllers.values();
  }

  // ┌─ getRegisteredControllers ─────
  /// @notice return controllers in `[start, min(end, count))` in unstable enumeration order.
  function getRegisteredControllers(uint256 start, uint256 end) external view returns (address[] memory arr) {
    // CAF-13: keep singleton pagination behavior; see Known Issues.
    uint256 len = _controllers.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _controllers.at(start + i);
    }
  }

  // ┌─ getRegisteredControllersCount ─────
  /// @notice return the current number of registered controllers.
  function getRegisteredControllersCount() external view returns (uint256) {
    return _controllers.length();
  }

  // ░░▒▒▓▓██ [ MARKETS ] ──────────────────────────────────────────────────────

  // ┌─ onlyController ─────
  modifier onlyController() {
    if (!_controllers.contains(msg.sender)) {
      revert NotController();
    }
    _;
  }

  // ┌─ registerMarket ─────
  /// @dev registered-controller-only market registration. reverts if already registered.
  function registerMarket(address market) external onlyController {
    // CAF-16: the singleton does not validate market code, archController(),
    // or factory(). controllers must only register conforming markets.
    if (!_markets.add(market)) {
      revert MarketAlreadyExists();
    }
    _addAllowedSenderOnChain(market);
    emit MarketAdded(msg.sender, market);
  }

  // ┌─ removeMarket ─────
  /// @dev owner-only market removal. reverts if not registered.
  function removeMarket(address market) external onlyOwner {
    if (!_markets.remove(market)) {
      revert MarketDoesNotExist();
    }
    emit MarketRemoved(market);
  }

  // ┌─ isRegisteredMarket ─────
  /// @notice report whether `market` is currently registered.
  function isRegisteredMarket(address market) external view returns (bool) {
    return _markets.contains(market);
  }

  // ┌─ getRegisteredMarkets ─────
  /// @notice return every registered market in unstable enumeration order.
  function getRegisteredMarkets() external view returns (address[] memory) {
    return _markets.values();
  }

  // ┌─ getRegisteredMarkets ─────
  /// @notice return markets in `[start, min(end, count))` in unstable enumeration order.
  function getRegisteredMarkets(uint256 start, uint256 end) external view returns (address[] memory arr) {
    // CAF-13: keep singleton pagination behavior; see Known Issues.
    uint256 len = _markets.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _markets.at(start + i);
    }
  }

  // ┌─ getRegisteredMarketsCount ─────
  /// @notice return the current number of registered markets.
  function getRegisteredMarketsCount() external view returns (uint256) {
    return _markets.length();
  }
}
