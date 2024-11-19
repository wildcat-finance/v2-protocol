// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import '../interfaces/WildcatStructsAndEnums.sol';
import { OpenTermHooks, HookedMarket as OpenTermHookedMarket } from '../access/OpenTermHooks.sol';
import { FixedTermHooks, HookedMarket as FixedTermHookedMarket } from '../access/FixedTermHooks.sol';
import '../access/IHooks.sol';
import '../HooksFactory.sol';
import './HooksConfigData.sol';
import './HooksTemplateData.sol';
import './RoleProviderData.sol';

using HooksInstanceDataLib for HooksInstanceData global;

struct HooksInstanceData {
  address hooksAddress;
  address borrower;
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

  function fill(
    HooksInstanceData memory data,
    address hooksAddress,
    HooksFactory factory
  ) internal view {
    data.hooksAddress = hooksAddress;

    address templateAddress = factory.getHooksTemplateForInstance(hooksAddress);
    data.hooksTemplate.fill(factory, templateAddress, data.borrower);

    IHooks hooks = IHooks(hooksAddress);

    bytes32 versionHash = keccak256(bytes(data.hooksTemplate.name));
    if (versionHash == keccak256('OpenTermHooks')) {
      data.kind = HooksInstanceKind.OpenTerm;
    } else if (versionHash == keccak256('FixedTermHooks')) {
      data.kind = HooksInstanceKind.FixedTermLoan;
    }

    if (data.kind != HooksInstanceKind.Unknown) {
      OpenTermHooks hooks = OpenTermHooks(hooksAddress);
      if (data.borrower == address(0)) {
        data.borrower = hooks.borrower();
      }
      data.pullProviders = hooks.getPullProviders().toRoleProviderDatas();
      data.pushProviders = hooks.getPushProviders().toRoleProviderDatas();
      data.constraints = hooks.getParameterConstraints();
      data.name = hooks.name();
    }
    data.deploymentFlags.fill(hooks.config());
    data.totalMarkets = factory.getMarketsForHooksInstanceCount(hooksAddress);
  }
}
