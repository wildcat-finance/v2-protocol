// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '../types/HooksConfig.sol';
import '../access/IHooks.sol';
import { HookedMarket as OpenTermHookedMarket, OpenTermHooks } from '../access/OpenTermHooks.sol';
import { HookedMarket as FixedTermHookedMarket, FixedTermHooks } from '../access/FixedTermHooks.sol';
import { HookedMarket as PeriodicTermHookedMarket, PeriodicTermHooks } from '../access/PeriodicTermHooks.sol';
import { WildcatMarket } from '../market/WildcatMarket.sol';

enum HooksInstanceKind {
  Unknown,
  OpenTerm,
  FixedTermLoan,
  PeriodicTerm
}

using HooksConfigDataLib for HooksConfigData global;
using HooksConfigDataLib for HooksDeploymentFlags global;
using HooksConfigDataLib for MarketHooksData global;

struct HooksConfigData {
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

struct HooksDeploymentFlags {
  HooksConfigData optional;
  HooksConfigData required;
}

struct MarketHooksData {
  address hooksAddress;
  HooksConfigData flags;
  HooksInstanceKind kind;
  // Shared flags
  bool transferRequiresAccess;
  bool depositRequiresAccess;
  uint128 minimumDeposit;
  bool transfersDisabled;
  // Fixed term loan flags
  bool withdrawalRequiresAccess;
  uint32 fixedTermEndTime;
  bool allowClosureBeforeTerm;
  bool allowTermReduction;
  // Periodic term flags
  uint32 firstWithdrawalWindowStart;
  uint32 periodDuration;
  uint32 withdrawalWindowDuration;
  bool periodicTermClosed;
}

library HooksConfigDataLib {
  using HooksConfigDataLib for *;

  function kindForVersion(string memory version) internal pure returns (HooksInstanceKind) {
    bytes32 versionHash = keccak256(bytes(version));
    if (versionHash == keccak256(bytes('OpenTermHooks'))) {
      return HooksInstanceKind.OpenTerm;
    } else if (versionHash == keccak256(bytes('FixedTermHooks'))) {
      return HooksInstanceKind.FixedTermLoan;
    } else if (versionHash == keccak256(bytes('PeriodicTermHooks'))) {
      return HooksInstanceKind.PeriodicTerm;
    }
    return HooksInstanceKind.Unknown;
  }

  function fill(MarketHooksData memory data, address marketAddress) internal view {
    WildcatMarket market = WildcatMarket(marketAddress);
    HooksConfig encodedHooksConfig = market.hooks();
    data.hooksAddress = encodedHooksConfig.hooksAddress();
    data.flags.fill(encodedHooksConfig);
    data.kind = kindForVersion(IHooks(encodedHooksConfig.hooksAddress()).version());
    if (data.kind == HooksInstanceKind.OpenTerm) {
      OpenTermHooks hooks = OpenTermHooks(data.hooksAddress);
      OpenTermHookedMarket memory hookedMarket = hooks.getHookedMarket(marketAddress);
      data.transferRequiresAccess = hookedMarket.transferRequiresAccess;
      data.depositRequiresAccess = hookedMarket.depositRequiresAccess;
      data.withdrawalRequiresAccess = encodedHooksConfig.useOnQueueWithdrawal();
      data.minimumDeposit = hookedMarket.minimumDeposit;
      data.transfersDisabled = hookedMarket.transfersDisabled;
    } else if (data.kind == HooksInstanceKind.FixedTermLoan) {
      FixedTermHooks hooks = FixedTermHooks(data.hooksAddress);
      FixedTermHookedMarket memory hookedMarket = hooks.getHookedMarket(marketAddress);
      data.transferRequiresAccess = hookedMarket.transferRequiresAccess;
      data.depositRequiresAccess = hookedMarket.depositRequiresAccess;
      data.withdrawalRequiresAccess = hookedMarket.withdrawalRequiresAccess;
      data.minimumDeposit = hookedMarket.minimumDeposit;
      data.fixedTermEndTime = hookedMarket.fixedTermEndTime;
      data.transfersDisabled = hookedMarket.transfersDisabled;
      data.allowClosureBeforeTerm = hookedMarket.allowClosureBeforeTerm;
      data.allowTermReduction = hookedMarket.allowTermReduction;
    } else if (data.kind == HooksInstanceKind.PeriodicTerm) {
      PeriodicTermHooks hooks = PeriodicTermHooks(data.hooksAddress);
      PeriodicTermHookedMarket memory hookedMarket = hooks.getHookedMarket(marketAddress);
      data.transferRequiresAccess = hookedMarket.transferRequiresAccess;
      data.depositRequiresAccess = hookedMarket.depositRequiresAccess;
      data.withdrawalRequiresAccess = hookedMarket.withdrawalRequiresAccess;
      data.minimumDeposit = hookedMarket.minimumDeposit;
      data.transfersDisabled = hookedMarket.transfersDisabled;
      data.firstWithdrawalWindowStart = hookedMarket.firstWithdrawalWindowStart;
      data.periodDuration = hookedMarket.periodDuration;
      data.withdrawalWindowDuration = hookedMarket.withdrawalWindowDuration;
      data.periodicTermClosed = hookedMarket.isClosed;
    }
  }

  function fill(HooksConfigData memory data, HooksConfig hooksConfig) internal pure {
    data.useOnDeposit = hooksConfig.useOnDeposit();
    data.useOnQueueWithdrawal = hooksConfig.useOnQueueWithdrawal();
    data.useOnExecuteWithdrawal = hooksConfig.useOnExecuteWithdrawal();
    data.useOnTransfer = hooksConfig.useOnTransfer();
    data.useOnBorrow = hooksConfig.useOnBorrow();
    data.useOnRepay = hooksConfig.useOnRepay();
    data.useOnCloseMarket = hooksConfig.useOnCloseMarket();
    data.useOnNukeFromOrbit = hooksConfig.useOnNukeFromOrbit();
    data.useOnSetMaxTotalSupply = hooksConfig.useOnSetMaxTotalSupply();
    data.useOnSetAnnualInterestAndReserveRatioBips = hooksConfig
      .useOnSetAnnualInterestAndReserveRatioBips();
    data.useOnSetProtocolFeeBips = hooksConfig.useOnSetProtocolFeeBips();
    data.useOnExecutePendingAnnualInterestBipsReduction = hooksConfig
      .useOnExecutePendingAnnualInterestBipsReduction();
  }

  function fill(HooksDeploymentFlags memory data, HooksDeploymentConfig config) internal pure {
    data.optional.fill(config.optionalFlags());
    data.required.fill(config.requiredFlags());
  }
}
