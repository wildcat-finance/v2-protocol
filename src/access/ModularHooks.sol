// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './covenants/CovenantHooksCore.sol';
import './covenants/ModularCovenants.sol';

/**
 * @title ModularHooks
 * @dev Deployable template: open-term revolving hooks with runtime covenant
 *      composition through an append-only module registry.
 *
 *      `hooksData` is standard ABI encoding of `(uint128 minimumDeposit,
 *      bool transfersDisabled, address registry)`: the registry pointer is
 *      market configuration, fixed at creation. Covenant modules arrive
 *      after creation, by borrower append, and never leave. Lenders should
 *      verify `covenantModuleRegistry(market)` against the canonical
 *      deployment before treating appended covenants as meaningful.
 */
contract ModularHooks is CovenantHooksCore, ModularCovenants {
  constructor(address _deployer, bytes memory args) CovenantHooksCore(_deployer, args) {}

  function version() external pure override returns (string memory) {
    return 'ModularHooks';
  }

  function _modularBorrower() internal view override returns (address) {
    return borrower;
  }

  function _requiredCovenantFlags() internal pure override returns (HooksConfig) {
    return EmptyHooksConfig.setFlag(Bit_Enabled_Borrow);
  }

  function _initCovenants(
    address marketAddress,
    DeployMarketInputs calldata,
    bytes calldata hooksData
  ) internal override {
    (, , address registry) = abi.decode(hooksData, (uint128, bool, address));
    _initModularCovenants(marketAddress, registry);
  }

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata /* extraData */
  ) external override {
    uint256 drawnBefore = _covenantDrawnBefore(state);
    uint256 drawnAfter = _drawnAfterBorrow(state, normalizedAmount);
    _modulesOnBorrow(drawnBefore, drawnAfter);
  }

  /// @dev Required by `IHooks`; modules never observe repayments.
  function onRepay(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}
}
