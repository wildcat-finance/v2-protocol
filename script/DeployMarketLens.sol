// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {console} from "forge-std/console.sol";

import "./DeployScriptBase.sol";

contract DeployMarketLens is DeployScriptBase {
    function run() external {
        (Deployments memory deployments, string memory networkName) = _resolveDeployments();
        bool overrideExisting = vm.envOr("OVERRIDE_EXISTING", false);

        address archController = _resolveAddress(deployments, "ARCH_CONTROLLER", "WildcatArchController");
        address defaultHooksFactory = _resolveAddress(deployments, "DEFAULT_HOOKS_FACTORY", "HooksFactory");

        bytes memory marketLensCreationCode = _getCreationCode(deployments, "src/lens/MarketLens.sol:MarketLens");
        bytes memory marketLensConstructorArgs = abi.encode(archController, defaultHooksFactory);

        (address marketLens, bool didDeployMarketLens) = deployments.getOrDeploy(
            "src/lens/MarketLens.sol:MarketLens", marketLensCreationCode, marketLensConstructorArgs, overrideExisting
        );

        deployments.write();

        console.log("Deployment complete for network:");
        console.log(networkName);
        console.log("MarketLens:");
        console.log(marketLens);
        console.log("Default hooks factory:");
        console.log(defaultHooksFactory);
        console.log("Did deploy MarketLens:");
        console.log(didDeployMarketLens);
    }
}
