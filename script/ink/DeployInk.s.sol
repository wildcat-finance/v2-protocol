// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { InkDeployment } from './InkDeployment.sol';

contract DeployInkMainnet is InkDeployment {
  function run() external {
    _run(MAINNET);
  }
}

contract DeployInkTestnet is InkDeployment {
  function run() external {
    _run(TESTNET);
  }
}

/// @dev read-only post-broadcast check. don't use --broadcast here.
contract VerifyInk is InkDeployment {
  function run() external view {
    Config memory c = _readConfig(vm.envString('INK_CONFIG'));
    string memory candidate = vm.readFile(vm.envString('INK_CANDIDATE'));
    require(vm.parseJsonBytes32(candidate, '.configHash') == c.configHash, 'Ink: config changed');
    require(vm.parseJsonBytes32(candidate, '.snapshotHash') == c.snapshotHash, 'Ink: snapshot changed');
    _verify(c, _readDeployment(candidate));
  }
}
