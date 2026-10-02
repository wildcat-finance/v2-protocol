// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // LibDeployment
// ║  ██▀▀     ▀▀██   Deployment execution, init-code storage, and artifact records.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  DEPLOYMENT INITIALIZATION
// ║  getDeployments()
// ║  getDeploymentsForNetwork(...)
// ║
// ║  DEPLOYMENT
// ║  getOrDeploy(...)
// ║  getOrDeploy(...)
// ║  getOrDeploy(...)
// ║  deploy(...)
// ║  getDeployment(...)
// ║
// ║  INIT-CODE STORAGE
// ║  getOrDeployInitcodeStorage(...)
// ║  getOrDeployInitcodeStorageByLabel(...)
// ║  isValidInitCodeStorage(...)
// ║  initCodeStorageRuntime(...)
// ║  initCodeStorageSecondary(...)
// ║
// ║  BROADCASTING
// ║  withPrivateKeyVarName(...)
// ║  broadcastCreate(...)
// ║  broadcastDeployInitcode(...)
// ║  broadcast(...)
// ║  broadcastAs(...)
// ║
// ║  ARTIFACT RECORDS
// ║  addArtifactWithoutDeploying(...)
// ║  pushArtifactFor(...)
// ║  pushArtifact(...)
// ║  write(...)
// ║  writeDeploymentArtifact(...)
// ║  findForgeArtifact(...)
// ║
// ║  NETWORK AND ARTIFACT PATHS
// ║  getNetworkName()
// ║  getForgeOutputDirectory()
// ║  parseContractNamePath(...)
// ║
// ║  FILESYSTEM PATHS
// ║  mkdir(...)
// ║  pathJoin(...)
// ║  join(...)
// ║
// ║  COMPILER INPUT EXPORT
// ║  writeStandardJson(...)
// ║  checkForBashFile()
// ║
// ║  JSON OBJECTS
// ║  create()
// ║  create(...)
// ║  set(...)
// ║  set(...)
// ║  set(...)
// ║  has(...)
// ║  has(...)
// ║  get(...)
// ║  get(...)
// ║  getBytes(...)
// ║  write(...)
// ║
// ║  ENVIRONMENT CHECKS
// ║  checkFfiEnabled()
// ║  isFfiEnabled()
// ║  checkDirectoryExistsAndAccessible(...)
// ╚═════

import { Vm as ForgeVM } from 'forge-std/Vm.sol';
import { console } from 'forge-std/console.sol';
import 'solady/utils/LibString.sol';

string constant bashFilePath = 'deployments/write-standard-json.sh';
import 'src/libraries/LibStoredInitCode.sol';
import 'src/libraries/LibSplitInitCode.sol';
import './PreparedInitCodeStorage.sol';

using LibString for string;
using LibString for address;
using LibString for bytes;
using JsonUtil for Json global;
using JsonUtil for Deployments global;
using LibDeployment for Deployments global;
using LibDeployment for ContractArtifact global;

ForgeVM constant forgeVm = ForgeVM(address(uint160(uint256(keccak256('hevm cheat code')))));

/// @param dir               output directory: `deployments/<network-name>`.
/// @param forgeOutDir       Forge output directory.
/// @param filePath          path to deployments.json.
/// @param deployments       in-memory deployment index.
/// @param privateKeyVarName environment variable holding the private key.
/// @param artifacts         newly created deployment artifacts awaiting a write.
struct Deployments {
  string dir;
  string forgeOutDir;
  string filePath;
  Json deployments;
  string privateKeyVarName;
  ContractArtifact[] artifacts;
}

/// @param namePath        contract name or qualified path, e.g. `Counter` or `src/Counter.sol:Counter`.
/// @param name            contract name, e.g. `Counter`.
/// @param artifactDir     output directory for this deployment's artifact.
/// @param customLabel     custom key for the deployment index and output file.
/// @param constructorArgs ABI-encoded constructor arguments.
/// @param deployment      deployed contract address.
struct ContractArtifact {
  string namePath;
  /// contract name.
  string name;
  string artifactDir;
  string customLabel;
  bytes constructorArgs;
  address deployment;
}

struct Json {
  string id;
  string serialized;
}

// ░░▒▒▓▓██ [ DEPLOYMENT INITIALIZATION ] ──────────────────────────────────────

