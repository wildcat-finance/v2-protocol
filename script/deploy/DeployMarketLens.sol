// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {console} from "forge-std/console.sol";

import "../common/DeployScriptBase.sol";

contract DeployMarketLens is DeployScriptBase {
    struct LensDeploymentResult {
        address marketLensCore;
        address marketLensAggregator;
        address marketLens;
        bool didDeployMarketLensCore;
        bool didDeployMarketLensAggregator;
        bool didDeployMarketLens;
    }

    function _deploymentLabel(string memory baseLabel, string memory deploymentTag)
        internal
        pure
        returns (string memory)
    {
        return string.concat(baseLabel, "_", deploymentTag);
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

    function _setCanonicalAlias(Deployments memory deployments, string memory aliasName, address target)
        internal
        returns (bool didUpdateAlias)
    {
        didUpdateAlias = !deployments.has(aliasName) || deployments.get(aliasName) != target;
        deployments.set(aliasName, target);
    }

    function _updateCanonicalAliases(
        Deployments memory deployments,
        address marketLensCore,
        address marketLensAggregator,
        address marketLens
    ) internal returns (bool didUpdateCanonicalAliases) {
        bool didUpdateCanonicalMarketLensCore = _setCanonicalAlias(deployments, "MarketLensCore", marketLensCore);
        bool didUpdateCanonicalMarketLensAggregator =
            _setCanonicalAlias(deployments, "MarketLensAggregator", marketLensAggregator);
        bool didUpdateCanonicalMarketLens = _setCanonicalAlias(deployments, "MarketLens", marketLens);

        didUpdateCanonicalAliases =
            didUpdateCanonicalMarketLensCore || didUpdateCanonicalMarketLensAggregator || didUpdateCanonicalMarketLens;

        console.log("Did update canonical MarketLensCore alias:");
        console.log(didUpdateCanonicalMarketLensCore);
        console.log("Did update canonical MarketLensAggregator alias:");
        console.log(didUpdateCanonicalMarketLensAggregator);
        console.log("Did update canonical MarketLens alias:");
        console.log(didUpdateCanonicalMarketLens);
        console.log("Did update any canonical lens alias:");
        console.log(didUpdateCanonicalAliases);
    }

    function _deployMarketLensFacade(
        Deployments memory deployments,
        string memory deploymentTag,
        address archController,
        address defaultHooksFactory,
        address marketLensCore,
        address marketLensAggregator,
        bool overrideExisting
    ) internal returns (address marketLens, bool didDeployMarketLens) {
        string memory contractName = "src/lens/MarketLens.sol:MarketLens";
        string memory deploymentLabel = _deploymentLabel("MarketLens", deploymentTag);
        bytes memory creationCode = _getCreationCode(deployments, contractName);
        bytes memory constructorArgs =
            abi.encode(archController, defaultHooksFactory, marketLensCore, marketLensAggregator);

        return _getOrDeployByLabel(
            deployments, deploymentLabel, contractName, creationCode, constructorArgs, overrideExisting
        );
    }

    function _deployLensHelper(
        Deployments memory deployments,
        string memory deploymentTag,
        string memory baseLabel,
        string memory contractName,
        address archController,
        address defaultHooksFactory,
        bool overrideExisting
    ) internal returns (address helperAddress, bool didDeployHelper) {
        string memory deploymentLabel = _deploymentLabel(baseLabel, deploymentTag);
        bytes memory creationCode = _getCreationCode(deployments, contractName);
        bytes memory constructorArgs = abi.encode(archController, defaultHooksFactory);

        return _getOrDeployByLabel(
            deployments, deploymentLabel, contractName, creationCode, constructorArgs, overrideExisting
        );
    }

    function _deployLensSet(
        Deployments memory deployments,
        string memory deploymentTag,
        address archController,
        address defaultHooksFactory,
        bool overrideExisting
    ) internal returns (LensDeploymentResult memory result) {
        (result.marketLensCore, result.didDeployMarketLensCore) = _deployLensHelper(
            deployments,
            deploymentTag,
            "MarketLensCore",
            "src/lens/MarketLensCore.sol:MarketLensCore",
            archController,
            defaultHooksFactory,
            overrideExisting
        );

        (result.marketLensAggregator, result.didDeployMarketLensAggregator) = _deployLensHelper(
            deployments,
            deploymentTag,
            "MarketLensAggregator",
            "src/lens/MarketLensAggregator.sol:MarketLensAggregator",
            archController,
            defaultHooksFactory,
            overrideExisting
        );

        (result.marketLens, result.didDeployMarketLens) = _deployMarketLensFacade(
            deployments,
            deploymentTag,
            archController,
            defaultHooksFactory,
            result.marketLensCore,
            result.marketLensAggregator,
            overrideExisting
        );
    }

    function run() external {
        (Deployments memory deployments, string memory networkName) = _resolveDeployments();
        bool overrideExisting = vm.envOr("OVERRIDE_EXISTING", false);
        string memory deploymentTag = vm.envOr("MARKET_LENS_DEPLOYMENT_TAG", string(""));
        if (bytes(deploymentTag).length == 0) {
            revert("Missing MARKET_LENS_DEPLOYMENT_TAG");
        }

        address archController = _resolveAddress(deployments, "ARCH_CONTROLLER", "WildcatArchController");
        address defaultHooksFactory = _resolveAddress(deployments, "DEFAULT_HOOKS_FACTORY", "HooksFactory");

        LensDeploymentResult memory result =
            _deployLensSet(deployments, deploymentTag, archController, defaultHooksFactory, overrideExisting);

        bool didDeployLensSet =
            result.didDeployMarketLensCore || result.didDeployMarketLensAggregator || result.didDeployMarketLens;
        _updateCanonicalAliases(
            deployments, result.marketLensCore, result.marketLensAggregator, result.marketLens
        );

        deployments.write();

        console.log("Deployment complete for network:");
        console.log(networkName);
        console.log("MarketLens deployment tag:");
        console.log(deploymentTag);
        console.log("MarketLens:");
        console.log(result.marketLens);
        console.log("MarketLensCore:");
        console.log(result.marketLensCore);
        console.log("MarketLensAggregator:");
        console.log(result.marketLensAggregator);
        console.log("Default hooks factory:");
        console.log(defaultHooksFactory);
        console.log("Did deploy MarketLensCore:");
        console.log(result.didDeployMarketLensCore);
        console.log("Did deploy MarketLensAggregator:");
        console.log(result.didDeployMarketLensAggregator);
        console.log("Did deploy MarketLens:");
        console.log(result.didDeployMarketLens);
        console.log("Did deploy any lens-set component:");
        console.log(didDeployLensSet);
    }
}
