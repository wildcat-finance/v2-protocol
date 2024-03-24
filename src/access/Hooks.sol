// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import '../libraries/BoolUtils.sol';
import '../libraries/MathUtils.sol';
import '../types/RoleProvider.sol';

using BoolUtils for bool;
using MathUtils for uint256;

/**
 * @param isBlocked Whether the lender is blocked from the market
 * @param hasEverDeposited Whether the lender has ever deposited to the market
 * @param lastProvider The address of the last provider to grant the lender a credential
 * @param canRefresh Whether the last provider can refresh the lender's credential
 * @param expiry The timestamp at which the lender's credential expires
 */
struct LenderStatus {
  bool isBlocked;
  bool hasEverDeposited;
  address lastProvider;
  bool canRefresh;
  uint32 expiry;
}

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

interface IRoleProvider {
  function canPull() external view returns (bool);

  function getCredential(address account) external view returns (uint32 timestamp);

  function validateCredential(address account) external returns (bytes4 magicValue);
}

contract AccessControlHooks {
  uint32 providerCount;
  mapping(address => LenderStatus) internal _lenderStatus;
  // Provider data is duplicated in the array and mapping to allow
  // push providers to update in a single step and pull providers to
  // be looped over without having to access the mapping.
  RoleProvider[] internal pullProviders;
  mapping(address => RoleProvider) internal roleProviders;

  function grantRole(address account) external {
    RoleProvider provider = roleProviders[msg.sender];
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
    uint256 timeToLive = provider.timeToLive();
    // todo - overflow possible in third argument - fix
    uint256 newExpiry = block.timestamp.satAdd(timeToLive, type(uint32).max);
    status.expiry = uint32(newExpiry);
    status.lastProvider = msg.sender;
    status.canRefresh = provider.isPullProvider();
    _lenderStatus[account] = status;
  }

  function addProvider(address providerAddress, bool isPullProvider, uint32 timeToLive) external {
    RoleProvider provider = roleProviders[providerAddress];
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
    roleProviders[providerAddress] = provider;
  }

  // function _refresh(
  //   LenderStatus memory status,
  //   RoleProvider memory provider,
  //   uint32 providerId,
  //   address accountAddress
  // ) internal returns (bool /* refreshed */) {
  //   // todo - query in assembly, return false if call fails
  //   uint256 credentialTimestamp = provider.provider.getCredential(accountAddress);

  //   if (credentialTimestamp == 0) return false;

  //   // Calculate new role expiry as either max uint32 or the last approval time
  //   // plus the provider's TTL, whichever is lower.
  //   uint256 newExpiry = credentialTimestamp.satAdd(provider.timeToLive(), type(uint32).max);

  //   // If new expiry would be expired, do not update status
  //   if (newExpiry > block.timestamp) {
  //     // User is approved, update status with new expiry and last provider
  //     status.expiry = uint32(newExpiry);
  //     status.lastProviderId = providerId;
  //     return true;
  //   }
  // }

  function tryPullUserAccess(
    LenderStatus memory status,
    RoleProvider provider,
    address accountAddress
  ) internal view returns (bool isApproved) {
    // Ensure provider is still approved
    if (!provider.isPullProvider()) return false;

    // Query provider for user approval
    IRoleProvider roleProvider = IRoleProvider(provider.providerAddress());

    // todo - query in assembly, return false if call fails
    uint256 lastApprovalTime = roleProvider.getCredential(accountAddress);

    if (lastApprovalTime == 0) return false;

    uint256 ttl = provider.timeToLive();
    // Calculate new role expiry as either max uint32 or the last approval time
    // plus the provider's TTL, whichever is lower.
    uint256 newExpiry = lastApprovalTime.satAdd(ttl, type(uint32).max);

    // If new expiry would be expired, do not update status
    if (newExpiry > block.timestamp) {
      // User is approved, update status with new expiry and last provider
      status.expiry = uint32(newExpiry);
      status.lastProvider = address(roleProvider);
      status.canRefresh = true;
      return true;
    }
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

    uint32 providerIndexToSkip;
    // Check if user has an existing credential
    if (status.expiry != 0) {
      // If credential is not expired and the provider is still supported,
      // return the status.
      if (status.expiry > block.timestamp) {
        RoleProvider provider = roleProviders[status.lastProvider];
        if (!provider.isNull()) return status;
      }
      // If user's role is expired, check if it can be refreshed
      if ((status.expiry < block.timestamp).and(status.canRefresh)) {
        RoleProvider provider = roleProviders[status.lastProvider];
        // Verify the provider is still supported
        if (!provider.isNull()) {
          // If the credential is refreshed, return the status
          if (tryPullUserAccess(status, provider, accountAddress)) {
            return status;
          }
          // Otherwise, skip the provider on the loop below
          providerIndexToSkip = provider.pullProviderIndex();
        }
        status.canRefresh = false;
        status.expiry = 0;
        status.lastProvider = address(0);
      } else {
        return status;
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
