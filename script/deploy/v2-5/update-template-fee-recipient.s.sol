// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/**
 * Sepolia-only repair for the v2.5 template fee recipient.
 *
 * The activation package registered all three templates on both v2.5 factories
 * with the retained executor as fee recipient. This script moves only that
 * field to the new executor through the replacement authority helper.
 *
 * Run through update-template-fee-recipient.sh. The script is safe to rerun:
 * registrations already using the new recipient are verified and skipped.
 */

import { console } from 'forge-std/console.sol';

import { HooksTemplate, IHooksFactory } from 'src/IHooksFactory.sol';
import { IWildcatArchController } from 'src/interfaces/IWildcatArchController.sol';

import '../../common/DeployScriptBase.sol';

interface ITemplateFeeAuthorityHelper {
  function archController() external view returns (address);

  function authorizedAccounts(address account) external view returns (bool);

  function executeProtocolAction(
    address target,
    bytes calldata data
  ) external returns (bytes memory result);
}

contract UpdateTemplateFeeRecipientV25 is DeployScriptBase {
  uint256 internal constant SEPOLIA_CHAIN_ID = 11_155_111;

  address internal constant ARCH_CONTROLLER = 0xC003f20F2642c76B81e5e1620c6D8cdEE826408f;
  address internal constant AUTHORITY_HELPER = 0x981f1Fb406bD7a8385f9373c08Ab4c832Ed0d508;
  address internal constant STANDARD_FACTORY = 0xbFbDaFc91977eE599a61B30D9e75788565Ad6d18;
  address internal constant REVOLVING_FACTORY = 0x190B42942fe9492df9CeA441dA5c43309840E93A;

  address internal constant OPEN_TERM_TEMPLATE = 0x1840E97Fba22DbA0996f4b8D02fc8bB74473dD95;
  address internal constant FIXED_TERM_TEMPLATE = 0x7Cf683E0802257180EDf4C21A12C5070acd166d2;
  address internal constant PERIODIC_TERM_TEMPLATE = 0xB63929E732156C46857C0d9b08e483f8845Ed1BE;

  address internal constant PREVIOUS_FEE_RECIPIENT = 0xca732651410E915090d7A7D889A1E44eF4575fcE;
  address internal constant NEW_FEE_RECIPIENT = 0xCa7007a75296b532Ce1606d9e130eAa849800Ca7;

  bytes32 internal constant AUTHORITY_HELPER_RUNTIME_HASH =
    0x71813272287ef573f8a2f96101f1a9ba6982761ad9de14a3e65e88c236a8a6fa;

  uint16 internal constant EXPECTED_PROTOCOL_FEE_BIPS = 500;

  struct TemplateTarget {
    address factory;
    address template;
    string name;
    uint24 index;
  }

  function _requireRecordedAddress(
    Deployments memory deployments,
    string memory key,
    address expected
  ) internal view {
    if (!deployments.has(key) || deployments.get(key) != expected) {
      revert(string.concat('Unexpected deployments.json address for ', key));
    }
  }

  function _targets() internal pure returns (TemplateTarget[6] memory targets) {
    targets[0] = TemplateTarget(STANDARD_FACTORY, OPEN_TERM_TEMPLATE, 'OpenTermHooks', 0);
    targets[1] = TemplateTarget(STANDARD_FACTORY, FIXED_TERM_TEMPLATE, 'FixedTermHooks', 1);
    targets[2] = TemplateTarget(STANDARD_FACTORY, PERIODIC_TERM_TEMPLATE, 'PeriodicTermHooks', 2);
    targets[3] = TemplateTarget(REVOLVING_FACTORY, OPEN_TERM_TEMPLATE, 'OpenTermHooks', 0);
    targets[4] = TemplateTarget(REVOLVING_FACTORY, FIXED_TERM_TEMPLATE, 'FixedTermHooks', 1);
    targets[5] = TemplateTarget(REVOLVING_FACTORY, PERIODIC_TERM_TEMPLATE, 'PeriodicTermHooks', 2);
  }

  function _assertExpectedTemplate(
    TemplateTarget memory target,
    HooksTemplate memory details
  ) internal pure {
    if (!details.exists || !details.enabled) revert('Template is not enabled');
    if (keccak256(bytes(details.name)) != keccak256(bytes(target.name))) {
      revert('Template name mismatch');
    }
    if (details.index != target.index) revert('Template index mismatch');
    if (
      details.originationFeeAsset != address(0) ||
      details.originationFeeAmount != 0 ||
      details.protocolFeeBips != EXPECTED_PROTOCOL_FEE_BIPS
    ) revert('Template fee parameters differ from the activated package');
    if (details.feeRecipient != PREVIOUS_FEE_RECIPIENT && details.feeRecipient != NEW_FEE_RECIPIENT)
      revert('Template has an unexpected fee recipient');
  }

  function _preflightTemplate(TemplateTarget memory target) internal view {
    IHooksFactory factory = IHooksFactory(target.factory);
    if (!factory.isHooksTemplate(target.template)) revert('Template is not registered');
    HooksTemplate memory details = factory.getHooksTemplateDetails(target.template);
    _assertExpectedTemplate(target, details);
    console.log(string.concat('Verified ', target.name, ' on factory'), target.factory);
    console.log('Current fee recipient:', details.feeRecipient);
  }

  function _assertUpdate(
    TemplateTarget memory target,
    HooksTemplate memory beforeDetails
  ) internal view {
    HooksTemplate memory afterDetails = IHooksFactory(target.factory).getHooksTemplateDetails(
      target.template
    );
    _assertExpectedTemplate(target, afterDetails);
    if (afterDetails.feeRecipient != NEW_FEE_RECIPIENT) {
      revert('Template fee recipient update failed');
    }
    if (
      afterDetails.originationFeeAsset != beforeDetails.originationFeeAsset ||
      afterDetails.originationFeeAmount != beforeDetails.originationFeeAmount ||
      afterDetails.protocolFeeBips != beforeDetails.protocolFeeBips ||
      afterDetails.exists != beforeDetails.exists ||
      afterDetails.enabled != beforeDetails.enabled ||
      afterDetails.index != beforeDetails.index ||
      keccak256(bytes(afterDetails.name)) != keccak256(bytes(beforeDetails.name))
    ) revert('Template changed outside the fee-recipient field');
  }

  function _updateTemplate(
    ITemplateFeeAuthorityHelper helper,
    TemplateTarget memory target,
    uint256 privateKey
  ) internal returns (bool updated) {
    IHooksFactory factory = IHooksFactory(target.factory);
    HooksTemplate memory beforeDetails = factory.getHooksTemplateDetails(target.template);
    if (beforeDetails.feeRecipient == NEW_FEE_RECIPIENT) {
      console.log(string.concat('Already updated ', target.name, ' on factory'), target.factory);
      return false;
    }

    bytes memory updateCall = abi.encodeCall(
      IHooksFactory.updateHooksTemplateFees,
      (
        target.template,
        NEW_FEE_RECIPIENT,
        beforeDetails.originationFeeAsset,
        beforeDetails.originationFeeAmount,
        beforeDetails.protocolFeeBips
      )
    );
    vm.broadcast(privateKey);
    helper.executeProtocolAction(target.factory, updateCall);
    _assertUpdate(target, beforeDetails);
    console.log(string.concat('Updated ', target.name, ' on factory'), target.factory);
    return true;
  }

  function _preflight(Deployments memory deployments) internal view {
    if (block.chainid != SEPOLIA_CHAIN_ID) revert('This repair is Sepolia-only');

    _requireRecordedAddress(deployments, 'WildcatArchController', ARCH_CONTROLLER);
    _requireRecordedAddress(deployments, 'MockArchControllerOwner', AUTHORITY_HELPER);
    _requireRecordedAddress(deployments, 'HooksFactory_v2-5', STANDARD_FACTORY);
    _requireRecordedAddress(deployments, 'HooksFactoryRevolving_v2-5', REVOLVING_FACTORY);
    _requireRecordedAddress(deployments, 'OpenTermHooks_initCodeStorage_v2-5', OPEN_TERM_TEMPLATE);
    _requireRecordedAddress(
      deployments,
      'FixedTermHooks_initCodeStorage_v2-5',
      FIXED_TERM_TEMPLATE
    );
    _requireRecordedAddress(
      deployments,
      'PeriodicTermHooks_initCodeStorage_v2-5',
      PERIODIC_TERM_TEMPLATE
    );

    if (
      ARCH_CONTROLLER.code.length == 0 ||
      AUTHORITY_HELPER.code.length == 0 ||
      STANDARD_FACTORY.code.length == 0 ||
      REVOLVING_FACTORY.code.length == 0 ||
      OPEN_TERM_TEMPLATE.code.length == 0 ||
      FIXED_TERM_TEMPLATE.code.length == 0 ||
      PERIODIC_TERM_TEMPLATE.code.length == 0
    ) revert('One or more repair targets have no code');
    if (AUTHORITY_HELPER.codehash != AUTHORITY_HELPER_RUNTIME_HASH) {
      revert('Authority helper runtime does not match the reviewed deployment');
    }

    IWildcatArchController archController = IWildcatArchController(ARCH_CONTROLLER);
    ITemplateFeeAuthorityHelper helper = ITemplateFeeAuthorityHelper(AUTHORITY_HELPER);
    if (archController.owner() != AUTHORITY_HELPER) {
      revert('Replacement authority helper does not own the ArchController');
    }
    if (helper.archController() != ARCH_CONTROLLER) {
      revert('Replacement authority helper is bound to the wrong ArchController');
    }
    if (!helper.authorizedAccounts(NEW_FEE_RECIPIENT)) {
      revert('New executor is not authorized on the replacement helper');
    }
    if (
      IHooksFactory(STANDARD_FACTORY).archController() != ARCH_CONTROLLER ||
      IHooksFactory(REVOLVING_FACTORY).archController() != ARCH_CONTROLLER
    ) revert('A v2.5 factory is bound to the wrong ArchController');
    if (
      !archController.isRegisteredControllerFactory(STANDARD_FACTORY) ||
      !archController.isRegisteredControllerFactory(REVOLVING_FACTORY) ||
      !archController.isRegisteredController(STANDARD_FACTORY) ||
      !archController.isRegisteredController(REVOLVING_FACTORY)
    ) revert('A v2.5 factory is not fully registered');

    TemplateTarget[6] memory targets = _targets();
    for (uint256 i; i < targets.length; i++) {
      _preflightTemplate(targets[i]);
    }
  }

  function run() external {
    (Deployments memory deployments, string memory networkName) = _resolveDeployments();
    if (!_sameStrings(networkName, 'sepolia')) revert('DEPLOYMENTS_NETWORK must be sepolia');
    _preflight(deployments);

    if (vm.envOr('CHECK_ONLY', false)) {
      console.log('Sepolia template fee-recipient preflight GREEN');
      return;
    }

    uint256 privateKey = vm.envOr('PVT_KEY', uint256(0));
    if (privateKey == 0) {
      revert('PVT_KEY is required');
    }
    address executor = vm.envOr('DEPLOYER_ADDRESS', address(0));
    if (executor == address(0)) revert('DEPLOYER_ADDRESS is required');
    if (vm.addr(privateKey) != executor) revert('PVT_KEY does not match DEPLOYER_ADDRESS');
    if (executor != NEW_FEE_RECIPIENT) revert('DEPLOYER_ADDRESS is not the new executor');

    ITemplateFeeAuthorityHelper helper = ITemplateFeeAuthorityHelper(AUTHORITY_HELPER);
    if (!helper.authorizedAccounts(executor)) revert('Configured executor is not authorized');

    TemplateTarget[6] memory targets = _targets();
    uint256 updateCount;
    for (uint256 i; i < targets.length; i++) {
      if (_updateTemplate(helper, targets[i], privateKey)) updateCount++;
    }
    for (uint256 i; i < targets.length; i++) {
      _preflightTemplate(targets[i]);
      if (
        IHooksFactory(targets[i].factory)
          .getHooksTemplateDetails(targets[i].template)
          .feeRecipient != NEW_FEE_RECIPIENT
      ) revert('Final fee-recipient verification failed');
    }

    console.log('Template fee-recipient update GREEN');
    console.log('Transactions sent:', updateCount);
    console.log('Fee recipient:', NEW_FEE_RECIPIENT);
  }
}
