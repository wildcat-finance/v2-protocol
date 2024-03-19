//  SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// struct RoleProvider {
//   uint32 roleTimeToLive;
//   address providerAddress;
//   bool isPullProvider;
//   bool isPushProvider;
//   uint24 pullProviderIndex;
//   uint24 pushProviderIndex;
// }
type RoleProvider is bytes25;

using RoleProviderLib for RoleProvider global;

function toRoleProvider(bytes32 packedProvider) pure returns (RoleProvider provider) {
  assembly {
    provider := packedProvider
  }
}

library RoleProviderLib {
  function roleTimeToLive(RoleProvider provider) internal pure returns (uint32 _roleTimeToLive) {
    assembly {
      _roleTimeToLive := shr(224, provider)
    }
  }

  function providerAddress(RoleProvider provider) internal pure returns (address _providerAddress) {
    assembly {
      _providerAddress := shr(96, shl(32, provider))
    }
  }

  function isPullProvider(RoleProvider provider) internal pure returns (bool _isPullProvider) {
    assembly {
      _isPullProvider := byte(4, provider)
    }
  }

  function isPushProvider(RoleProvider provider) internal pure returns (bool _isPushProvider) {
    assembly {
      //   _isPushProvider := iszero(byte(4, provider)) todo
    }
  }

  function isNull(RoleProvider provider) internal pure returns (bool _null) {
    assembly {
      _null := iszero(provider)
    }
  }

  function setPullProviderIndex(
    RoleProvider provider,
    uint24 index
  ) internal pure returns (RoleProvider _provider) {
    assembly {
      let mask := 0xffffffffffffffffffffffffffffffffffffffffffffffffffff
      _provider := or(and(provider, mask), shl(32, index))
    }
  }

  function setPushProviderIndex(
    RoleProvider provider,
    uint24 index
  ) internal pure returns (RoleProvider _provider) {
    assembly {
      let mask := 0xffffffffffffffffffffffffffffffffffffffffff
      _provider := or(and(provider, mask), index)
    }
  }

  function pack(
    uint32 _roleTimeToLive,
    address _providerAddress,
    bool _isPullProvider,
    bool _isPushProvider,
    uint24 _pullProviderIndex,
    uint24 _pushProviderIndex
  ) internal pure returns (RoleProvider provider) {
    assembly {
      provider := or(
        or(_pushProviderIndex, shl(24, _pullProviderIndex)),
        or(
          or(shl(48, _isPushProvider), shl(56, _isPullProvider)),
          or(shl(64, _providerAddress), shl(224, _roleTimeToLive))
        )
      )
    }
  }
}

type RoleProviderCache is uint256;

using LibRoleProviderCache for RoleProviderCache global;

struct MarketState {
  uint a;
}

library LibRoleProviderCache {
  function cache(MarketState storage stored) internal view returns (RoleProviderCache _cache) {
    assembly {
      _cache := mload(0x40)
      mstore(0x40, add(_cache, 0x20))
      mstore(_cache, sload(stored.slot))
      mstore(add(_cache, 0x20), sload(add(stored.slot, 0x01)))
    }
  }

  function getRoleTimeToLive(
    RoleProviderCache _cache
  ) internal pure returns (uint32 roleTimeToLive) {
    assembly {
      roleTimeToLive := shr(0xe0, mload(_cache))
    }
  }

  function setRoleTimeToLive(RoleProviderCache _cache, uint32 roleTimeToLive) internal pure {
    assembly {
      let startPointer := _cache
      mstore(startPointer, or(shr(0x20, shl(0x20, mload(startPointer))), shl(0xe0, roleTimeToLive)))
    }
  }

  function getProviderAddress(
    RoleProviderCache _cache
  ) internal pure returns (address providerAddress) {
    assembly {
      providerAddress := shr(0x60, shl(0x20, mload(_cache)))
    }
  }

  function setProviderAddress(RoleProviderCache _cache, address providerAddress) internal pure {
    assembly {
      let startPointer := add(_cache, 0x04)
      mstore(
        startPointer,
        or(shr(0xa0, shl(0xa0, mload(startPointer))), shl(0x60, providerAddress))
      )
    }
  }

  function getIsPullProvider(RoleProviderCache _cache) internal pure returns (bool isPullProvider) {
    assembly {
      isPullProvider := byte(24, mload(_cache))
    }
  }

  function setIsPullProvider(RoleProviderCache _cache, bool isPullProvider) internal pure {
    assembly {
      mstore8(add(_cache, 0x18), isPullProvider)
    }
  }

  function getIsPushProvider(RoleProviderCache _cache) internal pure returns (bool isPushProvider) {
    assembly {
      isPushProvider := byte(25, mload(_cache))
    }
  }

  function setIsPushProvider(RoleProviderCache _cache, bool isPushProvider) internal pure {
    assembly {
      mstore8(add(_cache, 0x19), isPushProvider)
    }
  }

  function getPullProviderIndex(
    RoleProviderCache _cache
  ) internal pure returns (uint24 pullProviderIndex) {
    assembly {
      pullProviderIndex := shr(0xe8, shl(0xd0, mload(_cache)))
    }
  }

  function setPullProviderIndex(RoleProviderCache _cache, uint24 pullProviderIndex) internal pure {
    assembly {
      let startPointer := add(_cache, 0x1a)
      mstore(
        startPointer,
        or(shr(0x18, shl(0x18, mload(startPointer))), shl(0xe8, pullProviderIndex))
      )
    }
  }

  function getPushProviderIndex(
    RoleProviderCache _cache
  ) internal pure returns (uint24 pushProviderIndex) {
    assembly {
      pushProviderIndex := shr(0xe8, mload(add(_cache, 0x20)))
    }
  }

  function setPushProviderIndex(RoleProviderCache _cache, uint24 pushProviderIndex) internal pure {
    assembly {
      let rightAlignedPointer := add(_cache, 0x03)
      mstore(
        rightAlignedPointer,
        or(shl(0x18, shr(0x18, mload(rightAlignedPointer))), pushProviderIndex)
      )
    }
  }

  function update(MarketState storage stored, RoleProviderCache _cache) internal {
    assembly {
      sstore(stored.slot, mload(_cache))
      sstore(add(stored.slot, 0x01), mload(add(_cache, 0x20)))
    }
  }
}
