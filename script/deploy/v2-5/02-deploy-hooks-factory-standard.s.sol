// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/**
 * Environment:
 * - Both modes: DEPLOYMENTS_NETWORK; optional RELEASE_TAG (default v2-5),
 *   ARCH_CONTROLLER, SANCTIONS_SENTINEL, WRAPPER_FACTORY, and
 *   SKIP_EIP1153_CHECK. Script 01 must precede this script.
 * - Direct: OWNER_MODE=direct (default off mainnet), RPC_URL, and
 *   PVT_KEY_<NETWORK> (unless Foundry already has a configured sender).
 * - Plan: OWNER_MODE=plan, RPC_URL, and EXPECTED_EXECUTOR; no private key is required.
 *
 * Direct example:
 *   OWNER_MODE=direct DEPLOYMENTS_NETWORK=anvil RPC_URL=$RPC_URL PVT_KEY_ANVIL=$KEY forge script script/deploy/v2-5/02-deploy-hooks-factory-standard.s.sol:DeployHooksFactoryStandardV25 --rpc-url $RPC_URL --broadcast
 * Plan example:
 *   OWNER_MODE=plan DEPLOYMENTS_NETWORK=anvil EXPECTED_EXECUTOR=0x1234567890123456789012345678901234567890 forge script script/deploy/v2-5/02-deploy-hooks-factory-standard.s.sol:DeployHooksFactoryStandardV25 --rpc-url $RPC_URL
 */

import { console } from 'forge-std/console.sol';

import { IHooksFactory } from 'src/IHooksFactory.sol';

import '../../common/DeployScriptBase.sol';

