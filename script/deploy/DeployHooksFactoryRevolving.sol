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
            objectKey,
            "description",
            "Register HooksFactoryRevolving as a controller factory in WildcatArchController"
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
            string.concat("HooksFactoryRevolving-", vm.toString(hooksFactoryRevolving), "-register-controller-factory.json")
        );
        vm.writeJson(json, artifactPath);
    }

    function run() external {
        (Deployments memory deployments, string memory networkName) = _resolveDeployments();
        bool overrideExisting = vm.envOr("OVERRIDE_EXISTING", false);
        string memory ownerMode = _ownerMode();

        address archController = _resolveAddress(deployments, "ARCH_CONTROLLER", "WildcatArchController");
        address sanctionsSentinel = _resolveAddress(deployments, "SANCTIONS_SENTINEL", "WildcatSanctionsSentinel");

        (
            address revolvingMarketInitCodeStorage,
            uint256 revolvingMarketInitCodeHash,
            bool didDeployRevolvingMarketInitCodeStorage
        ) = _deployRevolvingMarketInitCodeStorage(deployments, overrideExisting);

        (address hooksFactoryRevolving, bool didDeployHooksFactoryRevolving) = _deployHooksFactoryRevolving(
            deployments,
            overrideExisting,
            archController,
            sanctionsSentinel,
            revolvingMarketInitCodeStorage,
            revolvingMarketInitCodeHash
        );

        RegistrationResult memory registrationResult =
            _ensureArchControllerRegistration(deployments, networkName, ownerMode, archController, hooksFactoryRevolving);

        deployments.write();

        console.log("Deployment complete for network:");
        console.log(networkName);
        console.log("HooksFactoryRevolving:");
        console.log(hooksFactoryRevolving);
        console.log("Arch controller owner:");
        console.log(registrationResult.archControllerOwner);
        console.log("Broadcaster:");
        console.log(registrationResult.broadcaster);
        console.log("Has direct owner authority:");
        console.log(registrationResult.hasDirectOwnerAuthority);
        console.log("Arch controller owner mode:");
        console.log(ownerMode);
        console.log("WildcatMarketRevolving_initCodeStorage:");
        console.log(revolvingMarketInitCodeStorage);
        console.log("WildcatMarketRevolving_initCodeHash:");
        console.logUint(revolvingMarketInitCodeHash);
        console.log("Did deploy WildcatMarketRevolving init code storage:");
        console.log(didDeployRevolvingMarketInitCodeStorage);
        console.log("Did deploy HooksFactoryRevolving:");
        console.log(didDeployHooksFactoryRevolving);
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

    function _deployRevolvingMarketInitCodeStorage(Deployments memory deployments, bool overrideExisting)
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
        (revolvingMarketInitCodeStorage, didDeployRevolvingMarketInitCodeStorage) =
            deployments.getOrDeployInitcodeStorage(
                "src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving",
                revolvingMarketCreationCode,
                overrideExisting
            );
    }

    function _deployHooksFactoryRevolving(
        Deployments memory deployments,
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

        (hooksFactoryRevolving, didDeployHooksFactoryRevolving) = deployments.getOrDeploy(
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
        result.hasDirectOwnerAuthority = result.broadcaster != address(0) && result.broadcaster == result.archControllerOwner;

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
