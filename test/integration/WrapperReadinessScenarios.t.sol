// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './MarketConfigMatrix.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';

contract WrapperReadinessScenariosTest is MarketConfigMatrix {
  function test_wrapperReadinessAcrossBuiltInHookTemplates() external {
    _assertReadiness(MatrixHooksKind.OpenTerm);
    _assertReadiness(MatrixHooksKind.FixedTerm);
    _assertReadiness(MatrixHooksKind.PeriodicTerm);
  }

  function _assertReadiness(MatrixHooksKind hooksKind) internal {
    DeployedCell memory d = deployCell(defaultCell(hooksKind, MatrixMarketKind.Standard));
    Wildcat4626Wrapper wrapper = Wildcat4626Wrapper(
      wrapperFactory.createWrapper(address(d.market))
    );

    assertEq(wrapper.maxDeposit(alice), 0, 'uncredentialed wrapper capacity');
    assertEq(wrapper.maxMint(alice), 0, 'uncredentialed wrapper mint capacity');
    assertGt(wrapper.previewDeposit(1e18), 0, 'preview unexpectedly gated');

    _grantHookRole(d.hooksInstance, address(wrapper));

    assertGt(wrapper.maxDeposit(alice), 0, 'credentialed wrapper capacity');
    assertGt(wrapper.maxMint(alice), 0, 'credentialed wrapper mint capacity');
  }
}
