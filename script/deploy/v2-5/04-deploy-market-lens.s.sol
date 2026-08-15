// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/**
 * Environment:
 * - Both modes: DEPLOYMENTS_NETWORK; optional RELEASE_TAG (default v2-5),
 *   ARCH_CONTROLLER, and SKIP_EIP1153_CHECK. Script 02 must precede this script.
 * - Direct: OWNER_MODE=direct (default off mainnet), RPC_URL, and
 *   PVT_KEY_<NETWORK> (unless Foundry already has a configured sender).
 * - Plan: OWNER_MODE=plan, RPC_URL, and EXPECTED_EXECUTOR; no private key is required.
 *
 * Direct example:
 *   OWNER_MODE=direct DEPLOYMENTS_NETWORK=anvil RPC_URL=$RPC_URL PVT_KEY_ANVIL=$KEY forge script script/deploy/v2-5/04-deploy-market-lens.s.sol:DeployMarketLensV25 --rpc-url $RPC_URL --broadcast
 * Plan example:
 *   OWNER_MODE=plan DEPLOYMENTS_NETWORK=anvil EXPECTED_EXECUTOR=0x1234567890123456789012345678901234567890 forge script script/deploy/v2-5/04-deploy-market-lens.s.sol:DeployMarketLensV25 --rpc-url $RPC_URL
 */

import { console } from 'forge-std/console.sol';

import '../../common/DeployScriptBase.sol';

