// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC165SupportsInterface {
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC20BalanceOf {
  function balanceOf(address account) external view returns (uint256);
}

interface IERC4626Assets {
  function balanceOf(address account) external view returns (uint256);

  function convertToAssets(uint256 shares) external view returns (uint256);
}

interface IERC721BalanceOf {
  function balanceOf(address account) external view returns (uint256);
}

interface IERC721OwnerOf {
  function ownerOf(uint256 tokenId) external view returns (address);
}

interface IERC1155BalanceOf {
  function balanceOf(address account, uint256 id) external view returns (uint256);
}

interface IERC5192Locked {
  function locked(uint256 tokenId) external view returns (bool);
}

interface IERC5484BurnAuth {
  function burnAuth(uint256 tokenId) external view returns (uint256);
}