contract DeployHooksFactoryStandardV25 is V25DeployScriptBase {
  string internal constant MARKET_ARTIFACT = 'src/market/WildcatMarket.sol:WildcatMarket';
  string internal constant FACTORY_ARTIFACT = 'src/HooksFactory.sol:HooksFactory';
  string internal constant INIT_CODE_STORAGE_ARTIFACT =
    'script/common/DeployScriptBase.sol:InitCodeStorage';

  string internal constant WRAPPER_ENTRY_ID = 'deploy-wildcat-4626-wrapper-factory';
  string internal constant WRAPPER_OUTPUT = 'wildcat-4626-wrapper-factory';
  string internal constant STORAGE_ENTRY_ID = 'deploy-wildcat-market-init-code-storage';
  string internal constant STORAGE_OUTPUT = 'wildcat-market-init-code-storage';
  string internal constant FACTORY_ENTRY_ID = 'deploy-hooks-factory-standard';
  string internal constant FACTORY_OUTPUT = 'hooks-factory-standard';

  struct DeploymentInputs {
    address archController;
    address sanctionsSentinel;
    address wrapperFactory;
    bytes marketCreationCode;
    uint256 initCodeHash;
  }

  function _verifyFactory(
    address factory,
    string memory label,
    address archController,
    address sanctionsSentinel,
    address wrapperFactory,
    address initCodeStorage,
    uint256 initCodeHash
  ) internal view {
    _verifyAddressCall(
      factory,
      label,
      'archController',
      abi.encodeWithSelector(IHooksFactory.archController.selector),
      archController
    );
    _verifyAddressCall(
      factory,
      label,
      'sanctionsSentinel',
      abi.encodeWithSelector(IHooksFactory.sanctionsSentinel.selector),
      sanctionsSentinel
    );
    _verifyAddressCall(
      factory,
      label,
      'wrapperFactory',
      abi.encodeWithSelector(IHooksFactory.wrapperFactory.selector),
      wrapperFactory
    );
    _verifyAddressCall(
      factory,
      label,
      'marketInitCodeStorage',
      abi.encodeWithSelector(IHooksFactory.marketInitCodeStorage.selector),
      initCodeStorage
    );
    _verifyUintCall(
      factory,
      label,
      'marketInitCodeHash',
      abi.encodeWithSelector(IHooksFactory.marketInitCodeHash.selector),
      initCodeHash
    );
  }

  function _writePlanEntries(
    Deployments memory deployments,
    DeploymentInputs memory inputs
  ) internal {
    string[] memory storageAfter = new string[](1);
    storageAfter[0] = WRAPPER_ENTRY_ID;
    DeployPlanEntry memory storageEntry;
    storageEntry.sequence = 2;
    storageEntry.id = STORAGE_ENTRY_ID;
    storageEntry.artifactName = INIT_CODE_STORAGE_ARTIFACT;
    storageEntry.decodedConstructorArgs = string.concat(
      '[',
      _quoted(vm.toString(inputs.marketCreationCode)),
      ']'
    );
    storageEntry.output = STORAGE_OUTPUT;
    storageEntry.description = 'Deploy the v2.5 WildcatMarket init-code storage contract.';
    storageEntry.predicate = _planCodePresentPredicate(STORAGE_OUTPUT);
    storageEntry.afterEntries = storageAfter;
    _planEntry(deployments, storageEntry);

    string[] memory factoryAfter = new string[](1);
    factoryAfter[0] = STORAGE_ENTRY_ID;
    DeployPlanEntry memory factoryEntry;
    factoryEntry.sequence = 3;
    factoryEntry.id = FACTORY_ENTRY_ID;
    factoryEntry.artifactName = FACTORY_ARTIFACT;
    factoryEntry.decodedConstructorArgs = string.concat(
      '[',
      _quoted(vm.toString(inputs.archController)),
      ',',
      _quoted(vm.toString(inputs.sanctionsSentinel)),
      ',',
      _ref(WRAPPER_OUTPUT),
      ',',
      _ref(STORAGE_OUTPUT),
      ',',
      _quoted(vm.toString(bytes32(inputs.initCodeHash))),
      ']'
    );
    factoryEntry.output = FACTORY_OUTPUT;
    factoryEntry.description = 'Deploy the v2.5 standard hooks factory.';
    factoryEntry.predicate = _planCallEqPredicate(
      FACTORY_OUTPUT,
      'marketInitCodeStorage() view returns (address)',
      '[]',
      _ref(STORAGE_OUTPUT)
    );
    factoryEntry.afterEntries = factoryAfter;
    _planEntry(deployments, factoryEntry);
  }

  function _writeInventoryRecords(
    Deployments memory deployments,
    string memory networkName,
    string memory storageLabel,
    address initCodeStorage,
    string memory factoryLabel,
    address factory,
    address wrapperFactory,
    uint256 initCodeHash
  ) internal {
    string memory storageRecord = string.concat(
      '{"recordType":"initCodeStorage","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"deploymentKey":',
      _quoted(storageLabel),
      ',"address":',
      _quoted(vm.toString(initCodeStorage)),
      ',"initCodeHash":',
      _quoted(vm.toString(bytes32(initCodeHash))),
      '}'
    );
    _inventoryRecord(deployments, 2, storageLabel, storageRecord);

    string memory factoryRecord = string.concat(
      '{"recordType":"hooksFactory","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"marketType":"legacy","deploymentKey":',
      _quoted(factoryLabel),
      ',"address":',
      _quoted(vm.toString(factory)),
      ',"wrapperFactory":',
      _quoted(vm.toString(wrapperFactory)),
      ',"initCodeStorage":',
      _quoted(vm.toString(initCodeStorage)),
      ',"initCodeHash":',
      _quoted(vm.toString(bytes32(initCodeHash))),
      ',"canonicalIntent":true}'
    );
    _inventoryRecord(deployments, 3, factoryLabel, factoryRecord);
  }

  function _writePlanInventoryRecords(
    Deployments memory deployments,
    string memory networkName,
    uint256 initCodeHash
  ) internal {
    string memory storageLabel = _label('WildcatMarket_initCodeStorage');
    string memory storageRecord = string.concat(
      '{"recordType":"initCodeStorage","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"deploymentKey":',
      _quoted(storageLabel),
      ',"address":',
      _ref(STORAGE_OUTPUT),
      ',"initCodeHash":',
      _quoted(vm.toString(bytes32(initCodeHash))),
      '}'
    );
    _inventoryRecord(deployments, 2, storageLabel, storageRecord);

    string memory factoryLabel = _label('HooksFactory');
    string memory factoryRecord = string.concat(
      '{"recordType":"hooksFactory","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"marketType":"legacy","deploymentKey":',
      _quoted(factoryLabel),
      ',"address":',
      _ref(FACTORY_OUTPUT),
      ',"wrapperFactory":',
      _ref(WRAPPER_OUTPUT),
      ',"initCodeStorage":',
      _ref(STORAGE_OUTPUT),
      ',"initCodeHash":',
      _quoted(vm.toString(bytes32(initCodeHash))),
      ',"registerEntryId":"register-hooks-factory-standard","canonicalIntent":true}'
    );
    _inventoryRecord(deployments, 3, factoryLabel, factoryRecord);
  }

  function _runDirect(
    Deployments memory deployments,
    string memory networkName,
    DeploymentInputs memory inputs
  ) internal {
    _assertEip1153Supported();
    string memory storageLabel = _label('WildcatMarket_initCodeStorage');
    string memory factoryLabel = _label('HooksFactory');
    (address initCodeStorage, bool didDeployStorage) = _getOrDeployInitCodeStorageByLabel(
      deployments,
      storageLabel,
      MARKET_ARTIFACT,
      inputs.marketCreationCode
    );
    bytes memory constructorArgs = abi.encode(
      inputs.archController,
      inputs.sanctionsSentinel,
      inputs.wrapperFactory,
      initCodeStorage,
      inputs.initCodeHash
    );
    bytes memory factoryCreationCode = _getCreationCode(deployments, FACTORY_ARTIFACT);
    (address factory, bool didDeployFactory) = _getOrDeployByLabel(
      deployments,
      factoryLabel,
      FACTORY_ARTIFACT,
      factoryCreationCode,
      constructorArgs
    );
    _verifyFactory(
      factory,
      factoryLabel,
      inputs.archController,
      inputs.sanctionsSentinel,
      inputs.wrapperFactory,
      initCodeStorage,
      inputs.initCodeHash
    );
    console.log(string.concat('Found and fully verified ', factoryLabel, ' at'), factory);

    deployments.write();
    _writeInventoryRecords(
      deployments,
      networkName,
      storageLabel,
      initCodeStorage,
      factoryLabel,
      factory,
      inputs.wrapperFactory,
      inputs.initCodeHash
    );

    console.log('Did deploy WildcatMarket init-code storage:', didDeployStorage);
    console.log('Did deploy HooksFactory:', didDeployFactory);
  }

  function run() external {
    string memory ownerMode = _ownerMode();
    (Deployments memory deployments, string memory networkName) = _resolveDeployments();
    DeploymentInputs memory inputs;
    inputs.archController = _resolveExisting(
      deployments,
      'WildcatArchController',
      'ARCH_CONTROLLER'
    );
    inputs.sanctionsSentinel = _resolveExisting(
      deployments,
      'WildcatSanctionsSentinel',
      'SANCTIONS_SENTINEL'
    );
    inputs.marketCreationCode = _getCreationCode(deployments, MARKET_ARTIFACT);
    inputs.initCodeHash = uint256(keccak256(inputs.marketCreationCode));

    if (_isPlanMode(ownerMode)) {
      _writePlanEntries(deployments, inputs);
      _writePlanInventoryRecords(deployments, networkName, inputs.initCodeHash);
      return;
    }

    inputs.wrapperFactory = _resolveExisting(
      deployments,
      _label('Wildcat4626WrapperFactory'),
      'WRAPPER_FACTORY'
    );
    _runDirect(deployments, networkName, inputs);
  }
}
