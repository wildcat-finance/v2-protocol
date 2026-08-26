// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IBorrowerIdentityRegistry } from 'src/interfaces/IBorrowerIdentityRegistry.sol';

contract BorrowerIdentityAccountMock {}

contract BorrowerIdentityAccountFactoryMock {
  IBorrowerIdentityRegistry public immutable registry;

  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  function registerAccount(address account, address principal) external {
    registry.registerBorrowerAccount(account, principal);
  }
}
