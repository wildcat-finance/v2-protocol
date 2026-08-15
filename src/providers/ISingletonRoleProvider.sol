// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../access/IRoleProvider.sol';

interface ISingletonRoleProvider is IRoleProvider {
  function lender() external view returns (address);
}
