// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // IWildcatArchController
// ║  ██▀▀     ▀▀██   Protocol authorization registries and SphereX configuration.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  AUTHORITY
// ║  owner()
// ║
// ║  SPHEREX CONFIGURATION
// ║  transferSphereXAdminRole(...)
// ║  acceptSphereXAdminRole()
// ║  sphereXAdmin()
// ║  pendingSphereXAdmin()
// ║  changeSphereXOperator(...)
// ║  sphereXOperator()
// ║  changeSphereXEngine(...)
// ║  sphereXEngine()
// ║
// ║  BORROWERS
// ║  registerBorrower(...)
// ║  removeBorrower(...)
// ║  isRegisteredBorrower(...)
// ║  getRegisteredBorrowers()
// ║  getRegisteredBorrowers(...)
// ║  getRegisteredBorrowersCount()
// ║
// ║  ASSET BLACKLIST
// ║  addBlacklist(...)
// ║  removeBlacklist(...)
// ║  isBlacklistedAsset(...)
// ║  getBlacklistedAssets()
// ║  getBlacklistedAssets(...)
// ║  getBlacklistedAssetsCount()
// ║
// ║  CONTROLLER FACTORIES
// ║  registerControllerFactory(...)
// ║  removeControllerFactory(...)
// ║  isRegisteredControllerFactory(...)
// ║  getRegisteredControllerFactories()
// ║  getRegisteredControllerFactories(...)
// ║  getRegisteredControllerFactoriesCount()
// ║
// ║  CONTROLLERS
// ║  registerController(...)
// ║  removeController(...)
// ║  isRegisteredController(...)
// ║  getRegisteredControllers()
// ║  getRegisteredControllers(...)
// ║  getRegisteredControllersCount()
// ║
// ║  MARKETS
// ║  registerMarket(...)
// ║  removeMarket(...)
// ║  isRegisteredMarket(...)
// ║  getRegisteredMarkets()
// ║  getRegisteredMarkets(...)
// ║  getRegisteredMarketsCount()
// ╚═════

// ┌─ IWildcatArchController ───────────────────────────────────────────────────
/// @title Wildcat architecture controller
///
/// @notice registry and permission root for borrowers, factories, controllers, markets, and assets.
///
/// @dev the registries record protocol authorization, not bytecode provenance. removing a parent
///      does not recursively remove contracts it registered.
interface IWildcatArchController {
  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev the caller is not a registered market factory.
  error NotMarketFactory();

  /// @dev the caller is not a registered controller factory.
  error NotControllerFactory();

  // ░░▒▒▓▓██ [ SPHEREX EVENTS ] ───────────────────────────────────────────────

  /// @notice emitted when the SphereX operator changes.
  event ChangedSpherexOperator(address oldSphereXAdmin, address newSphereXAdmin);

  /// @notice emitted when the active SphereX engine changes.
  event ChangedSpherexEngineAddress(address oldEngineAddress, address newEngineAddress);

  /// @notice emitted when the admin starts or replaces a two-step transfer.
  event SpherexAdminTransferStarted(address currentAdmin, address pendingAdmin);

  /// @notice emitted when the pending admin accepts authority.
  event SpherexAdminTransferCompleted(address oldAdmin, address newAdmin);

  /// @notice emitted when the controller allows a sender on the active engine.
  event NewAllowedSenderOnchain(address sender);

  // ░░▒▒▓▓██ [ SPHEREX ERRORS ] ───────────────────────────────────────────────

  /// @dev the caller is not the SphereX operator.
  error SphereXOperatorRequired();

  /// @dev the caller is not the SphereX admin.
  error SphereXAdminRequired();

  /// @dev the caller is neither the SphereX operator nor admin.
  error SphereXOperatorOrAdminRequired();

  /// @dev the caller is not the pending SphereX admin.
  error SphereXNotPendingAdmin();

  /// @dev the proposed engine does not support the SphereX engine interface.
  error SphereXNotEngine();

  // ░░▒▒▓▓██ [ REGISTRY EVENTS ] ──────────────────────────────────────────────

  /// @notice emitted when the protocol owner adds a controller factory.
  event ControllerFactoryAdded(address);

  /// @notice emitted when the protocol owner removes a controller factory.
  event ControllerFactoryRemoved(address);

  /// @notice emitted when a registered factory adds a controller.
  event ControllerAdded(address, address);

  /// @notice emitted when the protocol owner removes a controller.
  event ControllerRemoved(address);

