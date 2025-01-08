// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import '../types/RoleProvider.sol';

using RoleProviderDataLib for RoleProviderData global;

struct RoleProviderData {
  uint32 timeToLive;
  address providerAddress;
  uint24 pullProviderIndex;
  uint24 pushProviderIndex;
}

library RoleProviderDataLib {
  function fill(RoleProviderData memory data, RoleProvider provider) internal pure {
    (data.timeToLive, data.providerAddress, data.pullProviderIndex, data.pushProviderIndex) = provider.decodeRoleProvider();
  }

  function toRoleProviderDatas(
    RoleProvider[] memory providers
  ) internal pure returns (RoleProviderData[] memory data) {
    data = new RoleProviderData[](providers.length);
    for (uint256 i; i < providers.length; i++) {
      data[i].fill(providers[i]);
    }
  }
}