// ┌─ getDeployments ─────
function getDeployments() returns (Deployments memory deployments) {
  string memory networkName = getNetworkName();
  deployments = getDeploymentsForNetwork(networkName);
  deployments.privateKeyVarName = join('PVT_KEY', networkName.upper(), '_');
}

// ┌─ getDeploymentsForNetwork ─────
/// @dev load a network's deployment index, creating its directory if needed.
function getDeploymentsForNetwork(string memory networkName) returns (Deployments memory deployments) {
  checkFfiEnabled();
  deployments.dir = pathJoin('deployments', networkName);
  checkDirectoryExistsAndAccessible(deployments.dir, true);
  deployments.filePath = pathJoin(deployments.dir, 'deployments.json');
  deployments.forgeOutDir = getForgeOutputDirectory();
  checkDirectoryExistsAndAccessible(deployments.forgeOutDir, false);

  if (forgeVm.exists(deployments.filePath)) {
    console.log(string.concat('Reading deployments from ', deployments.filePath));
    deployments.deployments = JsonUtil.create(forgeVm.readFile(deployments.filePath));
  } else {
    console.log(string.concat('No deployments found at ', deployments.filePath, '. Creating new deployments file'));
    deployments.deployments = JsonUtil.create();
  }
}

// ┌─ LibDeployment ────────────────────────────────────────────────────────────
/// @title Deployer
///
/// @author d1ll0n
///
/// @dev deployment index and artifact persistence for Forge scripts.
///
/// deploy or reuse contracts, then save compiler output, standard input JSON, and
/// constructor arguments with each deployment.
///
///
///
/// ===================================================================================
///                                   Private Key
/// ===================================================================================
///  default: `PVT_KEY_<NETWORK NAME>`, falling back to Foundry's configured key.
///
///  select another variable with `deployments.withPrivateKeyVarName(name)`.
///
/// ===================================================================================
///                              Setup Instructions
/// ===================================================================================
///
/// 1. grant access to the `deployments` directory and to the forge output directory.
///    add this to foundry.toml:
///         fs_permissions = [
///             { access = "read-write", path = "./deployments/"},
///             { access = "read-write", path = "./out/"},
///         ]
///    replace `./out/` if the deployment profile uses another output directory.
///    the script reads that profile's configured path.
///
/// 2. enable FFI (`ffi=true` in foundry.toml) for the shell commands that generate
///    deployment standard input JSON.
library LibDeployment {
  using LibDeployment for Json;
  using LibDeployment for ContractArtifact[];

  string internal constant PreparedStorageArtifact =
    'script/common/PreparedInitCodeStorage.sol:PreparedInitCodeStorage';
  string internal constant LinkedStorageArtifact = 'script/common/PreparedInitCodeStorage.sol:LinkedInitCodeStorage';

  // ░░▒▒▓▓██ [ DEPLOYMENT ] ───────────────────────────────────────────────────

  // ┌─ getOrDeploy ─────
  /// @dev reuse an indexed deployment unless `overrideExisting` is true. otherwise deploy,
  ///      update the in-memory index, and queue its artifact. `write` persists the index,
  ///      compiler output, standard input JSON, and constructor arguments.
  /// @param self             deployment index and pending artifacts.
  ///
  /// @param namePath         contract name or qualified path, e.g. `Counter` or `src/Counter.sol:Counter`.
  ///
  /// @param creationCode     creation code without constructor arguments.
  ///
  /// @param constructorArgs  ABI-encoded constructor arguments.
  ///
  /// @param overrideExisting whether to replace an already-indexed deployment.
  ///
  /// @return deployment deployed or reused contract address.
  /// @return didDeploy false when an existing deployment was reused.
  function getOrDeploy(
    Deployments memory self,
    string memory namePath,
    bytes memory creationCode,
    bytes memory constructorArgs,
    bool overrideExisting
  )
    internal
    returns (address deployment, bool didDeploy)
  {
    ContractArtifact memory artifact = parseContractNamePath(namePath);
    if (overrideExisting || !self.has(artifact.name)) {
      deployment = broadcastCreate(self, creationCode, constructorArgs);
      didDeploy = true;

      artifact.deployment = deployment;
      artifact.constructorArgs = constructorArgs;

      self.set(artifact.name, deployment);
      self.pushArtifact(artifact);

      console.log(string.concat('Deployed ', namePath, ' to'), deployment);
    } else {
      deployment = self.get(artifact.name);
      console.log(string.concat('Found ', namePath, ' at'), deployment);
    }
  }

  // ┌─ getOrDeploy ─────
  function getOrDeploy(
    Deployments memory deployments,
    string memory namePath,
    bytes memory creationCode,
    bytes memory constructorArgs
  )
    internal
    returns (address deployment, bool didDeploy)
  {
    return getOrDeploy(deployments, namePath, creationCode, constructorArgs, false);
  }

  // ┌─ getOrDeploy ─────
  function getOrDeploy(
    Deployments memory self,
    string memory namePath,
    bytes memory creationCode,
    bool overrideExisting
  )
    internal
    returns (address deployment, bool didDeploy)
  {
    return getOrDeploy(self, namePath, creationCode, '', overrideExisting);
  }

  // ┌─ deploy ─────
  function deploy(
    Deployments memory deployments,
    string memory namePath,
    bytes memory creationCode,
    bytes memory constructorArgs
  )
    internal
    returns (address deployment)
  {
    (deployment,) = getOrDeploy(deployments, namePath, creationCode, constructorArgs, true);
  }

  // ┌─ getDeployment ─────
  function getDeployment(Deployments memory self, string memory namePath) internal returns (address deployment) {
    ContractArtifact memory artifact = parseContractNamePath(namePath);
    return self.get(artifact.name);
  }

  // ░░▒▒▓▓██ [ INIT-CODE STORAGE ] ────────────────────────────────────────────

  // ┌─ getOrDeployInitcodeStorage ─────
  function getOrDeployInitcodeStorage(
    Deployments memory self,
    string memory namePath,
    bytes memory creationCode,
    bool overrideExisting
  )
    internal
    returns (address deployment, bool didDeploy)
  {
    ContractArtifact memory artifact = parseContractNamePath(namePath);
    string memory label = string.concat(artifact.name, '_initCodeStorage');
    return getOrDeployInitcodeStorageByLabel(self, label, creationCode, overrideExisting);
  }

  // ┌─ getOrDeployInitcodeStorageByLabel ─────
  function getOrDeployInitcodeStorageByLabel(
    Deployments memory self,
    string memory label,
    bytes memory creationCode,
    bool overrideExisting
  )
    internal
    returns (address deployment, bool didDeploy)
  {
    bytes memory runtime = initCodeStorageRuntime(creationCode);
    string memory secondaryLabel = string.concat(label, '_secondary');
    if (!overrideExisting && self.has(label)) {
      deployment = self.get(label);
      require(isValidInitCodeStorage(deployment, creationCode), 'Stored init code mismatch');
      address secondary = initCodeStorageSecondary(deployment);
      if (secondary != address(0)) {
        if (self.has(secondaryLabel)) {
          require(self.get(secondaryLabel) == secondary, 'Stored secondary address mismatch');
        } else {
          // recover the inventory link only after authenticating both complete runtimes.
          self.addArtifactWithoutDeploying(
            secondaryLabel,
            PreparedStorageArtifact,
            secondary,
            abi.encode(LibSplitInitCode.getSecondaryRuntime(creationCode))
          );
        }
      }
      return (deployment, false);
    }

    if (creationCode.length <= 24_575) {
      bytes memory args = abi.encode(runtime);
      deployment = self.broadcastCreate(type(PreparedInitCodeStorage).creationCode, args);
      self.addArtifactWithoutDeploying(label, PreparedStorageArtifact, deployment, args);
    } else {
      bytes memory secondaryRuntime = LibSplitInitCode.getSecondaryRuntime(creationCode);
      address secondary;
      if (!overrideExisting && self.has(secondaryLabel)) {
        secondary = self.get(secondaryLabel);
        require(secondary.codehash == keccak256(secondaryRuntime), 'Stored secondary code mismatch');
      } else {
        bytes memory secondaryArgs = abi.encode(secondaryRuntime);
        secondary = self.broadcastCreate(type(PreparedInitCodeStorage).creationCode, secondaryArgs);
        self.addArtifactWithoutDeploying(secondaryLabel, PreparedStorageArtifact, secondary, secondaryArgs);
      }
      bytes memory args = abi.encode(runtime, secondary);
      deployment = self.broadcastCreate(type(LinkedInitCodeStorage).creationCode, args);
      self.addArtifactWithoutDeploying(label, LinkedStorageArtifact, deployment, args);
    }
    require(isValidInitCodeStorage(deployment, creationCode), 'Stored init code mismatch');
    return (deployment, true);
  }

  // ┌─ isValidInitCodeStorage ─────
  /// @dev the artifact is the trust anchor. matching one reader response isn't enough:
  ///      a different executable store could return different code to the factory.
  function isValidInitCodeStorage(address deployment, bytes memory creationCode) internal view returns (bool) {
    if (deployment.code.length == 0 || deployment.code.length > 24_576) return false;
    if (creationCode.length > LibSplitInitCode.maximumInitCodeSize()) return false;
    bytes memory expectedRuntime;
    if (deployment.code[0] == bytes1(0)) {
      expectedRuntime = bytes.concat(hex'00', creationCode);
    } else {
      address secondary = initCodeStorageSecondary(deployment);
      if (secondary.codehash != keccak256(LibSplitInitCode.getSecondaryRuntime(creationCode))) {
        return false;
      }
      expectedRuntime = LibSplitInitCode.getPrimaryRuntime(creationCode, secondary);
    }
    if (deployment.codehash != keccak256(expectedRuntime)) return false;
    return keccak256(LibStoredInitCode.getInitCode(deployment)) == keccak256(creationCode);
  }

  // ┌─ initCodeStorageRuntime ─────
  /// @dev an oversized artifact returns an unlinked primary image. bind its secondary at install.
  function initCodeStorageRuntime(bytes memory creationCode) internal pure returns (bytes memory) {
    if (creationCode.length <= 24_575) return bytes.concat(hex'00', creationCode);
    return LibSplitInitCode.getPrimaryRuntime(creationCode, address(0));
  }

  // ┌─ initCodeStorageSecondary ─────
  function initCodeStorageSecondary(address deployment) internal view returns (address secondary) {
    return LibSplitInitCode.getSecondaryAddress(deployment);
  }

  // ░░▒▒▓▓██ [ BROADCASTING ] ─────────────────────────────────────────────────

  // ┌─ withPrivateKeyVarName ─────
  function withPrivateKeyVarName(
    Deployments memory deployments,
    string memory privateKeyVarName
  )
    internal
    pure
    returns (Deployments memory)
  {
    deployments.privateKeyVarName = privateKeyVarName;
    return deployments;
  }

  // ┌─ broadcastCreate ─────
  function broadcastCreate(
    Deployments memory deployments,
    bytes memory creationCode,
    bytes memory constructorArgs
  )
    internal
    returns (address deployment)
  {
    bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
    deployments.broadcast();
    assembly {
      deployment := create(0, add(initCode, 0x20), mload(initCode))
    }
    if (deployment == address(0)) {
      revert('Failed to deploy contract');
    }
  }

  // ┌─ broadcastDeployInitcode ─────
  function broadcastDeployInitcode(
    Deployments memory deployments,
    bytes memory creationCode
  )
    internal
    returns (address deployment)
  {
    bytes memory runtime = initCodeStorageRuntime(creationCode);
    if (creationCode.length <= 24_575) {
      return deployments.broadcastCreate(type(PreparedInitCodeStorage).creationCode, abi.encode(runtime));
    }
    address secondary = deployments.broadcastCreate(
      type(PreparedInitCodeStorage).creationCode, abi.encode(LibSplitInitCode.getSecondaryRuntime(creationCode))
    );
    return deployments.broadcastCreate(type(LinkedInitCodeStorage).creationCode, abi.encode(runtime, secondary));
  }

  // ┌─ broadcast ─────
  function broadcast(Deployments memory deployments) internal {
    uint256 key = forgeVm.envOr(deployments.privateKeyVarName, uint256(0));
    if (key == 0) {
      forgeVm.broadcast();
    } else {
      forgeVm.broadcast(key);
    }
  }

  // ┌─ broadcastAs ─────
  function broadcastAs(Deployments memory deployments, string memory pvtKeyVarName) internal {
    uint256 key = forgeVm.envOr(pvtKeyVarName, uint256(0));
    if (key == 0) {
      revert(string.concat('Private key not found in environment variable ', pvtKeyVarName));
    }
    forgeVm.broadcast(key);
  }

  // ░░▒▒▓▓██ [ ARTIFACT RECORDS ] ─────────────────────────────────────────────

  // ┌─ addArtifactWithoutDeploying ─────
  function addArtifactWithoutDeploying(
    Deployments memory self,
    string memory customLabel,
    string memory namePath,
    address deploymentAddress,
    bytes memory constructorArgs
  )
    internal
  {
    ContractArtifact memory artifact = parseContractNamePath(namePath);
    artifact.customLabel = customLabel;
    artifact.deployment = deploymentAddress;
    artifact.constructorArgs = constructorArgs;

    self.set(customLabel, deploymentAddress);
    self.pushArtifact(artifact);
  }

  // ┌─ pushArtifactFor ─────
  function pushArtifactFor(
    Deployments memory deployments,
    string memory namePath
  )
    internal
    pure
    returns (ContractArtifact memory)
  {
    ContractArtifact memory artifact = parseContractNamePath(namePath);
    deployments.pushArtifact(artifact);
    return artifact;
  }

  // ┌─ pushArtifact ─────
  function pushArtifact(Deployments memory deployments, ContractArtifact memory artifact) internal pure {
    ContractArtifact[] memory artifacts = deployments.artifacts;
    ContractArtifact[] memory newArtifacts = new ContractArtifact[](artifacts.length + 1);
    for (uint256 i = 0; i < artifacts.length; i++) {
      newArtifacts[i] = artifacts[i];
    }
    newArtifacts[artifacts.length] = artifact;
    deployments.artifacts = newArtifacts;
  }

  // ┌─ write ─────
  /// @dev persist the current name-to-address index in `deployments/<network-name>/deployments.json`.
  ///      write each new deployment's compiler output, standard input JSON, and constructor
  ///      arguments (if any) into its own artifact directory.
  function write(Deployments memory deployments) internal {
    deployments.deployments.write(deployments.filePath);
    console.log(string.concat('Wrote deployments to ', deployments.filePath));
    for (uint256 i = 0; i < deployments.artifacts.length; i++) {
      ContractArtifact memory artifact = deployments.artifacts[i];
      writeDeploymentArtifact(deployments, artifact);
    }
  }

  // ┌─ writeDeploymentArtifact ─────
  /// @dev write compiler output, standard input JSON, and any constructor arguments under
  ///      `deployments/<network-name>/<contract-name>-<deployment-address>/`.
  ///      a custom label replaces the final directory name.
  function writeDeploymentArtifact(Deployments memory deployments, ContractArtifact memory artifact) internal {
    string memory deploymentName = bytes(artifact.customLabel).length > 0
      ? artifact.customLabel
      : string.concat(artifact.name, '-', artifact.deployment.toHexString());

    artifact.artifactDir = pathJoin(deployments.dir, deploymentName);
    mkdir(artifact.artifactDir);

    StandardInputJson.writeStandardJson(artifact);
    if (artifact.constructorArgs.length > 0) {
      forgeVm.writeFile(pathJoin(artifact.artifactDir, 'constructor-args'), artifact.constructorArgs.toHexString());
    }
    string memory jsonPath = findForgeArtifact(artifact, deployments.forgeOutDir);
    forgeVm.copyFile(jsonPath, pathJoin(artifact.artifactDir, 'output.json'));

    console.log(string.concat('Wrote deployment artifact to ', artifact.artifactDir));
  }

  // ┌─ findForgeArtifact ─────
  function findForgeArtifact(
    ContractArtifact memory artifact,
    string memory forgeOutDir
  )
    internal
    returns (string memory)
  {
    if (bytes(artifact.namePath).length != bytes(artifact.name).length) {
      string memory namePath = artifact.namePath.split(':')[0];
      string[] memory components = namePath.split('/');
      string memory fileName = components[components.length - 1];
      fileName = string.concat(fileName, '/', artifact.name, '.json');
      for (uint256 i = components.length - 1; i > 0; i--) {
        string memory prev = components[i - 1];
        fileName = pathJoin(prev, fileName);
        string memory searchPath = pathJoin(forgeOutDir, fileName);
        if (forgeVm.exists(searchPath)) {
          return searchPath;
        }
      }
    }
    string memory jsonPath = pathJoin(forgeOutDir, string.concat(artifact.name, '.sol/', artifact.name, '.json'));
    if (forgeVm.exists(jsonPath)) {
      return jsonPath;
    }
    revert(string.concat('Could not find forge artifact for ', artifact.name, ' in ', forgeOutDir));
  }
}

