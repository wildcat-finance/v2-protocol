// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import 'forge-std/Test.sol';
import 'src/WildcatArchController.sol';
import 'src/HooksFactory.sol';
import 'src/IHooksFactory.sol';
import 'src/libraries/LibStoredInitCode.sol';
import { MockERC20, ERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import './helpers/Assertions.sol';
import './shared/mocks/MockHooks.sol';
import './helpers/StandardStructs.sol';
import 'src/market/WildcatMarket.sol';

// @todo test removal

struct FuzzFeeConfigurationInputs {
  address feeRecipient;
  bool useOriginationFeeAsset;
  address originationFeeAsset;
  uint80 originationFeeAmount;
  uint16 protocolFeeBips;
}

struct FuzzDeployMarketInputs {
  // Market config
  uint128 maxTotalSupply;
  uint16 annualInterestBips;
  uint16 delinquencyFeeBips;
  uint32 withdrawalBatchDuration;
  uint16 reserveRatioBips;
  uint32 delinquencyGracePeriod;
  // Hooks config
  StandardHooksConfig marketHooksConfig;
  StandardHooksConfig templateHooksConfig;
}

contract HooksFactoryTest is Test, Assertions {
  WildcatArchController archController;
  IHooksFactory hooksFactory;
  address hooksTemplate;

  address internal constant nullAddress = address(0);
  MockERC20 internal feeToken = new MockERC20('Token', 'TKN', 18);
  MockERC20 internal underlying = new MockERC20('Market', 'MKT', 18);
  address internal constant sanctionsSentinel = address(1);

  function _storeMarketInitCode()
    internal
    virtual
    returns (address initCodeStorage, uint256 initCodeHash)
  {
    bytes memory marketInitCode = type(WildcatMarket).creationCode;
    initCodeHash = uint256(keccak256(marketInitCode));
    initCodeStorage = LibStoredInitCode.deployInitCode(marketInitCode);
  }

  /*   function _constrainValidFeeConfiguration(
    address _feeRecipient,
    address _originationFeeAsset,
    uint80 _originationFeeAmount,
    uint16 _protocolFeeBips
  )
    internal
    view
    returns (
      address feeRecipient,
      address originationFeeAsset,
      uint80 originationFeeAmount,
      uint16 protocolFeeBips
    )
  {
    bool hasFeeRecipient = _feeRecipient != nullAddress;
    bool canHaveOriginationFee = _originationFeeAsset != nullAddress && hasFeeRecipient;
    feeRecipient = _feeRecipient;
    originationFeeAsset = _originationFeeAsset;
    protocolFeeBips = uint16(bound(_protocolFeeBips, 0, hasFeeRecipient ? 10_000 : 0));
    originationFeeAmount = uint80(
      bound(_originationFeeAmount, 0, canHaveOriginationFee ? type(uint80).max : 0)
    );
  } */

  modifier constrain(FuzzFeeConfigurationInputs memory input) {
    bool hasFeeRecipient = input.feeRecipient != nullAddress;
    if (input.useOriginationFeeAsset) {
      input.originationFeeAsset = address(feeToken);
    } else {
      input.originationFeeAsset = nullAddress;
    }
    bool canHaveOriginationFee = input.originationFeeAsset != nullAddress && hasFeeRecipient;
    uint maxProtocolFee = hasFeeRecipient ? 10_000 : 0;
    input.protocolFeeBips = uint16(bound(input.protocolFeeBips, 0, maxProtocolFee));
    input.originationFeeAmount = uint80(
      bound(input.originationFeeAmount, 0, canHaveOriginationFee ? type(uint80).max : 0)
    );
    _;
  }

  function setUp() public {
    archController = new WildcatArchController();

    (address marketTemplate, uint256 marketInitCodeHash) = _storeMarketInitCode();
    hooksFactory = new HooksFactory(
      address(archController),
      sanctionsSentinel,
      marketTemplate,
      marketInitCodeHash
    );
    hooksTemplate = LibStoredInitCode.deployInitCode(type(MockHooks).creationCode);
    archController.registerControllerFactory(address(hooksFactory));
    hooksFactory.registerWithArchController();
  }

  // ========================================================================== //
  //                              addHooksTemplate                              //
  // ========================================================================== //

  function test_addHooksTemplate(
    FuzzFeeConfigurationInputs memory feesInput
  ) external constrain(feesInput) {
    vm.expectEmit(address(hooksFactory));
    string memory name = 'name';
    emit IHooksFactoryEventsAndErrors.HooksTemplateAdded(
      hooksTemplate,
      name,
      feesInput.feeRecipient,
      feesInput.originationFeeAsset,
      feesInput.originationFeeAmount,
      feesInput.protocolFeeBips
    );
    hooksFactory.addHooksTemplate(
      hooksTemplate,
      name,
      feesInput.feeRecipient,
      feesInput.originationFeeAsset,
      feesInput.originationFeeAmount,
      feesInput.protocolFeeBips
    );
    address[] memory hooksTemplates = hooksFactory.getHooksTemplates();
    assertEq(hooksTemplates.length, 1);
    assertEq(hooksTemplates[0], hooksTemplate);
    HooksTemplate memory template = hooksFactory.getHooksTemplateDetails(hooksTemplate);
    assertEq(
      template,
      HooksTemplate({
        exists: true,
        enabled: true,
        index: 0,
        name: name,
        feeRecipient: feesInput.feeRecipient,
        originationFeeAsset: feesInput.originationFeeAsset,
        originationFeeAmount: feesInput.originationFeeAmount,
        protocolFeeBips: feesInput.protocolFeeBips
      })
    );
  }

  function test_addHooksTemplate_CallerNotArchControllerOwner(
    FuzzFeeConfigurationInputs memory feesInput
  ) external {
    vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
    vm.prank(address(1));
    string memory name = 'name';
    hooksFactory.addHooksTemplate(
      hooksTemplate,
      name,
      feesInput.feeRecipient,
      feesInput.originationFeeAsset,
      feesInput.originationFeeAmount,
      feesInput.protocolFeeBips
    );
  }

  function test_addHooksTemplate_HooksTemplateAlreadyExists(
    FuzzFeeConfigurationInputs memory feesInput
  ) external constrain(feesInput) {
    string memory name = 'name';
    hooksFactory.addHooksTemplate(
      hooksTemplate,
      name,
      feesInput.feeRecipient,
      feesInput.originationFeeAsset,
      feesInput.originationFeeAmount,
      feesInput.protocolFeeBips
    );
    vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateAlreadyExists.selector);
    hooksFactory.addHooksTemplate(
      hooksTemplate,
      name,
      feesInput.feeRecipient,
      feesInput.originationFeeAsset,
      feesInput.originationFeeAmount,
      feesInput.protocolFeeBips
    );
  }

  function test_addHooksTemplate_InvalidFeeConfiguration() external {
    address notNullFeeRecipient = address(1);
    string memory name = 'name';

    vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
    hooksFactory.addHooksTemplate(hooksTemplate, name, nullAddress, nullAddress, 0, 1);

    vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
    hooksFactory.addHooksTemplate(hooksTemplate, name, nullAddress, nullAddress, 1, 0);

    vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
    hooksFactory.addHooksTemplate(hooksTemplate, name, nullAddress, notNullFeeRecipient, 1, 0);

    vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
    hooksFactory.addHooksTemplate(hooksTemplate, name, nullAddress, nullAddress, 0, 10001);
  }

  // ========================================================================== //
  //                           updateHooksTemplateFees                          //
  // ========================================================================== //

  function test_updateHooksTemplateFees(
    FuzzFeeConfigurationInputs memory feesInput
  ) external constrain(feesInput) {
    string memory name = 'name';
    hooksFactory.addHooksTemplate(hooksTemplate, name, address(0), address(0), 0, 0);

    vm.expectEmit(address(hooksFactory));
    emit IHooksFactoryEventsAndErrors.HooksTemplateFeesUpdated(
      hooksTemplate,
      feesInput.feeRecipient,
      feesInput.originationFeeAsset,
      feesInput.originationFeeAmount,
      feesInput.protocolFeeBips
    );

    hooksFactory.updateHooksTemplateFees(
      hooksTemplate,
      feesInput.feeRecipient,
      feesInput.originationFeeAsset,
      feesInput.originationFeeAmount,
      feesInput.protocolFeeBips
    );
    HooksTemplate memory template = hooksFactory.getHooksTemplateDetails(hooksTemplate);
    assertEq(
      template,
      HooksTemplate({
        exists: true,
        enabled: true,
        index: 0,
        name: name,
        feeRecipient: feesInput.feeRecipient,
        originationFeeAsset: feesInput.originationFeeAsset,
        originationFeeAmount: feesInput.originationFeeAmount,
        protocolFeeBips: feesInput.protocolFeeBips
      })
    );
    assertTrue(hooksFactory.isHooksTemplate(hooksTemplate), '!isHooksTemplate');
  }

  function test_updateHooksTemplateFees_CallerNotArchControllerOwner(
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external {
    string memory name = 'name';
    hooksFactory.addHooksTemplate(hooksTemplate, name, nullAddress, nullAddress, 0, 0);

    vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
    vm.prank(address(1));
    hooksFactory.updateHooksTemplateFees(
      address(1),
      feeRecipient,
      originationFeeAsset,
      originationFeeAmount,
      protocolFeeBips
    );
  }

  function test_updateHooksTemplateFees_HooksTemplateNotFound(
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external {
    vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotFound.selector);
    hooksFactory.updateHooksTemplateFees(
      address(1),
      feeRecipient,
      originationFeeAsset,
      originationFeeAmount,
      protocolFeeBips
    );
  }

  function test_updateHooksTemplateFees_InvalidFeeConfiguration() external {
    address notNullFeeRecipient = address(1);
    string memory name = 'name';
    hooksFactory.addHooksTemplate(hooksTemplate, name, nullAddress, nullAddress, 0, 0);

    vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
    hooksFactory.updateHooksTemplateFees(hooksTemplate, nullAddress, nullAddress, 0, 1);

    vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
    hooksFactory.updateHooksTemplateFees(hooksTemplate, nullAddress, nullAddress, 1, 0);

    vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
    hooksFactory.updateHooksTemplateFees(hooksTemplate, nullAddress, notNullFeeRecipient, 1, 0);

    vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
    hooksFactory.updateHooksTemplateFees(hooksTemplate, nullAddress, nullAddress, 0, 10001);
  }

  // ========================================================================== //
  //                            disableHooksTemplate                            //
  // ========================================================================== //

  function test_disableHooksTemplate(
    FuzzFeeConfigurationInputs memory feesInput
  ) external constrain(feesInput) {
    hooksFactory.addHooksTemplate(
      hooksTemplate,
      'name',
      feesInput.feeRecipient,
      feesInput.originationFeeAsset,
      feesInput.originationFeeAmount,
      feesInput.protocolFeeBips
    );

    vm.expectEmit(address(hooksFactory));
    emit IHooksFactoryEventsAndErrors.HooksTemplateDisabled(hooksTemplate);

    hooksFactory.disableHooksTemplate(hooksTemplate);

    HooksTemplate memory template = hooksFactory.getHooksTemplateDetails(hooksTemplate);
    assertEq(
      template,
      HooksTemplate({
        exists: true,
        enabled: false,
        index: 0,
        name: 'name',
        feeRecipient: feesInput.feeRecipient,
        originationFeeAsset: feesInput.originationFeeAsset,
        originationFeeAmount: feesInput.originationFeeAmount,
        protocolFeeBips: feesInput.protocolFeeBips
      })
    );
  }

  function test_disableHooksTemplate_CallerNotArchControllerOwner(
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external {
    hooksFactory.addHooksTemplate(hooksTemplate, 'name', nullAddress, nullAddress, 0, 0);

    vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
    vm.prank(address(1));
    hooksFactory.disableHooksTemplate(hooksTemplate);
  }

  function test_disableHooksTemplate_HooksTemplateNotFound(
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external {
    vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotFound.selector);
    hooksFactory.disableHooksTemplate(hooksTemplate);
  }

  // ========================================================================== //
  //                             deployHooksInstance                            //
  // ========================================================================== //

  function test_deployHooksInstance(
    FuzzFeeConfigurationInputs memory feesInput
  ) external constrain(feesInput) {
    archController.registerBorrower(address(this));
    hooksFactory.addHooksTemplate(
      hooksTemplate,
      'name',
      feesInput.feeRecipient,
      feesInput.originationFeeAsset,
      feesInput.originationFeeAmount,
      feesInput.protocolFeeBips
    );
    // vm.expectEmit(address(hooksFactory));
    // emit IHooksFactory.HooksContractDeployed(address(0), address(0));
    bytes memory constructorArgs = 'o hey this is my hook arg do u like it';
    address hooks = hooksFactory.deployHooksInstance(hooksTemplate, constructorArgs);
    MockHooks hooksInstance = MockHooks(hooks);
    assertEq(hooksInstance.deployer(), address(this));
    assertEq(hooksInstance.constructorArgsHash(), keccak256(constructorArgs));
  }

  function test_deployHooksInstance_NotApprovedBorrower() external {
    vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedBorrower.selector);
    hooksFactory.deployHooksInstance(address(0), '');
  }

  function test_deployHooksInstance_HooksTemplateNotFound() external {
    archController.registerBorrower(address(this));
    vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotFound.selector);
    hooksFactory.deployHooksInstance(address(0), '');
  }

  function test_deployHooksInstance_HooksTemplateNotAvailable() external {
    archController.registerBorrower(address(this));
    hooksFactory.addHooksTemplate(hooksTemplate, 'name', nullAddress, nullAddress, 0, 0);
    hooksFactory.disableHooksTemplate(hooksTemplate);
    vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotAvailable.selector);
    hooksFactory.deployHooksInstance(hooksTemplate, '');
  }

  function _validateDeployHooksInstance(
    address hooksTemplate,
    bytes memory constructorArgs
  ) internal returns (MockHooks hooksInstance) {
    address expectedHooksInstance = _setUpDeployHooksInstance(hooksTemplate);
    _expectEventsDeployHooksInstance(hooksTemplate, expectedHooksInstance);
    // Check event
    hooksInstance = MockHooks(hooksFactory.deployHooksInstance(hooksTemplate, constructorArgs));
    _validateDeployedHooksInstance(
      hooksTemplate,
      expectedHooksInstance,
      hooksInstance,
      constructorArgs
    );
  }

  function _setUpDeployHooksInstance(
    address hooksTemplate
  ) internal returns (address expectedAddress) {
    expectedAddress = computeCreateAddress(
      address(hooksFactory),
      vm.getNonce(address(hooksFactory))
    );
    assertFalse(hooksFactory.isHooksInstance(expectedAddress), 'isHooksInstance before deploy');
  }

  function _expectEventsDeployHooksInstance(
    address hooksTemplate,
    address expectedAddress
  ) internal {
    vm.expectEmit(address(hooksFactory));
    emit IHooksFactoryEventsAndErrors.HooksInstanceDeployed(expectedAddress, hooksTemplate);
  }

  function _validateDeployedHooksInstance(
    address hooksTemplate,
    address expectedAddress,
    MockHooks hooksInstance,
    bytes memory constructorArgs
  ) internal {
    // Validate constructor args and version
    assertEq(address(hooksInstance), expectedAddress, 'hooksInstance');
    assertEq(hooksInstance.deployer(), address(this), 'borrower');
    assertEq(
      hooksInstance.constructorArgsHash(),
      keccak256(constructorArgs),
      'constructorArgsHash'
    );
    assertEq(hooksInstance.version(), 'mock-hooks', 'version');
    assertEq(
      hooksFactory.getHooksTemplateForInstance(expectedAddress),
      hooksTemplate,
      'getHooksTemplateForInstance'
    );
    assertTrue(hooksFactory.isHooksInstance(expectedAddress), '!isHooksInstance');
  }

  // ========================================================================== //
  //                                deployMarket                                //
  // ========================================================================== //

  function _validateAddHooksTemplate(
    address hooksTemplate,
    string memory name,
    FuzzFeeConfigurationInputs memory feesInput
  ) internal {
    address[] memory previousHooksTemplates = hooksFactory.getHooksTemplates();
    vm.expectEmit(address(hooksFactory));
    emit IHooksFactoryEventsAndErrors.HooksTemplateAdded(
      hooksTemplate,
      name,
      feesInput.feeRecipient,
      feesInput.originationFeeAsset,
      feesInput.originationFeeAmount,
      feesInput.protocolFeeBips
    );
    hooksFactory.addHooksTemplate(
      hooksTemplate,
      name,
      feesInput.feeRecipient,
      feesInput.originationFeeAsset,
      feesInput.originationFeeAmount,
      feesInput.protocolFeeBips
    );
    address[] memory hooksTemplates = hooksFactory.getHooksTemplates();
    assertEq(hooksTemplates.length, previousHooksTemplates.length + 1, 'hooksTemplates.length');
    assertEq(hooksTemplates[hooksTemplates.length - 1], hooksTemplate, 'hooksTemplates[-1]');

    HooksTemplate memory details = hooksFactory.getHooksTemplateDetails(hooksTemplate);
    assertEq(
      details,
      HooksTemplate({
        exists: true,
        enabled: true,
        index: uint24(previousHooksTemplates.length),
        name: name,
        feeRecipient: feesInput.feeRecipient,
        originationFeeAsset: feesInput.originationFeeAsset,
        originationFeeAmount: feesInput.originationFeeAmount,
        protocolFeeBips: feesInput.protocolFeeBips
      })
    );
  }

  function _setUpDeployMarket(FuzzFeeConfigurationInputs memory feesInput) internal {
    if (feesInput.originationFeeAsset != nullAddress && feesInput.originationFeeAmount > 0) {
      feeToken.mint(address(this), feesInput.originationFeeAmount);
      feeToken.approve(address(hooksFactory), feesInput.originationFeeAmount);
    }
  }

  // @todo context obj for tracking variables like salt
  function _expectEventsDeployMarket(
    DeployMarketInputs memory parameters,
    FuzzFeeConfigurationInputs memory feesInput,
    HooksConfig expectedConfig
  ) internal {
    if (feesInput.originationFeeAsset != nullAddress && feesInput.originationFeeAmount > 0) {
      vm.expectEmit(address(feeToken));
      emit ERC20.Transfer(address(this), feesInput.feeRecipient, feesInput.originationFeeAmount);
    }
    string memory name = string.concat(parameters.namePrefix, ERC20(parameters.asset).name());
    string memory symbol = string.concat(parameters.symbolPrefix, ERC20(parameters.asset).symbol());
    vm.expectEmit(address(hooksFactory));
    emit IHooksFactoryEventsAndErrors.MarketDeployed(
      hooksFactory.computeMarketAddress(bytes32(uint(1))),
      name,
      symbol,
      parameters.asset,
      parameters.maxTotalSupply,
      parameters.annualInterestBips,
      parameters.delinquencyFeeBips,
      parameters.withdrawalBatchDuration,
      parameters.reserveRatioBips,
      parameters.delinquencyGracePeriod,
      expectedConfig
    );
  }

  function _validateDeployedMarket(
    WildcatMarket market,
    DeployMarketInputs memory parameters,
    FuzzFeeConfigurationInputs memory feesInput,
    StandardHooksConfig memory marketHooksConfig,
    StandardHooksConfig memory templateHooksConfig,
    bytes memory hooksData
  ) internal {
    // Ensure the market's hooks config was updated to only include flags shared with the hooks instance
    HooksConfig marketConfig = market.hooks();
    assertEq(marketConfig, marketHooksConfig.mergeSharedFlags(templateHooksConfig), 'hooksConfig');

    MockHooks hooksInstance = MockHooks(parameters.hooks.hooksAddress());
    // Check that the hooks instance received the correct data in `onCreateMarket`
    // Update parameter.hooks for assertEq on the parameters object
    parameters.hooks = marketConfig;
    assertEq(hooksInstance.lastDeployer(), address(this), 'onCreateMarket: deployer');
    assertEq(hooksInstance.lastDeployMarketInputs(), parameters, 'onCreateMarket: parameters');
    assertEq(
      hooksInstance.lastCreateMarketHooksData(),
      hooksData,
      'onCreateMarket: lastCreateMarketHooksData'
    );

    // Check that the market received the correct other parameters
    assertEq(market.asset(), parameters.asset, 'asset');
    assertEq(
      market.name(),
      string.concat(parameters.namePrefix, ERC20(parameters.asset).name()),
      'name'
    );
    assertEq(
      market.symbol(),
      string.concat(parameters.symbolPrefix, ERC20(parameters.asset).symbol()),
      'symbol'
    );
    assertEq(market.decimals(), ERC20(parameters.asset).decimals(), 'decimals');
    assertEq(address(market.sentinel()), sanctionsSentinel, 'sentinel');
    assertEq(market.borrower(), address(this), 'borrower');
    assertEq(market.feeRecipient(), feesInput.feeRecipient, 'feeRecipient');
    assertEq(market.protocolFeeBips(), feesInput.protocolFeeBips, 'protocolFeeBips');
    assertEq(market.delinquencyFeeBips(), parameters.delinquencyFeeBips, 'delinquencyFeeBips');
    assertEq(
      market.delinquencyGracePeriod(),
      parameters.delinquencyGracePeriod,
      'delinquencyGracePeriod'
    );
    assertEq(
      market.withdrawalBatchDuration(),
      parameters.withdrawalBatchDuration,
      'withdrawalBatchDuration'
    );
  }

  function _validateDeployMarket(
    DeployMarketInputs memory parameters,
    FuzzFeeConfigurationInputs memory feesInput,
    StandardHooksConfig memory marketHooksConfig,
    StandardHooksConfig memory templateHooksConfig,
    bytes memory hooksData
  ) internal returns (WildcatMarket market) {
    _setUpDeployMarket(feesInput);
    _expectEventsDeployMarket(
      parameters,
      feesInput,
      marketHooksConfig.mergeSharedFlags(templateHooksConfig).toHooksConfig()
    );
    market = WildcatMarket(hooksFactory.deployMarket(parameters, hooksData, bytes32(uint(1))));
    _validateDeployedMarket(
      market,
      parameters,
      feesInput,
      marketHooksConfig,
      templateHooksConfig,
      hooksData
    );
  }

  function test_deployMarket(
    FuzzDeployMarketInputs memory paramsInput,
    FuzzFeeConfigurationInputs memory feesInput
  ) external constrain(feesInput) {
    archController.registerBorrower(address(this));

    _validateAddHooksTemplate(hooksTemplate, 'name', feesInput);

    bytes memory constructorArgs = 'o hey this is my market arg do u like it';
    MockHooks hooksInstance = _validateDeployHooksInstance(hooksTemplate, constructorArgs);

    bytes memory createMarketHooksData = 'o hey this is my createMarketHooksData do u like it';
    paramsInput.templateHooksConfig.hooksAddress = address(hooksInstance);
    paramsInput.marketHooksConfig.hooksAddress = address(hooksInstance);

    hooksInstance.setConfig(paramsInput.templateHooksConfig.toHooksConfig());

    DeployMarketInputs memory parameters = DeployMarketInputs({
      asset: address(underlying),
      namePrefix: 'name',
      symbolPrefix: 'symbol',
      maxTotalSupply: paramsInput.maxTotalSupply,
      annualInterestBips: paramsInput.annualInterestBips,
      delinquencyFeeBips: paramsInput.delinquencyFeeBips,
      withdrawalBatchDuration: paramsInput.withdrawalBatchDuration,
      reserveRatioBips: paramsInput.reserveRatioBips,
      delinquencyGracePeriod: paramsInput.delinquencyGracePeriod,
      hooks: paramsInput.marketHooksConfig.toHooksConfig()
    });
    _validateDeployMarket(
      parameters,
      feesInput,
      paramsInput.marketHooksConfig,
      paramsInput.templateHooksConfig,
      createMarketHooksData
    );
  }

  function test_deployMarketAndHooks(
    FuzzDeployMarketInputs memory paramsInput,
    FuzzFeeConfigurationInputs memory feesInput
  ) external constrain(feesInput) {
    hooksTemplate = LibStoredInitCode.deployInitCode(type(MockHooksWithConfig).creationCode);
    archController.registerBorrower(address(this));
    _validateAddHooksTemplate(hooksTemplate, 'name', feesInput);

    CreateMarketAndHooksContext memory context;
    context.expectedHooksInstance = _setUpDeployHooksInstance(hooksTemplate);
    _setUpDeployMarket(feesInput);

    paramsInput.templateHooksConfig.hooksAddress = context.expectedHooksInstance;
    paramsInput.marketHooksConfig.hooksAddress = context.expectedHooksInstance;
    context.expectedConfig = paramsInput
      .marketHooksConfig
      .mergeSharedFlags(paramsInput.templateHooksConfig)
      .toHooksConfig();

    context.constructorArgs = abi.encode(paramsInput.templateHooksConfig.toHooksConfig());
    context.createMarketHooksData = 'o hey this is my createMarketHooksData do u like it';

    context.parameters = DeployMarketInputs({
      asset: address(underlying),
      namePrefix: 'name',
      symbolPrefix: 'symbol',
      maxTotalSupply: paramsInput.maxTotalSupply,
      annualInterestBips: paramsInput.annualInterestBips,
      delinquencyFeeBips: paramsInput.delinquencyFeeBips,
      withdrawalBatchDuration: paramsInput.withdrawalBatchDuration,
      reserveRatioBips: paramsInput.reserveRatioBips,
      delinquencyGracePeriod: paramsInput.delinquencyGracePeriod,
      hooks: paramsInput.marketHooksConfig.toHooksConfig()
    });
    _expectEventsDeployHooksInstance(hooksTemplate, context.expectedHooksInstance);
    _expectEventsDeployMarket(context.parameters, feesInput, context.expectedConfig);

    {
      (context.marketAddress, context.hooksInstance) = hooksFactory.deployMarketAndHooks(
        hooksTemplate,
        context.constructorArgs,
        context.parameters,
        context.createMarketHooksData,
        bytes32(uint(1))
      );
      _validateDeployedMarket(
        WildcatMarket(context.marketAddress),
        context.parameters,
        feesInput,
        paramsInput.marketHooksConfig,
        paramsInput.templateHooksConfig,
        context.createMarketHooksData
      );
    }
    _validateDeployedHooksInstance(
      hooksTemplate,
      context.expectedHooksInstance,
      MockHooks(context.hooksInstance),
      context.constructorArgs
    );
  }

  struct CreateMarketAndHooksContext {
    bytes  constructorArgs;
    bytes  createMarketHooksData;
    DeployMarketInputs  parameters;
    address expectedHooksInstance;
    address hooksInstance;
    HooksConfig expectedConfig;
    address marketAddress;
  }
}