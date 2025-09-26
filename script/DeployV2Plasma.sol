// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import 'src/WildcatSanctionsSentinel.sol';
import 'src/WildcatArchController.sol';
import 'forge-std/Script.sol';
import 'solady/utils/LibString.sol';
import 'src/market/WildcatMarket.sol';
import 'src/libraries/LibStoredInitCode.sol';
import 'src/access/OpenTermHooks.sol';
import 'src/HooksFactory.sol';
import './LibDeployment.sol';
import './DeployTypes.sol';
import './mock/MockERC20Factory.sol';
import './mock/MockArchControllerOwner.sol';
import './mock/UniversalProvider.sol';
import './Lender.sol';

abstract contract ISphereX is ISphereXEngine {
  function addAllowedPatterns(uint216[] calldata patterns) external virtual;

  function grantSenderAdderRole(address newSenderAdder) external virtual;

  function configureRules(bytes8 rules) external virtual;
}

using LibString for address;
using LibString for string;
using LibString for uint;

string constant DeploymentsJsonFilePath = 'deployments.json';
bool constant RedoAllDeployments = false;

address constant DeployerAddress = 0xB1DddA4c0259ebFe058f057DfE22C70D3a91F799;

interface IEngine {
  function deactivateAllRules() external;

  function configureRules(bytes8 rules) external;

  function addAllowedPatterns(uint216[] calldata patterns) external;
}

