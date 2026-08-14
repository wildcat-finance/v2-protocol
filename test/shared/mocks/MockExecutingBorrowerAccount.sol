// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'src/interfaces/IBorrowerIdentityRegistry.sol';

/**
 * @dev Test-only smart account. Its principal can make calls from the
 *      registered borrower address. It does not model the v2.6 Borrower
 *      Account interface or delegation rules.
 */
contract MockExecutingBorrowerAccount {
  error CallerNotPrincipal();

  IBorrowerIdentityRegistry public immutable registry;

  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  receive() external payable {}

  function principal() public view returns (address) {
    return registry.principalOf(address(this));
  }

  function execute(
    address target,
    uint256 value,
    bytes calldata data
  ) external payable returns (bytes memory result) {
    if (msg.sender != principal()) revert CallerNotPrincipal();

    bool success;
    (success, result) = target.call{ value: value }(data);
    if (!success) {
      assembly ('memory-safe') {
        revert(add(result, 0x20), mload(result))
      }
    }
  }
}

/**
 * @dev Test-only factory used to register an account against its principal
 *      through the real identity registry.
 */
contract MockExecutingBorrowerAccountFactory {
  IBorrowerIdentityRegistry public immutable registry;

  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  function deployAccount(address principal) external returns (address account) {
    account = address(new MockExecutingBorrowerAccount(address(registry)));
    registry.registerBorrowerAccount(account, principal);
  }
}
