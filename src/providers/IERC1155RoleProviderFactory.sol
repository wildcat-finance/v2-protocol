// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // IERC1155RoleProviderFactory
// ║  ██▀▀     ▀▀██   ERC1155 provider deployment inputs and address prediction.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  DEPLOYMENT
// ║  createERC1155RoleProvider(...)
// ║
// ║  ADDRESS PREDICTION
// ║  computeRoleProviderAddress(...)
// ╚═════

import '../access/IRoleProviderFactory.sol';

/// @notice constructor and CREATE2 inputs for an ERC1155 balance provider.
///
/// @param token              collection queried for balances.
/// @param tokenId            only token ID that qualifies.
/// @param skipInterfaceCheck skips ERC165 and ERC1155 checks, not later `balanceOf` failures.
/// @param salt               caller-scoped salt used by the factory.
struct ERC1155RoleProviderFactoryInputs {
  address token;
  uint256 tokenId;
  bool skipInterfaceCheck;
  bytes32 salt;
}

// ┌─ IERC1155RoleProviderFactory ──────────────────────────────────────────────
/// @notice deterministic factory for immutable ERC1155 balance providers.
///
/// @dev salts are namespaced by the factory caller. the factory retains no authority over the
///      provider after deployment.
interface IERC1155RoleProviderFactory is IRoleProviderFactory {
  /// @dev a provider already has code at the derived CREATE2 address.
  error RoleProviderAlreadyExists();

  /// @notice emitted when the factory deploys an ERC1155 balance provider.
  event ERC1155RoleProviderDeployed(
    address indexed provider,
    address indexed token,
    address indexed deployer,
    bytes32 salt,
    uint256 tokenId,
    bool skipInterfaceCheck
  );

  // ░░▒▒▓▓██ [ DEPLOYMENT ] ───────────────────────────────────────────────────

  // ┌─ createERC1155RoleProvider ─────
  /// @notice deploys a provider for `msg.sender`.
  function createERC1155RoleProvider(ERC1155RoleProviderFactoryInputs calldata inputs)
    external
    returns (address provider);

  // ░░▒▒▓▓██ [ ADDRESS PREDICTION ] ───────────────────────────────────────────

  // ┌─ computeRoleProviderAddress ─────
  /// @notice predicts the address for the exact `deployer`, inputs, and this factory.
  ///
  /// @dev pass the address that will actually call the create function as `deployer`.
  function computeRoleProviderAddress(
    address deployer,
    ERC1155RoleProviderFactoryInputs calldata inputs
  )
    external
    view
    returns (address provider);
}
