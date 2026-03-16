// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import './MockRoleProvider.sol';
import 'src/libraries/LibStoredInitCode.sol';

contract MockRoleProviderFactory {
  bool public hasNextProviderAddress;
  address public nextProviderAddress;
  mapping(bytes32 dataHash => address nextProvider) public dataHashToProvider;
  uint256 internal immutable create2Prefix = LibStoredInitCode.getCreate2Prefix(address(this));

  function setNextProviderAddress(address provider) external {
    nextProviderAddress = provider;
    hasNextProviderAddress = true;
  }

  function setProviderToReturnForDataHash(bytes32 dataHash, address provider) external {
    dataHashToProvider[dataHash] = provider;
  }

  function createRoleProvider(bytes memory data) external returns (address) {
    if (hasNextProviderAddress) {
      nextProviderAddress = address(0);
      hasNextProviderAddress = false;
      return nextProviderAddress;
    }
    bytes32 dataHash = keccak256(data);
    if (dataHashToProvider[dataHash] != address(0)) {
      return dataHashToProvider[dataHash];
    }
    (bytes32 salt, bool isPullProvider) = abi.decode(data, (bytes32, bool));
    MockRoleProvider provider = new MockRoleProvider{ salt: salt }();
    provider.setIsPullProvider(isPullProvider);
    return address(provider);
  }

  function computeProviderAddress(bytes32 salt) external view returns (address) {
    uint256 initCodeHash = uint256(keccak256(type(MockRoleProvider).creationCode));
    return LibStoredInitCode.calculateCreate2Address(create2Prefix, salt, initCodeHash);
  }
}
