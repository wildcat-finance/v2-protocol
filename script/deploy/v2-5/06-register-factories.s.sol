// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/**
 * Register both v2.5 hooks factories as ArchController controllers, then
 * disable every superseded hooks factory recorded as registered in the
 * reconciled factory inventory.
 *
 * Environment:
 * - Both modes: DEPLOYMENTS_NETWORK; optional RELEASE_TAG (default v2-5) and
 *   ARCH_CONTROLLER. Script 05 must precede this script.
 * - Direct: OWNER_MODE=direct (default off mainnet), RPC_URL, and
 *   PVT_KEY_<NETWORK>.
 * - Plan: OWNER_MODE=plan, RPC_URL, and EXPECTED_EXECUTOR; no private key is required.
 */

import { IHooksFactory } from 'src/IHooksFactory.sol';
import { IHooksFactoryRevolving } from 'src/IHooksFactoryRevolving.sol';
import { IWildcatArchController } from 'src/interfaces/IWildcatArchController.sol';

import '../../common/DeployScriptBase.sol';

contract RegisterFactoriesV25 is V25DeployScriptBase {
  struct FactoryDeactivationTarget {
    address factory;
    string label;
  }

  string internal constant STANDARD_FACTORY_OUTPUT = 'hooks-factory-standard';
  string internal constant REVOLVING_FACTORY_OUTPUT = 'hooks-factory-revolving';
  string internal constant AFTER_OWNER_ACTIONS = 'add-revolving-periodic-term-template';
  string internal constant REGISTER_STANDARD_ENTRY_ID = 'register-hooks-factory-standard';
  string internal constant REGISTER_REVOLVING_ENTRY_ID = 'register-hooks-factory-revolving';

  function _resolveFactoryDeactivationTargets(
    Deployments memory deployments,
    string memory networkName,
    address standardFactory,
    address revolvingFactory
  ) internal returns (FactoryDeactivationTarget[] memory targets) {
    string memory inventoryPath = pathJoin(deployments.dir, 'factory-inventory.json');
    string[] memory args = new string[](9);
    args[0] = 'node';
    args[1] = 'scripts/factory-inventory.js';
    args[2] = 'deactivation-targets';
    args[3] = '--network';
    args[4] = networkName;
    args[5] = '--input';
    args[6] = inventoryPath;
    args[7] = '--exclude';
    args[8] = string.concat(vm.toString(standardFactory), ',', vm.toString(revolvingFactory));
    targets = abi.decode(vm.parseJson(string(vm.ffi(args))), (FactoryDeactivationTarget[]));
  }

  function _deactivationEntryId(
    string memory role,
    uint256 index
  ) internal returns (string memory) {
    return string.concat('remove-superseded-', role, '-', _sequence(index + 1));
  }

  function _writePlanEntry(
    Deployments memory deployments,
    address archController,
    uint256 sequence,
    string memory entryId,
    string memory factoryOutput,
    string memory afterEntry,
    string memory description
  ) internal {
    string[] memory afterEntries = new string[](1);
    afterEntries[0] = afterEntry;
    CallPlanEntry memory entry;
    entry.sequence = sequence;
    entry.id = entryId;
    entry.to = _ref(factoryOutput);
    entry.functionSignature = 'registerWithArchController()';
    entry.decodedArgs = '[]';
    entry.description = description;
    entry.predicate = _planCallEqPredicateForTarget(
      _quoted(vm.toString(archController)),
      'isRegisteredController(address) view returns (bool)',
      string.concat('[', _ref(factoryOutput), ']'),
      'true'
    );
    entry.afterEntries = afterEntries;
    _callPlanEntry(deployments, entry);
  }

  function _writeDeactivationPlanEntry(
    Deployments memory deployments,
    address archController,
    FactoryDeactivationTarget memory target,
    uint256 sequence,
    string memory entryId,
    string memory afterEntry,
    bool removeFactoryRole
  ) internal {
    string[] memory afterEntries = new string[](1);
    afterEntries[0] = afterEntry;
    string memory factory = _quoted(vm.toString(target.factory));
    string memory argsJson = string.concat('[', factory, ']');
    CallPlanEntry memory entry;
    entry.sequence = sequence;
    entry.id = entryId;
    entry.to = _quoted(vm.toString(archController));
    entry.functionSignature = removeFactoryRole
      ? 'removeControllerFactory(address)'
      : 'removeController(address)';
    entry.decodedArgs = argsJson;
    entry.description = string.concat(
      removeFactoryRole
        ? 'Prevent the superseded hooks factory at '
        : 'Prevent the superseded hooks controller at ',
      vm.toString(target.factory),
      removeFactoryRole ? ' from re-registering as a controller.' : ' from registering new markets.'
    );
    entry.predicate = _planCallEqPredicateForTarget(
      _quoted(vm.toString(archController)),
      removeFactoryRole
        ? 'isRegisteredControllerFactory(address) view returns (bool)'
        : 'isRegisteredController(address) view returns (bool)',
      argsJson,
      'false'
    );
    entry.afterEntries = afterEntries;
    _callPlanEntry(deployments, entry);
  }

  function _writeDeactivationPlanEntries(
    Deployments memory deployments,
    address archController,
    FactoryDeactivationTarget[] memory targets
  ) internal {
    string memory afterEntry = REGISTER_REVOLVING_ENTRY_ID;
    for (uint256 i; i < targets.length; i++) {
      string memory removeFactoryEntryId = _deactivationEntryId('controller-factory', i);
      _writeDeactivationPlanEntry(
        deployments,
        archController,
        targets[i],
        23 + i * 2,
        removeFactoryEntryId,
        afterEntry,
        true
      );
      string memory removeControllerEntryId = _deactivationEntryId('controller', i);
      _writeDeactivationPlanEntry(
        deployments,
        archController,
        targets[i],
        24 + i * 2,
        removeControllerEntryId,
        removeFactoryEntryId,
        false
      );
      afterEntry = removeControllerEntryId;
    }
  }

  function _registerStandard(Deployments memory deployments, address factory) internal {
    deployments.broadcast();
    IHooksFactory(factory).registerWithArchController();
  }

  function _registerRevolving(Deployments memory deployments, address factory) internal {
    deployments.broadcast();
    IHooksFactoryRevolving(factory).registerWithArchController();
  }

  function _deactivateSupersededFactories(
    Deployments memory deployments,
    IWildcatArchController archController,
    FactoryDeactivationTarget[] memory targets
  ) internal {
    for (uint256 i; i < targets.length; i++) {
      address factory = targets[i].factory;
      if (archController.isRegisteredControllerFactory(factory)) {
        deployments.broadcast();
        archController.removeControllerFactory(factory);
      }
      if (archController.isRegisteredController(factory)) {
        deployments.broadcast();
        archController.removeController(factory);
      }
      if (
        archController.isRegisteredControllerFactory(factory) ||
        archController.isRegisteredController(factory)
      ) {
        revert('Superseded factory deactivation failed');
      }
    }
  }

  function run() external {
    string memory ownerMode = _ownerMode();
    (Deployments memory deployments, string memory networkName) = _resolveDeployments();
    address archControllerAddress = _resolveExisting(
      deployments,
      'WildcatArchController',
      'ARCH_CONTROLLER'
    );

    if (_isPlanMode(ownerMode)) {
      address existingStandardFactory = deployments.has(_label('HooksFactory'))
        ? deployments.get(_label('HooksFactory'))
        : address(0);
      address existingRevolvingFactory = deployments.has(_label('HooksFactoryRevolving'))
        ? deployments.get(_label('HooksFactoryRevolving'))
        : address(0);
      FactoryDeactivationTarget[] memory planTargets = _resolveFactoryDeactivationTargets(
        deployments,
        networkName,
        existingStandardFactory,
        existingRevolvingFactory
      );
      _writePlanEntry(
        deployments,
        archControllerAddress,
        21,
        REGISTER_STANDARD_ENTRY_ID,
        STANDARD_FACTORY_OUTPUT,
        AFTER_OWNER_ACTIONS,
        'Register the v2.5 standard hooks factory as an ArchController controller.'
      );
      _writePlanEntry(
        deployments,
        archControllerAddress,
        22,
        REGISTER_REVOLVING_ENTRY_ID,
        REVOLVING_FACTORY_OUTPUT,
        REGISTER_STANDARD_ENTRY_ID,
        'Register the v2.5 revolving hooks factory as an ArchController controller.'
      );
      _writeDeactivationPlanEntries(deployments, archControllerAddress, planTargets);
      return;
    }

    string memory standardFactoryLabel = _label('HooksFactory');
    string memory revolvingFactoryLabel = _label('HooksFactoryRevolving');
    if (!deployments.has(standardFactoryLabel) || !deployments.has(revolvingFactoryLabel)) {
      revert('Missing v2.5 factories; run scripts 02 and 03 first');
    }
    address standardFactory = deployments.get(standardFactoryLabel);
    address revolvingFactory = deployments.get(revolvingFactoryLabel);
    FactoryDeactivationTarget[] memory targets = _resolveFactoryDeactivationTargets(
      deployments,
      networkName,
      standardFactory,
      revolvingFactory
    );
    IWildcatArchController archController = IWildcatArchController(archControllerAddress);
    if (!archController.isRegisteredController(standardFactory)) {
      _registerStandard(deployments, standardFactory);
    }
    if (!archController.isRegisteredController(revolvingFactory)) {
      _registerRevolving(deployments, revolvingFactory);
    }
    if (
      !archController.isRegisteredController(standardFactory) ||
      !archController.isRegisteredController(revolvingFactory)
    ) revert('Factory controller registration failed');
    _deactivateSupersededFactories(deployments, archController, targets);
  }
}
