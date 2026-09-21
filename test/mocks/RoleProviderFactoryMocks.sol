// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { IRoleProviderFactory } from 'src/access/IRoleProviderFactory.sol';

contract RoleProviderFactoryCaller {
  function createRoleProvider(
    address factory,
    bytes calldata data
  ) external returns (address provider) {
    return IRoleProviderFactory(factory).createRoleProvider(data);
  }
}

contract FactoryBalanceTokenMock {
  mapping(address account => uint256 balance) internal _balances;
  mapping(address account => mapping(uint256 tokenId => uint256 balance)) internal _idBalances;

  function setBalance(address account, uint256 balance) external {
    _balances[account] = balance;
  }

  function setBalance(address account, uint256 tokenId, uint256 balance) external {
    _idBalances[account][tokenId] = balance;
  }

  function balanceOf(address account) external view returns (uint256) {
    return _balances[account];
  }

  function balanceOf(address account, uint256 tokenId) external view returns (uint256) {
    return _idBalances[account][tokenId];
  }

  function convertToAssets(uint256 shares) external pure returns (uint256) {
    return shares;
  }
}

contract FactoryERC165TokenMock is FactoryBalanceTokenMock {
  bytes4 internal immutable _supportedInterface;

  constructor(bytes4 supportedInterface) {
    _supportedInterface = supportedInterface;
  }

  function supportsInterface(bytes4 interfaceId) external view returns (bool) {
    return interfaceId == 0x01ffc9a7 || interfaceId == _supportedInterface;
  }
}
