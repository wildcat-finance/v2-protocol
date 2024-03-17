pragma solidity >=0.8.20;

import '../types/LibRoleProvider.sol';
import '../types/LenderApproval.sol';
import '../libraries/MathUtils.sol';
import '../libraries/BoolUtils.sol';

using BoolUtils for bool;
using MathUtils for uint256;

/*
Markets will always allow users who have ever deposited to withdraw,
unless they are sanctioned.

Ideally, roles should be sharable between different borrowers,
but borrowers must also be able to have their own requirements.

One role can override another if it is a higher role or if the old role is expired.

*/

interface IPullProvider {
  function getLastUserApprovalTime(address user) external view returns (uint32 lastApprovalTime);
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

contract RoleManager {
  mapping(address => LenderApproval) public lenderApprovals;

  // Provider data is duplicated in the array and mapping to allow
  // push providers to update in a single step and pull providers to
  // be looped over without having to access the mapping.
  RoleProvider[] internal pullProviders;
  mapping(address => RoleProvider) internal roleProviders;

  constructor(address verifier) {}

  function addProvider(address providerAddress, bool isPullProvider, uint32 timeToLive) external {
    RoleProvider existingProvider = roleProviders[providerAddress];
    RoleProvider provider;
    if (existingProvider.isNull()) {
      // Role providers that are not pull providers have their `pullProviderIndex`
      // set to `EmptyIndex`, the max uint24, to indicate they are not providers.
      provider = encodeRoleProvider(
        timeToLive,
        providerAddress,
        isPullProvider ? uint24(pullProviders.length) : EmptyIndex
      );
      if (isPullProvider) pullProviders.push(provider);
      roleProviders[providerAddress] = provider;
    } else {
      if (isPullProvider.and(!existingProvider.isPullProvider())) {
        // If the provider is being marked as a pull provider and the existing config
        // is not marked as one, update and add to the array of pull providers.
        uint256 index = pullProviders.length;
        // Update provider stack variable with new pull provider index and ttl
        provider = existingProvider.setPullProviderIndex(uint24(index)).setRoleTimeToLive(
          timeToLive
        );
        // Add provider to the array of pull providers
        pullProviders.push(provider);
      } else if (!isPullProvider.and(existingProvider.isPullProvider())) {
        // If the provider is not marked as a pull provider and the existing config
        // is marked as one, remove it from the array.
        removeFromArray(pullProviders, roleProviders, existingProvider.pullProviderIndex());
        provider = existingProvider.setNotPullProvider().setRoleTimeToLive(timeToLive);
      }
      // Update the provider in the mapping of role providers
      roleProviders[providerAddress] = provider;
    }
  }

  function _getPullProvider(address providerAddress) internal view returns (RoleProvider provider) {
    provider = roleProviders[providerAddress];
    if (provider.isNull()) {
      revert('Controller: Provider not found');
    }
    if (!provider.isPullProvider()) {
      revert('Controller: Not a pull provider');
    }
  }

  function _getPushProvider(address providerAddress) internal view returns (RoleProvider provider) {
    provider = roleProviders[providerAddress];
    if (provider.isNull()) revert('Controller: Provider not found');
  }

  function grantRole(address account) external {
    RoleProvider provider = roleProviders[msg.sender];
    require(!provider.isNull(), 'Controller: Not a push provider');
    LenderApproval memory status = lenderApprovals[account];
    if (status.expiry > 0) {
      // Can only update role if it is expired or caller is previous role provider
      bool isPreviousRoleExpired = status.expiry < block.timestamp;
      bool isPreviousRoleProvider = status.lastRoleProvider == msg.sender;
      require(
        isPreviousRoleExpired.or(isPreviousRoleProvider),
        'Controller: Role is not expired and sender is not previous role provider'
      );
    }
    uint256 timeToLive = provider.roleTimeToLive();
    // todo - overflow possible in third argument - fix
    uint256 newExpiry = MathUtils.ternary(
      timeToLive == type(uint32).max,
      timeToLive,
      block.timestamp.satAdd(timeToLive, type(uint32).max)
    );
    status.expiry = uint32(newExpiry);
    status.lastRoleProvider = msg.sender;
    status.canPullLastProvider = provider.isPullProvider();
    lenderApprovals[account] = status;
  }

  function tryPullUserAccess(
    LenderApproval memory status,
    RoleProvider provider,
    address accountAddress
  ) internal view returns (bool isApproved) {
    // Ensure provider is still approved
    if (!provider.isPullProvider()) return false;

    // Query provider for user approval
    IPullProvider roleProvider = IPullProvider(provider.providerAddress());

    // todo - query in assembly, return false if call fails
    uint256 lastApprovalTime = roleProvider.getLastUserApprovalTime(accountAddress);

    if (lastApprovalTime == 0) return false;
    uint256 ttl = provider.roleTimeToLive();
    // Calculate new role expiry as either max uint32 or the last approval time
    // plus the provider's TTL, whichever is lower.
    uint256 newExpiry = MathUtils.ternary(
      ttl == type(uint32).max,
      ttl,
      lastApprovalTime.satAdd(ttl, type(uint32).max)
    );

    // If new expiry would be expired, do not update status
    if (newExpiry > block.timestamp) {
      // User is approved, update status with new expiry and last provider
      status.expiry = uint32(newExpiry);
      status.lastRoleProvider = address(roleProvider);
      status.canPullLastProvider = true;
      return true;
    }
  }

  function getUserAccess(
    address accountAddress
  ) external returns (bool isApproved, uint32 approvalExpiry) {
    LenderApproval memory status = lenderApprovals[accountAddress];
    if (status.expiry > block.timestamp) {
      return (true, status.expiry);
    }
    address providerToSkip;
    // Check if user has any existing role
    if (status.expiry != 0) {
      // If user's role is expired, check if it was set by a pull provider
      if (status.expiry <= block.timestamp) {
        if (status.canPullLastProvider) {
          // Query the previous provider to see if user is still approved
          RoleProvider provider = _getPullProvider(status.lastRoleProvider);
          if (tryPullUserAccess(status, provider, accountAddress)) {
            return (true, status.expiry);
          }
          providerToSkip = status.lastRoleProvider;
        }
      } else {
        return (true, status.expiry);
      }
    }
    for (uint256 i = 0; i < pullProviders.length; i++) {
      RoleProvider provider = pullProviders[i];
      if (provider.providerAddress() == providerToSkip) continue;
      if (tryPullUserAccess(status, provider, accountAddress)) {
        return (true, status.expiry);
      }
    }
  }
}
