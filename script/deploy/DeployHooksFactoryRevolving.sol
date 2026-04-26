// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {console} from "forge-std/console.sol";

import {IWildcatArchController} from "src/interfaces/IWildcatArchController.sol";
import {IHooksFactoryRevolving} from "src/IHooksFactoryRevolving.sol";

import "../common/DeployScriptBase.sol";

contract DeployHooksFactoryRevolving is DeployScriptBase {
    struct RegistrationResult {
        address archControllerOwner;
        address broadcaster;
        bool hasDirectOwnerAuthority;
        bool didRegisterControllerFactory;
        bool didRegisterController;
        bool didEmitPendingAdminAction;
        bool isControllerFactoryRegistered;
        bool isControllerRegistered;
    }

    struct RevolvingDeploymentResult {
        address revolvingMarketInitCodeStorage;
        uint256 revolvingMarketInitCodeHash;
        address hooksFactoryRevolving;
        bool didDeployRevolvingMarketInitCodeStorage;
        bool didDeployHooksFactoryRevolving;
    }

    struct CanonicalAliasResult {
        bool updateCanonicalAliases;
        bool didUpdateCanonicalInitCodeStorage;
        bool didUpdateCanonicalHooksFactory;
    }

    function _deploymentLabel(string memory baseLabel, string memory deploymentLabelSuffix)
        internal
        pure
        returns (string memory)
    {
        return string.concat(baseLabel, "_", deploymentLabelSuffix);
    }

    function _boolString(bool value) internal pure returns (string memory) {
        return value ? "true" : "false";
    }

    function _deploymentLabelSuffix() internal returns (string memory deploymentLabelSuffix) {
        deploymentLabelSuffix = vm.envOr("HOOKS_FACTORY_REVOLVING_DEPLOYMENT_LABEL", string(""));
        if (bytes(deploymentLabelSuffix).length == 0) {
            deploymentLabelSuffix = vm.envOr("HOOKS_FACTORY_REVOLVING_DEPLOYMENT_TAG", string(""));
        }
        if (bytes(deploymentLabelSuffix).length == 0) {
            revert("Missing HOOKS_FACTORY_REVOLVING_DEPLOYMENT_LABEL");
        }
    }

    function _getOrDeployByLabel(
        Deployments memory deployments,
        string memory deploymentLabel,
        string memory contractName,
        bytes memory creationCode,
        bytes memory constructorArgs,
        bool overrideExisting
    ) internal returns (address deployment, bool didDeploy) {
        if (overrideExisting || !deployments.has(deploymentLabel)) {
            deployment = deployments.broadcastCreate(creationCode, constructorArgs);
            didDeploy = true;
            deployments.addArtifactWithoutDeploying(deploymentLabel, contractName, deployment, constructorArgs);
            console.log(string.concat("Deployed ", deploymentLabel, " to"), deployment);
        } else {
            deployment = deployments.get(deploymentLabel);
            console.log(string.concat("Found ", deploymentLabel, " at"), deployment);
        }
    }

    function _getOrDeployInitcodeStorageByLabel(
        Deployments memory deployments,
        string memory deploymentLabel,
        string memory contractName,
        bytes memory creationCode,
        bool overrideExisting
    ) internal returns (address deployment, bool didDeploy) {
        if (overrideExisting || !deployments.has(deploymentLabel)) {
            deployment = deployments.broadcastDeployInitcode(creationCode);
            didDeploy = true;

            ContractArtifact memory artifact = parseContractNamePath(contractName);
            artifact.customLabel = deploymentLabel;
            artifact.deployment = deployment;

            deployments.set(deploymentLabel, deployment);
            deployments.pushArtifact(artifact);
            console.log(string.concat("Deployed ", deploymentLabel, " to"), deployment);
        } else {
            deployment = deployments.get(deploymentLabel);
            console.log(string.concat("Found ", deploymentLabel, " at"), deployment);
        }
    }

    function _factoryInventoryLabel(string memory deploymentLabelSuffix)
        internal
        returns (string memory inventoryLabel)
    {
        inventoryLabel = vm.envOr("HOOKS_FACTORY_REVOLVING_INVENTORY_LABEL", string(""));
        if (bytes(inventoryLabel).length == 0) {
            inventoryLabel = string.concat("revolving-", deploymentLabelSuffix);
        }
    }

    function _factoryInventoryStartBlock() internal returns (uint256 startBlock) {
        startBlock = vm.envOr("HOOKS_FACTORY_REVOLVING_START_BLOCK", uint256(0));
        if (startBlock == 0) {
            startBlock = block.number;
        }
    }

    function _setCanonicalAlias(Deployments memory deployments, string memory aliasName, address target)
        internal
        returns (bool didUpdateAlias)
    {
        didUpdateAlias = !deployments.has(aliasName) || deployments.get(aliasName) != target;
        deployments.set(aliasName, target);
    }

    function _updateCanonicalAliases(
        Deployments memory deployments,
        bool updateCanonicalAliases,
        address revolvingMarketInitCodeStorage,
        address hooksFactoryRevolving
    ) internal returns (CanonicalAliasResult memory result) {
        result.updateCanonicalAliases = updateCanonicalAliases;
        if (updateCanonicalAliases) {
            result.didUpdateCanonicalInitCodeStorage = _setCanonicalAlias(
                deployments, "WildcatMarketRevolving_initCodeStorage", revolvingMarketInitCodeStorage
            );
            result.didUpdateCanonicalHooksFactory =
                _setCanonicalAlias(deployments, "HooksFactoryRevolving", hooksFactoryRevolving);
        }
    }

    function _equalStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _ownerMode() internal returns (string memory mode) {
        mode = vm.envOr("ARCH_CONTROLLER_OWNER_MODE", string("direct"));
        if (!_equalStrings(mode, "direct") && !_equalStrings(mode, "emit") && !_equalStrings(mode, "require-direct")) {
            revert("Invalid ARCH_CONTROLLER_OWNER_MODE");
        }
    }

    function _broadcasterAddress(Deployments memory deployments) internal returns (address broadcaster) {
        uint256 key = vm.envOr(deployments.privateKeyVarName, uint256(0));
        if (key == 0) {
            return address(0);
        }
        return vm.addr(key);
    }

    function _emitPendingRegisterControllerFactoryAction(
        Deployments memory deployments,
        string memory networkName,
        address archController,
        address archControllerOwner,
        address hooksFactoryRevolving
    ) internal returns (string memory artifactPath) {
        string memory objectKey = string.concat("pending-admin-action-", vm.toString(hooksFactoryRevolving));
        string memory pendingAdminDir = pathJoin(deployments.dir, "pending-admin-actions");
        mkdir(pendingAdminDir);

        bytes memory calldata_ =
            abi.encodeWithSelector(IWildcatArchController.registerControllerFactory.selector, hooksFactoryRevolving);

        string memory json = vm.serializeUint(objectKey, "chainId", block.chainid);
        json = vm.serializeString(objectKey, "network", networkName);
        json = vm.serializeString(
            objectKey, "description", "Register HooksFactoryRevolving as a controller factory in WildcatArchController"
        );
        json = vm.serializeAddress(objectKey, "target", archController);
        json = vm.serializeString(objectKey, "value", "0");
        json = vm.serializeBytes(objectKey, "data", calldata_);
        json = vm.serializeString(objectKey, "functionSignature", "registerControllerFactory(address)");
        json = vm.serializeAddress(objectKey, "archControllerOwner", archControllerOwner);
        json = vm.serializeAddress(objectKey, "factory", hooksFactoryRevolving);
        json = vm.serializeString(objectKey, "ownerMode", "emit");

        artifactPath = pathJoin(
            pendingAdminDir,
            string.concat(
                "HooksFactoryRevolving-", vm.toString(hooksFactoryRevolving), "-register-controller-factory.json"
            )
        );
        vm.writeJson(json, artifactPath);
    }

    function run() external {
        (Deployments memory deployments, string memory networkName) = _resolveDeployments();
        bool overrideExisting = vm.envOr("OVERRIDE_EXISTING", false);
        string memory deploymentLabelSuffix = _deploymentLabelSuffix();
        string memory ownerMode = _ownerMode();

        address archController = _resolveAddress(deployments, "ARCH_CONTROLLER", "WildcatArchController");
        address sanctionsSentinel = _resolveAddress(deployments, "SANCTIONS_SENTINEL", "WildcatSanctionsSentinel");

        RevolvingDeploymentResult memory deploymentResult = _deployRevolvingSet(
            deployments, deploymentLabelSuffix, overrideExisting, archController, sanctionsSentinel
        );

        RegistrationResult memory registrationResult = _ensureArchControllerRegistration(
            deployments, networkName, ownerMode, archController, deploymentResult.hooksFactoryRevolving
        );

        CanonicalAliasResult memory canonicalAliasResult = _updateCanonicalAliases(
            deployments,
            vm.envOr("UPDATE_HOOKS_FACTORY_REVOLVING_CANONICAL_ALIAS", true),
            deploymentResult.revolvingMarketInitCodeStorage,
            deploymentResult.hooksFactoryRevolving
        );

        deployments.write();
        bool didUpdateFactoryInventory = _updateFactoryInventory(
            networkName, deploymentLabelSuffix, deploymentResult, registrationResult, canonicalAliasResult
        );

        console.log("Deployment complete for network:");
        console.log(networkName);
        console.log("HooksFactoryRevolving deployment label:");
        console.log(deploymentLabelSuffix);
        console.log("HooksFactoryRevolving:");
        console.log(deploymentResult.hooksFactoryRevolving);
        console.log("Arch controller owner:");
        console.log(registrationResult.archControllerOwner);
        console.log("Broadcaster:");
        console.log(registrationResult.broadcaster);
        console.log("Has direct owner authority:");
        console.log(registrationResult.hasDirectOwnerAuthority);
        console.log("Arch controller owner mode:");
        console.log(ownerMode);
        console.log("WildcatMarketRevolving_initCodeStorage:");
        console.log(deploymentResult.revolvingMarketInitCodeStorage);
        console.log("WildcatMarketRevolving_initCodeHash:");
        console.logUint(deploymentResult.revolvingMarketInitCodeHash);
        console.log("Did deploy WildcatMarketRevolving init code storage:");
        console.log(deploymentResult.didDeployRevolvingMarketInitCodeStorage);
        console.log("Did deploy HooksFactoryRevolving:");
        console.log(deploymentResult.didDeployHooksFactoryRevolving);
        console.log("Update canonical HooksFactoryRevolving aliases:");
        console.log(canonicalAliasResult.updateCanonicalAliases);
        console.log("Did update canonical WildcatMarketRevolving_initCodeStorage alias:");
        console.log(canonicalAliasResult.didUpdateCanonicalInitCodeStorage);
        console.log("Did update canonical HooksFactoryRevolving alias:");
        console.log(canonicalAliasResult.didUpdateCanonicalHooksFactory);
        console.log("Did update factory inventory:");
        console.log(didUpdateFactoryInventory);
        console.log("Did register HooksFactoryRevolving as controller factory:");
        console.log(registrationResult.didRegisterControllerFactory);
        console.log("Did register HooksFactoryRevolving as controller:");
        console.log(registrationResult.didRegisterController);
        console.log("Did emit pending admin action:");
        console.log(registrationResult.didEmitPendingAdminAction);
        console.log("Controller factory registered:");
        console.log(registrationResult.isControllerFactoryRegistered);
        console.log("Controller registered:");
        console.log(registrationResult.isControllerRegistered);
    }

    function _updateFactoryInventory(
        string memory networkName,
        string memory deploymentLabelSuffix,
        RevolvingDeploymentResult memory deploymentResult,
        RegistrationResult memory registrationResult,
        CanonicalAliasResult memory canonicalAliasResult
    ) internal returns (bool didUpdateInventory) {
        if (!vm.envOr("UPDATE_FACTORY_INVENTORY", true)) {
            console.log("Skipping factory inventory update because UPDATE_FACTORY_INVENTORY=false");
            return false;
        }

        bool isRegistered =
            registrationResult.isControllerFactoryRegistered && registrationResult.isControllerRegistered;
        bool isCanonical = canonicalAliasResult.updateCanonicalAliases && isRegistered;
        if (canonicalAliasResult.updateCanonicalAliases && !isRegistered) {
            console.log("Recording factory inventory as non-canonical until arch-controller registration is complete");
        }

        string[] memory args = new string[](29);
        args[0] = "node";
        args[1] = "scripts/factory-inventory.js";
        args[2] = "upsert";
        args[3] = "--network";
        args[4] = networkName;
        args[5] = "--chain-id";
        args[6] = vm.toString(block.chainid);
        args[7] = "--label";
        args[8] = _factoryInventoryLabel(deploymentLabelSuffix);
        args[9] = "--market-type";
        args[10] = "revolving";
        args[11] = "--address";
        args[12] = vm.toString(deploymentResult.hooksFactoryRevolving);
        args[13] = "--start-block";
        args[14] = vm.toString(_factoryInventoryStartBlock());
        args[15] = "--canonical";
        args[16] = _boolString(isCanonical);
        args[17] = "--indexed";
        args[18] = _boolString(vm.envOr("HOOKS_FACTORY_REVOLVING_INDEXED", true));
        args[19] = "--registered";
        args[20] = _boolString(isRegistered);
        args[21] = "--deployment-key";
        args[22] = _deploymentLabel("HooksFactoryRevolving", deploymentLabelSuffix);
        args[23] = "--init-code-storage";
        args[24] = vm.toString(deploymentResult.revolvingMarketInitCodeStorage);
        args[25] = "--init-code-hash";
        args[26] = vm.toString(bytes32(deploymentResult.revolvingMarketInitCodeHash));
        args[27] = "--preserve-start-block";
        args[28] = "--create";

        bytes memory result = vm.ffi(args);
        console.log(string(result));
        return true;
    }

    function _deployRevolvingSet(
        Deployments memory deployments,
        string memory deploymentLabelSuffix,
        bool overrideExisting,
        address archController,
        address sanctionsSentinel
    ) internal returns (RevolvingDeploymentResult memory result) {
        (
            result.revolvingMarketInitCodeStorage,
            result.revolvingMarketInitCodeHash,
            result.didDeployRevolvingMarketInitCodeStorage
        ) = _deployRevolvingMarketInitCodeStorage(deployments, deploymentLabelSuffix, overrideExisting);

        (result.hooksFactoryRevolving, result.didDeployHooksFactoryRevolving) = _deployHooksFactoryRevolving(
            deployments,
            deploymentLabelSuffix,
            overrideExisting,
            archController,
            sanctionsSentinel,
            result.revolvingMarketInitCodeStorage,
            result.revolvingMarketInitCodeHash
        );
    }

    function _deployRevolvingMarketInitCodeStorage(
        Deployments memory deployments,
        string memory deploymentLabelSuffix,
        bool overrideExisting
    )
        internal
        returns (
            address revolvingMarketInitCodeStorage,
            uint256 revolvingMarketInitCodeHash,
            bool didDeployRevolvingMarketInitCodeStorage
        )
    {
        bytes memory revolvingMarketCreationCode = _getCreationCode(
            deployments, "src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving"
        );
        revolvingMarketInitCodeHash = uint256(keccak256(revolvingMarketCreationCode));
        string memory deploymentLabel =
            _deploymentLabel("WildcatMarketRevolving_initCodeStorage", deploymentLabelSuffix);
        (revolvingMarketInitCodeStorage, didDeployRevolvingMarketInitCodeStorage) = _getOrDeployInitcodeStorageByLabel(
            deployments,
            deploymentLabel,
            "src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving",
            revolvingMarketCreationCode,
            overrideExisting
        );
    }

    function _deployHooksFactoryRevolving(
        Deployments memory deployments,
        string memory deploymentLabelSuffix,
        bool overrideExisting,
        address archController,
        address sanctionsSentinel,
        address revolvingMarketInitCodeStorage,
        uint256 revolvingMarketInitCodeHash
    ) internal returns (address hooksFactoryRevolving, bool didDeployHooksFactoryRevolving) {
        bytes memory hooksFactoryRevolvingCreationCode =
            _getCreationCode(deployments, "src/HooksFactoryRevolving.sol:HooksFactoryRevolving");
        bytes memory hooksFactoryRevolvingConstructorArgs =
            abi.encode(archController, sanctionsSentinel, revolvingMarketInitCodeStorage, revolvingMarketInitCodeHash);
        string memory deploymentLabel = _deploymentLabel("HooksFactoryRevolving", deploymentLabelSuffix);

        (hooksFactoryRevolving, didDeployHooksFactoryRevolving) = _getOrDeployByLabel(
            deployments,
            deploymentLabel,
            "src/HooksFactoryRevolving.sol:HooksFactoryRevolving",
            hooksFactoryRevolvingCreationCode,
            hooksFactoryRevolvingConstructorArgs,
            overrideExisting
        );
    }

    function _ensureArchControllerRegistration(
        Deployments memory deployments,
        string memory networkName,
        string memory ownerMode,
        address archController,
        address hooksFactoryRevolving
    ) internal returns (RegistrationResult memory result) {
        IWildcatArchController arch = IWildcatArchController(archController);
        result.archControllerOwner = arch.owner();
        result.broadcaster = _broadcasterAddress(deployments);
        result.hasDirectOwnerAuthority =
            result.broadcaster != address(0) && result.broadcaster == result.archControllerOwner;

        result.isControllerFactoryRegistered = arch.isRegisteredControllerFactory(hooksFactoryRevolving);
        if (!result.isControllerFactoryRegistered) {
            if (_equalStrings(ownerMode, "emit")) {
                string memory artifactPath = _emitPendingRegisterControllerFactoryAction(
                    deployments, networkName, archController, result.archControllerOwner, hooksFactoryRevolving
                );
                result.didEmitPendingAdminAction = true;
                console.log("Owner-gated registration is pending. Wrote admin action artifact:");
                console.log(artifactPath);
                return result;
            }

            if (_equalStrings(ownerMode, "require-direct") && !result.hasDirectOwnerAuthority) {
                revert("Direct owner authority required for registerControllerFactory");
            }

            deployments.broadcast();
            arch.registerControllerFactory(hooksFactoryRevolving);
            result.didRegisterControllerFactory = true;
            result.isControllerFactoryRegistered = arch.isRegisteredControllerFactory(hooksFactoryRevolving);
        }

        result.isControllerRegistered = arch.isRegisteredController(hooksFactoryRevolving);
        if (!result.isControllerRegistered) {
            deployments.broadcast();
            IHooksFactoryRevolving(hooksFactoryRevolving).registerWithArchController();
            result.didRegisterController = true;
            result.isControllerRegistered = arch.isRegisteredController(hooksFactoryRevolving);
        }

        if (!result.isControllerFactoryRegistered) {
            revert("Controller factory registration missing");
        }
        if (!result.isControllerRegistered) {
            revert("Controller registration missing");
        }
    }
}
