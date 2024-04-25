// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './interfaces/IWildcatArchController.sol';
import './libraries/LibStoredInitCode.sol';

contract HooksFactory {
  error NotApprovedBorrower();
  error NotApprovedHooksConstructor();
  error DeploymentFailed();

  event HooksContractDeployed(address hooksInstance, address hooksConstructor);

  IWildcatArchController public immutable archController;
  mapping(address => bool) public hooksDeployed;
  mapping(address => bool) public whitelistedHooksConstructors;

  constructor(address _archController) {
    archController = IWildcatArchController(_archController);
  }

  function deployHooksForMarket(address hooksConstructor, bytes calldata constructorArgs) external {
    if (!archController.isRegisteredBorrower(msg.sender)) {
      revert NotApprovedBorrower();
    }
    if (!whitelistedHooksConstructors[hooksConstructor]) {
      revert NotApprovedHooksConstructor();
    }

    address hooks;

    assembly {
      let initCodePointer := mload(0x40)
      let initCodeSize := sub(extcodesize(hooksConstructor), 1)
      // Copy code from target address to memory starting at byte 1
      extcodecopy(hooksConstructor, initCodePointer, 1, initCodeSize)
      let endInitCodePointer := add(initCodePointer, initCodeSize)
      // Write the address of the caller as the first parameter
      mstore(endInitCodePointer, caller())
      // Copy constructor args to init code after the address of the deployer
      let constructorArgsSize := constructorArgs.length
      calldatacopy(add(endInitCodePointer, 0x20), constructorArgs.offset, constructorArgsSize)
      // Copy constructor args from calldata to end of initcode after (address, args.offset, args.length)
      let initCodeSizeWithArgs := add(add(initCodeSize, 0x20), constructorArgsSize)
      hooks := create(0, initCodePointer, initCodeSizeWithArgs)
      if iszero(hooks) {
        mstore(0x00, 0x30116425) // DeploymentFailed()
        revert(0x1c, 0x04)
      }
    }

    emit HooksContractDeployed(hooks, hooksConstructor);
    hooksDeployed[hooks] = true;
  }
}
