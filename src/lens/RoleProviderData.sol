// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IManagedRoleProvider.sol';
import '../types/RoleProvider.sol';

using RoleProviderDataLib for RoleProviderData global;

struct RoleProviderData {
  uint32 timeToLive;
  address providerAddress;
  uint24 pullProviderIndex;
  uint24 pushProviderIndex;
  bool isManaged;
  address administrator;
  address pendingAdministrator;
}

library RoleProviderDataLib {
  function _tryReadAddress(
    address target,
    bytes4 selector
  ) private view returns (bool success, address value) {
    uint256 word;
    uint32 selectorWord = uint32(selector);
    assembly ('memory-safe') {
      mstore(0, shl(224, selectorWord))
      success := staticcall(30000, target, 0, 0x04, 0, 0x20)
      if iszero(eq(returndatasize(), 0x20)) {
        success := 0
      }
      word := mload(0)
    }
    if (!success || word > type(uint160).max) {
      return (false, address(0));
    }
    value = address(uint160(word));
  }

  function fill(RoleProviderData memory data, RoleProvider provider) internal view {
    (
      data.timeToLive,
      data.providerAddress,
      data.pullProviderIndex,
      data.pushProviderIndex
    ) = provider.decodeRoleProvider();

    (bool hasAdministrator, address administrator) = _tryReadAddress(
      data.providerAddress,
      IManagedRoleProvider.administrator.selector
    );
    if (hasAdministrator) {
      (bool hasPendingAdministrator, address pendingAdministrator) = _tryReadAddress(
        data.providerAddress,
        IManagedRoleProvider.pendingAdministrator.selector
      );
      if (hasPendingAdministrator) {
        data.isManaged = true;
        data.administrator = administrator;
        data.pendingAdministrator = pendingAdministrator;
      }
    }
  }

  function toRoleProviderDatas(
    RoleProvider[] memory providers
  ) internal view returns (RoleProviderData[] memory data) {
    data = new RoleProviderData[](providers.length);
    for (uint256 i; i < providers.length; i++) {
      data[i].fill(providers[i]);
    }
  }
}
