// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { IRoleProviderFactory } from 'src/access/IRoleProviderFactory.sol';
import { MockRoleProvider } from './MockRoleProvider.sol';

contract MockRoleProviderFactory is IRoleProviderFactory {
  bool internal _hasNextProviderAddress;
  address internal _nextProviderAddress;

  function setNextProviderAddress(address provider) external {
    _nextProviderAddress = provider;
    _hasNextProviderAddress = true;
  }

  function createRoleProvider(bytes calldata data) external returns (address providerAddress) {
    if (_hasNextProviderAddress) {
      _hasNextProviderAddress = false;
      providerAddress = _nextProviderAddress;
      _nextProviderAddress = address(0);
      return providerAddress;
    }

    (bytes32 salt, bool isPullProvider) = abi.decode(data, (bytes32, bool));
    MockRoleProvider provider = new MockRoleProvider{ salt: salt }();
    provider.setIsPullProvider(isPullProvider);
    return address(provider);
  }

  function computeProviderAddress(bytes32 salt) external view returns (address) {
    bytes32 initCodeHash = keccak256(type(MockRoleProvider).creationCode);
    return
      address(
        uint160(
          uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))
        )
      );
  }
}
