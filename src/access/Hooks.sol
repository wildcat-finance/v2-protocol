// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import '../libraries/BoolUtils.sol';
import '../libraries/MathUtils.sol';
import '../types/RoleProvider.sol';
import '../types/LenderStatus.sol';
import './IRoleProvider.sol';
import './IHooks.sol';

using BoolUtils for bool;
using MathUtils for uint256;

function removeFromArray(
  RoleProvider[] storage arr,
  mapping(address => RoleProvider) storage map,
  uint24 indexToRemove
) {
  // Get the last index in the array
  uint256 lastIndex = arr.length - 1;
  // If the index to remove is the last index, just pop the last element
  if (indexToRemove == lastIndex) {
    arr.pop();
    return;
  }
  RoleProvider lastProvider = arr[lastIndex];
  lastProvider = lastProvider.setPullProviderIndex(indexToRemove);
  arr[indexToRemove] = lastProvider;
  arr.pop();
  map[lastProvider.providerAddress()] = lastProvider;
}

// @todo custom error types
// @todo events

/**
 * @title AccessControlHooks
 * @dev Hooks contract for wildcat markets. Restricts access to deposits
 *      to accounts that have credentials from approved role providers, or
 *      which are manually approved by the borrower.
 *
 *      Withdrawals are restricted in the same way for users that have not
 *      made a deposit, while users who have made a deposit at any point
 *      remain approved even if they are later removed.
 *
 *      Deposit access may be canceled by the borrower.
 */
