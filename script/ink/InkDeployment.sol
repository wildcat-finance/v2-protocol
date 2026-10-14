// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {WildcatArchController} from "src/WildcatArchController.sol";
import {WildcatSanctionsSentinel} from "src/WildcatSanctionsSentinel.sol";
import {HooksFactory} from "src/HooksFactory.sol";
import {HooksTemplate} from "src/IHooksFactory.sol";
import {MarketLens} from "src/lens/MarketLens.sol";
import {Wildcat4626WrapperFactory} from "src/vault/Wildcat4626WrapperFactory.sol";
import {ChainalysisProxy} from "src/ChainalysisProxy.sol";
import {WildcatCopyOfChainalysisList} from "src/WildcatCopyOfChainalysisList.sol";
import {OpenAccessRoleProvider} from "src/OpenAccessRoleProvider.sol";
import {WildcatFeeRecipient} from "src/WildcatFeeRecipient.sol";
import {SphereXEngine} from "src/spherex-engine/SphereXEngine.sol";
import {MockArchControllerOwner} from "script/mock/MockArchControllerOwner.sol";
import {SphereXPatterns} from "./SphereXPatterns.sol";

/// @dev offchain Foundry script. the EOA sends every CREATE and configuration call.
/// resume keeps the saved plan. an explicit continuation gets its own plan and cache.
abstract contract InkDeployment is Script {
    uint256 internal constant MAINNET = 57073;
    uint256 internal constant TESTNET = 763373;
    uint256 internal constant MAX_CODE_SIZE = 24_576;

    struct Config {
        uint256 chainId;
        address deployer;
        uint64 expectedNonce;
        bool deployFeeRecipient;
        address feeRecipient;
        uint16 protocolFeeBips;
        address[] sanctions;
        bytes32 configHash;
        bytes32 snapshotHash;
    }

    struct Deployment {
        address archController;
        address sphereXEngine;
        address sanctionsList;
        address sanctionsAdapter;
        address sanctionsSentinel;
        address feeRecipient;
        address marketInitCodeStorage;
        address openTermHooks;
        address fixedTermHooks;
        address hooksFactory;
        address marketLens;
        address wrapperFactory;
        address openAccessRoleProvider;
        address testnetOwner;
    }

    struct Record {
        string name;
        string artifact;
        string kind;
        address deployed;
        bytes constructorArgs;
        bytes32 creationCodeHash;
        bytes32 runtimeCodeHash;
        uint256 runtimeSize;
    }

    Record[] internal records;

    function _readConfig(string memory path) internal view returns (Config memory c) {
        string memory json = vm.readFile(path);
        require(vm.parseJsonUint(json, ".schemaVersion") == 1, "Ink: config schema");
        c.chainId = vm.parseJsonUint(json, ".chainId");
        c.deployer = vm.parseJsonAddress(json, ".deployer");
        uint256 nonce = vm.parseJsonUint(json, ".expectedNonce");
        uint256 fee = vm.parseJsonUint(json, ".protocolFeeBips");
        require(nonce <= type(uint64).max && fee <= 10_000, "Ink: numeric config");
        c.expectedNonce = uint64(nonce);
        c.protocolFeeBips = uint16(fee);
        c.deployFeeRecipient = vm.parseJsonBool(json, ".deployFeeRecipient");
        c.feeRecipient = vm.parseJsonAddress(json, ".feeRecipient");
        c.configHash = keccak256(bytes(json));
        string memory snapshot = vm.readFile(vm.parseJsonString(json, ".sanctionsSnapshot"));
        c.snapshotHash = keccak256(bytes(snapshot));
        c.sanctions = vm.parseJsonAddressArray(snapshot, ".addresses");
        // these source fields are the operator's claim, not a check against the source chain.
        require(vm.parseJsonUint(snapshot, ".schemaVersion") == 1, "Ink: snapshot schema");
        require(vm.parseJsonUint(snapshot, ".sourceChainId") == 1, "Ink: snapshot source chain");
        require(vm.parseJsonAddress(snapshot, ".sourceOracle") != address(0), "Ink: snapshot oracle");
        require(vm.parseJsonUint(snapshot, ".sourceBlockNumber") > 0, "Ink: snapshot block");
        require(vm.parseJsonBytes32(snapshot, ".sourceBlockHash") != 0, "Ink: snapshot block hash");
    }

    function _preflight(Config memory c) internal view {
        require(c.chainId == MAINNET || c.chainId == TESTNET, "Ink: unknown chain");
        require(block.chainid == c.chainId, "Ink: wrong chain");
        require(c.deployer != address(0) && c.deployer.code.length == 0, "Ink: EOA required");
        require(vm.getNonce(c.deployer) == c.expectedNonce, "Ink: nonce changed; do not rerun");
        require(c.feeRecipient != address(0), "Ink: explicit fee recipient required");
        require(c.protocolFeeBips <= 10_000, "Ink: invalid fee");
        require(c.sanctions.length > 0, "Ink: empty sanctions snapshot");
        address previous;
        for (uint256 i; i < c.sanctions.length; ++i) {
            require(c.sanctions[i] > previous, "Ink: sanctions must be sorted, unique, nonzero");
            previous = c.sanctions[i];
        }
    }

    function _deploy(Config memory c) internal returns (Deployment memory d) {
        _preflight(c);
        require(records.length == 0, "Ink: script already used");
        vm.startBroadcast(c.deployer);

        d.archController = _create("WildcatArchController", "WildcatArchController.sol:WildcatArchController", "");
        d.sphereXEngine = _create("SphereXEngine", "spherex-engine/SphereXEngine.sol:SphereXEngine", "");
        d.sanctionsList = _create("SanctionsList", "WildcatCopyOfChainalysisList.sol:WildcatCopyOfChainalysisList", "");
        // batch the snapshot so one transaction doesn't have to seed the whole list.
        for (uint256 start; start < c.sanctions.length; start += 100) {
            uint256 count = c.sanctions.length - start;
            if (count > 100) count = 100;
            address[] memory batch = new address[](count);
            for (uint256 i; i < count; ++i) {
                batch[i] = c.sanctions[start + i];
            }
            WildcatCopyOfChainalysisList(d.sanctionsList).addToSanctionsList(batch);
        }
        _deployRemaining(c, d);
        vm.stopBroadcast();
        _verify(c, d);
    }

    // broadcast must already be active. both paths keep the same bindings and testnet handoff.
    function _deployRemaining(Config memory c, Deployment memory d) internal {
        d.sanctionsAdapter = _create("SanctionsAdapter", "ChainalysisProxy.sol:ChainalysisProxy", "");
        ChainalysisProxy(d.sanctionsAdapter).setSanctionsRegistry(d.sanctionsList);
        d.sanctionsSentinel = _create(
            "WildcatSanctionsSentinel",
            "WildcatSanctionsSentinel.sol:WildcatSanctionsSentinel",
            abi.encode(d.archController, d.sanctionsAdapter)
        );
        d.feeRecipient = c.deployFeeRecipient
            ? _create(
                "WildcatFeeRecipient",
                "WildcatFeeRecipient.sol:WildcatFeeRecipient",
                abi.encode(c.deployer, c.feeRecipient)
            )
            : c.feeRecipient;

        SphereXEngine engine = SphereXEngine(d.sphereXEngine);
        engine.addAllowedPatterns(SphereXPatterns.getPatterns());
        engine.grantSenderAdderRole(d.archController);
        engine.configureRules(0x0000000000000001);
        WildcatArchController arch = WildcatArchController(d.archController);
        arch.changeSphereXOperator(c.deployer);
        arch.changeSphereXEngine(d.sphereXEngine);

        bytes memory marketCode = vm.getCode("WildcatMarket.sol:WildcatMarket");
        d.marketInitCodeStorage = _store("WildcatMarket_initCodeStorage", "WildcatMarket.sol:WildcatMarket", marketCode);
        d.openTermHooks = _store(
            "OpenTermHooks_initCodeStorage",
            "OpenTermHooks.sol:OpenTermHooks",
            vm.getCode("OpenTermHooks.sol:OpenTermHooks")
        );
        d.fixedTermHooks = _store(
            "FixedTermHooks_initCodeStorage",
            "FixedTermHooks.sol:FixedTermHooks",
            vm.getCode("FixedTermHooks.sol:FixedTermHooks")
        );
        d.hooksFactory = _create(
            "HooksFactory",
            "HooksFactory.sol:HooksFactory",
            abi.encode(d.archController, d.sanctionsSentinel, d.marketInitCodeStorage, uint256(keccak256(marketCode)))
        );
        arch.registerControllerFactory(d.hooksFactory);
        HooksFactory factory = HooksFactory(d.hooksFactory);
        factory.registerWithArchController();
        factory.addHooksTemplate(d.openTermHooks, "OpenTermHooks", d.feeRecipient, address(0), 0, c.protocolFeeBips);
        factory.addHooksTemplate(d.fixedTermHooks, "FixedTermHooks", d.feeRecipient, address(0), 0, c.protocolFeeBips);
        d.marketLens = _create("MarketLens", "MarketLens.sol:MarketLens", abi.encode(d.archController, d.hooksFactory));
        d.wrapperFactory = _create(
            "Wildcat4626WrapperFactory",
            "Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory",
            abi.encode(d.archController)
        );
        d.openAccessRoleProvider = _create(
            "OpenAccessRoleProvider",
            "OpenAccessRoleProvider.sol:OpenAccessRoleProvider",
            abi.encode(d.sanctionsAdapter)
        );

        if (c.chainId == TESTNET) {
            address[] memory initialExecutors = new address[](1);
            initialExecutors[0] = c.deployer;
            d.testnetOwner = _create(
                "MockArchControllerOwner",
                "MockArchControllerOwner.sol:MockArchControllerOwner",
                abi.encode(d.archController, initialExecutors)
            );
            arch.transferOwnership(d.testnetOwner);
        }
    }

    function _create(string memory name, string memory artifact, bytes memory args) internal returns (address) {
        return _createRaw(name, artifact, "contract", args, abi.encodePacked(vm.getCode(artifact), args));
    }

    function _store(string memory name, string memory artifact, bytes memory code) internal returns (address) {
        require(code.length + 1 <= MAX_CODE_SIZE, "Ink: initcode store exceeds EIP-170");
        // match LibStoredInitCode.deployInitCode's creation prefix. runtime is STOP || initcode.
        bytes memory init = abi.encodePacked(bytes1(0x61), bytes2(uint16(code.length + 1)), hex"5f81600a5f39f300", code);
        return _createRaw(name, artifact, "initcode-store", "", init);
    }

    function _createRaw(
        string memory name,
        string memory artifact,
        string memory kind,
        bytes memory args,
        bytes memory init
    ) private returns (address deployed) {
        require(init.length <= 49_152, "Ink: initcode exceeds EIP-3860");
        assembly { deployed := create(0, add(init, 32), mload(init)) }
        require(deployed != address(0), string.concat("Ink: CREATE failed: ", name));
        require(deployed.code.length > 0 && deployed.code.length <= MAX_CODE_SIZE, "Ink: runtime size");
        records.push(
            Record(name, artifact, kind, deployed, args, keccak256(init), deployed.codehash, deployed.code.length)
        );
    }

    function _verify(Config memory c, Deployment memory d) internal view {
        _verify(c, d, true);
    }

    function _verify(Config memory c, Deployment memory d, bool sanctionsSeeded) internal view {
        require(sanctionsSeeded || c.chainId == TESTNET, "Ink: deferred seeding is testnet-only");
        require(block.chainid == c.chainId, "Ink: verify chain");
        WildcatArchController arch = WildcatArchController(d.archController);
        HooksFactory factory = HooksFactory(d.hooksFactory);
        SphereXEngine engine = SphereXEngine(d.sphereXEngine);
        require(arch.owner() == (c.chainId == TESTNET ? d.testnetOwner : c.deployer), "Ink: arch owner");
        require(
            arch.sphereXEngine() == d.sphereXEngine && factory.sphereXEngine() == d.sphereXEngine, "Ink: engine binding"
        );
        require(arch.sphereXAdmin() == c.deployer && arch.sphereXOperator() == c.deployer, "Ink: SphereX authority");
        require(arch.pendingSphereXAdmin() == address(0), "Ink: pending arch admin");
        require(engine.defaultAdmin() == c.deployer && engine.defaultAdminDelay() == 1 hours, "Ink: engine admin");
        (address pendingAdmin,) = engine.pendingDefaultAdmin();
        require(pendingAdmin == address(0), "Ink: pending engine admin");
        require(engine.hasRole(engine.OPERATOR_ROLE(), c.deployer), "Ink: engine operator");
        require(engine.hasRole(engine.SENDER_ADDER_ROLE(), d.archController), "Ink: sender-adder");
        // these slots assume the pinned Plasma engine and OZ 4.9.3; the JS build gate checks them.
        require(uint256(vm.load(d.sphereXEngine, bytes32(uint256(3)))) == 1, "Ink: SphereX rules disabled");
        require(
            uint256(vm.load(d.sphereXEngine, keccak256(abi.encode(d.hooksFactory, uint256(4))))) == 1,
            "Ink: factory sender"
        );
        uint216[] memory patterns = SphereXPatterns.getPatterns();
        for (uint256 i; i < patterns.length; ++i) {
            require(
                uint256(vm.load(d.sphereXEngine, keccak256(abi.encode(patterns[i], uint256(5))))) == 1,
                "Ink: missing SphereX pattern"
            );
        }
        require(
            arch.isRegisteredControllerFactory(d.hooksFactory) && arch.isRegisteredController(d.hooksFactory),
            "Ink: factory registration"
        );
        require(
            factory.archController() == d.archController && factory.sanctionsSentinel() == d.sanctionsSentinel,
            "Ink: factory binding"
        );
        require(factory.marketInitCodeStorage() == d.marketInitCodeStorage, "Ink: market storage");
        require(
            factory.marketInitCodeHash() == uint256(keccak256(vm.getCode("WildcatMarket.sol:WildcatMarket"))),
            "Ink: market hash"
        );
        require(factory.getHooksTemplatesCount() == 2, "Ink: template count");
        _verifyTemplate(factory, d.openTermHooks, d.feeRecipient, c.protocolFeeBips, 0);
        _verifyTemplate(factory, d.fixedTermHooks, d.feeRecipient, c.protocolFeeBips, 1);
        require(address(MarketLens(d.marketLens).archController()) == d.archController, "Ink: lens arch");
        require(address(MarketLens(d.marketLens).hooksFactory()) == d.hooksFactory, "Ink: lens factory");
        require(
            address(Wildcat4626WrapperFactory(d.wrapperFactory).archController()) == d.archController,
            "Ink: wrapper arch"
        );
        require(
            address(OpenAccessRoleProvider(d.openAccessRoleProvider).chainalysisOracle()) == d.sanctionsAdapter,
            "Ink: provider oracle"
        );
        require(ChainalysisProxy(d.sanctionsAdapter).owner() == c.deployer, "Ink: adapter owner");
        require(ChainalysisProxy(d.sanctionsAdapter).sanctionsRegistry() == d.sanctionsList, "Ink: adapter backend");
        WildcatSanctionsSentinel sentinel = WildcatSanctionsSentinel(d.sanctionsSentinel);
        require(
            sentinel.archController() == d.archController && sentinel.chainalysisSanctionsList() == d.sanctionsAdapter,
            "Ink: sentinel binding"
        );
        WildcatCopyOfChainalysisList list = WildcatCopyOfChainalysisList(d.sanctionsList);
        require(list.owner() == c.deployer, "Ink: list updater");
        require(list.getSanctionedAddressesCount() == (sanctionsSeeded ? c.sanctions.length : 0), "Ink: snapshot count");
        for (uint256 i; sanctionsSeeded && i < c.sanctions.length; ++i) {
            require(
                list.isSanctioned(c.sanctions[i]) && sentinel.isFlaggedByChainalysis(c.sanctions[i]),
                "Ink: snapshot entry"
            );
        }
        if (c.deployFeeRecipient) {
            WildcatFeeRecipient recipient = WildcatFeeRecipient(d.feeRecipient);
            require(recipient.owner() == c.deployer && recipient.recipient() == c.feeRecipient, "Ink: treasury");
        } else {
            require(d.feeRecipient == c.feeRecipient, "Ink: fee recipient");
        }
        if (c.chainId == TESTNET) {
            require(d.testnetOwner.code.length > 0, "Ink: missing testnet owner");
            MockArchControllerOwner helper = MockArchControllerOwner(d.testnetOwner);
            require(address(helper.archController()) == d.archController, "Ink: helper arch");
            require(keccak256(bytes(helper.version())) == keccak256("2"), "Ink: helper version");
            address[] memory executors = helper.getAuthorizedAccounts();
            require(executors.length == 1 && helper.getAuthorizedAccountsCount() == 1, "Ink: helper executor count");
            require(executors[0] == c.deployer && helper.authorizedAccounts(c.deployer), "Ink: helper executor");
        } else {
            require(d.testnetOwner == address(0), "Ink: testnet helper on mainnet");
        }
    }

    function _verifyTemplate(HooksFactory factory, address template, address recipient, uint16 fee, uint256 index)
        private
        view
    {
        HooksTemplate memory t = factory.getHooksTemplateDetails(template);
        require(t.exists && t.enabled && t.index == index, "Ink: template registration");
        require(t.feeRecipient == recipient && t.protocolFeeBips == fee, "Ink: template fees");
        require(t.originationFeeAsset == address(0) && t.originationFeeAmount == 0, "Ink: origination fee");
    }

    function _writeCandidate(Config memory c, Deployment memory d, string memory output) internal {
        _writeCandidate(c, d, output, true);
    }

    function _writeCandidate(Config memory c, Deployment memory d, string memory output, bool sanctionsSeeded) internal {
        string memory entries;
        for (uint256 i; i < records.length; ++i) {
            Record memory r = records[i];
            string memory key = string.concat("ink-record-", vm.toString(i));
            vm.serializeString(key, "name", r.name);
            vm.serializeString(key, "artifact", r.artifact);
            vm.serializeString(key, "kind", r.kind);
            vm.serializeAddress(key, "address", r.deployed);
            vm.serializeBytes(key, "constructorArgs", r.constructorArgs);
            vm.serializeBytes32(key, "creationCodeHash", r.creationCodeHash);
            vm.serializeBytes32(key, "runtimeCodeHash", r.runtimeCodeHash);
            string memory entry = vm.serializeUint(key, "runtimeSize", r.runtimeSize);
            entries = string.concat(entries, i == 0 ? "" : ",", entry);
        }
        string memory candidateKey = "ink-candidate";
        vm.serializeJson(candidateKey, string.concat('{"contracts":[', entries, "]}"));
        vm.serializeUint(candidateKey, "schemaVersion", 1);
        vm.serializeUint(candidateKey, "contractCount", records.length);
        vm.serializeString(candidateKey, "status", "unconfirmed-candidate");
        vm.serializeBool(candidateKey, "sanctionsSeeded", sanctionsSeeded);
        vm.serializeUint(candidateKey, "chainId", c.chainId);
        vm.serializeAddress(candidateKey, "deployer", c.deployer);
        vm.serializeUint(candidateKey, "startNonce", c.expectedNonce);
        vm.serializeUint(candidateKey, "endNonce", vm.getNonce(c.deployer));
        vm.serializeBytes32(candidateKey, "configHash", c.configHash);
        vm.serializeBytes32(candidateKey, "snapshotHash", c.snapshotHash);
        vm.serializeBytes32(candidateKey, "sphereXPatternsHash", keccak256(abi.encode(SphereXPatterns.getPatterns())));
        vm.serializeAddress(candidateKey, "feeRecipient", d.feeRecipient);
        vm.serializeString(candidateKey, "coreTag", "v2.1.0");
        vm.serializeString(candidateKey, "coreCommit", "c7be4039f8f383a9dda4e45f63331c17d63f9ed9");
        string memory json =
            vm.serializeString(candidateKey, "plasmaReference", "1bc514b1b0b903b1e94ca8046741fa8c9d367294");
        vm.writeJson(json, output);
    }

    function _run(uint256 expectedChain) internal {
        require(keccak256(bytes(vm.envString("FOUNDRY_PROFILE"))) == keccak256("ink"), "Ink: use ink build profile");
        Config memory c = _readConfig(vm.envString("INK_CONFIG"));
        require(c.chainId == expectedChain, "Ink: wrong entrypoint");
        string memory output = vm.envString("INK_CANDIDATE");
        require(!vm.exists(output), "Ink: candidate exists; resume or use a new run path");
        Deployment memory d = _deploy(c);
        _writeCandidate(c, d, output);
    }

    function _readDeployment(string memory candidate) internal pure returns (Deployment memory d) {
        string memory json = candidate;
        uint256 count = vm.parseJsonUint(json, ".contractCount");
        require(count >= 12 && count <= 14, "Ink: contract count");
        // optional fee/helper records shift indices. resolve contracts by name.
        for (uint256 i; i < count; ++i) {
            string memory prefix = string.concat(".contracts[", vm.toString(i), "]");
            bytes32 name = keccak256(bytes(vm.parseJsonString(json, string.concat(prefix, ".name"))));
            address a = vm.parseJsonAddress(json, string.concat(prefix, ".address"));
            if (name == keccak256("WildcatArchController")) d.archController = a;
            else if (name == keccak256("SphereXEngine")) d.sphereXEngine = a;
            else if (name == keccak256("SanctionsList")) d.sanctionsList = a;
            else if (name == keccak256("SanctionsAdapter")) d.sanctionsAdapter = a;
            else if (name == keccak256("WildcatSanctionsSentinel")) d.sanctionsSentinel = a;
            else if (name == keccak256("WildcatMarket_initCodeStorage")) d.marketInitCodeStorage = a;
            else if (name == keccak256("OpenTermHooks_initCodeStorage")) d.openTermHooks = a;
            else if (name == keccak256("FixedTermHooks_initCodeStorage")) d.fixedTermHooks = a;
            else if (name == keccak256("HooksFactory")) d.hooksFactory = a;
            else if (name == keccak256("MarketLens")) d.marketLens = a;
            else if (name == keccak256("Wildcat4626WrapperFactory")) d.wrapperFactory = a;
            else if (name == keccak256("OpenAccessRoleProvider")) d.openAccessRoleProvider = a;
            else if (name == keccak256("MockArchControllerOwner")) d.testnetOwner = a;
        }
        d.feeRecipient = vm.parseJsonAddress(json, ".feeRecipient");
    }
}
