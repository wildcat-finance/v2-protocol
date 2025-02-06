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

using LibString for address;
using LibString for string;
using LibString for uint;

string constant DeploymentsJsonFilePath = 'deployments.json';
bool constant RedoAllDeployments = false;
MockArchControllerOwner constant OldOwner = MockArchControllerOwner(
  0xa476920af80B587f696734430227869795E2Ea78
);

interface IEngine {
  function deactivateAllRules() external;

  function configureRules(bytes8 rules) external;

  function addAllowedPatterns(uint216[] calldata patterns) external;
}

contract DeployV2 is Script {
  function run() public virtual {
    // seedLender('LENDER_2', true, 12e18, 5e18, 2e18);
    // seedLender('LENDER_2', false, 13e18, 6e18, 2e18);
    forceDeployLens();
  }

  function seedLender(string memory lenderName, bool openMarket, uint depositAmount, uint withdrawAmount, uint borrowAmount) internal {
    string memory lenderPvtKeyVarName = string.concat(lenderName, '_PVT_KEY');
    Deployments memory deployments = getDeploymentsForNetwork('sepolia').withPrivateKeyVarName(
      'PVT_KEY'
    );
    string memory marketLabel = openMarket ? 'op2TOK_market' : 'fx2TOK_market';
    address market = deployments.get(marketLabel);
    Lender memory lender = buildLender(lenderName, market);
    if (!openMarket) {
      OpenTermHooks hooks = OpenTermHooks(deployments.get('fx2TOK_hooks'));
      deployments.broadcast();
      hooks.grantRole(lender.account, uint32(block.timestamp));
      console.log(string.concat('Granted role to lender ', lender.account.toHexString()));
    }
    lender.deposit(depositAmount);
    if (!openMarket) lender.withdraw(withdrawAmount);
    
    if (borrowAmount > 0 ) {
      deployments.broadcast();
      lender.market.borrow(borrowAmount);
    }
  }

  function addCloseMarket() internal {
    Deployments memory deployments = getDeploymentsForNetwork('sepolia').withPrivateKeyVarName(
      'PVT_KEY'
    );

    IEngine engine = IEngine(0xCc65C2Ad8ab5b5c63489cfC77F782175E0c6A36e);
    uint216[] memory patterns = new uint216[](5);
    patterns[0] = 94418217012137984803774416703850667173250690997694159855897612912;
    patterns[1] = 92083039521021907843879083621254831642817523105040888014352789085;
    patterns[2] = 46697456462908571842451701755225422725380819403284149584678459579;
    patterns[3] = 55812322464611803823919095340941798065809022442869364620170712203;
    patterns[4] = 14451904267781507293472597357567865620281743582632039118805013802;
    deployments.broadcast();
    engine.addAllowedPatterns(patterns);
    console.log('Added close market pattern');
  }

  function deployMarketAddTwoRemoveOne() internal {
    Deployments memory deployments = getDeploymentsForNetwork('sepolia').withPrivateKeyVarName(
      'PVT_KEY'
    );
  }

  function forceDeployLens() internal {
    Deployments memory deployments = getDeploymentsForNetwork('sepolia').withPrivateKeyVarName(
      'PVT_KEY'
    );
    address archController = deployments.get('WildcatArchController');
    address hooksFactory = deployments.get('HooksFactory');
    deployments.deploy(
      'MarketLens',
      _getCreationCode(deployments, 'MarketLens'),
      abi.encode(archController, hooksFactory)
    );
    deployments.write();
  }

  function deployAll() internal virtual {
    Deployments memory deployments = getDeploymentsForNetwork('sepolia').withPrivateKeyVarName(
      'PVT_KEY'
    );

    // ========================================================================== //
    //                       Deployments for whole protocol                       //
    // ========================================================================== //
    address chainalysis = deployments.get('Chainalysis');
    (address archController, bool didDeployArchController) = deployments.getOrDeploy(
      'WildcatArchController',
      _getCreationCode(deployments, 'WildcatArchController'),
      RedoAllDeployments
    );
    // require(
    //   WildcatArchController(archController).owner() == address(OldOwner),
    //   'Ownership should be held by old owner'
    // );
    require(!didDeployArchController, 'Arch controller should already be deployed');
    require(
      archController == 0xC003f20F2642c76B81e5e1620c6D8cdEE826408f,
      'Invalid arch controller'
    );

    address archControllerOwner = WildcatArchController(archController).owner();

    console.log('Arch controller owner: ', archControllerOwner);

    (address sentinel, bool didDeploySentinel) = deployments.getOrDeploy(
      'WildcatSanctionsSentinel',
      _getCreationCode(deployments, 'WildcatSanctionsSentinel'),
      abi.encode(archController, chainalysis),
      didDeployArchController
    );
    require(!didDeploySentinel, 'Sentinel should already be deployed');

    // ========================================================================== //
    //                                Hooks Factory                               //
    // ========================================================================== //

    (
      address marketTemplate,
      bool didDeployMarketTemplate,
      uint256 marketInitCodeHash
    ) = _storeMarketInitCode(deployments);
    // require(didDeployMarketTemplate, 'Market template should be deployed');
    (address hooksFactory, bool didDeployHooksFactory) = deployments.getOrDeploy(
      'HooksFactory',
      _getCreationCode(deployments, 'HooksFactory'),
      abi.encode(archController, sentinel, marketTemplate, marketInitCodeHash),
      didDeployArchController
    );
    // require(didDeployHooksFactory, 'Hooks factory should be deployed');
    _setUpHooksFactory(
      deployments,
      WildcatArchController(archController),
      HooksFactory(hooksFactory)
    );
    _registerBorrower(deployments, 0xca732651410E915090d7A7D889A1E44eF4575fcE);

    // ========================================================================== //
    //                                    Lens                                    //
    // ========================================================================== //
    deployments.getOrDeploy(
      'MarketLens',
      _getCreationCode(deployments, 'MarketLens'),
      abi.encode(archController, hooksFactory),
      didDeployHooksFactory
    );

    /* --------------------------- mock token factory --------------------------- */
    (, bool didDeployMockERC20Factory) = deployments.getOrDeploy(
      'MockERC20Factory',
      _getCreationCode(deployments, 'MockERC20Factory'),
      RedoAllDeployments
    );
    require(!didDeployMockERC20Factory, 'Mock ERC20 factory should already be deployed');

    (, WildcatMarket market, ) = _createMarket({
      deployments: deployments,
      openTerm: true,
      restrictive: false
    });
    _createMarket({ deployments: deployments, openTerm: false, restrictive: true });
    _seedMarketFunctions(deployments, market);
    _returnOwnershipOfArchController(deployments);
    require(
      WildcatArchController(archController).owner() == address(OldOwner),
      'Ownership should be returned'
    );

    HooksFactory factory = HooksFactory(hooksFactory);
    assertEq(factory.getHooksTemplatesCount(), 2, 'Wrong # of templates');
    address OpenTermHooks = deployments.get('OpenTermHooks_initCodeStorage');
    assertEq(factory.getHooksTemplates(0, 1)[0], OpenTermHooks, 'First template is not open term');
    assertEq(
      factory.getMarketsForHooksTemplateCount(OpenTermHooks),
      1,
      'wrong # of markets for OpenTermHooks'
    );

    address FixedTermHooks = deployments.get('FixedTermHooks_initCodeStorage');
    assertEq(
      factory.getHooksTemplates(1, 2)[0],
      FixedTermHooks,
      'Second template is not fixed term'
    );
    assertEq(
      factory.getMarketsForHooksTemplateCount(FixedTermHooks),
      1,
      'wrong # of markets for FixedTermHooks'
    );
    deployments.write();
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

  function _registerBorrower(Deployments memory deployments, address borrower) internal virtual {
    WildcatArchController archController = WildcatArchController(
      deployments.get('WildcatArchController')
    );
    if (!archController.isRegisteredBorrower(borrower)) {
      address owner = archController.owner();
      deployments.broadcast();
      if (owner == address(OldOwner)) {
        OldOwner.registerBorrower(borrower);
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
    if (archController.owner() == address(OldOwner)) {
      deployments.broadcast();
      OldOwner.returnOwnership();
      console.log('Took ownership of arch-controller...');
    }
  }

  function _returnOwnershipOfArchController(Deployments memory deployments) internal {
    WildcatArchController archController = WildcatArchController(
      deployments.get('WildcatArchController')
    );
    if (archController.owner() != address(OldOwner)) {
      deployments.broadcast();
      archController.transferOwnership(address(OldOwner));
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

    if (registerAsFactory || registerAsController || addOpenTermTemplate || addFixedTermTemplate) {
      _takeOwnershipOfArchController(deployments);
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
    config.namePrefix = openTerm ? 'Open V2 ' : 'Fixed V2 ';
    config.symbolPrefix = openTerm ? 'op2' : 'fx2';
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

  function assertEq(uint a, uint b, string memory errorMessage) internal {
    if (a != b) {
      console.log(string.concat('Error: ', errorMessage));
      console.log(string.concat('Expected: ', a.toString()));
      console.log(string.concat('Actual: ', b.toString()));
      revert(string.concat('Error: ', errorMessage));
    }
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

  function _seedMarketFunctions(Deployments memory deployments, WildcatMarket market) internal {
    IEngine engine = IEngine(market.sphereXEngine());

    deployments.broadcast();
    engine.deactivateAllRules();
    console.log('Deactivated spherex engine');

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

      deployments.broadcast();
      console.log('Did force buyback');
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
}
