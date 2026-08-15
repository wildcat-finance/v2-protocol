// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../libraries/SafeCastLib.sol';
import './ISingletonRoleProvider.sol';

using SafeCastLib for uint256;

/// @notice Pull-based role provider for exactly one immutable lender.
/// @dev The contract has no administrator or membership mutation path.
contract SingletonRoleProvider is ISingletonRoleProvider {
  error InvalidLender();

  bool public constant override isPullProvider = true;
  address public immutable override lender;

  constructor(address lender_) {
    if (lender_ == address(0)) revert InvalidLender();
    lender = lender_;
  }

  function getCredential(address account) external view override returns (uint32 timestamp) {
    return _credentialFor(account);
  }

  function validateCredential(
    address account,
    bytes calldata
  ) external view override returns (uint32 timestamp) {
    return _credentialFor(account);
  }

  function _credentialFor(address account) internal view returns (uint32 timestamp) {
    if (account != lender) return 0;
    return block.timestamp.toUint32();
  }
}
