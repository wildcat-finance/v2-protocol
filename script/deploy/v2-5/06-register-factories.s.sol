// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/**
 * Register both v2.5 hooks factories as ArchController controllers.
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
  string internal constant STANDARD_FACTORY_OUTPUT = 'hooks-factory-standard';
  string internal constant REVOLVING_FACTORY_OUTPUT = 'hooks-factory-revolving';
  string internal constant AFTER_OWNER_ACTIONS = 'add-revolving-periodic-term-template';
  string internal constant REGISTER_STANDARD_ENTRY_ID = 'register-hooks-factory-standard';
  string internal constant REGISTER_REVOLVING_ENTRY_ID = 'register-hooks-factory-revolving';

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

  function _registerStandard(Deployments memory deployments, address factory) internal {
    deployments.broadcast();
    IHooksFactory(factory).registerWithArchController();
  }

  function _registerRevolving(Deployments memory deployments, address factory) internal {
    deployments.broadcast();
    IHooksFactoryRevolving(factory).registerWithArchController();
  }

  function run() external {
    string memory ownerMode = _ownerMode();
    (Deployments memory deployments, ) = _resolveDeployments();
    address archControllerAddress = _resolveExisting(
      deployments,
      'WildcatArchController',
      'ARCH_CONTROLLER'
    );

    if (_isPlanMode(ownerMode)) {
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
      return;
    }

    string memory standardFactoryLabel = _label('HooksFactory');
    string memory revolvingFactoryLabel = _label('HooksFactoryRevolving');
    if (!deployments.has(standardFactoryLabel) || !deployments.has(revolvingFactoryLabel)) {
      revert('Missing v2.5 factories; run scripts 02 and 03 first');
    }
    address standardFactory = deployments.get(standardFactoryLabel);
    address revolvingFactory = deployments.get(revolvingFactoryLabel);
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
  }
}
