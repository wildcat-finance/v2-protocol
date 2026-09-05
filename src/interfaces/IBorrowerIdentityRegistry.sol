// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title borrower identity registry
/// @notice resolves direct borrowers and factory-deployed borrower accounts to registered
///         principals.
/// @dev removing an account factory stops new registrations. it does not invalidate accounts the
///      factory already registered.
interface IBorrowerIdentityRegistry {
  /// @dev the caller is not the current ArchController owner.
  error CallerNotArchControllerOwner();
  /// @dev the caller is not an approved borrower-account factory.
  error CallerNotAccountFactory();
  /// @dev the ArchController address is zero or has no code.
  error InvalidArchController();
  /// @dev the proposed account factory is zero or has no code.
  error InvalidAccountFactory();
  /// @dev the proposed account factory is already approved.
  error AccountFactoryAlreadyExists();
  /// @dev the requested account factory is not approved.
  error AccountFactoryDoesNotExist();
  /// @dev the borrower account is zero, undeployed, or equal to its principal.
  error InvalidBorrowerAccount();
  /// @dev the borrower account already has a principal.
  error BorrowerAccountAlreadyRegistered();
  /// @dev the requested account has no registered principal.
  error BorrowerAccountNotRegistered();
  /// @dev the proposed principal is not a directly registered borrower.
  error BorrowerPrincipalNotRegistered();
  /// @dev the supplied address is neither a direct borrower nor a registered borrower account.
  error BorrowerIdentityNotFound();
  /// @dev one address appears as both a borrower account and a direct borrower or account
  ///      principal.
  error AmbiguousBorrowerIdentity();
  /// @dev the caller is not the borrower account's current principal.
  error CallerNotBorrowerAccountPrincipal();
  /// @dev the caller is not the borrower account's pending principal.
  error CallerNotPendingBorrowerAccountPrincipal();
  /// @dev the proposed principal is zero, the account itself, or the current principal.
  error InvalidBorrowerAccountPrincipalTransferTarget();
  /// @dev no principal transfer is pending for this borrower account.
  error NoPendingBorrowerAccountPrincipalTransfer();
  /// @dev the requested pagination start exceeds the requested end.
  error InvalidPaginationRange();

  /// @notice emitted when the ArchController owner approves an account factory.
  event AccountFactoryAdded(
    address indexed administrator,
    address indexed accountFactory
  );
  /// @notice emitted when the ArchController owner removes an account factory.
  event AccountFactoryRemoved(
    address indexed administrator,
    address indexed accountFactory
  );
  /// @notice emitted when an approved factory registers a borrower account.
  event BorrowerAccountRegistered(
    address indexed account,
    address indexed principal,
    address indexed accountFactory
  );
  /// @notice emitted when a principal starts or replaces an account's principal transfer.
  event BorrowerAccountPrincipalTransferRequested(
    address indexed account,
    address indexed currentPrincipal,
    address previousPendingPrincipal,
    address indexed pendingPrincipal
  );
  /// @notice emitted when the current principal cancels a pending transfer.
  event BorrowerAccountPrincipalTransferCancelled(
    address indexed account,
    address indexed currentPrincipal,
    address indexed cancelledPendingPrincipal
  );
  /// @notice emitted when the pending principal accepts the borrower account.
  event BorrowerAccountPrincipalTransferred(
    address indexed account,
    address indexed previousPrincipal,
    address indexed newPrincipal
  );

  /// @notice ArchController used to validate principals and derive the registry administrator.
  function archController() external view returns (address);

  /// @notice current principal associated with `account`, or zero if it is unknown.
  function principalOf(address account) external view returns (address);

  /// @notice principal that can accept a pending transfer for `account`.
  function pendingPrincipalOf(address account) external view returns (address);

  /// @notice factory that registered `account`, or zero if it is unknown.
  function accountFactoryOf(address account) external view returns (address);

  /// @notice resolves a direct principal or borrower account using current ArchController state.
  /// @dev reverts for unknown, unregistered, or ambiguous identities.
  function resolveBorrower(address borrower) external view returns (address principal);

  /// @notice approves a contract to register borrower accounts.
  /// @dev only the current ArchController owner can call this.
  function addAccountFactory(address accountFactory) external;

  /// @notice stops a factory from registering more accounts.
  /// @dev only the current ArchController owner can call this. existing accounts keep working.
  function removeAccountFactory(address accountFactory) external;

  /// @notice says whether `accountFactory` may register new borrower accounts.
  function isAccountFactory(address accountFactory) external view returns (bool);

  /// @notice returns every currently approved account factory in unstable enumeration order.
  function getAccountFactories() external view returns (address[] memory);

  /// @notice returns account factories in the half-open range `[start, end)`.
  /// @dev clamps `end` to the current count. `start > end` reverts.
  function getAccountFactories(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory);

  /// @notice returns the current number of approved account factories.
  function getAccountFactoriesCount() external view returns (uint256);

  /// @notice associates a deployed borrower account with its initial registered principal.
  /// @dev only an approved account factory can call this. the account must be deployed code and
  ///      the principal must be a direct, registered borrower.
  function registerBorrowerAccount(address account, address principal) external;

  /// @notice proposes a new registered principal for `account`, replacing any earlier proposal.
  /// @dev only the current principal can call this.
  function requestBorrowerAccountPrincipalTransfer(address account, address newPrincipal) external;

  /// @notice clears the pending principal transfer for `account`.
  /// @dev only the current principal can call this.
  function cancelBorrowerAccountPrincipalTransfer(address account) external;

  /// @notice accepts the pending principal transfer for `account`.
  /// @dev only the pending principal can call this. factory provenance does not change.
  function acceptBorrowerAccountPrincipalTransfer(address account) external;

  /// @notice returns every current borrower account for `principal` in unstable order.
  function getBorrowerAccounts(address principal) external view returns (address[] memory);

  /// @notice returns `principal`'s current accounts in `[start, min(end, count))`.
  /// @dev `start > end` reverts; an empty or out-of-bounds range returns an empty array.
  function getBorrowerAccounts(
    address principal,
    uint256 start,
    uint256 end
  ) external view returns (address[] memory);

  /// @notice returns the current number of borrower accounts for `principal`.
  function getBorrowerAccountsCount(address principal) external view returns (uint256);

  /// @notice returns every account originally registered by `accountFactory`.
  /// @dev principal transfers do not change this provenance list.
  function getBorrowerAccountsForFactory(
    address accountFactory
  ) external view returns (address[] memory);

  /// @notice returns factory-provenance accounts in `[start, min(end, count))`.
  /// @dev `start > end` reverts; an empty or out-of-bounds range returns an empty array.
  function getBorrowerAccountsForFactory(
    address accountFactory,
    uint256 start,
    uint256 end
  ) external view returns (address[] memory);

  /// @notice returns how many accounts `accountFactory` originally registered.
  function getBorrowerAccountsForFactoryCount(
    address accountFactory
  ) external view returns (uint256);
}
