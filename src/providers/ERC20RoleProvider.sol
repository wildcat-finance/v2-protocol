// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';
import { IERC20BalanceOf } from './TokenInterfaces.sol';

/// @notice Grants credentials while an account holds at least `minBalance` of `token`.
/// @dev `minBalance` uses token base units.
contract ERC20RoleProvider is IRoleProvider {
  error InvalidTokenAddress();
  error InvalidMinimumBalance();

  address public immutable token;
  uint256 public immutable minBalance;

  constructor(address token_, uint256 minBalance_) {
    if (token_.code.length == 0) revert InvalidTokenAddress();
    if (minBalance_ == 0) revert InvalidMinimumBalance();
    token = token_;
    minBalance = minBalance_;
  }

  function isPullProvider() external pure override returns (bool) {
    return true;
  }

  function getCredential(address account) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  function validateCredential(
    address account,
    bytes calldata
  ) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  function _credentialTimestamp(address account) internal view returns (uint32) {
    if (IERC20BalanceOf(token).balanceOf(account) >= minBalance) {
      return uint32(block.timestamp);
    }
    return 0;
  }
}
