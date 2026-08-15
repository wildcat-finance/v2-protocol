// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.19;

import { Test } from 'forge-std/Test.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import './wrappers/LibStoredInitCodeExternal.sol';

contract SplitInitCodeTestContract {
  uint256 internal immutable value = 123;

  function getValue() external view returns (uint256) {
    return value;
  }
}

contract LibStoredInitCodeTwoPartsTest is Test {
  LibStoredInitCodeExternal internal immutable lib = new LibStoredInitCodeExternal();

  function test_deployInitCodeInTwoParts() external {
    bytes memory data = hex'aabbccddeeff';
    bytes32 originalHash = keccak256(data);
    (address first, address second) = lib.deployInitCodeInTwoParts(data);

    assertEq(first.codehash, keccak256(hex'00aabbcc'));
    assertEq(second.codehash, keccak256(hex'00ddeeff'));
    assertEq(keccak256(data), originalHash, 'input restored');
  }

  function test_create2WithStoredInitCode_TwoParts(bytes32 salt) external {
    uint256 create2Prefix = lib.getCreate2Prefix(address(lib));
    bytes memory initCode = type(SplitInitCodeTestContract).creationCode;
    (address initCodeStorage, address initCodeStorage2) = lib.deployInitCodeInTwoParts(initCode);
    uint256 initCodeHash = uint256(keccak256(initCode));

    address deployed = lib.create2WithStoredInitCode(initCodeStorage, initCodeStorage2, salt);
    assertEq(deployed.codehash, address(new SplitInitCodeTestContract()).codehash, 'codehash');
    assertEq(deployed.balance, 0, 'balance');
    assertEq(
      deployed,
      address(
        uint160(uint256(keccak256(abi.encodePacked(uint168(create2Prefix), salt, initCodeHash))))
      )
    );
  }

  function test_create2WithStoredInitCode_TwoPartsDeploymentFailed(bytes32 salt) external {
    bytes memory initCode = type(SplitInitCodeTestContract).creationCode;
    (address initCodeStorage, address initCodeStorage2) = lib.deployInitCodeInTwoParts(initCode);

    lib.create2WithStoredInitCode(initCodeStorage, initCodeStorage2, salt);
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    lib.create2WithStoredInitCode(initCodeStorage, initCodeStorage2, salt);
  }
}
