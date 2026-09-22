// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseHooks, AccessConfig } from 'src/access/BaseHooks.sol';
import { OpenTermHooks, HookedMarket as OpenMarket } from 'src/access/OpenTermHooks.sol';
import { FixedTermHooks, HookedMarket as FixedMarket } from 'src/access/FixedTermHooks.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { HookedMarket as PeriodicMarket } from 'src/access/PeriodicTermHooks.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { HooksConfig, EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { TestKernel } from './TestKernel.sol';

enum HookKind {
  Open,
  Fixed,
  Periodic
}

/// @dev deploy the production artifacts and call their hooks directly. keep test cases out of
///      this fixture or every derived suite will run them again.
abstract contract HookTemplateFixture is TestKernel {
  uint32 internal constant StartTimestamp = 1_724_284_800;
  uint32 internal constant FixedTermEnd = StartTimestamp + 30 days;
  uint32 internal constant FirstWindowStart = StartTimestamp + 1 days;
  uint32 internal constant PeriodDuration = 14 days;
  uint32 internal constant WindowDuration = 2 days;
  address internal constant MarketA = address(0x1001);
  address internal constant MarketB = address(0x1002);
  address internal constant MarketC = address(0x1003);

  BaseHooks[3] internal hooks;

  function _setUpHooks() internal {
    vm.warp(StartTimestamp);
    for (uint256 i; i < hooks.length; i++) hooks[i] = _newHooks(HookKind(i), '');
  }

  function _newHooks(HookKind kind, bytes memory args) internal returns (BaseHooks) {
    string memory artifact = kind == HookKind.Open
      ? 'src/access/OpenTermHooks.sol:OpenTermHooks'
      : kind == HookKind.Fixed
      ? 'src/access/FixedTermHooks.sol:FixedTermHooks'
      : 'src/access/PeriodicTermHooks.sol:PeriodicTermHooks';
    return BaseHooks(_deployCode(artifact, abi.encode(address(this), args)));
  }

  function _termData(HookKind kind) internal pure returns (bytes memory) {
    if (kind == HookKind.Open) return '';
    if (kind == HookKind.Fixed) return abi.encode(FixedTermEnd);
    return abi.encode(FirstWindowStart, PeriodDuration, WindowDuration);
  }

  function _marketData(
    HookKind kind,
    uint256 minimum,
    bool disabled
  ) internal pure returns (bytes memory) {
    return bytes.concat(_termData(kind), abi.encode(minimum, disabled));
  }

  function _createMarket(
    BaseHooks target,
    address market,
    HooksConfig requested,
    bytes memory data
  ) internal returns (HooksConfig) {
    DeployMarketInputs memory inputs;
    inputs.hooks = requested.setHooksAddress(address(target));
    return target.onCreateMarket(address(this), market, inputs, data);
  }

  /// @dev use the public getters so these checks cover the tuples callers actually receive.
  ///      don't add a test-only getter for shared state.
  function _access(
    HookKind kind,
    BaseHooks target,
    address market
  ) internal view returns (AccessConfig memory access) {
    if (kind == HookKind.Open) {
      OpenMarket memory config = OpenTermHooks(address(target)).getHookedMarket(market);
      return
        AccessConfig(
          config.isHooked,
          config.transferRequiresAccess,
          config.depositRequiresAccess,
          true,
          config.minimumDeposit,
          config.transfersDisabled
        );
    }
    if (kind == HookKind.Fixed) {
      FixedMarket memory config = FixedTermHooks(address(target)).getHookedMarket(market);
      return
        AccessConfig(
          config.isHooked,
          config.transferRequiresAccess,
          config.depositRequiresAccess,
          config.withdrawalRequiresAccess,
          config.minimumDeposit,
          config.transfersDisabled
        );
    }
    PeriodicMarket memory config = PeriodicTermHooks(address(target)).getHookedMarket(market);
    return
      AccessConfig(
        config.isHooked,
        config.transferRequiresAccess,
        config.depositRequiresAccess,
        config.withdrawalRequiresAccess,
        config.minimumDeposit,
        config.transfersDisabled
      );
  }
}
