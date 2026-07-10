// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/**
 * Environment:
 * - Both modes: DEPLOYMENTS_NETWORK; optional RELEASE_TAG (default v2-5),
 *   ARCH_CONTROLLER, and SKIP_EIP1153_CHECK. The network factory inventory
 *   must contain one v1 wrapper record, or an explicit empty wrapperFactories array.
 * - Direct: OWNER_MODE=direct (default off mainnet), RPC_URL, and
 *   PVT_KEY_<NETWORK> (unless Foundry already has a configured sender).
 * - Plan: OWNER_MODE=plan and EXPECTED_EXECUTOR; no private key is required.
 *
 * Direct example:
 *   OWNER_MODE=direct DEPLOYMENTS_NETWORK=anvil RPC_URL=$RPC_URL PVT_KEY_ANVIL=$KEY forge script script/deploy/v2-5/04-deploy-wrapper-factory.s.sol:DeployWrapperFactoryV25 --rpc-url $RPC_URL --broadcast
 * Plan example:
 *   OWNER_MODE=plan DEPLOYMENTS_NETWORK=anvil EXPECTED_EXECUTOR=0x1234567890123456789012345678901234567890 forge script script/deploy/v2-5/04-deploy-wrapper-factory.s.sol:DeployWrapperFactoryV25
 */

import { console } from 'forge-std/console.sol';

import '../../common/DeployScriptBase.sol';

contract DeployWrapperFactoryV25 is V25DeployScriptBase {
  string internal constant FACTORY_ARTIFACT =
    'src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory';
  string internal constant LENS_ENTRY_ID = 'deploy-market-lens';
  string internal constant FACTORY_ENTRY_ID = 'deploy-wildcat-4626-wrapper-factory';
  string internal constant FACTORY_OUTPUT = 'wildcat-4626-wrapper-factory';

  function _verifyFactory(
    address factory,
    string memory label,
    address archController,
    address v1Factory
  ) internal view {
    _verifyAddressCall(
      factory,
      label,
      'archController',
      abi.encodeWithSignature('archController()'),
      archController
    );
    _verifyAddressCall(
      factory,
      label,
      'v1Factory',
      abi.encodeWithSignature('v1Factory()'),
      v1Factory
    );
  }

  function _writePlanEntry(
    Deployments memory deployments,
    address archController,
    address v1Factory
  ) internal {
    string[] memory afterEntries = new string[](1);
    afterEntries[0] = LENS_ENTRY_ID;
    DeployPlanEntry memory entry;
    entry.sequence = 9;
    entry.id = FACTORY_ENTRY_ID;
    entry.artifactName = FACTORY_ARTIFACT;
    entry.decodedConstructorArgs = string.concat(
      '[',
      _quoted(vm.toString(archController)),
      ',',
      _quoted(vm.toString(v1Factory)),
      ']'
    );
    entry.output = FACTORY_OUTPUT;
    entry.description = 'Deploy the v2.5 ERC-4626 wrapper factory facade.';
    entry.predicate = _planCallEqPredicate(
      FACTORY_OUTPUT,
      'v1Factory() view returns (address)',
      '[]',
      _quoted(vm.toString(v1Factory))
    );
    entry.afterEntries = afterEntries;
    _planEntry(deployments, entry);
  }

  function _writeInventoryRecord(
    Deployments memory deployments,
    string memory networkName,
    string memory label,
    address factory,
    address v1Factory
  ) internal {
    string memory v1FactoryJson = v1Factory == address(0)
      ? 'null'
      : _quoted(vm.toString(v1Factory));
    string memory recordJson = string.concat(
      '{"recordType":"wrapperFactory","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"deploymentKey":',
      _quoted(label),
      ',"address":',
      _quoted(vm.toString(factory)),
      ',"v1Factory":',
      v1FactoryJson,
      ',"canonicalIntent":true}'
    );
    _inventoryRecord(deployments, 9, label, recordJson);
  }

  function _writePlanInventoryRecord(
    Deployments memory deployments,
    string memory networkName,
    address v1Factory
  ) internal {
    string memory label = _label('Wildcat4626WrapperFactory');
    string memory v1FactoryJson = v1Factory == address(0)
      ? 'null'
      : _quoted(vm.toString(v1Factory));
    string memory recordJson = string.concat(
      '{"recordType":"wrapperFactory","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"deploymentKey":',
      _quoted(label),
      ',"address":',
      _ref(FACTORY_OUTPUT),
      ',"v1Factory":',
      v1FactoryJson,
      ',"canonicalIntent":true}'
    );
    _inventoryRecord(deployments, 9, label, recordJson);
  }

  function run() external {
    string memory ownerMode = _ownerMode();
    (Deployments memory deployments, string memory networkName) = _resolveDeployments();
    address archController = _resolveExisting(
      deployments,
      'WildcatArchController',
      'ARCH_CONTROLLER'
    );
    address v1Factory = _resolveV1WrapperFactory(deployments);

    if (_isPlanMode(ownerMode)) {
      _writePlanEntry(deployments, archController, v1Factory);
      _writePlanInventoryRecord(deployments, networkName, v1Factory);
      return;
    }

    _assertEip1153Supported();
    string memory label = _label('Wildcat4626WrapperFactory');
    bytes memory constructorArgs = abi.encode(archController, v1Factory);
    (address factory, bool didDeploy) = _getOrDeployByLabel(
      deployments,
      label,
      FACTORY_ARTIFACT,
      _getCreationCode(deployments, FACTORY_ARTIFACT),
      constructorArgs
    );
    _verifyFactory(factory, label, archController, v1Factory);
    console.log(string.concat('Found and fully verified ', label, ' at'), factory);

    deployments.write();
    _writeInventoryRecord(deployments, networkName, label, factory, v1Factory);
    console.log('V1 wrapper factory:', v1Factory);
    console.log('Did deploy Wildcat4626WrapperFactory:', didDeploy);
  }
}
