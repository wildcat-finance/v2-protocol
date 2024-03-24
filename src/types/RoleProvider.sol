// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

type RoleProvider is uint256;
uint24 constant EmptyIndex = type(uint24).max;

using LibRoleProvider for RoleProvider global;

/// @dev Encode `timeToLive, providerAddress, pullProviderIndex`
///      members into a RoleProvider
function encodeRoleProvider(
  uint32 timeToLive,
  address providerAddress,
  uint24 pullProviderIndex
) pure returns (RoleProvider roleProvider) {
  assembly {
    roleProvider := or(
      or(shl(0xe0, timeToLive), shl(0x40, providerAddress)),
      shl(0x28, pullProviderIndex)
    )
  }
}

// @todo align largest type to the left to minimize mask

library LibRoleProvider {
  /// @dev Extract `timeToLive, providerAddress, pullProviderIndex`
  ///      members from a RoleProvider
  function decodeRoleProvider(
    RoleProvider roleProvider
  )
    internal
    pure
    returns (uint32 _timeToLive, address _providerAddress, uint24 _pullProviderIndex)
  {
    assembly {
      _timeToLive := shr(0xe0, roleProvider)
      _providerAddress := shr(0x60, shl(0x20, roleProvider))
      _pullProviderIndex := shr(0xe8, shl(0xc0, roleProvider))
    }
  }

  /// @dev Extract `timeToLive` from `roleProvider`
  function timeToLive(RoleProvider roleProvider) internal pure returns (uint32 _timeToLive) {
    assembly {
      _timeToLive := shr(0xe0, roleProvider)
    }
  }

  /// @dev Returns new RoleProvider with `timeToLive` set to `_timeToLive`
  /// Note: This function does not modify the original RoleProvider
  function setTimeToLive(
    RoleProvider roleProvider,
    uint32 _timeToLive
  ) internal pure returns (RoleProvider newRoleProvider) {
    assembly {
      newRoleProvider := or(shr(0x20, shl(0x20, roleProvider)), shl(0xe0, _timeToLive))
    }
  }

  /// @dev Extract `providerAddress` from `roleProvider`
  function providerAddress(
    RoleProvider roleProvider
  ) internal pure returns (address _providerAddress) {
    assembly {
      _providerAddress := shr(0x60, shl(0x20, roleProvider))
    }
  }

  /// @dev Returns new RoleProvider with `providerAddress` set to `_providerAddress`
  /// Note: This function does not modify the original RoleProvider
  function setProviderAddress(
    RoleProvider roleProvider,
    address _providerAddress
  ) internal pure returns (RoleProvider newRoleProvider) {
    assembly {
      newRoleProvider := or(
        and(roleProvider, 0xffffffff0000000000000000000000000000000000000000ffffffffffffffff),
        shl(0x40, _providerAddress)
      )
    }
  }

  /// @dev Extract `pullProviderIndex` from `roleProvider`
  function pullProviderIndex(
    RoleProvider roleProvider
  ) internal pure returns (uint24 _pullProviderIndex) {
    assembly {
      _pullProviderIndex := shr(0xe8, shl(0xc0, roleProvider))
    }
  }

  /// @dev Returns new RoleProvider with `pullProviderIndex` set to `_pullProviderIndex`
  /// Note: This function does not modify the original RoleProvider
  function setPullProviderIndex(
    RoleProvider roleProvider,
    uint24 _pullProviderIndex
  ) internal pure returns (RoleProvider newRoleProvider) {
    assembly {
      newRoleProvider := or(
        and(roleProvider, 0xffffffffffffffffffffffffffffffffffffffffffffffff000000ffffffffff),
        shl(0x28, _pullProviderIndex)
      )
    }
  }

  /// @dev Checks if two RoleProviders are equal
  function eq(
    RoleProvider roleProvider,
    RoleProvider otherRoleProvider
  ) internal pure returns (bool _eq) {
    assembly {
      _eq := eq(roleProvider, otherRoleProvider)
    }
  }

  /// @dev Checks if `roleProvider` is null
  function isNull(RoleProvider roleProvider) internal pure returns (bool _null) {
    assembly {
      _null := iszero(roleProvider)
    }
  }

  /// @dev Checks if `roleProvider` is a pull provider by checking if `pullProviderIndex`
  ///      is not equal to the max uint24.
  function isPullProvider(RoleProvider roleProvider) internal pure returns (bool _isPull) {
    return roleProvider.pullProviderIndex() != EmptyIndex;
  }

  /// @dev Set `pullProviderIndex` in `roleProvider` to the max uint24,
  ///      to mark it as not a pull provider.
  function setNotPullProvider(
    RoleProvider roleProvider
  ) internal pure returns (RoleProvider newRoleProvider) {
    assembly {
      newRoleProvider := or(roleProvider, 0xffffff0000000000)
    }
  }
}
