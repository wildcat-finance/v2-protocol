// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // BaseAccessControls
//  \ ^ /   Hooks authority, providers, credentials, and lender access.
//    V
//
//  SETUP
//  constructor(...)
//  _initialize(...)
//
//  ADMINISTRATOR AUTHORITY
//  onlyAdministrator()
//  requestAdministratorTransfer(...)
//  acceptAdministratorTransfer()
//  cancelAdministratorTransfer()
//  _validateAdministratorTransferTarget(...)
//  borrower()
//
//  INSTANCE METADATA
//  setName(...)
//
//  PROVIDER ATTACHMENT
//  createRoleProvider(...)
//  _createRoleProvider(...)
//  addRoleProvider(...)
//  _addRoleProvider(...)
//  _isPullProvider(...)
//
//  PROVIDER REMOVAL
//  removeRoleProvider(...)
//  _removeProviderFromList(...)
//
//  PROVIDER QUERIES
//  getRoleProvider(...)
//  getPullProviders()
//  getPushProviders()
//
//  CREDENTIAL GRANTS
//  grantRole(...)
//  grantRoles(...)
//  _grantRole(...)
//  _setCredentialAndEmitAccessGranted(...)
//
//  CREDENTIAL REVOCATION
//  revokeRole(...)
//  revokeRoles(...)
//  _revokeRole(...)
//
//  DEPOSIT BLOCKS
//  blockFromDeposits(...)
//  blockFromDeposits(...)
//  _blockFromDeposits(...)
//  unblockFromDeposits(...)
//
//  CREDENTIAL RESOLUTION
//  getLenderStatus(...)
//  getPreviousLenderStatus(...)
//  _tryValidateAccess(...)
//  _tryValidateAccessInner(...)
//  _canUseCachedCredential(...)
//  _handleHooksData(...)
//  _readAddress(...)
//  _tryValidateCredential(...)
//  _loopTryGetCredential(...)
//  _tryGetCredential(...)
//  _writeLenderStatus(...)
//
//  TRANSFER POLICY
//  _isMarketTransferRecipientAllowed(...)
//  _isRegisteredWrapper(...)
// ═════

import '../libraries/BoolUtils.sol';
import '../types/RoleProvider.sol';
import '../types/LenderStatus.sol';
import './IRoleProvider.sol';
import './ProviderStructs.sol';
import './IRoleProviderFactory.sol';
import './IHooksAdministrator.sol';
import '../interfaces/IWildcatArchController.sol';

using BoolUtils for bool;

