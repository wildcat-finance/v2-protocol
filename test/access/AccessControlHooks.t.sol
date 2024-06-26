// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/access/AccessControlHooks.sol';
import { LibString } from 'solady/utils/LibString.sol';
import '../shared/mocks/MockRoleProvider.sol';
import '../shared/mocks/MockAccessControlHooks.sol';
import '../helpers/Assertions.sol';
import { bound, warp } from '../helpers/VmUtils.sol';
import { AccessControlHooksFuzzInputs, AccessControlHooksFuzzContext, createAccessControlHooksFuzzContext } from '../helpers/fuzz/AccessControlHooksFuzzContext.sol';
import 'sol-utils/ir-only/MemoryPointer.sol';
import { ArrayHelpers } from 'sol-utils/ir-only/ArrayHelpers.sol';
import 'src/libraries/BoolUtils.sol';

using LibString for uint256;
using LibString for address;
using MathUtils for uint256;
using BoolUtils for bool;

contract AccessControlHooksTest is Test, Assertions {
  uint24 internal numPullProviders;
  StandardRoleProvider[] internal expectedRoleProviders;
  MockAccessControlHooks internal hooks;
  MockRoleProvider internal mockProvider1;
  MockRoleProvider internal mockProvider2;

  function setUp() external {
    hooks = new MockAccessControlHooks(address(this));
    mockProvider1 = new MockRoleProvider();
    mockProvider2 = new MockRoleProvider();
    assertEq(hooks.factory(), address(this), 'factory');
    assertEq(hooks.borrower(), address(this), 'borrower');
    _addExpectedProvider(MockRoleProvider(address(this)), type(uint32).max, false);
    _validateRoleProviders();
    // Set block.timestamp to 4:50 am, May 3 2024
    warp(1714737030);
  }

  function test_config() external {
    StandardHooksConfig memory expectedConfig = StandardHooksConfig({
      hooksAddress: address(hooks),
      useOnDeposit: true,
      useOnQueueWithdrawal: true,
      useOnExecuteWithdrawal: true,
      useOnTransfer: true,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
      useOnAssetsSentToEscrow: false,
      useOnSetMaxTotalSupply: false,
      useOnSetAnnualInterestAndReserveRatioBips: false
    });
    assertEq(hooks.config(), expectedConfig, 'config.');
  }

  // ========================================================================== //
  //                              State validation                              //
  // ========================================================================== //

  function _addExpectedProvider(
    MockRoleProvider mockProvider,
    uint32 timeToLive,
    bool isPullProvider
  ) internal returns (StandardRoleProvider storage) {
    if (address(mockProvider) != address(this)) {
      mockProvider.setIsPullProvider(isPullProvider);
    }
    uint24 pullProviderIndex = isPullProvider ? numPullProviders++ : NotPullProviderIndex;
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider),
        timeToLive: timeToLive,
        pullProviderIndex: pullProviderIndex
      })
    );
    return expectedRoleProviders[expectedRoleProviders.length - 1];
  }

  function _validateRoleProviders() internal {
    RoleProvider[] memory pullProviders = hooks.getPullProviders();
    uint256 index;
    for (uint i; i < expectedRoleProviders.length; i++) {
      if (expectedRoleProviders[i].pullProviderIndex != NotPullProviderIndex) {
        if (index >= pullProviders.length) {
          emit log('Error: provider with pullProviderIndex not found');
          fail();
        }
        // Check pull provider matches expected provider
        string memory label = string.concat('pullProviders[', index.toString(), '].');
        assertEq(pullProviders[index++], expectedRoleProviders[i], label);
      }
      address providerAddress = expectedRoleProviders[i].providerAddress;
      // Check _roleProviders[provider] matches expected provider
      RoleProvider provider = hooks.getRoleProvider(providerAddress);
      assertEq(
        provider,
        expectedRoleProviders[i],
        string.concat('getRoleProvider(', providerAddress.toHexString(), ').')
      );
    }
    assertEq(index, pullProviders.length, 'pullProviders.length');
  }

  function _expectRoleProviderAdded(
    address providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex
  ) internal {
    vm.expectEmit();
    emit AccessControlHooks.RoleProviderAdded(providerAddress, timeToLive, pullProviderIndex);
  }

  function _expectRoleProviderUpdated(
    address providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex
  ) internal {
    vm.expectEmit();
    emit AccessControlHooks.RoleProviderUpdated(providerAddress, timeToLive, pullProviderIndex);
  }

  function _expectRoleProviderRemoved(address providerAddress, uint24 pullProviderIndex) internal {
    vm.expectEmit();
    emit AccessControlHooks.RoleProviderRemoved(providerAddress, pullProviderIndex);
  }

  function _expectAccountAccessGranted(
    address providerAddress,
    address accountAddress,
    uint32 credentialTimestamp
  ) internal {
    vm.expectEmit();
    emit AccessControlHooks.AccountAccessGranted(
      providerAddress,
      accountAddress,
      credentialTimestamp
    );
  }

  // ========================================================================== //
  //                          Role provider management                          //
  // ========================================================================== //

  function test_addRoleProvider(bool isPullProvider, uint32 timeToLive) external {
    mockProvider1.setIsPullProvider(isPullProvider);

    uint24 pullProviderIndex = isPullProvider ? 0 : NotPullProviderIndex;
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider1),
        timeToLive: timeToLive,
        pullProviderIndex: pullProviderIndex
      })
    );

    _expectRoleProviderAdded(address(mockProvider1), timeToLive, pullProviderIndex);
    hooks.addRoleProvider(address(mockProvider1), timeToLive);

    _validateRoleProviders();
  }

  function test_addRoleProvider_badInterface(uint32 timeToLive) external {
    vm.expectRevert();
    hooks.addRoleProvider(address(2), timeToLive);
    _validateRoleProviders();
  }

  function test_addRoleProvider_updateTimeToLive(
    bool isPullProvider,
    uint32 ttl1,
    uint32 ttl2
  ) external {
    StandardRoleProvider storage provider = _addExpectedProvider(
      mockProvider1,
      ttl1,
      isPullProvider
    );
    _expectRoleProviderAdded(address(mockProvider1), ttl1, provider.pullProviderIndex);
    hooks.addRoleProvider(address(mockProvider1), ttl1);

    // Validate the initial state
    _validateRoleProviders();

    // Update the TTL using `addRoleProvider`
    provider.timeToLive = ttl2;
    _expectRoleProviderUpdated(address(mockProvider1), ttl2, provider.pullProviderIndex);
    hooks.addRoleProvider(address(mockProvider1), ttl2);

    // Validate the updated state
    _validateRoleProviders();
  }

  function test_removeRoleProvider(bool isPullProvider, uint32 timeToLive) external {
    StandardRoleProvider storage provider = _addExpectedProvider(
      mockProvider1,
      timeToLive,
      isPullProvider
    );

    hooks.addRoleProvider(address(mockProvider1), timeToLive);

    _expectRoleProviderRemoved(address(mockProvider1), provider.pullProviderIndex);
    hooks.removeRoleProvider(address(mockProvider1));
    expectedRoleProviders.pop();

    _validateRoleProviders();
  }

  function test_removeRoleProvider_ProviderNotFound(bool isPullProvider) external {
    vm.expectRevert(AccessControlHooks.ProviderNotFound.selector);
    hooks.removeRoleProvider(address(mockProvider1));
  }

  /// @dev Remove the last pull provider. Should not cause any changes
  ///      to other pull providers.
  function test_removeRoleProvider_LastPullProvider() external {
    mockProvider1.setIsPullProvider(true);
    mockProvider2.setIsPullProvider(true);
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider1),
        timeToLive: 1,
        pullProviderIndex: 0
      })
    );
    hooks.addRoleProvider(address(mockProvider1), 1);
    hooks.addRoleProvider(address(mockProvider2), 1);

    _expectRoleProviderRemoved(address(mockProvider2), 1);
    hooks.removeRoleProvider(address(mockProvider2));
    _validateRoleProviders();
  }

  /// @dev Remove a pull provider that is not the last pull provider.
  ///      Should cause the last pull provider to be moved to the
  ///      removed provider's index
  function test_removeRoleProvider_NotLastProvider() external {
    mockProvider1.setIsPullProvider(true);
    mockProvider2.setIsPullProvider(true);
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider2),
        timeToLive: 1,
        pullProviderIndex: 0
      })
    );

    // Add two pull providers
    _expectRoleProviderAdded(address(mockProvider1), 1, 0);
    hooks.addRoleProvider(address(mockProvider1), 1);

    _expectRoleProviderAdded(address(mockProvider2), 1, 1);
    hooks.addRoleProvider(address(mockProvider2), 1);

    _expectRoleProviderRemoved(address(mockProvider1), 0);
    _expectRoleProviderUpdated(address(mockProvider2), 1, 0);

    hooks.removeRoleProvider(address(mockProvider1));
    _validateRoleProviders();
  }

  // ========================================================================== //
  //                               Role Management                              //
  // ========================================================================== //

  /// @dev `grantRole` reverts if the provider is not found.
  function test_grantRole_ProviderNotFound(address account, uint32 timestamp) external {
    vm.prank(address(1));
    vm.expectRevert(AccessControlHooks.ProviderNotFound.selector);
    hooks.grantRole(address(2), timestamp);
  }

  /// @dev `grantRole` reverts if the timestamp + TTL is less than the current time.
  function test_grantRole_GrantedCredentialExpired(
    address account,
    bool isPullProvider,
    uint32 timeToLive,
    uint32 timestamp
  ) external {
    uint256 maxExpiry = block.timestamp - 1;
    timeToLive = uint32(bound(timeToLive, 0, maxExpiry));
    timestamp = uint32(bound(timestamp, 0, maxExpiry - timeToLive));
    StandardRoleProvider storage provider = _addExpectedProvider(
      mockProvider1,
      timeToLive,
      isPullProvider
    );
    hooks.addRoleProvider(address(mockProvider1), timeToLive);

    vm.prank(address(mockProvider1));
    vm.expectRevert(AccessControlHooks.GrantedCredentialExpired.selector);
    hooks.grantRole(account, timestamp);
  }

  function test_grantRole(
    address account,
    bool isPullProvider,
    uint32 timeToLive,
    uint32 timestamp
  ) external {
    timestamp = uint32(bound(timestamp, block.timestamp.satSub(timeToLive), type(uint32).max));
    _addExpectedProvider(mockProvider1, timeToLive, isPullProvider);
    hooks.addRoleProvider(address(mockProvider1), timeToLive);
    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    hooks.grantRole(account, timestamp);
  }

  /// @dev Provider can replace credentials with an earlier expiry
  function test_grantRole_laterExpiry(
    address account,
    uint32 timeToLive1,
    uint32 timeToLive2,
    uint32 timestamp
  ) external {
    timeToLive1 = uint32(bound(timeToLive1, 0, type(uint32).max - 1));
    timeToLive2 = uint32(bound(timeToLive2, timeToLive1 + 1, type(uint32).max));
    // Make sure the timestamp will result in provider 1 granting expiry that will expire (not max uint32)
    timestamp = uint32(
      bound(
        timestamp,
        block.timestamp.satSub(timeToLive1),
        uint(type(uint32).max).satSub(timeToLive1) - 1
      )
    );
    hooks.addRoleProvider(address(mockProvider1), timeToLive1);
    hooks.addRoleProvider(address(mockProvider2), timeToLive2);

    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    hooks.grantRole(account, timestamp);

    _expectAccountAccessGranted(address(mockProvider2), account, timestamp);
    vm.prank(address(mockProvider2));
    hooks.grantRole(account, timestamp);
  }

  /// @dev Provider can replace credentials if the provider has been removed
  function test_grantRole_oldProviderRemoved(
    address account,
    uint32 timeToLive1,
    uint32 timeToLive2,
    uint32 timestamp
  ) external {
    // Make sure the second TTL is less than the first so that we know the reason it works isn't that
    // the expiry is newer.
    timeToLive2 = uint32(bound(timeToLive2, 0, type(uint32).max - 1));
    timeToLive1 = uint32(bound(timeToLive1, timeToLive2 + 1, type(uint32).max));
    // Make sure the timestamp won't result in an expired credential
    timestamp = uint32(
      bound(
        timestamp,
        block.timestamp.satSub(timeToLive2),
        uint(type(uint32).max).satSub(timeToLive2) - 1
      )
    );
    hooks.addRoleProvider(address(mockProvider1), timeToLive1);
    hooks.addRoleProvider(address(mockProvider2), timeToLive2);

    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    hooks.grantRole(account, timestamp);

    _expectRoleProviderRemoved(address(mockProvider1), NotPullProviderIndex);
    hooks.removeRoleProvider(address(mockProvider1));

    _expectAccountAccessGranted(address(mockProvider2), account, timestamp);
    vm.prank(address(mockProvider2));
    hooks.grantRole(account, timestamp);
  }

  /// @dev Provider can not replace a credential from another provider unless it has
  ///      a greater expiry.
  function test_grantRole_ProviderCanNotReplaceCredential(
    address account,
    uint32 timeToLive1,
    uint32 timeToLive2,
    uint32 timestamp
  ) external {
    timeToLive1 = uint32(bound(timeToLive1, 0, type(uint32).max - 1));
    timeToLive2 = uint32(bound(timeToLive2, timeToLive1 + 1, type(uint32).max));
    // Make sure the timestamp will result in provider 1 granting expiry that will expire (not max uint32)
    timestamp = uint32(
      bound(
        timestamp,
        block.timestamp.satSub(timeToLive1) + 1,
        uint(type(uint32).max).satSub(timeToLive1)
      )
    );
    hooks.addRoleProvider(address(mockProvider1), timeToLive2);
    hooks.addRoleProvider(address(mockProvider2), timeToLive1);

    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    hooks.grantRole(account, timestamp);

    vm.expectRevert(AccessControlHooks.ProviderCanNotReplaceCredential.selector);
    vm.prank(address(mockProvider2));
    hooks.grantRole(account, timestamp);
  }

  function test_fuzz_getOrValidateCredential(
    AccessControlHooksFuzzInputs memory fuzzInputs
  ) external {
    AccessControlHooksFuzzContext memory context = createAccessControlHooksFuzzContext(
      fuzzInputs,
      hooks,
      mockProvider1,
      mockProvider2,
      address(50)
    );
    context.registerExpectations(true);
    if (context.expectations.expectedError != 0) {
      hooks.tryValidateAccess(context.account, context.hooksData);
    } else {
      (bool hasValidCredential, bool wasUpdated) = hooks.tryValidateAccess(
        context.account,
        context.hooksData
      );
      assertEq(hasValidCredential, context.expectations.hasValidCredential, 'hasValidCredential');
      assertEq(wasUpdated, context.expectations.wasUpdated, 'wasUpdated');
      LenderStatus memory status = hooks.getPreviousLenderStatus(context.account);
      assertEq(status.lastProvider, context.expectations.lastProvider, 'lastProvider');
      assertEq(
        status.lastApprovalTimestamp,
        context.expectations.lastApprovalTimestamp,
        'lastApprovalTimestamp'
      );
    }
  }

  struct UserAccessContext {
    // Whether user already has credential
    bool userHasCredential;
    // Whether user's credential is expired
    bool userCredentialExpired;
    // Whether last credential is expired
    bool lastProviderRemoved;
    // Whether last provider is a pull provider
    bool lastProviderIsPullProvider;
    // Whether last

    bool expiredCredentialWillBeRefreshed;
    bool someProviderWillGrantCredential;
  }

  function test_tryValidateAccess_existingCredential(address account) external {
    hooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    hooks.grantRole(account, uint32(block.timestamp));

    (bool hasValidCredential, bool wasUpdated) = hooks.tryValidateAccess(account, '');
    assertTrue(hasValidCredential, 'hasValidCredential');
    assertFalse(wasUpdated, 'wasUpdated');
  }

  function test_tryValidateAccess_validateCredential(address account) external {}

  function test_getParameterConstraints() external view {
    MarketParameterConstraints memory constraints = hooks.getParameterConstraints();
    assertEq(constraints.minimumDelinquencyGracePeriod, 0, 'minimumDelinquencyGracePeriod');
    assertEq(constraints.maximumDelinquencyGracePeriod, 90 days, 'maximumDelinquencyGracePeriod');
    assertEq(constraints.minimumReserveRatioBips, 0, 'minimumReserveRatioBips');
    assertEq(constraints.maximumReserveRatioBips, 10_000, 'maximumReserveRatioBips');
    assertEq(constraints.minimumDelinquencyFeeBips, 0, 'minimumDelinquencyFeeBips');
    assertEq(constraints.maximumDelinquencyFeeBips, 10_000, 'maximumDelinquencyFeeBips');
    assertEq(constraints.minimumWithdrawalBatchDuration, 0, 'minimumWithdrawalBatchDuration');
    assertEq(
      constraints.maximumWithdrawalBatchDuration,
      365 days,
      'maximumWithdrawalBatchDuration'
    );
    assertEq(constraints.minimumAnnualInterestBips, 0, 'minimumAnnualInterestBips');
    assertEq(constraints.maximumAnnualInterestBips, 10_000, 'maximumAnnualInterestBips');
  }

  function test_grantRoles() external {
    address[] memory accounts = new address[](4);
    for (uint160 i; i < accounts.length; i++) {
      accounts[i] = address(i);
    }
    uint32 timestamp= uint32(block.timestamp + 1);
    hooks.addRoleProvider(address(mockProvider1), 1);

    uint32[] memory timestamps = new uint32[](accounts.length);
    for (uint i; i < accounts.length; i++) {
      timestamps[i] = timestamp;
    }
    vm.prank(address(mockProvider1));
    hooks.grantRoles(accounts, timestamps);
    vm.prank(address(mockProvider1));
    hooks.grantRoles(accounts, timestamps);
  }
}