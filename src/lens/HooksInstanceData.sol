// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import '../interfaces/WildcatStructsAndEnums.sol';
import { AccessControlHooks, HookedMarket as AccessControlHookedMarket } from '../access/AccessControlHooks.sol';
import { FixedTermLoanHooks, HookedMarket as FixedTermHookedMarket } from '../access/FixedTermLoanHooks.sol';
import '../access/IHooks.sol';
import '../HooksFactory.sol';
import './HooksConfigData.sol';
import './HooksTemplateData.sol';
import './RoleProviderData.sol';

using HooksInstanceDataLib for HooksInstanceData global;

struct HooksInstanceData {
  address hooksAddress;
  address borrower;
  HooksInstanceKind kind;
  address hooksTemplate;
  string hooksTemplateName;
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

    data.hooksTemplate = factory.getHooksTemplateForInstance(hooksAddress);
    data.hooksTemplateName = factory.getHooksTemplateDetails(data.hooksTemplate).name;

    IHooks hooks = IHooks(hooksAddress);

    bytes32 versionHash = keccak256(bytes(data.hooksTemplateName));
    if (versionHash == keccak256('SingleBorrowerAccessControlHooks')) {
      data.kind = HooksInstanceKind.AccessControl;
    } else if (versionHash == keccak256('FixedTermLoanHooks')) {
      data.kind = HooksInstanceKind.FixedTermLoan;
    }

    if (data.kind != HooksInstanceKind.Unknown) {
      AccessControlHooks accessControlHooks = AccessControlHooks(hooksAddress);
      if (data.borrower == address(0)) {
        data.borrower = accessControlHooks.borrower();
      }
      data.pullProviders = accessControlHooks.getPullProviders().toRoleProviderDatas();
      data.pushProviders = accessControlHooks.getPushProviders().toRoleProviderDatas();
      data.constraints = accessControlHooks.getParameterConstraints();
    }
    data.deploymentFlags.fill(hooks.config());
    data.totalMarkets = factory.getMarketsForHooksInstanceCount(hooksAddress);
  }
}
