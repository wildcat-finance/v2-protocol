// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { MarketLens } from 'src/lens/MarketLens.sol';
import { MarketLensCore } from 'src/lens/MarketLensCore.sol';
import { HooksConfigData, HooksInstanceKind } from 'src/lens/HooksConfigData.sol';
import { LenderAccountQuery, OptionalUintDataV2_5 } from 'src/lens/MarketData.sol';
import { Bit_Enabled_Borrow } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_CloseMarket } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_ExecutePendingAnnualInterestBipsReduction } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_ExecuteWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_NukeFromOrbit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Repay } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetAnnualInterestAndReserveRatioBips } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetMaxTotalSupply } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetProtocolFeeBips } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig, HooksConfig } from 'src/types/HooksConfig.sol';
import { LensDelegateTargetMock, LensProbeHarness, LensV1MarketMock } from '../mocks/LensMocks.sol';
import { MalformedVersionMock, OptionalUintTargetMock } from '../mocks/LensMocks.sol';
import { RevertingVersionMock, VersionStringMock } from '../mocks/LensMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract MarketLensFacadeTest is TestKernel {
  uint256 internal constant CoreResponse = 0xC0;
  uint256 internal constant AggregationResponse = 0xA0;
  uint256 internal constant LiveResponse = 0x11;

  MarketLens internal lens;
  LensProbeHarness internal probes;

  function setUp() external {
    address core = _deployCode(
      'test-next/mocks/LensMocks.sol:LensDelegateTargetMock',
      abi.encode(CoreResponse, false)
    );
    address aggregation = _deployCode(
      'test-next/mocks/LensMocks.sol:LensDelegateTargetMock',
      abi.encode(AggregationResponse, false)
    );
    address live = _deployCode(
      'test-next/mocks/LensMocks.sol:LensDelegateTargetMock',
      abi.encode(LiveResponse, false)
    );
    lens = MarketLens(
      _deployCode(
        'src/lens/MarketLens.sol:MarketLens',
        abi.encode(address(0xA11CE), address(0xFAC7), core, aggregation, live)
      )
    );
    probes = LensProbeHarness(_deployCode('test-next/mocks/LensMocks.sol:LensProbeHarness'));
  }

  function _assertRoute(bytes memory payload, uint256 expectedResponse) internal view {
    (bool success, bytes memory result) = address(lens).staticcall(payload);
    assertTrue(success, 'facade call');
    assertEq(result, abi.encode(expectedResponse), 'helper route');
  }

  function _aggregationRoute(bytes memory payload) internal view {
    _assertRoute(payload, AggregationResponse);
  }

  function _coreRoute(bytes memory payload) internal view {
    _assertRoute(payload, CoreResponse);
  }

  function test_constructorAndAggregationRoutes_AreComplete() external view {
    address borrower = address(0xB0B);
    address factory = address(0xFAC7);
    address template = address(0x7E4);
    address[] memory templates = new address[](1);
    templates[0] = template;

    assertEq(address(lens.archController()), address(0xA11CE), 'controller');
    assertEq(address(lens.hooksFactory()), factory, 'factory');

    _aggregationRoute(abi.encodeWithSignature('getHooksDataForBorrower(address)', borrower));
    _aggregationRoute(
      abi.encodeWithSignature('getHooksDataForBorrower(address,address)', factory, borrower)
    );
    _aggregationRoute(
      abi.encodeWithSignature('getAggregatedHooksDataForBorrower(address)', borrower)
    );
    _aggregationRoute(abi.encodeWithSignature('getHooksInstancesForBorrower(address)', borrower));
    _aggregationRoute(
      abi.encodeWithSignature('getHooksInstancesForBorrower(address,address)', factory, borrower)
    );
    _aggregationRoute(
      abi.encodeWithSignature('getAggregatedHooksInstancesForBorrower(address)', borrower)
    );
    _aggregationRoute(
      abi.encodeWithSignature('getHooksTemplateForBorrower(address,address)', borrower, template)
    );
    _aggregationRoute(
      abi.encodeWithSignature(
        'getHooksTemplateForBorrower(address,address,address)',
        factory,
        borrower,
        template
      )
    );
    _aggregationRoute(
      abi.encodeWithSignature(
        'getHooksTemplatesForBorrower(address,address[])',
        borrower,
        templates
      )
    );
    _aggregationRoute(
      abi.encodeWithSignature(
        'getHooksTemplatesForBorrower(address,address,address[])',
        factory,
        borrower,
        templates
      )
    );
    _aggregationRoute(
      abi.encodeWithSignature('getAllHooksTemplatesForBorrower(address)', borrower)
    );
    _aggregationRoute(
      abi.encodeWithSignature('getAllHooksTemplatesForBorrower(address,address)', factory, borrower)
    );
    _aggregationRoute(
      abi.encodeWithSignature('getAggregatedAllHooksTemplatesForBorrower(address)', borrower)
    );
    _aggregationRoute(
      abi.encodeWithSignature(
        'getAggregatedHooksTemplatesForBorrowerWithFactory(address)',
        borrower
      )
    );
  }

  function test_aggregationMarketRoutes_AreComplete() external view {
    address factory = address(0xFAC7);
    address template = address(0x7E4);

    _aggregationRoute(
      abi.encodeWithSignature('getMarketsForHooksTemplateCount(address)', template)
    );
    _aggregationRoute(
      abi.encodeWithSignature('getMarketsForHooksTemplateCount(address,address)', factory, template)
    );
    _aggregationRoute(
      abi.encodeWithSignature('getAggregatedMarketsForHooksTemplateCount(address)', template)
    );
    _aggregationRoute(
      abi.encodeWithSignature(
        'getPaginatedMarketsDataForHooksTemplate(address,uint256,uint256)',
        template,
        1,
        2
      )
    );
    _aggregationRoute(
      abi.encodeWithSignature(
        'getPaginatedMarketsDataForHooksTemplate(address,address,uint256,uint256)',
        factory,
        template,
        1,
        2
      )
    );
    _aggregationRoute(
      abi.encodeWithSignature(
        'getPaginatedMarketsDataV2ForHooksTemplate(address,uint256,uint256)',
        template,
        1,
        2
      )
    );
    _aggregationRoute(
      abi.encodeWithSignature(
        'getPaginatedMarketsDataV2ForHooksTemplate(address,address,uint256,uint256)',
        factory,
        template,
        1,
        2
      )
    );
    _aggregationRoute(
      abi.encodeWithSignature('getAllMarketsDataForHooksTemplate(address)', template)
    );
    _aggregationRoute(
      abi.encodeWithSignature(
        'getAllMarketsDataForHooksTemplate(address,address)',
        factory,
        template
      )
    );
    _aggregationRoute(
      abi.encodeWithSignature('getAllMarketsDataV2ForHooksTemplate(address)', template)
    );
    _aggregationRoute(
      abi.encodeWithSignature(
        'getAllMarketsDataV2ForHooksTemplate(address,address)',
        factory,
        template
      )
    );
    _aggregationRoute(
      abi.encodeWithSignature('getAggregatedAllMarketsDataForHooksTemplate(address)', template)
    );
    _aggregationRoute(
      abi.encodeWithSignature('getAggregatedAllMarketsDataV2ForHooksTemplate(address)', template)
    );
  }

  function test_coreAndLiveRoutes_AreComplete() external view {
    address lender = address(0x1EAD);
    address market = address(0xAA4);
    address token = address(0x70AE);
    address[] memory addresses = new address[](1);
    addresses[0] = market;
    uint32[] memory expiries = new uint32[](1);
    expiries[0] = 123;
    LenderAccountQuery memory query = LenderAccountQuery(lender, market, expiries);
    LenderAccountQuery[] memory queries = new LenderAccountQuery[](1);
    queries[0] = query;

    _coreRoute(abi.encodeWithSignature('getTokenInfo(address)', token));
    _coreRoute(abi.encodeWithSignature('getTokensInfo(address[])', addresses));
    _coreRoute(abi.encodeWithSignature('getMarketData(address)', market));
    _coreRoute(abi.encodeWithSignature('getMarketsData(address[])', addresses));
    _coreRoute(abi.encodeWithSignature('getMarketDataV2(address)', market));
    _coreRoute(abi.encodeWithSignature('getMarketsDataV2(address[])', addresses));
    _coreRoute(
      abi.encodeWithSignature('getMarketDataWithLenderStatus(address,address)', lender, market)
    );
    _coreRoute(
      abi.encodeWithSignature(
        'getMarketsDataWithLenderStatus(address,address[])',
        lender,
        addresses
      )
    );
    _coreRoute(abi.encodeWithSignature('getLenderAccountData(address,address)', lender, market));
    _coreRoute(
      abi.encodeWithSignature('getLenderAccountData(address,address[])', lender, addresses)
    );
    _coreRoute(
      abi.encodeWithSignature('getLenderAccountsData(address,address[])', market, addresses)
    );
    _coreRoute(abi.encodeWithSignature('queryLenderAccount((address,address,uint32[]))', query));
    _coreRoute(
      abi.encodeWithSignature('queryLenderAccounts((address,address,uint32[])[])', queries)
    );
    _coreRoute(
      abi.encodeWithSignature('getWithdrawalBatchData(address,uint32)', market, uint32(123))
    );
    _coreRoute(
      abi.encodeWithSignature('getWithdrawalBatchesData(address,uint32[])', market, expiries)
    );
    _coreRoute(
      abi.encodeWithSignature(
        'getWithdrawalBatchesDataWithLenderStatus(address,uint32[],address)',
        market,
        expiries,
        lender
      )
    );
    _coreRoute(
      abi.encodeWithSignature(
        'getWithdrawalBatchDataWithLenderStatus(address,uint32,address)',
        market,
        uint32(123),
        lender
      )
    );
    _coreRoute(
      abi.encodeWithSignature(
        'getWithdrawalBatchDataWithLendersStatus(address,uint32,address[])',
        market,
        uint32(123),
        addresses
      )
    );

    _assertRoute(
      abi.encodeWithSignature('getMarketsLiveDataV2(address[])', addresses),
      LiveResponse
    );
    _assertRoute(
      abi.encodeWithSignature(
        'getMarketsLiveDataWithLenderStatusV2(address,address[])',
        lender,
        addresses
      ),
      LiveResponse
    );
  }

  function test_delegate_BubblesExactHelperRevert() external {
    address revertingCore = _deployCode(
      'test-next/mocks/LensMocks.sol:LensDelegateTargetMock',
      abi.encode(uint256(0), true)
    );
    MarketLens revertingLens = MarketLens(
      _deployCode(
        'src/lens/MarketLens.sol:MarketLens',
        abi.encode(address(0), address(0), revertingCore, address(0), address(0))
      )
    );

    vm.expectRevert(LensDelegateTargetMock.DelegatedCallFailed.selector);
    revertingLens.getTokenInfo(address(0));
  }

  function test_getMarketData_BubblesCanonicalNotV2MarketError() external {
    MarketLensCore core = MarketLensCore(
      _deployCode('src/lens/MarketLensCore.sol:MarketLensCore', abi.encode(address(0), address(0)))
    );
    MarketLens productionCoreLens = MarketLens(
      _deployCode(
        'src/lens/MarketLens.sol:MarketLens',
        abi.encode(address(0), address(0), address(core), address(0), address(0))
      )
    );
    LensV1MarketMock v1Market = LensV1MarketMock(
      _deployCode('test-next/mocks/LensMocks.sol:LensV1MarketMock', abi.encode(address(0)))
    );

    vm.expectRevert(MarketLens.NotV2Market.selector);
    productionCoreLens.getMarketData(address(v1Market));
  }

  function test_versionAndHooksKindProbes_HandleValidBoundaries() external {
    VersionStringMock v2 = _version('2.5.0');
    VersionStringMock v1 = _version('1.0.0');
    VersionStringMock empty = _version('');
    VersionStringMock openTerm = _version('OpenTermHooks');
    VersionStringMock fixedTerm = _version('FixedTermHooks');
    VersionStringMock periodicTerm = _version('PeriodicTermHooks');
    VersionStringMock unknown = _version('A hooks version deliberately longer than one word');

    assertTrue(probes.isV2Market(address(v2)), 'v2');
    assertFalse(probes.isV2Market(address(v1)), 'v1');
    assertFalse(probes.isV2Market(address(empty)), 'empty');
    assertEq(uint256(probes.hooksKind(address(openTerm))), uint256(HooksInstanceKind.OpenTerm));
    assertEq(
      uint256(probes.hooksKind(address(fixedTerm))),
      uint256(HooksInstanceKind.FixedTermLoan)
    );
    assertEq(
      uint256(probes.hooksKind(address(periodicTerm))),
      uint256(HooksInstanceKind.PeriodicTerm)
    );
    assertEq(uint256(probes.hooksKind(address(empty))), uint256(HooksInstanceKind.Unknown));
    assertEq(uint256(probes.hooksKind(address(unknown))), uint256(HooksInstanceKind.Unknown));
  }

  function test_versionAndHooksKindProbes_RejectMalformedDataAndBubbleReverts() external {
    for (uint256 i; i < 3; i++) {
      address malformed = _deployCode(
        'test-next/mocks/LensMocks.sol:MalformedVersionMock',
        abi.encode(MalformedVersionMock.Shape(i))
      );
      vm.expectRevert();
      probes.isV2Market(malformed);
      vm.expectRevert();
      probes.hooksKind(malformed);
    }

    RevertingVersionMock revertingTarget = RevertingVersionMock(
      _deployCode('test-next/mocks/LensMocks.sol:RevertingVersionMock')
    );
    vm.expectRevert(RevertingVersionMock.VersionReadFailed.selector);
    probes.isV2Market(address(revertingTarget));
    vm.expectRevert(RevertingVersionMock.VersionReadFailed.selector);
    probes.hooksKind(address(revertingTarget));
  }

  function test_optionalUintProbe_DistinguishesPresenceFromFallback() external {
    bytes4 selector = bytes4(keccak256('optionalValue()'));
    OptionalUintTargetMock zero = _optionalTarget(0, OptionalUintTargetMock.Shape.Word);
    OptionalUintTargetMock value = _optionalTarget(42, OptionalUintTargetMock.Shape.Long);
    OptionalUintTargetMock short = _optionalTarget(42, OptionalUintTargetMock.Shape.Short);
    OptionalUintTargetMock revertingTarget = _optionalTarget(
      42,
      OptionalUintTargetMock.Shape.Revert
    );

    (bool present, uint256 result) = _optionalResult(address(zero), selector);
    assertTrue(present, 'zero present');
    assertEq(result, 0, 'zero value');
    (present, result) = _optionalResult(address(value), selector);
    assertTrue(present, 'long present');
    assertEq(result, 42, 'long value');
    (present, result) = _optionalResult(address(short), selector);
    assertFalse(present, 'short absent');
    assertEq(result, 0, 'short value');
    (present, result) = _optionalResult(address(revertingTarget), selector);
    assertFalse(present, 'revert absent');
    assertEq(result, 0, 'revert value');
  }

  function test_hooksConfigData_MapsEveryFlag() external view {
    HooksConfig config = EmptyHooksConfig;
    config = config.setFlag(Bit_Enabled_Deposit);
    config = config.setFlag(Bit_Enabled_QueueWithdrawal);
    config = config.setFlag(Bit_Enabled_ExecuteWithdrawal);
    config = config.setFlag(Bit_Enabled_Transfer);
    config = config.setFlag(Bit_Enabled_Borrow);
    config = config.setFlag(Bit_Enabled_Repay);
    config = config.setFlag(Bit_Enabled_CloseMarket);
    config = config.setFlag(Bit_Enabled_NukeFromOrbit);
    config = config.setFlag(Bit_Enabled_SetMaxTotalSupply);
    config = config.setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips);
    config = config.setFlag(Bit_Enabled_SetProtocolFeeBips);
    config = config.setFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction);

    HooksConfigData memory data = probes.decodeFlags(config);
    assertTrue(data.useOnDeposit, 'deposit');
    assertTrue(data.useOnQueueWithdrawal, 'queue');
    assertTrue(data.useOnExecuteWithdrawal, 'execute');
    assertTrue(data.useOnTransfer, 'transfer');
    assertTrue(data.useOnBorrow, 'borrow');
    assertTrue(data.useOnRepay, 'repay');
    assertTrue(data.useOnCloseMarket, 'close');
    assertTrue(data.useOnNukeFromOrbit, 'nuke');
    assertTrue(data.useOnSetMaxTotalSupply, 'max supply');
    assertTrue(data.useOnSetAnnualInterestAndReserveRatioBips, 'apr');
    assertTrue(data.useOnSetProtocolFeeBips, 'protocol fee');
    assertTrue(data.useOnExecutePendingAnnualInterestBipsReduction, 'pending apr');
  }

  function _version(string memory version) internal returns (VersionStringMock target) {
    target = VersionStringMock(
      _deployCode('test-next/mocks/LensMocks.sol:VersionStringMock', abi.encode(version))
    );
  }

  function _optionalTarget(
    uint256 value,
    OptionalUintTargetMock.Shape shape
  ) internal returns (OptionalUintTargetMock target) {
    target = OptionalUintTargetMock(
      _deployCode('test-next/mocks/LensMocks.sol:OptionalUintTargetMock', abi.encode(value, shape))
    );
  }

  function _optionalResult(
    address target,
    bytes4 selector
  ) internal view returns (bool present, uint256 value) {
    OptionalUintDataV2_5 memory data = probes.optionalUint(target, selector);
    return (data.isPresent, data.value);
  }
}
