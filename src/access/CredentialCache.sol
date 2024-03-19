// SPDX-License-Identifer: Apache-2.0
pragma solidity ^0.8.20;

// todo: convert to packed custom type
struct Credential {
  uint32 timestamp;
  uint56 roles;
  bool canRefresh;
  ICredentialProvider provider;
}

struct CredentialQueryResult {
  uint32 providerId;
  uint32 timestamp;
}

// todo: convert to packed custom type
struct CredentialQuery {
  uint32 providerId;
  uint32 maxAge;
  uint96 restrictedRoles;
  uint96 requiredRoles;
}

struct CredentialProvider {
  address providerAddress;
  // Whether expired credentials can be refreshed by querying the provider
  bool allowRefresh;
}

interface ICredentialProvider {
  function getCredential(address account) external view returns (uint32 timestamp, uint56 roles);
}

contract CredentialCache {
  uint32 public providerCount;
  mapping(uint32 providerId => mapping(address => Credential)) internal _credentials;
  mapping(uint32 providerId => CredentialProvider) internal _providers;

  function register(bool allowRefresh) external {
    providerCount++;
    CredentialProvider storage provider = _providers[providerCount];
    provider.providerAddress = msg.sender;
    provider.allowRefresh = allowRefresh;
  }

  function setCredential(
    uint32 providerId,
    address account,
    Credential memory credential
  ) external {
    require(msg.sender == _providers[providerId].providerAddress);
    _credentials[providerId][account] = credential;
  }

  function getCredential(
    uint32 providerId,
    address account
  ) external view returns (Credential memory) {
    return _credentials[providerId][account];
  }

  function _tryRefreshCredential(
    Credential memory credential,
    CredentialQuery memory query,
    address account
  ) internal returns (bool) {
    if (credential.canRefresh) {
      (uint32 timestamp, uint56 roles) = credential.provider.getCredential(account);

      if (timestamp > credential.timestamp + query.maxAge && meetsConditions(query, roles)) {
        _credentials[query.providerId][account].timestamp = timestamp;
        _credentials[query.providerId][account].roles = roles;
        return true;
      }
    }
    return false;
  }
}

function meetsConditions(CredentialQuery memory query, uint roles) pure returns (bool) {
  return (roles & query.requiredRoles) | (roles & query.restrictedRoles) == roles;
}

