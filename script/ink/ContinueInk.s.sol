// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {InkDeployment, WildcatArchController, SphereXEngine, WildcatCopyOfChainalysisList} from "./InkDeployment.sol";

/// @dev reuse only the three successful CREATEs before seeding. later addresses are regenerated.
contract ContinueInkTestnet is InkDeployment {
    function run() external {
        require(keccak256(bytes(vm.envString("FOUNDRY_PROFILE"))) == keccak256("ink"), "Ink: use ink build profile");
        Config memory c = _readConfig(vm.envString("INK_CONFIG"));
        string memory output = vm.envString("INK_CANDIDATE");
        require(!vm.exists(output), "Ink: candidate exists; resume the continuation");
        string memory parent = vm.readFile(vm.envString("INK_PARENT_CANDIDATE"));
        Deployment memory d = _continue(c, parent);
        _writeCandidate(c, d, output, false);
    }

    function _continue(Config memory c, string memory parent) internal returns (Deployment memory d) {
        _preflight(c);
        require(c.chainId == TESTNET, "Ink: continuation is testnet-only");
        require(records.length == 0, "Ink: script already used");
        require(vm.parseJsonUint(parent, ".chainId") == c.chainId, "Ink: parent chain");
        require(vm.parseJsonAddress(parent, ".deployer") == c.deployer, "Ink: parent deployer");
        require(vm.parseJsonBytes32(parent, ".snapshotHash") == c.snapshotHash, "Ink: parent snapshot");
        uint256 firstNonce = vm.parseJsonUint(parent, ".startNonce");
        require(c.expectedNonce == firstNonce + 3, "Ink: continuation nonce");
        d.archController =
            _reuse(c, parent, 0, "WildcatArchController", "WildcatArchController.sol:WildcatArchController");
        d.sphereXEngine = _reuse(c, parent, 1, "SphereXEngine", "spherex-engine/SphereXEngine.sol:SphereXEngine");
        d.sanctionsList =
            _reuse(c, parent, 2, "SanctionsList", "WildcatCopyOfChainalysisList.sol:WildcatCopyOfChainalysisList");

        WildcatArchController arch = WildcatArchController(d.archController);
        require(arch.owner() == c.deployer && arch.sphereXAdmin() == c.deployer, "Ink: reused arch authority");
        require(
            arch.sphereXEngine() == address(0) && arch.sphereXOperator() == address(0), "Ink: reused arch configured"
        );
        require(arch.pendingSphereXAdmin() == address(0), "Ink: reused arch pending admin");
        require(arch.getRegisteredMarkets().length == 0, "Ink: reused arch has markets");
        SphereXEngine engine = SphereXEngine(d.sphereXEngine);
        require(
            engine.defaultAdmin() == c.deployer && engine.hasRole(engine.OPERATOR_ROLE(), c.deployer),
            "Ink: reused engine authority"
        );
        require(uint256(vm.load(d.sphereXEngine, bytes32(uint256(3)))) == 0, "Ink: reused engine configured");
        WildcatCopyOfChainalysisList list = WildcatCopyOfChainalysisList(d.sanctionsList);
        require(list.owner() == c.deployer, "Ink: reused list owner");
        require(list.getSanctionedAddressesCount() == 0, "Ink: reused list is not empty");

        vm.startBroadcast(c.deployer);
        _deployRemaining(c, d);
        vm.stopBroadcast();
        // only the list-count/member check differs. the helper still owns ArchController.
        _verify(c, d, false);
    }

    function _reuse(Config memory c, string memory parent, uint256 index, string memory name, string memory artifact)
        private
        returns (address deployed)
    {
        string memory key = string.concat(".contracts[", vm.toString(index), "]");
        require(
            keccak256(bytes(vm.parseJsonString(parent, string.concat(key, ".name")))) == keccak256(bytes(name)),
            "Ink: reused contract order"
        );
        deployed = vm.parseJsonAddress(parent, string.concat(key, ".address"));
        require(
            deployed == vm.computeCreateAddress(c.deployer, c.expectedNonce - 3 + index), "Ink: reused CREATE address"
        );
        bytes32 creationHash = keccak256(vm.getCode(artifact));
        require(
            creationHash == vm.parseJsonBytes32(parent, string.concat(key, ".creationCodeHash")),
            "Ink: reused creation code"
        );
        require(
            deployed.codehash == vm.parseJsonBytes32(parent, string.concat(key, ".runtimeCodeHash")),
            "Ink: reused runtime code"
        );
        require(
            deployed.code.length > 0
                && deployed.code.length == vm.parseJsonUint(parent, string.concat(key, ".runtimeSize")),
            "Ink: reused runtime size"
        );
        records.push(
            Record(name, artifact, "contract", deployed, "", creationHash, deployed.codehash, deployed.code.length)
        );
    }
}

/// @dev read-only checkpoint verification; an empty list is recorded, not treated as seeded.
contract VerifyInkContinuation is InkDeployment {
    function run() external view {
        Config memory c = _readConfig(vm.envString("INK_CONFIG"));
        string memory candidate = vm.readFile(vm.envString("INK_CANDIDATE"));
        require(vm.parseJsonBytes32(candidate, ".configHash") == c.configHash, "Ink: config changed");
        require(vm.parseJsonBytes32(candidate, ".snapshotHash") == c.snapshotHash, "Ink: snapshot changed");
        require(!vm.parseJsonBool(candidate, ".sanctionsSeeded"), "Ink: not a deferred-seeding candidate");
        _verify(c, _readDeployment(candidate), false);
    }
}
