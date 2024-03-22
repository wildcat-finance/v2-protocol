// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// import '../types/LenderStatus.sol';
import '../libraries/MathUtils.sol';

using MathUtils for uint256;

struct LenderStatus {
  bool isBlocked;
  bool hasEverDeposited;
  uint32 lastProviderId;
  uint32 expiry;
}

interface ICredentialProvider {
  function getCredential(address account) external view returns (uint32 timestamp);
  function validateCredential(address account) external returns (bytes4 magicValue);
}

// If provider should be checked every time, TTL should be 0
struct CredentialProvider {
  ICredentialProvider provider;
  uint32 timeToLive;
  bool allowRefresh;
}

contract WildcatMarketHooks {
  uint32 providerCount;
  mapping(address => LenderStatus) internal _credentials;
  mapping(uint32 => CredentialProvider) internal _providers;

  function refreshCredential(
    LenderStatus storage status,
    CredentialProvider memory provider,
    address accountAddress
  ) internal returns (bool isApproved) {
    // todo - query in assembly, return false if call fails
    uint256 credentialTimestamp = provider.provider.getCredential(accountAddress);

    if (credentialTimestamp == 0) return false;

    // Calculate new role expiry as either max uint32 or the last approval time
    // plus the provider's TTL, whichever is lower.
    uint256 newExpiry = credentialTimestamp.satAdd(provider.timeToLive, type(uint32).max);

    // If new expiry would be expired, do not update status
    if (newExpiry > block.timestamp) {
      // User is approved, update status with new expiry and last provider
      status.expiry = uint32(newExpiry);
      status.lastProviderId = address(roleProvider);
      return true;
    }
  }
  
  function _checkLenderAccess(address account) internal returns (bool isApproved, uint32 approvalExpiry) {
    LenderStatus memory credential = _credentials[account];
    if (status.expiry > block.timestamp) {
      return (true, status.expiry);
    }
    if (approval.lastApprovalId == type(uint32).max) {
      return;
    }
  }

  function getUserAccessAndExpiry(
    address accountAddress
  ) external view returns (bool isApproved, uint32 approvalExpiry) {
    LenderApproval memory status = _credentials[accountAddress];
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

  function validateDeposit(address lender, uint256 scaledAmount) external {
  }

  function validateTransfer(address from, address to, uint scaledAmount, uint scaledTotalSupply) external {
    
  }

  function validateRequestWithdrawal(address lender, uint32 withdrawalBatchExpiry, uint scaledAmount) external {}

  function validateExecuteWithdrawal(address lender, uint32 withdrawalBatchExpiry, uint scaledAmount) external {}
}
