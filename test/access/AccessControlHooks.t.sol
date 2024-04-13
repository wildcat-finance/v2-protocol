// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/access/AccessControlHooks.sol';
import { LibString } from 'solady/utils/LibString.sol';
import '../shared/mocks/MockRoleProvider.sol';
import '../helpers/Assertions.sol';

using LibString for uint256;

contract AccessControlHooksTest is Test, Assertions {
  uint24 internal numPullProviders;
  StandardRoleProvider[] internal expectedRoleProviders;
  AccessControlHooks internal hooks;
  MockRoleProvider internal mockProvider1;
  MockRoleProvider internal mockProvider2;

  function _addExpectedProvider(
    MockRoleProvider mockProvider,
    uint32 timeToLive,
    bool isPullProvider
  ) internal returns (StandardRoleProvider storage) {
    mockProvider.setIsPullProvider(isPullProvider);
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

  function setUp() external {
    hooks = new AccessControlHooks();
    mockProvider1 = new MockRoleProvider();
    mockProvider2 = new MockRoleProvider();
  }

  function test_config() external {
    StandardHooksConfig memory expectedConfig = StandardHooksConfig({
      hooksAddress: address(hooks),
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
    assertEq(hooks.config(), expectedConfig, 'config.');
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
      // Check _roleProviders[provider] matches expected provider
      RoleProvider provider = hooks.getRoleProvider(expectedRoleProviders[i].providerAddress);
      assertEq(provider, expectedRoleProviders[i], 'getRoleProvider');
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
    hooks.addRoleProvider(address(this), timeToLive);
    _validateRoleProviders();
  }

  function test_addRoleProvider_updateTimeToLive(
    bool isPullProvider,
    uint32 ttl1,
    uint32 ttl2
  ) external {
    StandardRoleProvider storage provider = _addExpectedProvider(mockProvider1, ttl1, isPullProvider);
    _expectRoleProviderAdded(address(mockProvider1), ttl1, provider.pullProviderIndex);
    hooks.addRoleProvider(address(mockProvider1), ttl1);

    _validateRoleProviders();

    expectedRoleProviders[0].timeToLive = ttl2;
    _expectRoleProviderUpdated(address(mockProvider1), ttl2, provider.pullProviderIndex);
    hooks.addRoleProvider(address(mockProvider1), ttl2);

    _validateRoleProviders();
  }

  function test_removeRoleProvider(bool isPullProvider, uint32 timeToLive) external {
    StandardRoleProvider storage provider = _addExpectedProvider(mockProvider1, timeToLive, isPullProvider);

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

    _expectRoleProviderAdded(address(mockProvider1), 1, 0);
    hooks.addRoleProvider(address(mockProvider1), 1);

    _expectRoleProviderAdded(address(mockProvider2), 1, 1);
    hooks.addRoleProvider(address(mockProvider2), 1);

    _expectRoleProviderRemoved(address(mockProvider1), 0);
    _expectRoleProviderUpdated(address(mockProvider2), 1, 0);

    hooks.removeRoleProvider(address(mockProvider1));
    _validateRoleProviders();
  }
}
