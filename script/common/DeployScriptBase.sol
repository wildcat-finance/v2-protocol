// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Script} from "forge-std/Script.sol";

import "solady/utils/LibString.sol";

import "./LibDeployment.sol";

abstract contract DeployScriptBase is Script {
    using LibDeployment for Deployments;
    using LibString for string;

    function _resolveDeployments() internal returns (Deployments memory deployments, string memory networkName) {
        networkName = vm.envOr("DEPLOYMENTS_NETWORK", string(""));
        if (bytes(networkName).length == 0) {
            networkName = getNetworkName();
        }

        if (bytes(networkName).length == 0) {
            revert("Unknown network; set DEPLOYMENTS_NETWORK");
        }

        deployments = getDeploymentsForNetwork(networkName);

        string memory privateKeyVarName = vm.envOr("DEPLOYER_PRIVATE_KEY_VAR", string("PVT_KEY"));
        deployments = deployments.withPrivateKeyVarName(privateKeyVarName);
    }

    function _resolveAddress(Deployments memory deployments, string memory envVarName, string memory deploymentKey)
        internal
        returns (address value)
    {
        value = vm.envOr(envVarName, address(0));
        if (value != address(0)) {
            return value;
        }
        if (!deployments.has(deploymentKey)) {
            revert(string.concat("Missing ", envVarName, " and deployments key ", deploymentKey));
        }
        return deployments.get(deploymentKey);
    }

    function _getCreationCode(Deployments memory deployments, string memory namePath)
        internal
        returns (bytes memory creationCode)
    {
        ContractArtifact memory artifact = parseContractNamePath(namePath);
        string memory jsonPath = LibDeployment.findForgeArtifact(artifact, deployments.forgeOutDir);
        string memory forgeArtifactJson = vm.readFile(jsonPath);
        creationCode = vm.parseJsonBytes(forgeArtifactJson, ".bytecode.object");
    }
}
