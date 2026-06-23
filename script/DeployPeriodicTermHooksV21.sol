// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "solady/utils/LibString.sol";

import "src/IHooksFactory.sol";
import {IWildcatArchController} from "src/interfaces/IWildcatArchController.sol";
import {MarketLens} from "src/lens/MarketLens.sol";
import {PeriodicTermHooks} from "src/access/PeriodicTermHooks.sol";

import "./LibDeployment.sol";

using LibDeployment for Deployments;
using LibString for address;
using LibString for string;

contract DeployPeriodicTermHooksV21 is Script {
    string internal constant PeriodicTermHooksName = "PeriodicTermHooks";
    string internal constant PeriodicTermHooksKey = "PeriodicTermHooks_initCodeStorage";
    string internal constant PeriodicMarketLensKey = "PeriodicTermHooks_MarketLens";
    string internal constant OpenTermHooksKey = "OpenTermHooks_initCodeStorage";
    string internal constant DefaultRegistrationMode = "auto";

    struct TemplateFeeConfig {
        address feeRecipient;
        address originationFeeAsset;
        uint80 originationFeeAmount;
        uint16 protocolFeeBips;
    }

    struct Rollout {
        string networkName;
        address broadcaster;
        address archController;
        address archControllerOwner;
        address hooksFactory;
        address periodicTemplate;
        address marketLens;
        bool didDeployPeriodicTemplate;
        bool didDeployMarketLens;
        bool wasTemplateRegistered;
        bool isTemplateRegistered;
        bool didRegisterTemplate;
        string registrationMode;
        string registrationActionPath;
        TemplateFeeConfig feeConfig;
    }

    function run() external {
        Rollout memory rollout;
        Deployments memory deployments;
        (deployments, rollout.networkName) = _resolveDeployments();

        rollout.broadcaster = _broadcaster(deployments);
        rollout.archController = _resolveAddress(deployments, "ARCH_CONTROLLER", "WildcatArchController");
        rollout.hooksFactory = _resolveAddress(deployments, "HOOKS_FACTORY", "HooksFactory");
        rollout.archControllerOwner = IWildcatArchController(rollout.archController).owner();
        rollout.registrationMode = vm.envOr("PERIODIC_TEMPLATE_REGISTRATION_MODE", DefaultRegistrationMode);

        (rollout.periodicTemplate, rollout.didDeployPeriodicTemplate) = deployments.getOrDeployInitcodeStorage(
            PeriodicTermHooksName,
            _getCreationCode(deployments, PeriodicTermHooksName),
            vm.envOr("OVERRIDE_PERIODIC_TEMPLATE", false)
        );

        rollout.feeConfig =
            _resolveFeeConfig(deployments, IHooksFactory(rollout.hooksFactory), rollout.archControllerOwner);
        rollout.wasTemplateRegistered = IHooksFactory(rollout.hooksFactory).isHooksTemplate(rollout.periodicTemplate);

        if (!rollout.wasTemplateRegistered && _shouldRegisterDirectly(rollout)) {
            deployments.broadcast();
            IHooksFactory(rollout.hooksFactory)
                .addHooksTemplate({
                hooksTemplate: rollout.periodicTemplate,
                name: PeriodicTermHooksName,
                feeRecipient: rollout.feeConfig.feeRecipient,
                originationFeeAsset: rollout.feeConfig.originationFeeAsset,
                originationFeeAmount: rollout.feeConfig.originationFeeAmount,
                protocolFeeBips: rollout.feeConfig.protocolFeeBips
            });
            rollout.didRegisterTemplate = true;
        }

        rollout.isTemplateRegistered = IHooksFactory(rollout.hooksFactory).isHooksTemplate(rollout.periodicTemplate);
        if (rollout.isTemplateRegistered) {
            HooksTemplate memory template =
                IHooksFactory(rollout.hooksFactory).getHooksTemplateDetails(rollout.periodicTemplate);
            require(template.enabled, "Periodic template disabled");
            require(
                keccak256(bytes(template.name)) == keccak256(bytes(PeriodicTermHooksName)),
                "Periodic template name mismatch"
            );
        }

        (rollout.marketLens, rollout.didDeployMarketLens) =
            _resolveMarketLens(deployments, rollout.archController, rollout.hooksFactory);
        _validateMarketLens(rollout.marketLens, rollout.archController, rollout.hooksFactory);

        rollout.registrationActionPath = _writeRegistrationAction(deployments, rollout);
        deployments.write();
        _writeRolloutSummary(deployments, rollout);
        _printRollout(rollout);
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

    function _resolveAddress(Deployments memory deployments, string memory envVarName, string memory deploymentKey)
        internal
        view
        returns (address value)
    {
        value = vm.envOr(envVarName, address(0));
        if (value != address(0)) {
            return value;
        }
        require(deployments.has(deploymentKey), string.concat("Missing deployments key ", deploymentKey));
        return deployments.get(deploymentKey);
    }

    function _broadcaster(Deployments memory deployments) internal view returns (address) {
        uint256 privateKey = vm.envOr(deployments.privateKeyVarName, uint256(0));
        if (privateKey != 0) {
            return vm.addr(privateKey);
        }
        return vm.envOr("DEPLOYER_ADDRESS", address(0));
    }

    function _getCreationCode(Deployments memory deployments, string memory namePath) internal returns (bytes memory) {
        ContractArtifact memory artifact = parseContractNamePath(namePath);
        string memory jsonPath = LibDeployment.findForgeArtifact(artifact, deployments.forgeOutDir);
        Json memory forgeArtifact = JsonUtil.create(vm.readFile(jsonPath));
        return forgeArtifact.getBytes("bytecode.object");
    }

    function _resolveFeeConfig(Deployments memory deployments, IHooksFactory hooksFactory, address defaultFeeRecipient)
        internal
        view
        returns (TemplateFeeConfig memory config)
    {
        address sourceTemplate = vm.envOr("PERIODIC_TEMPLATE_FEE_SOURCE", address(0));
        if (sourceTemplate == address(0) && deployments.has(OpenTermHooksKey)) {
            sourceTemplate = deployments.get(OpenTermHooksKey);
        }

        if (sourceTemplate != address(0) && hooksFactory.isHooksTemplate(sourceTemplate)) {
            HooksTemplate memory source = hooksFactory.getHooksTemplateDetails(sourceTemplate);
            config = TemplateFeeConfig({
                feeRecipient: source.feeRecipient,
                originationFeeAsset: source.originationFeeAsset,
                originationFeeAmount: source.originationFeeAmount,
                protocolFeeBips: source.protocolFeeBips
            });
        } else {
            config.feeRecipient = defaultFeeRecipient;
            config.originationFeeAsset = address(0);
            config.originationFeeAmount = 0;
            config.protocolFeeBips = 1_000;
        }

        config.feeRecipient = vm.envOr("PERIODIC_FEE_RECIPIENT", config.feeRecipient);
        config.originationFeeAsset = vm.envOr("PERIODIC_ORIGINATION_FEE_ASSET", config.originationFeeAsset);
        uint256 originationFeeAmount = vm.envOr("PERIODIC_ORIGINATION_FEE_AMOUNT", uint256(config.originationFeeAmount));
        uint256 protocolFeeBips = vm.envOr("PERIODIC_PROTOCOL_FEE_BIPS", uint256(config.protocolFeeBips));
        require(originationFeeAmount <= type(uint80).max, "Periodic origination fee too large");
        require(protocolFeeBips <= type(uint16).max, "Periodic protocol fee too large");
        // forge-lint: disable-next-line(unsafe-typecast)
        config.originationFeeAmount = uint80(originationFeeAmount);
        // forge-lint: disable-next-line(unsafe-typecast)
        config.protocolFeeBips = uint16(protocolFeeBips);
    }

    function _shouldRegisterDirectly(Rollout memory rollout) internal pure returns (bool) {
        bytes32 mode = keccak256(bytes(rollout.registrationMode));
        if (mode == keccak256("skip") || mode == keccak256("emit")) {
            return false;
        }
        if (mode == keccak256("direct")) {
            return true;
        }
        require(mode == keccak256(bytes(DefaultRegistrationMode)), "Invalid registration mode");
        return rollout.broadcaster != address(0) && rollout.broadcaster == rollout.archControllerOwner;
    }

    function _resolveMarketLens(Deployments memory deployments, address archController, address hooksFactory)
        internal
        returns (address marketLens, bool didDeployMarketLens)
    {
        address existingMarketLens = vm.envOr("MARKET_LENS", address(0));
        if (existingMarketLens != address(0)) {
            deployments.set("MarketLens", existingMarketLens);
            deployments.set(PeriodicMarketLensKey, existingMarketLens);
            return (existingMarketLens, false);
        }

        bool deployMarketLens = vm.envOr("DEPLOY_MARKET_LENS", true);
        if (!deployMarketLens) {
            require(deployments.has("MarketLens"), "Missing MARKET_LENS and deployments key MarketLens");
            return (deployments.get("MarketLens"), false);
        }

        bool overrideMarketLens = vm.envOr("OVERRIDE_MARKET_LENS", false);
        if (!overrideMarketLens && deployments.has(PeriodicMarketLensKey)) {
            marketLens = deployments.get(PeriodicMarketLensKey);
            deployments.set("MarketLens", marketLens);
            console.log("Found MarketLens at", marketLens);
            return (marketLens, false);
        }

        (marketLens, didDeployMarketLens) = deployments.getOrDeploy(
            "MarketLens", _getCreationCode(deployments, "MarketLens"), abi.encode(archController, hooksFactory), true
        );
        deployments.set(PeriodicMarketLensKey, marketLens);
    }

    function _validateMarketLens(address marketLens, address archController, address hooksFactory) internal view {
        require(address(MarketLens(marketLens).archController()) == archController, "Lens arch mismatch");
        require(address(MarketLens(marketLens).hooksFactory()) == hooksFactory, "Lens factory mismatch");
    }

    function _registrationCalldata(Rollout memory rollout) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            IHooksFactory.addHooksTemplate.selector,
            rollout.periodicTemplate,
            PeriodicTermHooksName,
            rollout.feeConfig.feeRecipient,
            rollout.feeConfig.originationFeeAsset,
            rollout.feeConfig.originationFeeAmount,
            rollout.feeConfig.protocolFeeBips
        );
    }

    function _writeRegistrationAction(Deployments memory deployments, Rollout memory rollout)
        internal
        returns (string memory artifactPath)
    {
        string memory actionId = "periodic-template-registration-action";
        string memory status = rollout.wasTemplateRegistered
            ? "already-registered"
            : rollout.didRegisterTemplate
                ? "executed"
                : keccak256(bytes(rollout.registrationMode)) == keccak256("skip") ? "skipped" : "pending-owner-action";

        string memory json = vm.serializeUint(actionId, "chainId", block.chainid);
        json = vm.serializeString(actionId, "network", rollout.networkName);
        json = vm.serializeString(actionId, "status", status);
        json = vm.serializeString(
            actionId, "description", "Register PeriodicTermHooks as a hooks template on the existing v2.1 HooksFactory"
        );
        json = vm.serializeAddress(actionId, "target", rollout.hooksFactory);
        json = vm.serializeString(actionId, "value", "0");
        json = vm.serializeBytes(actionId, "data", _registrationCalldata(rollout));
        json = vm.serializeString(
            actionId, "functionSignature", "addHooksTemplate(address,string,address,address,uint80,uint16)"
        );
        json = vm.serializeAddress(actionId, "archController", rollout.archController);
        json = vm.serializeAddress(actionId, "archControllerOwner", rollout.archControllerOwner);
        json = vm.serializeAddress(actionId, "broadcaster", rollout.broadcaster);
        json = vm.serializeAddress(actionId, "hooksFactory", rollout.hooksFactory);
        json = vm.serializeAddress(actionId, PeriodicTermHooksKey, rollout.periodicTemplate);
        json = vm.serializeAddress(actionId, "feeRecipient", rollout.feeConfig.feeRecipient);
        json = vm.serializeAddress(actionId, "originationFeeAsset", rollout.feeConfig.originationFeeAsset);
        json = vm.serializeUint(actionId, "originationFeeAmount", rollout.feeConfig.originationFeeAmount);
        json = vm.serializeUint(actionId, "protocolFeeBips", rollout.feeConfig.protocolFeeBips);
        json = vm.serializeBool(actionId, "wasTemplateRegistered", rollout.wasTemplateRegistered);
        json = vm.serializeBool(actionId, "didRegisterTemplate", rollout.didRegisterTemplate);
        json = vm.serializeBool(actionId, "isTemplateRegistered", rollout.isTemplateRegistered);

        string memory actionsDir = pathJoin(deployments.dir, "pending-admin-actions");
        mkdir(actionsDir);
        artifactPath = pathJoin(actionsDir, "PeriodicTermHooks-add-template.json");
        vm.writeJson(json, artifactPath);
    }

    function _writeRolloutSummary(Deployments memory deployments, Rollout memory rollout) internal {
        string memory summaryId = "periodic-hooks-v21-rollout";
        string memory json = vm.serializeUint(summaryId, "chainId", block.chainid);
        json = vm.serializeString(summaryId, "network", rollout.networkName);
        json = vm.serializeAddress(summaryId, "broadcaster", rollout.broadcaster);
        json = vm.serializeAddress(summaryId, "archController", rollout.archController);
        json = vm.serializeAddress(summaryId, "archControllerOwner", rollout.archControllerOwner);
        json = vm.serializeAddress(summaryId, "hooksFactory", rollout.hooksFactory);
        json = vm.serializeAddress(summaryId, PeriodicTermHooksKey, rollout.periodicTemplate);
        json = vm.serializeAddress(summaryId, "MarketLens", rollout.marketLens);
        json = vm.serializeBool(summaryId, "didDeployPeriodicTemplate", rollout.didDeployPeriodicTemplate);
        json = vm.serializeBool(summaryId, "didDeployMarketLens", rollout.didDeployMarketLens);
        json = vm.serializeBool(summaryId, "wasTemplateRegistered", rollout.wasTemplateRegistered);
        json = vm.serializeBool(summaryId, "didRegisterTemplate", rollout.didRegisterTemplate);
        json = vm.serializeBool(summaryId, "isTemplateRegistered", rollout.isTemplateRegistered);
        json = vm.serializeString(summaryId, "registrationMode", rollout.registrationMode);
        json = vm.serializeString(summaryId, "registrationActionPath", rollout.registrationActionPath);
        json = vm.serializeAddress(summaryId, "feeRecipient", rollout.feeConfig.feeRecipient);
        json = vm.serializeAddress(summaryId, "originationFeeAsset", rollout.feeConfig.originationFeeAsset);
        json = vm.serializeUint(summaryId, "originationFeeAmount", rollout.feeConfig.originationFeeAmount);
        json = vm.serializeUint(summaryId, "protocolFeeBips", rollout.feeConfig.protocolFeeBips);
        vm.writeJson(json, pathJoin(deployments.dir, "periodic-hooks-v21-rollout.json"));
    }

    function _printRollout(Rollout memory rollout) internal view {
        console.log("Periodic hooks v2.1 rollout complete");
        console.log("Network:", rollout.networkName);
        console.log("ArchController:", rollout.archController);
        console.log("ArchController owner:", rollout.archControllerOwner);
        console.log("HooksFactory:", rollout.hooksFactory);
        console.log("PeriodicTermHooks init-code storage:", rollout.periodicTemplate);
        console.log("MarketLens:", rollout.marketLens);
        console.log("Registration mode:", rollout.registrationMode);
        console.log("Registration action artifact:", rollout.registrationActionPath);
        console.log("Template registered:", rollout.isTemplateRegistered);
        console.log("Did register template:", rollout.didRegisterTemplate);
        console.log("Did deploy PeriodicTermHooks init-code storage:", rollout.didDeployPeriodicTemplate);
        console.log("Did deploy MarketLens:", rollout.didDeployMarketLens);
    }
}
