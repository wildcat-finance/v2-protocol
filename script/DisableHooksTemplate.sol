// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "solady/utils/LibString.sol";

import "src/IHooksFactory.sol";
import {IWildcatArchController} from "src/interfaces/IWildcatArchController.sol";

import "./common/LibDeployment.sol";

using LibDeployment for Deployments;
using LibString for address;
using LibString for string;

contract DisableHooksTemplate is Script {
    string internal constant PeriodicTermHooksKey = "PeriodicTermHooks_initCodeStorage";
    string internal constant DefaultDisableMode = "auto";

    struct DisableAction {
        string networkName;
        address broadcaster;
        address archController;
        address archControllerOwner;
        address hooksFactory;
        address hooksTemplate;
        string templateName;
        bool wasTemplateRegistered;
        bool wasTemplateEnabled;
        bool isTemplateEnabled;
        bool didDisableTemplate;
        string disableMode;
        string disableActionPath;
    }

    function run() external {
        DisableAction memory action;
        Deployments memory deployments;
        (deployments, action.networkName) = _resolveDeployments();

        action.broadcaster = _broadcaster(deployments);
        action.hooksFactory = _resolveAddress(deployments, "DISABLE_HOOKS_FACTORY", "HOOKS_FACTORY", "HooksFactory");
        action.hooksTemplate = _resolveTemplate(deployments);
        action.archController = IHooksFactory(action.hooksFactory).archController();
        action.archControllerOwner = IWildcatArchController(action.archController).owner();
        action.disableMode = vm.envOr("DISABLE_TEMPLATE_MODE", DefaultDisableMode);

        action.wasTemplateRegistered = IHooksFactory(action.hooksFactory).isHooksTemplate(action.hooksTemplate);
        if (action.wasTemplateRegistered) {
            HooksTemplate memory template =
                IHooksFactory(action.hooksFactory).getHooksTemplateDetails(action.hooksTemplate);
            action.templateName = template.name;
            action.wasTemplateEnabled = template.enabled;
        }

        if (action.wasTemplateRegistered && action.wasTemplateEnabled && _shouldDisableDirectly(action)) {
            deployments.broadcast();
            IHooksFactory(action.hooksFactory).disableHooksTemplate(action.hooksTemplate);
            action.didDisableTemplate = true;
        }

        if (action.wasTemplateRegistered) {
            HooksTemplate memory template =
                IHooksFactory(action.hooksFactory).getHooksTemplateDetails(action.hooksTemplate);
            action.isTemplateEnabled = template.enabled;
        }

        action.disableActionPath = _writeDisableAction(deployments, action);
        _printDisableAction(action);
    }

    function _resolveDeployments() internal returns (Deployments memory deployments, string memory networkName) {
        networkName = vm.envOr("DEPLOYMENTS_NETWORK", string(""));
        if (bytes(networkName).length == 0) {
            networkName = getNetworkName();
        }
        require(bytes(networkName).length != 0, "Unknown network; set DEPLOYMENTS_NETWORK");
        deployments = getDeploymentsForNetwork(networkName)
            .withPrivateKeyVarName(vm.envOr("DEPLOYER_PRIVATE_KEY_VAR", string("PVT_KEY")));
    }

    function _resolveAddress(
        Deployments memory deployments,
        string memory primaryEnvVarName,
        string memory fallbackEnvVarName,
        string memory deploymentKey
    ) internal view returns (address value) {
        value = vm.envOr(primaryEnvVarName, address(0));
        if (value != address(0)) {
            return value;
        }
        value = vm.envOr(fallbackEnvVarName, address(0));
        if (value != address(0)) {
            return value;
        }
        require(deployments.has(deploymentKey), string.concat("Missing deployments key ", deploymentKey));
        return deployments.get(deploymentKey);
    }

    function _resolveTemplate(Deployments memory deployments) internal view returns (address value) {
        value = vm.envOr("DISABLE_HOOKS_TEMPLATE", address(0));
        if (value != address(0)) {
            return value;
        }
        value = vm.envOr("HOOKS_TEMPLATE", address(0));
        if (value != address(0)) {
            return value;
        }
        require(deployments.has(PeriodicTermHooksKey), string.concat("Missing deployments key ", PeriodicTermHooksKey));
        return deployments.get(PeriodicTermHooksKey);
    }

    function _broadcaster(Deployments memory deployments) internal view returns (address) {
        uint256 privateKey = vm.envOr(deployments.privateKeyVarName, uint256(0));
        if (privateKey != 0) {
            return vm.addr(privateKey);
        }
        return vm.envOr("DEPLOYER_ADDRESS", address(0));
    }

    function _shouldDisableDirectly(DisableAction memory action) internal pure returns (bool) {
        bytes32 mode = keccak256(bytes(action.disableMode));
        if (mode == keccak256("skip") || mode == keccak256("emit")) {
            return false;
        }
        if (mode == keccak256("direct")) {
            return true;
        }
        require(mode == keccak256(bytes(DefaultDisableMode)), "Invalid disable mode");
        return action.broadcaster != address(0) && action.broadcaster == action.archControllerOwner;
    }

    function _disableCalldata(DisableAction memory action) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IHooksFactory.disableHooksTemplate.selector, action.hooksTemplate);
    }

    function _writeDisableAction(Deployments memory deployments, DisableAction memory action)
        internal
        returns (string memory artifactPath)
    {
        string memory status = !action.wasTemplateRegistered
            ? "template-not-found"
            : !action.wasTemplateEnabled
                ? "already-disabled"
                : action.didDisableTemplate
                    ? "executed"
                    : keccak256(bytes(action.disableMode)) == keccak256("skip") ? "skipped" : "pending-owner-action";

        string memory json = vm.serializeUint("disable-hooks-template-action", "chainId", block.chainid);
        json = vm.serializeString("disable-hooks-template-action", "network", action.networkName);
        json = vm.serializeString("disable-hooks-template-action", "status", status);
        json = vm.serializeString(
            "disable-hooks-template-action", "description", "Disable a hooks template on a HooksFactory"
        );
        json = vm.serializeAddress("disable-hooks-template-action", "target", action.hooksFactory);
        json = vm.serializeString("disable-hooks-template-action", "value", "0");
        json = vm.serializeBytes("disable-hooks-template-action", "data", _disableCalldata(action));
        json = vm.serializeString("disable-hooks-template-action", "functionSignature", "disableHooksTemplate(address)");
        json = vm.serializeAddress("disable-hooks-template-action", "archController", action.archController);
        json = vm.serializeAddress("disable-hooks-template-action", "archControllerOwner", action.archControllerOwner);
        json = vm.serializeAddress("disable-hooks-template-action", "broadcaster", action.broadcaster);
        json = vm.serializeAddress("disable-hooks-template-action", "hooksFactory", action.hooksFactory);
        json = vm.serializeAddress("disable-hooks-template-action", "hooksTemplate", action.hooksTemplate);
        json = vm.serializeString("disable-hooks-template-action", "templateName", action.templateName);
        json = vm.serializeBool("disable-hooks-template-action", "wasTemplateRegistered", action.wasTemplateRegistered);
        json = vm.serializeBool("disable-hooks-template-action", "wasTemplateEnabled", action.wasTemplateEnabled);
        json = vm.serializeBool("disable-hooks-template-action", "didDisableTemplate", action.didDisableTemplate);
        json = vm.serializeBool("disable-hooks-template-action", "isTemplateEnabled", action.isTemplateEnabled);

        string memory actionsDir = pathJoin(deployments.dir, "pending-admin-actions");
        mkdir(actionsDir);
        artifactPath = pathJoin(actionsDir, "PeriodicTermHooks-disable-template.json");
        vm.writeJson(json, artifactPath);
    }

    function _printDisableAction(DisableAction memory action) internal view {
        console.log("Disable hooks template action complete");
        console.log("Network:", action.networkName);
        console.log("ArchController:", action.archController);
        console.log("ArchController owner:", action.archControllerOwner);
        console.log("HooksFactory:", action.hooksFactory);
        console.log("Hooks template:", action.hooksTemplate);
        console.log("Template name:", action.templateName);
        console.log("Disable mode:", action.disableMode);
        console.log("Action artifact:", action.disableActionPath);
        console.log("Template registered:", action.wasTemplateRegistered);
        console.log("Was template enabled:", action.wasTemplateEnabled);
        console.log("Is template enabled:", action.isTemplateEnabled);
        console.log("Did disable template:", action.didDisableTemplate);
    }
}
