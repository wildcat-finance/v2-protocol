// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import { EnumerableSet } from 'openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import 'solady/auth/Ownable.sol';
import './spherex/SphereXConfig.sol';
import './libraries/MathUtils.sol';
import './interfaces/ISphereXProtectedRegisteredBase.sol';

/// @title Wildcat architecture controller
/// @notice owns the protocol registries and coordinates SphereX configuration across them.
/// @dev registry membership is an authorization decision. this singleton does not validate the
///      bytecode or reported parent of every address it registers, so operators still have to.
contract WildcatArchController is SphereXConfig, Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  // ========================================================================== //
  //                                   Storage                                  //
  // ========================================================================== //

  EnumerableSet.AddressSet internal _markets;
  EnumerableSet.AddressSet internal _controllerFactories;
  EnumerableSet.AddressSet internal _borrowers;
  EnumerableSet.AddressSet internal _controllers;
  EnumerableSet.AddressSet internal _assetBlacklist;

  // ========================================================================== //
  //                              Events and Errors                             //
  // ========================================================================== //

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

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  constructor() SphereXConfig(msg.sender, address(0), address(0)) {
    _initializeOwner(msg.sender);
  }

  // ========================================================================== //
  //                            SphereX Engine Update                           //
  // ========================================================================== //

  /// @notice pushes the current SphereX engine to selected registered contracts.
  /// @dev only the SphereX operator or admin can call this. it also allows each selected contract
  ///      on the nonzero engine. every address must still be present in the matching registry, and
  ///      one failed update reverts the whole batch.
  function updateSphereXEngineOnRegisteredContracts(
    address[] calldata controllerFactories,
    address[] calldata controllers,
    address[] calldata markets
  ) external spherexOnlyOperatorOrAdmin {
    address engineAddress = sphereXEngine();
    bytes memory changeSphereXEngineCalldata = abi.encodeWithSelector(
      ISphereXProtectedRegisteredBase.changeSphereXEngine.selector,
      engineAddress
    );
    bytes memory addAllowedSenderOnChainCalldata;
    if (engineAddress != address(0)) {
      addAllowedSenderOnChainCalldata = abi.encodeWithSelector(
        ISphereXEngine.addAllowedSenderOnChain.selector,
        address(0)
      );
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

  function _updateSphereXEngineOnRegisteredContractsInSet(
    EnumerableSet.AddressSet storage set,
    address engineAddress,
    address[] memory contracts,
    bytes memory changeSphereXEngineCalldata,
    bytes memory addAllowedSenderOnChainCalldata,
    bytes4 notInSetErrorSelectorBytes
  ) internal {
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

  function _callWith(address target, bytes memory data) internal {
    assembly {
      if iszero(call(gas(), target, 0, add(data, 0x20), mload(data), 0, 0)) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
  }

  /* ========================================================================== */
  /*                                  Borrowers                                 */
  /* ========================================================================== */

  /// @dev Owner-only borrower registration. Reverts if already registered.
  function registerBorrower(address borrower) external onlyOwner {
    if (!_borrowers.add(borrower)) {
      revert BorrowerAlreadyExists();
    }
    emit BorrowerAdded(borrower);
  }

  /// @dev Owner-only borrower removal. Reverts if not registered.
  function removeBorrower(address borrower) external onlyOwner {
    if (!_borrowers.remove(borrower)) {
      revert BorrowerDoesNotExist();
    }
    emit BorrowerRemoved(borrower);
  }

  /// @notice says whether `borrower` is a currently registered principal.
  function isRegisteredBorrower(address borrower) external view returns (bool) {
    return _borrowers.contains(borrower);
  }

  /// @notice returns every registered borrower in unstable enumeration order.
  function getRegisteredBorrowers() external view returns (address[] memory) {
    return _borrowers.values();
  }

  /// @notice returns borrowers in `[start, min(end, count))` in unstable enumeration order.
  function getRegisteredBorrowers(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr) {
    // CAF-13 known issue: malformed ranges can panic after `end` is clamped.
    // The singleton keeps deployed behavior; new registries should reject
    // `start >= end` explicitly before subtracting.
    uint256 len = _borrowers.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _borrowers.at(start + i);
    }
  }

  /// @notice returns the current number of registered borrowers.
  function getRegisteredBorrowersCount() external view returns (uint256) {
    return _borrowers.length();
  }

  // ========================================================================== //
  //                          Asset Blacklist Registry                          //
  // ========================================================================== //

  /// @dev Owner-only asset blacklist insertion. Reverts if already blacklisted.
  function addBlacklist(address asset) external onlyOwner {
    if (!_assetBlacklist.add(asset)) {
      revert AssetAlreadyBlacklisted();
    }
    emit AssetBlacklisted(asset);
  }

  /// @dev Owner-only asset blacklist removal. Reverts if not blacklisted.
  function removeBlacklist(address asset) external onlyOwner {
    if (!_assetBlacklist.remove(asset)) {
      revert AssetNotBlacklisted();
    }
    emit AssetPermitted(asset);
  }

  /// @notice says whether `asset` is currently blacklisted.
  function isBlacklistedAsset(address asset) external view returns (bool) {
    return _assetBlacklist.contains(asset);
  }

  /// @notice returns every blacklisted asset in unstable enumeration order.
  function getBlacklistedAssets() external view returns (address[] memory) {
    return _assetBlacklist.values();
  }

  /// @notice returns assets in `[start, min(end, count))` in unstable enumeration order.
  function getBlacklistedAssets(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr) {
    // CAF-13: keep singleton pagination behavior; see Known Issues.
    uint256 len = _assetBlacklist.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _assetBlacklist.at(start + i);
    }
  }

  /// @notice returns the current number of blacklisted assets.
  function getBlacklistedAssetsCount() external view returns (uint256) {
    return _assetBlacklist.length();
  }

  /* ========================================================================== */
  /*                            Controller Factories                            */
  /* ========================================================================== */

  /// @dev Owner-only controller factory registration. Reverts if already registered.
  function registerControllerFactory(address factory) external onlyOwner {
    // CAF-16 known issue: the singleton does not validate that `factory` is a
    // contract or reports this ArchController. Operators must validate before
    // registration; new registry bytecode should enforce it.
    if (!_controllerFactories.add(factory)) {
      revert ControllerFactoryAlreadyExists();
    }
    _addAllowedSenderOnChain(factory);
    emit ControllerFactoryAdded(factory);
  }

  /// @dev Owner-only controller factory removal. Reverts if not registered.
  function removeControllerFactory(address factory) external onlyOwner {
    if (!_controllerFactories.remove(factory)) {
      revert ControllerFactoryDoesNotExist();
    }
    emit ControllerFactoryRemoved(factory);
  }

  /// @notice says whether `factory` is currently registered.
  function isRegisteredControllerFactory(address factory) external view returns (bool) {
    return _controllerFactories.contains(factory);
  }

  /// @notice returns every controller factory in unstable enumeration order.
  function getRegisteredControllerFactories() external view returns (address[] memory) {
    return _controllerFactories.values();
  }

  /// @notice returns factories in `[start, min(end, count))` in unstable enumeration order.
  function getRegisteredControllerFactories(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr) {
    // CAF-13: keep singleton pagination behavior; see Known Issues.
    uint256 len = _controllerFactories.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _controllerFactories.at(start + i);
    }
  }

  /// @notice returns the current number of registered controller factories.
  function getRegisteredControllerFactoriesCount() external view returns (uint256) {
    return _controllerFactories.length();
  }

  /* ========================================================================== */
  /*                                 Controllers                                */
  /* ========================================================================== */

  modifier onlyControllerFactory() {
    if (!_controllerFactories.contains(msg.sender)) {
      revert NotControllerFactory();
    }
    _;
  }

  /// @dev Registered-factory-only controller registration. Reverts if already registered.
  function registerController(address controller) external onlyControllerFactory {
    // CAF-16: registered controller addresses are trusted privileged input on
    // the singleton. Validate offchain before registration.
    if (!_controllers.add(controller)) {
      revert ControllerAlreadyExists();
    }
    _addAllowedSenderOnChain(controller);
    emit ControllerAdded(msg.sender, controller);
  }

  /// @dev Owner-only controller removal. Reverts if not registered.
  function removeController(address controller) external onlyOwner {
    if (!_controllers.remove(controller)) {
      revert ControllerDoesNotExist();
    }
    emit ControllerRemoved(controller);
  }

  /// @notice says whether `controller` is currently registered.
  function isRegisteredController(address controller) external view returns (bool) {
    return _controllers.contains(controller);
  }

  /// @notice returns every controller in unstable enumeration order.
  function getRegisteredControllers() external view returns (address[] memory) {
    return _controllers.values();
  }

  /// @notice returns controllers in `[start, min(end, count))` in unstable enumeration order.
  function getRegisteredControllers(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr) {
    // CAF-13: keep singleton pagination behavior; see Known Issues.
    uint256 len = _controllers.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _controllers.at(start + i);
    }
  }

  /// @notice returns the current number of registered controllers.
  function getRegisteredControllersCount() external view returns (uint256) {
    return _controllers.length();
  }

  /* ========================================================================== */
  /*                                   Markets                                   */
  /* ========================================================================== */

  modifier onlyController() {
    if (!_controllers.contains(msg.sender)) {
      revert NotController();
    }
    _;
  }

  /// @dev Registered-controller-only market registration. Reverts if already registered.
  function registerMarket(address market) external onlyController {
    // CAF-16: the singleton does not validate market code, archController(),
    // or factory(). Controllers must only register conforming markets.
    if (!_markets.add(market)) {
      revert MarketAlreadyExists();
    }
    _addAllowedSenderOnChain(market);
    emit MarketAdded(msg.sender, market);
  }

  /// @dev Owner-only market removal. Reverts if not registered.
  function removeMarket(address market) external onlyOwner {
    if (!_markets.remove(market)) {
      revert MarketDoesNotExist();
    }
    emit MarketRemoved(market);
  }

  /// @notice says whether `market` is currently registered.
  function isRegisteredMarket(address market) external view returns (bool) {
    return _markets.contains(market);
  }

  /// @notice returns every registered market in unstable enumeration order.
  function getRegisteredMarkets() external view returns (address[] memory) {
    return _markets.values();
  }

  /// @notice returns markets in `[start, min(end, count))` in unstable enumeration order.
  function getRegisteredMarkets(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr) {
    // CAF-13: keep singleton pagination behavior; see Known Issues.
    uint256 len = _markets.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _markets.at(start + i);
    }
  }

  /// @notice returns the current number of registered markets.
  function getRegisteredMarketsCount() external view returns (uint256) {
    return _markets.length();
  }
}
