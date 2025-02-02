// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/access/BaseAccessControls.sol';
import { LibString } from 'solady/utils/LibString.sol';
import '../shared/mocks/MockRoleProvider.sol';
import '../shared/mocks/MockRoleProviderFactory.sol';
import '../helpers/Assertions.sol';
import { bound, warp } from '../helpers/VmUtils.sol';
import { AccessControlHooksFuzzInputs, AccessControlHooksFuzzContext, OpenTermHooks, createAccessControlHooksFuzzContext, FunctionKind } from '../helpers/fuzz/AccessControlHooksFuzzContext.sol';
import { Prankster } from 'sol-utils/test/Prankster.sol';
import { getTimestamp, fastForward } from '../helpers/VmUtils.sol';

using LibString for uint256;
using LibString for address;
using MathUtils for uint256;

abstract contract MockBaseAccessControls is BaseAccessControls {
  function tryValidateAccess(
    address accountAddress,
    bytes calldata hooksData
  ) external virtual returns (bool hasValidCredential, bool wasUpdated);

  function setIsKnownLender(
    address accountAddress,
    address marketAddress,
    bool isKnownLender
  ) external virtual;
}

abstract contract BaseAccessControlsTest is Test, Assertions, Prankster {
  uint24 internal numPullProviders;
  uint24 internal numPushProviders;
  StandardRoleProvider[] internal expectedRoleProviders;
  MockBaseAccessControls internal baseHooks;
  MockRoleProvider internal mockProvider1 = new MockRoleProvider();
  MockRoleProvider internal mockProvider2 = new MockRoleProvider();
  MockRoleProviderFactory internal providerFactory = new MockRoleProviderFactory();

  bytes4 internal constant Panic_ErrorSelector = 0x4e487b71;
  uint256 internal constant Panic_Arithmetic = 0x11;

  function _getIsKnownLenderStatus(AccessControlHooksFuzzContext memory context) internal {
    baseHooks.setIsKnownLender(context.account, context.market, true);
  }

  // ========================================================================== //
  //                              State validation                              //
  // ========================================================================== //

  function _addExpectedProvider(
    MockRoleProvider mockProvider,
    uint32 timeToLive,
    bool isPullProvider
  ) internal returns (StandardRoleProvider storage) {
    if (address(mockProvider) != address(this) && address(mockProvider).code.length > 0) {
      mockProvider.setIsPullProvider(isPullProvider);
    }
    uint24 pullProviderIndex = isPullProvider ? numPullProviders++ : NullProviderIndex;
    uint24 pushProviderIndex = isPullProvider ? NullProviderIndex : numPushProviders++;
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider),
        timeToLive: timeToLive,
        pullProviderIndex: pullProviderIndex,
        pushProviderIndex: pushProviderIndex
      })
    );
    return expectedRoleProviders[expectedRoleProviders.length - 1];
  }

  function _validateRoleProviders() internal {
    RoleProvider[] memory pullProviders = baseHooks.getPullProviders();
    RoleProvider[] memory pushProviders = baseHooks.getPushProviders();
    uint256 pullIndex;
    uint256 pushIndex;
    for (uint i; i < expectedRoleProviders.length; i++) {
      if (expectedRoleProviders[i].pullProviderIndex != NullProviderIndex) {
        if (pullIndex >= pullProviders.length) {
          emit log('Error: provider with pullProviderIndex not found');
          fail();
        }
        // Check pull provider matches expected provider
        string memory label = string.concat('pullProviders[', pullIndex.toString(), '].');
        assertEq(pullProviders[pullIndex++], expectedRoleProviders[i], label);
      }
      if (expectedRoleProviders[i].pushProviderIndex != NullProviderIndex) {
        if (pushIndex >= pushProviders.length) {
          emit log('Error: provider with pushProviderIndex not found');
          fail();
        }
        // Check pull provider matches expected provider
        string memory label = string.concat('pushProviders[', pushIndex.toString(), '].');
        assertEq(pushProviders[pushIndex++], expectedRoleProviders[i], label);
      }
      address providerAddress = expectedRoleProviders[i].providerAddress;
      // Check _roleProviders[provider] matches expected provider
      RoleProvider provider = baseHooks.getRoleProvider(providerAddress);
      assertEq(
        provider,
        expectedRoleProviders[i],
        string.concat('getRoleProvider(', providerAddress.toHexString(), ').')
      );
    }
    assertEq(pullIndex, pullProviders.length, 'pullProviders.length');
    assertEq(pushIndex, pushProviders.length, 'pushProviders.length');
  }

  function _expectRoleProviderAdded(
    address providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex,
    uint24 pushProviderIndex
  ) internal {
    vm.expectEmit();
    emit BaseAccessControls.RoleProviderAdded(
      providerAddress,
      timeToLive,
      pullProviderIndex,
      pushProviderIndex
    );
  }

  function _expectRoleProviderUpdated(
    address providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex,
    uint24 pushProviderIndex
  ) internal {
    vm.expectEmit();
    emit BaseAccessControls.RoleProviderUpdated(
      providerAddress,
      timeToLive,
      pullProviderIndex,
      pushProviderIndex
    );
  }

  function _expectRoleProviderRemoved(
    address providerAddress,
    uint24 pullProviderIndex,
    uint24 pushProviderIndex
  ) internal {
    vm.expectEmit();
    emit BaseAccessControls.RoleProviderRemoved(
      providerAddress,
      pullProviderIndex,
      pushProviderIndex
    );
  }

  function _expectAccountAccessGranted(
    address providerAddress,
    address accountAddress,
    uint32 credentialTimestamp
  ) internal {
    vm.expectEmit();
    emit BaseAccessControls.AccountAccessGranted(
      providerAddress,
      accountAddress,
      credentialTimestamp
    );
  }

  // ========================================================================== //
  //                                   setName                                  //
  // ========================================================================== //

  function test_setName_CallerNotBorrower() external {
    vm.prank(address(1));
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    baseHooks.setName('');
  }

  function test_setName() external {
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.NameUpdated('New Name');
    baseHooks.setName('New Name');
    assertEq(baseHooks.name(), 'New Name', 'name');
  }

  // ========================================================================== //
  //                          Role provider management                          //
  // ========================================================================== //

  function test_createRoleProvider_CallerNotBorrower(
    bool isPullProvider,
    uint32 timeToLive
  ) external {
    vm.prank(address(1));
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    baseHooks.createRoleProvider(address(1), 0, '');
  }

  function test_createRoleProvider(bool isPullProvider, uint32 timeToLive) external {
    bytes32 salt = bytes32(uint256(1));
    bytes memory factoryInput = abi.encode(salt, isPullProvider);
    address expectedProviderAddress = providerFactory.computeProviderAddress(salt);
    _addExpectedProvider(MockRoleProvider(expectedProviderAddress), timeToLive, isPullProvider);
    _expectRoleProviderAdded(
      expectedProviderAddress,
      timeToLive,
      isPullProvider ? 0 : NullProviderIndex,
      isPullProvider ? NullProviderIndex : 1
    );
    baseHooks.createRoleProvider(address(providerFactory), timeToLive, factoryInput);
  }

  function test_createRoleProvider_CreateRoleProviderFailed(
    bool isPullProvider,
    uint32 timeToLive
  ) external {
    bytes32 salt = bytes32(uint256(1));
    bytes memory factoryInput = abi.encode(salt, isPullProvider);
    address expectedProviderAddress = providerFactory.computeProviderAddress(salt);
    providerFactory.setNextProviderAddress(address(0));
    vm.expectRevert(BaseAccessControls.CreateRoleProviderFailed.selector);
    baseHooks.createRoleProvider(address(providerFactory), timeToLive, factoryInput);
  }

  function test_addRoleProvider(bool isPullProvider, uint32 timeToLive) external {
    mockProvider1.setIsPullProvider(isPullProvider);

    uint24 pullProviderIndex = isPullProvider ? 0 : NullProviderIndex;
    uint24 pushProviderIndex = isPullProvider ? NullProviderIndex : 1;
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider1),
        timeToLive: timeToLive,
        pullProviderIndex: pullProviderIndex,
        pushProviderIndex: pushProviderIndex
      })
    );

    _expectRoleProviderAdded(
      address(mockProvider1),
      timeToLive,
      pullProviderIndex,
      pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive);

    _validateRoleProviders();
  }

  function test_addRoleProvider_CallerNotBorrower() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    baseHooks.addRoleProvider(address(2), 1);
  }

  function test_addRoleProvider_badInterface(uint32 timeToLive) external {
    vm.expectRevert();
    baseHooks.addRoleProvider(address(2), timeToLive);
    _validateRoleProviders();
  }

  function test_addRoleProvider_updateTimeToLive(uint32 ttl1, uint32 ttl2) external {
    StandardRoleProvider storage provider = _addExpectedProvider(mockProvider1, ttl1, true);
    _expectRoleProviderAdded(
      address(mockProvider1),
      ttl1,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl1);

    // Validate the initial state
    _validateRoleProviders();

    // Update the TTL using `addRoleProvider`
    provider.timeToLive = ttl2;
    _expectRoleProviderUpdated(
      address(mockProvider1),
      ttl2,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl2);

    // Validate the updated state
    _validateRoleProviders();
  }

  function test_addRoleProvider_updateTimeToLive2(uint32 ttl1, uint32 ttl2) external {
    StandardRoleProvider storage provider = _addExpectedProvider(mockProvider1, ttl1, false);
    _expectRoleProviderAdded(
      address(mockProvider1),
      ttl1,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl1);

    // Validate the initial state
    _validateRoleProviders();

    // Update the TTL using `addRoleProvider`
    provider.timeToLive = ttl2;
    _expectRoleProviderUpdated(
      address(mockProvider1),
      ttl2,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl2);

    // Validate the updated state
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
    _expectRoleProviderAdded(
      address(mockProvider1),
      ttl1,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl1);

    // Validate the initial state
    _validateRoleProviders();

    // Update the TTL using `addRoleProvider`
    provider.timeToLive = ttl2;
    _expectRoleProviderUpdated(
      address(mockProvider1),
      ttl2,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl2);

    // Validate the updated state
    _validateRoleProviders();
  }

  function test_removeRoleProvider(bool isPullProvider, uint32 timeToLive) external {
    StandardRoleProvider storage provider = _addExpectedProvider(
      mockProvider1,
      timeToLive,
      isPullProvider
    );

    baseHooks.addRoleProvider(address(mockProvider1), timeToLive);

    _expectRoleProviderRemoved(
      address(mockProvider1),
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.removeRoleProvider(address(mockProvider1));
    expectedRoleProviders.pop();

    _validateRoleProviders();
  }

  function test_removeRoleProvider_CallerNotBorrower() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    baseHooks.removeRoleProvider(address(mockProvider1));
  }

  function test_removeRoleProvider_ProviderNotFound() external {
    vm.expectRevert(BaseAccessControls.ProviderNotFound.selector);
    baseHooks.removeRoleProvider(address(2));
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
        pullProviderIndex: 0,
        pushProviderIndex: NullProviderIndex
      })
    );
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    baseHooks.addRoleProvider(address(mockProvider2), 1);

    _expectRoleProviderRemoved(address(mockProvider2), 1, NullProviderIndex);
    baseHooks.removeRoleProvider(address(mockProvider2));
    _validateRoleProviders();
  }

  /// @dev Remove a pull provider that is not the last pull provider.
  ///      Should cause the last pull provider to be moved to the
  ///      removed provider's index
  function test_removeRoleProvider_NotLastPullProvider() external {
    mockProvider1.setIsPullProvider(true);
    mockProvider2.setIsPullProvider(true);
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider2),
        timeToLive: 1,
        pullProviderIndex: 0,
        pushProviderIndex: NullProviderIndex
      })
    );

    // Add two pull providers
    _expectRoleProviderAdded(address(mockProvider1), 1, 0, NullProviderIndex);
    baseHooks.addRoleProvider(address(mockProvider1), 1);

    _expectRoleProviderAdded(address(mockProvider2), 1, 1, NullProviderIndex);
    baseHooks.addRoleProvider(address(mockProvider2), 1);

    _expectRoleProviderRemoved(address(mockProvider1), 0, NullProviderIndex);
    _expectRoleProviderUpdated(address(mockProvider2), 1, 0, NullProviderIndex);

    baseHooks.removeRoleProvider(address(mockProvider1));
    _validateRoleProviders();
  }

  /// @dev Remove a push provider that is not the last push provider.
  ///      Should cause the last push provider to be moved to the
  ///      removed provider's index
  function test_removeRoleProvider_NotLastPushProvider() external {
    mockProvider1.setIsPullProvider(false);
    mockProvider2.setIsPullProvider(false);
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider2),
        timeToLive: 1,
        pullProviderIndex: NullProviderIndex,
        pushProviderIndex: 1
      })
    );

    // Add two pull providers
    _expectRoleProviderAdded(address(mockProvider1), 1, NullProviderIndex, 1);
    baseHooks.addRoleProvider(address(mockProvider1), 1);

    _expectRoleProviderAdded(address(mockProvider2), 1, NullProviderIndex, 2);
    baseHooks.addRoleProvider(address(mockProvider2), 1);

    _expectRoleProviderRemoved(address(mockProvider1), NullProviderIndex, 1);
    _expectRoleProviderUpdated(address(mockProvider2), 1, NullProviderIndex, 1);

    baseHooks.removeRoleProvider(address(mockProvider1));
    _validateRoleProviders();
  }

  // ========================================================================== //
  //                                  grantRole                                 //
  // ========================================================================== //

  /// @dev `grantRole` reverts if the provider is not found.
  function test_grantRole_ProviderNotFound(address account, uint32 timestamp) external {
    vm.prank(address(1));
    vm.expectRevert(BaseAccessControls.ProviderNotFound.selector);
    baseHooks.grantRole(address(2), timestamp);
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
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive);

    vm.prank(address(mockProvider1));
    vm.expectRevert(BaseAccessControls.GrantedCredentialExpired.selector);
    baseHooks.grantRole(account, timestamp);
  }

  function test_grantRole(
    address account,
    bool isPullProvider,
    uint32 timeToLive,
    uint32 timestamp
  ) external {
    timestamp = uint32(bound(timestamp, block.timestamp.satSub(timeToLive), type(uint32).max));
    _addExpectedProvider(mockProvider1, timeToLive, isPullProvider);
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive);
    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, timestamp);
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
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive1);
    baseHooks.addRoleProvider(address(mockProvider2), timeToLive2);

    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, timestamp);

    _expectAccountAccessGranted(address(mockProvider2), account, timestamp);
    vm.prank(address(mockProvider2));
    baseHooks.grantRole(account, timestamp);
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
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive1);
    baseHooks.addRoleProvider(address(mockProvider2), timeToLive2);

    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, timestamp);

    _expectRoleProviderRemoved(address(mockProvider1), NullProviderIndex, 1);
    _expectRoleProviderUpdated(address(mockProvider2), timeToLive2, NullProviderIndex, 1);
    baseHooks.removeRoleProvider(address(mockProvider1));

    _expectAccountAccessGranted(address(mockProvider2), account, timestamp);
    vm.prank(address(mockProvider2));
    baseHooks.grantRole(account, timestamp);
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
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive2);
    baseHooks.addRoleProvider(address(mockProvider2), timeToLive1);

    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, timestamp);

    vm.expectRevert(BaseAccessControls.ProviderCanNotReplaceCredential.selector);
    vm.prank(address(mockProvider2));
    baseHooks.grantRole(account, timestamp);
  }

  // ========================================================================== //
  //                               getLenderStatus                              //
  // ========================================================================== //

  function test_getLenderStatus_loop() external {
    address bob = address(0xb0b);
    mockProvider1.setIsPullProvider(false);
    mockProvider2.setIsPullProvider(true);
    mockProvider2.setCredential(bob, uint32(block.timestamp));
    baseHooks.addRoleProvider(address(mockProvider1), type(uint32).max);
    baseHooks.addRoleProvider(address(mockProvider2), type(uint32).max);
    LenderStatus memory status = baseHooks.getLenderStatus(bob);
    assertEq(status.lastProvider, address(mockProvider2), 'lastProvider');
    assertEq(status.lastApprovalTimestamp, block.timestamp, 'lastApprovalTimestamp');
    assertEq(status.canRefresh, true, 'canRefresh');
    assertEq(status.isBlockedFromDeposits, false, 'isBlockedFromDeposits');
  }

  function test_getLenderStatus_refresh() external {
    address bob = address(0xb0b);
    mockProvider1.setIsPullProvider(false);
    mockProvider2.setIsPullProvider(true);
    mockProvider2.setCredential(bob, uint32(block.timestamp));
    baseHooks.addRoleProvider(address(mockProvider1), type(uint32).max);
    baseHooks.addRoleProvider(address(mockProvider2), 1);
    fastForward(2);
    uint32 newTimestamp = uint32(getTimestamp());
    mockProvider2.setCredential(bob, newTimestamp);
    LenderStatus memory status = baseHooks.getLenderStatus(bob);
    assertEq(status.lastProvider, address(mockProvider2), 'lastProvider');
    assertEq(status.lastApprovalTimestamp, newTimestamp, 'lastApprovalTimestamp');
    assertEq(status.canRefresh, true, 'canRefresh');
    assertEq(status.isBlockedFromDeposits, false, 'isBlockedFromDeposits');
  }

  // ========================================================================== //
  //                           getOrValidateCredential                          //
  // ========================================================================== //

  function test_fuzz_getOrValidateCredential(
    AccessControlHooksFuzzInputs memory fuzzInputs
  ) external {
    AccessControlHooksFuzzContext memory context = createAccessControlHooksFuzzContext(
      fuzzInputs,
      address(1),
      OpenTermHooks(address(baseHooks)),
      mockProvider1,
      mockProvider2,
      address(50),
      FunctionKind.HooksFunction,
      0,
      _getIsKnownLenderStatus,
      0
    );
    context.registerExpectations(true);
    if (context.expectations.expectedError != 0) {
      baseHooks.tryValidateAccess(context.account, context.hooksData);
    } else {
      (bool hasValidCredential, bool wasUpdated) = baseHooks.tryValidateAccess(
        context.account,
        context.hooksData
      );
      assertEq(hasValidCredential, context.expectations.hasValidCredential, 'hasValidCredential');
      assertEq(wasUpdated, context.expectations.wasUpdated, 'wasUpdated');
      LenderStatus memory status = baseHooks.getLenderStatus(context.account);
      assertEq(status, baseHooks.getPreviousLenderStatus(context.account), 'status');
      assertEq(status.lastProvider, context.expectations.lastProvider, 'lastProvider');
      assertEq(
        status.lastApprovalTimestamp,
        context.expectations.lastApprovalTimestamp,
        'lastApprovalTimestamp'
      );
    }
    context.validate();
  }

  // ========================================================================== //
  //                              tryValidateAccess                             //
  // ========================================================================== //

  function test_tryValidateAccess_existingCredential(address account) external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, uint32(block.timestamp));

    (bool hasValidCredential, bool wasUpdated) = baseHooks.tryValidateAccess(account, '');
    assertTrue(hasValidCredential, 'hasValidCredential');
    assertFalse(wasUpdated, 'wasUpdated');
  }

  function test_tryValidateAccess_validateCredential(address account) external {}

  // ========================================================================== //
  //                                 grantRoles                                 //
  // ========================================================================== //

  function test_grantRoles() external {
    address[] memory accounts = new address[](4);
    for (uint160 i; i < accounts.length; i++) {
      accounts[i] = address(i);
    }
    uint32 timestamp = uint32(block.timestamp + 1);
    baseHooks.addRoleProvider(address(mockProvider1), 1);

    uint32[] memory timestamps = new uint32[](accounts.length);
    for (uint i; i < accounts.length; i++) {
      timestamps[i] = timestamp;
    }
    vm.prank(address(mockProvider1));
    baseHooks.grantRoles(accounts, timestamps);
    vm.prank(address(mockProvider1));
    baseHooks.grantRoles(accounts, timestamps);
  }

  function test_grantRoles_InvalidArrayLength() external {
    address[] memory accounts = new address[](4);
    uint32[] memory timestamps = new uint32[](3);
    vm.expectRevert(BaseAccessControls.InvalidArrayLength.selector);
    baseHooks.grantRoles(accounts, timestamps);
  }

  /// @dev `grantRole` reverts if the provider is not found.
  function test_grantRoles_ProviderNotFound(address account, uint32 timestamp) external {
    address[] memory accounts = new address[](1);
    uint32[] memory timestamps = new uint32[](1);
    vm.prank(address(1));
    vm.expectRevert(BaseAccessControls.ProviderNotFound.selector);
    baseHooks.grantRoles(accounts, timestamps);
  }

  // ========================================================================== //
  //                                 revokeRole                                 //
  // ========================================================================== //

  function test_revokeRole() external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.startPrank(address(mockProvider1));
    baseHooks.grantRole(address(1), uint32(block.timestamp));
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountAccessRevoked(address(1));
    baseHooks.revokeRole(address(1));
  }

  function test_revokeRole_ProviderCanNotRevokeCredential() external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(address(1), uint32(block.timestamp));
    vm.prank(address(mockProvider2));
    vm.expectRevert(BaseAccessControls.ProviderCanNotRevokeCredential.selector);
    baseHooks.revokeRole(address(1));
  }

  // ========================================================================== //
  //                                 revokeRoles                                //
  // ========================================================================== //

  function test_revokeRoles() external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    address[] memory lenders = new address[](1);
    lenders[0] = address(1);
    vm.startPrank(address(mockProvider1));
    baseHooks.grantRole(address(1), uint32(block.timestamp));
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountAccessRevoked(address(1));
    baseHooks.revokeRoles(lenders);
  }

  function test_revokeRoles_ProviderCanNotRevokeCredential() external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    address[] memory lenders = new address[](1);
    lenders[0] = address(1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(address(1), uint32(block.timestamp));
    vm.prank(address(mockProvider2));
    vm.expectRevert(BaseAccessControls.ProviderCanNotRevokeCredential.selector);
    baseHooks.revokeRoles(lenders);
  }

  // ========================================================================== //
  //                              blockFromDeposits                             //
  // ========================================================================== //

  function test_blockFromDeposits_CallerNotBorrower() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    baseHooks.blockFromDeposits(address(1));
  }

  function test_blockFromDeposits(address account) external {
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountBlockedFromDeposits(account);
    baseHooks.blockFromDeposits(account);
    LenderStatus memory status = baseHooks.getLenderStatus(account);
    assertEq(status.isBlockedFromDeposits, true, 'isBlockedFromDeposits');
  }

  function test_blockFromDeposits_UnsetsCredential(address account) external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, uint32(block.timestamp));

    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountAccessRevoked(account);
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountBlockedFromDeposits(account);

    baseHooks.blockFromDeposits(account);
    LenderStatus memory status = baseHooks.getLenderStatus(account);
    assertEq(status.isBlockedFromDeposits, true, 'isBlockedFromDeposits');
  }

  function test_blockFromDeposits_multiple_CallerNotBorrower() external asAccount(address(1)) {
    address[] memory accounts = new address[](1);
    accounts[0] = address(0);
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    baseHooks.blockFromDeposits(accounts);
  }

  function test_blockFromDeposits_multiple(address account) external {
    address[] memory accounts = new address[](1);
    accounts[0] = account;
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountBlockedFromDeposits(account);
    baseHooks.blockFromDeposits(accounts);
    LenderStatus memory status = baseHooks.getLenderStatus(account);
    assertEq(status.isBlockedFromDeposits, true, 'isBlockedFromDeposits');
  }

  function test_blockFromDeposits_multiple_UnsetsCredential(address account) external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, uint32(block.timestamp));

    address[] memory accounts = new address[](1);
    accounts[0] = account;

    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountAccessRevoked(account);
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountBlockedFromDeposits(account);

    baseHooks.blockFromDeposits(accounts);
    LenderStatus memory status = baseHooks.getLenderStatus(account);
    assertEq(status.isBlockedFromDeposits, true, 'isBlockedFromDeposits');
  }

  // ========================================================================== //
  //                             unblockFromDeposits                            //
  // ========================================================================== //

  function test_unblockFromDeposits_CallerNotBorrower() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    baseHooks.unblockFromDeposits(address(1));
  }

  function test_unblockFromDeposits(address account) external {
    baseHooks.blockFromDeposits(account);
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountUnblockedFromDeposits(account);
    baseHooks.unblockFromDeposits(account);
    LenderStatus memory status = baseHooks.getLenderStatus(account);
    assertEq(status.isBlockedFromDeposits, false, 'isBlockedFromDeposits');
  }
}
