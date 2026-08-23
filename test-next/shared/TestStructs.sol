// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { RoleProvider, encodeRoleProvider } from 'src/types/RoleProvider.sol';
import { Bit_Enabled_ExecutePendingAnnualInterestBipsReduction } from 'src/types/HooksConfig.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { encodeHooksConfig } from 'src/types/HooksConfig.sol';
import { encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';

struct StandardRoleProvider {
  address providerAddress;
  uint32 timeToLive;
  uint24 pullProviderIndex;
  uint24 pushProviderIndex;
}

using { toRoleProvider } for StandardRoleProvider global;

function toRoleProvider(StandardRoleProvider memory input) pure returns (RoleProvider) {
  return
    encodeRoleProvider({
      providerAddress: input.providerAddress,
      timeToLive: input.timeToLive,
      pullProviderIndex: input.pullProviderIndex,
      pushProviderIndex: input.pushProviderIndex
    });
}

struct StandardHooksConfig {
  address hooksAddress;
  bool useOnDeposit;
  bool useOnQueueWithdrawal;
  bool useOnExecuteWithdrawal;
  bool useOnTransfer;
  bool useOnBorrow;
  bool useOnRepay;
  bool useOnCloseMarket;
  bool useOnNukeFromOrbit;
  bool useOnSetMaxTotalSupply;
  bool useOnSetAnnualInterestAndReserveRatioBips;
  bool useOnSetProtocolFeeBips;
  bool useOnExecutePendingAnnualInterestBipsReduction;
}

struct StandardHooksDeploymentConfig {
  StandardHooksConfig optional;
  StandardHooksConfig required;
}

using { mergeFlags, mergeSharedFlags, toHooksConfig } for StandardHooksConfig global;
using { toHooksDeploymentConfig } for StandardHooksDeploymentConfig global;

function toHooksConfig(StandardHooksConfig memory input) pure returns (HooksConfig hooks) {
  hooks = encodeHooksConfig({
    hooksAddress: input.hooksAddress,
    useOnDeposit: input.useOnDeposit,
    useOnQueueWithdrawal: input.useOnQueueWithdrawal,
    useOnExecuteWithdrawal: input.useOnExecuteWithdrawal,
    useOnTransfer: input.useOnTransfer,
    useOnBorrow: input.useOnBorrow,
    useOnRepay: input.useOnRepay,
    useOnCloseMarket: input.useOnCloseMarket,
    useOnNukeFromOrbit: input.useOnNukeFromOrbit,
    useOnSetMaxTotalSupply: input.useOnSetMaxTotalSupply,
    useOnSetAnnualInterestAndReserveRatioBips: input.useOnSetAnnualInterestAndReserveRatioBips,
    useOnSetProtocolFeeBips: input.useOnSetProtocolFeeBips
  });
  if (input.useOnExecutePendingAnnualInterestBipsReduction) {
    hooks = hooks.setFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction);
  }
}

function mergeSharedFlags(
  StandardHooksConfig memory a,
  StandardHooksConfig memory b
) pure returns (StandardHooksConfig memory merged) {
  merged = StandardHooksConfig({
    hooksAddress: a.hooksAddress,
    useOnDeposit: a.useOnDeposit && b.useOnDeposit,
    useOnQueueWithdrawal: a.useOnQueueWithdrawal && b.useOnQueueWithdrawal,
    useOnExecuteWithdrawal: a.useOnExecuteWithdrawal && b.useOnExecuteWithdrawal,
    useOnTransfer: a.useOnTransfer && b.useOnTransfer,
    useOnBorrow: a.useOnBorrow && b.useOnBorrow,
    useOnRepay: a.useOnRepay && b.useOnRepay,
    useOnCloseMarket: a.useOnCloseMarket && b.useOnCloseMarket,
    useOnNukeFromOrbit: a.useOnNukeFromOrbit && b.useOnNukeFromOrbit,
    useOnSetMaxTotalSupply: a.useOnSetMaxTotalSupply && b.useOnSetMaxTotalSupply,
    useOnSetAnnualInterestAndReserveRatioBips: a.useOnSetAnnualInterestAndReserveRatioBips &&
      b.useOnSetAnnualInterestAndReserveRatioBips,
    useOnSetProtocolFeeBips: a.useOnSetProtocolFeeBips && b.useOnSetProtocolFeeBips,
    useOnExecutePendingAnnualInterestBipsReduction: a
      .useOnExecutePendingAnnualInterestBipsReduction &&
      b.useOnExecutePendingAnnualInterestBipsReduction
  });
}

function toHooksDeploymentConfig(
  StandardHooksDeploymentConfig memory input
) pure returns (HooksDeploymentConfig) {
  return
    encodeHooksDeploymentConfig(input.optional.toHooksConfig(), input.required.toHooksConfig());
}

function mergeFlags(
  StandardHooksConfig memory config,
  StandardHooksDeploymentConfig memory flags
) pure returns (StandardHooksConfig memory merged) {
  merged = config.mergeSharedFlags(flags.optional);
  merged.useOnDeposit = merged.useOnDeposit || flags.required.useOnDeposit;
  merged.useOnQueueWithdrawal = merged.useOnQueueWithdrawal || flags.required.useOnQueueWithdrawal;
  merged.useOnExecuteWithdrawal =
    merged.useOnExecuteWithdrawal ||
    flags.required.useOnExecuteWithdrawal;
  merged.useOnTransfer = merged.useOnTransfer || flags.required.useOnTransfer;
  merged.useOnBorrow = merged.useOnBorrow || flags.required.useOnBorrow;
  merged.useOnRepay = merged.useOnRepay || flags.required.useOnRepay;
  merged.useOnCloseMarket = merged.useOnCloseMarket || flags.required.useOnCloseMarket;
  merged.useOnNukeFromOrbit = merged.useOnNukeFromOrbit || flags.required.useOnNukeFromOrbit;
  merged.useOnSetMaxTotalSupply =
    merged.useOnSetMaxTotalSupply ||
    flags.required.useOnSetMaxTotalSupply;
  merged.useOnSetAnnualInterestAndReserveRatioBips =
    merged.useOnSetAnnualInterestAndReserveRatioBips ||
    flags.required.useOnSetAnnualInterestAndReserveRatioBips;
  merged.useOnSetProtocolFeeBips =
    merged.useOnSetProtocolFeeBips ||
    flags.required.useOnSetProtocolFeeBips;
  merged.useOnExecutePendingAnnualInterestBipsReduction =
    merged.useOnExecutePendingAnnualInterestBipsReduction ||
    flags.required.useOnExecutePendingAnnualInterestBipsReduction;
}
