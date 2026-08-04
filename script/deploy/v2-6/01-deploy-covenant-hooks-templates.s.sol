// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/**
 * Deploys the covenant hooks templates and registers them on the revolving
 * factory. This is the first script of the v2.6 release; v2.5's script 03
 * (03-deploy-hooks-factory-revolving) must have run for this network first.
 *
 * Fees are NOT read from deployments/template-fee-parameters.json. They must be
 * supplied explicitly, so a misconfigured or absent entry fails the run rather
 * than silently deploying a template with inherited fees.
 *
 * Environment:
 *   DEPLOYMENTS_NETWORK
 *   RELEASE_TAG                       (required; use v2-6. The base default is
 *                                     v2-5, which would file these templates
 *                                     under the previous release's labels.)
 *   COVENANT_FEE_RECIPIENT            (required)
 *   COVENANT_ORIGINATION_FEE_ASSET    (required; address(0) for none)
 *   COVENANT_ORIGINATION_FEE_AMOUNT   (required; uint80)
 *   COVENANT_PROTOCOL_FEE_BIPS        (required; uint16)
 *   REVOLVING_HOOKS_FACTORY           (optional; overrides the deployments entry)
 *   SKIP_CLEANDOWN_TEMPLATE           (optional; "true" to register only the
 *                                     combined template. Both ship by default.)
 *   OWNER_MODE=direct  -> RPC_URL, PVT_KEY_<NETWORK>; broadcaster must own the
 *                         ArchController
 *   OWNER_MODE=plan    -> EXPECTED_EXECUTOR; emits calldata for the owner to
 *                         execute
 */

import { console } from 'forge-std/console.sol';
import { IHooksFactoryRevolving } from 'src/IHooksFactoryRevolving.sol';
import { RevolvingCovenantHooks } from 'src/access/RevolvingCovenantHooks.sol';
import { RevolvingCleanDownHooks } from 'src/access/RevolvingCleanDownHooks.sol';
import { CrossMarketGateLib } from 'src/access/covenants/lib/CrossMarketGateLib.sol';
import { CleanDownLib } from 'src/access/covenants/lib/CleanDownLib.sol';
import { CommitmentScheduleLib } from 'src/access/covenants/lib/CommitmentScheduleLib.sol';
import { DrawTimelockLib } from 'src/access/covenants/lib/DrawTimelockLib.sol';
import { RevolvingScheduleHooks } from 'src/access/RevolvingScheduleHooks.sol';
import { RevolvingTimelockHooks } from 'src/access/RevolvingTimelockHooks.sol';
import { FixedTermScheduleHooks } from 'src/access/FixedTermScheduleHooks.sol';
import { PeriodicTimelockHooks } from 'src/access/PeriodicTimelockHooks.sol';
import { CREATE2_DEPLOYER, CROSS_MARKET_GATE_LIB, CLEAN_DOWN_LIB, COMMITMENT_SCHEDULE_LIB, DRAW_TIMELOCK_LIB, CROSS_MARKET_GATE_LIB_SALT, CLEAN_DOWN_LIB_SALT, COMMITMENT_SCHEDULE_LIB_SALT, DRAW_TIMELOCK_LIB_SALT } from 'src/access/covenants/lib/CovenantLibraries.sol';
import '../../common/DeployScriptBase.sol';

contract DeployCovenantHooksTemplatesV26 is V25DeployScriptBase {
  string internal constant COVENANT_ARTIFACT =
    'src/access/RevolvingCovenantHooks.sol:RevolvingCovenantHooks';
  string internal constant CLEANDOWN_ARTIFACT =
    'src/access/RevolvingCleanDownHooks.sol:RevolvingCleanDownHooks';


  string internal constant INIT_CODE_STORAGE_ARTIFACT =
    'script/common/DeployScriptBase.sol:InitCodeStorage';
  string internal constant REVOLVING_FACTORY_NAME = 'HooksFactoryRevolving';
  string internal constant REVOLVING_FACTORY_OUTPUT = 'hooks-factory-revolving';

  struct Fees {
    address recipient;
    address originationFeeAsset;
    uint80 originationFeeAmount;
    uint16 protocolFeeBips;
  }

  function _requiredFees() internal returns (Fees memory fees) {
    fees.recipient = vm.envAddress('COVENANT_FEE_RECIPIENT');
    fees.originationFeeAsset = vm.envAddress('COVENANT_ORIGINATION_FEE_ASSET');
    uint256 amount = vm.envUint('COVENANT_ORIGINATION_FEE_AMOUNT');
    uint256 bips = vm.envUint('COVENANT_PROTOCOL_FEE_BIPS');
    require(fees.recipient != address(0), 'COVENANT_FEE_RECIPIENT is zero');
    require(amount <= type(uint80).max, 'origination fee exceeds uint80');
    require(bips <= type(uint16).max, 'protocol fee exceeds uint16');
    require(
      fees.originationFeeAsset != address(0) || amount == 0,
      'origination fee amount set with no asset'
    );
    fees.originationFeeAmount = uint80(amount);
    fees.protocolFeeBips = uint16(bips);
  }

  /// @dev Deployment labels carry the release tag via `_label`, and the base
  ///      class defaults that tag to `v2-5`. This is a v2.6 release, so the tag
  ///      is required explicitly rather than letting templates file silently
  ///      under the previous release.
  function _requireReleaseTag() internal {
    string memory tag = vm.envOr('RELEASE_TAG', string(''));
    require(bytes(tag).length > 0, 'Set RELEASE_TAG (v2-6)');
    require(
      keccak256(bytes(tag)) != keccak256(bytes('v2-5')),
      'RELEASE_TAG=v2-5 would file v2.6 templates under the v2.5 release'
    );
  }

  /// @dev The revolving factory is deployed by v2.5's script 03, so it is
  ///      recorded under that release's label rather than this one. Earlier
  ///      deployments recorded it under the bare contract name. Try the
  ///      explicit override, then this release's label, then v2.5's, then bare.
  ///      `'hooks-factory-revolving'` is a plan output id and is never a
  ///      deployments key; do not resolve against it.
  function _resolveRevolvingFactory(
    Deployments memory deployments
  ) internal returns (address factory) {
    factory = vm.envOr('REVOLVING_HOOKS_FACTORY', address(0));
    if (factory != address(0)) return factory;

    string[3] memory candidates = [
      _label(REVOLVING_FACTORY_NAME),
      string.concat(REVOLVING_FACTORY_NAME, '_v2-5'),
      REVOLVING_FACTORY_NAME
    ];
    for (uint256 i; i < candidates.length; i++) {
      if (deployments.has(candidates[i])) return deployments.get(candidates[i]);
    }
    revert(
      'Missing HooksFactoryRevolving: run v2.5 script 03 or set REVOLVING_HOOKS_FACTORY'
    );
  }

  /// @dev Verifies a linked library address is what this source actually
  ///      produces, then ensures code is present there. Templates delegatecall
  ///      into these, so registering a template before its libraries exist
  ///      would produce a market whose covenants revert on every draw.
  function _ensureLibrary(
    bool planMode,
    string memory name,
    address linked,
    bytes32 salt,
    bytes memory initCode
  ) internal {
    address expected = address(
      uint160(
        uint256(
          keccak256(
            abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, keccak256(initCode))
          )
        )
      )
    );
    require(
      expected == linked,
      string.concat(name, ' address drift: update the constant and foundry.toml libraries')
    );
    if (linked.code.length > 0) {
      console.log(string.concat(name, ' already deployed at'), linked);
      return;
    }
    if (planMode) {
      console.log(string.concat('PLAN: deploy ', name, ' via CREATE2 to'), linked);
      return;
    }
    vm.broadcast();
    (bool ok, ) = CREATE2_DEPLOYER.call(abi.encodePacked(salt, initCode));
    require(ok, string.concat(name, ' deployment failed'));
    require(linked.code.length > 0, string.concat(name, ' absent after deployment'));
    console.log(string.concat('Deployed ', name, ' to'), linked);
  }

  function _ensureCovenantLibraries(bool planMode) internal {
    _ensureLibrary(
      planMode,
      'CrossMarketGateLib',
      CROSS_MARKET_GATE_LIB,
      CROSS_MARKET_GATE_LIB_SALT,
      type(CrossMarketGateLib).creationCode
    );
    _ensureLibrary(
      planMode,
      'CleanDownLib',
      CLEAN_DOWN_LIB,
      CLEAN_DOWN_LIB_SALT,
      type(CleanDownLib).creationCode
    );
    _ensureLibrary(
      planMode,
      'CommitmentScheduleLib',
      COMMITMENT_SCHEDULE_LIB,
      COMMITMENT_SCHEDULE_LIB_SALT,
      type(CommitmentScheduleLib).creationCode
    );
    _ensureLibrary(
      planMode,
      'DrawTimelockLib',
      DRAW_TIMELOCK_LIB,
      DRAW_TIMELOCK_LIB_SALT,
      type(DrawTimelockLib).creationCode
    );
  }

  function run() external {
    _requireReleaseTag();
    string memory mode = _ownerMode();
    bool planMode = _isPlanMode(mode);
    (Deployments memory deployments, ) = _resolveDeployments();
    Fees memory fees = _requiredFees();

    address factory = _resolveRevolvingFactory(deployments);
    _requireCode(factory, REVOLVING_FACTORY_NAME);
    _ensureCovenantLibraries(planMode);

    _deployAndRegister(
      deployments,
      planMode,
      factory,
      fees,
      'RevolvingCovenantHooks',
      COVENANT_ARTIFACT,
      type(RevolvingCovenantHooks).creationCode
    );

    if (!vm.envOr('SKIP_CLEANDOWN_TEMPLATE', false)) {
      _deployAndRegister(
        deployments,
        planMode,
        factory,
        fees,
        'RevolvingCleanDownHooks',
        CLEANDOWN_ARTIFACT,
        type(RevolvingCleanDownHooks).creationCode
      );
    }
  }

  function _deployAndRegister(
    Deployments memory deployments,
    bool planMode,
    address factory,
    Fees memory fees,
    string memory name,
    string memory artifact,
    bytes memory creationCode
  ) internal {
    string memory label = _label(string.concat(name, '_initCodeStorage'));

    // Plan mode deploys nothing. Mirrors script 03: emit the entries an
    // executor will run and return, rather than broadcasting here.
    if (planMode) {
      _writePlanEntries(deployments, factory, fees, name, artifact, creationCode);
      return;
    }

    (address template, ) = _getOrDeployInitCodeStorageByLabel(
      deployments,
      label,
      artifact,
      creationCode
    );

    if (IHooksFactoryRevolving(factory).isHooksTemplate(template)) {
      console.log(string.concat(name, ': already registered at'), template);
      return;
    }

    bytes memory callData = abi.encodeCall(
      IHooksFactoryRevolving.addHooksTemplate,
      (
        template,
        name,
        fees.recipient,
        fees.originationFeeAsset,
        fees.originationFeeAmount,
        fees.protocolFeeBips
      )
    );

    vm.broadcast();
    (bool ok, ) = factory.call(callData);
    require(ok, string.concat('addHooksTemplate failed for ', name));
    require(
      IHooksFactoryRevolving(factory).isHooksTemplate(template),
      string.concat('template not registered: ', name)
    );
    console.log(string.concat('Registered ', name, ' at'), template);
  }

  /// @dev Emits the two entries an executor runs for one template: deploy the
  ///      init-code storage contract, then register it on the factory. The
  ///      registration references the storage contract by plan output rather
  ///      than by address, since it does not exist yet.
  ///
  ///      Split across two helpers to keep each frame inside the stack limit
  ///      under the default profile.
  function _writePlanEntries(
    Deployments memory deployments,
    address factory,
    Fees memory fees,
    string memory name,
    string memory artifact,
    bytes memory creationCode
  ) internal {
    artifact;
    string memory storageOutput = string.concat(_lowerName(name), '-init-code-storage');
    _planStorageEntry(deployments, name, storageOutput, creationCode);
    _planRegisterEntry(deployments, factory, fees, name, storageOutput);
  }

  function _planStorageEntry(
    Deployments memory deployments,
    string memory name,
    string memory storageOutput,
    bytes memory creationCode
  ) internal {
    DeployPlanEntry memory entry;
    entry.sequence = 1;
    entry.id = string.concat('deploy-', storageOutput);
    entry.artifactName = INIT_CODE_STORAGE_ARTIFACT;
    entry.decodedConstructorArgs = string.concat('[', _quoted(vm.toString(creationCode)), ']');
    entry.output = storageOutput;
    entry.description = string.concat('Deploy the ', name, ' init-code storage contract.');
    entry.predicate = _planCodePresentPredicate(storageOutput);
    _planEntry(deployments, entry);
  }

  function _planRegisterEntry(
    Deployments memory deployments,
    address factory,
    Fees memory fees,
    string memory name,
    string memory storageOutput
  ) internal {
    string[] memory afterEntries = new string[](1);
    afterEntries[0] = string.concat('deploy-', storageOutput);

    CallPlanEntry memory entry;
    entry.sequence = 2;
    entry.id = string.concat('register-', storageOutput);
    entry.to = _quoted(vm.toString(factory));
    entry.functionSignature = 'addHooksTemplate(address,string,address,address,uint80,uint16)';
    entry.decodedArgs = _planRegisterArgs(fees, name, storageOutput);
    entry.description = string.concat('Register ', name, ' on the revolving factory.');
    entry.predicate = _planCallEqPredicateForTarget(
      _quoted(vm.toString(factory)),
      'isHooksTemplate(address) view returns (bool)',
      string.concat('[', _ref(storageOutput), ']'),
      'true'
    );
    entry.afterEntries = afterEntries;
    _callPlanEntry(deployments, entry);
  }

  function _planRegisterArgs(
    Fees memory fees,
    string memory name,
    string memory storageOutput
  ) internal pure returns (string memory) {
    return
      string.concat(
        '[',
        _ref(storageOutput),
        ',',
        _quoted(name),
        ',',
        _quoted(vm.toString(fees.recipient)),
        ',',
        _quoted(vm.toString(fees.originationFeeAsset)),
        ',',
        vm.toString(fees.originationFeeAmount),
        ',',
        vm.toString(fees.protocolFeeBips),
        ']'
      );
  }

  /// @dev `RevolvingCovenantHooks` -> `revolving-covenant-hooks`, for plan ids.
  function _lowerName(string memory name) internal pure returns (string memory out) {
    bytes memory b = bytes(name);
    bytes memory o = new bytes(b.length * 2);
    uint256 n;
    for (uint256 i; i < b.length; i++) {
      uint8 c = uint8(b[i]);
      if (c >= 65 && c <= 90) {
        if (i != 0) o[n++] = '-';
        o[n++] = bytes1(c + 32);
      } else {
        o[n++] = b[i];
      }
    }
    bytes memory trimmed = new bytes(n);
    for (uint256 i; i < n; i++) trimmed[i] = o[i];
    return string(trimmed);
  }
}
