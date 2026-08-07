// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantBase.sol';
import './CovenantModuleRegistry.sol';
import './lib/ICovenantModule.sol';
import './lib/CovenantEvents.sol';

/**
 * @title ModularCovenants
 * @dev Runtime covenant composition, with the mutability removed. A borrower
 *      may append registered covenant modules to their own live market;
 *      nobody, borrower included, may ever remove one.
 *
 *      Three invariants carry the design:
 *
 *      1. **Append-only, both levels.** The registry never removes; the
 *         per-market list never removes. A borrower who could loosen their
 *         covenants mid-life would be offering lenders nothing, so appends
 *         are irrevocable and self-binding is credible. This is the amendment
 *         mechanic compile-time mixins can't provide: a live market's terms
 *         can tighten, on the borrower's own initiative, and only tighten.
 *
 *      2. **STATICCALL isolation.** Modules are stateless predicates. Their
 *         parameters live here, in the dispatcher, and are handed to the
 *         module on each call, so a module cannot reach hooks storage, role
 *         state, or anything else. The worst a hostile module does is block
 *         draws on the market whose borrower chose to append it. Repayment
 *         and closure never consult modules, so a bricked market unwinds
 *         normally.
 *
 *      3. **Codehash pinned end to end.** The registry pins at registration,
 *         the append copies the pin, and every dispatch re-checks it,
 *         failing closed: a covenant that cannot be evaluated must not
 *         silently pass.
 *
 *      Appending requires acknowledging the registry's waiver by hash, which
 *      puts the risk allocation on-chain next to the act that takes the risk.
 *
 *      The registry pointer is per-market configuration, fixed at market
 *      creation like every other covenant parameter and never writable
 *      after. Lenders should verify `covenantModuleRegistry(market)` against
 *      the canonical deployment before treating appended covenants as
 *      meaningful.
 */
abstract contract ModularCovenants is CovenantBase, ICovenantEvents {
  struct AppendedModule {
    address module;
    bytes32 codehash;
    bytes config;
  }

  uint256 internal constant MAX_MODULES_PER_MARKET = 16;

  /// @dev Host requirement: the borrower this instance is bound to.
  function _modularBorrower() internal view virtual returns (address);

  mapping(address => CovenantModuleRegistry) internal _registryOf;
  mapping(address => AppendedModule[]) internal _appendedModules;

  function _initModularCovenants(address market, address registry) internal {
    if (registry == address(0) || registry.code.length == 0) {
      revert InvalidModuleRegistry();
    }
    _registryOf[market] = CovenantModuleRegistry(registry);
  }

  function covenantModuleRegistry(address market) external view returns (address) {
    return address(_registryOf[market]);
  }

  /// @notice Irrevocably append a registered covenant module to `market`.
  ///         Borrower only, own markets only, waiver acknowledged by hash.
  function appendCovenantModule(
    address market,
    address module,
    bytes calldata config,
    bytes32 waiverAcknowledgement
  ) external {
    if (msg.sender != _modularBorrower()) revert CallerNotCovenantBorrower();
    CovenantModuleRegistry registry = _registryOf[market];
    if (address(registry) == address(0)) revert NotOwnMarket();
    if (waiverAcknowledgement != registry.WAIVER_HASH()) {
      revert WaiverNotAcknowledged();
    }
    bytes32 pinned = registry.moduleCodehash(module);
    if (pinned == bytes32(0)) revert ModuleNotRegistered();
    if (module.codehash != pinned) revert ModuleCodehashMismatch();
    AppendedModule[] storage list = _appendedModules[market];
    uint256 n = list.length;
    if (n >= MAX_MODULES_PER_MARKET) revert TooManyModules();
    for (uint256 i; i < n; i++) {
      if (list[i].module == module) revert ModuleAlreadyAppended();
    }
    ICovenantModule(module).validateConfig(config);
    list.push(AppendedModule({ module: module, codehash: pinned, config: config }));
    emit CovenantModuleAppended(market, module, config);
  }

  /// @dev Called from `onBorrow`. Every appended module is dispatched by
  ///      STATICCALL and any failure blocks the draw, a codehash drift
  ///      included: fail closed, never open.
  function _modulesOnBorrow(uint256 drawnBefore, uint256 drawnAfter) internal view {
    AppendedModule[] storage list = _appendedModules[msg.sender];
    uint256 n = list.length;
    for (uint256 i; i < n; i++) {
      AppendedModule storage entry = list[i];
      address module = entry.module;
      if (module.codehash != entry.codehash) revert ModuleCodehashMismatch();
      (bool ok, bytes memory ret) = module.staticcall(
        abi.encodeWithSelector(
          ICovenantModule.checkOnBorrow.selector,
          msg.sender,
          drawnBefore,
          drawnAfter,
          entry.config
        )
      );
      if (!ok) {
        // surface the module's own revert data where it gave any
        if (ret.length > 0) {
          assembly {
            revert(add(ret, 0x20), mload(ret))
          }
        }
        revert CovenantModuleBlockedDraw(module);
      }
    }
  }

  function getAppendedModules(
    address market
  ) external view returns (AppendedModule[] memory) {
    return _appendedModules[market];
  }
}
