// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../libraries/BoolUtils.sol';
import '../types/RoleProvider.sol';
import '../types/LenderStatus.sol';
import './IRoleProvider.sol';
import './ProviderStructs.sol';
import './IRoleProviderFactory.sol';
import './IHooksAdministrator.sol';
import '../interfaces/IWildcatArchController.sol';

using BoolUtils for bool;

contract BaseAccessControls is IHooksAdministrator {
  // ========================================================================== //
  //                                   Events                                   //
  // ========================================================================== //

  event RoleProviderUpdated(
    address indexed providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex,
    uint24 pushProviderIndex
  );
  event RoleProviderAdded(
    address indexed providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex,
    uint24 pushProviderIndex
  );
  event RoleProviderRemoved(
    address indexed providerAddress,
    uint24 pullProviderIndex,
    uint24 pushProviderIndex
  );
  event AccountBlockedFromDeposits(address indexed accountAddress);
  event AccountUnblockedFromDeposits(address indexed accountAddress);
  event AccountAccessGranted(
    address indexed providerAddress,
    address indexed accountAddress,
    uint32 credentialTimestamp
  );
  event AccountAccessRevoked(address indexed accountAddress);
  event AccountMadeFirstDeposit(address indexed market, address indexed accountAddress);
  event NameUpdated(string name);
  event AdministratorTransferRequested(
    address indexed administrator,
    address indexed previousPendingAdministrator,
    address indexed pendingAdministrator
  );
  event AdministratorTransferCancelled(
    address indexed administrator,
    address indexed cancelledPendingAdministrator
  );
  event AdministratorTransferred(
    address indexed previousAdministrator,
    address indexed newAdministrator
  );

  // ========================================================================== //
  //                                   Errors                                   //
  // ========================================================================== //

  error CallerNotAdministrator();
  error InvalidAdministratorTransferTarget();
  error AdministratorNotRegistered();
  error NoPendingAdministratorTransfer();
  error NotPendingAdministrator();
  error ProviderNotFound();
  error ProviderCanNotReplaceCredential();
  error ProviderCanNotRevokeCredential();
  /// @dev Error thrown when a provider grants a credential with a null or future timestamp.
  error InvalidCredentialTimestamp();
  /// @dev Error thrown when a provider grants a credential that is already expired.
  error GrantedCredentialExpired();
  /// @dev Error thrown when a provider is called to validate a credential and the
  ///      returndata can not be decoded as a uint.
  error InvalidCredentialReturned();
  /// @dev Error thrown when a user does not have a valid credential
  error NotApprovedLender();
  error InvalidArrayLength();
  error CreateRoleProviderFailed();

  // ========================================================================== //
  //                                    State                                   //
  // ========================================================================== //

  address public override administrator;
  address public override pendingAdministrator;
  address internal immutable _hooksFactory;
  // Name of the hooks instance
  string public name;
  // Credentials by lender address
  mapping(address => LenderStatus) internal _lenderStatus;
  // Whether an account is a known lender for a given market
  mapping(address lender => mapping(address market => bool)) public isKnownLenderOnMarket;
  RoleProvider[] internal _pullProviders;
  RoleProvider[] internal _pushProviders;
  mapping(address => RoleProvider) internal _roleProviders;

  // ========================================================================== //
  //                                  Modifiers                                 //
  // ========================================================================== //

  modifier onlyAdministrator() {
    if (msg.sender != administrator) revert CallerNotAdministrator();
    _;
  }

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  constructor(address _administrator) {
    administrator = _administrator;
    _hooksFactory = msg.sender;
  }

  function _initialize(NameAndProviderInputs memory inputs) internal {
    name = inputs.name;
    for (uint256 i = 0; i < inputs.existingProviders.length; i++) {
      ExistingProviderInputs memory provider = inputs.existingProviders[i];
      _addRoleProvider(provider.providerAddress, provider.timeToLive);
    }
    IRoleProviderFactory providerFactory = IRoleProviderFactory(inputs.roleProviderFactory);
    if (address(providerFactory) != address(0)) {
      for (uint256 i; i < inputs.newProviderInputs.length; i++) {
        CreateProviderInputs memory createProviderInputs = inputs.newProviderInputs[i];
        _createRoleProvider(
          providerFactory,
          createProviderInputs.timeToLive,
          createProviderInputs.providerFactoryCalldata
        );
      }
    }
  }

  /// @dev Compatibility alias for integrations that still call the hook administrator `borrower`.
  function borrower() external view returns (address) {
    return administrator;
  }

  // ========================================================================== //
  //                         Administrator transfer                             //
  // ========================================================================== //

  function _validateAdministratorTransferTarget(address newAdministrator) internal view {
    if (newAdministrator == address(0) || newAdministrator == administrator) {
      revert InvalidAdministratorTransferTarget();
    }
    address archController = IHooksFactoryAdministratorCallback(_hooksFactory).archController();
    if (!IWildcatArchController(archController).isRegisteredBorrower(newAdministrator)) {
      revert AdministratorNotRegistered();
    }
  }

  function requestAdministratorTransfer(
    address newAdministrator
  ) external override onlyAdministrator {
    _validateAdministratorTransferTarget(newAdministrator);
    address previousPendingAdministrator = pendingAdministrator;
    pendingAdministrator = newAdministrator;
    emit AdministratorTransferRequested(
      msg.sender,
      previousPendingAdministrator,
      newAdministrator
    );
  }

  function cancelAdministratorTransfer() external override onlyAdministrator {
    address cancelledPendingAdministrator = pendingAdministrator;
    if (cancelledPendingAdministrator == address(0)) {
      revert NoPendingAdministratorTransfer();
    }
    pendingAdministrator = address(0);
    emit AdministratorTransferCancelled(msg.sender, cancelledPendingAdministrator);
  }

  function acceptAdministratorTransfer() external override {
    address newAdministrator = pendingAdministrator;
    if (msg.sender != newAdministrator) revert NotPendingAdministrator();
    _validateAdministratorTransferTarget(newAdministrator);

    address previousAdministrator = administrator;
    pendingAdministrator = address(0);
    administrator = newAdministrator;
    emit AdministratorTransferred(previousAdministrator, newAdministrator);

    IHooksFactoryAdministratorCallback(_hooksFactory).onHooksAdministratorTransferred(
      previousAdministrator,
      newAdministrator
    );
  }

  /// @dev Administrator-only setter for this hooks instance name.
  function setName(string memory _name) external onlyAdministrator {
    name = _name;
    emit NameUpdated(_name);
  }

  // ========================================================================== //
  //                             Provider management                            //
  // ========================================================================== //

  /**
   * @dev Administrator-only helper that creates a role provider through `providerFactory`
   *      and adds it with the supplied TTL. Reverts if creation returns address(0).
   */
  function createRoleProvider(
    address providerFactory,
    uint32 timeToLive,
    bytes memory data
  ) external onlyAdministrator {
    _createRoleProvider(IRoleProviderFactory(providerFactory), timeToLive, data);
  }

  function _createRoleProvider(
    IRoleProviderFactory providerFactory,
    uint32 timeToLive,
    bytes memory data
  ) internal {
    address providerAddress = providerFactory.createRoleProvider(data);
    if (providerAddress == address(0)) revert CreateRoleProviderFailed();
    _addRoleProvider(providerAddress, timeToLive);
  }

  /**
   * @dev Adds or updates a role provider that is able to grant user access.
   *      If it is not already approved, it is added to `_roleProviders` and,
   *      if the provider can refresh credentials, added to `pullProviders`;
   *      otherwise, it is added to `pushProviders`.
   *      If the provider is already approved, only updates `timeToLive`.
   */
  function addRoleProvider(address providerAddress, uint32 timeToLive) external onlyAdministrator {
    _addRoleProvider(providerAddress, timeToLive);
  }

  function _isPullProvider(address providerAddress) internal view returns (bool isPullProvider) {
    (bool success, bytes memory data) = providerAddress.staticcall(
      abi.encodeCall(IRoleProvider.isPullProvider, ())
    );
    if (success && data.length >= 0x20) {
      uint256 result;
      assembly {
        result := mload(add(data, 0x20))
      }
      // Only a clean boolean true response makes the provider pull-capable.
      isPullProvider = result == 1;
    }
  }

  function _addRoleProvider(address providerAddress, uint32 timeToLive) internal {
    RoleProvider provider = _roleProviders[providerAddress];
    if (provider.isNull()) {
      bool isPullProvider = _isPullProvider(providerAddress);
      (uint24 pullProviderIndex, uint24 pushProviderIndex) = isPullProvider
        ? (uint24(_pullProviders.length), NullProviderIndex)
        : (NullProviderIndex, uint24(_pushProviders.length));
      // Role providers that are not pull providers have `pullProviderIndex` set to
      // `NullProviderIndex` (max uint24) to indicate they do not refresh credentials.
      provider = encodeRoleProvider(
        timeToLive,
        providerAddress,
        pullProviderIndex,
        pushProviderIndex
      );
      if (isPullProvider) {
        _pullProviders.push(provider);
      } else {
        _pushProviders.push(provider);
      }
      emit RoleProviderAdded(providerAddress, timeToLive, pullProviderIndex, pushProviderIndex);
    } else {
      // If provider already exists, the only value that can be updated is the TTL
      provider = provider.setTimeToLive(timeToLive);
      uint24 pullProviderIndex = provider.pullProviderIndex();
      uint24 pushProviderIndex = provider.pushProviderIndex();
      if (pullProviderIndex != NullProviderIndex) {
        _pullProviders[pullProviderIndex] = provider;
      } else {
        _pushProviders[pushProviderIndex] = provider;
      }
      emit RoleProviderUpdated(providerAddress, timeToLive, pullProviderIndex, pushProviderIndex);
    }
    // Update the provider in storage
    _roleProviders[providerAddress] = provider;
  }

  /**
   * @dev Removes a role provider from the `_roleProviders` mapping and, if it is a
   *      pull provider, from the `_pullProviders` array.
   */
  function removeRoleProvider(address providerAddress) external onlyAdministrator {
    RoleProvider provider = _roleProviders[providerAddress];
    if (provider.isNull()) revert ProviderNotFound();
    // Remove the provider from `_roleProviders`
    _roleProviders[providerAddress] = EmptyRoleProvider;
    emit RoleProviderRemoved(
      providerAddress,
      provider.pullProviderIndex(),
      provider.pushProviderIndex()
    );
    // If the provider is a pull provider, remove it from `_pullProviders`
    if (provider.isPullProvider()) {
      _removePullProvider(provider.pullProviderIndex());
    } else {
      _removePushProvider(provider.pushProviderIndex());
    }
  }

  /**
   * @dev Remove a pull provider from the `_pullProviders` array.
   *      If the provider is not the last in the array, the last provider
   *      is moved to the index of the provider being removed, so its index
   *      must also be updated in the `_roleProviders` mapping.
   */
  function _removePullProvider(uint24 indexToRemove) internal {
    // Get the last index in the array
    uint256 lastIndex = _pullProviders.length - 1;
    // If the index to remove is the last index, just pop the last element
    if (indexToRemove == lastIndex) {
      _pullProviders.pop();
      return;
    }
    // If the index to remove is not the last index, move the last element
    // to the index of the element being removed
    RoleProvider lastProvider = _pullProviders[lastIndex].setPullProviderIndex(indexToRemove);
    _pullProviders[indexToRemove] = lastProvider;
    _pullProviders.pop();
    address lastProviderAddress = lastProvider.providerAddress();
    _roleProviders[lastProviderAddress] = lastProvider;
    // Emit an event to notify that the provider's index has been updated
    emit RoleProviderUpdated(
      lastProviderAddress,
      lastProvider.timeToLive(),
      indexToRemove,
      NullProviderIndex
    );
  }

  /**
   * @dev Remove a push provider from the `_pushProviders` array.
   *      If the provider is not the last in the array, the last provider
   *      is moved to the index of the provider being removed, so its index
   *      must also be updated in the `_roleProviders` mapping.
   */
  function _removePushProvider(uint24 indexToRemove) internal {
    // Get the last index in the array
    uint256 lastIndex = _pushProviders.length - 1;
    // If the index to remove is the last index, just pop the last element
    if (indexToRemove == lastIndex) {
      _pushProviders.pop();
      return;
    }
    // If the index to remove is not the last index, move the last element
    // to the index of the element being removed
    RoleProvider lastProvider = _pushProviders[lastIndex].setPushProviderIndex(indexToRemove);
    _pushProviders[indexToRemove] = lastProvider;
    _pushProviders.pop();
    address lastProviderAddress = lastProvider.providerAddress();
    _roleProviders[lastProviderAddress] = lastProvider;
    // Emit an event to notify that the provider's index has been updated
    emit RoleProviderUpdated(
      lastProviderAddress,
      lastProvider.timeToLive(),
      NullProviderIndex,
      indexToRemove
    );
  }

  // ========================================================================== //
  //                              Provider queries                              //
  // ========================================================================== //

  /// @dev Returns encoded role provider settings for `providerAddress`.
  function getRoleProvider(address providerAddress) external view returns (RoleProvider) {
    return _roleProviders[providerAddress];
  }

  /// @dev Returns all providers that can be queried for credentials.
  function getPullProviders() external view returns (RoleProvider[] memory) {
    return _pullProviders;
  }

  /// @dev Returns all providers that grant credentials by calling this contract.
  function getPushProviders() external view returns (RoleProvider[] memory) {
    return _pushProviders;
  }

  // ========================================================================== //
  //                                Role queries                                //
  // ========================================================================== //

  /// @dev Returns stored lender status without refreshing credentials.
  function getPreviousLenderStatus(
    address accountAddress
  ) external view returns (LenderStatus memory status) {
    status = _lenderStatus[accountAddress];
  }

  /**
   * @dev Retrieves the current status of a lender, attempting to find a valid
   *      credential if their current one is invalid or non-existent.
   *
   *      If the lender has an expired credential, will attempt to refresh it
   *      with the previous provider if it is still supported.
   *
   *      If the lender has no credential, or one from a provider that is no longer
   *      supported or will not refresh it, will loop over all providers to find
   *      a valid credential.
   */
  function getLenderStatus(
    address accountAddress
  ) external view returns (LenderStatus memory status) {
    status = _lenderStatus[accountAddress];

    uint256 previousPullProviderIndexToSkip = type(uint256).max;

    // Check if user has an existing credential
    if (status.lastApprovalTimestamp > 0) {
      RoleProvider provider = _roleProviders[status.lastProvider];
      if (!provider.isNull()) {
        if (_canUseCachedCredential(status, provider)) return status;

        // If credential is expired but the provider is still supported and
        // allows refreshing (i.e. it's a pull provider), try to refresh.
        if (status.canRefresh) {
          if (_tryGetCredential(status, provider, accountAddress)) {
            return status;
          }
          // If refresh fails, provider should be skipped in the query loop
          previousPullProviderIndexToSkip = provider.pullProviderIndex();
        }
      }
      // If credential could not be refreshed or the provider is no longer
      // supported, remove it
      status.unsetCredential();
    }

    // Loop over all pull providers to find a valid role for the lender
    if (
      _loopTryGetCredential(
        status,
        accountAddress,
        previousPullProviderIndexToSkip,
        type(uint256).max
      )
    ) {
      return status;
    }
  }

  // ========================================================================== //
  //                                Role actions                                //
  // ========================================================================== //

  /**
   * @dev Grants a role to an account by updating the account's status.
   *      Can only be called by an approved role provider.
   *
   *      If the account has an existing credential, it can only be updated if:
   *      - the previous credential's provider is no longer supported, OR
   *      - the caller is the previous role provider, OR
   *      - the new expiry is later than the current expiry
   */
  function grantRole(address account, uint32 roleGrantedTimestamp) external {
    RoleProvider callingProvider = _roleProviders[msg.sender];

    if (callingProvider.isNull()) revert ProviderNotFound();

    _grantRole(callingProvider, account, roleGrantedTimestamp);
  }

  /**
   * @dev Grants roles to multiple accounts by updating their statuses.
   *      Can only be called by an approved role provider.
   *
   *      If any account has an existing credential, it can only be updated if:
   *      - the previous credential's provider is no longer supported, OR
   *      - the caller is the previous role provider, OR
   *      - the new expiry is later than the current expiry
   */
  function grantRoles(address[] memory accounts, uint32[] memory roleGrantedTimestamps) external {
    RoleProvider callingProvider = _roleProviders[msg.sender];

    if (callingProvider.isNull()) revert ProviderNotFound();

    if (accounts.length != roleGrantedTimestamps.length) revert InvalidArrayLength();
    for (uint256 i = 0; i < accounts.length; i++) {
      _grantRole(callingProvider, accounts[i], roleGrantedTimestamps[i]);
    }
  }

  function _grantRole(
    RoleProvider callingProvider,
    address account,
    uint32 roleGrantedTimestamp
  ) internal {
    LenderStatus memory status = _lenderStatus[account];

    if (roleGrantedTimestamp == 0 || roleGrantedTimestamp > block.timestamp) {
      revert InvalidCredentialTimestamp();
    }

    uint256 newExpiry = callingProvider.calculateExpiry(roleGrantedTimestamp);

    // Check if the new credential is still valid
    if (newExpiry < block.timestamp) revert GrantedCredentialExpired();

    // Check if the account has ever had a credential
    if (status.hasCredential()) {
      RoleProvider lastProvider = _roleProviders[status.lastProvider];

      // Check if the provider that last granted access is still supported
      if (!lastProvider.isNull()) {
        uint256 oldExpiry = lastProvider.calculateExpiry(status.lastApprovalTimestamp);

        // Can only update role if the caller is the previous role provider or the new
        // expiry is greater than the previous expiry.
        if (!((status.lastProvider == msg.sender).or(newExpiry > oldExpiry))) {
          revert ProviderCanNotReplaceCredential();
        }
      }
    }

    _setCredentialAndEmitAccessGranted(status, callingProvider, account, roleGrantedTimestamp);
  }

  /// @dev Revokes `account`'s credential. Reverts unless caller granted it.
  function revokeRole(address account) external {
    _revokeRole(account);
  }

  /// @dev Revokes credentials for each account; caller must have granted each one.
  function revokeRoles(address[] calldata accounts) external {
    for (uint256 i = 0; i < accounts.length; i++) {
      _revokeRole(accounts[i]);
    }
  }

  function _revokeRole(address account) internal {
    LenderStatus memory status = _lenderStatus[account];
    if (msg.sender != status.lastProvider) {
      revert ProviderCanNotRevokeCredential();
    }
    status.unsetCredential();
    _lenderStatus[account] = status;
    emit AccountAccessRevoked(account);
  }

  /// @dev Administrator-only block that clears any credential and prevents future deposits.
  function blockFromDeposits(address account) external onlyAdministrator {
    _blockFromDeposits(account);
  }

  /// @dev Administrator-only batch version of `blockFromDeposits`.
  function blockFromDeposits(address[] calldata accounts) external onlyAdministrator {
    for (uint256 i; i < accounts.length; i++) {
      _blockFromDeposits(accounts[i]);
    }
  }

  function _blockFromDeposits(address account) internal {
    LenderStatus memory status = _lenderStatus[account];
    if (status.hasCredential()) {
      status.unsetCredential();
      emit AccountAccessRevoked(account);
    }
    status.isBlockedFromDeposits = true;
    _lenderStatus[account] = status;
    emit AccountBlockedFromDeposits(account);
  }

  /// @dev Administrator-only unblock that lets the account deposit if otherwise approved.
  function unblockFromDeposits(address account) external onlyAdministrator {
    LenderStatus memory status = _lenderStatus[account];
    status.isBlockedFromDeposits = false;
    _lenderStatus[account] = status;
    emit AccountUnblockedFromDeposits(account);
  }

  /**
   * @dev Tries to pull an active credential for an account from a pull provider.
   *      If one exists, updates the account in memory and returns true.
   *
   *      Note: Does not check that provider is a pull provider - should
   *      only be called if that has already been checked.
   */
  function _tryGetCredential(
    LenderStatus memory status,
    RoleProvider provider,
    address accountAddress
  ) internal view returns (bool isApproved) {
    // Query provider for user approval
    address providerAddress = provider.providerAddress();

    uint32 credentialTimestamp;
    uint getCredentialSelector = uint32(IRoleProvider.getCredential.selector);
    assembly {
      mstore(0x00, getCredentialSelector)
      mstore(0x20, accountAddress)
      // Call the provider and check if the return data is valid
      if and(gt(returndatasize(), 0x1f), staticcall(gas(), providerAddress, 0x1c, 0x24, 0, 0x20)) {
        // If the return data is valid, set `credentialTimestamp` to the returned word
        // with a uint32 mask applied
        credentialTimestamp := and(mload(0), 0xffffffff)
      }
    }

    // If the returned timestamp is null or greater than the current time, return false.
    if (credentialTimestamp == 0 || credentialTimestamp > block.timestamp) {
      return false;
    }

    // If credential is still valid, update credential
    if (provider.calculateExpiry(credentialTimestamp) >= block.timestamp) {
      // User is approved, update status with the new approval timestamp and provider
      status.setCredential(provider, credentialTimestamp);
      return true;
    }
  }

  /**
   * @dev A zero-TTL pull credential cannot satisfy a check from cache, including
   *      another check in the same block. Push providers keep their existing
   *      timestamp behavior because the hook cannot refresh them.
   */
  function _canUseCachedCredential(
    LenderStatus memory status,
    RoleProvider provider
  ) internal view returns (bool) {
    if (provider.isPullProvider() && provider.timeToLive() == 0) return false;
    return status.credentialNotExpired(provider);
  }

  function _readAddress(bytes calldata hooksData) internal pure returns (address providerAddress) {
    assembly {
      providerAddress := shr(96, calldataload(hooksData.offset))
    }
  }

  /**
   * @dev Uses the data added to the end of the base call to the market function to call
   *      `validateCredential` on the selected provider. Returns false if the provider does not
   *      exist, the call fails, or the credential is invalid. Only reverts if the call succeeds but
   *      does not return the correct amount of data.
   *
   *      The calldata to the market function must have a suffix encoded as (address, bytes), where
   *      the address is packed and the bytes do not contain an offset or length. For example, if
   *      the market function were `fn(uint256 arg0)` and the user provided a 32 byte `accessToken`
   *      for provider `provider0`, the calldata to the market would be:
   *      [0:4] selector
   *      [4:36] arg0
   *      [36:58] provider0
   *      [58:90] `accessToken`
   */
  function _tryValidateCredential(
    LenderStatus memory status,
    address accountAddress,
    bytes calldata hooksData
  ) internal returns (bool) {
    uint validateSelector = uint32(IRoleProvider.validateCredential.selector);
    address providerAddress = _readAddress(hooksData);
    RoleProvider provider = _roleProviders[providerAddress];
    if (provider.isNull()) return false;
    uint credentialTimestamp;
    uint invalidCredentialReturnedSelector = uint32(InvalidCredentialReturned.selector);
    assembly {
      // Get the offset to the extra data provided in the hooks call, after the provider.
      let validateDataCalldataPointer := add(hooksData.offset, 0x14)
      // Encode the call to `validateCredential(address account, bytes calldata data)`
      let calldataPointer := mload(0x40)
      // The selector is right aligned, so the real calldata buffer begins at calldataPointer + 28
      mstore(calldataPointer, validateSelector)
      mstore(add(calldataPointer, 0x20), accountAddress)
      // Write the calldata offset to `data`
      mstore(add(calldataPointer, 0x40), 0x40)
      // Get length of the data segment in the hooks data
      let dataLength := sub(hooksData.length, 0x14)
      // Write the length of the calldata to `data`
      mstore(add(calldataPointer, 0x60), dataLength)
      // Copy the calldata to the buffer
      calldatacopy(add(calldataPointer, 0x80), validateDataCalldataPointer, dataLength)
      // Call the provider
      if call(
        gas(),
        providerAddress,
        0,
        add(calldataPointer, 0x1c),
        add(dataLength, 0x64),
        0,
        0x20
      ) {
        switch lt(returndatasize(), 0x20)
        case 1 {
          // If the returndata is invalid but the call succeeded, the call must throw
          // because the validateCredential function is stateful and can have side effects.
          mstore(0, invalidCredentialReturnedSelector)
          revert(0x1c, 0x04)
        }
        default {
          // If the return data is valid, set `credentialTimestamp` to the returned word
          // with a uint32 mask applied
          credentialTimestamp := and(mload(0), 0xffffffff)
        }
      }
    }
    // If the returned timestamp is null or greater than the current time, return false.
    if (credentialTimestamp == 0 || credentialTimestamp > block.timestamp) {
      return false;
    }
    // Check if the returned timestamp results in a valid expiry
    if (provider.calculateExpiry(credentialTimestamp) >= block.timestamp) {
      status.setCredential(provider, credentialTimestamp);
      return true;
    }
  }

  /// @dev Loops over pull providers to find a valid credential, skipping providers already tried.
  function _loopTryGetCredential(
    LenderStatus memory status,
    address accountAddress,
    uint256 previousPullProviderIndexToSkip,
    uint256 hooksDataPullProviderIndexToSkip
  ) internal view returns (bool foundCredential) {
    uint256 providerCount = _pullProviders.length;
    for (uint256 i = 0; i < providerCount; i++) {
      if (i == previousPullProviderIndexToSkip || i == hooksDataPullProviderIndexToSkip) continue;
      RoleProvider provider = _pullProviders[i];
      if (_tryGetCredential(status, provider, accountAddress)) return (true);
    }
  }

  /**
   * @dev Handles the hooks data passed to the contract.
   *
   *      If the hooks data is 20 bytes long, it is interpreted as a provider selection
   *      to pull a credential from with `getCredential`.
   *
   *      If the hooks data is more than 20 bytes, it is interpreted as a request to use
   *      `validateCredential`, where the first 20 bytes encode the provider address and
   *      the remaining bytes are the encoded credential data to pass to the provider.
   *
   *      If the hooks data is less than 20 bytes, it is skipped.
   *
   * @param status Current lender status object, updated in memory if a credential is found
   * @param accountAddress Address of the lender
   * @param hooksData Bytes passed to the contract for provider selection
   * @return validCredential True if hooks data produced a valid credential
   * @return pullProviderIndexToSkip Pull provider index selected by hooks data, if any
   */
  function _handleHooksData(
    LenderStatus memory status,
    address accountAddress,
    bytes calldata hooksData
  ) internal returns (bool validCredential, uint256 pullProviderIndexToSkip) {
    pullProviderIndexToSkip = type(uint256).max;
    // Check if the hooks data only contains a provider address
    if (hooksData.length == 20) {
      // If the data contains only an address, attempt to query a credential from that provider
      // if it exists and is a pull provider.
      address providerAddress = _readAddress(hooksData);
      RoleProvider provider = _roleProviders[providerAddress];
      if (!provider.isNull() && provider.isPullProvider()) {
        pullProviderIndexToSkip = provider.pullProviderIndex();
        validCredential = _tryGetCredential(status, provider, accountAddress);
      }
    } else if (hooksData.length > 20) {
      // If the data contains both an address and additional bytes, attempt to
      // validate a credential from that provider
      address providerAddress = _readAddress(hooksData);
      RoleProvider provider = _roleProviders[providerAddress];
      if (!provider.isNull() && provider.isPullProvider()) {
        pullProviderIndexToSkip = provider.pullProviderIndex();
      }
      validCredential = _tryValidateCredential(status, accountAddress, hooksData);
    }
  }

  /**
   * @dev Internal function used to validate or update the status of a lender account for
   *      hooks on restricted actions.
   *
   *     The function follows these steps until a valid credential is found:
   *       1. Check if lender has an existing unexpired credential.
   *       2. Check if `hooksData` was provided, and if so:
   *         - If it contains only an address, call `getCredential` on that provider.
   *         - If it contains an address and bytes, call `validateCredential` on that provider.
   *       3. If lender has an existing expired credential, attempt to refresh it.
   *       4. Loop over all pull providers to find a valid credential, excluding providers
   *          already checked during hooks data handling or expired credential refresh.
   *
   * note: Does not update storage or emit an event, but is stateful because it can invoke
   *       `validateCredential` on a provider.
   */
  function _tryValidateAccessInner(
    LenderStatus memory status,
    address accountAddress,
    bytes calldata hooksData
  ) internal returns (bool hasValidCredential, bool wasUpdated) {
    // Get the last provider that granted the lender a credential, if any
    RoleProvider lastProvider = status.hasCredential()
      ? _roleProviders[status.lastProvider]
      : EmptyRoleProvider;

    // If the lender has a cacheable active credential from a supported provider, return.
    if (!lastProvider.isNull() && _canUseCachedCredential(status, lastProvider)) {
      return (true, false);
    }

    // Handle the calldata suffix, if any
    (bool validCredential, uint256 hooksDataPullProviderIndexToSkip) = _handleHooksData(
      status,
      accountAddress,
      hooksData
    );

    if (validCredential) {
      return (true, true);
    }

    uint256 previousPullProviderIndexToSkip = type(uint256).max;

    // If lender has an expired credential from a pull provider, attempt to refresh it
    if (!lastProvider.isNull() && status.canRefresh) {
      if (_tryGetCredential(status, lastProvider, accountAddress)) {
        return (true, true);
      }
      // If refresh fails, provider should be skipped in the query loop
      previousPullProviderIndexToSkip = lastProvider.pullProviderIndex();
    }

    // Loop over all pull providers to find a valid role for the lender
    if (
      _loopTryGetCredential(
        status,
        accountAddress,
        previousPullProviderIndexToSkip,
        hooksDataPullProviderIndexToSkip
      )
    ) {
      return (true, true);
    }

    // If there was previously a credential and no valid credential could be found,
    // unset the credential.
    if (status.hasCredential()) {
      status.unsetCredential();
      wasUpdated = true;
    }
  }

  function _tryValidateAccess(
    LenderStatus memory status,
    address accountAddress,
    bytes calldata hooksData
  ) internal returns (bool hasValidCredential) {
    bool wasUpdated;
    (hasValidCredential, wasUpdated) = _tryValidateAccessInner(status, accountAddress, hooksData);
    _writeLenderStatus(status, accountAddress, hasValidCredential, wasUpdated, false);
  }

  /**
   * @dev Updates a lender's status in storage and emits an event when a
   *      credential is granted or revoked, or when the lender is marked
   *      as a known lender.
   */
  function _writeLenderStatus(
    LenderStatus memory status,
    address accountAddress,
    bool hasValidCredential,
    bool wasUpdated,
    bool canSetKnownLender
  ) internal {
    if (wasUpdated) {
      if (hasValidCredential) {
        emit AccountAccessGranted(
          status.lastProvider,
          accountAddress,
          status.lastApprovalTimestamp
        );
      } else {
        emit AccountAccessRevoked(accountAddress);
      }
    }
    // Mark account as a known lender if they have a valid credential, are not
    // already known, and the function counts as a deposit.
    if (
      canSetKnownLender.and(hasValidCredential).and(
        !isKnownLenderOnMarket[accountAddress][msg.sender]
      )
    ) {
      isKnownLenderOnMarket[accountAddress][msg.sender] = true;
      emit AccountMadeFirstDeposit(msg.sender, accountAddress);
    }

    // Write the account's status to storage if it was updated
    if (wasUpdated) _lenderStatus[accountAddress] = status;
  }

  function _setCredentialAndEmitAccessGranted(
    LenderStatus memory status,
    RoleProvider provider,
    address accountAddress,
    uint32 credentialTimestamp
  ) internal {
    // Update the account's status with the new credential in memory
    status.setCredential(provider, credentialTimestamp);
    // Update the account's status in storage
    _lenderStatus[accountAddress] = status;
    emit AccountAccessGranted(provider.providerAddress(), accountAddress, credentialTimestamp);
  }
}
