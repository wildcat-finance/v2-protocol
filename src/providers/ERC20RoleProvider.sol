// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';
import 'src/interfaces/IERC20.sol';

/// @notice ERC20 role provider; gates on balance >= minBalance.
/// @dev minBalance is in token base units.
contract ERC20RoleProvider is IRoleProvider {
  error InvalidTokenAddress();

  address public immutable token;
  uint256 public immutable minBalance;

  constructor(address _token, uint256 _minBalance) {
    if (_token.code.length == 0) revert InvalidTokenAddress();
    token = _token;
    minBalance = _minBalance;
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
    if (IERC20(token).balanceOf(account) >= minBalance) {
      return uint32(block.timestamp);
    }
    return 0;
  }
}
