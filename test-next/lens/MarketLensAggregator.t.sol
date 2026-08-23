// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { FactoryScopedHooksTemplateData } from 'src/lens/FactoryScopedHooksTemplateData.sol';
import { HooksDataForBorrower } from 'src/lens/HooksDataForBorrower.sol';
import { HooksInstanceData } from 'src/lens/HooksInstanceData.sol';
import { HooksTemplateData } from 'src/lens/HooksTemplateData.sol';
import { MarketData, MarketDataV2_5 } from 'src/lens/MarketData.sol';
import { MarketLensAggregator } from 'src/lens/MarketLensAggregator.sol';
import { LensArchControllerMock, LensFactoryMock, LensHooksMock } from '../mocks/LensMocks.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

contract MarketLensAggregatorTest is MarketFixture {
  address internal constant TemplateA = address(0xA100);
  address internal constant SharedTemplate = address(0xA200);
  address internal constant TemplateB = address(0xB100);
  address internal constant PendingAdministrator = address(0xAD011);

  Fixture internal standard;
  Fixture internal revolving;
  LensArchControllerMock internal archController;
  LensFactoryMock internal factoryA;
  LensFactoryMock internal factoryB;
  LensFactoryMock internal revertingFactory;
  LensHooksMock internal hooksA;
  LensHooksMock internal sharedHooks;
  LensHooksMock internal hooksB;
  address internal nonHooksController;
  MarketLensAggregator internal aggregator;

  function setUp() external {
    standard = _newMarket(HooksKind.OpenTerm);
    revolving = _newRevolvingMarket(HooksKind.OpenTerm);
    archController = LensArchControllerMock(
      _deployCode('test-next/mocks/LensMocks.sol:LensArchControllerMock')
    );
    factoryA = _newFactory();
    factoryB = _newFactory();
    revertingFactory = _newFactory();
    hooksA = _newHooks(address(0xA1));
    sharedHooks = _newHooks(PendingAdministrator);
    hooksB = _newHooks(address(0xB1));
    nonHooksController = _deployCode('test-next/mocks/LensMocks.sol:LensNonHooksControllerMock');

    _configureFactories();
    address[] memory controllers = new address[](4);
    controllers[0] = nonHooksController;
    controllers[1] = address(factoryA);
    controllers[2] = address(factoryB);
    controllers[3] = address(revertingFactory);
    archController.setControllers(controllers);
    archController.setRegisteredBorrower(Borrower, true);
    aggregator = _newAggregator(address(archController), address(factoryA));

    standard.asset.mint(Borrower, 5e18);
    vm.startPrank(Borrower);
    standard.asset.approve(address(factoryA), 3e18);
    standard.asset.approve(address(factoryB), 4e18);
    vm.stopPrank();
  }

  function _newFactory() internal returns (LensFactoryMock factory) {
    factory = LensFactoryMock(_deployCode('test-next/mocks/LensMocks.sol:LensFactoryMock'));
  }

  function _newHooks(address pendingAdministrator) internal returns (LensHooksMock hooks) {
    hooks = LensHooksMock(
      _deployCode('test-next/mocks/LensMocks.sol:LensHooksMock', abi.encode(pendingAdministrator))
    );
  }

  function _newAggregator(
    address controller,
    address defaultFactory
  ) internal returns (MarketLensAggregator lens) {
    lens = MarketLensAggregator(
      _deployCode(
        'src/lens/MarketLensAggregator.sol:MarketLensAggregator',
        abi.encode(controller, defaultFactory)
      )
    );
  }

  function _configureFactories() internal {
    address[] memory templatesA = new address[](2);
    templatesA[0] = TemplateA;
    templatesA[1] = SharedTemplate;
    factoryA.setTemplates(templatesA);
    address[] memory templatesB = new address[](2);
    templatesB[0] = SharedTemplate;
    templatesB[1] = TemplateB;
    factoryB.setTemplates(templatesB);

    address[] memory instancesA = new address[](2);
    instancesA[0] = address(hooksA);
    instancesA[1] = address(sharedHooks);
    factoryA.setInstances(instancesA);
    address[] memory instancesB = new address[](2);
    instancesB[0] = address(sharedHooks);
    instancesB[1] = address(hooksB);
    factoryB.setInstances(instancesB);

    _setTemplate(factoryA, TemplateA, 'Template A', 0, 101);
    _setTemplate(factoryA, SharedTemplate, 'Shared A', 1, 102);
    _setTemplate(factoryB, SharedTemplate, 'Shared B', 0, 202);
    _setTemplate(factoryB, TemplateB, 'Template B', 1, 203);
    factoryA.setInstanceTemplate(address(hooksA), TemplateA);
    factoryA.setInstanceTemplate(address(sharedHooks), SharedTemplate);
    factoryB.setInstanceTemplate(address(sharedHooks), SharedTemplate);
    factoryB.setInstanceTemplate(address(hooksB), TemplateB);

    address[] memory oneMarket = new address[](1);
    oneMarket[0] = address(standard.market);
    factoryA.setMarkets(SharedTemplate, oneMarket);
    address[] memory twoMarkets = new address[](2);
    twoMarkets[0] = address(standard.market);
    twoMarkets[1] = address(revolving.market);
    factoryB.setMarkets(SharedTemplate, twoMarkets);
    revertingFactory.setReverts(false, true, true, true);
  }

  function _setTemplate(
    LensFactoryMock factory,
    address template,
    string memory name,
    uint24 index,
    uint16 protocolFeeBips
  ) internal {
    factory.setTemplateDetails(
      template,
      name,
      index,
      protocolFeeBips,
      address(uint160(protocolFeeBips)),
      address(standard.asset),
      1e18
    );
  }

  function test_directAndFactoryParameterizedReads_PreserveScopeAndFeeData() external view {
    HooksDataForBorrower memory defaults = aggregator.getHooksDataForBorrower(Borrower);
    assertEq(defaults.borrower, Borrower, 'borrower');
    assertTrue(defaults.isRegisteredBorrower, 'registered');
    assertEq(defaults.hooksTemplates.length, 2, 'default templates');
    assertEq(defaults.hooksInstances.length, 2, 'default instances');
    _assertTemplate(defaults.hooksTemplates[0], TemplateA, 'Template A', 101, address(factoryA));
    _assertInstance(defaults.hooksInstances[1], address(sharedHooks), SharedTemplate, 102);
    assertEq(aggregator.getHooksInstancesForBorrower(Borrower).length, 2, 'default instance alias');
    assertEq(
      aggregator.getHooksInstancesForBorrower(address(factoryB), Borrower).length,
      2,
      'factory instance alias'
    );

    HooksDataForBorrower memory second = aggregator.getHooksDataForBorrower(
      address(factoryB),
      Borrower
    );
    assertEq(second.hooksTemplates.length, 2, 'second templates');
    assertEq(second.hooksInstances.length, 2, 'second instances');
    _assertTemplate(second.hooksTemplates[0], SharedTemplate, 'Shared B', 202, address(factoryB));
    _assertInstance(second.hooksInstances[1], address(hooksB), TemplateB, 203);

    _assertTemplate(
      aggregator.getHooksTemplateForBorrower(Borrower, TemplateA),
      TemplateA,
      'Template A',
      101,
      address(factoryA)
    );
    HooksTemplateData memory template = aggregator.getHooksTemplateForBorrower(
      address(factoryB),
      Borrower,
      TemplateB
    );
    _assertTemplate(template, TemplateB, 'Template B', 203, address(factoryB));
    address[] memory templates = new address[](2);
    templates[0] = TemplateB;
    templates[1] = SharedTemplate;
    HooksTemplateData[] memory selected = aggregator.getHooksTemplatesForBorrower(
      address(factoryB),
      Borrower,
      templates
    );
    assertEq(selected.length, 2, 'selected templates');
    assertEq(selected[0].hooksTemplate, TemplateB, 'selected order 0');
    assertEq(selected[1].hooksTemplate, SharedTemplate, 'selected order 1');
    assertEq(
      aggregator.getHooksTemplatesForBorrower(Borrower, templates).length,
      2,
      'default selected alias'
    );
    assertEq(aggregator.getAllHooksTemplatesForBorrower(Borrower).length, 2, 'default all alias');
    assertEq(
      aggregator.getAllHooksTemplatesForBorrower(address(factoryB), Borrower).length,
      2,
      'factory all alias'
    );
  }

  function test_activeFactories_FilterControllersAndAppendValidDefault() external {
    address[] memory active = aggregator.getActiveHooksFactories();
    assertEq(active.length, 3, 'active count');
    assertEq(active[0], address(factoryA), 'active A');
    assertEq(active[1], address(factoryB), 'active B');
    assertEq(active[2], address(revertingFactory), 'active reverting');

    LensFactoryMock appendedFactory = _newFactory();
    address[] memory controllers = new address[](2);
    controllers[0] = nonHooksController;
    controllers[1] = address(factoryB);
    archController.setControllers(controllers);
    MarketLensAggregator appended = _newAggregator(
      address(archController),
      address(appendedFactory)
    );
    active = appended.getActiveHooksFactories();
    assertEq(active.length, 2, 'appended count');
    assertEq(active[0], address(factoryB), 'controller first');
    assertEq(active[1], address(appendedFactory), 'default appended');

    controllers = new address[](0);
    archController.setControllers(controllers);
    MarketLensAggregator empty = _newAggregator(address(archController), nonHooksController);
    assertEq(empty.getActiveHooksFactories().length, 0, 'invalid default ignored');
    assertEq(
      empty.getAggregatedHooksTemplatesForBorrowerWithFactory(Borrower).length,
      0,
      'empty scoped templates'
    );
    assertEq(
      empty.getAggregatedMarketsForHooksTemplateCount(SharedTemplate),
      0,
      'empty aggregate markets'
    );

    controllers = new address[](1);
    controllers[0] = address(factoryA);
    archController.setControllers(controllers);
    MarketLensAggregator single = _newAggregator(address(archController), address(factoryA));
    assertEq(
      single.getAggregatedMarketsForHooksTemplateCount(SharedTemplate),
      1,
      'single aggregate markets'
    );

    controllers[0] = address(revertingFactory);
    archController.setControllers(controllers);
    MarketLensAggregator reverting = _newAggregator(
      address(archController),
      address(revertingFactory)
    );
    assertEq(
      reverting.getAggregatedMarketsForHooksTemplateCount(SharedTemplate),
      0,
      'reverting aggregate markets'
    );
  }

  function test_aggregationHelpers_DedupeFirstSeenAndIsolateFactoryFailures() external view {
    address[] memory none = new address[](0);
    assertEq(
      aggregator.getAggregatedHooksInstancesForBorrowerWithFactories(Borrower, none).length,
      0,
      'empty instances'
    );
    assertEq(
      aggregator.getAggregatedAllHooksTemplatesForBorrowerWithFactories(Borrower, none).length,
      0,
      'empty templates'
    );

    address[] memory one = new address[](1);
    one[0] = address(factoryA);
    assertEq(
      aggregator.getAggregatedHooksInstancesForBorrowerWithFactories(Borrower, one).length,
      2,
      'single instances'
    );
    assertEq(
      aggregator.getAggregatedAllHooksTemplatesForBorrowerWithFactories(Borrower, one).length,
      2,
      'single templates'
    );
    one[0] = address(revertingFactory);
    assertEq(
      aggregator.getAggregatedHooksInstancesForBorrowerWithFactories(Borrower, one).length,
      0,
      'reverting single instances'
    );
    assertEq(
      aggregator.getAggregatedAllHooksTemplatesForBorrowerWithFactories(Borrower, one).length,
      0,
      'reverting single templates'
    );

    address[] memory factories = new address[](3);
    factories[0] = address(factoryA);
    factories[1] = address(factoryB);
    factories[2] = address(revertingFactory);
    HooksInstanceData[] memory instances = aggregator
      .getAggregatedHooksInstancesForBorrowerWithFactories(Borrower, factories);
    assertEq(instances.length, 3, 'deduped instances');
    assertEq(instances[0].hooksAddress, address(hooksA), 'instance 0');
    assertEq(instances[1].hooksAddress, address(sharedHooks), 'instance 1');
    assertEq(instances[2].hooksAddress, address(hooksB), 'instance 2');
    assertEq(instances[1].hooksTemplate.name, 'Shared A', 'first instance wins');

    HooksTemplateData[] memory templates = aggregator
      .getAggregatedAllHooksTemplatesForBorrowerWithFactories(Borrower, factories);
    assertEq(templates.length, 3, 'deduped templates');
    assertEq(templates[0].hooksTemplate, TemplateA, 'template 0');
    assertEq(templates[1].hooksTemplate, SharedTemplate, 'template 1');
    assertEq(templates[2].hooksTemplate, TemplateB, 'template 2');
    assertEq(templates[1].name, 'Shared A', 'first template wins');
  }

  function test_discoveredAggregation_ReturnsUnifiedAndFactoryScopedViews() external view {
    HooksDataForBorrower memory data = aggregator.getAggregatedHooksDataForBorrower(Borrower);
    assertEq(data.borrower, Borrower, 'borrower');
    assertTrue(data.isRegisteredBorrower, 'registered');
    assertEq(data.hooksInstances.length, 3, 'instances');
    assertEq(data.hooksTemplates.length, 3, 'templates');
    assertEq(
      aggregator.getAggregatedHooksInstancesForBorrower(Borrower).length,
      3,
      'instance facade'
    );
    assertEq(
      aggregator.getAggregatedAllHooksTemplatesForBorrower(Borrower).length,
      3,
      'template facade'
    );

    FactoryScopedHooksTemplateData[] memory scoped = aggregator
      .getAggregatedHooksTemplatesForBorrowerWithFactory(Borrower);
    assertEq(scoped.length, 4, 'scoped count');
    assertEq(scoped[0].hooksFactory, address(factoryA), 'scope 0 factory');
    assertEq(scoped[1].hooksTemplateData.name, 'Shared A', 'scope 1 data');
    assertEq(scoped[2].hooksFactory, address(factoryB), 'scope 2 factory');
    assertEq(scoped[2].hooksTemplateData.name, 'Shared B', 'scope 2 data');
    assertEq(scoped[3].hooksTemplateData.name, 'Template B', 'scope 3 data');
  }

  function test_directMarketReads_RespectFactoryAndPagination() external view {
    assertEq(aggregator.getMarketsForHooksTemplateCount(SharedTemplate), 1, 'default count');
    assertEq(
      aggregator.getMarketsForHooksTemplateCount(address(factoryB), SharedTemplate),
      2,
      'factory count'
    );
    MarketData[] memory defaultMarkets = aggregator.getAllMarketsDataForHooksTemplate(
      SharedTemplate
    );
    assertEq(defaultMarkets.length, 1, 'default markets');
    assertEq(defaultMarkets[0].marketToken.token, address(standard.market), 'default market');
    assertEq(
      aggregator.getAllMarketsDataForHooksTemplate(address(factoryB), SharedTemplate).length,
      2,
      'factory legacy markets'
    );

    MarketDataV2_5[] memory factoryMarkets = aggregator.getAllMarketsDataV2ForHooksTemplate(
      address(factoryB),
      SharedTemplate
    );
    assertEq(factoryMarkets.length, 2, 'factory markets');
    assertFalse(factoryMarkets[0].commitmentFeeBips.isPresent, 'standard shape');
    assertTrue(factoryMarkets[1].commitmentFeeBips.isPresent, 'revolving shape');
    assertEq(
      aggregator.getAllMarketsDataV2ForHooksTemplate(SharedTemplate).length,
      1,
      'default v2 markets'
    );

    MarketData[] memory legacyPage = aggregator.getPaginatedMarketsDataForHooksTemplate(
      address(factoryB),
      SharedTemplate,
      1,
      2
    );
    assertEq(legacyPage.length, 1, 'legacy page length');
    assertEq(legacyPage[0].marketToken.token, address(revolving.market), 'legacy page market');
    assertEq(
      aggregator.getPaginatedMarketsDataForHooksTemplate(SharedTemplate, 0, 1).length,
      1,
      'default legacy page'
    );
    assertEq(
      aggregator.getPaginatedMarketsDataV2ForHooksTemplate(SharedTemplate, 0, 1).length,
      1,
      'default v2 page'
    );

    MarketDataV2_5[] memory page = aggregator.getPaginatedMarketsDataV2ForHooksTemplate(
      address(factoryB),
      SharedTemplate,
      1,
      2
    );
    assertEq(page.length, 1, 'page length');
    assertEq(page[0].market.marketToken.token, address(revolving.market), 'page market');
  }

  function test_aggregatedMarketReads_DedupeStableOrderAndSkipReverts() external view {
    assertEq(
      aggregator.getAggregatedMarketsForHooksTemplateCount(SharedTemplate),
      2,
      'aggregate count'
    );
    MarketData[] memory legacy = aggregator.getAggregatedAllMarketsDataForHooksTemplate(
      SharedTemplate
    );
    assertEq(legacy.length, 2, 'legacy length');
    assertEq(legacy[0].marketToken.token, address(standard.market), 'legacy 0');
    assertEq(legacy[1].marketToken.token, address(revolving.market), 'legacy 1');

    MarketDataV2_5[] memory v2 = aggregator.getAggregatedAllMarketsDataV2ForHooksTemplate(
      SharedTemplate
    );
    assertEq(v2.length, 2, 'v2 length');
    assertEq(v2[0].market.marketToken.token, address(standard.market), 'v2 0');
    assertEq(v2[1].market.marketToken.token, address(revolving.market), 'v2 1');
    assertTrue(v2[1].commitmentFeeBips.isPresent, 'v2 revolving');
  }

  function test_templateWideMarketReads_AcceptBytes32UnderlyingMetadata() external {
    vm.mockCall(
      address(standard.asset),
      abi.encodeWithSignature('name()'),
      abi.encode(bytes32('Legacy Token'))
    );
    vm.mockCall(
      address(standard.asset),
      abi.encodeWithSignature('symbol()'),
      abi.encode(bytes32('LEGACY'))
    );

    MarketData[] memory factoryMarkets = aggregator.getAllMarketsDataForHooksTemplate(
      address(factoryB),
      SharedTemplate
    );
    assertEq(factoryMarkets.length, 2, 'factory markets');
    assertEq(factoryMarkets[0].underlyingToken.name, 'Legacy Token', 'bytes32 name');
    assertEq(factoryMarkets[1].underlyingToken.name, 'Token', 'string name');

    MarketDataV2_5[] memory aggregated = aggregator.getAggregatedAllMarketsDataV2ForHooksTemplate(
      SharedTemplate
    );
    assertEq(aggregated.length, 2, 'aggregated markets');
    assertEq(aggregated[0].market.underlyingToken.symbol, 'LEGACY', 'bytes32 symbol');
    assertEq(aggregated[1].market.underlyingToken.symbol, 'TKN', 'string symbol');
  }

  function _assertTemplate(
    HooksTemplateData memory data,
    address template,
    string memory name,
    uint16 protocolFeeBips,
    address factory
  ) internal view {
    assertEq(data.hooksTemplate, template, 'template');
    assertTrue(data.exists, 'exists');
    assertTrue(data.enabled, 'enabled');
    assertEq(data.name, name, 'name');
    assertEq(data.fees.protocolFeeBips, protocolFeeBips, 'protocol fee');
    assertEq(data.fees.originationFeeToken.token, address(standard.asset), 'fee asset');
    assertEq(data.fees.originationFeeAmount, 1e18, 'origination fee');
    assertEq(data.fees.borrowerOriginationFeeBalance, 5e18, 'fee balance');
    uint256 expectedApproval = factory == address(factoryA) ? 3e18 : 4e18;
    assertEq(data.fees.borrowerOriginationFeeApproval, expectedApproval, 'fee approval');
  }

  function _assertInstance(
    HooksInstanceData memory data,
    address hooks,
    address template,
    uint16 protocolFeeBips
  ) internal view {
    assertEq(data.hooksAddress, hooks, 'hooks');
    assertEq(data.administrator, Borrower, 'administrator');
    if (hooks == address(sharedHooks)) {
      assertEq(data.pendingAdministrator, PendingAdministrator, 'pending administrator');
    }
    assertEq(data.hooksTemplate.hooksTemplate, template, 'instance template');
    assertEq(data.hooksTemplate.fees.protocolFeeBips, protocolFeeBips, 'instance fee');
    assertEq(data.totalMarkets, 1, 'instance markets');
  }
}
