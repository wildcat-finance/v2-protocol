// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IBorrowerIdentityRegistry {
  error CallerNotArchControllerOwner();
  error CallerNotAccountFactory();
  error InvalidArchController();
  error InvalidAccountFactory();
  error AccountFactoryAlreadyExists();
  error AccountFactoryDoesNotExist();
  error InvalidBorrowerAccount();
  error BorrowerAccountAlreadyRegistered();
  error BorrowerAccountNotRegistered();
  error BorrowerPrincipalNotRegistered();
  error BorrowerIdentityNotFound();
  error AmbiguousBorrowerIdentity();
  error CallerNotBorrowerAccountPrincipal();
  error CallerNotPendingBorrowerAccountPrincipal();
  error InvalidBorrowerAccountPrincipalTransferTarget();
  error NoPendingBorrowerAccountPrincipalTransfer();
  error InvalidPaginationRange();

  event AccountFactoryAdded(
    address indexed administrator,
    address indexed accountFactory
  );
  event AccountFactoryRemoved(
    address indexed administrator,
    address indexed accountFactory
  );
  event BorrowerAccountRegistered(
    address indexed account,
    address indexed principal,
    address indexed accountFactory
  );
  event BorrowerAccountPrincipalTransferRequested(
    address indexed account,
    address indexed currentPrincipal,
    address previousPendingPrincipal,
    address indexed pendingPrincipal
  );
  event BorrowerAccountPrincipalTransferCancelled(
    address indexed account,
    address indexed currentPrincipal,
    address indexed cancelledPendingPrincipal
  );
  event BorrowerAccountPrincipalTransferred(
    address indexed account,
    address indexed previousPrincipal,
    address indexed newPrincipal
  );

  function archController() external view returns (address);

  /// @notice Current principal associated with `account`, or zero if it is unknown.
  function principalOf(address account) external view returns (address);

  /// @notice Principal that can accept a pending transfer for `account`.
  function pendingPrincipalOf(address account) external view returns (address);

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

  /// @notice Associates a deployed borrower account with its initial registered principal.
  function registerBorrowerAccount(address account, address principal) external;

  function requestBorrowerAccountPrincipalTransfer(address account, address newPrincipal) external;

  function cancelBorrowerAccountPrincipalTransfer(address account) external;

  function acceptBorrowerAccountPrincipalTransfer(address account) external;

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
