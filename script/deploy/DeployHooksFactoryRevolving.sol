// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {console} from "forge-std/console.sol";

import {IWildcatArchController} from "src/interfaces/IWildcatArchController.sol";
import {IHooksFactoryRevolving} from "src/IHooksFactoryRevolving.sol";

import "../common/DeployScriptBase.sol";

contract DeployHooksFactoryRevolving is DeployScriptBase {
    function run() external {
        (Deployments memory deployments, string memory networkName) = _resolveDeployments();
        bool overrideExisting = vm.envOr("OVERRIDE_EXISTING", false);

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

        _ensureArchControllerRegistration(deployments, archController, hooksFactoryRevolving);

        deployments.write();

        console.log("Deployment complete for network:");
        console.log(networkName);
        console.log("HooksFactoryRevolving:");
        console.log(hooksFactoryRevolving);
        console.log("WildcatMarketRevolving_initCodeStorage:");
        console.log(revolvingMarketInitCodeStorage);
        console.log("WildcatMarketRevolving_initCodeHash:");
        console.logUint(revolvingMarketInitCodeHash);
        console.log("Did deploy WildcatMarketRevolving init code storage:");
        console.log(didDeployRevolvingMarketInitCodeStorage);
        console.log("Did deploy HooksFactoryRevolving:");
        console.log(didDeployHooksFactoryRevolving);
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
        address archController,
        address hooksFactoryRevolving
    ) internal {
        IWildcatArchController arch = IWildcatArchController(archController);

        if (!arch.isRegisteredControllerFactory(hooksFactoryRevolving)) {
            deployments.broadcast();
            arch.registerControllerFactory(hooksFactoryRevolving);
        }

        if (!arch.isRegisteredController(hooksFactoryRevolving)) {
            deployments.broadcast();
            IHooksFactoryRevolving(hooksFactoryRevolving).registerWithArchController();
        }

        if (!arch.isRegisteredControllerFactory(hooksFactoryRevolving)) {
            revert("Controller factory registration missing");
        }
        if (!arch.isRegisteredController(hooksFactoryRevolving)) {
            revert("Controller registration missing");
        }
    }
}
