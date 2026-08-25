// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'src/libraries/LibERC20.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract LibERC20External {
  using LibERC20 for address;

  function safeTransfer(address token, address to, uint256 amount) external {
    token.safeTransfer(to, amount);
  }

  function safeTransferFrom(address token, address from, address to, uint256 amount) external {
    token.safeTransferFrom(from, to, amount);
  }

  function safeTransferAll(address token, address to) external returns (uint256) {
    return token.safeTransferAll(to);
  }

  function balanceOf(address token, address account) external view returns (uint256) {
    return token.balanceOf(account);
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

contract LibERC20NoBalanceReturnToken {
  function balanceOf(address) external pure {}

  function transfer(address, uint256) external pure returns (bool) {
    return true;
  }
}

contract LibERC20BalanceFalseTransferToken {
  function balanceOf(address) external pure returns (uint256) {
    return 123;
  }

  function transfer(address, uint256) external pure returns (bool) {
    return false;
  }
}

contract LibERC20MissingDecimalsToken {}

contract LibERC20Test is TestKernel {
  LibERC20External internal wrapper;

  function setUp() external {
    wrapper = LibERC20External(_deployCode('test-next/libraries/LibERC20.t.sol:LibERC20External'));
  }

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

  function test_safeTransferAll_BalanceOfNoReturnReverts() external {
    LibERC20NoBalanceReturnToken token = new LibERC20NoBalanceReturnToken();

    vm.expectRevert(LibERC20.TransferFailed.selector);
    wrapper.safeTransferAll(address(token), address(0xB0B));
  }

  function test_safeTransferAll_TransferReturningFalseReverts() external {
    LibERC20BalanceFalseTransferToken token = new LibERC20BalanceFalseTransferToken();

    vm.expectRevert(LibERC20.TransferFailed.selector);
    wrapper.safeTransferAll(address(token), address(0xB0B));
  }

  function test_balanceOf_NoReturnReverts() external {
    LibERC20NoBalanceReturnToken token = new LibERC20NoBalanceReturnToken();

    vm.expectRevert(LibERC20.BalanceOfFailed.selector);
    wrapper.balanceOf(address(token), address(this));
  }

  function test_decimals_MissingDecimalsReverts() external {
    LibERC20MissingDecimalsToken token = new LibERC20MissingDecimalsToken();

    vm.expectRevert(LibERC20.DecimalsFailed.selector);
    wrapper.decimals(address(token));
  }
}
