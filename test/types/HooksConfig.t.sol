// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/types/HooksConfig.sol';
import 'forge-std/Test.sol';
import '../helpers/Assertions.sol';

contract HooksConfigTest is Test, Assertions {
  function testEncode(StandardHooksConfig memory input) external {
    HooksConfig hooks = input.toHooksConfig();
    assertEq(hooks, input);
  }
}
