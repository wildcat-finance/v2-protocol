// SPDX-License-Identifier; MIT
pragma solidity >=0.8.20;

import 'src/libraries/BoolUtils.sol';
import 'src/access/AccessControlHooks.sol';

import 'sol-utils/ir-only/MemoryPointer.sol';
import { ArrayHelpers } from 'sol-utils/ir-only/ArrayHelpers.sol';
import { Vm, VmSafe } from 'forge-std/Vm.sol';

import '../../shared/mocks/MockRoleProvider.sol';
import { warp } from '../../helpers/VmUtils.sol';

using BoolUtils for bool;

using LibAccessControlHooksFuzzContext for AccessControlHooksFuzzContext global;

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

struct AccessControlHooksFuzzContext {
  AccessControlHooks hooks;
  address borrower;
  address account;
  bytes hooksData;
  ExistingCredentialFuzzInputs existingCredentialOptions;
  AccessControlHooksDataFuzzInputs dataOptions;
  AccessControlValidationExpectations expectations;
  MockRoleProvider previousProvider;
  MockRoleProvider providerToGiveData;
}

struct AccessControlValidationExpectations {
  // Whether the account will end up with a valid credential
  bool hasValidCredential;
  // Whether the account's credential will be updated (added, refreshed or revoked)
  bool wasUpdated;
  // Expected calls to occur between the hooks instance and role providers
  ExpectedCall[] expectedCalls;
  // Error the hooks instance should throw
  bytes4 expectedError;
  // The `lastProvider` of the account after the call
  address lastProvider;
  // The `lastApprovalTimestamp` of the account after the call
  uint32 lastApprovalTimestamp;
}

struct AccessControlHooksFuzzInputs {
  ExistingCredentialFuzzInputs existingCredentialInputs;
  AccessControlHooksDataFuzzInputs dataInputs;
}

struct ExistingCredentialFuzzInputs {
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
struct AccessControlHooksDataFuzzInputs {
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

struct ExpectedCall {
  address target;
  bytes data;
}

address constant VM_ADDRESS = address(uint160(uint256(keccak256('hevm cheat code'))));
Vm constant vm = Vm(VM_ADDRESS);

function createAccessControlHooksFuzzContext(
  AccessControlHooksFuzzInputs memory fuzzInputs,
  AccessControlHooks hooks,
  MockRoleProvider mockProvider1,
  MockRoleProvider mockProvider2,
  address account
) returns (AccessControlHooksFuzzContext memory context) {
  context.hooks = hooks;
  context.borrower = hooks.borrower();
  context.account = account;
  context.existingCredentialOptions = fuzzInputs.existingCredentialInputs;
  context.dataOptions = fuzzInputs.dataInputs;
  context.previousProvider = mockProvider1;
  context.providerToGiveData = mockProvider2;
  vm.label(address(mockProvider1), 'previousProvider');
  vm.label(address(mockProvider2), 'providerToGiveData');

  context.setUpExistingCredential();
  context.setUpHooksData();
  context.setUpCredentialRefresh();

  // If a previous credential exists but the lender will not end up with a valid credential,
  // the last provider and approval timestamp should be reset
  if (
    fuzzInputs.existingCredentialInputs.credentialExists && !context.expectations.hasValidCredential
  ) {
    context.expectations.wasUpdated = true;
    context.expectations.lastProvider = address(0);
    context.expectations.lastApprovalTimestamp = 0;
  }
}

library LibAccessControlHooksFuzzContext {
  using AccessControlTestTypeCasts for *;

  /**
   * @dev Register event, error and call expectations with the forge vm
   */
  function registerExpectations(
    AccessControlHooksFuzzContext memory context,
    bool skipRevokedEvent
  ) internal {
    for (uint i; i < context.expectations.expectedCalls.length; i++) {
      vm.expectCall(
        context.expectations.expectedCalls[i].target,
        context.expectations.expectedCalls[i].data
      );
    }
    if (context.expectations.wasUpdated) {
      if (context.expectations.hasValidCredential) {
        vm.expectEmit(address(context.hooks));
        emit AccessControlHooks.AccountAccessGranted(
          context.expectations.lastProvider,
          context.account,
          context.expectations.lastApprovalTimestamp
        );
      } else if (!skipRevokedEvent) {
        vm.expectEmit(address(context.hooks));
        emit AccessControlHooks.AccountAccessRevoked(
          address(context.previousProvider),
          context.account
        );
      }
    }
    if (context.expectations.expectedError != 0) {
      vm.expectRevert(context.expectations.expectedError);
    }
  }

  /**
   * @dev Validate state after execution
   */
  function validate(AccessControlHooksFuzzContext memory context) internal view {
    LenderStatus memory status = context.hooks.getPreviousLenderStatus(context.account);
    vm.assertEq(status.lastProvider, context.expectations.lastProvider, 'lastProvider');
    vm.assertEq(
      status.lastApprovalTimestamp,
      context.expectations.lastApprovalTimestamp,
      'lastApprovalTimestamp'
    );
  }

  function setUpExistingCredential(AccessControlHooksFuzzContext memory context) internal {
    MockRoleProvider provider = context.previousProvider;
    ExistingCredentialFuzzInputs memory existingCredentialOptions = context
      .existingCredentialOptions;
    if (existingCredentialOptions.credentialExists) {
      uint32 originalTimestamp = uint32(block.timestamp);
      // If the credential should exist, add the provider and grant the role
      uint32 credentialTimestamp = existingCredentialOptions.expired
        ? originalTimestamp - 2
        : originalTimestamp;

      if (existingCredentialOptions.isPullProvider) {
        provider.setIsPullProvider(true);
      }
      if (existingCredentialOptions.expired) {
        warp(credentialTimestamp);
      }

      vm.prank(context.borrower);
      // If the credential should exist, add the provider and grant the role
      context.hooks.addRoleProvider(address(provider), 1);
      vm.prank(address(provider));
      context.hooks.grantRole(context.account, credentialTimestamp);

      if (existingCredentialOptions.expired) {
        warp(originalTimestamp);
      }

      // If the provider should no longer be approved, remove it
      if (!existingCredentialOptions.providerApproved) {
        vm.prank(context.borrower);
        context.hooks.removeRoleProvider(address(provider));
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

  function setUpHooksData(AccessControlHooksFuzzContext memory context) internal {
    MockRoleProvider provider = context.providerToGiveData;
    AccessControlHooksDataFuzzInputs memory dataOptions = context.dataOptions;

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
        vm.prank(context.borrower);
        context.hooks.addRoleProvider(address(provider), 1);
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

  // Runs after _setUpExistingCredential and _setUpHooksData
  function setUpCredentialRefresh(AccessControlHooksFuzzContext memory context) internal {
    if (context.expectations.expectedError != bytes4(0)) {
      return;
    }
    MockRoleProvider provider = context.previousProvider;
    ExistingCredentialFuzzInputs memory existingCredentialOptions = context
      .existingCredentialOptions;

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
