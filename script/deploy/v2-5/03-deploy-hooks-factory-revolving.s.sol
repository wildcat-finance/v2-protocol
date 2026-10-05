// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // 03-deploy-hooks-factory-revolving.s
//  \ ^ /   Revolving hooks-factory deployment and release inventory.
//    V
//
//  DEPLOYMENT
//  run()
//
//  DEPLOYMENT PLAN
//  _writePlanEntries(...)
//
//  DIRECT DEPLOYMENT
//  _runDirect(...)
//  _verifyFactory(...)
//
//  INVENTORY RECORDS
//  _writePlanInventoryRecords(...)
//  _writeInventoryRecords(...)
// ═════

// environment:
// - both modes: DEPLOYMENTS_NETWORK; optional RELEASE_TAG (default v2-5),
//   ARCH_CONTROLLER, SANCTIONS_SENTINEL, WRAPPER_FACTORY, and
//   SKIP_EIP1153_CHECK. scripts 01 and 02 must precede this script.
// - direct: OWNER_MODE=direct (default off mainnet), RPC_URL, and
//   PVT_KEY_<NETWORK> (unless Foundry already has a configured sender).
// - plan: OWNER_MODE=plan, RPC_URL, and EXPECTED_EXECUTOR; no private key is required.
//
// direct example:
//   OWNER_MODE=direct DEPLOYMENTS_NETWORK=anvil RPC_URL=$RPC_URL PVT_KEY_ANVIL=$KEY forge script script/deploy/v2-5/03-deploy-hooks-factory-revolving.s.sol:DeployHooksFactoryRevolvingV25 --rpc-url $RPC_URL --broadcast
// plan example:
//   OWNER_MODE=plan DEPLOYMENTS_NETWORK=anvil EXPECTED_EXECUTOR=0x1234567890123456789012345678901234567890 forge script script/deploy/v2-5/03-deploy-hooks-factory-revolving.s.sol:DeployHooksFactoryRevolvingV25 --rpc-url $RPC_URL

import { console } from 'forge-std/console.sol';

import { IHooksFactoryRevolving } from 'src/IHooksFactoryRevolving.sol';

import '../../common/DeployScriptBase.sol';

