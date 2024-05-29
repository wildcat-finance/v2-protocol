// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/access/AccessControlHooks.sol';
import { LibString } from 'solady/utils/LibString.sol';
import '../shared/mocks/MockRoleProvider.sol';
import '../shared/mocks/MockAccessControlHooks.sol';
import '../helpers/Assertions.sol';

import { bound } from '../helpers/VmUtils.sol';
import 'sol-utils/ir-only/MemoryPointer.sol';
import { ArrayHelpers } from 'sol-utils/ir-only/ArrayHelpers.sol';

import 'src/libraries/BoolUtils.sol';

using LibString for uint256;
using LibString for address;
using MathUtils for uint256;
using BoolUtils for bool;

struct ExpectedCall {
  address target;
  bytes data;
}

contract AccessControlHooksTest is Test, Assertions {
  using AccessControlTestTypeCasts for *;

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
    vm.warp(1714737030);
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
    StandardRoleProvider storage provider = _addExpectedProvider(
      mockProvider1,
      timeToLive,
      isPullProvider
    );
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
    bool isPullProvider,
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

  /*

bytes memory hooksData;
if (
  credential.credentialExists &&
  !credential.expired &&
  credential.providerApproved
) {
  // Returns true, no update, no calls made
}
// Hooks stage
if (hooksData.giveHooksData) {
  if (hooksData.giveDataToValidate) {
    hooksData = hex"aabbccddeeff";
    provider.approveCredentialData()
  }
}

    Scenarios to test:
    1. User has existing credential
      - Pass conditions:
        - !expired & providerApproved
        - expired & providerApproved & isPullProvider & willRefresh
      - Fail conditions:
        - !expired + !providerApproved  
        - expired + providerApproved + !isPullProvider
        - expired + providerApproved + isPullProvider + !willRefresh
    2. User has expired credential
      - Provider does not exist
      - Provider exists but is not a pull provider
      - Provider is a pull provider and will refresh credential
      - Provider is a pull provider and will not refresh credential
    3. User has no credential:
      - No pull providers will grant credential
      - There is a pull provider that will grant a credential
  */

  struct ExistingCredentialOptions {
    // Whether the user has an existing credential
    bool credentialExists;
    // Whether the provider that granted the credential is still approved
    bool providerApproved;
    // Whether the credential is expired
    bool expired;
    // Whether the provider is a pull provider
    bool isPullProvider;
    // Whether provider will return valid encoded timestamp
    bool willReturnUint;
    // Provider will grant credential, but credential is expired
    bool newCredentialExpired;
    // Provider will revert on getCredential
    bool callWillRevert;
  }

  // @todo handle cases where timestamp > block.timestamp
  struct HooksDataOptions {
    // Whether to give any hooks data
    bool giveHooksData;
    // Give data for validation rather than just the provider address
    bool giveDataToValidate;
    // Provider exists
    bool providerApproved;
    // Provider is a pull provider
    bool isPullProvider;
    // Whether provider will return valid encoded timestamp
    bool willReturnUint;
    // Provider will grant credential, but credential is expired
    bool credentialExpired;
    // Provider will revert on validateCredential / getCredential
    bool callWillRevert;
  }

  function test_fuzz_getOrValidateCredential(
    ExistingCredentialOptions memory existingCredentialOptions,
    HooksDataOptions memory dataOptions
  ) external {
    // ExistingCredentialOptions memory existingCredentialOptions;
    // existingCredentialOptions.credentialExists = true;
    // existingCredentialOptions.providerApproved = true;
    // existingCredentialOptions.expired = false;

    HookValidationContext memory context;
    context.account = address(50);
    context.existingCredentialOptions = existingCredentialOptions;
    context.dataOptions = dataOptions;
    context.previousProvider = mockProvider1;
    context.providerToGiveData = mockProvider2;
    vm.label(address(mockProvider1), 'previousProvider');
    vm.label(address(mockProvider2), 'providerToGiveData');

    _setUpExistingCredential(context);
    _setUpHooksData(context);
    _setUpCredentialRefresh(context);

    // If a previous credential exists but the lender will not end up with a valid credential,
    // the last provider and approval timestamp should be reset
    if (existingCredentialOptions.credentialExists && !context.expectations.hasValidCredential) {
      context.expectations.wasUpdated = true;
      context.expectations.lastProvider = address(0);
      context.expectations.lastApprovalTimestamp = 0;
    }

    for (uint i; i < context.expectations.expectedCalls.length; i++) {
      vm.expectCall(
        context.expectations.expectedCalls[i].target,
        context.expectations.expectedCalls[i].data
      );
    }
    if (context.expectations.expectedError != 0) {
      vm.expectRevert(context.expectations.expectedError);
      hooks.tryValidateAccess(context.account, context.hooksData);
    } else {
      (bool hasValidCredential, bool wasUpdated) = hooks.tryValidateAccess(
        context.account,
        context.hooksData
      );
      assertEq(hasValidCredential, context.expectations.hasValidCredential, 'hasValidCredential');
      assertEq(wasUpdated, context.expectations.wasUpdated, 'wasUpdated');
    }
  }

  struct ValidationExpectations {
    bool hasValidCredential;
    bool wasUpdated;
    ExpectedCall[] expectedCalls;
    bytes4 expectedError;
    address lastProvider;
    uint32 lastApprovalTimestamp;
  }

  struct HookValidationContext {
    address account;
    bytes hooksData;
    ExistingCredentialOptions existingCredentialOptions;
    HooksDataOptions dataOptions;
    ValidationExpectations expectations;
    MockRoleProvider previousProvider;
    MockRoleProvider providerToGiveData;
  }

  function _setUpExistingCredential(HookValidationContext memory context) internal {
    MockRoleProvider provider = context.previousProvider;
    ExistingCredentialOptions memory existingCredentialOptions = context.existingCredentialOptions;
    if (existingCredentialOptions.credentialExists) {
      // If the credential should exist, add the provider and grant the role
      uint32 credentialTimestamp = existingCredentialOptions.expired
        ? uint32(block.timestamp - 2)
        : uint32(block.timestamp);

      if (existingCredentialOptions.isPullProvider) {
        provider.setIsPullProvider(true);
      }
      uint currentTimestamp = block.timestamp;
      if (existingCredentialOptions.expired) {
        vm.warp(credentialTimestamp);
      }

      // If the credential should exist, add the provider and grant the role
      hooks.addRoleProvider(address(provider), 1);
      vm.prank(address(provider));
      hooks.grantRole(context.account, credentialTimestamp);

      if (existingCredentialOptions.expired) {
        vm.warp(currentTimestamp);
      }

      // If the provider should no longer be approved, remove it
      if (!existingCredentialOptions.providerApproved) {
        hooks.removeRoleProvider(address(provider));
      }

      // If the credential should be valid still, expect the account to have a valid credential
      // from the provider with no changes
      if (!existingCredentialOptions.expired && existingCredentialOptions.providerApproved) {
        context.expectations.hasValidCredential = true;
        context.expectations.wasUpdated = false;
        context.expectations.lastProvider = address(provider);
        context.expectations.lastApprovalTimestamp = credentialTimestamp;
      }
    }
  }

  // Runs after _setUpExistingCredential and _setUpHooksData
  function _setUpCredentialRefresh(HookValidationContext memory context) internal {
    MockRoleProvider provider = context.previousProvider;
    ExistingCredentialOptions memory existingCredentialOptions = context.existingCredentialOptions;

    // The contract will call the provider if all of the following are true:
    // - The account has an expired credential
    // - The provider is a pull provider
    // - The provider is approved
    // - The hooks data step will not return a valid credential
    bool contractWillBeCalled = existingCredentialOptions
      .credentialExists
      .and(existingCredentialOptions.expired)
      .and(existingCredentialOptions.isPullProvider)
      .and(existingCredentialOptions.providerApproved)
      .and(!context.expectations.hasValidCredential);

    if (contractWillBeCalled) {
      uint32 credentialTimestamp = existingCredentialOptions.newCredentialExpired
        ? uint32(block.timestamp - 2)
        : uint32(block.timestamp);

      // If `willReturnUint` is false, make the provider return 0 bytes
      if (!existingCredentialOptions.willReturnUint) {
        provider.setCallShouldReturnCorruptedData(true);
      }
      if (existingCredentialOptions.callWillRevert) {
        provider.setCallShouldRevert(true);
      }
      provider.setCredential(context.account, credentialTimestamp);

      ArrayHelpers.cloneAndPush.asPushExpectedCall()(
        context.expectations.expectedCalls,
        ExpectedCall(
          address(provider),
          abi.encodeWithSelector(IRoleProvider.getCredential.selector, context.account)
        )
      );

      // The call will return a valid credential if all of the following are true:
      // - The provider will return a valid uint
      // - The credential is not expired
      // - The call will not revert
      bool hooksWillYieldCredential = contractWillBeCalled
        .and(existingCredentialOptions.willReturnUint)
        .and(!existingCredentialOptions.newCredentialExpired)
        .and(!existingCredentialOptions.callWillRevert);

      if (hooksWillYieldCredential) {
        context.expectations.hasValidCredential = true;
        context.expectations.wasUpdated = true;
        context.expectations.lastProvider = address(provider);
        context.expectations.lastApprovalTimestamp = credentialTimestamp;
      }
    }
  }

  function _setUpHooksData(HookValidationContext memory context) internal {
    MockRoleProvider provider = context.providerToGiveData;
    HooksDataOptions memory dataOptions = context.dataOptions;
    address account = context.account;

    // The contract will call the provider if all of the following are true:
    // - The account does not already have a valid credential
    // - Hooks data is given
    // - The provider is approved
    // - The provider is a pull provider or `validateCredential` is being called
    bool contractWillBeCalled = (!context.expectations.hasValidCredential)
      .and(dataOptions.giveHooksData)
      .and(dataOptions.providerApproved)
      .and(dataOptions.isPullProvider || dataOptions.giveDataToValidate);

    if (dataOptions.giveHooksData) {
      uint32 credentialTimestamp = dataOptions.credentialExpired
        ? uint32(block.timestamp - 2)
        : uint32(block.timestamp);

      provider.setIsPullProvider(dataOptions.isPullProvider);
      // If provider should be approved, add it to the list of role providers
      if (dataOptions.providerApproved) {
        hooks.addRoleProvider(address(provider), 1);
      }

      // If `willReturnUint` is false, make the provider return 0 bytes
      provider.setCallShouldReturnCorruptedData(!dataOptions.willReturnUint);
      // If `callWillRevert` is true, make the provider revert
      provider.setCallShouldRevert(dataOptions.callWillRevert);

      if (dataOptions.giveDataToValidate) {
        bytes memory validateData = hex'aabbccddeeff';
        if (dataOptions.willReturnUint) {
          provider.approveCredentialData(keccak256(validateData), credentialTimestamp);
        }
        context.hooksData = abi.encodePacked(provider, validateData);
      } else {
        context.hooksData = abi.encodePacked(provider);
        if (dataOptions.willReturnUint) {
          provider.setCredential(context.account, credentialTimestamp);
        }
      }

      // The call will return a valid credential if all of the following are true:
      // - The provider will return a valid uint
      // - The credential is not expired
      // - The call will not revert
      bool hooksWillYieldCredential = contractWillBeCalled
        .and(dataOptions.willReturnUint)
        .and(!dataOptions.credentialExpired)
        .and(!dataOptions.callWillRevert);

      if (hooksWillYieldCredential) {
        context.expectations.hasValidCredential = true;
        context.expectations.wasUpdated = true;
        context.expectations.lastProvider = address(provider);
        context.expectations.lastApprovalTimestamp = credentialTimestamp;
      }
    }

    if (contractWillBeCalled) {
      bytes memory expectedCalldata = dataOptions.giveDataToValidate
        ? abi.encodeWithSelector(
          IRoleProvider.validateCredential.selector,
          context.account,
          hex'aabbccddeeff'
        )
        : abi.encodeWithSelector(IRoleProvider.getCredential.selector, context.account);

      ArrayHelpers.cloneAndPush.asPushExpectedCall()(
        context.expectations.expectedCalls,
        ExpectedCall(address(provider), expectedCalldata)
      );
      if (
        (!dataOptions.callWillRevert).and(!dataOptions.willReturnUint).and(
          dataOptions.giveDataToValidate
        )
      ) {
        context.expectations.expectedError = AccessControlHooks.InvalidCredentialReturned.selector;
      }
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

  function test_tryValidateAccess_credentialNotExists(address account) external {}

  function test_tryValidateAccess_credentialExists(address account) external {
    hooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    hooks.grantRole(account, uint32(block.timestamp));

    (bool hasValidCredential, bool wasUpdated) = hooks.tryValidateAccess(account, '');
    assertTrue(hasValidCredential, 'hasValidCredential');
    assertFalse(wasUpdated, 'wasUpdated');
  }
}

library AccessControlTestTypeCasts {
  function asPushExpectedCall(
    function(MemoryPointer, uint256) internal pure returns (MemoryPointer) _fn
  )
    internal
    pure
    returns (
      function(ExpectedCall[] memory, ExpectedCall memory)
        internal
        pure
        returns (ExpectedCall[] memory) fn
    )
  {
    assembly {
      fn := _fn
    }
  }
}
