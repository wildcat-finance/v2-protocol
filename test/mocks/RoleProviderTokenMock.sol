// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

contract RoleProviderTokenMock {
  bytes4 internal constant ERC165InterfaceId = 0x01ffc9a7;
  bytes4 internal constant ERC721InterfaceId = 0x80ac58cd;
  bytes4 internal constant ERC1155InterfaceId = 0xd9b67a26;
  bytes4 internal constant ERC5192InterfaceId = 0xb45a3c0e;
  bytes4 internal constant ERC5484InterfaceId = 0x0489b56f;
  bytes4 internal constant InvalidInterfaceId = 0xffffffff;

  uint8 internal constant SupportsERC721 = 1 << 0;
  uint8 internal constant SupportsERC1155 = 1 << 1;
  uint8 internal constant SupportsERC5192 = 1 << 2;
  uint8 internal constant SupportsERC5484 = 1 << 3;

  mapping(address account => uint256 balance) internal _balances;
  mapping(address account => mapping(uint256 tokenId => uint256 balance)) internal _idBalances;
  mapping(uint256 tokenId => address owner) internal _owners;
  mapping(uint256 tokenId => bool isLocked) internal _locked;
  mapping(uint256 tokenId => uint256 authorization) internal _burnAuth;

  uint256 internal _assetsPerShare = 1;
  uint8 internal _supportedStandards = type(uint8).max;
  bool internal _supportsERC165 = true;
  bool internal _invalidERC165;
  bool internal _revertSupportsInterface;
  bool internal _revertBalance;
  bool internal _revertConversion;
  bool internal _revertOwner;
  bool internal _revertLocked;
  bool internal _revertBurnAuth;

  function setInterfaceBehavior(
    uint8 supportedStandards,
    bool supportsERC165_,
    bool invalidERC165,
    bool revertSupportsInterface
  ) external {
    _supportedStandards = supportedStandards;
    _supportsERC165 = supportsERC165_;
    _invalidERC165 = invalidERC165;
    _revertSupportsInterface = revertSupportsInterface;
  }

  function setReadReverts(
    bool balance,
    bool conversion,
    bool owner,
    bool isLocked,
    bool authorization
  ) external {
    _revertBalance = balance;
    _revertConversion = conversion;
    _revertOwner = owner;
    _revertLocked = isLocked;
    _revertBurnAuth = authorization;
  }

  function setBalance(address account, uint256 balance) external {
    _balances[account] = balance;
  }

  function setBalance(address account, uint256 tokenId, uint256 balance) external {
    _idBalances[account][tokenId] = balance;
  }

  function setAssetsPerShare(uint256 assetsPerShare) external {
    _assetsPerShare = assetsPerShare;
  }

  function setOwner(uint256 tokenId, address owner) external {
    _owners[tokenId] = owner;
  }

  function setLocked(uint256 tokenId, bool isLocked) external {
    _locked[tokenId] = isLocked;
  }

  function setBurnAuth(uint256 tokenId, uint256 authorization) external {
    _burnAuth[tokenId] = authorization;
  }

  function balanceOf(address account) external view returns (uint256) {
    if (_revertBalance) revert('BALANCE_REVERTED');
    return _balances[account];
  }

  function balanceOf(address account, uint256 tokenId) external view returns (uint256) {
    if (_revertBalance) revert('BALANCE_REVERTED');
    return _idBalances[account][tokenId];
  }

  function convertToAssets(uint256 shares) external view returns (uint256) {
    if (_revertConversion) revert('CONVERSION_REVERTED');
    return shares * _assetsPerShare;
  }

  function ownerOf(uint256 tokenId) external view returns (address owner) {
    if (_revertOwner) revert('OWNER_REVERTED');
    owner = _owners[tokenId];
    if (owner == address(0)) revert('NOT_MINTED');
  }

  function locked(uint256 tokenId) external view returns (bool) {
    if (_revertLocked) revert('LOCKED_REVERTED');
    return _locked[tokenId];
  }

  function burnAuth(uint256 tokenId) external view returns (uint256) {
    if (_revertBurnAuth) revert('BURN_AUTH_REVERTED');
    return _burnAuth[tokenId];
  }

  function supportsInterface(bytes4 interfaceId) external view returns (bool) {
    if (_revertSupportsInterface) revert('INTERFACE_REVERTED');
    if (interfaceId == InvalidInterfaceId) return _invalidERC165;
    if (interfaceId == ERC165InterfaceId) return _supportsERC165;
    if (!_supportsERC165) return false;
    if (interfaceId == ERC721InterfaceId) {
      return _supportedStandards & SupportsERC721 != 0;
    }
    if (interfaceId == ERC1155InterfaceId) {
      return _supportedStandards & SupportsERC1155 != 0;
    }
    if (interfaceId == ERC5192InterfaceId) {
      return _supportedStandards & SupportsERC5192 != 0;
    }
    if (interfaceId == ERC5484InterfaceId) {
      return _supportedStandards & SupportsERC5484 != 0;
    }
    return false;
  }
}
