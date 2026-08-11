// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBorrowerIdentityRegistry {
  error CallerNotArchControllerOwner();
  error CallerNotAccountFactory();
  error InvalidArchController();
  error InvalidAccountFactory();
  error AccountFactoryAlreadyExists();
  error AccountFactoryDoesNotExist();
  error InvalidBorrowerAccount();
  error BorrowerAccountAlreadyRegistered();
  error BorrowerPrincipalNotRegistered();
  error BorrowerIdentityNotFound();
  error AmbiguousBorrowerIdentity();
  error InvalidPaginationRange();

  event AccountFactoryAdded(address indexed accountFactory);
  event AccountFactoryRemoved(address indexed accountFactory);
  event BorrowerAccountRegistered(
    address indexed account,
    address indexed principal,
    address indexed accountFactory
  );

  function archController() external view returns (address);

  /// @notice Permanent principal associated with `account`, or zero if it is unknown.
  function principalOf(address account) external view returns (address);

  /// @notice Factory that registered `account`, or zero if it is unknown.
  function accountFactoryOf(address account) external view returns (address);

  /// @notice Resolves a direct principal or borrower account using current ArchController state.
  function resolveBorrower(address borrower) external view returns (address principal);

  function addAccountFactory(address accountFactory) external;

  function removeAccountFactory(address accountFactory) external;

  function isAccountFactory(address accountFactory) external view returns (bool);

  function getAccountFactories() external view returns (address[] memory);

  function getAccountFactories(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory);

  function getAccountFactoriesCount() external view returns (uint256);

  /// @notice Permanently associates a deployed borrower account with a registered principal.
  function registerBorrowerAccount(address account, address principal) external;

  function getBorrowerAccounts(address principal) external view returns (address[] memory);

  function getBorrowerAccounts(
    address principal,
    uint256 start,
    uint256 end
  ) external view returns (address[] memory);

  function getBorrowerAccountsCount(address principal) external view returns (uint256);

  function getBorrowerAccountsForFactory(
    address accountFactory
  ) external view returns (address[] memory);

  function getBorrowerAccountsForFactory(
    address accountFactory,
    uint256 start,
    uint256 end
  ) external view returns (address[] memory);

  function getBorrowerAccountsForFactoryCount(
    address accountFactory
  ) external view returns (uint256);
}
