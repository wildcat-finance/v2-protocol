// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/**
 * Deploy the v2.5 hooks template init-code storages, then perform the owner
 * actions that make the new factories and templates available.
 *
 * Environment:
 * - Both modes: DEPLOYMENTS_NETWORK; optional RELEASE_TAG (default v2-5),
 *   ARCH_CONTROLLER, TEMPLATE_FEE_SOURCE_FACTORY, and TEMPLATE_FEE_RECIPIENT.
 *   Scripts 01-04 must precede this script.
 * - Direct: OWNER_MODE=direct (default off mainnet), RPC_URL, and
 *   PVT_KEY_<NETWORK>. The broadcaster must be the ArchController owner.
 * - Plan: OWNER_MODE=plan, RPC_URL, and EXPECTED_EXECUTOR; no private key is required.
 *
 * Sepolia direct-mode helper flow, before running this script:
 *   cast send "$HELPER_OWNER" 'returnOwnership()' --rpc-url "$RPC_URL" --private-key "$KEY"
 * Return ownership afterward with:
 *   cast send "$ARCH_CONTROLLER" 'transferOwnership(address)' "$HELPER_OWNER" --rpc-url "$RPC_URL" --private-key "$KEY"
 */

import { console } from 'forge-std/console.sol';

import { HooksTemplate, IHooksFactory } from 'src/IHooksFactory.sol';
import { IWildcatArchController } from 'src/interfaces/IWildcatArchController.sol';

import '../../common/DeployScriptBase.sol';

