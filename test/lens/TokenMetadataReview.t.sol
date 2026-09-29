// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { LibERC20 } from 'src/libraries/LibERC20.sol';
import { MarketData } from 'src/lens/MarketData.sol';
import { MarketLensCore } from 'src/lens/MarketLensCore.sol';
import { TokenMetadata } from 'src/lens/TokenData.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';

/// @dev Characterizes the unmodified 7b7db0e candidate. Expected failures are
/// compatibility limitations, not assertions that those limitations are fixed.
contract TokenMetadataReviewTest is ProductionMatrixFixture {
  ProductionStack internal stack;
  MarketLensCore internal core;

  function setUp() external {
    stack = _deployProductionStack();
    core = MarketLensCore(
      _deployCode(
        'src/lens/MarketLensCore.sol:MarketLensCore',
        abi.encode(address(stack.archController), address(stack.standardFactory))
      )
    );
  }

  function deployMarket(MatrixMarketKind kind, uint96 nonce) external returns (address) {
    return address(_deployCell(stack, kind, nonce).market);
  }

  function _deployCell(
    ProductionStack memory selectedStack,
    MatrixMarketKind kind,
    uint96 nonce
  ) internal returns (MatrixCell memory) {
    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, kind);
    options.annualInterestBips = 0;
    options.commitmentFeeBips = 0;
    options.delinquencyFeeBips = 0;
    return _deployMatrixCell(selectedStack, options, MatrixBorrower, MatrixBorrower, nonce);
  }

  function _mockName(bytes memory response) internal {
    vm.mockCall(address(stack.asset), abi.encodeWithSignature('name()'), response);
  }

  function _mockSymbol(bytes memory response) internal {
    vm.mockCall(address(stack.asset), abi.encodeWithSignature('symbol()'), response);
  }

  function _repeat(uint256 length) internal pure returns (string memory) {
    bytes memory value = new bytes(length);
    for (uint256 i; i < length; i++) value[i] = 'x';
    return string(value);
  }

  function test_canonicalEmptyStringsRejectButLegacyEmptyWordsDeploy() external {
    bytes memory emptyString = abi.encode('');
    assertEq(emptyString.length, 64, 'canonical empty ABI size');
    _mockName(emptyString);
    vm.expectRevert(bytes4(0x4cb9c000));
    core.getTokenInfo(address(stack.asset));
    for (uint256 k; k < 2; k++) {
      vm.expectRevert(bytes4(0x4cb9c000));
      this.deployMarket(MatrixMarketKind(k), uint96(k + 1));
    }

    vm.clearMockedCalls();
    _mockSymbol(emptyString);
    vm.expectRevert(bytes4(0x4cb9c000));
    core.getTokenInfo(address(stack.asset));
    for (uint256 k; k < 2; k++) {
      vm.expectRevert(bytes4(0x4cb9c000));
      this.deployMarket(MatrixMarketKind(k), uint96(k + 1));
    }

    vm.clearMockedCalls();
    _mockName(abi.encode(bytes32(0)));
    _mockSymbol(abi.encode(bytes32(0)));
    TokenMetadata memory data = core.getTokenInfo(address(stack.asset));
    assertEq(data.name, '', 'empty legacy name');
    assertEq(data.symbol, '', 'empty legacy symbol');
    for (uint256 k; k < 2; k++) {
      WildcatMarket market = WildcatMarket(this.deployMarket(MatrixMarketKind(k), uint96(k + 1)));
      assertEq(market.name(), 'Wildcat ', 'prefix-only market name');
      assertEq(market.symbol(), 'wc', 'prefix-only market symbol');
    }
  }

  function test_factoryNameLimitCountsCombinedUtf8Bytes() external {
    _mockName(abi.encode(_repeat(55)));
    for (uint256 k; k < 2; k++) {
      WildcatMarket market = WildcatMarket(this.deployMarket(MatrixMarketKind(k), uint96(k + 1)));
      assertEq(bytes(market.name()).length, 63, '55 bytes plus eight-byte prefix fits');
    }

    string memory unicodeName = string.concat(_repeat(53), unicode'猫');
    assertEq(bytes(unicodeName).length, 56, '54 characters occupy 56 bytes');
    _mockName(abi.encode(unicodeName));
    for (uint256 k; k < 2; k++) {
      vm.expectRevert(bytes4(0x19a65cb6));
      this.deployMarket(MatrixMarketKind(k), uint96(k + 3));
    }
  }

  function test_factorySymbolLimitCountsCombinedBytes() external {
    _mockSymbol(abi.encode(_repeat(61)));
    for (uint256 k; k < 2; k++) {
      WildcatMarket market = WildcatMarket(this.deployMarket(MatrixMarketKind(k), uint96(k + 1)));
      assertEq(bytes(market.symbol()).length, 63, '61 bytes plus two-byte prefix fits');
    }
    _mockSymbol(abi.encode(_repeat(62)));
    for (uint256 k; k < 2; k++) {
      vm.expectRevert(bytes4(0x19a65cb6));
      this.deployMarket(MatrixMarketKind(k), uint96(k + 3));
    }
  }

  function test_unicodeMetadataPreservedAndMarketIdentityCached() external {
    string memory name = unicode'Token 猫';
    string memory symbol = unicode'猫';
    _mockName(abi.encode(name));
    _mockSymbol(abi.encode(symbol));
    MatrixCell memory cell = _deployCell(stack, MatrixMarketKind.Standard, 1);
    assertEq(cell.market.name(), string.concat('Wildcat ', name), 'UTF-8 name preserved');
    assertEq(cell.market.symbol(), string.concat('wc', symbol), 'UTF-8 symbol preserved');
    _mockName(abi.encode('Renamed Token'));
    _mockSymbol(abi.encode('NEW'));
    MarketData memory data = core.getMarketData(address(cell.market));
    assertEq(data.underlyingToken.name, 'Renamed Token', 'lens underlying name is live');
    assertEq(data.marketToken.name, string.concat('Wildcat ', name), 'market name remains cached');
    assertEq(data.marketToken.symbol, string.concat('wc', symbol), 'market symbol remains cached');
  }

  function test_missingDecimalsRejectsCreationAndTokenRead() external {
    vm.mockCall(address(stack.asset), abi.encodeWithSignature('decimals()'), bytes(''));
    vm.expectRevert(LibERC20.DecimalsFailed.selector);
    core.getTokenInfo(address(stack.asset));
    for (uint256 k; k < 2; k++) {
      vm.expectRevert(LibERC20.DecimalsFailed.selector);
      this.deployMarket(MatrixMarketKind(k), uint96(k + 1));
    }
    vm.clearMockedCalls();
    vm.mockCall(address(stack.asset), abi.encodeWithSignature('decimals()'), abi.encode(uint8(6)));
    WildcatMarket market = WildcatMarket(this.deployMarket(MatrixMarketKind.Standard, 1));
    assertEq(market.decimals(), 6, 'valid six-decimal metadata is cached');
  }

  function test_mutableDecimalsProducesConflictingLensUnits() external {
    MatrixCell memory cell = _deployCell(stack, MatrixMarketKind.Standard, 1);
    assertEq(cell.market.decimals(), 18, 'creation units');
    vm.mockCall(address(stack.asset), abi.encodeWithSignature('decimals()'), abi.encode(uint8(6)));
    MarketData memory data = core.getMarketData(address(cell.market));
    assertEq(data.marketToken.decimals, 18, 'market immutable units');
    assertEq(data.underlyingToken.decimals, 6, 'underlying live units');
    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, 1e18);
    assertEq(cell.market.balanceOf(MatrixAlice), 1e18, 'raw accounting remains one-for-one');
    assertEq(stack.asset.balanceOf(address(cell.market)), 1e18, 'raw underlying balance');
  }

  function test_failedMetadataAbortsMixedMarketReadButNotDepositsOrWithdrawal() external {
    MatrixCell memory affected = _deployCell(stack, MatrixMarketKind.Standard, 1);
    ProductionStack memory healthyStack = stack;
    healthyStack.asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode('Healthy Token', 'HLTH', uint8(18))
      )
    );
    MatrixCell memory healthy = _deployCell(healthyStack, MatrixMarketKind.Standard, 2);
    address[] memory markets = new address[](2);
    markets[0] = address(healthy.market);
    markets[1] = address(affected.market);
    assertEq(core.getMarketsData(markets).length, 2, 'both read before metadata failure');

    vm.mockCallRevert(
      address(stack.asset),
      abi.encodeWithSignature('name()'),
      bytes('metadata unavailable')
    );
    assertEq(
      core.getMarketData(address(healthy.market)).underlyingToken.name,
      'Healthy Token',
      'healthy read remains available'
    );
    vm.expectRevert(bytes('metadata unavailable'));
    core.getMarketsData(markets);

    _authorize(stack, affected, MatrixAlice);
    _deposit(stack, affected, MatrixAlice, 1e18);
    vm.prank(MatrixAlice);
    uint32 expiry = affected.market.queueFullWithdrawal();
    vm.warp(uint256(expiry) + 1);
    assertEq(
      affected.market.executeWithdrawal(MatrixAlice, expiry),
      1e18,
      'withdrawal does not read metadata'
    );
    assertEq(stack.asset.balanceOf(MatrixAlice), 1e18, 'lender receives underlying');

    vm.clearMockedCalls();
    assertEq(core.getMarketsData(markets).length, 2, 'restored metadata restores batch read');
  }
}
