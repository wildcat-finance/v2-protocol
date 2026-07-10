// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { Script } from 'forge-std/Script.sol';
import { console } from 'forge-std/console.sol';

import 'solady/utils/LibString.sol';

import './LibDeployment.sol';

/// @dev Deployable form of LibStoredInitCode's STOP-prefixed runtime layout.
///      Plan entries need an artifact-backed CREATE transaction, while direct
///      mode uses LibStoredInitCode through LibDeployment.
contract InitCodeStorage {
  constructor(bytes memory initCode) {
    bytes memory runtimeCode = bytes.concat(hex'00', initCode);
    assembly ('memory-safe') {
      return(add(runtimeCode, 0x20), mload(runtimeCode))
    }
  }
}

abstract contract DeployScriptBase is Script {
  using LibDeployment for Deployments;
  using LibString for string;

  struct DeployPlanEntry {
    uint256 sequence;
    string id;
    string artifactName;
    string decodedConstructorArgs;
    string output;
    string description;
    string predicate;
    string[] afterEntries;
  }

  struct CallPlanEntry {
    uint256 sequence;
    string id;
    string to;
    string functionSignature;
    string decodedArgs;
    string description;
    string predicate;
    string[] afterEntries;
  }

  uint256 internal constant ETHEREUM_MAINNET_CHAIN_ID = 1;
  uint256 internal constant DEFAULT_PLASMA_MAINNET_CHAIN_ID = 9745;

  function _sameStrings(string memory a, string memory b) internal pure returns (bool) {
    return keccak256(bytes(a)) == keccak256(bytes(b));
  }

  function _containsDot(string memory value) internal pure returns (bool) {
    bytes memory data = bytes(value);
    for (uint256 i; i < data.length; i++) {
      if (data[i] == '.') return true;
    }
    return false;
  }

  function _resolveOwnerMode() internal returns (string memory mode) {
    mode = vm.envOr('OWNER_MODE', string(''));
    uint256 plasmaMainnetChainId = vm.envOr(
      'PLASMA_MAINNET_CHAIN_ID',
      DEFAULT_PLASMA_MAINNET_CHAIN_ID
    );
    bool isMainnet = block.chainid == ETHEREUM_MAINNET_CHAIN_ID ||
      block.chainid == plasmaMainnetChainId;

    if (bytes(mode).length == 0) {
      if (isMainnet) {
        revert('OWNER_MODE is required on Ethereum and Plasma mainnet');
      }
      return 'direct';
    }
    if (!_sameStrings(mode, 'direct') && !_sameStrings(mode, 'plan')) {
      revert("Invalid OWNER_MODE; expected 'direct' or 'plan'");
    }
  }

  function _isPlanMode(string memory mode) internal pure returns (bool) {
    return _sameStrings(mode, 'plan');
  }

  function _releaseTag() internal returns (string memory tag) {
    tag = vm.envOr('RELEASE_TAG', string('v2-5'));
    if (bytes(tag).length == 0) revert('RELEASE_TAG must not be empty');
    if (_containsDot(tag)) revert('RELEASE_TAG must not contain dots');
  }

  function _label(string memory name) internal returns (string memory label) {
    label = string.concat(name, '_', _releaseTag());
    if (_containsDot(label)) revert('Deployment labels must not contain dots');
  }

  function _assertEip1153Supported() internal {
    if (vm.envOr('SKIP_EIP1153_CHECK', false)) {
      console.log('Skipping EIP-1153 transient storage probe because SKIP_EIP1153_CHECK=true');
      return;
    }

    string memory rpcUrl = vm.envOr('RPC_URL', string(''));
    if (bytes(rpcUrl).length == 0) {
      revert('Missing RPC_URL for EIP-1153 transient storage probe');
    }

    string[] memory args = new string[](5);
    args[0] = 'node';
    args[1] = 'scripts/check-eip1153.js';
    args[2] = '--rpc-url';
    args[3] = rpcUrl;
    args[4] = '--quiet';
    vm.ffi(args);
    console.log('EIP-1153 transient storage probe passed');
  }

  function _resolveDeployments()
    internal
    returns (Deployments memory deployments, string memory networkName)
  {
    networkName = vm.envOr('DEPLOYMENTS_NETWORK', string(''));
    if (bytes(networkName).length == 0) {
      networkName = getNetworkName();
    }

    if (bytes(networkName).length == 0) {
      revert('Unknown network; set DEPLOYMENTS_NETWORK');
    }

    deployments = getDeploymentsForNetwork(networkName);

    string memory defaultPrivateKeyVar = string.concat('PVT_KEY_', networkName.upper());
    string memory privateKeyVarName = vm.envOr('DEPLOYER_PRIVATE_KEY_VAR', defaultPrivateKeyVar);
    deployments = deployments.withPrivateKeyVarName(privateKeyVarName);
  }

  function _resolveExisting(
    Deployments memory deployments,
    string memory name,
    string memory envVarName
  ) internal returns (address value) {
    value = vm.envOr(envVarName, address(0));
    if (value != address(0)) return value;
    if (!deployments.has(name)) {
      revert(
        string.concat(
          'Missing existing ',
          name,
          ': set ',
          envVarName,
          ' or add key ',
          name,
          ' to ',
          deployments.filePath
        )
      );
    }
    return deployments.get(name);
  }

  function _resolveAddress(
    Deployments memory deployments,
    string memory envVarName,
    string memory deploymentKey
  ) internal returns (address value) {
    return _resolveExisting(deployments, deploymentKey, envVarName);
  }

  function _resolveV1WrapperFactory(
    Deployments memory deployments
  ) internal returns (address v1Factory) {
    string memory inventoryPath = pathJoin(deployments.dir, 'factory-inventory.json');
    if (!vm.exists(inventoryPath)) {
      revert(
        string.concat(
          'Missing ',
          inventoryPath,
          '; provide an inventory with the v1 wrapper record or an explicit empty wrapperFactories array'
        )
      );
    }

    string[] memory args = new string[](4);
    args[0] = 'node';
    args[1] = '-e';
    args[
      2
    ] = "(()=>{const fs=require('fs');let x;try{x=JSON.parse(fs.readFileSync(process.argv[1],'utf8'))}catch(e){process.stdout.write('ERROR: '+e.message);return}const r=x.wrapperFactories;if(!Array.isArray(r)){process.stdout.write('ERROR: wrapperFactories must be an array');return}if(r.length===0){process.stdout.write('NONE');return}const v1=r.filter((e)=>e&&e.v1Factory===null);if(v1.length!==1){process.stdout.write('ERROR: expected exactly one wrapper factory record with v1Factory null');return}process.stdout.write('ADDRESS:'+String(v1[0].address||''));})()";
    args[3] = inventoryPath;
    string memory result = string(vm.ffi(args));
    if (_sameStrings(result, 'NONE')) {
      console.log(
        'WARNING: factory inventory explicitly has no wrapper records; deploying with v1Factory=0'
      );
      return address(0);
    }
    if (result.startsWith('ERROR:')) {
      revert(string.concat('Invalid wrapper inventory: ', result));
    }
    if (!result.startsWith('ADDRESS:')) {
      revert(string.concat('Invalid wrapper inventory resolver output: ', result));
    }
    string memory addressString = result.slice(8);
    try vm.parseAddress(addressString) returns (address parsed) {
      if (parsed == address(0)) revert('V1 wrapper factory inventory address is zero');
      return parsed;
    } catch {
      revert(
        string.concat('Invalid v1 wrapper factory address in ', inventoryPath, ': ', addressString)
      );
    }
  }

  function _getCreationCode(
    Deployments memory deployments,
    string memory namePath
  ) internal returns (bytes memory creationCode) {
    ContractArtifact memory artifact = parseContractNamePath(namePath);
    string memory jsonPath = LibDeployment.findForgeArtifact(artifact, deployments.forgeOutDir);
    string memory forgeArtifactJson = vm.readFile(jsonPath);
    creationCode = vm.parseJsonBytes(forgeArtifactJson, '.bytecode.object');
  }

  function _requireCode(address deployment, string memory label) internal view {
    if (deployment.code.length == 0) {
      revert(string.concat('Verification failed for ', label, ': no code at recorded address'));
    }
  }

  function _verifyStoredInitCode(
    address deployment,
    string memory label,
    bytes memory initCode
  ) internal view {
    _requireCode(deployment, label);
    bytes32 expectedCodeHash = keccak256(bytes.concat(hex'00', initCode));
    if (deployment.codehash != expectedCodeHash) {
      revert(string.concat('Verification failed for ', label, ': stored init code mismatch'));
    }
  }

  function _verifyAddressCall(
    address deployment,
    string memory label,
    string memory field,
    bytes memory callData,
    address expected
  ) internal view {
    _requireCode(deployment, label);
    (bool success, bytes memory data) = deployment.staticcall(callData);
    if (!success || data.length < 32) {
      revert(string.concat('Verification failed for ', label, ': could not read ', field));
    }
    address actual = abi.decode(data, (address));
    if (actual != expected) {
      revert(string.concat('Verification failed for ', label, ': ', field, ' mismatch'));
    }
  }

  function _verifyUintCall(
    address deployment,
    string memory label,
    string memory field,
    bytes memory callData,
    uint256 expected
  ) internal view {
    _requireCode(deployment, label);
    (bool success, bytes memory data) = deployment.staticcall(callData);
    if (!success || data.length < 32) {
      revert(string.concat('Verification failed for ', label, ': could not read ', field));
    }
    uint256 actual = abi.decode(data, (uint256));
    if (actual != expected) {
      revert(string.concat('Verification failed for ', label, ': ', field, ' mismatch'));
    }
  }

  function _getOrDeployByLabel(
    Deployments memory deployments,
    string memory label,
    string memory artifactName,
    bytes memory creationCode,
    bytes memory constructorArgs
  ) internal returns (address deployment, bool didDeploy) {
    if (deployments.has(label)) {
      deployment = deployments.get(label);
      _requireCode(deployment, label);
      console.log(string.concat('Found and code-verified ', label, ' at'), deployment);
      return (deployment, false);
    }

    deployment = deployments.broadcastCreate(creationCode, constructorArgs);
    deployments.addArtifactWithoutDeploying(label, artifactName, deployment, constructorArgs);
    _requireCode(deployment, label);
    console.log(string.concat('Deployed ', label, ' to'), deployment);
    return (deployment, true);
  }

  function _getOrDeployInitCodeStorageByLabel(
    Deployments memory deployments,
    string memory label,
    string memory artifactName,
    bytes memory initCode
  ) internal returns (address deployment, bool didDeploy) {
    if (deployments.has(label)) {
      deployment = deployments.get(label);
      _verifyStoredInitCode(deployment, label, initCode);
      console.log(string.concat('Found and verified ', label, ' at'), deployment);
      return (deployment, false);
    }

    deployment = deployments.broadcastDeployInitcode(initCode);
    ContractArtifact memory artifact = parseContractNamePath(artifactName);
    artifact.customLabel = label;
    artifact.deployment = deployment;
    deployments.set(label, deployment);
    deployments.pushArtifact(artifact);
    _verifyStoredInitCode(deployment, label, initCode);
    console.log(string.concat('Deployed ', label, ' to'), deployment);
    return (deployment, true);
  }

  function _ref(string memory output) internal pure returns (string memory) {
    return string.concat('{"$ref":"', output, '"}');
  }

  function _quoted(string memory value) internal pure returns (string memory) {
    return string.concat('"', value, '"');
  }

  function _jsonStringArray(string[] memory values) internal pure returns (string memory json) {
    json = '[';
    for (uint256 i; i < values.length; i++) {
      if (i != 0) json = string.concat(json, ',');
      json = string.concat(json, _quoted(values[i]));
    }
    return string.concat(json, ']');
  }

  function _sequence(uint256 value) internal returns (string memory) {
    if (value == 0 || value > 99) revert('Plan/inventory sequence must be between 1 and 99');
    string memory sequence = vm.toString(value);
    return value < 10 ? string.concat('0', sequence) : sequence;
  }

  function _expectedExecutor() internal returns (address executor) {
    executor = vm.envOr('EXPECTED_EXECUTOR', address(0));
    if (executor == address(0)) {
      revert('EXPECTED_EXECUTOR is required in OWNER_MODE=plan');
    }
  }

  function _planCodePresentPredicate(string memory output) internal pure returns (string memory) {
    return string.concat('{"type":"codePresent","target":', _ref(output), '}');
  }

  function _planCallEqPredicate(
    string memory output,
    string memory signature,
    string memory argsJson,
    string memory expectedJson
  ) internal pure returns (string memory) {
    return _planCallEqPredicateForTarget(_ref(output), signature, argsJson, expectedJson);
  }

  function _planCallEqPredicateForTarget(
    string memory target,
    string memory signature,
    string memory argsJson,
    string memory expectedJson
  ) internal pure returns (string memory) {
    return
      string.concat(
        '{"type":"callEq","target":',
        target,
        ',"call":{"sig":',
        _quoted(signature),
        ',"args":',
        argsJson,
        '},"expect":',
        expectedJson,
        '}'
      );
  }

  function _planEntry(
    Deployments memory deployments,
    DeployPlanEntry memory entry
  ) internal returns (string memory entryPath) {
    address expectedExecutor = _expectedExecutor();
    string memory json = string.concat(
      '{"id":',
      _quoted(entry.id),
      ',"kind":"deploy","artifactName":',
      _quoted(entry.artifactName),
      ',"constructorArgs":{"decoded":',
      entry.decodedConstructorArgs,
      '},"output":',
      _quoted(entry.output)
    );
    json = string.concat(
      json,
      ',"description":',
      _quoted(entry.description),
      ',"envelope":{"chainId":',
      vm.toString(block.chainid),
      ',"expectedExecutor":',
      _quoted(vm.toString(expectedExecutor)),
      ',"to":null,"value":"0","data":"initCode+constructorArgs",',
      '"gasLimitPolicy":"estimate*1.3","nonceCheck":"display-and-confirm"}'
    );
    json = string.concat(
      json,
      ',"predicate":',
      entry.predicate,
      ',"after":',
      _jsonStringArray(entry.afterEntries),
      '}'
    );

    string memory planEntriesDir = pathJoin(deployments.dir, 'plan-entries');
    mkdir(planEntriesDir);
    entryPath = pathJoin(
      planEntriesDir,
      string.concat(_sequence(entry.sequence), '-', entry.id, '.json')
    );
    vm.writeJson(vm.serializeJson(entry.id, json), entryPath);
    console.log(string.concat('Wrote plan entry ', entry.id, ' to ', entryPath));
  }

  function _callPlanEntry(
    Deployments memory deployments,
    CallPlanEntry memory entry
  ) internal returns (string memory entryPath) {
    address expectedExecutor = _expectedExecutor();
    string memory json = string.concat(
      '{"id":',
      _quoted(entry.id),
      ',"kind":"call","to":',
      entry.to,
      ',"functionSignature":',
      _quoted(entry.functionSignature),
      ',"args":',
      entry.decodedArgs
    );
    json = string.concat(
      json,
      ',"description":',
      _quoted(entry.description),
      ',"envelope":{"chainId":',
      vm.toString(block.chainid),
      ',"expectedExecutor":',
      _quoted(vm.toString(expectedExecutor)),
      ',"to":',
      entry.to,
      ',"value":"0","data":"functionSignature+args",',
      '"gasLimitPolicy":"estimate*1.3","nonceCheck":"display-and-confirm"}'
    );
    json = string.concat(
      json,
      ',"predicate":',
      entry.predicate,
      ',"after":',
      _jsonStringArray(entry.afterEntries),
      '}'
    );

    string memory planEntriesDir = pathJoin(deployments.dir, 'plan-entries');
    mkdir(planEntriesDir);
    entryPath = pathJoin(
      planEntriesDir,
      string.concat(_sequence(entry.sequence), '-', entry.id, '.json')
    );
    vm.writeJson(vm.serializeJson(entry.id, json), entryPath);
    console.log(string.concat('Wrote plan entry ', entry.id, ' to ', entryPath));
  }

  function _inventoryRecord(
    Deployments memory deployments,
    uint256 sequence,
    string memory label,
    string memory recordJson
  ) internal returns (string memory recordPath) {
    if (_containsDot(label)) revert('Inventory record labels must not contain dots');
    string memory pendingDir = pathJoin(deployments.dir, 'inventory-pending');
    mkdir(pendingDir);
    recordPath = pathJoin(pendingDir, string.concat(_sequence(sequence), '-', label, '.json'));
    vm.writeJson(vm.serializeJson(label, recordJson), recordPath);
    console.log(string.concat('Wrote pending inventory record to ', recordPath));
  }
}

/// @dev v2.5 scripts inherit this compatibility layer so the legacy revolving
///      script can retain its pre-v2.5 `_ownerMode()` implementation unchanged.
abstract contract V25DeployScriptBase is DeployScriptBase {
  function _ownerMode() internal returns (string memory mode) {
    return _resolveOwnerMode();
  }
}
