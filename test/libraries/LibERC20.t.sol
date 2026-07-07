// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/libraries/LibERC20.sol';

contract LibERC20External {
  using LibERC20 for address;

  function safeTransfer(address token, address to, uint256 amount) external {
    token.safeTransfer(to, amount);
  }

  function safeTransferFrom(address token, address from, address to, uint256 amount) external {
    token.safeTransferFrom(from, to, amount);
  }

  function decimals(address token) external view returns (uint8) {
    return token.decimals();
  }

  function name(address token) external view returns (string memory) {
    return token.name();
  }

  function symbol(address token) external view returns (string memory) {
    return token.symbol();
  }
}

contract LibERC20Bytes32Metadata {
  bytes32 public constant name = 'TestToken';
  bytes32 public constant symbol = 'TEST';
}

contract LibERC20NoReturnToken {
  address public lastSender;
  address public lastFrom;
  address public lastTo;
  uint256 public lastAmount;
  bool public transferFromCalled;

  function transfer(address to, uint256 amount) external {
    lastSender = msg.sender;
    lastTo = to;
    lastAmount = amount;
  }

  function transferFrom(address from, address to, uint256 amount) external {
    lastSender = msg.sender;
    lastFrom = from;
    lastTo = to;
    lastAmount = amount;
    transferFromCalled = true;
  }
}

contract LibERC20FalseReturnToken {
  function transfer(address, uint256) external pure returns (bool) {
    return false;
  }

  function transferFrom(address, address, uint256) external pure returns (bool) {
    return false;
  }
}

contract LibERC20MissingDecimalsToken {}

contract LibERC20Test is Test {
  LibERC20External internal wrapper = new LibERC20External();

  function test_nameAndSymbol_Bytes32Metadata() external {
    LibERC20Bytes32Metadata token = new LibERC20Bytes32Metadata();

    assertEq(wrapper.name(address(token)), 'TestToken', 'name');
    assertEq(wrapper.symbol(address(token)), 'TEST', 'symbol');
  }

  function test_safeTransfer_NoReturnData() external {
    LibERC20NoReturnToken token = new LibERC20NoReturnToken();
    address to = address(0xB0B);

    wrapper.safeTransfer(address(token), to, 123);

    assertEq(token.lastSender(), address(wrapper), 'lastSender');
    assertEq(token.lastTo(), to, 'lastTo');
    assertEq(token.lastAmount(), 123, 'lastAmount');
    assertFalse(token.transferFromCalled(), 'transferFromCalled');
  }

  function test_safeTransferFrom_NoReturnData() external {
    LibERC20NoReturnToken token = new LibERC20NoReturnToken();
    address from = address(0xA11CE);
    address to = address(0xB0B);

    wrapper.safeTransferFrom(address(token), from, to, 456);

    assertEq(token.lastSender(), address(wrapper), 'lastSender');
    assertEq(token.lastFrom(), from, 'lastFrom');
    assertEq(token.lastTo(), to, 'lastTo');
    assertEq(token.lastAmount(), 456, 'lastAmount');
    assertTrue(token.transferFromCalled(), 'transferFromCalled');
  }

  function test_safeTransfer_ReturningFalseReverts() external {
    LibERC20FalseReturnToken token = new LibERC20FalseReturnToken();

    vm.expectRevert(LibERC20.TransferFailed.selector);
    wrapper.safeTransfer(address(token), address(0xB0B), 1);

    vm.expectRevert(LibERC20.TransferFromFailed.selector);
    wrapper.safeTransferFrom(address(token), address(0xA11CE), address(0xB0B), 1);
  }

  function test_decimals_MissingDecimalsReverts() external {
    LibERC20MissingDecimalsToken token = new LibERC20MissingDecimalsToken();

    vm.expectRevert(LibERC20.DecimalsFailed.selector);
    wrapper.decimals(address(token));
  }
}
