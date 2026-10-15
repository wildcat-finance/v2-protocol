// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // IHooksFactoryRevolving
//  \ ^ /   Revolving factory registration, hooks lifecycle, and deployment.
//    V
//
//  MARKET DEPLOYMENT
//  deployMarket(...)
//  deployMarketAndHooks(...)
//  getRevolvingMarketCommitmentFeeBips()
// ═════

import './IHooksFactory.sol';
import './interfaces/WildcatStructsAndEnums.sol';

// ┌─ IHooksFactoryRevolving ───────────────────────────────────────────────────
/// @title Wildcat revolving hooks factory
///
/// @notice standard hooks-template and instance registry with revolving-market deployment data.
///
/// @dev `marketData` belongs to the factory, not the hooks instance. the current encoding is
///      `abi.encode(uint8(1), uint16 commitmentFeeBips)`.
interface IHooksFactoryRevolving is IHooksFactoryBase {
  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev `marketData` does not have the expected static encoding length.
  error InvalidMarketData();

  /// @dev `marketData` uses a version this factory does not understand.
  error UnsupportedMarketDataVersion();

  /// @dev the commitment fee exceeds 10,000 bips.
  error InvalidCommitmentFeeBips();

  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  /// @notice emitted with the fixed commitment fee captured by a new revolving market.
  event RevolvingMarketDeployed(address indexed market, uint256 commitmentFeeBips);

  // ░░▒▒▓▓██ [ MARKET DEPLOYMENT ] ────────────────────────────────────────────

  // ┌─ deployMarket ─────
  /// @notice deploy a revolving market using the existing instance in `parameters.hooks`.
  ///
  /// @dev the caller becomes the operational borrower. its resolved principal is passed to the
  ///      hooks and market, fee arguments must match the template, and `salt` binds to the caller.
  ///
  /// @param hooksData  opaque data forwarded to the hooks instance.
  /// @param marketData `abi.encode(uint8 version, uint16 commitmentFeeBips)`; current version is 1.
  function deployMarket(
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes calldata marketData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  )
    external
    returns (address market);

  // ┌─ deployMarketAndHooks ─────
  /// @notice deploy a principal-administered hooks instance and a revolving market using it.
  ///
  /// @dev both deployments are atomic. `marketData` uses the same encoding as `deployMarket`.
  function deployMarketAndHooks(
    address hooksTemplate,
    bytes calldata hooksConstructorArgs,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes calldata marketData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  )
    external
    returns (address market, address hooks);

  // ┌─ getRevolvingMarketCommitmentFeeBips ─────
  /// @notice commitment fee for the revolving market currently being constructed.
  ///
  /// @dev only valid during market deployment; it reverts after transient state is cleared.
  function getRevolvingMarketCommitmentFeeBips() external view returns (uint16);
}