// ┌─ DeployHooksFactoryRevolvingV25 ───────────────────────────────────────────
contract DeployHooksFactoryRevolvingV25 is V25DeployScriptBase {
  string internal constant MARKET_ARTIFACT = 'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving';
  string internal constant FACTORY_ARTIFACT = 'src/HooksFactoryRevolving.sol:HooksFactoryRevolving';

  string internal constant STANDARD_FACTORY_ENTRY_ID = 'deploy-hooks-factory-standard';
  string internal constant WRAPPER_OUTPUT = 'wildcat-4626-wrapper-factory';
  string internal constant IDENTITY_REGISTRY_OUTPUT = 'borrower-identity-registry';
  string internal constant STORAGE_ENTRY_ID = 'deploy-wildcat-market-revolving-init-code-storage';
  string internal constant STORAGE_OUTPUT = 'wildcat-market-revolving-init-code-storage';
  string internal constant FACTORY_ENTRY_ID = 'deploy-hooks-factory-revolving';
  string internal constant FACTORY_OUTPUT = 'hooks-factory-revolving';

  struct DeploymentInputs {
    address archController;
    address sanctionsSentinel;
    address wrapperFactory;
    address borrowerIdentityRegistry;
    bytes marketCreationCode;
    uint256 initCodeHash;
  }

  // ░░▒▒▓▓██ [ DEPLOYMENT ] ───────────────────────────────────────────────────

  // ┌─ run ─────
  function run() external {
    string memory ownerMode = _ownerMode();
    (Deployments memory deployments, string memory networkName) = _resolveDeployments();
    DeploymentInputs memory inputs;
    inputs.archController = _resolveExisting(deployments, 'WildcatArchController', 'ARCH_CONTROLLER');
    inputs.sanctionsSentinel = _resolveExisting(deployments, 'WildcatSanctionsSentinel', 'SANCTIONS_SENTINEL');
    inputs.marketCreationCode = _getCreationCode(deployments, MARKET_ARTIFACT);
    _requireInitCodeStoragePayloadFits(inputs.marketCreationCode, MARKET_ARTIFACT);
    inputs.initCodeHash = uint256(keccak256(inputs.marketCreationCode));

    if (_isPlanMode(ownerMode)) {
      _writePlanEntries(deployments, inputs);
      _writePlanInventoryRecords(deployments, networkName, inputs.initCodeHash, inputs.marketCreationCode);
      return;
    }

    inputs.wrapperFactory = _resolveExisting(deployments, _label('Wildcat4626WrapperFactory'), 'WRAPPER_FACTORY');
    inputs.borrowerIdentityRegistry =
      _resolveExisting(deployments, _label('WildcatBorrowerIdentityRegistry'), 'BORROWER_IDENTITY_REGISTRY');
    _runDirect(deployments, networkName, inputs);
  }

  // ░░▒▒▓▓██ [ DEPLOYMENT PLAN ] ──────────────────────────────────────────────

  // ┌─ _writePlanEntries ─────
  function _writePlanEntries(Deployments memory deployments, DeploymentInputs memory inputs) internal {
    string[] memory storageAfter = new string[](1);
    storageAfter[0] = STANDARD_FACTORY_ENTRY_ID;
    DeployPlanEntry memory storageEntry;
    storageEntry.sequence = 6;
    storageEntry.id = STORAGE_ENTRY_ID;
    storageEntry.output = STORAGE_OUTPUT;
    storageEntry.description = 'Deploy the v2.5 WildcatMarketRevolving init-code storage contract.';
    storageEntry.afterEntries = storageAfter;
    _planInitCodeStorageEntry(deployments, storageEntry, inputs.marketCreationCode);

    string[] memory factoryAfter = new string[](1);
    factoryAfter[0] = STORAGE_ENTRY_ID;
    DeployPlanEntry memory factoryEntry;
    factoryEntry.sequence = 7;
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
      ',',
      _ref(IDENTITY_REGISTRY_OUTPUT),
      ']'
    );
    factoryEntry.output = FACTORY_OUTPUT;
    factoryEntry.description = 'Deploy the v2.5 revolving hooks factory.';
    factoryEntry.predicate = _planCallEqPredicate(
      FACTORY_OUTPUT, 'marketInitCodeStorage() view returns (address)', '[]', _ref(STORAGE_OUTPUT)
    );
    factoryEntry.afterEntries = factoryAfter;
    _planEntry(deployments, factoryEntry);
  }

  // ░░▒▒▓▓██ [ DIRECT DEPLOYMENT ] ────────────────────────────────────────────

  // ┌─ _runDirect ─────
  function _runDirect(
    Deployments memory deployments,
    string memory networkName,
    DeploymentInputs memory inputs
  )
    internal
  {
    _assertEip1153Supported();
    string memory storageLabel = _label('WildcatMarketRevolving_initCodeStorage');
    string memory factoryLabel = _label('HooksFactoryRevolving');
    (address initCodeStorage, bool didDeployStorage) =
      _getOrDeployInitCodeStorageByLabel(deployments, storageLabel, MARKET_ARTIFACT, inputs.marketCreationCode);
    bytes memory constructorArgs = abi.encode(
      inputs.archController,
      inputs.sanctionsSentinel,
      inputs.wrapperFactory,
      initCodeStorage,
      inputs.initCodeHash,
      inputs.borrowerIdentityRegistry
    );
    bytes memory factoryCreationCode = _getCreationCode(deployments, FACTORY_ARTIFACT);
    (address factory, bool didDeployFactory) =
      _getOrDeployByLabel(deployments, factoryLabel, FACTORY_ARTIFACT, factoryCreationCode, constructorArgs);
    _verifyFactory(
      factory,
      factoryLabel,
      inputs.archController,
      inputs.sanctionsSentinel,
      inputs.wrapperFactory,
      inputs.borrowerIdentityRegistry,
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
      inputs.borrowerIdentityRegistry,
      inputs.initCodeHash
    );

    console.log('Did deploy WildcatMarketRevolving init-code storage:', didDeployStorage);
    console.log('Did deploy HooksFactoryRevolving:', didDeployFactory);
  }

  // ┌─ _verifyFactory ─────
  function _verifyFactory(
    address factory,
    string memory label,
    address archController,
    address sanctionsSentinel,
    address wrapperFactory,
    address borrowerIdentityRegistry,
    address initCodeStorage,
    uint256 initCodeHash
  )
    internal
    view
  {
    _verifyAddressCall(
      factory,
      label,
      'archController',
      abi.encodeWithSelector(IHooksFactoryRevolving.archController.selector),
      archController
    );
    _verifyAddressCall(
      factory,
      label,
      'sanctionsSentinel',
      abi.encodeWithSelector(IHooksFactoryRevolving.sanctionsSentinel.selector),
      sanctionsSentinel
    );
    _verifyAddressCall(
      factory,
      label,
      'wrapperFactory',
      abi.encodeWithSelector(IHooksFactoryRevolving.wrapperFactory.selector),
      wrapperFactory
    );
    _verifyAddressCall(
      factory,
      label,
      'borrowerIdentityRegistry',
      abi.encodeWithSelector(IHooksFactoryRevolving.borrowerIdentityRegistry.selector),
      borrowerIdentityRegistry
    );
    _verifyAddressCall(
      factory,
      label,
      'marketInitCodeStorage',
      abi.encodeWithSelector(IHooksFactoryRevolving.marketInitCodeStorage.selector),
      initCodeStorage
    );
    _verifyUintCall(
      factory,
      label,
      'marketInitCodeHash',
      abi.encodeWithSelector(IHooksFactoryRevolving.marketInitCodeHash.selector),
      initCodeHash
    );
  }

  // ░░▒▒▓▓██ [ INVENTORY RECORDS ] ────────────────────────────────────────────

  // ┌─ _writePlanInventoryRecords ─────
  function _writePlanInventoryRecords(
    Deployments memory deployments,
    string memory networkName,
    uint256 initCodeHash,
    bytes memory creationCode
  )
    internal
  {
    string memory storageLabel = _label('WildcatMarketRevolving_initCodeStorage');
    _writePlanInitCodeStorageInventory(deployments, 6, networkName, storageLabel, STORAGE_OUTPUT, creationCode);

    string memory factoryLabel = _label('HooksFactoryRevolving');
    string memory factoryRecord = string.concat(
      '{"recordType":"hooksFactory","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"marketType":"revolving","deploymentKey":',
      _quoted(factoryLabel),
      ',"address":',
      _ref(FACTORY_OUTPUT),
      ',"wrapperFactory":',
      _ref(WRAPPER_OUTPUT),
      ',"borrowerIdentityRegistry":',
      _ref(IDENTITY_REGISTRY_OUTPUT),
      ',"initCodeStorage":',
      _ref(STORAGE_OUTPUT),
      ',"initCodeHash":',
      _quoted(vm.toString(bytes32(initCodeHash))),
      ',"registerEntryId":"register-hooks-factory-revolving","canonicalIntent":true}'
    );
    _inventoryRecord(deployments, 7, factoryLabel, factoryRecord);
  }

  // ┌─ _writeInventoryRecords ─────
  function _writeInventoryRecords(
    Deployments memory deployments,
    string memory networkName,
    string memory storageLabel,
    address initCodeStorage,
    string memory factoryLabel,
    address factory,
    address wrapperFactory,
    address borrowerIdentityRegistry,
    uint256 initCodeHash
  )
    internal
  {
    _writeLiveInitCodeStorageInventory(deployments, 6, networkName, storageLabel, initCodeStorage, initCodeHash);

    string memory factoryRecord = string.concat(
      '{"recordType":"hooksFactory","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"marketType":"revolving","deploymentKey":',
      _quoted(factoryLabel),
      ',"address":',
      _quoted(vm.toString(factory)),
      ',"wrapperFactory":',
      _quoted(vm.toString(wrapperFactory)),
      ',"borrowerIdentityRegistry":',
      _quoted(vm.toString(borrowerIdentityRegistry)),
      ',"initCodeStorage":',
      _quoted(vm.toString(initCodeStorage)),
      ',"initCodeHash":',
      _quoted(vm.toString(bytes32(initCodeHash))),
      ',"canonicalIntent":true}'
    );
    _inventoryRecord(deployments, 7, factoryLabel, factoryRecord);
  }
}
