// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // LegacyMarketCoverage.t
//  \ ^ /   Native legacy coverage through full and live lens routes.
//    V
//
//  LEGACY FACTORY INTERFACE
//  registerWithArchController()
//  addHooksTemplate(...)
//  deployHooksInstance(...)
//  deployMarket(...)
//
//  FIXTURE
//  setUp()
//  _legacyInitCode(...)
//  _createLegacyArtifact(...)
//  _legacyMarket(...)
//  _repayLegacy(...)
//  _readQuotes(...)
//
//  COVERAGE AND REPAYMENT
//  test_quoteClearsDelinquency()
//  test_withdrawalCoverage()
//  test_closedMarketCoverage()
//  test_coverageReadFailures()
// ═════

import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { HooksConfig, Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { MarketAccountingReader } from 'src/lens/MarketAccountingReader.sol';
import { MarketLensCore } from 'src/lens/MarketLensCore.sol';
import { MarketLensLive } from 'src/lens/MarketLensLive.sol';
import { MarketData } from 'src/lens/MarketData.sol';
import { MarketLiveDataV2_5 } from 'src/lens/MarketLiveData.sol';

struct LegacyDeployMarketInputs {
  address asset;
  string namePrefix;
  string symbolPrefix;
  uint128 maxTotalSupply;
  uint16 annualInterestBips;
  uint16 delinquencyFeeBips;
  uint32 withdrawalBatchDuration;
  uint16 reserveRatioBips;
  uint32 delinquencyGracePeriod;
  HooksConfig hooks;
}

// ┌─ ILegacyQuoteFactory ──────────────────────────────────────────────────────
interface ILegacyQuoteFactory {
  // ┌─ registerWithArchController ─────
  function registerWithArchController() external;

  // ┌─ addHooksTemplate ─────
  function addHooksTemplate(address, string calldata, address, address, uint80, uint16) external;

  // ┌─ deployHooksInstance ─────
  function deployHooksInstance(address, bytes calldata) external returns (address);

  // ┌─ deployMarket ─────
  function deployMarket(
    LegacyDeployMarketInputs calldata,
    bytes calldata,
    bytes32,
    address,
    uint256
  )
    external
    returns (address);
}

// ┌─ LegacyMarketCoverageTest ─────────────────────────────────────────────────
contract LegacyMarketCoverageTest is ProductionMatrixFixture {
  error NativeCoverageUnavailable();

  uint256 internal constant LegacySupply = 1_000_000_000_019;
  MockERC20 internal asset;
  ILegacyQuoteFactory internal factory;
  OpenTermHooks internal hooks;
  MarketLensCore internal core;
  MarketLensLive internal live;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    ProductionStack memory stack = _deployProductionStack();
    asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20', abi.encode('Legacy USD', 'LUSD', uint8(6))
      )
    );
    bytes memory marketInitCode = _legacyInitCode('market');
    address marketStorage = LibStoredInitCode.deployInitCode(marketInitCode);
    factory = ILegacyQuoteFactory(
      _createLegacyArtifact(
        'factory',
        abi.encode(
          address(stack.archController), address(stack.sentinel), marketStorage, uint256(keccak256(marketInitCode))
        )
      )
    );
    stack.archController.registerControllerFactory(address(factory));
    factory.registerWithArchController();
    address hooksTemplate = LibStoredInitCode.deployInitCode(_legacyInitCode('hooks'));
    factory.addHooksTemplate(hooksTemplate, 'Legacy Open Term', address(0), address(0), 0, 0);
    vm.prank(MatrixBorrower);
    hooks = OpenTermHooks(factory.deployHooksInstance(hooksTemplate, ''));
    vm.prank(MatrixBorrower);
    hooks.grantRole(MatrixAlice, uint32(vm.getBlockTimestamp()));

    bytes memory lensArgs = abi.encode(address(stack.archController), address(factory));
    core = MarketLensCore(_deployCode('src/lens/MarketLensCore.sol:MarketLensCore', lensArgs));
    live = MarketLensLive(_deployCode('src/lens/MarketLensLive.sol:MarketLensLive', lensArgs));
  }

  // ┌─ _legacyInitCode ─────
  function _legacyInitCode(string memory name) internal view returns (bytes memory) {
    // these original artifacts are identical at v2.0.0 and v2.1.0. their source
    // revisions and bytecode hashes are retained alongside the fixture bytes.
    string memory fixtureJson = vm.readFile('test/fixtures/legacy-v2.json');
    return vm.parseJsonBytes(fixtureJson, string.concat('.artifacts.', name, '.creationCode'));
  }

  // ┌─ _createLegacyArtifact ─────
  function _createLegacyArtifact(string memory name, bytes memory args) internal returns (address deployed) {
    bytes memory code = bytes.concat(_legacyInitCode(name), args);
    assembly ('memory-safe') {
      deployed := create(0, add(code, 32), mload(code))
    }
    require(deployed != address(0), 'legacy artifact deployment');
  }

  // ┌─ _legacyMarket ─────
  function _legacyMarket(uint96 nonce) internal returns (WildcatMarket market) {
    LegacyDeployMarketInputs memory inputs = LegacyDeployMarketInputs({
      asset: address(asset),
      namePrefix: 'Legacy ',
      symbolPrefix: 'lg',
      maxTotalSupply: 2_000_000e6,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 1_000,
      withdrawalBatchDuration: 1 days,
      reserveRatioBips: 5_000,
      delinquencyGracePeriod: 2_000,
      hooks: HooksConfig.wrap(uint256(uint160(address(hooks))) << 96).setFlag(Bit_Enabled_Deposit)
    });
    bytes32 salt = bytes32((uint256(uint160(MatrixBorrower)) << 96) | nonce);
    vm.prank(MatrixBorrower);
    market = WildcatMarket(factory.deployMarket(inputs, '', salt, address(0), 0));
    asset.mint(MatrixAlice, LegacySupply);
    vm.startPrank(MatrixAlice);
    asset.approve(address(market), type(uint256).max);
    market.deposit(LegacySupply);
    vm.stopPrank();
    vm.startPrank(MatrixBorrower);
    asset.approve(address(market), type(uint256).max);
    market.borrow(market.borrowableAssets());
    vm.stopPrank();
    assertEq(market.totalAssets(), 500_000_000_010, 'initial native reserves');
    assertFalse(MarketAccountingReader.previousState(market).isDelinquent, 'initially collateralized');
  }

  // ┌─ _repayLegacy ─────
  function _repayLegacy(WildcatMarket market, uint256 amount) internal {
    vm.prank(MatrixBorrower);
    market.repay(amount);
  }

  // ┌─ _readQuotes ─────
  function _readQuotes(WildcatMarket market) internal view returns (MarketData memory full) {
    full = core.getMarketData(address(market));
    address[] memory markets = new address[](1);
    markets[0] = address(market);
    MarketLiveDataV2_5 memory current = live.getMarketsLiveDataV2(markets)[0];
    assertEq(current.coverageLiquidity, full.coverageLiquidity, 'full/live coverage parity');
    assertEq(current.totalAssets, full.totalAssets, 'full/live asset parity');
    assertEq(current.isDelinquent, full.isDelinquent, 'full/live delinquency parity');
    assertEq(full.coverageLiquidity, market.coverageLiquidity(), 'native legacy coverage');
  }

  // ░░▒▒▓▓██ [ COVERAGE AND REPAYMENT ] ───────────────────────────────────────

  // ┌─ test_quoteClearsDelinquency ─────
  function test_quoteClearsDelinquency() external {
    WildcatMarket quoted = _legacyMarket(1);
    WildcatMarket underpaid = _legacyMarket(2);
    (, bytes memory encodedState) = address(quoted).staticcall(abi.encodeWithSignature('currentState()'));
    assertEq(encodedState.length, 0x1c0, 'real fourteen-word legacy state');
    assertEq(MarketAccountingReader.currentState(quoted).withdrawalRemainder, 0, 'reader pads remainder');
    assertEq(_readQuotes(quoted).coverageLiquidity, quoted.coverageLiquidity(), 'initial quote is accurate');

    vm.warp(vm.getBlockTimestamp() + 365 days / 2);
    MarketData memory quote = _readQuotes(quoted);
    uint256 displayedDebt = quote.coverageLiquidity - quote.totalAssets;
    uint256 nativeDebt = quoted.coverageLiquidity() - quoted.totalAssets();
    assertEq(displayedDebt, 25_000e6 + 1, 'lens-derived cure quote');
    assertEq(nativeDebt, displayedDebt, 'native and lens quotes agree');
    assertEq(underpaid.coverageLiquidity() - underpaid.totalAssets(), nativeDebt, 'identical control quote');

    _repayLegacy(quoted, displayedDebt);
    _repayLegacy(underpaid, nativeDebt - 1);
    quote = _readQuotes(quoted);
    assertEq(quote.coverageLiquidity, quote.totalAssets, 'quoted repayment funds coverage exactly');
    assertFalse(quote.isDelinquent, 'quoted repayment clears delinquency');
    assertFalse(MarketAccountingReader.previousState(quoted).isDelinquent, 'cure committed');
    MarketData memory shortQuote = _readQuotes(underpaid);
    assertEq(shortQuote.coverageLiquidity - shortQuote.totalAssets, 1, 'underpayment remains visible');
    assertTrue(shortQuote.isDelinquent, 'one-unit underpayment control');

    vm.warp(vm.getBlockTimestamp() + 12 hours);
    quoted.updateState();
    underpaid.updateState();
    MarketState memory badState = MarketAccountingReader.previousState(underpaid);
    MarketState memory goodState = MarketAccountingReader.previousState(quoted);
    assertEq(badState.timeDelinquent, 12 hours, 'residual delinquency time accumulates');
    assertEq(goodState.timeDelinquent, 0, 'immediate cure avoids the elapsed penalty');
    // ordinary interest can create a new shortfall at this checkpoint. legacy
    // accrual uses the stored healthy flag for the interval following the cure.
    assertEq(underpaid.totalDebts() - quoted.totalDebts(), 137_176_561, 'penalty avoided by quoted repayment');
  }

  // ┌─ test_withdrawalCoverage ─────
  function test_withdrawalCoverage() external {
    WildcatMarket market = _legacyMarket(1);
    vm.warp(vm.getBlockTimestamp() + 365 days / 2);
    vm.prank(MatrixAlice);
    uint32 expiry = market.queueWithdrawal(800_000e6 + 1);
    assertTrue(MarketAccountingReader.currentState(market).scaledPendingWithdrawals > 0, 'pending withdrawal');
    _readQuotes(market);
    vm.warp(uint256(expiry) + 1);
    _readQuotes(market);
    market.updateState();
    assertTrue(MarketAccountingReader.previousState(market).normalizedUnclaimedWithdrawals > 0, 'paid withdrawal');
    _readQuotes(market);
  }

  // ┌─ test_closedMarketCoverage ─────
  function test_closedMarketCoverage() external {
    WildcatMarket market = _legacyMarket(1);
    vm.warp(vm.getBlockTimestamp() + 365 days / 2);
    asset.mint(MatrixBorrower, market.totalDebts());
    vm.prank(MatrixBorrower);
    market.closeMarket();
    MarketData memory quote = _readQuotes(market);
    assertTrue(quote.isClosed, 'legacy market closed');
    assertEq(quote.coverageLiquidity, quote.totalSupply, 'closed supply is fully reserved');
  }

  // ┌─ test_coverageReadFailures ─────
  function test_coverageReadFailures() external {
    WildcatMarket market = _legacyMarket(1);
    address[] memory markets = new address[](1);
    markets[0] = address(market);
    bytes memory selector = abi.encodeWithSelector(market.coverageLiquidity.selector);
    bytes memory reason = abi.encodeWithSelector(NativeCoverageUnavailable.selector);
    vm.mockCallRevert(address(market), selector, reason);
    vm.expectRevert(reason);
    core.getMarketData(address(market));
    vm.expectRevert(reason);
    live.getMarketsLiveDataV2(markets);
    vm.clearMockedCalls();
    vm.mockCall(address(market), selector, new bytes(31));
    vm.expectRevert();
    core.getMarketData(address(market));
    vm.expectRevert();
    live.getMarketsLiveDataV2(markets);
  }
}