// ░░▒▒▓▓██ [ NETWORK AND ARTIFACT PATHS ] ─────────────────────────────────────

// ┌─ getNetworkName ─────
function getNetworkName() view returns (string memory) {
  return block.chainid == 1 ? 'mainnet' : block.chainid == 11155111 ? 'sepolia' : '';
}

// ┌─ getForgeOutputDirectory ─────
/// @dev query Forge's output directory through FFI. the subprocess inherits the running
///      script's Foundry profile.
function getForgeOutputDirectory() returns (string memory) {
  string[] memory args = new string[](4);
  args[0] = 'forge';
  args[1] = 'config';
  args[2] = '--basic';
  args[3] = '--json';
  return forgeVm.parseJsonString(string(forgeVm.ffi(args)), '.out');
}

// ┌─ parseContractNamePath ─────
function parseContractNamePath(string memory namePath) pure returns (ContractArtifact memory path) {
  path.namePath = namePath;
  // contract-name extraction:
  // Counter => Counter
  // src/Counter.sol:Counter => Counter
  uint256 indexOfSlash = namePath.indexOf('/');
  if (indexOfSlash == LibString.NOT_FOUND) {
    path.name = namePath;
  } else {
    uint256 indexOfColon = namePath.indexOf(':');
    if (indexOfColon == LibString.NOT_FOUND) {
      revert('Invalid contract name path. Should be <contract-name> or <path>:<contract-name>');
    }
    path.name = namePath.slice(indexOfColon + 1);
  }
}

