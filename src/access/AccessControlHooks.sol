// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import '../libraries/BoolUtils.sol';
import '../libraries/MathUtils.sol';
import '../types/RoleProvider.sol';
import '../types/LenderStatus.sol';
import './IRoleProvider.sol';
import './ConstrainDeployParameters.sol';

using BoolUtils for bool;
using MathUtils for uint256;

// @todo custom error types
// @todo events

/**
 * @title AccessControlHooks
 * @dev Hooks contract for wildcat markets. Restricts access to deposits
 *      to accounts that have credentials from approved role providers, or
 *      which are manually approved by the borrower.
 *
 *      Withdrawals are restricted in the same way for users that have not
 *      made a deposit, while users who have made a deposit at any point
 *      remain approved even if they are later removed.
 *
 *      Deposit access may be canceled by the borrower.
 */
contract AccessControlHooks is ConstrainDeployParameters {
  // ========================================================================== //
  //                                   Events                                   //
  // ========================================================================== //

  event RoleProviderUpdated(
    address indexed providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex
  );
  event RoleProviderAdded(
    address indexed providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex
  );
  event RoleProviderRemoved(address indexed providerAddress, uint24 pullProviderIndex);
  event AccountBlockedFromDeposits(address indexed accountAddress);
  event AccountUnblockedFromDeposits(address indexed accountAddress);
  event AccountAccessGranted(
    address indexed providerAddress,
    address indexed accountAddress,
    uint32 credentialTimestamp
  );
  event AccountAccessRevoked(address indexed providerAddress, address indexed accountAddress);

  // ========================================================================== //
  //                                   Errors                                   //
  // ========================================================================== //

  error CallerNotBorrower();
  error ProviderNotFound();
  error ProviderCanNotReplaceCredential();
  /// @dev Error thrown when a provider grants a credential that is already expired.
  error GrantedCredentialExpired();
  /// @dev Error thrown when a provider is called to validate a credential and the
  ///      returndata can not be decoded as a uint.
  error InvalidCredentialReturned();

  // ========================================================================== //
  //                                    State                                   //
  // ========================================================================== //

  address public immutable borrower;

  mapping(address => LenderStatus) internal _lenderStatus;
  // Provider data is duplicated in the array and mapping to allow
  // push providers to update in a single step and pull providers to
  // be looped over without having to access the mapping.
  RoleProvider[] internal _pullProviders;
  mapping(address => RoleProvider) internal _roleProviders;

  HooksConfig public immutable override config;

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  /**
   * @param _deployer Address of the account that called the factory.
   * @param restrictedFunctions Configuration specifying which functions to apply
   *                            access controls to.
   */
  constructor(address _deployer, HooksConfig restrictedFunctions) IHooks() {
    borrower = _deployer;
    // Allow deployer to grant roles with no expiry
    _roleProviders[_deployer] = encodeRoleProvider(
      type(uint32).max,
      _deployer,
      NotPullProviderIndex
    );
    config = encodeHooksConfig({
      hooksAddress: address(this),
      useOnDeposit: restrictedFunctions.useOnDeposit(),
      useOnQueueWithdrawal: restrictedFunctions.useOnQueueWithdrawal(),
      useOnExecuteWithdrawal: restrictedFunctions.useOnExecuteWithdrawal(),
      useOnTransfer: restrictedFunctions.useOnTransfer(),
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
      useOnAssetsSentToEscrow: false,
      useOnSetMaxTotalSupply: false,
      useOnSetAnnualInterestBips: false
    });
  }

  function version() external pure override returns (string memory) {
    return 'SingleBorrowerAccessControlHooks';
  }

  /**
   * @dev Called when market is deployed using this contract as its `hooks`.
   *
   *      Note: Called inside the root `onCreateMarket` in the base contract,
   *      so no need to verify the caller is the factory.
   */
  function _onCreateMarket(
    MarketParameters calldata parameters,
    bytes calldata extraData
  ) internal override {
    if (msg.sender != borrower) revert CallerNotBorrower();
    // Validate the deploy parameters
    super._onCreateMarket(parameters, extraData);
  }

  // ========================================================================== //
  //                             Provider management                            //
  // ========================================================================== //

  /**
   * @dev Adds or updates a role provider that is able to grant user access.
   *      If it is not already approved, it is added to `_roleProviders` and,
   *      if the provider can refresh credentials, added to `pullProviders`.
   *      If the provider is already approved, only updates `timeToLive`.
   */
  function addRoleProvider(address providerAddress, uint32 timeToLive) external {
    RoleProvider provider = _roleProviders[providerAddress];
    if (provider.isNull()) {
      bool isPullProvider = IRoleProvider(providerAddress).isPullProvider();
      // Role providers that are not pull providers have `pullProviderIndex` set to
      // `NotPullProviderIndex` (max uint24) to indicate they do not refresh credentials.
      provider = encodeRoleProvider(
        timeToLive,
        providerAddress,
        isPullProvider ? uint24(_pullProviders.length) : NotPullProviderIndex
      );
      if (isPullProvider) {
        _pullProviders.push(provider);
      }
      emit RoleProviderAdded(providerAddress, timeToLive, provider.pullProviderIndex());
    } else {
      // If provider already exists, the only value that can be updated is the TTL
      provider = provider.setTimeToLive(timeToLive);
      uint24 pullProviderIndex = provider.pullProviderIndex();
      if (pullProviderIndex != NotPullProviderIndex) {
        _pullProviders[pullProviderIndex] = provider;
      }
      emit RoleProviderUpdated(providerAddress, timeToLive, pullProviderIndex);
    }
    // Update the provider in storage
    _roleProviders[providerAddress] = provider;
  }

  /**
   * @dev Removes a role provider from the `_roleProviders` mapping and, if it is a
   *      pull provider, from the `_pullProviders` array.
   */
  function removeRoleProvider(address providerAddress) external {
    RoleProvider provider = _roleProviders[providerAddress];
    if (provider.isNull()) revert ProviderNotFound();
    // Remove the provider from `_roleProviders`
    _roleProviders[providerAddress] = EmptyRoleProvider;
    emit RoleProviderRemoved(providerAddress, provider.pullProviderIndex());
    // If the provider is a pull provider, remove it from `_pullProviders`
    if (provider.isPullProvider()) {
      _removePullProvider(provider.pullProviderIndex());
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
    emit RoleProviderUpdated(lastProviderAddress, lastProvider.timeToLive(), indexToRemove);
  }

  // ========================================================================== //
  //                              Provider queries                              //
  // ========================================================================== //

  function getRoleProvider(address providerAddress) external view returns (RoleProvider) {
    return _roleProviders[providerAddress];
  }

  function getPullProviders() external view returns (RoleProvider[] memory) {
    return _pullProviders;
  }

  // ========================================================================== //
  //                                Role queries                                //
  // ========================================================================== //

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

    uint256 pullProviderIndexToSkip;

    // Check if user has an existing credential
    if (status.lastApprovalTimestamp > 0) {
      RoleProvider provider = _roleProviders[status.lastProvider];
      if (!provider.isNull()) {
        // If credential is not expired and the provider is still
        // supported, the lender has a valid credential.
        if (status.hasActiveCredential(provider)) return status;

        // If credential is expired but the provider is still supported and
        // allows refreshing (i.e. it's a pull provider), try to refresh.
        if (status.canRefresh) {
          if (_tryGetCredential(status, provider, accountAddress)) {
            return status;
          }
          // If refresh fails, provider should be skipped in the query loop
          pullProviderIndexToSkip = provider.pullProviderIndex();
        }
      }
      // If credential could not be refreshed or the provider is no longer
      // supported, remove it
      status.unsetCredential();
    }

    // Loop over all pull providers to find a valid role for the lender
    if (_loopTryGetCredential(status, accountAddress, pullProviderIndexToSkip)) {
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

    LenderStatus memory status = _lenderStatus[account];

    uint256 newExpiry = callingProvider.calculateExpiry(roleGrantedTimestamp);

    // Check if the new credential is still valid
    if (newExpiry < block.timestamp) revert GrantedCredentialExpired();

    // Check if the account has ever had a credential
    if (status.lastApprovalTimestamp > 0) {
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
      // User is approved, update status with new expiry and last provider
      status.setCredential(provider, credentialTimestamp);
      return true;
    }
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
    // @todo use constant selector once interface is fixed
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
      if call(gas(), providerAddress, 0, add(calldataPointer, 0x1c), add(dataLength, 0x64), 0, 0x20) {
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

  /// @dev Loops over all pull providers to find a valid credential for the lender.
  function _loopTryGetCredential(
    LenderStatus memory status,
    address accountAddress,
    uint256 pullProviderIndexToSkip
  ) internal view returns (bool foundCredential) {
    uint256 providerCount = _pullProviders.length;
    for (uint256 i = 0; i < providerCount; i++) {
      if (i == pullProviderIndexToSkip) continue;
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
   */
  function _handleHooksData(
    LenderStatus memory status,
    address accountAddress,
    bytes calldata hooksData
  ) internal returns (bool validCredential) {
    // Check if the hooks data only contains a provider address
    if (hooksData.length == 20) {
      // @todo make the methods of updating based on the cd prefix more consistent

      // If the data contains only an address, attempt to query a credential from that provider
      // if it exists and is a pull provider.
      address providerAddress = _readAddress(hooksData);
      RoleProvider provider = _roleProviders[providerAddress];
      if (!provider.isNull() && provider.isPullProvider()) {
        return _tryGetCredential(status, provider, accountAddress);
      }
    } else if (hooksData.length > 20) {
      // If the data contains both an address and additional bytes, attempt to
      // validate a credential from that provider
      return _tryValidateCredential(status, accountAddress, hooksData);
    }
  }

  /**
   * @dev Internal function used to validate or update the status of a lender account for hooks on restricted actions.
   *
   *     The function follows the following logic, with the process ending if a valid credential is found:
   *       1. Check if lender has an existing unexpired credential.
   *       2. Check if `hooksData` was provided, and if so:
   *         - If the suffix contains only an address, attempt to query a credential from that provider.
   *         - If the suffix contains both an address and raw data, attempt to validate a credential from that provider.
   *       3. If lender has an existing expired credential, attempt to refresh it.
   *       4. Loop over all pull providers to find a valid credential, excluding the last provider if it failed to refresh.
   *
   * note: Does not update storage or emit an event, but is stateful because it can invoke `validateCredential` on a provider.
   */
  function _tryValidateOrUpdateStatus(
    LenderStatus memory status,
    address accountAddress,
    bytes calldata hooksData
  ) internal returns (bool hasValidCredential, bool wasUpdated) {
    status = _lenderStatus[accountAddress];

    // Get the last provider that granted the lender a credential, if any
    RoleProvider lastProvider = status.hasCredential()
      ? _roleProviders[status.lastProvider]
      : EmptyRoleProvider;

    // If the lender has an active credential and the last provider is still supported, return
    if (!lastProvider.isNull() && status.hasActiveCredential(lastProvider)) {
      return (true, false);
    }

    // Handle the calldata suffix, if any
    if (_handleHooksData(status, accountAddress, hooksData)) {
      return (true, true);
    }

    // @todo handle skipping the provider from the hooks data step if one was given
    uint256 pullProviderIndexToSkip;

    // If lender has an expired credential from a pull provider, attempt to refresh it
    if (!lastProvider.isNull() && status.canRefresh) {
      if (_tryGetCredential(status, lastProvider, accountAddress)) {
        return (true, true);
      }
      // If refresh fails, provider should be skipped in the query loop
      pullProviderIndexToSkip = lastProvider.pullProviderIndex();
    }

    // Loop over all pull providers to find a valid role for the lender
    if (_loopTryGetCredential(status, accountAddress, pullProviderIndexToSkip)) {
      return (true, true);
    }

    // If there was previously a credential and no valid credential could be found,
    // unset the credential.
    if (status.hasCredential()) {
      status.unsetCredential();
      wasUpdated = true;
    }
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

  // ========================================================================== //
  //                                    Hooks                                   //
  // ========================================================================== //

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) external override {}

  function onQueueWithdrawal(
    address lender,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) external override {}

  function onExecuteWithdrawal(
    address lender,
    uint128 normalizedAmountWithdrawn,
    MarketState calldata state,
    bytes calldata extraData
  ) external override {}

  function onTransfer(
    address caller,
    address from,
    address to,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) external override {}

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) external override {}

  function onRepay(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) external override {}

  function onCloseMarket(MarketState calldata state, bytes calldata extraData) external override {}

  function onAssetsSentToEscrow(
    address lender,
    address asset,
    address escrow,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) external override {}

  function onSetMaxTotalSupply(
    uint256 maxTotalSupply,
    MarketState calldata state,
    bytes calldata extraData
  ) external override {}

  function onSetAnnualInterestBips(
    uint16 annualInterestBips,
    MarketState calldata state,
    bytes calldata extraData
  ) external override {}
}
