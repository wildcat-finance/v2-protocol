// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './BaseHooks.sol';
import '../libraries/SafeCastLib.sol';
import { HookedMarket } from './types/OpenTermHookTypes.sol';

using BoolUtils for bool;
using MathUtils for uint256;
using SafeCastLib for uint256;

/// @dev reusable open-term configuration and access adapters. the concrete hook supplies flags.
abstract contract OpenTermPolicy is BaseHooks {
  mapping(address => HookedMarket) internal _hookedMarkets;
  // keep immutable dispatch separate; adding it to HookedMarket would change the public tuple.
  mapping(address => bool) internal _depositHookEnabled;

  function _readBoolCd(bytes calldata data, uint offset) internal pure returns (bool value) {
    assembly {
      value := and(calldataload(add(data.offset, offset)), 1)
    }
  }

  function _readUint128Cd(bytes calldata data) internal pure returns (uint128 value) {
    uint _value;
    assembly {
      _value := calldataload(data.offset)
    }
    return _value.toUint128();
  }

  /// @dev binds the market after BaseHooks checks `administrator_` against the current
  ///      administrator. `hooksData` is `(uint128 minimumDeposit?, bool transfersDisabled?)`;
  ///      missing words read as zero. gated withdrawals need gated deposits and gated or disabled
  ///      transfers. otherwise a lender can enter without credentials and get stuck on exit.
  function _initializeMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal virtual override returns (HooksConfig marketHooksConfig) {
    (
      AccessConfig memory access,
      bool depositHookEnabled,
      HooksConfig effective
    ) = _configureMarketAccess(
        administrator_,
        marketAddress,
        parameters.hooks,
        _readUint128Cd(hooksData),
        _readBoolCd(hooksData, 0x20)
      );
    _depositHookEnabled[marketAddress] = depositHookEnabled;
    _hookedMarkets[marketAddress] = HookedMarket({
      isHooked: access.isHooked,
      transferRequiresAccess: access.transferRequiresAccess,
      depositRequiresAccess: access.depositRequiresAccess,
      minimumDeposit: access.minimumDeposit,
      transfersDisabled: access.transfersDisabled
    });
    return effective;
  }

  // ========================================================================== //
  //                              Market Management                             //
  // ========================================================================== //

  function _readAccessConfig(
    address market
  ) internal view virtual override returns (AccessConfig memory) {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    return
      AccessConfig({
        isHooked: hookedMarket.isHooked,
        transferRequiresAccess: hookedMarket.transferRequiresAccess,
        depositRequiresAccess: hookedMarket.depositRequiresAccess,
        // open-term withdrawals always check access when the market calls this hook.
        withdrawalRequiresAccess: true,
        minimumDeposit: hookedMarket.minimumDeposit,
        transfersDisabled: hookedMarket.transfersDisabled
      });
  }

  function _isDepositHookEnabled(address market) internal view virtual override returns (bool) {
    return _depositHookEnabled[market];
  }

  function _writeMinimumDeposit(address market, uint128 value) internal virtual override {
    _hookedMarkets[market].minimumDeposit = value;
  }
}