// ┌─ BaseAccessControls ───────────────────────────────────────────────────────
/// @notice shared provider, credential, and lender-policy state for built-in access hooks.
///
/// @dev provider attachments and lender credentials belong to the hooks instance, which may serve
///      several markets. known-lender status is permanent and scoped to one lender and market.
///      the hooks administrator manages attachments and local deposit blocks; that authority does
///      not make the administrator a credential provider.
contract BaseAccessControls is IHooksAdministrator {
  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

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
  event AccountBlockedFromDeposits(address indexed administrator, address indexed accountAddress);

  /// @notice emitted when the administrator removes an account's deposit block.
  event AccountUnblockedFromDeposits(address indexed administrator, address indexed accountAddress);

  /// @notice emitted when this hooks instance stores a new lender credential.
  event AccountAccessGranted(
    address indexed providerAddress,
    address indexed accountAddress,
    address indexed caller,
    uint32 credentialTimestamp
  );

  /// @notice emitted when this hooks instance clears a stored lender credential.
  event AccountAccessRevoked(address indexed providerAddress, address indexed accountAddress, address indexed caller);

  /// @notice emitted the first time an account becomes known on a market.
  ///
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
  event AdministratorTransferCancelled(address indexed administrator, address indexed cancelledPendingAdministrator);

  /// @notice emitted when the pending administrator accepts authority.
  event AdministratorTransferred(address indexed previousAdministrator, address indexed newAdministrator);

  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

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

  // ░░▒▒▓▓██ [ STATE ] ────────────────────────────────────────────────────────

  bytes4 internal constant RegisteredWrapperSelector = bytes4(keccak256('registeredWrapper()'));
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

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  /// @param _administrator initial authority over hooks configuration, not provider credentials.
  constructor(address _administrator) {
    administrator = _administrator;
    _hooksFactory = msg.sender;
  }

  // ┌─ _initialize ─────
  /// @dev store the instance name, attach existing providers, then create any new providers.
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
          providerFactory, createProviderInputs.timeToLive, createProviderInputs.providerFactoryCalldata
        );
      }
    }
  }

  // ░░▒▒▓▓██ [ ADMINISTRATOR AUTHORITY ] ──────────────────────────────────────

  // ┌─ onlyAdministrator ─────
  modifier onlyAdministrator() {
    if (msg.sender != administrator) revert CallerNotAdministrator();
    _;
  }

  // ┌─ requestAdministratorTransfer ─────
  /// @notice start or replace a hooks-administrator transfer.
  ///
  /// @dev the target must be a registered borrower now and again when it accepts. pending status
  ///      grants no authority.
  function requestAdministratorTransfer(address newAdministrator) external override onlyAdministrator {
    _validateAdministratorTransferTarget(newAdministrator);
    address previousPendingAdministrator = pendingAdministrator;
    pendingAdministrator = newAdministrator;
    emit AdministratorTransferRequested(msg.sender, previousPendingAdministrator, newAdministrator);
  }

  // ┌─ acceptAdministratorTransfer ─────
  /// @notice complete a pending transfer and update the creating factory's administrator index.
  ///
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

    IHooksFactoryAdministratorCallback(_hooksFactory)
      .onHooksAdministratorTransferred(previousAdministrator, newAdministrator);
  }

  // ┌─ cancelAdministratorTransfer ─────
  /// @notice cancel the pending transfer without changing hooks authority.
  function cancelAdministratorTransfer() external override onlyAdministrator {
    address cancelledPendingAdministrator = pendingAdministrator;
    if (cancelledPendingAdministrator == address(0)) {
      revert NoPendingAdministratorTransfer();
    }
    pendingAdministrator = address(0);
    emit AdministratorTransferCancelled(msg.sender, cancelledPendingAdministrator);
  }

  // ┌─ _validateAdministratorTransferTarget ─────
  function _validateAdministratorTransferTarget(address newAdministrator) internal view {
    if (newAdministrator == address(0) || newAdministrator == administrator) {
      revert InvalidAdministratorTransferTarget();
    }
    address archController = IHooksFactoryAdministratorCallback(_hooksFactory).archController();
    if (!IWildcatArchController(archController).isRegisteredBorrower(newAdministrator)) {
      revert AdministratorNotRegistered();
    }
  }

  // ┌─ borrower ─────
  /// @notice compatibility alias for integrations that still call the hooks administrator
  ///         `borrower`.
  function borrower() external view returns (address) {
    return administrator;
  }

  // ░░▒▒▓▓██ [ INSTANCE METADATA ] ────────────────────────────────────────────

  // ┌─ setName ─────
  /// @notice update this hooks instance's display name.
  function setName(string calldata _name) external onlyAdministrator {
    string memory previousName = name;
    name = _name;
    emit NameUpdated(msg.sender, previousName, _name);
  }

  // ░░▒▒▓▓██ [ PROVIDER ATTACHMENT ] ──────────────────────────────────────────

  // ┌─ createRoleProvider ─────
  /// @notice deploy a provider through `providerFactory` and attach it to this hooks instance.
  ///
  /// @dev reverts if the factory returns the zero address. the provider factory's interpretation
  ///      of `data` and any authority over the result are outside this contract.
  ///
  /// @param timeToLive seconds added to the provider's credential timestamps to determine expiry.
  function createRoleProvider(
    address providerFactory,
    uint32 timeToLive,
    bytes memory data
  )
    external
    onlyAdministrator
  {
    _createRoleProvider(IRoleProviderFactory(providerFactory), timeToLive, data);
  }

  // ┌─ _createRoleProvider ─────
  function _createRoleProvider(IRoleProviderFactory providerFactory, uint32 timeToLive, bytes memory data) internal {
    address providerAddress = providerFactory.createRoleProvider(data);
    if (providerAddress == address(0)) revert CreateRoleProviderFailed();
    _addRoleProvider(providerAddress, timeToLive);
  }

  // ┌─ addRoleProvider ─────
  /// @notice attach a provider or update its hook-local credential TTL.
  ///
  /// @dev a new provider is classified once. only an exact true response from `isPullProvider`
  ///      makes it pull-based; everything else is treated as push-based. updating the TTL does not
  ///      classify it again, and immediately changes the effective expiry of its stored
  ///      credentials. a zero-TTL pull credential is refreshed on every credential check, including
  ///      another one in the same block.
  function addRoleProvider(address providerAddress, uint32 timeToLive) external onlyAdministrator {
    _addRoleProvider(providerAddress, timeToLive);
  }

  // ┌─ _addRoleProvider ─────
  function _addRoleProvider(address providerAddress, uint32 timeToLive) internal {
    RoleProvider provider = _roleProviders[providerAddress];
    if (provider.isNull()) {
      bool isPullProvider = _isPullProvider(providerAddress);
      (uint24 pullProviderIndex, uint24 pushProviderIndex) = isPullProvider
        ? (uint24(_pullProviders.length), NullProviderIndex)
        : (NullProviderIndex, uint24(_pushProviders.length));
      // `NullProviderIndex` (max uint24) means this provider can't refresh credentials.
      provider = encodeRoleProvider(timeToLive, providerAddress, pullProviderIndex, pushProviderIndex);
      if (isPullProvider) {
        _pullProviders.push(provider);
      } else {
        _pushProviders.push(provider);
      }
      emit RoleProviderAdded(administrator, providerAddress, timeToLive, pullProviderIndex, pushProviderIndex);
    } else {
      // attachment fixes the provider type; only TTL can change.
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
    _roleProviders[providerAddress] = provider;
  }

  // ┌─ _isPullProvider ─────
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
      isPullProvider := and(success, and(iszero(lt(returndatasize(), 0x20)), eq(mload(0x00), 1)))
    }
  }

  // ░░▒▒▓▓██ [ PROVIDER REMOVAL ] ─────────────────────────────────────────────

  // ┌─ removeRoleProvider ─────
  /// @notice stop accepting new or cached credentials from `providerAddress`.
  ///
  /// @dev lender records are not rewritten immediately. they become unsupported on the next check.
  ///      the removed provider may still revoke a credential that remains recorded as its grant.
  function removeRoleProvider(address providerAddress) external onlyAdministrator {
    RoleProvider provider = _roleProviders[providerAddress];
    if (provider.isNull()) revert ProviderNotFound();
    _roleProviders[providerAddress] = EmptyRoleProvider;
    emit RoleProviderRemoved(
      administrator,
      providerAddress,
      provider.timeToLive(),
      provider.pullProviderIndex(),
      provider.pushProviderIndex()
    );
    _removeProviderFromList(provider);
  }

  // ┌─ _removeProviderFromList ─────
  /// @dev swap-remove a provider and repair the moved provider's packed index and registry entry.
  function _removeProviderFromList(RoleProvider provider) internal {
    bool isPull = provider.isPullProvider();
    RoleProvider[] storage providers = isPull ? _pullProviders : _pushProviders;
    uint24 indexToRemove = isPull ? provider.pullProviderIndex() : provider.pushProviderIndex();
    uint256 lastIndex = providers.length - 1;
    if (indexToRemove == lastIndex) {
      providers.pop();
      return;
    }
    RoleProvider lastProvider = providers[lastIndex];
    lastProvider =
      isPull ? lastProvider.setPullProviderIndex(indexToRemove) : lastProvider.setPushProviderIndex(indexToRemove);
    providers[indexToRemove] = lastProvider;
    providers.pop();
    address lastProviderAddress = lastProvider.providerAddress();
    _roleProviders[lastProviderAddress] = lastProvider;
    emit RoleProviderUpdated(
      administrator,
      lastProviderAddress,
      lastProvider.timeToLive(),
      lastProvider.timeToLive(),
      isPull ? uint24(lastIndex) : NullProviderIndex,
      isPull ? indexToRemove : NullProviderIndex,
      isPull ? NullProviderIndex : uint24(lastIndex),
      isPull ? NullProviderIndex : indexToRemove
    );
  }

  // ░░▒▒▓▓██ [ PROVIDER QUERIES ] ─────────────────────────────────────────────

  // ┌─ getRoleProvider ─────
  /// @notice return this hook's packed configuration for `providerAddress`.
  function getRoleProvider(address providerAddress) external view returns (RoleProvider) {
    return _roleProviders[providerAddress];
  }

  // ┌─ getPullProviders ─────
  /// @notice return providers this hook can query without caller-supplied validation data.
  ///
  /// @dev removal uses swap-and-pop, so order and indices are not stable.
  function getPullProviders() external view returns (RoleProvider[] memory) {
    return _pullProviders;
  }

  // ┌─ getPushProviders ─────
  /// @notice return providers this hook will not query automatically.
  ///
  /// @dev this includes push providers and validation-only providers. removal uses swap-and-pop,
  ///      so order and indices are not stable.
  function getPushProviders() external view returns (RoleProvider[] memory) {
    return _pushProviders;
  }

  // ░░▒▒▓▓██ [ CREDENTIAL GRANTS ] ────────────────────────────────────────────

  // ┌─ grantRole ─────
  /// @notice let an attached provider push a timestamped credential for `account`.
  ///
  /// @dev the timestamp must be nonzero, no later than now, and unexpired under the provider's
  ///      current TTL. an existing credential can be replaced by its own provider, when its
  ///      recorded provider was removed, or when the new expiry is strictly later. this never
  ///      clears a local deposit block.
  function grantRole(address account, uint32 roleGrantedTimestamp) external {
    RoleProvider callingProvider = _roleProviders[msg.sender];

    if (callingProvider.isNull()) revert ProviderNotFound();

    _grantRole(callingProvider, account, roleGrantedTimestamp);
  }

  // ┌─ grantRoles ─────
  /// @notice grant credentials in a batch; every credential must pass the same checks.
  ///
  /// @dev array lengths must match. one failure reverts the whole batch.
  function grantRoles(address[] calldata accounts, uint32[] calldata roleGrantedTimestamps) external {
    RoleProvider callingProvider = _roleProviders[msg.sender];

    if (callingProvider.isNull()) revert ProviderNotFound();

    if (accounts.length != roleGrantedTimestamps.length) revert InvalidArrayLength();
    for (uint256 i = 0; i < accounts.length; i++) {
      _grantRole(callingProvider, accounts[i], roleGrantedTimestamps[i]);
    }
  }

  // ┌─ _grantRole ─────
  function _grantRole(RoleProvider callingProvider, address account, uint32 roleGrantedTimestamp) internal {
    LenderStatus memory status = _lenderStatus[account];

    if (roleGrantedTimestamp == 0 || roleGrantedTimestamp > block.timestamp) {
      revert InvalidCredentialTimestamp();
    }

    uint256 newExpiry = callingProvider.calculateExpiry(roleGrantedTimestamp);

    if (newExpiry < block.timestamp) revert GrantedCredentialExpired();

    if (status.hasCredential()) {
      RoleProvider lastProvider = _roleProviders[status.lastProvider];

      if (!lastProvider.isNull()) {
        uint256 oldExpiry = lastProvider.calculateExpiry(status.lastApprovalTimestamp);

        // replacing another attached provider's credential requires a strictly later expiry.
        if (!((status.lastProvider == msg.sender).or(newExpiry > oldExpiry))) {
          revert ProviderCanNotReplaceCredential();
        }
      }
    }

    _setCredentialAndEmitAccessGranted(status, callingProvider, account, roleGrantedTimestamp);
  }

  // ┌─ _setCredentialAndEmitAccessGranted ─────
  function _setCredentialAndEmitAccessGranted(
    LenderStatus memory status,
    RoleProvider provider,
    address accountAddress,
    uint32 credentialTimestamp
  )
    internal
  {
    status.setCredential(provider, credentialTimestamp);
    _lenderStatus[accountAddress] = status;
    emit AccountAccessGranted(provider.providerAddress(), accountAddress, msg.sender, credentialTimestamp);
  }

  // ░░▒▒▓▓██ [ CREDENTIAL REVOCATION ] ────────────────────────────────────────

  // ┌─ revokeRole ─────
  /// @notice clear `account`'s credential when called by the provider that granted it.
  ///
  /// @dev removal from this hooks instance does not take away that revocation authority.
  function revokeRole(address account) external {
    _revokeRole(account);
  }

  // ┌─ revokeRoles ─────
  /// @notice revoke credentials in a batch; the caller must have granted every current credential.
  function revokeRoles(address[] calldata accounts) external {
    for (uint256 i = 0; i < accounts.length; i++) {
      _revokeRole(accounts[i]);
    }
  }

  // ┌─ _revokeRole ─────
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

  // ░░▒▒▓▓██ [ DEPOSIT BLOCKS ] ───────────────────────────────────────────────

  // ┌─ blockFromDeposits ─────
  /// @notice clear `account`'s credential and block deposits wherever this instance's deposit
  ///         callback runs.
  ///
  /// @dev known-lender status is not cleared, so the account may retain transfer and withdrawal
  ///      rights that depend on having entered a particular market before.
  function blockFromDeposits(address account) external onlyAdministrator {
    _blockFromDeposits(account);
  }

  // ┌─ blockFromDeposits ─────
  /// @notice block deposits for a batch of accounts.
  function blockFromDeposits(address[] calldata accounts) external onlyAdministrator {
    for (uint256 i; i < accounts.length; i++) {
      _blockFromDeposits(accounts[i]);
    }
  }

  // ┌─ _blockFromDeposits ─────
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

  // ┌─ unblockFromDeposits ─────
  /// @notice clear the local deposit block without restoring the account's old credential.
  function unblockFromDeposits(address account) external onlyAdministrator {
    LenderStatus memory status = _lenderStatus[account];
    status.isBlockedFromDeposits = false;
    _lenderStatus[account] = status;
    emit AccountUnblockedFromDeposits(msg.sender, account);
  }

  // ░░▒▒▓▓██ [ CREDENTIAL RESOLUTION ] ────────────────────────────────────────

  // ┌─ getLenderStatus ─────
  /// @notice resolve the lender's current status using cached state and pull providers.
  ///
  /// @dev this is a view, so a refreshed credential exists only in the returned value. it first
  ///      tries the recorded pull provider, then the remaining pull providers. explicit validation
  ///      data and push providers are not available on this path.
  function getLenderStatus(address accountAddress) public view returns (LenderStatus memory status) {
    status = _lenderStatus[accountAddress];

    uint256 previousPullProviderIndexToSkip = type(uint256).max;

    if (status.lastApprovalTimestamp > 0) {
      RoleProvider provider = _roleProviders[status.lastProvider];
      if (!provider.isNull()) {
        if (_canUseCachedCredential(status, provider)) return status;

        // expired and zero-TTL pull credentials need a fresh provider check.
        if (status.canRefresh) {
          if (_tryGetCredential(status, provider, accountAddress)) {
            return status;
          }
          // don't retry this provider in the fallback search.
          previousPullProviderIndexToSkip = provider.pullProviderIndex();
        }
      }
      status.unsetCredential();
    }

    if (_loopTryGetCredential(status, accountAddress, previousPullProviderIndexToSkip, type(uint256).max)) {
      return status;
    }
  }

  // ┌─ getPreviousLenderStatus ─────
  /// @notice return stored lender status without checking providers or clearing stale state.
  function getPreviousLenderStatus(address accountAddress) external view returns (LenderStatus memory status) {
    status = _lenderStatus[accountAddress];
  }

  // ┌─ _tryValidateAccess ─────
  function _tryValidateAccess(
    LenderStatus memory status,
    address accountAddress,
    bytes calldata hooksData
  )
    internal
    returns (bool hasValidCredential)
  {
    bool wasUpdated;
    (hasValidCredential, wasUpdated) = _tryValidateAccessInner(status, accountAddress, hooksData);
    _writeLenderStatus(status, accountAddress, hasValidCredential, wasUpdated, false);
  }

  // ┌─ _tryValidateAccessInner ─────
  /// @dev resolves access in this order: supported cache, hook data, previous pull provider, then
  ///      remaining pull providers. it only mutates `status` in memory, but isn't a view because
  ///      explicit provider validation may change provider state.
  function _tryValidateAccessInner(
    LenderStatus memory status,
    address accountAddress,
    bytes calldata hooksData
  )
    internal
    returns (bool hasValidCredential, bool wasUpdated)
  {
    RoleProvider lastProvider = status.hasCredential() ? _roleProviders[status.lastProvider] : EmptyRoleProvider;

    // only supported, cacheable credentials bypass provider calls.
    if (!lastProvider.isNull() && _canUseCachedCredential(status, lastProvider)) {
      return (true, false);
    }

    (bool validCredential, uint256 hooksDataPullProviderIndexToSkip) =
      _handleHooksData(status, accountAddress, hooksData);

    if (validCredential) {
      return (true, true);
    }

    uint256 previousPullProviderIndexToSkip = type(uint256).max;

    // try the recorded pull provider before the fallback search.
    if (!lastProvider.isNull() && status.canRefresh) {
      if (_tryGetCredential(status, lastProvider, accountAddress)) {
        return (true, true);
      }
      // don't retry this provider in the fallback search.
      previousPullProviderIndexToSkip = lastProvider.pullProviderIndex();
    }

    if (_loopTryGetCredential(
        status, accountAddress, previousPullProviderIndexToSkip, hooksDataPullProviderIndexToSkip
      )) {
      return (true, true);
    }

    if (status.hasCredential()) {
      status.unsetCredential();
      wasUpdated = true;
    }
  }

  // ┌─ _canUseCachedCredential ─────
  /// @dev a zero-TTL pull credential never satisfies a check from cache, including another check
  ///      in the same block. push providers keep timestamp-based behavior because they can't be
  ///      refreshed automatically.
  function _canUseCachedCredential(LenderStatus memory status, RoleProvider provider) internal view returns (bool) {
    if (provider.isPullProvider() && provider.timeToLive() == 0) return false;
    return status.credentialNotExpired(provider);
  }

  // ┌─ _handleHooksData ─────
  /// @dev interprets 20 bytes as a pull-provider selection and more than 20 bytes as a provider
  ///      address plus validation data. shorter input is ignored. `status` is updated in memory
  ///      when the selected provider returns a usable credential.
  ///
  /// @return validCredential whether hook data produced a valid credential.
  /// @return pullProviderIndexToSkip selected pull-provider index, so later search won't retry it.
  function _handleHooksData(
    LenderStatus memory status,
    address accountAddress,
    bytes calldata hooksData
  )
    internal
    returns (bool validCredential, uint256 pullProviderIndexToSkip)
  {
    pullProviderIndexToSkip = type(uint256).max;
    if (hooksData.length == 20) {
      // an address alone selects an attached pull provider.
      address providerAddress = _readAddress(hooksData);
      RoleProvider provider = _roleProviders[providerAddress];
      if (!provider.isNull() && provider.isPullProvider()) {
        pullProviderIndexToSkip = provider.pullProviderIndex();
        validCredential = _tryGetCredential(status, provider, accountAddress);
      }
    } else if (hooksData.length > 20) {
      // additional bytes select stateful validation, including push providers.
      address providerAddress = _readAddress(hooksData);
      RoleProvider provider = _roleProviders[providerAddress];
      if (!provider.isNull() && provider.isPullProvider()) {
        pullProviderIndexToSkip = provider.pullProviderIndex();
      }
      validCredential = _tryValidateCredential(status, accountAddress, hooksData, provider);
    }
  }

  // ┌─ _readAddress ─────
  function _readAddress(bytes calldata hooksData) internal pure returns (address providerAddress) {
    assembly {
      providerAddress := shr(96, calldataload(hooksData.offset))
    }
  }

  // ┌─ _tryValidateCredential ─────
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
  )
    internal
    returns (bool)
  {
    uint validateSelector = uint32(IRoleProvider.validateCredential.selector);
    if (provider.isNull()) return false;
    address providerAddress = provider.providerAddress();
    uint credentialTimestamp;
    uint invalidCredentialReturnedSelector = uint32(InvalidCredentialReturned.selector);
    assembly {
      let validateDataCalldataPointer := add(hooksData.offset, 0x14)
      let calldataPointer := mload(0x40)
      // the right-aligned selector makes calldata start at calldataPointer + 28.
      mstore(calldataPointer, validateSelector)
      mstore(add(calldataPointer, 0x20), accountAddress)
      mstore(add(calldataPointer, 0x40), 0x40)
      let dataLength := sub(hooksData.length, 0x14)
      mstore(add(calldataPointer, 0x60), dataLength)
      calldatacopy(add(calldataPointer, 0x80), validateDataCalldataPointer, dataLength)
      if call(gas(), providerAddress, 0, add(calldataPointer, 0x1c), add(dataLength, 0x64), 0, 0x20) {
        switch lt(returndatasize(), 0x20)
        case 1 {
          // don't keep provider side effects without a usable credential response.
          mstore(0, invalidCredentialReturnedSelector)
          revert(0x1c, 0x04)
        }
        default {
          // only the low uint32 is the credential timestamp.
          credentialTimestamp := and(mload(0), 0xffffffff)
        }
      }
    }
    if (credentialTimestamp == 0 || credentialTimestamp > block.timestamp) {
      return false;
    }
    if (provider.calculateExpiry(credentialTimestamp) >= block.timestamp) {
      status.setCredential(provider, credentialTimestamp);
      return true;
    }
  }

  // ┌─ _loopTryGetCredential ─────
  /// @dev searches pull providers for a credential, skipping up to two providers already tried.
  function _loopTryGetCredential(
    LenderStatus memory status,
    address accountAddress,
    uint256 previousPullProviderIndexToSkip,
    uint256 hooksDataPullProviderIndexToSkip
  )
    internal
    view
    returns (bool foundCredential)
  {
    uint256 providerCount = _pullProviders.length;
    for (uint256 i = 0; i < providerCount; i++) {
      if (i == previousPullProviderIndexToSkip || i == hooksDataPullProviderIndexToSkip) continue;
      RoleProvider provider = _pullProviders[i];
      if (_tryGetCredential(status, provider, accountAddress)) return (true);
    }
  }

  // ┌─ _tryGetCredential ─────
  /// @dev asks a known pull provider for a credential and updates `status` in memory on success.
  ///      this helper assumes the caller already checked the provider classification.
  function _tryGetCredential(
    LenderStatus memory status,
    RoleProvider provider,
    address accountAddress
  )
    internal
    view
    returns (bool isApproved)
  {
    address providerAddress = provider.providerAddress();

    uint32 credentialTimestamp;
    uint getCredentialSelector = uint32(IRoleProvider.getCredential.selector);
    assembly {
      mstore(0x00, getCredentialSelector)
      mstore(0x20, accountAddress)
      if and(gt(returndatasize(), 0x1f), staticcall(gas(), providerAddress, 0x1c, 0x24, 0, 0x20)) {
        // only the low uint32 is the credential timestamp.
        credentialTimestamp := and(mload(0), 0xffffffff)
      }
    }

    if (credentialTimestamp == 0 || credentialTimestamp > block.timestamp) {
      return false;
    }

    if (provider.calculateExpiry(credentialTimestamp) >= block.timestamp) {
      status.setCredential(provider, credentialTimestamp);
      return true;
    }
  }

  // ┌─ _writeLenderStatus ─────
  /// @dev persists a changed credential and, for successful entry actions, permanently marks the
  ///      account as known on `msg.sender`'s market.
  function _writeLenderStatus(
    LenderStatus memory status,
    address accountAddress,
    bool hasValidCredential,
    bool wasUpdated,
    bool canSetKnownLender
  )
    internal
  {
    if (wasUpdated) {
      if (hasValidCredential) {
        emit AccountAccessGranted(status.lastProvider, accountAddress, msg.sender, status.lastApprovalTimestamp);
      } else {
        emit AccountAccessRevoked(_lenderStatus[accountAddress].lastProvider, accountAddress, msg.sender);
      }
    }
    // only entry actions make a lender known; queueing alone doesn't.
    if (canSetKnownLender && hasValidCredential && !isKnownLenderOnMarket[accountAddress][msg.sender]) {
      isKnownLenderOnMarket[accountAddress][msg.sender] = true;
      emit AccountMadeFirstDeposit(msg.sender, accountAddress);
    }

    if (wasUpdated) _lenderStatus[accountAddress] = status;
  }

  // ░░▒▒▓▓██ [ TRANSFER POLICY ] ──────────────────────────────────────────────

  // ┌─ _isMarketTransferRecipientAllowed ─────
  /// @dev answers the transfer hook's recipient-side question without hook data. the market's
  ///      registered wrapper is protocol-allowed because wrapper entry uses an ordinary ERC-20
  ///      transfer that cannot carry credential data.
  function _isMarketTransferRecipientAllowed(
    address market,
    address recipient,
    bool transferRequiresAccess
  )
    internal
    view
    returns (bool)
  {
    if (isKnownLenderOnMarket[recipient][market]) return true;
    if (_isRegisteredWrapper(market, recipient)) return true;
    if (_lenderStatus[recipient].isBlockedFromDeposits) return false;
    if (!transferRequiresAccess) return true;
    return getLenderStatus(recipient).hasCredential();
  }

  // ┌─ _isRegisteredWrapper ─────
  /// @dev returns whether `recipient` is the market's nonzero canonical wrapper. a failed or
  ///      malformed market query is not an exemption, so the ordinary recipient policy applies.
  function _isRegisteredWrapper(address market, address recipient) internal view returns (bool isRegisteredWrapper) {
    if (recipient == address(0)) return false;

    uint256 selectorWord = uint32(RegisteredWrapperSelector);
    assembly ('memory-safe') {
      // borrow the free-memory pointer for four bytes of input and one return word. nothing
      // survives this block, so leave 0x40 alone.
      let pointer := mload(0x40)

      // mstore right-aligns selectorWord. +0x1c skips its 28 leading zero bytes, giving the call
      // exactly the four-byte registeredWrapper() selector. copy at most one return word back.
      mstore(pointer, selectorWord)
      let success := staticcall(gas(), market, add(pointer, 0x1c), 0x04, pointer, 0x20)

      // a revert, codeless target, or short response does not earn an exemption. comparing the
      // whole word to recipient also rejects dirty address padding, just like Solidity's decoder.
      isRegisteredWrapper := and(success, and(iszero(lt(returndatasize(), 0x20)), eq(mload(pointer), recipient)))
    }
  }
}
