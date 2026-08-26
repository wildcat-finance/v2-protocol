// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProvider.sol';
import '../access/IManagedRoleProvider.sol';

interface IMerkleRoleProvider is IRoleProvider, IManagedRoleProvider {
  event RootUpdated(
    address indexed administrator,
    bytes32 previousRoot,
    bytes32 newRoot
  );

  function root() external view returns (bytes32);

  function updateRoot(bytes32 newRoot) external;

  function isMember(address account, bytes32[] calldata proof) external view returns (bool);
}
