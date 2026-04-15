// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {console} from "forge-std/console.sol";

import "./DeployScriptBase.sol";

contract DeployMarketLens is DeployScriptBase {
    function _deployLensHelper(
        Deployments memory deployments,
        string memory contractName,
        address archController,
        address defaultHooksFactory,
        bool overrideExisting
    ) internal returns (address helperAddress, bool didDeploy) {
        bytes memory creationCode = _getCreationCode(deployments, contractName);
        bytes memory constructorArgs = abi.encode(archController, defaultHooksFactory);

        return deployments.getOrDeploy(contractName, creationCode, constructorArgs, overrideExisting);
    }

    function _deployMarketLensFacade(
        Deployments memory deployments,
        address archController,
        address defaultHooksFactory,
        address marketLensCore,
        address marketLensAggregator,
        bool overrideExisting
    ) internal returns (address marketLens, bool didDeploy) {
        bytes memory creationCode = _getCreationCode(deployments, "src/lens/MarketLens.sol:MarketLens");
        bytes memory constructorArgs =
            abi.encode(archController, defaultHooksFactory, marketLensCore, marketLensAggregator);

        return
            deployments.getOrDeploy(
                "src/lens/MarketLens.sol:MarketLens", creationCode, constructorArgs, overrideExisting
            );
    }

    function run() external {
        (Deployments memory deployments, string memory networkName) = _resolveDeployments();
        bool overrideExisting = vm.envOr("OVERRIDE_EXISTING", false);

        address archController = _resolveAddress(deployments, "ARCH_CONTROLLER", "WildcatArchController");
        address defaultHooksFactory = _resolveAddress(deployments, "DEFAULT_HOOKS_FACTORY", "HooksFactory");

        (address marketLensCore, bool didDeployMarketLensCore) = _deployLensHelper(
            deployments,
            "src/lens/MarketLensCore.sol:MarketLensCore",
            archController,
            defaultHooksFactory,
            overrideExisting
        );

        (address marketLensAggregator, bool didDeployMarketLensAggregator) = _deployLensHelper(
            deployments,
            "src/lens/MarketLensAggregator.sol:MarketLensAggregator",
            archController,
            defaultHooksFactory,
            overrideExisting
        );

        (address marketLens, bool didDeployMarketLens) = _deployMarketLensFacade(
            deployments, archController, defaultHooksFactory, marketLensCore, marketLensAggregator, overrideExisting
        );

        deployments.write();

        console.log("Deployment complete for network:");
        console.log(networkName);
        console.log("MarketLens:");
        console.log(marketLens);
        console.log("MarketLensCore:");
        console.log(marketLensCore);
        console.log("MarketLensAggregator:");
        console.log(marketLensAggregator);
        console.log("Default hooks factory:");
        console.log(defaultHooksFactory);
        console.log("Did deploy MarketLensCore:");
        console.log(didDeployMarketLensCore);
        console.log("Did deploy MarketLensAggregator:");
        console.log(didDeployMarketLensAggregator);
        console.log("Did deploy MarketLens:");
        console.log(didDeployMarketLens);
    }
}
