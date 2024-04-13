// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/types/HooksConfig.sol';
import 'src/types/RoleProvider.sol';

struct StandardRoleProvider {
  address providerAddress;
  uint32 timeToLive;
  uint24 pullProviderIndex;
}

using { toRoleProvider } for StandardRoleProvider global;

function toRoleProvider(StandardRoleProvider memory input) pure returns (RoleProvider) {
  return
    encodeRoleProvider({
      providerAddress: input.providerAddress,
      timeToLive: input.timeToLive,
      pullProviderIndex: input.pullProviderIndex
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
  bool useOnAssetsSentToEscrow;
  bool useOnSetMaxTotalSupply;
  bool useOnSetAnnualInterestBips;
}
using { toHooksConfig } for StandardHooksConfig global;

function toHooksConfig(StandardHooksConfig memory input) pure returns (HooksConfig) {
  return
    encodeHooksConfig({
      hooksAddress: input.hooksAddress,
      useOnDeposit: input.useOnDeposit,
      useOnQueueWithdrawal: input.useOnQueueWithdrawal,
      useOnExecuteWithdrawal: input.useOnExecuteWithdrawal,
      useOnTransfer: input.useOnTransfer,
      useOnBorrow: input.useOnBorrow,
      useOnRepay: input.useOnRepay,
      useOnCloseMarket: input.useOnCloseMarket,
      useOnAssetsSentToEscrow: input.useOnAssetsSentToEscrow,
      useOnSetMaxTotalSupply: input.useOnSetMaxTotalSupply,
      useOnSetAnnualInterestBips: input.useOnSetAnnualInterestBips
    });
}
