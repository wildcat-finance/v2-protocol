// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // TokenInterfaces
// ║  ██▀▀     ▀▀██   Narrow token-query surfaces used by credential providers.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  INTERFACE SUPPORT
// ║  supportsInterface(...)
// ║
// ║  ERC20 BALANCES
// ║  balanceOf(...)
// ║
// ║  VAULT ASSET VALUE
// ║  balanceOf(...)
// ║  convertToAssets(...)
// ║
// ║  COLLECTION BALANCES
// ║  balanceOf(...)
// ║
// ║  TOKEN OWNERSHIP
// ║  ownerOf(...)
// ║
// ║  TOKEN-ID BALANCES
// ║  balanceOf(...)
// ║
// ║  LOCK STATUS
// ║  locked(...)
// ║
// ║  BURN AUTHORITY
// ║  burnAuth(...)
// ╚═════

// ┌─ IERC165SupportsInterface ─────────────────────────────────────────────────
/// @dev narrow ERC165 surface used for deployment-time interface checks.
interface IERC165SupportsInterface {
  // ░░▒▒▓▓██ [ INTERFACE SUPPORT ] ────────────────────────────────────────────

  // ┌─ supportsInterface ─────
  /// @notice returns whether the target claims support for `interfaceId`.
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// ┌─ IERC20BalanceOf ──────────────────────────────────────────────────────────
/// @dev narrow ERC20 surface used by balance-based providers.
interface IERC20BalanceOf {
  // ░░▒▒▓▓██ [ ERC20 BALANCES ] ───────────────────────────────────────────────

  // ┌─ balanceOf ─────
  /// @notice returns `account`'s token balance in base units.
  function balanceOf(address account) external view returns (uint256);
}

// ┌─ IERC4626Assets ───────────────────────────────────────────────────────────
/// @dev narrow ERC4626 surface used to value an account's shares in asset units.
interface IERC4626Assets {
  // ░░▒▒▓▓██ [ VAULT ASSET VALUE ] ────────────────────────────────────────────

  // ┌─ balanceOf ─────
  /// @notice returns the number of vault shares held by `account`.
  function balanceOf(address account) external view returns (uint256);

  // ┌─ convertToAssets ─────
  /// @notice quotes the underlying asset value of `shares`.
  function convertToAssets(uint256 shares) external view returns (uint256);
}

// ┌─ IERC721BalanceOf ─────────────────────────────────────────────────────────
/// @dev narrow ERC721 balance surface used when any token in a collection qualifies.
interface IERC721BalanceOf {
  // ░░▒▒▓▓██ [ COLLECTION BALANCES ] ──────────────────────────────────────────

  // ┌─ balanceOf ─────
  /// @notice returns the number of collection tokens held by `account`.
  function balanceOf(address account) external view returns (uint256);
}

// ┌─ IERC721OwnerOf ───────────────────────────────────────────────────────────
/// @dev narrow ERC721 ownership surface used when the caller supplies a token ID.
interface IERC721OwnerOf {
  // ░░▒▒▓▓██ [ TOKEN OWNERSHIP ] ──────────────────────────────────────────────

  // ┌─ ownerOf ─────
  /// @notice returns the current owner of `tokenId`.
  function ownerOf(uint256 tokenId) external view returns (address);
}

// ┌─ IERC1155BalanceOf ────────────────────────────────────────────────────────
/// @dev narrow ERC1155 balance surface used for one configured token ID.
interface IERC1155BalanceOf {
  // ░░▒▒▓▓██ [ TOKEN-ID BALANCES ] ────────────────────────────────────────────

  // ┌─ balanceOf ─────
  /// @notice returns `account`'s balance of token `id`.
  function balanceOf(address account, uint256 id) external view returns (uint256);
}

// ┌─ IERC5192Locked ───────────────────────────────────────────────────────────
/// @dev ERC5192 lock query used after token ownership has been established.
interface IERC5192Locked {
  // ░░▒▒▓▓██ [ LOCK STATUS ] ──────────────────────────────────────────────────

  // ┌─ locked ─────
  /// @notice returns whether `tokenId` is currently locked.
  function locked(uint256 tokenId) external view returns (bool);
}

// ┌─ IERC5484BurnAuth ─────────────────────────────────────────────────────────
/// @dev ERC5484 burn-authorization query used after token ownership has been established.
interface IERC5484BurnAuth {
  // ░░▒▒▓▓██ [ BURN AUTHORITY ] ───────────────────────────────────────────────

  // ┌─ burnAuth ─────
  /// @notice returns the burn-authorization enum value for `tokenId`.
  function burnAuth(uint256 tokenId) external view returns (uint256);
}
