// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { Vm } from 'forge-std/Vm.sol';

abstract contract TestKernel {
  error ArtifactDeploymentFailed(string artifact);

  address internal constant VmAddress = address(uint160(uint256(keccak256('hevm cheat code'))));
  Vm internal constant vm = Vm(VmAddress);

  modifier asAccount(address account) {
    vm.startPrank(account);
    _;
    vm.stopPrank();
  }

  function _deployCode(string memory artifact) internal returns (address deployed) {
    return _deployCode(artifact, '');
  }

  function _deployCode(
    string memory artifact,
    bytes memory constructorArguments
  ) internal returns (address deployed) {
    bytes memory creationCode = abi.encodePacked(vm.getCode(artifact), constructorArguments);
    assembly ('memory-safe') {
      deployed := create(0, add(creationCode, 0x20), mload(creationCode))
      if iszero(deployed) {
        let returnDataSize := returndatasize()
        if returnDataSize {
          let returnDataPointer := mload(0x40)
          returndatacopy(returnDataPointer, 0, returnDataSize)
          revert(returnDataPointer, returnDataSize)
        }
      }
    }
    if (deployed == address(0)) revert ArtifactDeploymentFailed(artifact);
  }

  function _bound(uint256 value, uint256 minimum, uint256 maximum) internal pure returns (uint256) {
    require(minimum <= maximum, 'invalid bounds');
    if (value >= minimum && value <= maximum) return value;

    uint256 size = maximum - minimum + 1;
    if (value <= 3 && size > value) return minimum + value;
    if (value >= type(uint256).max - 3 && size > type(uint256).max - value) {
      return maximum - (type(uint256).max - value);
    }
    if (value > maximum) {
      uint256 upperRemainder = (value - maximum) % size;
      return upperRemainder == 0 ? maximum : minimum + upperRemainder - 1;
    }

    uint256 lowerRemainder = (minimum - value) % size;
    return lowerRemainder == 0 ? minimum : maximum - lowerRemainder + 1;
  }

  function bound(uint256 value, uint256 minimum, uint256 maximum) internal pure returns (uint256) {
    return _bound(value, minimum, maximum);
  }

  function _warp(uint256 timestamp) internal {
    vm.warp(timestamp);
  }

  function warp(uint256 timestamp) internal {
    vm.warp(timestamp);
  }

  function _fastForward(uint256 secondsToAdvance) internal {
    vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
  }

  function fastForward(uint256 secondsToAdvance) internal {
    vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
  }

  function getTimestamp() internal view returns (uint256) {
    return vm.getBlockTimestamp();
  }

  function assertTrue(bool value) internal pure {
    vm.assertTrue(value);
  }

  function assertTrue(bool value, string memory message) internal pure {
    vm.assertTrue(value, message);
  }

  function assertFalse(bool value) internal pure {
    vm.assertFalse(value);
  }

  function assertFalse(bool value, string memory message) internal pure {
    vm.assertFalse(value, message);
  }

  function assertEq(bool left, bool right, string memory message) internal pure {
    vm.assertEq(left, right, message);
  }

  function assertEq(bool left, bool right) internal pure {
    vm.assertEq(left, right);
  }

  function assertEq(address left, address right, string memory message) internal pure {
    vm.assertEq(left, right, message);
  }

  function assertEq(address left, address right) internal pure {
    vm.assertEq(left, right);
  }

  function assertEq(uint256 left, uint256 right, string memory message) internal pure {
    vm.assertEq(left, right, message);
  }

  function assertEq(uint256 left, uint256 right) internal pure {
    vm.assertEq(left, right);
  }

  function assertEq(bytes32 left, bytes32 right, string memory message) internal pure {
    vm.assertEq(left, right, message);
  }

  function assertEq(bytes32 left, bytes32 right) internal pure {
    vm.assertEq(left, right);
  }

  function assertEq(string memory left, string memory right, string memory message) internal pure {
    vm.assertEq(left, right, message);
  }

  function assertEq(string memory left, string memory right) internal pure {
    vm.assertEq(left, right);
  }

  function assertEq(bytes memory left, bytes memory right, string memory message) internal pure {
    vm.assertEq(left, right, message);
  }

  function assertEq(bytes memory left, bytes memory right) internal pure {
    vm.assertEq(left, right);
  }
}