  /// @notice emitted when the protocol owner registers a borrower principal.
  event BorrowerAdded(address);

  /// @notice emitted when the protocol owner removes a borrower principal.
  event BorrowerRemoved(address);

  /// @notice emitted when the protocol owner removes an asset from the blacklist.
  event AssetPermitted();

  /// @notice emitted when the protocol owner blacklists an asset.
  event AssetBlacklisted();

  /// @notice emitted when a registered controller adds a market.
  event MarketAdded(address, address);

  /// @notice emitted when the protocol owner removes a market.
  event MarketRemoved(address);

  // ░░▒▒▓▓██ [ AUTHORITY ] ────────────────────────────────────────────────────

  // ┌─ owner ─────
  /// @notice protocol owner allowed to manage registries and asset policy.
  function owner() external view returns (address);

  // ░░▒▒▓▓██ [ SPHEREX CONFIGURATION ] ────────────────────────────────────────

  // ┌─ transferSphereXAdminRole ─────
  /// @notice starts a two-step SphereX admin transfer.
  ///
  /// @dev only the current SphereX admin can call this.
  function transferSphereXAdminRole(address newAdmin) external virtual;

  // ┌─ acceptSphereXAdminRole ─────
  /// @notice accepts the pending SphereX admin transfer.
  function acceptSphereXAdminRole() external virtual;

  // ┌─ sphereXAdmin ─────
  /// @notice current SphereX admin.
  function sphereXAdmin() external view returns (address);

  // ┌─ pendingSphereXAdmin ─────
  /// @notice address allowed to accept the pending SphereX admin transfer.
  function pendingSphereXAdmin() external view returns (address);

  // ┌─ changeSphereXOperator ─────
  /// @notice replaces the SphereX operator.
  ///
  /// @dev only the SphereX admin can call this.
  function changeSphereXOperator(address newSphereXOperator) external;

  // ┌─ sphereXOperator ─────
  /// @notice current SphereX operator.
  function sphereXOperator() external view returns (address);

  // ┌─ changeSphereXEngine ─────
  /// @notice replaces the SphereX engine, or disables protection when set to zero.
  ///
  /// @dev only the SphereX operator can call this. nonzero engines must support `ISphereXEngine`.
  function changeSphereXEngine(address newSphereXEngine) external;

  // ┌─ sphereXEngine ─────
  /// @notice active SphereX engine, or zero when protection is disabled.
  function sphereXEngine() external view returns (address);

  // ░░▒▒▓▓██ [ BORROWERS ] ────────────────────────────────────────────────────

  // ┌─ registerBorrower ─────
  /// @notice approves a borrower principal.
  ///
  /// @dev only the protocol owner can call this.
  function registerBorrower(address borrower) external;

  // ┌─ removeBorrower ─────
  /// @notice removes a borrower principal from the registry.
  ///
  /// @dev only the protocol owner can call this. existing markets are not changed.
  function removeBorrower(address borrower) external;

  // ┌─ isRegisteredBorrower ─────
  /// @notice says whether `borrower` is a currently registered principal.
  function isRegisteredBorrower(address borrower) external view returns (bool);

  // ┌─ getRegisteredBorrowers ─────
  /// @notice returns every registered borrower in unstable enumeration order.
  function getRegisteredBorrowers() external view returns (address[] memory);

  // ┌─ getRegisteredBorrowers ─────
  /// @notice returns borrowers in `[start, min(end, count))`.
  ///
  /// @dev retained singleton behavior panics when `start` exceeds the clamped end.
  function getRegisteredBorrowers(uint256 start, uint256 end) external view returns (address[] memory);

  // ┌─ getRegisteredBorrowersCount ─────
  /// @notice returns the current number of registered borrowers.
  function getRegisteredBorrowersCount() external view returns (uint256);

  // ░░▒▒▓▓██ [ ASSET BLACKLIST ] ──────────────────────────────────────────────

  // ┌─ addBlacklist ─────
  /// @notice blocks `asset` from use by factories that consult this registry.
  ///
  /// @dev only the protocol owner can call this. existing markets are not changed.
  function addBlacklist(address asset) external;

  // ┌─ removeBlacklist ─────
  /// @notice removes `asset` from the blacklist.
  ///
  /// @dev only the protocol owner can call this.
  function removeBlacklist(address asset) external;

  // ┌─ isBlacklistedAsset ─────
  /// @notice says whether `asset` is currently blacklisted.
  function isBlacklistedAsset(address asset) external view returns (bool);

