// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { LenderStatus } from 'src/types/LenderStatus.sol';
import { NullProviderIndex, RoleProvider, encodeRoleProvider } from 'src/types/RoleProvider.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract LenderStatusHarness {
  function credentialExpired(
    LenderStatus memory status,
    RoleProvider provider
  ) external view returns (bool) {
    return status.credentialExpired(provider);
  }

  function credentialNotExpired(
    LenderStatus memory status,
    RoleProvider provider
  ) external view returns (bool) {
    return status.credentialNotExpired(provider);
  }

  function hasCredential(LenderStatus memory status) external pure returns (bool) {
    return status.hasCredential();
  }

  function setCredential(
    LenderStatus memory status,
    RoleProvider provider,
    uint32 timestamp
  ) external pure returns (LenderStatus memory) {
    status.setCredential(provider, timestamp);
    return status;
  }

  function unsetCredential(LenderStatus memory status) external pure returns (LenderStatus memory) {
    status.unsetCredential();
    return status;
  }
}

contract LenderStatusTest is TestKernel {
  LenderStatusHarness internal harness;

  function setUp() external {
    harness = LenderStatusHarness(
      _deployCode('test-next/types/LenderStatus.t.sol:LenderStatusHarness')
    );
  }

  function _provider(
    address providerAddress,
    uint32 timeToLive,
    bool canRefresh
  ) internal pure returns (RoleProvider) {
    return
      encodeRoleProvider({
        providerAddress: providerAddress,
        timeToLive: timeToLive,
        pullProviderIndex: canRefresh ? 0 : NullProviderIndex,
        pushProviderIndex: canRefresh ? NullProviderIndex : 0
      });
  }

  function _expiry(uint32 approvalTimestamp, uint32 timeToLive) internal pure returns (uint256) {
    uint256 expiry = uint256(approvalTimestamp) + timeToLive;
    return expiry > type(uint32).max ? type(uint32).max : expiry;
  }

  function test_credentialExpired(
    uint32 timeToLive,
    uint32 approvalTimestamp,
    uint32 currentTimestamp
  ) external {
    vm.warp(currentTimestamp);
    LenderStatus memory status;
    status.lastApprovalTimestamp = approvalTimestamp;
    RoleProvider provider = _provider(address(1), timeToLive, true);

    assertEq(
      harness.credentialExpired(status, provider),
      _expiry(approvalTimestamp, timeToLive) < currentTimestamp
    );
    assertEq(
      harness.credentialNotExpired(status, provider),
      _expiry(approvalTimestamp, timeToLive) >= currentTimestamp
    );
  }

  function test_hasCredential(uint32 approvalTimestamp) external view {
    LenderStatus memory status;
    status.lastApprovalTimestamp = approvalTimestamp;
    assertEq(harness.hasCredential(status), approvalTimestamp > 0);
  }

  function test_setCredential(
    bool blocked,
    bool canRefresh,
    address providerAddress,
    uint32 timestamp
  ) external view {
    LenderStatus memory status;
    status.isBlockedFromDeposits = blocked;
    RoleProvider provider = _provider(providerAddress, 1 days, canRefresh);

    status = harness.setCredential(status, provider, timestamp);
    assertEq(status.isBlockedFromDeposits, blocked, 'deposit block');
    assertEq(status.lastProvider, providerAddress, 'provider');
    assertEq(status.canRefresh, canRefresh, 'canRefresh');
    assertEq(status.lastApprovalTimestamp, timestamp, 'timestamp');
  }

  function test_unsetCredential(
    bool blocked,
    bool canRefresh,
    address providerAddress,
    uint32 timestamp
  ) external view {
    LenderStatus memory status = LenderStatus({
      isBlockedFromDeposits: blocked,
      lastProvider: providerAddress,
      canRefresh: canRefresh,
      lastApprovalTimestamp: timestamp
    });

    status = harness.unsetCredential(status);
    assertEq(status.isBlockedFromDeposits, blocked, 'deposit block');
    assertEq(status.lastProvider, address(0), 'provider');
    assertFalse(status.canRefresh, 'canRefresh');
    assertEq(status.lastApprovalTimestamp, 0, 'timestamp');
  }
}
