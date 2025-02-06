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

using LibString for address;
using LibString for string;
using LibString for uint;

string constant DeploymentsJsonFilePath = 'deployments.json';
bool constant RedoAllDeployments = false;

interface IEngine {
  function deactivateAllRules() external;

  function configureRules(bytes8 rules) external;

  function addAllowedPatterns(uint216[] calldata patterns) external;

  function grantRole(bytes32 role, address account) external;
}

contract DeployV2 is Script {
  function run() public virtual {
    // seedLender('LENDER_2', true, 12e18, 5e18, 2e18);
    // seedLender('LENDER_2', false, 13e18, 6e18, 2e18);
    // forceDeployLens();
    deployAll();

  }


  function addSphereXPatterns(Deployments memory deployments) internal {
    address archController = deployments.get('WildcatArchController');
    address sphereXEngine = WildcatArchController(archController).sphereXEngine();

    IEngine engine = IEngine(sphereXEngine);
    engine.grantRole(
      0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929,
      0x0C2914FD10086443A8800e2bB5258D4c463A88a0
    );
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

  function deployAll() internal virtual {
    Deployments memory deployments = getDeploymentsForNetwork('mainnet');
    // .withPrivateKeyVarName(
      // 'PVT_KEY'
    // );

    // addSphereXPatterns(deployments);

    // ========================================================================== //
    //                       Deployments for whole protocol                       //
    // ========================================================================== //
    address archController = deployments.get('WildcatArchController');

    // ========================================================================== //
    //                                Hooks Factory                               //
    // ========================================================================== //

    (address hooksFactory, bool didDeployHooksFactory) = _setUpHooksFactory(
      deployments,
      WildcatArchController(archController)
    );

    // ========================================================================== //
    //                                    Lens                                    //
    // ========================================================================== //
    deployments.getOrDeploy(
      'MarketLens',
      _getCreationCode(deployments, 'MarketLens'),
      abi.encode(archController, hooksFactory),
      didDeployHooksFactory
    );

/* -------------------------------------------------------------------------- */
/*                            Validate Deployments                            */
/* -------------------------------------------------------------------------- */

    HooksFactory factory = HooksFactory(hooksFactory);
    assertEq(factory.getHooksTemplatesCount(), 2, 'Wrong # of templates');
    address OpenTermHooks = deployments.get('OpenTermHooks_initCodeStorage');
    assertEq(factory.getHooksTemplates(0, 1)[0], OpenTermHooks, 'First template is not open term');

    address FixedTermHooks = deployments.get('FixedTermHooks_initCodeStorage');
    assertEq(
      factory.getHooksTemplates(1, 2)[0],
      FixedTermHooks,
      'Second template is not fixed term'
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

  /**
   * @dev Initializes the hooks factory, and registers the initial two templates.
   *      Intended to gracefully resume a deployment if it was interrupted, or if one of
   *      the transactions failed for some reason.
   *
   *      Steps:
   *      - Registers the hooks factory as a controller factory and initializes
   *        it with the arch controller, if either has not been done.
   *      - Deploys the OpenTermHooks template if it does not exist.
   *      - Deploys the FixedTermHooks template if it does not exist.
   *      - Registers the templates with the hooks factory if they're not already registered.
   *
   *      Requirements:
   *      - The arch controller must be deployed.
   *      - The caller must be the owner of the arch controller.
   */
  function _setUpHooksFactory(
    Deployments memory deployments,
    WildcatArchController archController
  ) internal returns (address hooksFactory, bool didDeployHooksFactory) {
    address sentinel = deployments.get('WildcatSanctionsSentinel');

    (
      address marketTemplate,
      bool didDeployMarketTemplate,
      uint256 marketInitCodeHash
    ) = _storeMarketInitCode(deployments);
    (hooksFactory, didDeployHooksFactory) = deployments.getOrDeploy(
      'HooksFactory',
      _getCreationCode(deployments, 'HooksFactory'),
      abi.encode(archController, sentinel, marketTemplate, marketInitCodeHash)
    );

    bool registerAsFactory = !archController.isRegisteredControllerFactory(hooksFactory);
    bool registerAsController = !archController.isRegisteredController(hooksFactory);
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

    address owner = archController.owner();
    if (registerAsFactory) {
      deployments.broadcast();
      archController.registerControllerFactory(hooksFactory);
    }
    if (registerAsController) {
      deployments.broadcast();
      HooksFactory(hooksFactory).registerWithArchController();
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
}