contract DeployV2Plasma is Script {
  function run() public virtual {
    console.log(
      'Deploying to %s (chain id: %s | %s)',
      getNetworkName(),
      block.chainid,
      getIsTestnet() ? 'testnet' : 'mainnet'
    );
    console.log('Deployer: %s | balance: %e', DeployerAddress, DeployerAddress.balance);
    deployAll();
  }

  function validateDeployments(Deployments memory deployments) internal {
    WildcatArchController archController = WildcatArchController(
      deployments.get('WildcatArchController')
    );
    HooksFactory hooksFactory = HooksFactory(deployments.get('HooksFactory'));
    WildcatSanctionsSentinel sentinel = WildcatSanctionsSentinel(
      deployments.get('WildcatSanctionsSentinel')
    );
    ISphereX sphereXEngine = ISphereX(deployments.get('SphereXEngine'));
    address openTermHooks = deployments.get('OpenTermHooks_initCodeStorage');
    address fixedTermHooks = deployments.get('FixedTermHooks_initCodeStorage');
    address openAccessRoleProvider = deployments.get('OpenAccessRoleProvider');
    address marketLens = deployments.get('MarketLens');
    bool isTestnet = getIsTestnet();
    address chainalysis;
    if (isTestnet) {
      chainalysis = deployments.get('MockChainalysisContract');
    } else {
      chainalysis = deployments.get('ChainalysisProxy');
    }
    // Owner is deployer on mainnet, or the MockArchControllerOwner on testnet
    if (isTestnet) {
      assertEq(
        archController.owner(),
        deployments.get('MockArchControllerOwner'),
        'Arch controller owner is not the MockArchControllerOwner'
      );
    } else {
      assertEq(
        archController.owner(),
        DeployerAddress,
        'Arch controller owner is not the deployer'
      );
    }
    // HooksFactory is a registered controller factory and controller
    assertTrue(
      archController.isRegisteredControllerFactory(address(hooksFactory)),
      'HooksFactory is not a registered controller factory'
    );
    assertTrue(
      archController.isRegisteredController(address(hooksFactory)),
      'HooksFactory is not a registered controller'
    );
    // HooksFactory has the correct owner, templates, and SphereX engine
    assertEq(
      hooksFactory.archController(),
      address(archController),
      'HooksFactory arch controller is not the arch controller'
    );
    assertEq(
      hooksFactory.getHooksTemplatesCount(),
      2,
      'HooksFactory has the wrong number of templates'
    );
    assertEq(
      hooksFactory.getHooksTemplates(0, 1)[0],
      openTermHooks,
      'First template is not open term'
    );
    assertEq(
      hooksFactory.getHooksTemplates(1, 2)[0],
      fixedTermHooks,
      'Second template is not fixed term'
    );
    assertEq(
      hooksFactory.sphereXEngine(),
      address(sphereXEngine),
      'HooksFactory has the wrong SphereX engine'
    );
    assertEq(
      hooksFactory.sphereXOperator(),
      address(archController),
      'HooksFactory has the wrong SphereX operator'
    );
    // Sentinel has the correct owner, arch controller, and chainalysis
    assertEq(
      sentinel.archController(),
      address(archController),
      'Sentinel arch controller is not the arch controller'
    );
    assertEq(
      sentinel.chainalysisSanctionsList(),
      address(chainalysis),
      'Sentinel chainalysis is not the chainalysis'
    );
    // Arch controller has the correct owner, spherex engine, and operator
    assertEq(
      archController.sphereXOperator(),
      DeployerAddress,
      'Arch controller spherex operator is not the deployer'
    );
    assertEq(
      archController.sphereXEngine(),
      address(sphereXEngine),
      'Arch controller spherex engine is not the spherex engine'
    );
    // All deployments on arch controller have correct spherex engine
    address[] memory targets = archController.getRegisteredMarkets();
    for (uint i = 0; i < targets.length; i++) {
      assertEq(
        SphereXProtectedRegisteredBase(targets[i]).sphereXEngine(),
        address(sphereXEngine),
        string.concat(
          'Market ',
          targets[i].toHexString(),
          ' spherex engine is not the spherex engine'
        )
      );
    }
    targets = archController.getRegisteredControllerFactories();
    for (uint i = 0; i < targets.length; i++) {
      assertEq(
        SphereXProtectedRegisteredBase(targets[i]).sphereXEngine(),
        address(sphereXEngine),
        string.concat(
          'Controller factory ',
          targets[i].toHexString(),
          ' spherex engine is not the spherex engine'
        )
      );
    }
    targets = archController.getRegisteredControllers();
    for (uint i = 0; i < targets.length; i++) {
      assertEq(
        SphereXProtectedRegisteredBase(targets[i]).sphereXEngine(),
        address(sphereXEngine),
        string.concat(
          'Controller ',
          targets[i].toHexString(),
          ' spherex engine is not the spherex engine'
        )
      );
    }
  }

  function deployBaseProtocolContracts(
    Deployments memory deployments
  )
    internal
    returns (
      WildcatArchController archController,
      bool didDeployArchController,
      address chainalysis,
      WildcatSanctionsSentinel sentinel
    )
  {
    address _archController;
    (_archController, didDeployArchController) = deployments.getOrDeploy(
      'WildcatArchController',
      _getCreationCode(deployments, 'WildcatArchController'),
      RedoAllDeployments
    );
    archController = WildcatArchController(_archController);
    if (getIsTestnet()) {
      (chainalysis, ) = deployments.getOrDeploy(
        'MockChainalysisContract',
        _getCreationCode(deployments, 'MockChainalysisContract'),
        RedoAllDeployments
      );
    } else {
      (chainalysis, ) = deployments.getOrDeploy(
        'ChainalysisProxy',
        _getCreationCode(deployments, 'ChainalysisProxy'),
        RedoAllDeployments
      );
    }
    (address _sentinel, bool didDeploySentinel) = deployments.getOrDeploy(
      'WildcatSanctionsSentinel',
      _getCreationCode(deployments, 'WildcatSanctionsSentinel'),
      abi.encode(_archController, chainalysis),
      didDeployArchController
    );
    sentinel = WildcatSanctionsSentinel(_sentinel);
    setupSphereXEngine(deployments);
  }

  function setupSphereXEngine(
    Deployments memory deployments
  ) internal returns (ISphereX sphereXEngine, bool didDeploySphereXEngine) {
    address _sphereXEngine;
    (_sphereXEngine, didDeploySphereXEngine) = deployments.getOrDeploy(
      'SphereXEngine',
      _getCreationCode(deployments, 'SphereXEngine'),
      RedoAllDeployments
    );
    WildcatArchController archController = WildcatArchController(
      deployments.get('WildcatArchController')
    );
    sphereXEngine = ISphereX(_sphereXEngine);
    if (didDeploySphereXEngine) {
      deployments.broadcast();
      sphereXEngine.addAllowedPatterns(getSphereXPatterns());
      deployments.broadcast();
      sphereXEngine.grantSenderAdderRole(address(archController));
      deployments.broadcast();
      sphereXEngine.configureRules(0x0000000000000001);
      console.log('Configured SphereX patterns, rules and roles');
      deployments.broadcast();
      archController.changeSphereXOperator(DeployerAddress);
      deployments.broadcast();
      archController.changeSphereXEngine(_sphereXEngine);
      console.log('Configured SphereX engine and operator on arch controller');
    }
  }

  function deployAll() internal virtual {
    Deployments memory deployments = getDeployments().withPrivateKeyVarName('PVT_KEY');

    (
      WildcatArchController archController,
      bool didDeployArchController,
      address chainalysis,
      WildcatSanctionsSentinel sentinel
    ) = deployBaseProtocolContracts(deployments);
    /* ---------------------------- V2 Hooks Factory ---------------------------- */

    // Deploy market template and hooks factory
    (
      address marketTemplate,
      bool didDeployMarketTemplate,
      uint256 marketInitCodeHash
    ) = _storeMarketInitCode(deployments);

    (address hooksFactory, bool didDeployHooksFactory) = deployments.getOrDeploy(
      'HooksFactory',
      _getCreationCode(deployments, 'HooksFactory'),
      abi.encode(address(archController), address(sentinel), marketTemplate, marketInitCodeHash),
      didDeployArchController || didDeployMarketTemplate
    );

    if (getIsTestnet()) {
      deployments.getOrDeploy(
        'MockArchControllerOwner',
        abi.encodePacked(
          type(MockArchControllerOwner).creationCode,
          abi.encode(archController, hooksFactory)
        ),
        didDeployArchController
      );
    }

    _setUpHooksFactory(deployments, archController, HooksFactory(hooksFactory));
    deployments.getOrDeploy(
      'OpenAccessRoleProvider',
      _getCreationCode(deployments, 'OpenAccessRoleProvider'),
      abi.encode(chainalysis)
    );

    /* --------------------------------- V2 Lens -------------------------------- */
    deployments.getOrDeploy(
      'MarketLens',
      _getCreationCode(deployments, 'MarketLens'),
      abi.encode(archController, hooksFactory),
      didDeployHooksFactory
    );

    HooksFactory factory = HooksFactory(hooksFactory);
    assertEq(factory.getHooksTemplatesCount(), 2, 'Wrong # of templates');
    address openTermHooks = deployments.get('OpenTermHooks_initCodeStorage');
    assertEq(factory.getHooksTemplates(0, 1)[0], openTermHooks, 'First template is not open term');

    address fixedTermHooks = deployments.get('FixedTermHooks_initCodeStorage');
    assertEq(
      factory.getHooksTemplates(1, 2)[0],
      fixedTermHooks,
      'Second template is not fixed term'
    );

    if (getIsTestnet()) {
      _seedForTestnet(deployments);
    }
    deployments.write();
    validateDeployments(deployments);
  }

  /**
   * @dev Prepares the hooks factory:
   *      - Registers the hooks factory as a controller factory and initializes
   *        it with the arch controller, if either has not been done.
   *      - Deploys the OpenTermHooks template if it does not exist.
   *      - Deploys the FixedTermHooks template if it does not exist.
   *      - Registers the templates with the hooks factory if they're not already registered.
   */
  function _setUpHooksFactory(
    Deployments memory deployments,
    WildcatArchController archController,
    HooksFactory hooksFactory
  ) internal {
    bool registerAsFactory = !archController.isRegisteredControllerFactory(address(hooksFactory));
    bool registerAsController = !archController.isRegisteredController(address(hooksFactory));
    console.log("Registering controller...", registerAsController);
    (address openTermTemplate, ) = deployments.getOrDeployInitcodeStorage(
      'OpenTermHooks',
      _getCreationCode(deployments, 'OpenTermHooks'),
      RedoAllDeployments
    );
    (address fixedTermTemplate, ) = deployments.getOrDeployInitcodeStorage(
      'FixedTermHooks',
      _getCreationCode(deployments, 'FixedTermHooks'),
      RedoAllDeployments
    );
    bool addOpenTermTemplate = !HooksFactory(hooksFactory).isHooksTemplate(openTermTemplate);
    bool addFixedTermTemplate = !HooksFactory(hooksFactory).isHooksTemplate(fixedTermTemplate);

    if (
      getIsTestnet() &&
      (registerAsFactory || registerAsController || addOpenTermTemplate || addFixedTermTemplate)
    ) {
      _takeOwnershipOfArchController(deployments);
    }
    if (!getIsTestnet() && archController.owner() != DeployerAddress) {
      revert('Deployer is not the owner of the arch controller.');
    }
    address owner = archController.owner();
    if (registerAsFactory) {
      deployments.broadcast();
      archController.registerControllerFactory(address(hooksFactory));
    }
    if (registerAsController) {
      deployments.broadcast();
      hooksFactory.registerWithArchController();
    }
    if (addOpenTermTemplate) {
      deployments.broadcast();
      HooksFactory(hooksFactory).addHooksTemplate({
        hooksTemplate: openTermTemplate,
        name: 'OpenTermHooks',
        feeRecipient: owner,
        originationFeeAsset: address(0),
        originationFeeAmount: 0,
        protocolFeeBips: 1_000
      });
    }
    if (addFixedTermTemplate) {
      deployments.broadcast();
      HooksFactory(hooksFactory).addHooksTemplate({
        hooksTemplate: fixedTermTemplate,
        name: 'FixedTermHooks',
        feeRecipient: owner,
        originationFeeAsset: address(0),
        originationFeeAmount: 0,
        protocolFeeBips: 1_000
      });
    }
  }

  function _storeMarketInitCode(
    Deployments memory deployments
  )
    internal
    virtual
    returns (address initCodeStorage, bool didDeployInitcodeStorage, uint256 initCodeHash)
  {
    bytes memory initCode = _getCreationCode(deployments, 'WildcatMarket');
    (initCodeStorage, didDeployInitcodeStorage) = deployments.getOrDeployInitcodeStorage(
      'WildcatMarket',
      initCode,
      RedoAllDeployments
    );
    initCodeHash = uint(keccak256(initCode));
  }

  function _getCreationCode(
    Deployments memory deployments,
    string memory namePath
  ) internal returns (bytes memory) {
    ContractArtifact memory artifact = parseContractNamePath(namePath);

    string memory jsonPath = LibDeployment.findForgeArtifact(artifact, deployments.forgeOutDir);
    Json memory forgeArtifact = JsonUtil.create(vm.readFile(jsonPath));
    bytes memory creationCode = forgeArtifact.getBytes('bytecode.object');
    return creationCode;
  }

  /* ========================================================================== */
  /*                              Testnet Functions                             */
  /* ========================================================================== */

  function _seedForTestnet(Deployments memory deployments) internal {
    _registerBorrower(deployments, 0xca732651410E915090d7A7D889A1E44eF4575fcE);
    HooksFactory factory = HooksFactory(deployments.get('HooksFactory'));
    WildcatArchController archController = WildcatArchController(
      deployments.get('WildcatArchController')
    );
    deployments.getOrDeploy(
      'MockERC20Factory',
      _getCreationCode(deployments, 'MockERC20Factory'),
      RedoAllDeployments
    );

    (, WildcatMarket market, ) = _createMarket({
      deployments: deployments,
      openTerm: true,
      restrictive: false
    });
    _createMarket({ deployments: deployments, openTerm: false, restrictive: true });
    _seedMarketFunctions(deployments, market);
    _returnOwnershipOfArchController(deployments);

    require(
      archController.owner() == deployments.get('MockArchControllerOwner'),
      'Ownership should be returned'
    );
    address openTermHooks = deployments.get('OpenTermHooks_initCodeStorage');
    assertEq(
      factory.getMarketsForHooksTemplateCount(openTermHooks),
      1,
      'wrong # of markets for OpenTermHooks'
    );
    address fixedTermHooks = deployments.get('FixedTermHooks_initCodeStorage');
    assertEq(
      factory.getMarketsForHooksTemplateCount(fixedTermHooks),
      1,
      'wrong # of markets for FixedTermHooks'
    );
  }

  function _buildMarketConfig(
    bool openTerm,
    bool restrictive
  ) internal view returns (MarketConfig memory config) {
    // token parameters
    config.tokenName = 'Token';
    config.tokenSymbol = 'TOK';
    config.tokenDecimals = 18;
    // market parameters
    config.salt = openTerm ? bytes32(0) : bytes32(uint(1));
    config.namePrefix = openTerm ? 'TestMKT Open V2 ' : 'TestMKT Fixed V2 ';
    config.symbolPrefix = openTerm ? 'Test_op2' : 'Test_fx2';
    config.maxTotalSupply = uint128(100_000e18);
    config.annualInterestBips = 1_500;
    config.delinquencyFeeBips = 1_000;
    config.withdrawalBatchDuration = uint32(1);
    config.reserveRatioBips = 1_000;
    config.delinquencyGracePeriod = uint32(1);
    config.marketSymbol = string.concat(config.symbolPrefix, config.tokenSymbol);
    config.hooks = MarketHooksOptions({
      isOpenTerm: openTerm,
      transferAccess: restrictive ? TransferAccess.Disabled : TransferAccess.Open,
      depositAccess: restrictive ? DepositAccess.RequiresCredential : DepositAccess.Open,
      withdrawalAccess: restrictive ? WithdrawalAccess.RequiresCredential : WithdrawalAccess.Open,
      minimumDeposit: uint128(1e16),
      fixedTermEndTime: openTerm ? 0 : uint32(block.timestamp + 1_500),
      allowClosureBeforeTerm: restrictive ? false : true,
      allowTermReduction: restrictive ? false : true,
      hooksName: string.concat(
        config.marketSymbol,
        config.hooks.isOpenTerm ? ' OpenTermHooks' : 'FixedTermHooks'
      ),
      useUniversalProvider: true
    });
  }

  function _createMarket(
    Deployments memory deployments,
    bool openTerm,
    bool restrictive
  ) internal returns (OpenTermHooks hooks, WildcatMarket market, MockERC20 token) {
    MarketConfig memory config = _buildMarketConfig(openTerm, restrictive);
    (hooks, market, token) = _deployMarketAndHooks(deployments, config);
  }

  function _seedMarketFunctions(Deployments memory deployments, WildcatMarket market) internal {
    IEngine engine = IEngine(market.sphereXEngine());

    // deployments.broadcast();
    // engine.deactivateAllRules();
    // console.log('Deactivated spherex engine');

    address borrower = market.borrower();
    if (!deployments.has('MockERC20:RescueToken')) {
      MockERC20 rescueToken = _deployToken(deployments, 'RescueToken', 'RST');

      deployments.broadcast();
      rescueToken.mint(address(market), 1e18);

      deployments.broadcast();
      market.rescueTokens(address(rescueToken));
      console.log('Did rescue tokens');
    }

    // if (market.balanceOf(borrower) < 1e18) {
    //   deployments.broadcast();
    //   market.deposit{ gas: 400_000 }(1e18);
    //   console.log('Did deposit #1');

    //   deployments.broadcast();
    //   market.queueFullWithdrawal{ gas: 400_000 }();
    //   console.log('Did queue full withdrawal');
    // }

    if (market.balanceOf(borrower) < 1e18) {
      deployments.broadcast();
      market.deposit{ gas: 400_000 }(1e18);
      console.log('Did deposit #2');
    }

    HooksFactory factory = HooksFactory(deployments.get('HooksFactory'));
    address hooksInstance = market.hooks().hooksAddress();
    address hooksTemplate = factory.getHooksTemplateForInstance(hooksInstance);
    HooksTemplate memory templateDetails = factory.getHooksTemplateDetails(hooksTemplate);
    console.log('Hooks template: ', hooksTemplate);
    _takeOwnershipOfArchController(deployments);
    deployments.broadcast();
    factory.updateHooksTemplateFees({
      hooksTemplate: hooksTemplate,
      feeRecipient: templateDetails.feeRecipient,
      originationFeeAsset: templateDetails.originationFeeAsset,
      originationFeeAmount: templateDetails.originationFeeAmount,
      protocolFeeBips: 500
    });
    console.log('Updated protocol fee for template');

    deployments.broadcast();
    factory.pushProtocolFeeBipsUpdates(hooksTemplate, 0, 1);
    console.log('Pushed protocol fee to market');

    deployments.broadcast();
    market.setAnnualInterestAndReserveRatioBips(2_000, 0);
    console.log('Set annual interest and reserve ratio');

    deployments.broadcast();
    engine.configureRules(0x0000000000000001);
    console.log('Reactivated spherex engine');
  }

  function _registerBorrower(Deployments memory deployments, address borrower) internal virtual {
    WildcatArchController archController = WildcatArchController(
      deployments.get('WildcatArchController')
    );
    MockArchControllerOwner oldOwner = MockArchControllerOwner(
      deployments.get('MockArchControllerOwner')
    );
    if (!archController.isRegisteredBorrower(borrower)) {
      address owner = archController.owner();
      deployments.broadcast();
      if (owner == address(oldOwner)) {
        oldOwner.registerBorrower(borrower);
      } else {
        archController.registerBorrower(borrower);
      }
    }
  }

  function getHooksTemplateArgs(
    Deployments memory deployments,
    string memory hooksName
  ) internal returns (bytes memory hooksTemplateArgs) {
    (address providerAddress, ) = deployments.getOrDeploy(
      'UniversalProvider',
      _getCreationCode(deployments, 'UniversalProvider'),
      false
    );

    NameAndProviderInputs memory hooksArgs;
    hooksArgs.name = hooksName;
    hooksArgs.existingProviders = new ExistingProviderInputs[](1);
    hooksArgs.existingProviders[0].providerAddress = providerAddress;
    hooksArgs.existingProviders[0].timeToLive = type(uint32).max;
    return abi.encode(hooksArgs);
  }

  function _deployMarketAndHooks(
    Deployments memory deployments,
    MarketConfig memory config
  ) internal returns (OpenTermHooks hooks, WildcatMarket market, MockERC20 token) {
    string memory marketSymbol = config.marketSymbol;

    if (deployments.has(string.concat(marketSymbol, '_market'))) {
      market = WildcatMarket(deployments.get(string.concat(marketSymbol, '_market')));
      hooks = OpenTermHooks(deployments.get(string.concat(marketSymbol, '_hooks')));
      token = MockERC20(market.asset());
      return (hooks, market, token);
    }

    HooksFactory hooksFactory = HooksFactory(deployments.get('HooksFactory'));
    address hooksTemplate = deployments.get(
      config.hooks.isOpenTerm ? 'OpenTermHooks_initCodeStorage' : 'FixedTermHooks_initCodeStorage'
    );

    DeployMarketInputs memory inputs;
    {
      inputs.asset = address(_deployToken(deployments, config.tokenName, config.tokenSymbol));
      inputs.namePrefix = config.namePrefix;
      inputs.symbolPrefix = config.symbolPrefix;
      inputs.maxTotalSupply = config.maxTotalSupply;
      inputs.annualInterestBips = config.annualInterestBips;
      inputs.delinquencyFeeBips = config.delinquencyFeeBips;
      inputs.withdrawalBatchDuration = config.withdrawalBatchDuration;
      inputs.reserveRatioBips = config.reserveRatioBips;
      inputs.delinquencyGracePeriod = config.delinquencyGracePeriod;
      inputs.hooks = config.hooks.toHooksConfig();
    }
    bytes memory hooksTemplateArgs = getHooksTemplateArgs(deployments, config.hooks.hooksName);
    {
      bytes memory hookData = config.hooks.encodeHooksData();

      deployments.broadcast();
      (address marketAddress, address hooksInstance) = hooksFactory.deployMarketAndHooks({
        hooksTemplate: hooksTemplate,
        hooksTemplateArgs: hooksTemplateArgs,
        parameters: inputs,
        hooksData: hookData,
        salt: config.salt,
        originationFeeAsset: address(0),
        originationFeeAmount: 0
      });

      hooks = OpenTermHooks(hooksInstance);
      market = WildcatMarket(marketAddress);
    }
    token = MockERC20(inputs.asset);
    require(
      keccak256(bytes(market.symbol())) ==
        keccak256(bytes(string.concat(config.symbolPrefix, config.tokenSymbol))),
      'Market symbols do not match!'
    );

    {
      address borrower = market.borrower();
      // Set up approvals
      deployments.broadcast();
      token.mint(borrower, 1_000_000_000e18);
      deployments.broadcast();
      token.approve(address(market), type(uint256).max);
      deployments.broadcast();
      market.approve(borrower, type(uint256).max);

      // Add market artifact - takes no constructor args
      deployments.addArtifactWithoutDeploying(
        string.concat(marketSymbol, '_market'),
        'WildcatMarket',
        address(market),
        ''
      );
      // Add hooks artifact - takes constructor args (address borrower, bytes args)
      deployments.addArtifactWithoutDeploying(
        string.concat(marketSymbol, '_hooks'),
        config.hooks.isOpenTerm ? 'OpenTermHooks' : 'FixedTermHooks',
        address(hooks),
        abi.encode(borrower, hooksTemplateArgs)
      );

      assertEq(
        hooksFactory.computeMarketAddress(config.salt),
        address(market),
        'Wrong market address computed'
      );
    }
  }

  function _takeOwnershipOfArchController(Deployments memory deployments) internal {
    WildcatArchController archController = WildcatArchController(
      deployments.get('WildcatArchController')
    );
    MockArchControllerOwner oldOwner = MockArchControllerOwner(
      deployments.get('MockArchControllerOwner')
    );
    if (archController.owner() == address(oldOwner)) {
      deployments.broadcast();
      oldOwner.returnOwnership();
      console.log('Took ownership of arch-controller...');
    }
  }

  function _returnOwnershipOfArchController(Deployments memory deployments) internal {
    WildcatArchController archController = WildcatArchController(
      deployments.get('WildcatArchController')
    );
    MockArchControllerOwner oldOwner = MockArchControllerOwner(
      deployments.get('MockArchControllerOwner')
    );
    if (archController.owner() != address(oldOwner)) {
      deployments.broadcast();
      archController.transferOwnership(address(oldOwner));
    }
  }

  function _deployToken(
    Deployments memory deployments,
    string memory name,
    string memory symbol
  ) internal returns (MockERC20 token) {
    string memory label = string.concat('MockERC20:', name);
    if (deployments.has(label)) {
      token = MockERC20(deployments.get(label));
    } else {
      IMockERC20Factory erc20Factory = IMockERC20Factory(deployments.get('MockERC20Factory'));
      deployments.broadcast();
      token = MockERC20(erc20Factory.deployMockERC20(name, symbol));
      deployments.set(label, address(token));
    }
  }

  /* ========================================================================== */
  /*                              Utility Functions                             */
  /* ========================================================================== */

  function assertEq(uint a, uint b, string memory errorMessage) internal {
    if (a != b) {
      console.log(string.concat('Error: ', errorMessage));
      console.log(string.concat('Expected: ', a.toString()));
      console.log(string.concat('Actual: ', b.toString()));
      revert(string.concat('Error: ', errorMessage));
    }
  }

  function assertTrue(bool condition, string memory errorMessage) internal {
    assertEq(condition ? 1 : 0, 1, errorMessage);
  }

  function assertEq(uint a, uint b) internal {
    assertEq(a, b, 'Numbers do not match');
  }

  function assertEq(address a, address b, string memory errorMessage) internal {
    assertEq(a.toHexString(), b.toHexString(), errorMessage);
  }

  function assertEq(address a, address b) internal {
    assertEq(a, b, 'Addresses do not match');
  }

  function assertEq(string memory a, string memory b, string memory errorMessage) internal {
    if (keccak256(bytes(a)) != keccak256(bytes(b))) {
      console.log(string.concat('Error: ', errorMessage));
      console.log(string.concat('Expected: ', a));
      console.log(string.concat('Actual: ', b));
      revert(string.concat('Error: ', errorMessage));
    }
  }

  function assertEq(string memory a, string memory b) internal {
    assertEq(a, b, 'Strings do not match');
  }

  function getSphereXPatterns() internal pure returns (uint216[] memory patterns) {
    patterns = new uint216[](130);
    patterns[0] = 0xf642b59116a112dd2f20f0dc0d9228c2aef57174fd61dfa7d1d9b2;
    patterns[1] = 0xf647bb033467cca24b2a5d21a3f46d4b6733654bd38b012430e3fe;
    patterns[2] = 0xbd601bc0d4e30878a60d5b7855e17147303b9467895982862d2b22;
    patterns[3] = 0x11d01debc9c9755589eef434e72489ff00616fd191ad095273da6d;
    patterns[4] = 0x20dd8cb2a66682cd3842ec6c27927efb6096ff4548c1084dd1e72e;
    patterns[5] = 0x631a68713a9fb43ea371a62c6e40b7231b3709878f03f84ebc850d;
    patterns[6] = 0x7da7ef8c1ffe8ce2498eb6bdc8556f64ebc2967af9a9857ea28dc0;
    patterns[7] = 0x318fdb84f14cfdcced05eda620b965ecd1d5c31f4b40a5db6a4392;
    patterns[8] = 0x3d8abc50db2bc9817f805fcdcfd0abbd4a8513cd01ed8809c35006;
    patterns[9] = 0xad914010796a504bf8804e2ac6d2b3b0552f20e58831ae450ddebb;
    patterns[10] = 0xfa967fdd6a14880f6cab4deba6a68efd6bee798f674bf990fe46f9;
    patterns[11] = 0xd36d10466c61d1e1fe3fad20010ff0cf7214ed0d8aded3c962adee;
    patterns[12] = 0x6499a2e4088f2517cf2ad9f9576bd80c6aeacb963e5242758690fc;
    patterns[13] = 0x3d8c1bdf7a445c19ccdbfe117bdb1d2d2715be32dcdcd0a0384694;
    patterns[14] = 0xb7004d02220bcbe18a59c0d370be541295e568db31c1b677f0cf94;
    patterns[15] = 0x27d781620a33831a4dc367cd896000118a6288464ba55c1f0b0227;
    patterns[16] = 0x6260a7bb3d6c4d79d073f27820121d3d2f93be61ffdf049a1ab656;
    patterns[17] = 0x3f62c6f68771d7f980e7cfba63dce875afbc3e6a8c4956b0ed8aac;
    patterns[18] = 0xc4907f2fc7c0264a7afd38e5e361bb578af4ec43f5c5d9630e4469;
    patterns[19] = 0xc94eb716b934ac75e834a45db5acbf67fb50b2560906104d267f61;
    patterns[20] = 0x353ef80fa36456cef4cd107619e343a7e42d7c2995f1cebefafd9e;
    patterns[21] = 0x018056df2ffdea0a4e0e94d14b0a38b4e978a095ef5124dcd48550;
    patterns[22] = 0x4a68c797021cd0e2d614e125c8468913c485301974b9517edecccd;
    patterns[23] = 0xf60451157eadaef42fe5e43ed98574bbef8379d828c1af26b74df9;
    patterns[24] = 0x173442a564c4d6d5954eb0ed6e21cf940ea1ea25d7a1284af71ef7;
    patterns[25] = 0x5805406bec88ac6ecdf8d6fc36f842f1697af1f5a686d82281145d;
    patterns[26] = 0x275d57a09644716d7797b1c932b2ecf37597f344691770acad462a;
    patterns[27] = 0xe8d1e2faf807459ed2f0d29973af3a469d8330199840c4cba5a488;
    patterns[28] = 0x2251b25652fb26113892b05d7b9ddbada300eb8d56eebf8fc125a5;
    patterns[29] = 0xcbb2133916c20c49c977792f59212e710f96b46b4c927fedf93b9a;
    patterns[30] = 0x2a787072e1e89f598ac67762eb02a0191a0001ee2cab44f67476fe;
    patterns[31] = 0x1f040ea045dc0d480d3f5c83dd71ccdbc1fbe21b4b08f4d2bdfd6a;
    patterns[32] = 0x1c5d6cc6ee70879ff7384641ff88e4444003962d067ec40edd215a;
    patterns[33] = 0xb9fdb6acf80533e440be102d2c00639049ab244fd1fe3b0e73c3a2;
    patterns[34] = 0x6d870dd8044195a55f6bd8890ad9b300953b7146627500a8d68f34;
    patterns[35] = 0x6db8b2a8a19591cc7f5bfc74c1aa7c98e7b94a9b266e86e8e57e98;
    patterns[36] = 0x2051e0a9157b8c7812a9eaef1878990e04de06100ec038beba2d10;
    patterns[37] = 0xd55a82ce86e1f7d3603512313797901e314de2196e200889e5a044;
    patterns[38] = 0x2faac319c009372689fa0053aa7446b7e6cad955f9af576cd2b23d;
    patterns[39] = 0xd570b18d154d3180356a7815729e0c7207a37a30a5d0c80dc42d55;
    patterns[40] = 0xecda32887aa781dc916a5020d0194a77405d8ef50458df046c29dd;
    patterns[41] = 0x271ec67f753f531e529adc32a989b1bd02ad4a30eaed6a69eaf992;
    patterns[42] = 0xc921ce3762af6ffe2362b80ede3adc18a9c6f99d31fa01b58421f9;
    patterns[43] = 0x1da5ce46a6eabd59b0fe01ad02012d44b9e6635ce08f7149606654;
    patterns[44] = 0xca8cc436545190bf28efeb9576912c2de1cad3dcf3971db2455563;
    patterns[45] = 0xeac27dd606c4a3cbaebf3b62fd8d8691d977bad9b1cffd0a090da8;
    patterns[46] = 0xe903f52482ffd73264ea8e3b2f57cae808e4acdf620134aaeb16d3;
    patterns[47] = 0x6e502fb3e8c39336b4bfa673fa08b1283d51054f59c29b3a96836d;
    patterns[48] = 0x02f2f31873a2b5e5c1d9d83978d7f9a5ead35d350f6dc209632749;
    patterns[49] = 0xb250aa52eda4f95d9219b4519e2dd01f6e056cb7a47f142fab4bfa;
    patterns[50] = 0xca7db5bf93c4360ab26f1a8b6c7d6671a2d098e0bdeb2434c98f41;
    patterns[51] = 0xa906b706331aa24edc88661637bd7a5ff187cb3896653acf72677c;
    patterns[52] = 0x59ff32fa8d9a32147697a61fa77471f10c5bceb00267a4b23ee266;
    patterns[53] = 0x3b0f205c6c597840d54d40fd8dda2b0359f65eac42702038064abc;
    patterns[54] = 0xd126cd48c278188d3aad7d5508a41a064110bd8fb6b7a6eb6d1ef1;
    patterns[55] = 0xc9923f444a465646dfe67b60c5770bd841c629d2df6fbe3e1d7888;
    patterns[56] = 0x4038dbea624b2c0e64f114d09cb90620ebfdbe49d898e7bb378dc8;
    patterns[57] = 0x6e49dd201646503d4686241009a202325ebb24c3e519fba7d81311;
    patterns[58] = 0x0e75cc1a3e080cc138a1c840ea30bc7c3b129223ac090ae857639c;
    patterns[59] = 0xbda3503d1e6bc51d8bc4bbe8dd0f59377943ab67e0e21320f25950;
    patterns[60] = 0x0dd8ed84bedba799a2f61591c78773264e1212bf5c0dbd7e012709;
    patterns[61] = 0x8305bd5c08166c6a2d2476c0e8c9320b7447565d0f87e943eddc11;
    patterns[62] = 0xb1debd9ca95dec62bdb9e91bd2c0fbb5c460a00add162b59136f18;
    patterns[63] = 0x0b2e532f4df6bd0bb23c36a237e527eecd53135cd17e936e133efd;
    patterns[64] = 0xce94897113a4c682677a8e97d1a168d3a78d08e096ff69bdaac867;
    patterns[65] = 0x28fb4de931c43401f4b0baeff23f9294fc9600ec1a1b2b414129e8;
    patterns[66] = 0xe29202d34b2625d60b3a1468db0758c308375c9d2cf363b7cf4503;
    patterns[67] = 0x664ff4715c4f349bc6b2d11a56c053d43cf10436e8f95e208198cc;
    patterns[68] = 0x7717fa711257ff51b4bdc48d3cf0a55a32f9026835e3d62ee8dda9;
    patterns[69] = 0x17684bcdccb19db80840a79a1ddb0abfd69d39752207ec2574770d;
    patterns[70] = 0x94ed04983f1d90f8cb8d434edfa8a4286412d604a4a2496be952b0;
    patterns[71] = 0x2cbf075a12829592e1c94cd1733b71801d97f3d7ce275cd69d079c;
    patterns[72] = 0xf83eac1b1977fd224448068185310bb1d670dbfb32d8c67db65e14;
    patterns[73] = 0xe4ac051779b18238f19eadfa72f0f226531705a23c61c48e8b8a22;
    patterns[74] = 0x777ecc068c8034a0cf2d366be876065de03fc41d1b23d4f27b6b0d;
    patterns[75] = 0x3b208afb09cdb7bb164b706c36301ad20b5a2670ca19aca932e259;
    patterns[76] = 0x3602200333c6966af1215669ebd9ea5f749bb89ac968a82e56f86d;
    patterns[77] = 0xeff9bd8292b3f2bdf234fe62e1e77631380ac1903544de845049d5;
    patterns[78] = 0xd28df619ae170f14949dad92d4d91e49f6be973da40bfaec2c7e4d;
    patterns[79] = 0xf8abf3667dc364068c0bbeafa561801acaeab2d225eefab0a09170;
    patterns[80] = 0xf07b8ce1705c3c528c349306f634631d29ccc642bc4f75cc85d292;
    patterns[81] = 0x2362fe5b3740e2d4e87f66c14d1f27a9e5c995e86a33fb2a018a45;
    patterns[82] = 0xee3e4fcf76f9e48161a3f7800503cf9e00c6265579ed58fa1fa04d;
    patterns[83] = 0x3e6c160065fee38988e78c8a3dd2c9b6bbdd24365af3ec2791d589;
    patterns[84] = 0xaada5342c675181e61e25e471aa89720d93ac56a61d0d9161988e0;
    patterns[85] = 0x5058693d7e6e7a30aa4c13c1202b8ef9ed8e3cbc0499996cf494af;
    patterns[86] = 0x82ddad00f4cfd2877a22bc2b4ac127dfa88f9a3f88bd27493e4cfd;
    patterns[87] = 0x12b41087295b6600097d07f200f7f66d04c7014e319f4face4ab1b;
    patterns[88] = 0x86b5c9990a8818113029c1ff36801832d45cdc3c4f30c393fa0a6a;
    patterns[89] = 0x3eb64c4944ccbe6e1adca87fa6565c4d58c92500161ca6a9090b02;
    patterns[90] = 0xecf64b4a983663cbb460553e05a7d2936794b7d02664e1499b8974;
    patterns[91] = 0x8e779b2fc38483aac3d0485dc4d95506289d4a97d63d1e80d47ecd;
    patterns[92] = 0x91da5f935ad6a5017ca5ef1d73ab8f434328f4a71dc1c5b749f10c;
    patterns[93] = 0x0be7d2f82ffde8ec9591ecf464f1c698727ce834b65dcce1c5e585;
    patterns[94] = 0x0b1559a092083c3216a5c9d163d9057991b63d7c3fd4b4baf1c3e0;
    patterns[95] = 0x64e5ff6c7e061c9fde09bfcb634b2e991a9ad154c503a953bcc938;
    patterns[96] = 0x21d5b7bd1febdd97b5152e20076c1b66ca2e27fcc7cdea9f60215c;
    patterns[97] = 0x0f54cd032e9a0b23994e6d0c6b3c29b821e03ecc4e7d14113ff0c9;
    patterns[98] = 0x0a0def1a8053fc65803119d7def8942b3ccd29e2593cb933ac041e;
    patterns[99] = 0xb4b5d540ae16e68d3722d56391d7ec52731e4a38129db0bed9531f;
    patterns[100] = 0xad960a4e173a9f6aeb338baf449b377dc903ce01bd2a99db1efb11;
    patterns[101] = 0x01a35b36de5cd6d1e7e0dde2f815f0fe1f9ef16d7fe326c3286a7c;
    patterns[102] = 0x69a92d94e6bd2fa474d1662f3f7737004254bae1915f99f134b63b;
    patterns[103] = 0x9135a33e33742b39d40bde4ae01a16f619d08fac0124b234a15ddb;
    patterns[104] = 0x0b2de6bc228289a7979910d129ef526127b08045731129456ea43d;
    patterns[105] = 0x263c7041632c06092990084eca90c23c17dce359b993f6fca796d7;
    patterns[106] = 0xc5e141a0e7c2c0794d07f0b63acddb97a1453682a65042a3f572cb;
    patterns[107] = 0x021471218c8b1713fa1c7c39a6f483a7f2820eb4b65bb2560c1b53;
    patterns[108] = 0xbc815e6719a912eaa9e5f85fe03b63e664ea451deb1ce2d2d7ea88;
    patterns[109] = 0x28ab6bcbc1d805573f79358c75beb679f3b762190fd9e30ea41065;
    patterns[110] = 0x48931db3445039a91cb944c0ca0358a30809421e10a53f8fd3cb74;
    patterns[111] = 0x3a2b0afd7e1cf824e27b2777cb3312f5864f1c0f6a10a4eeae0fa0;
    patterns[112] = 0x1ca85b67ae5d342a7f2890a650570644b097c5787edcce99317181;
    patterns[113] = 0x3aa3b7c9cffd6093d98c0938d8be4061858cff8251a2807bdd7b81;
    patterns[114] = 0x7cae615817e9e12e0841cc13d42a37edde53a804a8a62b23b8ff06;
    patterns[115] = 0xe1abe947762a6aef51d26083764ab26864bdf87cde27f8ac6f6a16;
    patterns[116] = 0xd7a5ba337ecad308e4acd39f37c9a72e986cde68c1969744a3bfa8;
    patterns[117] = 0x786b785ac0ebb35fd5b48963de9707598dbb0be56b28b4f8cfe618;
    patterns[118] = 0x8cc2799e25f2c86a52cbe63492586587a8994910f5de9c3e1915ab;
    patterns[119] = 0x5304cbfc7d47545cd503f55411b6c6fc4652caad2bb564c9f28360;
    patterns[120] = 0x8e795403f7a796a3dcaa143ab81ed2b29c79458e032f5ea2ee2f12;
    patterns[121] = 0x2c58547e0704a99147abf7260109203f7351dde17dc086f77a24b8;
    patterns[122] = 0x03ebdc91469ea837e126d5a2941fb0fc8780915c3fc0b6851bddee;
    patterns[123] = 0x16d7885b916ac7bd05255fbc324f19e1b9846a66f5853b554c779c;
    patterns[124] = 0x168e959b4fd93f890c3e6fef0521b57df12925c9bddfbfc6f9992c;
    patterns[125] = 0xe58499c74f9cfef729dc55eee2b509b341519a7f9c9663c1d11270;
    patterns[126] = 0xdfd76a8a95745051de63c50a19fd7361cc2da20412121a8cf5ae5d;
    patterns[127] = 0x7183e6042288c1c76435cd5a7b3d956faa7928f9aa8339f22198bb;
    patterns[128] = 0x87ac17f22c544e65e441ce4bab04151c0b0fbfb537a0d26af9548b;
    patterns[129] = 0x2321712dcf6d3490ef53048eef5adc87b4106e45b23fc2613e152a;
  }
}
