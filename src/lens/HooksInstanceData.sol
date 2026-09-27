// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

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

/// @notice factory provenance, administration, providers, and market count for one hooks instance.
/// @dev unknown hook families still return common factory and callback data. typed fields remain
///      empty when their interface is not known.
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
  /// @dev false for older ten-word constraint tuples or unknown hook families.
  bool repaymentConstraintsAvailable;
}

/// @notice builds hooks-instance views from factory records and bounded optional probes.
library HooksInstanceDataLib {
  using RoleProviderDataLib for *;

  error InvalidParameterConstraints();

  bytes4 internal constant _BORROWER_SELECTOR = bytes4(keccak256('borrower()'));

  function _readConstraints(
    address hooksAddress
  ) internal view returns (MarketParameterConstraints memory constraints, bool hasRepaymentBounds) {
    bytes memory result = new bytes(0x180);
    uint256 selector = uint32(bytes4(keccak256('getParameterConstraints()')));
    uint256 size;
    assembly ('memory-safe') {
      let ptr := add(result, 0x20)
      mstore(ptr, shl(224, selector))
      let success := staticcall(gas(), hooksAddress, ptr, 4, ptr, 0x180)
      size := returndatasize()
      if iszero(success) {
        let errorPtr := mload(0x40)
        returndatacopy(errorPtr, 0, size)
        revert(errorPtr, size)
      }
      // older hooks return ten words. pad only the two new bounds, then let abi.decode
      // validate every uint16/uint32 field just as the typed call did.
      if eq(size, 0x140) {
        mstore(add(ptr, 0x140), 0)
        mstore(add(ptr, 0x160), 0)
      }
    }
    if (size != 0x140 && size < 0x180) revert InvalidParameterConstraints();
    constraints = abi.decode(result, (MarketParameterConstraints));
    hasRepaymentBounds = size >= 0x180;
  }

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

  /// @notice fills one hooks instance using factory data and optional typed probes.
  /// @param administrator trusted factory-index key, or zero to probe the hooks instance.
  /// @param kind family already identified from `version()`.
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
      (data.constraints, data.repaymentConstraintsAvailable) = _readConstraints(hooksAddress);
      data.name = hooks.name();
    }

    address templateAddress = factory.getHooksTemplateForInstance(hooksAddress);
    data.hooksTemplate.fill(factory, templateAddress, data.administrator);
    data.deploymentFlags.fill(hooks.config());
    data.totalMarkets = factory.getMarketsForHooksInstanceCount(hooksAddress);
  }
}
