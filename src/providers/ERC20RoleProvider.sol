// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import '../libraries/SafeCastLib.sol';
import './IERC20RoleProvider.sol';
import { IERC20BalanceOf } from './TokenInterfaces.sol';

using SafeCastLib for uint256;

/// @notice grants credentials while an account holds at least `minBalance` of one ERC20.
/// @dev the immutable threshold uses token base units. deployment only checks that `token` has
///      code; the provider trusts its `balanceOf` behavior and proves no holding duration.
contract ERC20RoleProvider is IERC20RoleProvider {
  bool public constant override isPullProvider = true;

  address public immutable override token;
  uint256 public immutable override minBalance;

  /// @param token_ contract queried for balances.
  /// @param minBalance_ nonzero qualifying balance in token base units.
  constructor(address token_, uint256 minBalance_) {
    if (token_.code.length == 0) revert InvalidTokenAddress();
    if (minBalance_ == 0) revert InvalidMinimumBalance();
    token = token_;
    minBalance = minBalance_;
  }

  function getCredential(address account) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  /// @notice runs the live balance check for `account`; caller data is ignored.
  function validateCredential(
    address account,
    bytes calldata
  ) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  function _credentialTimestamp(address account) internal view returns (uint32) {
    if (IERC20BalanceOf(token).balanceOf(account) >= minBalance) {
      return block.timestamp.toUint32();
    }
    return 0;
  }
}
