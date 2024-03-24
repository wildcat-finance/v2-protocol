// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import '../libraries/BoolUtils.sol';
import '../libraries/MathUtils.sol';
import '../types/RoleProvider.sol';
import '../types/LenderStatus.sol';
import './IRoleProvider.sol';

using BoolUtils for bool;
using MathUtils for uint256;

function removeFromArray(
  RoleProvider[] storage arr,
  mapping(address => RoleProvider) storage map,
  uint24 indexToRemove
) {
  // Get the last index in the array
  uint256 lastIndex = arr.length - 1;
  // If the index to remove is the last index, just pop the last element
  if (indexToRemove == lastIndex) {
    arr.pop();
    return;
  }
  RoleProvider lastProvider = arr[lastIndex];
  lastProvider = lastProvider.setPullProviderIndex(indexToRemove);
  arr[indexToRemove] = lastProvider;
  arr.pop();
  map[lastProvider.providerAddress()] = lastProvider;
}

// @todo custom error types
// @todo events
contract AccessControlHooks {
  uint32 providerCount;
  mapping(address => LenderStatus) internal _lenderStatus;
  // Provider data is duplicated in the array and mapping to allow
  // push providers to update in a single step and pull providers to
  // be looped over without having to access the mapping.
  RoleProvider[] internal pullProviders;
  mapping(address => RoleProvider) internal _roleProviders;

  function addProvider(address providerAddress, bool isPullProvider, uint32 timeToLive) external {
    RoleProvider provider = _roleProviders[providerAddress];
    if (!provider.isNull()) {
      // If provider already exists, the only value that can be updated is the TTL
      provider = provider.setTimeToLive(timeToLive);
    } else {
      // Role providers that are not pull providers have their `pullProviderIndex`
      // set to `EmptyIndex`, the max uint24, to indicate they are not providers.
      provider = encodeRoleProvider(
        timeToLive,
        providerAddress,
        isPullProvider ? uint24(pullProviders.length) : EmptyIndex
      );
      if (isPullProvider) pullProviders.push(provider);
    }
    // Update the provider in storage
    _roleProviders[providerAddress] = provider;
  }

  function removeProvider(address providerAddress) external {
    RoleProvider provider = _roleProviders[providerAddress];
    require(!provider.isNull(), 'Provider null');
    if (provider.isPullProvider()) {
      removeFromArray(pullProviders, _roleProviders, provider.pullProviderIndex());
    }
    delete _roleProviders[providerAddress];
  }

  function grantRole(address account) external {
    RoleProvider provider = _roleProviders[msg.sender];
    require(!provider.isNull(), 'Controller: Not a push provider');
    LenderStatus memory status = _lenderStatus[account];
    if (status.expiry > 0) {
      // Can only update role if it is expired or caller is previous role provider
      bool isPreviousRoleExpired = status.expiry < block.timestamp;
      bool isPreviousRoleProvider = status.lastProvider == msg.sender;
      require(
        isPreviousRoleExpired.or(isPreviousRoleProvider),
        'Role is not expired and sender is not previous role provider'
      );
    }
    status.setCredential(provider, block.timestamp);
    _lenderStatus[account] = status;
  }

  function tryPullUserAccess(
    LenderStatus memory status,
    RoleProvider provider,
    address accountAddress
  ) internal view returns (bool isApproved) {
    // Query provider for user approval
    IRoleProvider roleProvider = IRoleProvider(provider.providerAddress());

    // todo - query in assembly, return false if call fails
    uint256 lastApprovalTime = roleProvider.getCredential(accountAddress);

    if (lastApprovalTime == 0) return false;

    // Calculate new role expiry as either max uint32 or the last approval time
    // plus the provider's TTL, whichever is lower.
    uint256 newExpiry = lastApprovalTime.satAdd(provider.timeToLive(), type(uint32).max);

    // If new expiry would be expired, do not update status
    if (newExpiry < block.timestamp) return false;

    // User is approved, update status with new expiry and last provider
    status.setCredential(provider, lastApprovalTime);
    return true;
  }

  // @todo update ethereum-access-token to allow the provider to specify the
  //       cdptr to the signature
  function _validateCredential(address accountAddress, uint calldataPointer) internal {
    uint validateSelector = IRoleProvider.validateCredential.selector;
    address providerAddress;
    assembly {
      providerAddress := shr(96, calldataload(calldataPointer))
      // Increment calldata pointer forward 20 bytes to indicate the remainder is
      // the data to pass to the provider
      calldataPointer := add(calldataPointer, 0x14)
    }
    RoleProvider provider = _roleProviders[providerAddress];
    // @todo custom error
    require(!provider.isNull(), 'Provider not found');
    assembly {
      let ptr := mload(0x40)
      mstore(ptr, validateSelector)
      mstore(add(ptr, 0x20), accountAddress)
      let extraCalldataBytes := sub(calldatasize(), calldataPointer)
      calldatacopy(add(ptr, 0x40), calldataPointer, extraCalldataBytes)
      let size := add(0x24, extraCalldataBytes)
      if iszero(
        and(eq(mload(0), selector), call(gas(), sload(accountAddress.slot), 0, ptr, size, 0, 0))
      ) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
    LenderStatus memory status = _lenderStatus[accountAddress];
    status.setCredential(provider, block.timestamp, type(uint32).max);
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

    uint256 providerIndexToSkip;

    // Check if user has an existing credential
    if (status.expiry != 0) {
      // Check if the credential is still valid
      if (status.expiry >= block.timestamp) {
        // If credential is not expired and the provider is still
        // supported, the lender has a valid credential.
        RoleProvider provider = _roleProviders[status.lastProvider];
        if (!provider.isNull()) {
          return status;
        }
      } else if (status.canRefresh) {
        // If credential is expired but the provider is still supported and
        // allows refreshing (i.e. it's a pull provider), try to refresh.
        RoleProvider provider = _roleProviders[status.lastProvider];
        if (!provider.isNull()) {
          // If the credential is refreshed, return the status
          if (tryPullUserAccess(status, provider, accountAddress)) {
            return status;
          }
          // Otherwise, skip the provider on the loop below
          // Don't need to set a skip index if provider is null
          // as it won't be in `pullProviders`
          providerIndexToSkip = provider.pullProviderIndex();
        }
        // If credential could not be refreshed, remove it from the lender
        status.unsetCredential();
      }
    }
    // Loop over all pull providers to find a valid role
    for (uint256 i = 0; i < providerCount; i++) {
      if (i == providerIndexToSkip) continue;
      RoleProvider provider = pullProviders[i];
      if (tryPullUserAccess(status, provider, accountAddress)) {
        return status;
      }
    }
  }

  function validateDeposit(address lender, uint256 scaledAmount) external {}

  function validateTransfer(
    address from,
    address to,
    uint scaledAmount,
    uint scaledTotalSupply
  ) external {}

  function validateRequestWithdrawal(
    address lender,
    uint32 withdrawalBatchExpiry,
    uint scaledAmount
  ) external {}

  function validateExecuteWithdrawal(
    address lender,
    uint32 withdrawalBatchExpiry,
    uint scaledAmount
  ) external {}
}