// ░░▒▒▓▓██ [ FILESYSTEM PATHS ] ───────────────────────────────────────────────

// ┌─ mkdir ─────
function mkdir(string memory path) {
  if (!forgeVm.exists(path)) {
    forgeVm.createDir(path, true);
  }
}

// ┌─ pathJoin ─────
function pathJoin(string memory a, string memory b) pure returns (string memory) {
  uint aLen;
  uint bLen;
  assembly {
    aLen := mload(a)
    bLen := mload(b)
  }
  if (a.endsWith('/')) {
    a = a.slice(0, aLen - 1);
  }
  if (b.startsWith('/')) {
    b = b.slice(1);
  }
  return join(a, b, '/');
}

// ┌─ join ─────
function join(string memory a, string memory b, string memory separator) pure returns (string memory) {
  if (bytes(a).length == 0) return b;
  if (bytes(b).length == 0) return a;
  return string.concat(a, separator, b);
}

// ┌─ StandardInputJson ────────────────────────────────────────────────────────
library StandardInputJson {
  // ░░▒▒▓▓██ [ COMPILER INPUT EXPORT ] ────────────────────────────────────────

  // ┌─ writeStandardJson ─────
  function writeStandardJson(ContractArtifact memory artifact) internal {
    checkForBashFile();
    string[] memory args = new string[](4);
    args[0] = 'bash';
    args[1] = bashFilePath;
    args[2] = artifact.namePath;
    args[3] = pathJoin(artifact.artifactDir, 'standard-input.json');
    bytes memory result = forgeVm.ffi(args);
    bytes32 resultBytes;
    assembly {
      resultBytes := mload(add(result, 32))
    }
    if (resultBytes != 'ok') {
      if (result.length > 0) {
        console.logBytes('Output from bash script:');
        console.logBytes(result);
      }
      revert(string.concat('Failed to write standard input json for ', artifact.namePath));
    }
    console.logBytes(result);
  }

  // ┌─ checkForBashFile ─────
  function checkForBashFile() internal {
    if (!forgeVm.exists(bashFilePath)) {
      string memory bashFile =
        'forge verify-contract --show-standard-json-input 0x0000000000000000000000000000000000000000 $1 > $2 && echo ok';
      forgeVm.writeFile(bashFilePath, bashFile);
      console.log(string.concat('Wrote bash file to ', bashFilePath));
    }
  }
}

