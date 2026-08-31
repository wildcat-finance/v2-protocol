// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import '../libraries/BoolUtils.sol';
import '../types/RoleProvider.sol';
import '../types/LenderStatus.sol';
import './IRoleProvider.sol';
import './ProviderStructs.sol';
import './IRoleProviderFactory.sol';
import './IHooksAdministrator.sol';
import '../interfaces/IWildcatArchController.sol';

using BoolUtils for bool;

/// @notice shared provider, credential, and lender-policy state for built-in access hooks.
/// @dev provider attachments and lender credentials belong to the hooks instance, which may serve
///      several markets. known-lender status is permanent and scoped to one lender and market.
///      the hooks administrator manages attachments and local deposit blocks; that authority does
///      not make the administrator a credential provider.
contract BaseAccessControls is IHooksAdministrator {
  // ========================================================================== //
  //                                   Events                                   //
  // ========================================================================== //

  /// @notice emitted when a provider's TTL changes or swap-removal moves its array index.
  event RoleProviderUpdated(
    address indexed administrator,
    address indexed providerAddress,
    uint32 previousTimeToLive,
    uint32 newTimeToLive,
    uint24 previousPullProviderIndex,
    uint24 newPullProviderIndex,
    uint24 previousPushProviderIndex,
    uint24 newPushProviderIndex
  );
  /// @notice emitted when the administrator attaches a credential provider.
  event RoleProviderAdded(
    address indexed administrator,
    address indexed providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex,
    uint24 pushProviderIndex
  );
  /// @notice emitted when the administrator detaches a credential provider.
  event RoleProviderRemoved(
    address indexed administrator,
    address indexed providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex,
    uint24 pushProviderIndex
  );
  /// @notice emitted when the administrator blocks an account from making new deposits.
  event AccountBlockedFromDeposits(
    address indexed administrator,
    address indexed accountAddress
  );
  /// @notice emitted when the administrator removes an account's deposit block.
  event AccountUnblockedFromDeposits(
    address indexed administrator,
    address indexed accountAddress
  );
  /// @notice emitted when this hooks instance stores a new lender credential.
  event AccountAccessGranted(
    address indexed providerAddress,
    address indexed accountAddress,
    address indexed caller,
    uint32 credentialTimestamp
  );
  /// @notice emitted when this hooks instance clears a stored lender credential.
  event AccountAccessRevoked(
    address indexed providerAddress,
    address indexed accountAddress,
    address indexed caller
  );
  /// @notice emitted the first time an account becomes known on a market.
  /// @dev the legacy name is broader than it sounds: receiving market tokens with a valid
  ///      credential can also make the account known.
  event AccountMadeFirstDeposit(address indexed market, address indexed accountAddress);
  /// @notice emitted when the hooks-instance display name changes.
  event NameUpdated(address indexed administrator, string previousName, string newName);
  /// @notice emitted when the administrator starts or replaces a two-step transfer.
  event AdministratorTransferRequested(
    address indexed administrator,
    address indexed previousPendingAdministrator,
    address indexed pendingAdministrator
  );
  /// @notice emitted when the administrator cancels a pending transfer.
  event AdministratorTransferCancelled(
    address indexed administrator,
    address indexed cancelledPendingAdministrator
  );
  /// @notice emitted when the pending administrator accepts authority.
  event AdministratorTransferred(
    address indexed previousAdministrator,
    address indexed newAdministrator
  );

  // ========================================================================== //
  //                                   Errors                                   //
  // ========================================================================== //

  /// @dev the caller is not the current hooks administrator.
  error CallerNotAdministrator();
  /// @dev the proposed administrator is zero or unchanged.
  error InvalidAdministratorTransferTarget();
  /// @dev the proposed or pending administrator is no longer a registered borrower.
  error AdministratorNotRegistered();
  /// @dev no hooks-administrator transfer is pending.
  error NoPendingAdministratorTransfer();
  /// @dev the caller is not the pending hooks administrator.
  error NotPendingAdministrator();
  /// @dev the requested provider is not attached to this hooks instance.
  error ProviderNotFound();
  /// @dev the provider is not allowed to replace the lender's current credential.
  error ProviderCanNotReplaceCredential();
  /// @dev the provider is not allowed to revoke the lender's current credential.
  error ProviderCanNotRevokeCredential();
  /// @dev an attached provider supplied a null or future credential timestamp.
  error InvalidCredentialTimestamp();
  /// @dev an attached provider supplied a credential already expired under its current TTL.
  error GrantedCredentialExpired();
  /// @dev a successful stateful validation returned less than one word.
  error InvalidCredentialReturned();
  /// @dev an action required a lender credential and none could be found.
  error NotApprovedLender();
  /// @dev parallel input arrays have different lengths.
  error InvalidArrayLength();
  /// @dev new-provider inputs were supplied without a provider factory.
  error RoleProviderFactoryRequired();
  /// @dev the provider factory returned the zero address.
  error CreateRoleProviderFailed();

  // ========================================================================== //
  //                                    State                                   //
  // ========================================================================== //

  address public override administrator;
  address public override pendingAdministrator;
  address internal immutable _hooksFactory;
  /// @notice display name for this hooks instance.
  string public name;
  // credentials are hooks-wide; the market-specific known-lender bit lives below.
  mapping(address => LenderStatus) internal _lenderStatus;
  /// @notice whether a lender permanently passed the entry policy for a given market.
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

  /// @param _administrator initial authority over hooks configuration, not provider credentials.
  constructor(address _administrator) {
    administrator = _administrator;
    _hooksFactory = msg.sender;
  }

  /// @dev stores the instance name, attaches existing providers, then creates any new providers.
  ///      all new providers use the one factory supplied in `inputs`.
  function _initialize(NameAndProviderInputs memory inputs) internal {
    if (inputs.roleProviderFactory == address(0) && inputs.newProviderInputs.length > 0) {
      revert RoleProviderFactoryRequired();
    }
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

  /// @notice compatibility alias for integrations that still call the hooks administrator
  ///         `borrower`.
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

  /// @notice starts or replaces a hooks-administrator transfer.
  /// @dev the target must be a registered borrower now and again when it accepts. pending status
  ///      grants no authority.
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

  /// @notice cancels the pending transfer without changing hooks authority.
  function cancelAdministratorTransfer() external override onlyAdministrator {
    address cancelledPendingAdministrator = pendingAdministrator;
    if (cancelledPendingAdministrator == address(0)) {
      revert NoPendingAdministratorTransfer();
    }
    pendingAdministrator = address(0);
    emit AdministratorTransferCancelled(msg.sender, cancelledPendingAdministrator);
  }

  /// @notice completes a pending transfer and updates the creating factory's administrator index.
  /// @dev only the pending administrator may accept. the factory callback is atomic with the state
  ///      change, so a callback failure rolls the whole transfer back. providers, credentials,
  ///      deposit blocks, known lenders, and hooked-market settings are otherwise unchanged.
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

  /// @notice updates this hooks instance's display name.
  function setName(string calldata _name) external onlyAdministrator {
    string memory previousName = name;
    name = _name;
    emit NameUpdated(msg.sender, previousName, _name);
  }

  // ========================================================================== //
  //                             Provider management                            //
  // ========================================================================== //

  /// @notice deploys a provider through `providerFactory` and attaches it to this hooks instance.
  /// @dev reverts if the factory returns the zero address. the provider factory's interpretation
  ///      of `data` and any authority over the result are outside this contract.
  /// @param timeToLive seconds added to the provider's credential timestamps to determine expiry.
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

  /// @notice attaches a provider or updates its hook-local credential TTL.
  /// @dev a new provider is classified once. only an exact true response from `isPullProvider`
  ///      makes it pull-based; everything else is treated as push-based. updating the TTL does not
  ///      classify it again, and immediately changes the effective expiry of its stored
  ///      credentials. a zero-TTL pull credential is refreshed on every credential check, including
  ///      another one in the same block.
  function addRoleProvider(address providerAddress, uint32 timeToLive) external onlyAdministrator {
    _addRoleProvider(providerAddress, timeToLive);
  }

  function _isPullProvider(address providerAddress) internal view returns (bool isPullProvider) {
    // make this a low-end four-byte number; the Yul shift below moves it into calldata position.
    uint256 selectorWord = uint32(IRoleProvider.isPullProvider.selector);
    assembly {
      // 0x00 is Solidity scratch space. shifting left by 224 bits, or 28 bytes, puts the selector
      // in the first four bytes of that word so staticcall can read it directly from 0x00.
      mstore(0x00, shl(224, selectorWord))

      // staticcall reads those four input bytes before writing up to one return word back over
      // them, so the same scratch word can safely handle both sides of the call.
      let success := staticcall(gas(), providerAddress, 0x00, 0x04, 0x00, 0x20)

      // keep this fail closed. only a successful call with a complete first word containing
      // exactly one makes this a pull provider. reverts, empty or short responses, false, and
      // dirty bools all become push providers; harmless trailing data is ignored.
      //
      // Yul's and evaluates every term, but success and return size still gate the final value.
      // stale scratch data can't turn a failed or short call into true.
      isPullProvider := and(
        success,
        and(iszero(lt(returndatasize(), 0x20)), eq(mload(0x00), 1))
      )
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
      emit RoleProviderAdded(
        administrator,
        providerAddress,
        timeToLive,
        pullProviderIndex,
        pushProviderIndex
      );
    } else {
      // If provider already exists, the only value that can be updated is the TTL
      uint32 previousTimeToLive = provider.timeToLive();
      provider = provider.setTimeToLive(timeToLive);
      uint24 pullProviderIndex = provider.pullProviderIndex();
      uint24 pushProviderIndex = provider.pushProviderIndex();
      if (pullProviderIndex != NullProviderIndex) {
        _pullProviders[pullProviderIndex] = provider;
      } else {
        _pushProviders[pushProviderIndex] = provider;
      }
      emit RoleProviderUpdated(
        administrator,
        providerAddress,
        previousTimeToLive,
        timeToLive,
        pullProviderIndex,
        pullProviderIndex,
        pushProviderIndex,
        pushProviderIndex
      );
    }
    // Update the provider in storage
    _roleProviders[providerAddress] = provider;
  }

  /// @notice stops accepting new or cached credentials from `providerAddress`.
  /// @dev lender records are not rewritten immediately. they become unsupported on the next check.
  ///      the removed provider may still revoke a credential that remains recorded as its grant.
  function removeRoleProvider(address providerAddress) external onlyAdministrator {
    RoleProvider provider = _roleProviders[providerAddress];
    if (provider.isNull()) revert ProviderNotFound();
    // Remove the provider from `_roleProviders`
    _roleProviders[providerAddress] = EmptyRoleProvider;
    emit RoleProviderRemoved(
      administrator,
      providerAddress,
      provider.timeToLive(),
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

  /// @dev swap-removes a pull provider and repairs the moved provider's stored index.
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
      administrator,
      lastProviderAddress,
      lastProvider.timeToLive(),
      lastProvider.timeToLive(),
      uint24(lastIndex),
      indexToRemove,
      NullProviderIndex,
      NullProviderIndex
    );
  }

  /// @dev swap-removes a push provider and repairs the moved provider's stored index.
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
      administrator,
      lastProviderAddress,
      lastProvider.timeToLive(),
      lastProvider.timeToLive(),
      NullProviderIndex,
      NullProviderIndex,
      uint24(lastIndex),
      indexToRemove
    );
  }

  // ========================================================================== //
  //                              Provider queries                              //
  // ========================================================================== //

  /// @notice returns this hook's packed configuration for `providerAddress`.
  function getRoleProvider(address providerAddress) external view returns (RoleProvider) {
    return _roleProviders[providerAddress];
  }

  /// @notice returns providers this hook can query without caller-supplied validation data.
  /// @dev removal uses swap-and-pop, so order and indices are not stable.
  function getPullProviders() external view returns (RoleProvider[] memory) {
    return _pullProviders;
  }

  /// @notice returns providers this hook will not query automatically.
  /// @dev this includes push providers and validation-only providers. removal uses swap-and-pop,
  ///      so order and indices are not stable.
  function getPushProviders() external view returns (RoleProvider[] memory) {
    return _pushProviders;
  }

  // ========================================================================== //
  //                                Role queries                                //
  // ========================================================================== //

  /// @notice returns stored lender status without checking providers or clearing stale state.
  function getPreviousLenderStatus(
    address accountAddress
  ) external view returns (LenderStatus memory status) {
    status = _lenderStatus[accountAddress];
  }

  /// @notice resolves the lender's current status using cached state and pull providers.
  /// @dev this is a view, so a refreshed credential exists only in the returned value. it first
  ///      tries the recorded pull provider, then the remaining pull providers. explicit validation
  ///      data and push providers are not available on this path.
  function getLenderStatus(
    address accountAddress
  ) public view returns (LenderStatus memory status) {
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

  /// @dev answers the transfer hook's recipient-side question without hook data. canonical
  ///      ERC-4626 wrappers use ordinary ERC-20 transfers, so they can't pass credential data
  ///      along.
  function _isMarketTransferRecipientAllowed(
    address market,
    address recipient,
    bool transferRequiresAccess
  ) internal view returns (bool) {
    if (isKnownLenderOnMarket[recipient][market]) return true;
    if (_lenderStatus[recipient].isBlockedFromDeposits) return false;
    if (!transferRequiresAccess) return true;
    return getLenderStatus(recipient).hasCredential();
  }

  // ========================================================================== //
  //                                Role actions                                //
  // ========================================================================== //

  /// @notice lets an attached provider push a timestamped credential for `account`.
  /// @dev the timestamp must be nonzero, no later than now, and unexpired under the provider's
  ///      current TTL. an existing credential can be replaced by its own provider, when its
  ///      recorded provider was removed, or when the new expiry is strictly later. this never
  ///      clears a local deposit block.
  function grantRole(address account, uint32 roleGrantedTimestamp) external {
    RoleProvider callingProvider = _roleProviders[msg.sender];

    if (callingProvider.isNull()) revert ProviderNotFound();

    _grantRole(callingProvider, account, roleGrantedTimestamp);
  }

  /// @notice batch version of `grantRole`; every credential must pass the same checks.
  /// @dev array lengths must match. one failure reverts the whole batch.
  function grantRoles(
    address[] calldata accounts,
    uint32[] calldata roleGrantedTimestamps
  ) external {
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

  /// @notice clears `account`'s credential when called by the provider that granted it.
  /// @dev removal from this hooks instance does not take away that revocation authority.
  function revokeRole(address account) external {
    _revokeRole(account);
  }

  /// @notice batch version of `revokeRole`; caller must have granted every current credential.
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
    address providerAddress = status.lastProvider;
    status.unsetCredential();
    _lenderStatus[account] = status;
    emit AccountAccessRevoked(providerAddress, account, msg.sender);
  }

  /// @notice clears `account`'s credential and blocks deposits wherever this instance's deposit
  ///         callback runs.
  /// @dev known-lender status is not cleared, so the account may retain transfer and withdrawal
  ///      rights that depend on having entered a particular market before.
  function blockFromDeposits(address account) external onlyAdministrator {
    _blockFromDeposits(account);
  }

  /// @notice batch version of `blockFromDeposits`.
  function blockFromDeposits(address[] calldata accounts) external onlyAdministrator {
    for (uint256 i; i < accounts.length; i++) {
      _blockFromDeposits(accounts[i]);
    }
  }

  function _blockFromDeposits(address account) internal {
    LenderStatus memory status = _lenderStatus[account];
    if (status.hasCredential()) {
      address providerAddress = status.lastProvider;
      status.unsetCredential();
      emit AccountAccessRevoked(providerAddress, account, msg.sender);
    }
    status.isBlockedFromDeposits = true;
    _lenderStatus[account] = status;
    emit AccountBlockedFromDeposits(msg.sender, account);
  }

  /// @notice clears the local deposit block without restoring the account's old credential.
  function unblockFromDeposits(address account) external onlyAdministrator {
    LenderStatus memory status = _lenderStatus[account];
    status.isBlockedFromDeposits = false;
    _lenderStatus[account] = status;
    emit AccountUnblockedFromDeposits(msg.sender, account);
  }

  /// @dev asks a known pull provider for a credential and updates `status` in memory on success.
  ///      this helper assumes the caller already checked the provider classification.
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

  /// @dev a zero-TTL pull credential never satisfies a check from cache, including another check
  ///      in the same block. push providers keep timestamp-based behavior because they can't be
  ///      refreshed automatically.
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

  /// @dev calls `validateCredential` on the provider packed into the market call's raw suffix.
  ///      returns false for an unknown provider, a reverted call, or an invalid credential. a
  ///      successful stateful call with short returndata reverts so its side effects can't survive
  ///      without a usable answer.
  ///
  ///      the suffix is a packed provider address followed directly by provider data. it has no
  ///      offset or length word: `abi.encodePacked(provider, validationData)`.
  function _tryValidateCredential(
    LenderStatus memory status,
    address accountAddress,
    bytes calldata hooksData,
    RoleProvider provider
  ) internal returns (bool) {
    uint validateSelector = uint32(IRoleProvider.validateCredential.selector);
    if (provider.isNull()) return false;
    address providerAddress = provider.providerAddress();
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

  /// @dev searches pull providers for a credential, skipping up to two providers already tried.
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

  /// @dev interprets 20 bytes as a pull-provider selection and more than 20 bytes as a provider
  ///      address plus validation data. shorter input is ignored. `status` is updated in memory
  ///      when the selected provider returns a usable credential.
  /// @return validCredential whether hook data produced a valid credential.
  /// @return pullProviderIndexToSkip selected pull-provider index, so later search won't retry it.
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
      validCredential = _tryValidateCredential(status, accountAddress, hooksData, provider);
    }
  }

  /// @dev resolves access in this order: supported cache, hook data, previous pull provider, then
  ///      remaining pull providers. it only mutates `status` in memory, but isn't a view because
  ///      explicit provider validation may change provider state.
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

  /// @dev persists a changed credential and, for successful entry actions, permanently marks the
  ///      account as known on `msg.sender`'s market.
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
          msg.sender,
          status.lastApprovalTimestamp
        );
      } else {
        emit AccountAccessRevoked(
          _lenderStatus[accountAddress].lastProvider,
          accountAddress,
          msg.sender
        );
      }
    }
    // Mark account as a known lender if they have a valid credential, are not
    // already known, and the function counts as a deposit.
    if (
      canSetKnownLender &&
      hasValidCredential &&
      !isKnownLenderOnMarket[accountAddress][msg.sender]
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
    emit AccountAccessGranted(
      provider.providerAddress(),
      accountAddress,
      msg.sender,
      credentialTimestamp
    );
  }
}