contract AccessControlHooks is IHooks {
  function version() external pure override returns (string memory) {
    return 'AccessControlHooks';
  }

  function config() external view override returns (HooksConfig) {
    return
      encodeHooksConfig({
        hooksAddress: address(this),
        useOnDeposit: true,
        useOnQueueWithdrawal: true,
        useOnExecuteWithdrawal: false,
        useOnTransfer: false,
        useOnBorrow: false,
        useOnRepay: false,
        useOnCloseMarket: false,
        useOnAssetsSentToEscrow: false,
        useOnSetMaxTotalSupply: false,
        useOnSetAnnualInterestBips: false
      });
  }

  mapping(address => LenderStatus) internal _lenderStatus;
  // Provider data is duplicated in the array and mapping to allow
  // push providers to update in a single step and pull providers to
  // be looped over without having to access the mapping.
  RoleProvider[] internal _pullProviders;
  mapping(address => RoleProvider) internal _roleProviders;

  /**
   * @dev Adds or updates a role provider that is able to grant user access.
   *      If it is not already approved, it is added to `_roleProviders` and,
   *      if the provider can refresh credentials, added to `pullProviders`.
   *      If the provider is already approved, only updates `timeToLive`.
   */
  function addProvider(address providerAddress, uint32 timeToLive) external {
    RoleProvider provider = _roleProviders[providerAddress];
    if (provider.isNull()) {
      bool isPullProvider = IRoleProvider(providerAddress).isPullProvider();
      // Role providers that are not pull providers have `pullProviderIndex` set to
      // `NotPullProviderIndex` (max uint24) to indicate they do not refresh credentials.
      provider = encodeRoleProvider(
        timeToLive,
        providerAddress,
        isPullProvider ? uint24(_pullProviders.length) : NotPullProviderIndex
      );
      if (isPullProvider) {
        _pullProviders.push(provider);
      }
    } else {
      // If provider already exists, the only value that can be updated is the TTL
      provider = provider.setTimeToLive(timeToLive);
    }
    // Update the provider in storage
    _roleProviders[providerAddress] = provider;
  }

  function removeProvider(address providerAddress) external {
    RoleProvider provider = _roleProviders[providerAddress];
    // @todo custom error
    require(!provider.isNull(), 'Provider null');
    if (provider.isPullProvider()) {
      removeFromArray(_pullProviders, _roleProviders, provider.pullProviderIndex());
    }
    _roleProviders[providerAddress] = EmptyRoleProvider;
  }

  function grantRole(address account) external {
    RoleProvider callingProvider = _roleProviders[msg.sender];
    require(!callingProvider.isNull(), 'Controller: Not a push provider');
    LenderStatus memory status = _lenderStatus[account];
    if (status.lastApprovalTimestamp > 0) {
      RoleProvider lastProvider = _roleProviders[status.lastProvider];
      if (!lastProvider.isNull()) {
        // Can only update role if it is expired or caller is previous role provider
        bool isPreviousRoleExpired = status.hasExpiredCredential(lastProvider);
        bool isPreviousRoleProvider = status.lastProvider == msg.sender;
        require(
          isPreviousRoleExpired.or(isPreviousRoleProvider),
          'Role is not expired and sender is not previous role provider'
        );
      }
    }
    status.setCredential(callingProvider, block.timestamp);
    _lenderStatus[account] = status;
  }

  /**
   * @dev Tries to pull an active credential for an account from a
   *      pull provider. If one exists, updates the account in memory
   *      and returns true.
   *
   *      Note: Does not check that provider is a pull provider - should
   *      only be called if that has already been checked.
   */
  function _tryPullCredential(
    LenderStatus memory status,
    RoleProvider provider,
    address accountAddress
  ) internal view returns (bool isApproved) {
    // Query provider for user approval
    IRoleProvider roleProvider = IRoleProvider(provider.providerAddress());

    // todo - query in assembly, return false if call fails
    uint256 lastApprovalTime = roleProvider.getCredential(accountAddress);

    if (lastApprovalTime > 0) {
      // Calculate new role expiry as either max uint32 or the last approval time
      // plus the provider's TTL, whichever is lower.
      uint256 newExpiry = provider.calculateExpiry(lastApprovalTime);

      // If credential is still valid, update credential
      if (newExpiry >= block.timestamp) {
        // User is approved, update status with new expiry and last provider
        status.setCredential(provider, lastApprovalTime);
        return true;
      }
    }
    return false;
  }

  // @todo update ethereum-access-token to allow the provider to specify the
  //       cdptr to the signature

  function _readProviderAddressFromCalldataSuffix(
    uint256 baseCalldataSize
  ) internal pure returns (address providerAddress) {
    assembly {
      providerAddress := shr(96, calldataload(baseCalldataSize))
    }
  }

  /**
   * @dev Uses the data added to the end of the base call to the hook function to call
   *      `validateCredential` on the selected provider. Returns false if the provider does not
   *      exist, the call fails, or the credential is invalid. Only reverts if the call succeeds but
   *      does not return the correct amount of data.
   *
   *      The calldata to the hook function must have a suffix encoded as (address, raw bytes), where
   *      the address is packed and the raw bytes do not contain an offset or length. For example, if
   *      the hook function were `onAction(address caller)` and the user provided a credential with a
   *      32 byte token, the calldata sent to the hook contract would be:
   *      [0:4] 0xde923be9
   *      [4:36] caller address
   *      [36:58] provider address
   *      [58:90] token to send to the provider
   */
  function _tryValidateCredential(
    LenderStatus memory status,
    address accountAddress,
    uint256 baseCalldataSize
  ) internal returns (bool) {
    uint validateSelector = uint32(IRoleProvider.validateCredential.selector);
    address providerAddress = _readProviderAddressFromCalldataSuffix(baseCalldataSize);
    RoleProvider provider = _roleProviders[providerAddress];
    if (provider.isNull()) return false;
    uint32 credentialTimestamp;
    assembly {
      // Get the offset to the extra data provided in the hooks call, after the provider.
      let validateDataCalldataPointer := add(baseCalldataSize, 0x14)
      // Encode the call to `validateCredential(address account, bytes calldata data)`
      let calldataPointer := mload(0x40)
      // The selector is right aligned, so the real calldata buffer begins at calldataPointer + 28
      mstore(calldataPointer, validateSelector)
      mstore(add(calldataPointer, 0x20), accountAddress)
      // Write the calldata offset to `data`
      mstore(add(calldataPointer, 0x40), 0x40)
      let dataLength := sub(calldatasize(), validateDataCalldataPointer)
      // Write the length of the calldata to `data`
      mstore(add(calldataPointer, 0x60), dataLength)
      // Copy the calldata to the buffer
      calldatacopy(add(calldataPointer, 0x80), validateDataCalldataPointer, dataLength)
      // Call the provider
      if call(gas(), providerAddress, 0, calldataPointer, add(dataLength, 0x84), 0, 0x20) {
        switch lt(returndatasize(), 0x20)
        case 1 {
          // If the returndata is invalid but the call succeeded, the call must throw
          returndatacopy(0, 0, returndatasize()) // @todo custom error
          revert(0, returndatasize())
        }
        default {
          // If sufficient data was returned, set `credentialTimestamp` to the returned word
          credentialTimestamp := mload(0)
        }
      }
    }
    // If the returned timestamp is null or greater than the current time, return false.
    if (credentialTimestamp == 0 || credentialTimestamp > block.timestamp) {
      return false;
    }
    // Check if the returned timestamp results in a valid expiry
    if (provider.calculateExpiry(credentialTimestamp) >= block.timestamp) {
      status.setCredential(provider, credentialTimestamp);
    }
  }

  /**
   * @dev Retrieves the current status of a lender, attempting to find a valid
   *      credential if their current one is invalid or non-existent.
   *
   *      If the lender has an expired credential, will attempt to refresh it
   *      with the previous provider if it is still supported.
   *
   *      If the lender has no credential, or one from a provider that is no longer
   *      supported or will not refresh it, will loop over all providers to find
   *      a valid credential.
   */
  function getLenderStatus(
    address accountAddress
  ) external view returns (LenderStatus memory status) {
    status = _lenderStatus[accountAddress];

    uint256 providerIndexToSkip;

    // Check if user has an existing credential
    if (status.lastApprovalTimestamp > 0) {
      RoleProvider provider = _roleProviders[status.lastProvider];
      if (!provider.isNull()) {
        // If credential is not expired and the provider is still
        // supported, the lender has a valid credential.
        if (status.hasActiveCredential(provider)) return status;

        // If credential is expired but the provider is still supported and
        // allows refreshing (i.e. it's a pull provider), try to refresh.
        if (status.canRefresh) {
          if (_tryPullCredential(status, provider, accountAddress)) {
            return status;
          }
          // If refresh fails, provider should be skipped in the query loop
          providerIndexToSkip = provider.pullProviderIndex();
        }
      }
      // If credential could not be refreshed or the provider is no longer
      // supported, remove it
      status.unsetCredential();
    }

    uint256 providerCount = _pullProviders.length;
    // Loop over all pull providers to find a valid role for the lender
    for (uint256 i = 0; i < providerCount; i++) {
      if (i == providerIndexToSkip) continue;
      RoleProvider provider = _pullProviders[i];
      if (_tryPullCredential(status, provider, accountAddress)) {
        return status;
      }
    }
  }

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external override {}

  function onQueueWithdrawal(
    address lender,
    uint32 withdrawalBatchExpiry,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external override {}

  function onExecuteWithdrawal(
    address lender,
    uint32 withdrawalBatchExpiry,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external override {}

  function onTransfer(
    address from,
    address to,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external override {}

  function onBorrow(uint normalizedAmount, bytes calldata extraData) external override {}

  function onRepay(uint normalizedAmount, bytes calldata extraData) external override {}

  function onCloseMarket(bytes calldata extraData) external override {}

  function onAssetsSentToEscrow(
    address lender,
    address escrow,
    uint scaledAmount,
    bytes calldata extraData
  ) external override {}

  function onSetMaxTotalSupply(bytes calldata extraData) external override {}

  function onSetAnnualInterestBips(bytes calldata extraData) external override {}
}
