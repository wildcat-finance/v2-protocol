// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'src/libraries/FIFOQueue.sol';
import './wrappers/FIFOQueueLibExternal.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// Uses an external wrapper library to make forge coverage work for FIFOQueueLib.
// Forge is currently incapable of mapping MemberAccess function calls with
// expressions other than library identifiers (e.g. value.x() vs XLib.x(value))
// to the correct FunctionDefinition nodes.
contract FIFOQueueTest is TestKernel {
  FIFOQueue internal arr;

  using FIFOQueueLibExternal for FIFOQueue;

  function test_empty() external {
    assertEq(arr.$empty(), true);
    arr.$push(1);
    assertEq(arr.$empty(), false);
    arr.$shift();
    assertEq(arr.$empty(), true);
  }

  function test() external {
    arr.$push(1);
    arr.$push(2);
    arr.$push(3);
    arr.$shift();
    arr.$push(4);
    arr.$shiftN(2);
    assertEq(arr.$length(), 1);
    assertEq(arr.$first(), 4);
    assertEq(arr.$at(0), 4);
  }

  function test_push() external {
    assertEq(arr.$length(), 0);
    arr.$push(1);
    assertEq(arr.$length(), 1);
    assertEq(arr.$first(), 1);
    assertEq(arr.$at(0), 1);
    assertEq(arr.startIndex, 0);
    assertEq(arr.nextIndex, 1);
  }

  function test_shift() external {
    arr.$push(1);
    arr.$shift();
    assertEq(arr.startIndex, 1);
    assertEq(arr.nextIndex, 1);
  }

  function test_shift_OutOfBounds() external {
    arr.$push(1);
    arr.$shift();
    assertEq(arr.startIndex, 1);
    assertEq(arr.nextIndex, 1);
    vm.expectRevert(FIFOQueueLibExternal.FIFOQueueOutOfBounds.selector);
    arr.$shift();
  }

  function test_shiftN() external {
    arr.$push(1);
    arr.$push(1);
    arr.$push(1);
    arr.$shiftN(2);
    assertEq(arr.$length(), 1);
    assertEq(arr.startIndex, 2);
    assertEq(arr.nextIndex, 3);
  }

  function test_shiftN_OutOfBounds() external {
    arr.$push(1);
    vm.expectRevert(FIFOQueueLibExternal.FIFOQueueOutOfBounds.selector);
    arr.$shiftN(2);
  }

  function test_first() external {
    arr.$push(1);
    assertEq(arr.$first(), 1);
  }

  function test_first_OutOfBounds() external {
    vm.expectRevert(FIFOQueueLibExternal.FIFOQueueOutOfBounds.selector);
    arr.$first();
  }

  function test_at() external {
    arr.$push(1);
    assertEq(arr.$at(0), 1);
    arr.$push(2);
    arr.$shift();
    assertEq(arr.$at(0), 2);
  }

  function test_at_OutOfBounds() external {
    vm.expectRevert(FIFOQueueLibExternal.FIFOQueueOutOfBounds.selector);
    arr.$at(0);
  }

  function test_values() external {
    assertEq(arr.$values().length, 0);
    uint32[] memory _arr = new uint32[](3);
    _arr[0] = 1;
    _arr[1] = 2;
    _arr[2] = 3;
    arr.$push(1);
    arr.$push(2);
    arr.$push(3);
    assertEq(arr.$values(), _arr);
  }

  function test_values_AcrossPackedWords() external {
    for (uint32 i = 1; i <= 10; i++) {
      arr.$push(i);
    }
    arr.$shiftN(3);

    uint32[] memory expected = new uint32[](7);
    for (uint32 i = 0; i < expected.length; i++) {
      expected[i] = i + 4;
    }
    assertEq(arr.$values(), expected);
  }

  function test_shift_AcrossPackedWord() external {
    for (uint32 i = 1; i <= 9; i++) {
      arr.$push(i);
    }
    for (uint32 i = 1; i <= 8; i++) {
      assertEq(arr.$first(), i);
      arr.$shift();
    }
    assertEq(arr.$first(), 9);
    assertEq(arr.$length(), 1);
  }

  function test_shiftN_AcrossPackedWords() external {
    for (uint32 i = 1; i <= 20; i++) {
      arr.$push(i);
    }
    arr.$shiftN(13);
    assertEq(arr.$first(), 14);

    for (uint32 i = 21; i <= 24; i++) {
      arr.$push(i);
    }

    uint32[] memory expected = new uint32[](11);
    for (uint32 i = 0; i < expected.length; i++) {
      expected[i] = i + 14;
    }
    assertEq(arr.$values(), expected);
  }

  function test_shiftN_EmptyPartialWordCanBeReused() external {
    for (uint32 i = 1; i <= 3; i++) {
      arr.$push(i);
    }
    arr.$shiftN(3);
    arr.$push(4);
    assertEq(arr.$first(), 4);
    assertEq(arr.$values().length, 1);
  }

  function test_shift_ClearsFullWords() external {
    for (uint32 i = 1; i <= 9; i++) {
      arr.$push(i);
    }
    arr.$shiftN(8);
    assertEq(arr.$word(0), 0);
    assertEq(arr.$word(1), 9);

    arr.$shift();
    assertEq(arr.$word(1), 9);

    for (uint32 i = 10; i <= 16; i++) {
      arr.$push(i);
    }
    arr.$shiftN(7);
    assertEq(arr.$word(1), 0);
  }

  function testFuzz_matchesReference(
    uint32[] calldata initialValues,
    uint32[] calldata extraValues,
    uint256 shiftSeed
  ) external {
    uint256 initialLength = initialValues.length < 32 ? initialValues.length : 32;
    uint256 extraLength = extraValues.length < 16 ? extraValues.length : 16;

    for (uint256 i = 0; i < initialLength; i++) {
      arr.$push(initialValues[i]);
    }

    uint256 shiftCount = bound(shiftSeed, 0, initialLength);
    arr.$shiftN(uint128(shiftCount));

    for (uint256 i = 0; i < extraLength; i++) {
      arr.$push(extraValues[i]);
    }

    uint32[] memory expected = new uint32[](initialLength - shiftCount + extraLength);
    uint256 expectedIndex;
    for (uint256 i = shiftCount; i < initialLength; i++) {
      expected[expectedIndex++] = initialValues[i];
    }
    for (uint256 i = 0; i < extraLength; i++) {
      expected[expectedIndex++] = extraValues[i];
    }

    assertEq(arr.$length(), expected.length);
    assertEq(arr.$values(), expected);
    for (uint256 i = 0; i < expected.length; i++) {
      assertEq(arr.$at(i), expected[i]);
    }
  }

  function assertEq(uint32[] memory a, uint32[] memory b) internal pure {
    assertEq(a.length, b.length, 'length');
    for (uint256 i = 0; i < a.length; i++) {
      assertEq(a[i], b[i]);
    }
  }
}
