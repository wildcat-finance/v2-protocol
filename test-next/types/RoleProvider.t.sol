// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/types/RoleProvider.sol';
import { TestKernel } from '../shared/TestKernel.sol';
import { StandardRoleProvider } from '../shared/TestStructs.sol';

contract RoleProviderTest is TestKernel {
  modifier setNullIndex(StandardRoleProvider memory input, bool isPullProvider) {
    if (!isPullProvider) input.pullProviderIndex = NullProviderIndex;
    else input.pushProviderIndex = NullProviderIndex;
    _;
  }

  function assertEq(
    RoleProvider actual,
    StandardRoleProvider memory expected,
    string memory message
  ) internal pure {
    assertEq(actual.providerAddress(), expected.providerAddress, message);
    assertEq(actual.timeToLive(), expected.timeToLive, message);
    assertEq(actual.pullProviderIndex(), expected.pullProviderIndex, message);
    assertEq(actual.pushProviderIndex(), expected.pushProviderIndex, message);
  }

  function assertEq(RoleProvider actual, StandardRoleProvider memory expected) internal pure {
    assertEq(actual, expected, 'RoleProvider');
  }

  function test_encodeRoleProvider(
    StandardRoleProvider memory input,
    bool isPullProvider
  ) external pure setNullIndex(input, isPullProvider) {
    RoleProvider provider = input.toRoleProvider();
    assertEq(provider, input);
  }

  function test_decodeRoleProvider(
    StandardRoleProvider memory input,
    bool isPullProvider
  ) external pure setNullIndex(input, isPullProvider) {
    RoleProvider provider = input.toRoleProvider();
    assertEq(provider, input);
    (
      input.timeToLive,
      input.providerAddress,
      input.pullProviderIndex,
      input.pushProviderIndex
    ) = provider.decodeRoleProvider();
    assertEq(provider, input);
  }

  function test_calculateExpiry(
    StandardRoleProvider memory input,
    bool isPullProvider,
    uint32 timestamp
  ) external pure setNullIndex(input, isPullProvider) {
    RoleProvider provider = input.toRoleProvider();
    uint256 expiryTimestamp = uint(timestamp) + uint(input.timeToLive);
    if (expiryTimestamp > type(uint32).max) expiryTimestamp = type(uint32).max;
    assertEq(provider.calculateExpiry(timestamp), expiryTimestamp);
  }

  function test_setTimeToLive(
    StandardRoleProvider memory input,
    bool isPullProvider,
    uint32 newTimeToLive
  ) external pure setNullIndex(input, isPullProvider) {
    RoleProvider provider = input.toRoleProvider();
    provider = provider.setTimeToLive(newTimeToLive);
    assertEq(provider.timeToLive(), newTimeToLive);
    input.timeToLive = newTimeToLive;
    assertEq(provider, input, 'with new ttl');
  }

  function test_setProviderAddress(
    StandardRoleProvider memory input,
    bool isPullProvider,
    address newProviderAddress
  ) external pure setNullIndex(input, isPullProvider) {
    RoleProvider provider = input.toRoleProvider();
    provider = provider.setProviderAddress(newProviderAddress);
    assertEq(provider.providerAddress(), newProviderAddress);
    input.providerAddress = newProviderAddress;
    assertEq(provider, input, 'with new providerAddress');
  }

  function test_setPullProviderIndex(
    StandardRoleProvider memory input,
    bool isPullProvider,
    uint24 newPullProviderIndex
  ) external pure setNullIndex(input, isPullProvider) {
    if (!isPullProvider) {
      newPullProviderIndex = NullProviderIndex;
    }
    RoleProvider provider = input.toRoleProvider();
    provider = provider.setPullProviderIndex(newPullProviderIndex);
    assertEq(provider.pullProviderIndex(), newPullProviderIndex);
    input.pullProviderIndex = newPullProviderIndex;
    assertEq(provider, input, 'with new pullProviderIndex');
  }

  function test_setPushProviderIndex(
    StandardRoleProvider memory input,
    bool isPullProvider,
    uint24 newPushProviderIndex
  ) external pure setNullIndex(input, isPullProvider) {
    if (isPullProvider) {
      newPushProviderIndex = NullProviderIndex;
    }
    RoleProvider provider = input.toRoleProvider();
    provider = provider.setPushProviderIndex(newPushProviderIndex);
    assertEq(provider.pushProviderIndex(), newPushProviderIndex);
    input.pushProviderIndex = newPushProviderIndex;
    assertEq(provider, input, 'with new pullProviderIndex');
  }

  function test_setPushProviderIndex() external pure {
    RoleProvider provider = encodeRoleProvider({
      providerAddress: address(type(uint160).max),
      pullProviderIndex: type(uint24).max,
      pushProviderIndex: type(uint24).max,
      timeToLive: type(uint32).max
    });
    assertEq(provider.providerAddress(), address(type(uint160).max));
    assertEq(provider.pullProviderIndex(), type(uint24).max);
    assertEq(provider.pushProviderIndex(), type(uint24).max);
    assertEq(provider.timeToLive(), type(uint32).max);
    provider = provider.setPushProviderIndex(1_000);
    assertEq(provider.providerAddress(), address(type(uint160).max));
    assertEq(provider.pullProviderIndex(), type(uint24).max);
    assertEq(provider.pushProviderIndex(), 1_000);
    assertEq(provider.timeToLive(), type(uint32).max);
  }

  function test_eq(
    StandardRoleProvider memory input1,
    bool isPullProvider1,
    StandardRoleProvider memory input2,
    bool isPullProvider2
  ) external pure setNullIndex(input1, isPullProvider1) setNullIndex(input2, isPullProvider2) {
    RoleProvider provider1 = input1.toRoleProvider();
    RoleProvider provider2 = input2.toRoleProvider();
    assertEq(
      provider1.eq(provider2),
      input1.providerAddress == input2.providerAddress &&
        input1.pullProviderIndex == input2.pullProviderIndex &&
        input1.pushProviderIndex == input2.pushProviderIndex &&
        input1.timeToLive == input2.timeToLive
    );
  }

  function test_isNull(
    StandardRoleProvider memory input,
    bool isPullProvider
  ) external pure setNullIndex(input, isPullProvider) {
    RoleProvider provider = input.toRoleProvider();
    assertEq(
      provider.isNull(),
      input.providerAddress == address(0) && input.timeToLive == 0 && input.pullProviderIndex == 0
    );
  }

  function test_isPullProvider(
    StandardRoleProvider memory input,
    bool isPullProvider
  ) external pure setNullIndex(input, isPullProvider) {
    RoleProvider provider = input.toRoleProvider();
    assertEq(provider.isPullProvider(), input.pullProviderIndex != NullProviderIndex);
  }

  function test_setNotPullProvider(
    StandardRoleProvider memory input,
    bool isPullProvider
  ) external pure setNullIndex(input, isPullProvider) {
    RoleProvider provider = input.toRoleProvider();
    provider = provider.setNotPullProvider();
    input.pullProviderIndex = NullProviderIndex;
    assertEq(provider, input);
  }
}
