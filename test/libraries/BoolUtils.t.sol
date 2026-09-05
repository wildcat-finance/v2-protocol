// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BoolUtils } from 'src/libraries/BoolUtils.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract BoolUtilsTest is TestKernel {
  function test_and(bool a, bool b) external pure {
    assertEq(BoolUtils.and(a, b), a && b);
  }

  function test_or(bool a, bool b) external pure {
    assertEq(BoolUtils.or(a, b), a || b);
  }

  function test_xor(bool a, bool b) external pure {
    assertEq(BoolUtils.xor(a, b), a != b);
  }
}
