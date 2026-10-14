// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
  InkDeployment,
  WildcatArchController,
  ChainalysisProxy,
  WildcatCopyOfChainalysisList,
  WildcatFeeRecipient,
  SphereXEngine
} from './InkDeployment.sol';
import { console2 } from 'forge-std/console2.sol';

interface IFoundationSafe {
  function getThreshold() external view returns (uint256);
}

/// @dev mainnet only. the EOA nominates, the Safe accepts, then the EOA gives up the remaining roles.
/// choose the list updater separately; governance doesn't inherit that role.
contract HandoffInk is InkDeployment {
  function nominate() external {
    (Config memory c, Deployment memory d) = _inputs();
    address safe = vm.envAddress('INK_FOUNDATION_SAFE');
    _nominate(c, d, safe);
    console2.log('After the engine admin delay, execute these calls FROM the reviewed Safe:');
    console2.log('ArchController:', d.archController);
    console2.logBytes(abi.encodeWithSignature('acceptSphereXAdminRole()'));
    console2.logBytes(abi.encodeWithSignature('changeSphereXOperator(address)', safe));
    console2.log('SphereXEngine:', d.sphereXEngine);
    console2.logBytes(abi.encodeWithSignature('acceptDefaultAdminTransfer()'));
  }

  function finish() external {
    (Config memory c, Deployment memory d) = _inputs();
    _finish(
      c,
      d,
      vm.envAddress('INK_FOUNDATION_SAFE'),
      vm.envAddress('INK_SANCTIONS_UPDATER'),
      vm.envAddress('INK_TREASURY_RECIPIENT')
    );
  }

  function _inputs() internal view returns (Config memory c, Deployment memory d) {
    c = _readConfig(vm.envString('INK_CONFIG'));
    string memory candidate = vm.readFile(vm.envString('INK_CANDIDATE'));
    require(vm.parseJsonBytes32(candidate, '.configHash') == c.configHash, 'Ink: config changed');
    require(vm.parseJsonBytes32(candidate, '.snapshotHash') == c.snapshotHash, 'Ink: snapshot changed');
    uint256 count = vm.parseJsonUint(candidate, '.contractCount');
    for (uint256 i; i < count; ++i) {
      string memory prefix = string.concat('.contracts[', vm.toString(i), ']');
      address deployed = vm.parseJsonAddress(candidate, string.concat(prefix, '.address'));
      require(
        deployed.codehash == vm.parseJsonBytes32(candidate, string.concat(prefix, '.runtimeCodeHash')),
        'Ink: handoff code mismatch'
      );
    }
    d = _readDeployment(candidate);
  }

  function _checkBindings(Deployment memory d) internal view {
    require(WildcatArchController(d.archController).sphereXEngine() == d.sphereXEngine, 'Ink: changed engine');
    require(
      ChainalysisProxy(d.sanctionsAdapter).sanctionsRegistry() == d.sanctionsList, 'Ink: changed sanctions backend'
    );
    require(
      SphereXEngine(d.sphereXEngine).hasRole(SphereXEngine(d.sphereXEngine).SENDER_ADDER_ROLE(), d.archController),
      'Ink: sender-adder missing'
    );
  }

  function _nominate(Config memory c, Deployment memory d, address safe) internal {
    require(c.chainId == MAINNET && block.chainid == MAINNET, 'Ink: mainnet handoff only');
    require(safe.code.length > 0 && IFoundationSafe(safe).getThreshold() > 0, 'Ink: deployed Safe required');
    _checkBindings(d);
    WildcatArchController arch = WildcatArchController(d.archController);
    SphereXEngine engine = SphereXEngine(d.sphereXEngine);
    // list membership can change after bootstrap. don't compare current membership
    // with the bootstrap snapshot during the handoff.
    require(
      arch.owner() == c.deployer && arch.sphereXAdmin() == c.deployer && arch.sphereXOperator() == c.deployer,
      'Ink: current arch authority'
    );
    require(arch.pendingSphereXAdmin() == address(0), 'Ink: existing arch nomination');
    (address pending,) = engine.pendingDefaultAdmin();
    require(engine.defaultAdmin() == c.deployer && pending == address(0), 'Ink: current engine authority');
    require(ChainalysisProxy(d.sanctionsAdapter).owner() == c.deployer, 'Ink: current adapter owner');
    require(WildcatCopyOfChainalysisList(d.sanctionsList).owner() != address(0), 'Ink: no sanctions updater');
    if (c.deployFeeRecipient) {
      require(WildcatFeeRecipient(d.feeRecipient).owner() == c.deployer, 'Ink: treasury owner');
    }
    vm.startBroadcast(c.deployer);
    WildcatArchController(d.archController).transferSphereXAdminRole(safe);
    SphereXEngine(d.sphereXEngine).beginDefaultAdminTransfer(safe);
    SphereXEngine(d.sphereXEngine).grantRole(SphereXEngine(d.sphereXEngine).OPERATOR_ROLE(), safe);
    vm.stopBroadcast();
  }

  function _finish(Config memory c, Deployment memory d, address safe, address updater, address treasury) internal {
    require(c.chainId == MAINNET && block.chainid == MAINNET, 'Ink: mainnet handoff only');
    require(safe.code.length > 0 && IFoundationSafe(safe).getThreshold() > 0, 'Ink: deployed Safe required');
    require(updater != address(0) && treasury != address(0), 'Ink: explicit updater/treasury required');
    require(updater != c.deployer, 'Ink: updater must rotate off deployer');
    require(treasury != c.deployer, 'Ink: treasury must rotate off deployer');
    _checkBindings(d);
    WildcatArchController arch = WildcatArchController(d.archController);
    SphereXEngine engine = SphereXEngine(d.sphereXEngine);
    require(arch.sphereXAdmin() == safe && arch.sphereXOperator() == safe, 'Ink: Safe must accept/configure arch');
    require(
      engine.defaultAdmin() == safe && engine.hasRole(engine.OPERATOR_ROLE(), safe), 'Ink: Safe must accept engine'
    );
    require(
      arch.owner() == c.deployer && ChainalysisProxy(d.sanctionsAdapter).owner() == c.deployer,
      'Ink: current governance owner'
    );
    require(
      ChainalysisProxy(d.sanctionsAdapter).sanctionsRegistry() == d.sanctionsList, 'Ink: changed sanctions backend'
    );
    address currentUpdater = WildcatCopyOfChainalysisList(d.sanctionsList).owner();
    require(currentUpdater == c.deployer || currentUpdater == updater, 'Ink: updater must confirm its own rotation');
    require(engine.hasRole(engine.SENDER_ADDER_ROLE(), d.archController), 'Ink: sender-adder missing');
    if (c.deployFeeRecipient) {
      require(WildcatFeeRecipient(d.feeRecipient).owner() == c.deployer, 'Ink: treasury owner');
    } else {
      require(treasury == d.feeRecipient, 'Ink: external fee recipient cannot be rotated here');
    }
    vm.startBroadcast(c.deployer);
    arch.transferOwnership(safe);
    ChainalysisProxy(d.sanctionsAdapter).transferOwnership(safe);
    if (currentUpdater == c.deployer) WildcatCopyOfChainalysisList(d.sanctionsList).transferOwnership(updater);
    if (c.deployFeeRecipient) {
      WildcatFeeRecipient(d.feeRecipient).changeRecipient(treasury);
      WildcatFeeRecipient(d.feeRecipient).changeOwner(safe);
    }
    engine.renounceRole(engine.OPERATOR_ROLE(), c.deployer);
    vm.stopBroadcast();
    require(
      arch.owner() == safe && ChainalysisProxy(d.sanctionsAdapter).owner() == safe, 'Ink: governance handoff failed'
    );
    require(WildcatCopyOfChainalysisList(d.sanctionsList).owner() == updater, 'Ink: updater handoff failed');
    require(
      !engine.hasRole(engine.OPERATOR_ROLE(), c.deployer) && engine.defaultAdmin() == safe, 'Ink: retained engine power'
    );
    if (c.deployFeeRecipient) {
      require(
        WildcatFeeRecipient(d.feeRecipient).owner() == safe
          && WildcatFeeRecipient(d.feeRecipient).recipient() == treasury,
        'Ink: treasury handoff failed'
      );
    }
  }
}
