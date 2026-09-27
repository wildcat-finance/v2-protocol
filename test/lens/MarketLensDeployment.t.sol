// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MarketLens } from 'src/lens/MarketLens.sol';
import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';

/// @dev keep the deployment harness below EIP-170 too. run with --code-size-limit 24576;
///      the larger lifecycle suite owns the decoded-field and boundary assertions.
contract MarketLensDeploymentTest is ProductionMatrixFixture {
  function test_realLimits_LensHelpersAndFacade() external {
    ProductionStack memory stack = _deployProductionStack();
    bytes memory args = abi.encode(address(stack.archController), address(stack.standardFactory));
    address core = _deployCode('src/lens/MarketLensCore.sol:MarketLensCore', args);
    address aggregator = _deployCode(
      'src/lens/MarketLensAggregator.sol:MarketLensAggregator',
      args
    );
    address live = _deployCode('src/lens/MarketLensLive.sol:MarketLensLive', args);
    MarketLens lens = MarketLens(
      _deployCode(
        'src/lens/MarketLens.sol:MarketLens',
        abi.encode(
          address(stack.archController),
          address(stack.standardFactory),
          core,
          aggregator,
          live
        )
      )
    );
    assertTrue(core.code.length <= 24_576, 'core runtime fits');
    assertTrue(aggregator.code.length <= 24_576, 'aggregator runtime fits');
    assertTrue(live.code.length <= 24_576, 'live runtime fits');
    assertTrue(address(lens).code.length <= 24_576, 'facade runtime fits');
    assertEq(address(lens.coreHelper()), core, 'core binding');
    assertEq(address(lens.aggregationHelper()), aggregator, 'aggregator binding');
    assertEq(address(lens.liveHelper()), live, 'live binding');

    for (uint256 i; i < 2; i++) {
      MatrixOptions memory options = _defaultMatrixOptions(
        MatrixHooksKind.OpenTerm,
        MatrixMarketKind(i)
      );
      options.repaymentDate = uint32(vm.getBlockTimestamp() + 1 days);
      options.repaymentPeriod = 1 days;
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        options,
        MatrixBorrower,
        MatrixBorrower,
        uint96(i)
      );
      address[] memory markets = new address[](1);
      markets[0] = address(cell.market);
      vm.warp(options.repaymentDate);
      assertTrue(cell.market.isClosed(), 'empty market previews closure');
      _assertForwarded(
        core,
        address(lens),
        abi.encodeWithSignature('getMarketDataV2(address)', markets[0])
      );
      _assertForwarded(
        live,
        address(lens),
        abi.encodeWithSignature('getMarketsLiveDataV2(address[])', markets)
      );
      _assertForwarded(
        aggregator,
        address(lens),
        abi.encodeWithSignature(
          'getAllMarketsDataV2ForHooksTemplate(address,address)',
          address(_factoryFor(stack, options.marketKind)),
          cell.hooksTemplate
        )
      );
    }
  }

  function _assertForwarded(address helper, address facade, bytes memory input) private view {
    (bool directSuccess, bytes memory direct) = helper.staticcall(input);
    (bool facadeSuccess, bytes memory forwarded) = facade.staticcall(input);
    assertTrue(directSuccess, 'helper read succeeds');
    assertTrue(facadeSuccess, 'facade read succeeds');
    assertTrue(direct.length != 0, 'nonempty return data');
    assertEq(forwarded, direct, 'exact return bytes');
  }
}
