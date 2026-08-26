// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import { EnumerableSet } from 'openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import './interfaces/IBorrowerIdentityRegistry.sol';
import './interfaces/IWildcatArchController.sol';

/**
 * @dev Resolves borrower accounts to registered principals. The current ArchController
 *      owner may approve factories, but account principals manage their own transfers.
 */
contract WildcatBorrowerIdentityRegistry is IBorrowerIdentityRegistry {
  using EnumerableSet for EnumerableSet.AddressSet;

  address internal immutable _archController;

  EnumerableSet.AddressSet internal _accountFactories;

  mapping(address account => address principal) public override principalOf;
  mapping(address account => address pendingPrincipal) public override pendingPrincipalOf;
  mapping(address account => address accountFactory) public override accountFactoryOf;
  mapping(address principal => EnumerableSet.AddressSet accounts) internal _borrowerAccounts;
  mapping(address accountFactory => address[] accounts) internal _borrowerAccountsForFactory;

  constructor(address archController_) {
    if (archController_ == address(0) || archController_.code.length == 0) {
      revert InvalidArchController();
    }
    _archController = archController_;
  }

  function archController() external view override returns (address) {
    return _archController;
  }

  modifier onlyArchControllerOwner() {
    if (msg.sender != _archControllerOwner()) {
      revert CallerNotArchControllerOwner();
    }
    _;
  }

  modifier onlyAccountFactory() {
    if (!_accountFactories.contains(msg.sender)) {
      revert CallerNotAccountFactory();
    }
    _;
  }

  function addAccountFactory(
    address accountFactory
  ) external override onlyArchControllerOwner {
    if (accountFactory == address(0) || accountFactory.code.length == 0) {
      revert InvalidAccountFactory();
    }
    if (!_accountFactories.add(accountFactory)) {
      revert AccountFactoryAlreadyExists();
    }
    emit AccountFactoryAdded(msg.sender, accountFactory);
  }

  function removeAccountFactory(
    address accountFactory
  ) external override onlyArchControllerOwner {
    if (!_accountFactories.remove(accountFactory)) {
      revert AccountFactoryDoesNotExist();
    }
    emit AccountFactoryRemoved(msg.sender, accountFactory);
  }

  function isAccountFactory(address accountFactory) external view override returns (bool) {
    return _accountFactories.contains(accountFactory);
  }

  function getAccountFactories() external view override returns (address[] memory) {
    return _accountFactories.values();
  }

  function getAccountFactories(
    uint256 start,
    uint256 end
  ) external view override returns (address[] memory arr) {
    if (start > end) revert InvalidPaginationRange();
    uint256 length = _accountFactories.length();
    if (end > length) end = length;
    if (start >= end) return new address[](0);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _accountFactories.at(start + i);
    }
  }

  function getAccountFactoriesCount() external view override returns (uint256) {
    return _accountFactories.length();
  }

  function registerBorrowerAccount(
    address account,
    address principal
  ) external override onlyAccountFactory {
    if (principal == address(0)) revert BorrowerPrincipalNotRegistered();
    if (account == address(0) || account == principal || account.code.length == 0) {
      revert InvalidBorrowerAccount();
    }
    if (principalOf[account] != address(0)) {
      revert BorrowerAccountAlreadyRegistered();
    }

    if (_isRegisteredBorrower(account) || principalOf[principal] != address(0)) {
      revert AmbiguousBorrowerIdentity();
    }
    if (!_isRegisteredBorrower(principal)) {
      revert BorrowerPrincipalNotRegistered();
    }

    principalOf[account] = principal;
    accountFactoryOf[account] = msg.sender;
    _borrowerAccounts[principal].add(account);
    _borrowerAccountsForFactory[msg.sender].push(account);

    emit BorrowerAccountRegistered(account, principal, msg.sender);
  }

  function requestBorrowerAccountPrincipalTransfer(
    address account,
    address newPrincipal
  ) external override {
    address currentPrincipal = _getAccountPrincipal(account);
    if (msg.sender != currentPrincipal) revert CallerNotBorrowerAccountPrincipal();
    _validatePrincipalTransferTarget(account, currentPrincipal, newPrincipal);

    address previousPendingPrincipal = pendingPrincipalOf[account];
    pendingPrincipalOf[account] = newPrincipal;
    emit BorrowerAccountPrincipalTransferRequested(
      account,
      currentPrincipal,
      previousPendingPrincipal,
      newPrincipal
    );
  }

  function cancelBorrowerAccountPrincipalTransfer(address account) external override {
    address currentPrincipal = _getAccountPrincipal(account);
    if (msg.sender != currentPrincipal) revert CallerNotBorrowerAccountPrincipal();

    address cancelledPendingPrincipal = pendingPrincipalOf[account];
    if (cancelledPendingPrincipal == address(0)) {
      revert NoPendingBorrowerAccountPrincipalTransfer();
    }
    delete pendingPrincipalOf[account];
    emit BorrowerAccountPrincipalTransferCancelled(
      account,
      currentPrincipal,
      cancelledPendingPrincipal
    );
  }

  function acceptBorrowerAccountPrincipalTransfer(address account) external override {
    address newPrincipal = pendingPrincipalOf[account];
    if (msg.sender != newPrincipal) revert CallerNotPendingBorrowerAccountPrincipal();

    address previousPrincipal = _getAccountPrincipal(account);
    _validatePrincipalTransferTarget(account, previousPrincipal, newPrincipal);

    delete pendingPrincipalOf[account];
    _borrowerAccounts[previousPrincipal].remove(account);
    _borrowerAccounts[newPrincipal].add(account);
    principalOf[account] = newPrincipal;

    emit BorrowerAccountPrincipalTransferred(account, previousPrincipal, newPrincipal);
  }

  function resolveBorrower(address borrower) external view override returns (address principal) {
    if (borrower == address(0)) revert BorrowerIdentityNotFound();

    principal = principalOf[borrower];
    if (_isRegisteredBorrower(borrower)) {
      if (principal != address(0)) revert AmbiguousBorrowerIdentity();
      return borrower;
    }
    if (principal == address(0)) revert BorrowerIdentityNotFound();
    if (principalOf[principal] != address(0)) revert AmbiguousBorrowerIdentity();
    if (!_isRegisteredBorrower(principal)) {
      revert BorrowerPrincipalNotRegistered();
    }
  }

  function getBorrowerAccounts(
    address principal
  ) external view override returns (address[] memory) {
    return _borrowerAccounts[principal].values();
  }

  function getBorrowerAccounts(
    address principal,
    uint256 start,
    uint256 end
  ) external view override returns (address[] memory) {
    return _getAddressSetSlice(_borrowerAccounts[principal], start, end);
  }

  function getBorrowerAccountsCount(address principal) external view override returns (uint256) {
    return _borrowerAccounts[principal].length();
  }

  function getBorrowerAccountsForFactory(
    address accountFactory
  ) external view override returns (address[] memory) {
    return _borrowerAccountsForFactory[accountFactory];
  }

  function getBorrowerAccountsForFactory(
    address accountFactory,
    uint256 start,
    uint256 end
  ) external view override returns (address[] memory) {
    return _getAddressSlice(_borrowerAccountsForFactory[accountFactory], start, end);
  }

  function getBorrowerAccountsForFactoryCount(
    address accountFactory
  ) external view override returns (uint256) {
    return _borrowerAccountsForFactory[accountFactory].length;
  }

  function _getAddressSlice(
    address[] storage values,
    uint256 start,
    uint256 end
  ) internal view returns (address[] memory arr) {
    if (start > end) revert InvalidPaginationRange();
    uint256 length = values.length;
    if (end > length) end = length;
    if (start >= end) return new address[](0);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = values[start + i];
    }
  }

  function _getAccountPrincipal(address account) internal view returns (address principal) {
    principal = principalOf[account];
    if (principal == address(0)) revert BorrowerAccountNotRegistered();
  }

  function _validatePrincipalTransferTarget(
    address account,
    address currentPrincipal,
    address newPrincipal
  ) internal view {
    if (
      newPrincipal == address(0) ||
      newPrincipal == account ||
      newPrincipal == currentPrincipal
    ) {
      revert InvalidBorrowerAccountPrincipalTransferTarget();
    }

    if (_isRegisteredBorrower(account) || principalOf[newPrincipal] != address(0)) {
      revert AmbiguousBorrowerIdentity();
    }
    if (!_isRegisteredBorrower(newPrincipal)) {
      revert BorrowerPrincipalNotRegistered();
    }
  }

  function _archControllerOwner() internal view returns (address controllerOwner) {
    address controller = _archController;
    assembly ('memory-safe') {
      // owner() has no arguments, so one scratch word can do both jobs. mstore leaves the
      // selector at 0x1c; call those last four bytes and reuse 0x00 for the return word.
      mstore(0, 0x8da5cb5b)
      if iszero(staticcall(gas(), controller, 0x1c, 0x04, 0, 0x20)) {
        // don't hide an ArchController error behind this helper. copy the complete revert data
        // over scratch space and bubble it up. this path ends here, so nothing needs that memory.
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }

      // owner() owes us one clean ABI address: a complete word with zeroes above the low 160 bits.
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      controllerOwner := mload(0)
      if shr(160, controllerOwner) {
        revert(0, 0)
      }
    }
  }

  function _isRegisteredBorrower(address borrower) internal view returns (bool isRegistered) {
    address controller = _archController;
    assembly ('memory-safe') {
      // same scratch-space layout, now with borrower in the second word. starting at 0x1c gives
      // us four selector bytes followed by one normal address slot, for 0x24 bytes total.
      mstore(0, 0x0787c1fe)
      mstore(0x20, borrower)
      if iszero(staticcall(gas(), controller, 0x1c, 0x24, 0, 0x20)) {
        // preserve the controller's revert exactly. the full payload can overwrite scratch
        // because this branch immediately reverts.
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }

      // Solidity's bool decoder requires one full word containing exactly zero or one. extra
      // return data is harmless, so only validate the first word.
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      isRegistered := mload(0)
      if gt(isRegistered, 1) {
        revert(0, 0)
      }
    }
  }

  function _getAddressSetSlice(
    EnumerableSet.AddressSet storage values,
    uint256 start,
    uint256 end
  ) internal view returns (address[] memory arr) {
    if (start > end) revert InvalidPaginationRange();
    uint256 length = values.length();
    if (end > length) end = length;
    if (start >= end) return new address[](0);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = values.at(start + i);
    }
  }
}
