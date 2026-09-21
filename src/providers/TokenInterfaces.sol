// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @dev narrow ERC165 surface used for deployment-time interface checks.
interface IERC165SupportsInterface {
  /// @notice returns whether the target claims support for `interfaceId`.
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @dev narrow ERC20 surface used by balance-based providers.
interface IERC20BalanceOf {
  /// @notice returns `account`'s token balance in base units.
  function balanceOf(address account) external view returns (uint256);
}

/// @dev narrow ERC4626 surface used to value an account's shares in asset units.
interface IERC4626Assets {
  /// @notice returns the number of vault shares held by `account`.
  function balanceOf(address account) external view returns (uint256);

  /// @notice quotes the underlying asset value of `shares`.
  function convertToAssets(uint256 shares) external view returns (uint256);
}

/// @dev narrow ERC721 balance surface used when any token in a collection qualifies.
interface IERC721BalanceOf {
  /// @notice returns the number of collection tokens held by `account`.
  function balanceOf(address account) external view returns (uint256);
}

/// @dev narrow ERC721 ownership surface used when the caller supplies a token ID.
interface IERC721OwnerOf {
  /// @notice returns the current owner of `tokenId`.
  function ownerOf(uint256 tokenId) external view returns (address);
}

/// @dev narrow ERC1155 balance surface used for one configured token ID.
interface IERC1155BalanceOf {
  /// @notice returns `account`'s balance of token `id`.
  function balanceOf(address account, uint256 id) external view returns (uint256);
}

/// @dev ERC5192 lock query used after token ownership has been established.
interface IERC5192Locked {
  /// @notice returns whether `tokenId` is currently locked.
  function locked(uint256 tokenId) external view returns (bool);
}

/// @dev ERC5484 burn-authorization query used after token ownership has been established.
interface IERC5484BurnAuth {
  /// @notice returns the burn-authorization enum value for `tokenId`.
  function burnAuth(uint256 tokenId) external view returns (uint256);
}
