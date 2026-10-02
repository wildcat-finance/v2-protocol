// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // RoleProviderFactoryMocks
//  \ ^ /   Factory callers and token capability test doubles.
//    V
//
//  FACTORY CALLS
//  createRoleProvider(...)
//
//  TOKEN BALANCES
//  setBalance(...)
//  setBalance(...)
//  balanceOf(...)
//  balanceOf(...)
//  convertToAssets(...)
//
//  TOKEN CAPABILITIES
//  constructor(...)
//  supportsInterface(...)
// ═════

import { IRoleProviderFactory } from 'src/access/IRoleProviderFactory.sol';

// ┌─ RoleProviderFactoryCaller ────────────────────────────────────────────────
contract RoleProviderFactoryCaller {
  // ░░▒▒▓▓██ [ FACTORY CALLS ] ────────────────────────────────────────────────

  // ┌─ createRoleProvider ─────
  function createRoleProvider(address factory, bytes calldata data) external returns (address provider) {
    return IRoleProviderFactory(factory).createRoleProvider(data);
  }
}

// ┌─ FactoryBalanceTokenMock ──────────────────────────────────────────────────
contract FactoryBalanceTokenMock {
  mapping(address account => uint256 balance) internal _balances;
  mapping(address account => mapping(uint256 tokenId => uint256 balance)) internal _idBalances;

  // ░░▒▒▓▓██ [ TOKEN BALANCES ] ───────────────────────────────────────────────

  // ┌─ setBalance ─────
  function setBalance(address account, uint256 balance) external {
    _balances[account] = balance;
  }

  // ┌─ setBalance ─────
  function setBalance(address account, uint256 tokenId, uint256 balance) external {
    _idBalances[account][tokenId] = balance;
  }

  // ┌─ balanceOf ─────
  function balanceOf(address account) external view returns (uint256) {
    return _balances[account];
  }

  // ┌─ balanceOf ─────
  function balanceOf(address account, uint256 tokenId) external view returns (uint256) {
    return _idBalances[account][tokenId];
  }

  // ┌─ convertToAssets ─────
  function convertToAssets(uint256 shares) external pure returns (uint256) {
    return shares;
  }
}

// ┌─ FactoryERC165TokenMock ───────────────────────────────────────────────────
contract FactoryERC165TokenMock is FactoryBalanceTokenMock {
  bytes4 internal immutable _supportedInterface;

  // ░░▒▒▓▓██ [ TOKEN CAPABILITIES ] ───────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(bytes4 supportedInterface) {
    _supportedInterface = supportedInterface;
  }

  // ┌─ supportsInterface ─────
  function supportsInterface(bytes4 interfaceId) external view returns (bool) {
    return interfaceId == 0x01ffc9a7 || interfaceId == _supportedInterface;
  }
}