// ┌─ JsonUtil ─────────────────────────────────────────────────────────────────
library JsonUtil {
  bytes32 internal constant JSON_ID_SLOT = bytes32(uint256(keccak256('deployments.json.id')) - 1);

  // ░░▒▒▓▓██ [ JSON OBJECTS ] ─────────────────────────────────────────────────

  // ┌─ create ─────
  function create() internal returns (Json memory json) {
    bytes32 jsonIdSlot = JSON_ID_SLOT;
    assembly {
      let counter := sload(jsonIdSlot)
      sstore(jsonIdSlot, add(counter, 1))

      // Foundry scripts reject address(this), so derive a per-run unique ID
      // from chain id and the monotonic counter instead.
      mstore(0, chainid())
      mstore(32, counter)
      let id := keccak256(0, 64)

      let ptr := mload(0x40)
      mstore(ptr, 32)
      mstore(0x40, add(ptr, 64))

      mstore(add(ptr, 32), id)
      mstore(json, ptr)
    }
  }

  // ┌─ create ─────
  function create(string memory jsonString) internal returns (Json memory json) {
    json = create();
    json.serialized = forgeVm.serializeJson(json.id, jsonString);
  }

  // ┌─ set ─────
  function set(Json memory self, string memory key, address value) internal {
    self.serialized = forgeVm.serializeAddress(self.id, key, value);
  }

  // ┌─ set ─────
  function set(Json memory self, string memory key, Json memory value) internal {
    self.serialized = forgeVm.serializeString(self.id, key, value.serialized);
  }

  // ┌─ set ─────
  function set(Deployments memory deployments, string memory name, address value) internal {
    deployments.deployments.set(name, value);
  }

  // ┌─ has ─────
  function has(Json memory self, string memory key) internal view returns (bool) {
    // a new Json has an empty `serialized` until the first set;
    // vm.keyExists cannot parse an empty string.
    if (bytes(self.serialized).length == 0) return false;
    return forgeVm.keyExists(self.serialized, string.concat('.', key));
  }

  // ┌─ has ─────
  function has(Deployments memory deployments, string memory name) internal view returns (bool) {
    return has(deployments.deployments, name);
  }

  // ┌─ get ─────
  function get(Json memory json, string memory key) internal pure returns (address) {
    return forgeVm.parseJsonAddress(json.serialized, string.concat('.', key));
  }

  // ┌─ get ─────
  function get(Deployments memory deployments, string memory name) internal pure returns (address) {
    return get(deployments.deployments, name);
  }

  // ┌─ getBytes ─────
  function getBytes(Json memory json, string memory key) internal pure returns (bytes memory) {
    return forgeVm.parseJsonBytes(json.serialized, string.concat('.', key));
  }

  // ┌─ write ─────
  function write(Json memory self, string memory filePath) internal {
    forgeVm.writeFile(filePath, self.serialized);
  }
}