  // ┌─ getBlacklistedAssets ─────
  /// @notice returns every blacklisted asset in unstable enumeration order.
  function getBlacklistedAssets() external view returns (address[] memory);

  // ┌─ getBlacklistedAssets ─────
  /// @notice returns blacklisted assets in `[start, min(end, count))`.
  ///
  /// @dev retained singleton behavior panics when `start` exceeds the clamped end.
  function getBlacklistedAssets(uint256 start, uint256 end) external view returns (address[] memory);

  // ┌─ getBlacklistedAssetsCount ─────
  /// @notice returns the current number of blacklisted assets.
  function getBlacklistedAssetsCount() external view returns (uint256);

  // ░░▒▒▓▓██ [ CONTROLLER FACTORIES ] ─────────────────────────────────────────

  // ┌─ registerControllerFactory ─────
  /// @notice adds a controller factory to the registry.
  ///
  /// @dev only the protocol owner can call this.
  function registerControllerFactory(address factory) external;

  // ┌─ removeControllerFactory ─────
  /// @notice removes a controller factory without changing controllers it already registered.
  ///
  /// @dev only the protocol owner can call this.
  function removeControllerFactory(address factory) external;

  // ┌─ isRegisteredControllerFactory ─────
  /// @notice says whether `factory` is currently registered.
  function isRegisteredControllerFactory(address factory) external view returns (bool);

  // ┌─ getRegisteredControllerFactories ─────
  /// @notice returns every controller factory in unstable enumeration order.
  function getRegisteredControllerFactories() external view returns (address[] memory);

  // ┌─ getRegisteredControllerFactories ─────
  /// @notice returns controller factories in `[start, min(end, count))`.
  ///
  /// @dev retained singleton behavior panics when `start` exceeds the clamped end.
  function getRegisteredControllerFactories(uint256 start, uint256 end) external view returns (address[] memory);

  // ┌─ getRegisteredControllerFactoriesCount ─────
  /// @notice returns the current number of registered controller factories.
  function getRegisteredControllerFactoriesCount() external view returns (uint256);

  // ░░▒▒▓▓██ [ CONTROLLERS ] ──────────────────────────────────────────────────

  // ┌─ registerController ─────
  /// @notice adds a controller to the registry.
  ///
  /// @dev only a registered controller factory can call this.
  function registerController(address controller) external;

  // ┌─ removeController ─────
  /// @notice removes a controller without changing markets it already registered.
  ///
  /// @dev only the protocol owner can call this.
  function removeController(address controller) external;

  // ┌─ isRegisteredController ─────
  /// @notice says whether `controller` is currently registered.
  function isRegisteredController(address controller) external view returns (bool);

  // ┌─ getRegisteredControllers ─────
  /// @notice returns every controller in unstable enumeration order.
  function getRegisteredControllers() external view returns (address[] memory);

  // ┌─ getRegisteredControllers ─────
  /// @notice returns controllers in `[start, min(end, count))`.
  ///
  /// @dev retained singleton behavior panics when `start` exceeds the clamped end.
  function getRegisteredControllers(uint256 start, uint256 end) external view returns (address[] memory);

  // ┌─ getRegisteredControllersCount ─────
  /// @notice returns the current number of registered controllers.
  function getRegisteredControllersCount() external view returns (uint256);

  // ░░▒▒▓▓██ [ MARKETS ] ──────────────────────────────────────────────────────

  // ┌─ registerMarket ─────
  /// @notice adds a market to the registry.
  ///
  /// @dev only a registered controller can call this.
  function registerMarket(address market) external;

  // ┌─ removeMarket ─────
  /// @notice removes a market from the registry without changing the market contract.
  ///
  /// @dev only the protocol owner can call this.
  function removeMarket(address market) external;

  // ┌─ isRegisteredMarket ─────
  /// @notice says whether `market` is currently registered.
  function isRegisteredMarket(address market) external view returns (bool);

  // ┌─ getRegisteredMarkets ─────
  /// @notice returns every registered market in unstable enumeration order.
  function getRegisteredMarkets() external view returns (address[] memory);

  // ┌─ getRegisteredMarkets ─────
  /// @notice returns markets in `[start, min(end, count))`.
  ///
  /// @dev retained singleton behavior panics when `start` exceeds the clamped end.
  function getRegisteredMarkets(uint256 start, uint256 end) external view returns (address[] memory);

  // ┌─ getRegisteredMarketsCount ─────
  /// @notice returns the current number of registered markets.
  function getRegisteredMarketsCount() external view returns (uint256);
}