contract OwnerActionsV25 is V25DeployScriptBase {
  string internal constant FEE_PARAMETERS_PATH = 'deployments/template-fee-parameters.json';
  string internal constant INIT_CODE_STORAGE_ARTIFACT =
    'script/common/DeployScriptBase.sol:InitCodeStorage';
  string internal constant OPEN_TERM_ARTIFACT = 'src/access/OpenTermHooks.sol:OpenTermHooks';
  string internal constant FIXED_TERM_ARTIFACT = 'src/access/FixedTermHooks.sol:FixedTermHooks';
  string internal constant PERIODIC_TERM_ARTIFACT =
    'src/access/PeriodicTermHooks.sol:PeriodicTermHooks';

  string internal constant STANDARD_FACTORY_OUTPUT = 'hooks-factory-standard';
  string internal constant REVOLVING_FACTORY_OUTPUT = 'hooks-factory-revolving';
  string internal constant DEPLOYMENTS_COMPLETE_ENTRY_ID = 'deploy-market-lens';

  string internal constant OPEN_STORAGE_ENTRY_ID = 'deploy-open-term-hooks-init-code-storage';
  string internal constant OPEN_STORAGE_OUTPUT = 'open-term-hooks-init-code-storage';
  string internal constant FIXED_STORAGE_ENTRY_ID = 'deploy-fixed-term-hooks-init-code-storage';
  string internal constant FIXED_STORAGE_OUTPUT = 'fixed-term-hooks-init-code-storage';
  string internal constant PERIODIC_STORAGE_ENTRY_ID =
    'deploy-periodic-term-hooks-init-code-storage';
  string internal constant PERIODIC_STORAGE_OUTPUT = 'periodic-term-hooks-init-code-storage';

  string internal constant REGISTER_STANDARD_FACTORY_ENTRY_ID =
    'register-controller-factory-standard';
  string internal constant REGISTER_REVOLVING_FACTORY_ENTRY_ID =
    'register-controller-factory-revolving';
  string internal constant ADD_STANDARD_OPEN_ENTRY_ID = 'add-standard-open-term-template';
  string internal constant ADD_STANDARD_FIXED_ENTRY_ID = 'add-standard-fixed-term-template';
  string internal constant ADD_STANDARD_PERIODIC_ENTRY_ID = 'add-standard-periodic-term-template';
  string internal constant ADD_REVOLVING_OPEN_ENTRY_ID = 'add-revolving-open-term-template';
  string internal constant ADD_REVOLVING_FIXED_ENTRY_ID = 'add-revolving-fixed-term-template';
  string internal constant ADD_REVOLVING_PERIODIC_ENTRY_ID =
    'add-revolving-periodic-term-template';

  struct TemplateFeeParameters {
    address originationFeeAsset;
    uint80 originationFeeAmount;
    uint16 protocolFeeBips;
  }

  struct TemplateDeployment {
    string name;
    string artifactName;
    string deploymentLabel;
    address deployment;
    bytes creationCode;
    TemplateFeeParameters fees;
  }

  function _readTemplateFees(
    string memory parametersJson,
    string memory templateName
  ) internal returns (TemplateFeeParameters memory fees) {
    string memory prefix = string.concat('.templates.', templateName);
    fees.originationFeeAsset = vm.parseJsonAddress(
      parametersJson,
      string.concat(prefix, '.originationFeeAsset')
    );
    uint256 originationFeeAmount = vm.parseJsonUint(
      parametersJson,
      string.concat(prefix, '.originationFeeAmount')
    );
    uint256 protocolFeeBips = vm.parseJsonUint(
      parametersJson,
      string.concat(prefix, '.protocolFeeBips')
    );
    if (originationFeeAmount > type(uint80).max) revert('Template origination fee exceeds uint80');
    if (protocolFeeBips > type(uint16).max) revert('Template protocol fee exceeds uint16');
    fees.originationFeeAmount = uint80(originationFeeAmount);
    fees.protocolFeeBips = uint16(protocolFeeBips);
  }

  function _loadTemplate(
    Deployments memory deployments,
    string memory parametersJson,
    string memory name,
    string memory artifactName
  ) internal returns (TemplateDeployment memory template) {
    template.name = name;
    template.artifactName = artifactName;
    template.deploymentLabel = _label(string.concat(name, '_initCodeStorage'));
    template.creationCode = _getCreationCode(deployments, artifactName);
    template.fees = _readTemplateFees(parametersJson, name);
  }

  function _resolveFeeRecipient(
    Deployments memory deployments,
    string memory templateName
  ) internal returns (address recipient) {
    recipient = vm.envOr('TEMPLATE_FEE_RECIPIENT', address(0));
    if (recipient != address(0)) return recipient;

    address sourceFactory = vm.envOr('TEMPLATE_FEE_SOURCE_FACTORY', address(0));
    if (sourceFactory == address(0)) {
      sourceFactory = _resolveExisting(deployments, 'HooksFactory', 'TEMPLATE_FEE_SOURCE_FACTORY');
    }
    IHooksFactory factory = IHooksFactory(sourceFactory);
    address fallbackRecipient;
    address[] memory templates = factory.getHooksTemplates();
    for (uint256 i; i < templates.length; i++) {
      HooksTemplate memory details = factory.getHooksTemplateDetails(templates[i]);
      if (!details.enabled || details.feeRecipient == address(0)) continue;
      if (fallbackRecipient == address(0)) fallbackRecipient = details.feeRecipient;
      if (_sameStrings(details.name, templateName)) recipient = details.feeRecipient;
    }
    if (recipient == address(0)) recipient = fallbackRecipient;
    if (recipient == address(0)) {
      revert('Could not resolve template fee recipient; set TEMPLATE_FEE_RECIPIENT');
    }
  }

  function _writeTemplateStoragePlanEntry(
    Deployments memory deployments,
    string memory networkName,
    TemplateDeployment memory template,
    uint256 sequence,
    string memory entryId,
    string memory output,
    string memory afterEntry
  ) internal {
    string[] memory afterEntries = new string[](1);
    afterEntries[0] = afterEntry;
    DeployPlanEntry memory entry;
    entry.sequence = sequence;
    entry.id = entryId;
    entry.artifactName = INIT_CODE_STORAGE_ARTIFACT;
    entry.decodedConstructorArgs = string.concat(
      '[',
      _quoted(vm.toString(template.creationCode)),
      ']'
    );
    entry.output = output;
    entry.description = string.concat('Deploy the v2.5 ', template.name, ' init-code storage.');
    entry.predicate = _planCodePresentPredicate(output);
    entry.afterEntries = afterEntries;
    _planEntry(deployments, entry);

    string memory recordJson = string.concat(
      '{"recordType":"initCodeStorage","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"deploymentKey":',
      _quoted(template.deploymentLabel),
      ',"address":',
      _ref(output),
      ',"initCodeHash":',
      _quoted(vm.toString(keccak256(template.creationCode))),
      '}'
    );
    _inventoryRecord(deployments, sequence, template.deploymentLabel, recordJson);
  }

  function _writeRegisterControllerFactoryPlanEntry(
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
    entry.to = _quoted(vm.toString(archController));
    entry.functionSignature = 'registerControllerFactory(address)';
    entry.decodedArgs = string.concat('[', _ref(factoryOutput), ']');
    entry.description = description;
    entry.predicate = _planCallEqPredicateForTarget(
      _quoted(vm.toString(archController)),
      'isRegisteredControllerFactory(address) view returns (bool)',
      string.concat('[', _ref(factoryOutput), ']'),
      'true'
    );
    entry.afterEntries = afterEntries;
    _callPlanEntry(deployments, entry);
  }

  function _writeAddTemplatePlanEntry(
    Deployments memory deployments,
    TemplateDeployment memory template,
    address feeRecipient,
    uint256 sequence,
    string memory entryId,
    string memory factoryOutput,
    string memory storageOutput,
    string memory afterEntry,
    string memory description
  ) internal {
    string[] memory afterEntries = new string[](1);
    afterEntries[0] = afterEntry;
    string memory templateArgs = string.concat(
      '[',
      _ref(storageOutput),
      ',',
      _quoted(template.name),
      ',',
      _quoted(vm.toString(feeRecipient)),
      ',',
      _quoted(vm.toString(template.fees.originationFeeAsset)),
      ',',
      vm.toString(template.fees.originationFeeAmount),
      ',',
      vm.toString(template.fees.protocolFeeBips),
      ']'
    );
    CallPlanEntry memory entry;
    entry.sequence = sequence;
    entry.id = entryId;
    entry.to = _ref(factoryOutput);
    entry.functionSignature = 'addHooksTemplate(address,string,address,address,uint80,uint16)';
    entry.decodedArgs = templateArgs;
    entry.description = description;
    entry.predicate = _planCallEqPredicate(
      factoryOutput,
      'isHooksTemplate(address) view returns (bool)',
      string.concat('[', _ref(storageOutput), ']'),
      'true'
    );
    entry.afterEntries = afterEntries;
    _callPlanEntry(deployments, entry);
  }

  function _writePlanEntries(
    Deployments memory deployments,
    string memory networkName,
    address archController,
    TemplateDeployment memory openTerm,
    TemplateDeployment memory fixedTerm,
    TemplateDeployment memory periodicTerm
  ) internal {
    _writeTemplateStoragePlanEntry(
      deployments,
      networkName,
      openTerm,
      10,
      OPEN_STORAGE_ENTRY_ID,
      OPEN_STORAGE_OUTPUT,
      DEPLOYMENTS_COMPLETE_ENTRY_ID
    );
    _writeTemplateStoragePlanEntry(
      deployments,
      networkName,
      fixedTerm,
      11,
      FIXED_STORAGE_ENTRY_ID,
      FIXED_STORAGE_OUTPUT,
      OPEN_STORAGE_ENTRY_ID
    );
    _writeTemplateStoragePlanEntry(
      deployments,
      networkName,
      periodicTerm,
      12,
      PERIODIC_STORAGE_ENTRY_ID,
      PERIODIC_STORAGE_OUTPUT,
      FIXED_STORAGE_ENTRY_ID
    );

    _writeRegisterControllerFactoryPlanEntry(
      deployments,
      archController,
      13,
      REGISTER_STANDARD_FACTORY_ENTRY_ID,
      STANDARD_FACTORY_OUTPUT,
      PERIODIC_STORAGE_ENTRY_ID,
      'Register the v2.5 standard hooks factory as a controller factory.'
    );
    _writeRegisterControllerFactoryPlanEntry(
      deployments,
      archController,
      14,
      REGISTER_REVOLVING_FACTORY_ENTRY_ID,
      REVOLVING_FACTORY_OUTPUT,
      REGISTER_STANDARD_FACTORY_ENTRY_ID,
      'Register the v2.5 revolving hooks factory as a controller factory.'
    );

    address openFeeRecipient = _resolveFeeRecipient(deployments, openTerm.name);
    address fixedFeeRecipient = _resolveFeeRecipient(deployments, fixedTerm.name);
    address periodicFeeRecipient = _resolveFeeRecipient(deployments, periodicTerm.name);
    _writeAddTemplatePlanEntry(
      deployments,
      openTerm,
      openFeeRecipient,
      15,
      ADD_STANDARD_OPEN_ENTRY_ID,
      STANDARD_FACTORY_OUTPUT,
      OPEN_STORAGE_OUTPUT,
      REGISTER_REVOLVING_FACTORY_ENTRY_ID,
      'Add the v2.5 OpenTermHooks template to the standard factory.'
    );
    _writeAddTemplatePlanEntry(
      deployments,
      fixedTerm,
      fixedFeeRecipient,
      16,
      ADD_STANDARD_FIXED_ENTRY_ID,
      STANDARD_FACTORY_OUTPUT,
      FIXED_STORAGE_OUTPUT,
      ADD_STANDARD_OPEN_ENTRY_ID,
      'Add the v2.5 FixedTermHooks template to the standard factory.'
    );
    _writeAddTemplatePlanEntry(
      deployments,
      periodicTerm,
      periodicFeeRecipient,
      17,
      ADD_STANDARD_PERIODIC_ENTRY_ID,
      STANDARD_FACTORY_OUTPUT,
      PERIODIC_STORAGE_OUTPUT,
      ADD_STANDARD_FIXED_ENTRY_ID,
      'Add the v2.5 PeriodicTermHooks template to the standard factory.'
    );
    _writeAddTemplatePlanEntry(
      deployments,
      openTerm,
      openFeeRecipient,
      18,
      ADD_REVOLVING_OPEN_ENTRY_ID,
      REVOLVING_FACTORY_OUTPUT,
      OPEN_STORAGE_OUTPUT,
      ADD_STANDARD_PERIODIC_ENTRY_ID,
      'Add the v2.5 OpenTermHooks template to the revolving factory.'
    );
    _writeAddTemplatePlanEntry(
      deployments,
      fixedTerm,
      fixedFeeRecipient,
      19,
      ADD_REVOLVING_FIXED_ENTRY_ID,
      REVOLVING_FACTORY_OUTPUT,
      FIXED_STORAGE_OUTPUT,
      ADD_REVOLVING_OPEN_ENTRY_ID,
      'Add the v2.5 FixedTermHooks template to the revolving factory.'
    );
    _writeAddTemplatePlanEntry(
      deployments,
      periodicTerm,
      periodicFeeRecipient,
      20,
      ADD_REVOLVING_PERIODIC_ENTRY_ID,
      REVOLVING_FACTORY_OUTPUT,
      PERIODIC_STORAGE_OUTPUT,
      ADD_REVOLVING_FIXED_ENTRY_ID,
      'Add the v2.5 PeriodicTermHooks template to the revolving factory.'
    );
  }

  function _deployTemplateStorage(
    Deployments memory deployments,
    string memory networkName,
    TemplateDeployment memory template,
    uint256 sequence
  ) internal returns (TemplateDeployment memory) {
    bool didDeploy;
    (template.deployment, didDeploy) = _getOrDeployInitCodeStorageByLabel(
      deployments,
      template.deploymentLabel,
      template.artifactName,
      template.creationCode
    );
    string memory recordJson = string.concat(
      '{"recordType":"initCodeStorage","network":',
      _quoted(networkName),
      ',"chainId":',
      vm.toString(block.chainid),
      ',"deploymentKey":',
      _quoted(template.deploymentLabel),
      ',"address":',
      _quoted(vm.toString(template.deployment)),
      ',"initCodeHash":',
      _quoted(vm.toString(keccak256(template.creationCode))),
      '}'
    );
    _inventoryRecord(deployments, sequence, template.deploymentLabel, recordJson);
    console.log(string.concat('Did deploy ', template.name, ' init-code storage:'), didDeploy);
    return template;
  }

  function _registerControllerFactory(
    Deployments memory deployments,
    IWildcatArchController archController,
    address factory
  ) internal {
    if (!archController.isRegisteredControllerFactory(factory)) {
      deployments.broadcast();
      archController.registerControllerFactory(factory);
    }
    if (!archController.isRegisteredControllerFactory(factory)) {
      revert('Controller factory registration failed');
    }
  }

  function _addTemplate(
    Deployments memory deployments,
    address factoryAddress,
    TemplateDeployment memory template
  ) internal {
    IHooksFactory factory = IHooksFactory(factoryAddress);
    address feeRecipient = _resolveFeeRecipient(deployments, template.name);
    if (!factory.isHooksTemplate(template.deployment)) {
      deployments.broadcast();
      factory.addHooksTemplate(
        template.deployment,
        template.name,
        feeRecipient,
        template.fees.originationFeeAsset,
        template.fees.originationFeeAmount,
        template.fees.protocolFeeBips
      );
    }
    HooksTemplate memory details = factory.getHooksTemplateDetails(template.deployment);
    if (!details.exists || !details.enabled) revert('Template registration failed');
    if (!_sameStrings(details.name, template.name)) revert('Template name mismatch');
    if (
      details.feeRecipient != feeRecipient ||
      details.originationFeeAsset != template.fees.originationFeeAsset ||
      details.originationFeeAmount != template.fees.originationFeeAmount ||
      details.protocolFeeBips != template.fees.protocolFeeBips
    ) revert('Template fee configuration mismatch');
  }

  function run() external {
    string memory ownerMode = _ownerMode();
    (Deployments memory deployments, string memory networkName) = _resolveDeployments();
    address archControllerAddress = _resolveExisting(
      deployments,
      'WildcatArchController',
      'ARCH_CONTROLLER'
    );
    string memory parametersJson = vm.readFile(FEE_PARAMETERS_PATH);
    TemplateDeployment memory openTerm = _loadTemplate(
      deployments,
      parametersJson,
      'OpenTermHooks',
      OPEN_TERM_ARTIFACT
    );
    TemplateDeployment memory fixedTerm = _loadTemplate(
      deployments,
      parametersJson,
      'FixedTermHooks',
      FIXED_TERM_ARTIFACT
    );
    TemplateDeployment memory periodicTerm = _loadTemplate(
      deployments,
      parametersJson,
      'PeriodicTermHooks',
      PERIODIC_TERM_ARTIFACT
    );

    if (_isPlanMode(ownerMode)) {
      _writePlanEntries(
        deployments,
        networkName,
        archControllerAddress,
        openTerm,
        fixedTerm,
        periodicTerm
      );
      return;
    }

    openTerm = _deployTemplateStorage(deployments, networkName, openTerm, 10);
    fixedTerm = _deployTemplateStorage(deployments, networkName, fixedTerm, 11);
    periodicTerm = _deployTemplateStorage(deployments, networkName, periodicTerm, 12);
    deployments.write();

    string memory standardFactoryLabel = _label('HooksFactory');
    string memory revolvingFactoryLabel = _label('HooksFactoryRevolving');
    if (!deployments.has(standardFactoryLabel) || !deployments.has(revolvingFactoryLabel)) {
      revert('Missing v2.5 factories; run scripts 02 and 03 first');
    }
    address standardFactory = deployments.get(standardFactoryLabel);
    address revolvingFactory = deployments.get(revolvingFactoryLabel);
    IWildcatArchController archController = IWildcatArchController(archControllerAddress);
    _registerControllerFactory(deployments, archController, standardFactory);
    _registerControllerFactory(deployments, archController, revolvingFactory);
    _addTemplate(deployments, standardFactory, openTerm);
    _addTemplate(deployments, standardFactory, fixedTerm);
    _addTemplate(deployments, standardFactory, periodicTerm);
    _addTemplate(deployments, revolvingFactory, openTerm);
    _addTemplate(deployments, revolvingFactory, fixedTerm);
    _addTemplate(deployments, revolvingFactory, periodicTerm);
  }
}
