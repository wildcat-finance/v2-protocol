// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import '../interfaces/WildcatStructsAndEnums.sol';
import { OpenTermHooks, HookedMarket as OpenTermHookedMarket } from '../access/OpenTermHooks.sol';
import { FixedTermHooks, HookedMarket as FixedTermHookedMarket } from '../access/FixedTermHooks.sol';
import '../access/IHooks.sol';
import '../access/IHooksAdministrator.sol';
import '../IHooksFactory.sol';
import './HooksConfigData.sol';
import './HooksTemplateData.sol';
import './RoleProviderData.sol';

using HooksInstanceDataLib for HooksInstanceData global;

struct HooksInstanceData {
  address hooksAddress;
  address administrator;
  address pendingAdministrator;
  string name;
  HooksInstanceKind kind;
  HooksTemplateData hooksTemplate;
  MarketParameterConstraints constraints;
  HooksDeploymentFlags deploymentFlags;
  RoleProviderData[] pullProviders;
  RoleProviderData[] pushProviders;
  uint256 totalMarkets;
}

library HooksInstanceDataLib {
  using RoleProviderDataLib for *;

  bytes4 internal constant _BORROWER_SELECTOR = bytes4(keccak256('borrower()'));

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

  function fill(
    HooksInstanceData memory data,
    address hooksAddress,
    IHooksFactory factory,
    address administrator,
    HooksInstanceKind kind
  ) internal view {
    data.hooksAddress = hooksAddress;
    if (administrator != address(0)) {
      data.administrator = administrator;
    }

    IHooks hooks = IHooks(hooksAddress);
    data.kind = kind;

    if (data.administrator == address(0)) {
      (bool hasAdministrator, address currentAdministrator) = _tryReadAddress(
        hooksAddress,
        IHooksAdministrator.administrator.selector
      );
      if (!hasAdministrator) {
        (, currentAdministrator) = _tryReadAddress(hooksAddress, _BORROWER_SELECTOR);
      }
      data.administrator = currentAdministrator;
    }
    (, data.pendingAdministrator) = _tryReadAddress(
      hooksAddress,
      IHooksAdministrator.pendingAdministrator.selector
    );

    if (data.kind != HooksInstanceKind.Unknown) {
      OpenTermHooks hooks = OpenTermHooks(hooksAddress);
      data.pullProviders = hooks.getPullProviders().toRoleProviderDatas();
      data.pushProviders = hooks.getPushProviders().toRoleProviderDatas();
      data.constraints = hooks.getParameterConstraints();
      data.name = hooks.name();
    }

    address templateAddress = factory.getHooksTemplateForInstance(hooksAddress);
    data.hooksTemplate.fill(factory, templateAddress, data.administrator);
    data.deploymentFlags.fill(hooks.config());
    data.totalMarkets = factory.getMarketsForHooksInstanceCount(hooksAddress);
  }
}