// ░░▒▒▓▓██ [ ENVIRONMENT CHECKS ] ─────────────────────────────────────────────

// ┌─ checkFfiEnabled ─────
function checkFfiEnabled() {
  if (!isFfiEnabled()) {
    revert(
      'LibDeployment requires FFI to generate standard input json files. Please enable FFI in foundry.toml using `ffi=true`.'
    );
  }
}

// ┌─ isFfiEnabled ─────
function isFfiEnabled() returns (bool result) {
  string[] memory args = new string[](2);
  args[0] = 'echo';
  args[1] = 'ok';
  try forgeVm.ffi(args) returns (bytes memory result) {
    bytes32 resultBytes;
    assembly {
      resultBytes := mload(add(result, 32))
    }
    if (resultBytes != 'ok') {
      if (result.length > 0) {
        console.logBytes('Unexpected output from bash script:');
        console.logBytes(result);
      }
      revert('Failed to validate FFI access.');
    }
    return true;
  } catch {
    result = false;
  }
}

// ┌─ checkDirectoryExistsAndAccessible ─────
function checkDirectoryExistsAndAccessible(string memory dir, bool writeAccess) {
  string memory requestString =
    string.concat(' Please grant read', writeAccess ? '-write' : '', ' permission for `', dir, '` in foundry.toml.');
  string memory readErrorMessage =
    string.concat('LibDeployment requires access to the `', dir, '` directory.', requestString);
  string memory writeErrorMessage = string.concat(
    'LibDeployment requires access to the `',
    dir,
    '` directory but',
    ' the current configuration only provides read access.',
    requestString
  );
  bool dirExists;
  try forgeVm.exists(dir) returns (bool exists) {
    dirExists = exists;
  } catch {
    revert(readErrorMessage);
  }
  if (dirExists && !writeAccess) {
    return;
  }
  if (!dirExists) {
    try forgeVm.createDir(dir, true) {
      console.log(string.concat('Created directory: ', dir));
    } catch {
      revert(writeErrorMessage);
    }
  }
  try forgeVm.writeFile(pathJoin(dir, 'test'), '') {
    forgeVm.removeFile(pathJoin(dir, 'test'));
  } catch {
    revert(writeErrorMessage);
  }
}