contract DeployMarketLensV25 is V25DeployScriptBase {
  string internal constant CORE_ARTIFACT = 'src/lens/MarketLensCore.sol:MarketLensCore';
  string internal constant AGGREGATOR_ARTIFACT =
    'src/lens/MarketLensAggregator.sol:MarketLensAggregator';
  string internal constant LIVE_ARTIFACT = 'src/lens/MarketLensLive.sol:MarketLensLive';
  string internal constant FACADE_ARTIFACT = 'src/lens/MarketLens.sol:MarketLens';

  string internal constant FACTORY_ENTRY_ID = 'deploy-hooks-factory-revolving';
  string internal constant FACTORY_OUTPUT = 'hooks-factory-standard';
  string internal constant CORE_ENTRY_ID = 'deploy-market-lens-core';
  string internal constant CORE_OUTPUT = 'market-lens-core';
  string internal constant AGGREGATOR_ENTRY_ID = 'deploy-market-lens-aggregator';
  string internal constant AGGREGATOR_OUTPUT = 'market-lens-aggregator';
  string internal constant LIVE_ENTRY_ID = 'deploy-market-lens-live';
  string internal constant LIVE_OUTPUT = 'market-lens-live';
  string internal constant FACADE_ENTRY_ID = 'deploy-market-lens';
  string internal constant FACADE_OUTPUT = 'market-lens';

  struct LensSet {
    address core;
    address aggregator;
    address live;
    address facade;
    bool didDeployCore;
    bool didDeployAggregator;
    bool didDeployLive;
    bool didDeployFacade;
  }

  function _twoAddressArgs(
    address first,
    string memory secondRef
  ) internal pure returns (string memory) {
    return string.concat('[', _quoted(vm.toString(first)), ',', _ref(secondRef), ']');
  }

  function _writeHelperPlanEntry(
    Deployments memory deployments,
    uint256 sequence,
    string memory id,
    string memory artifactName,
    string memory output,
    string memory description,
    string memory afterEntry,
    address archController
  ) internal {
    string[] memory afterEntries = new string[](1);
    afterEntries[0] = afterEntry;
    DeployPlanEntry memory entry;
    entry.sequence = sequence;
    entry.id = id;
    entry.artifactName = artifactName;
    entry.decodedConstructorArgs = _twoAddressArgs(archController, FACTORY_OUTPUT);
    entry.output = output;
    entry.description = description;
    entry.predicate = _planCallEqPredicate(
      output,
      'hooksFactory() view returns (address)',
      '[]',
      _ref(FACTORY_OUTPUT)
    );
    entry.afterEntries = afterEntries;
    _planEntry(deployments, entry);
  }

  function _writePlanEntries(Deployments memory deployments, address archController) internal {
    _writeHelperPlanEntry(
      deployments,
      9,
      CORE_ENTRY_ID,
      CORE_ARTIFACT,
      CORE_OUTPUT,
      'Deploy the v2.5 market-lens core helper.',
      FACTORY_ENTRY_ID,
      archController
    );
    _writeHelperPlanEntry(
      deployments,
      10,
      AGGREGATOR_ENTRY_ID,
      AGGREGATOR_ARTIFACT,
      AGGREGATOR_OUTPUT,
      'Deploy the v2.5 market-lens aggregation helper.',
      CORE_ENTRY_ID,
      archController
    );
    _writeHelperPlanEntry(
      deployments,
      11,
      LIVE_ENTRY_ID,
      LIVE_ARTIFACT,
      LIVE_OUTPUT,
      'Deploy the v2.5 market-lens live-data helper.',
      AGGREGATOR_ENTRY_ID,
      archController
    );

    string[] memory facadeAfter = new string[](1);
    facadeAfter[0] = LIVE_ENTRY_ID;
    DeployPlanEntry memory facadeEntry;
    facadeEntry.sequence = 12;
    facadeEntry.id = FACADE_ENTRY_ID;
    facadeEntry.artifactName = FACADE_ARTIFACT;
    facadeEntry.decodedConstructorArgs = string.concat(
      '[',
      _quoted(vm.toString(archController)),
      ',',
      _ref(FACTORY_OUTPUT),
      ',',
      _ref(CORE_OUTPUT),
      ',',
      _ref(AGGREGATOR_OUTPUT),
      ',',
      _ref(LIVE_OUTPUT),
      ']'
    );
    facadeEntry.output = FACADE_OUTPUT;
    facadeEntry.description = 'Deploy the v2.5 market-lens facade wired to its helpers.';
    facadeEntry.predicate = _planCallEqPredicate(
      FACADE_OUTPUT,
      'aggregationHelper() view returns (address)',
      '[]',
      _ref(AGGREGATOR_OUTPUT)
    );
    facadeEntry.afterEntries = facadeAfter;
    _planEntry(deployments, facadeEntry);
  }

  function _verifyHelper(
    address helper,
    string memory label,
    address archController,
    address hooksFactory
  ) internal view {
    _verifyAddressCall(
      helper,
      label,
      'archController',
      abi.encodeWithSignature('archController()'),
      archController
    );
    _verifyAddressCall(
      helper,
      label,
      'hooksFactory',
      abi.encodeWithSignature('hooksFactory()'),
      hooksFactory
    );
  }

  function _verifyFacade(
    address facade,
    string memory label,
    address archController,
    address hooksFactory,
    LensSet memory lens
  ) internal view {
    _verifyHelper(facade, label, archController, hooksFactory);
    _verifyAddressCall(
      facade,
      label,
      'coreHelper',
      abi.encodeWithSignature('coreHelper()'),
      lens.core
    );
    _verifyAddressCall(
      facade,
      label,
      'aggregationHelper',
      abi.encodeWithSignature('aggregationHelper()'),
      lens.aggregator
    );
    _verifyAddressCall(
      facade,
      label,
      'liveHelper',
      abi.encodeWithSignature('liveHelper()'),
      lens.live
    );
  }

  function _deployLensSet(
    Deployments memory deployments,
    address archController,
    address hooksFactory
  ) internal returns (LensSet memory lens) {
    bytes memory helperArgs = abi.encode(archController, hooksFactory);
    string memory coreLabel = _label('MarketLensCore');
    (lens.core, lens.didDeployCore) = _getOrDeployByLabel(
      deployments,
      coreLabel,
      CORE_ARTIFACT,
      _getCreationCode(deployments, CORE_ARTIFACT),
      helperArgs
    );
    _verifyHelper(lens.core, coreLabel, archController, hooksFactory);

    string memory aggregatorLabel = _label('MarketLensAggregator');
    (lens.aggregator, lens.didDeployAggregator) = _getOrDeployByLabel(
      deployments,
      aggregatorLabel,
      AGGREGATOR_ARTIFACT,
      _getCreationCode(deployments, AGGREGATOR_ARTIFACT),
      helperArgs
    );
    _verifyHelper(lens.aggregator, aggregatorLabel, archController, hooksFactory);

    string memory liveLabel = _label('MarketLensLive');
    (lens.live, lens.didDeployLive) = _getOrDeployByLabel(
      deployments,
      liveLabel,
      LIVE_ARTIFACT,
      _getCreationCode(deployments, LIVE_ARTIFACT),
      helperArgs
    );
    _verifyHelper(lens.live, liveLabel, archController, hooksFactory);

    string memory facadeLabel = _label('MarketLens');
    bytes memory facadeArgs = abi.encode(
      archController,
      hooksFactory,
      lens.core,
      lens.aggregator,
      lens.live
    );
    (lens.facade, lens.didDeployFacade) = _getOrDeployByLabel(
      deployments,
      facadeLabel,
      FACADE_ARTIFACT,
      _getCreationCode(deployments, FACADE_ARTIFACT),
      facadeArgs
    );
    _verifyFacade(lens.facade, facadeLabel, archController, hooksFactory, lens);
  }

  function _writeInventoryRecord(
    Deployments memory deployments,
    string memory networkName,
    uint256 sequence,
    string memory name,
    string memory role,
    address deployment
  ) internal {
    string memory label = _label(name);
    string memory recordJson = string.concat(
      '{"recordType":"deployment","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"role":',
      _quoted(role),
      ',"deploymentKey":',
      _quoted(label),
      ',"address":',
      _quoted(vm.toString(deployment)),
      '}'
    );
    _inventoryRecord(deployments, sequence, label, recordJson);
  }

  function _writeInventoryRecords(
    Deployments memory deployments,
    string memory networkName,
    LensSet memory lens
  ) internal {
    _writeInventoryRecord(deployments, networkName, 9, 'MarketLensCore', 'core', lens.core);
    _writeInventoryRecord(
      deployments,
      networkName,
      10,
      'MarketLensAggregator',
      'aggregator',
      lens.aggregator
    );
    _writeInventoryRecord(deployments, networkName, 11, 'MarketLensLive', 'live', lens.live);
    _writeInventoryRecord(deployments, networkName, 12, 'MarketLens', 'facade', lens.facade);
  }

  function _writePlanInventoryRecord(
    Deployments memory deployments,
    string memory networkName,
    uint256 sequence,
    string memory name,
    string memory role,
    string memory output
  ) internal {
    string memory label = _label(name);
    string memory recordJson = string.concat(
      '{"recordType":"deployment","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"role":',
      _quoted(role),
      ',"deploymentKey":',
      _quoted(label),
      ',"address":',
      _ref(output),
      '}'
    );
    _inventoryRecord(deployments, sequence, label, recordJson);
  }

  function _writePlanInventoryRecords(
    Deployments memory deployments,
    string memory networkName
  ) internal {
    _writePlanInventoryRecord(deployments, networkName, 9, 'MarketLensCore', 'core', CORE_OUTPUT);
    _writePlanInventoryRecord(
      deployments,
      networkName,
      10,
      'MarketLensAggregator',
      'aggregator',
      AGGREGATOR_OUTPUT
    );
    _writePlanInventoryRecord(deployments, networkName, 11, 'MarketLensLive', 'live', LIVE_OUTPUT);
    _writePlanInventoryRecord(deployments, networkName, 12, 'MarketLens', 'facade', FACADE_OUTPUT);
  }

  function run() external {
    string memory ownerMode = _ownerMode();
    (Deployments memory deployments, string memory networkName) = _resolveDeployments();
    address archController = _resolveExisting(
      deployments,
      'WildcatArchController',
      'ARCH_CONTROLLER'
    );

    if (_isPlanMode(ownerMode)) {
      _writePlanEntries(deployments, archController);
      _writePlanInventoryRecords(deployments, networkName);
      return;
    }

    _assertEip1153Supported();
    string memory factoryLabel = _label('HooksFactory');
    if (!deployments.has(factoryLabel)) {
      revert(string.concat('Missing ', factoryLabel, '; run deployment script 02 first'));
    }
    address hooksFactory = deployments.get(factoryLabel);
    _requireCode(hooksFactory, factoryLabel);

    LensSet memory lens = _deployLensSet(deployments, archController, hooksFactory);
    deployments.write();
    _writeInventoryRecords(deployments, networkName, lens);

    console.log('MarketLens:', lens.facade);
    console.log('MarketLensCore:', lens.core);
    console.log('MarketLensAggregator:', lens.aggregator);
    console.log('MarketLensLive:', lens.live);
    console.log('Did deploy MarketLens:', lens.didDeployFacade);
    console.log('Did deploy MarketLensCore:', lens.didDeployCore);
    console.log('Did deploy MarketLensAggregator:', lens.didDeployAggregator);
    console.log('Did deploy MarketLensLive:', lens.didDeployLive);
  }
}
