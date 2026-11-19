// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // LibERC20.t
//  \ ^ /   Safe-token transfer, balance, and metadata compatibility tests.
//    V
//
//  TRANSFER ADAPTERS
//  safeTransfer(...)
//  safeTransferFrom(...)
//  safeTransferAll(...)
//
//  QUERY ADAPTERS
//  balanceOf(...)
//  decimals(...)
//  name(...)
//  symbol(...)
//
//  NO RETURN TOKEN
//  transfer(...)
//  transferFrom(...)
//
//  FALSE RETURN TOKEN
//  transfer(...)
//  transferFrom(...)
//
//  NO BALANCE RETURN TOKEN
//  balanceOf(...)
//  transfer(...)
//
//  FALSE TRANSFER TOKEN
//  balanceOf(...)
//  transfer(...)
//
//  FIXTURE
//  setUp()
//
//  SAFE TRANSFERS
//  test_safeTransfer_NoReturnData()
//  test_safeTransferFrom_NoReturnData()
//  test_safeTransfer_ReturningFalseReverts()
//  test_safeTransferAll_BalanceOfNoReturnReverts()
//  test_safeTransferAll_TransferReturningFalseReverts()
//
//  TOKEN QUERIES
//  test_balanceOf_NoReturnReverts()
//  test_decimals_MissingDecimalsReverts()
//  test_nameAndSymbol_Bytes32Metadata()
// ═════

import 'src/libraries/LibERC20.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// ┌─ LibERC20External ─────────────────────────────────────────────────────────
contract LibERC20External {
  using LibERC20 for address;

  // ░░▒▒▓▓██ [ TRANSFER ADAPTERS ] ────────────────────────────────────────────

  // ┌─ safeTransfer ─────
  function safeTransfer(address token, address to, uint256 amount) external {
    token.safeTransfer(to, amount);
  }

  // ┌─ safeTransferFrom ─────
  function safeTransferFrom(address token, address from, address to, uint256 amount) external {
    token.safeTransferFrom(from, to, amount);
  }

  // ┌─ safeTransferAll ─────
  function safeTransferAll(address token, address to) external returns (uint256) {
    return token.safeTransferAll(to);
  }

  // ░░▒▒▓▓██ [ QUERY ADAPTERS ] ───────────────────────────────────────────────

  // ┌─ balanceOf ─────
  function balanceOf(address token, address account) external view returns (uint256) {
    return token.balanceOf(account);
  }

  // ┌─ decimals ─────
  function decimals(address token) external view returns (uint8) {
    return token.decimals();
  }

  // ┌─ name ─────
  function name(address token) external view returns (string memory) {
    return token.name();
  }

  // ┌─ symbol ─────
  function symbol(address token) external view returns (string memory) {
    return token.symbol();
  }
}

// ┌─ LibERC20Bytes32Metadata ──────────────────────────────────────────────────
contract LibERC20Bytes32Metadata {
  bytes32 public constant name = 'TestToken';
  bytes32 public constant symbol = 'TEST';
}

// ┌─ LibERC20NoReturnToken ────────────────────────────────────────────────────
contract LibERC20NoReturnToken {
  address public lastSender;
  address public lastFrom;
  address public lastTo;
  uint256 public lastAmount;
  bool public transferFromCalled;

  // ░░▒▒▓▓██ [ NO RETURN TOKEN ] ──────────────────────────────────────────────

  // ┌─ transfer ─────
  function transfer(address to, uint256 amount) external {
    lastSender = msg.sender;
    lastTo = to;
    lastAmount = amount;
  }

  // ┌─ transferFrom ─────
  function transferFrom(address from, address to, uint256 amount) external {
    lastSender = msg.sender;
    lastFrom = from;
    lastTo = to;
    lastAmount = amount;
    transferFromCalled = true;
  }
}

// ┌─ LibERC20FalseReturnToken ─────────────────────────────────────────────────
contract LibERC20FalseReturnToken {
  // ░░▒▒▓▓██ [ FALSE RETURN TOKEN ] ───────────────────────────────────────────

  // ┌─ transfer ─────
  function transfer(address, uint256) external pure returns (bool) {
    return false;
  }

  // ┌─ transferFrom ─────
  function transferFrom(address, address, uint256) external pure returns (bool) {
    return false;
  }
}

// ┌─ LibERC20NoBalanceReturnToken ─────────────────────────────────────────────
contract LibERC20NoBalanceReturnToken {
  // ░░▒▒▓▓██ [ NO BALANCE RETURN TOKEN ] ──────────────────────────────────────

  // ┌─ balanceOf ─────
  function balanceOf(address) external pure { }

  // ┌─ transfer ─────
  function transfer(address, uint256) external pure returns (bool) {
    return true;
  }
}

// ┌─ LibERC20BalanceFalseTransferToken ────────────────────────────────────────
contract LibERC20BalanceFalseTransferToken {
  // ░░▒▒▓▓██ [ FALSE TRANSFER TOKEN ] ─────────────────────────────────────────

  // ┌─ balanceOf ─────
  function balanceOf(address) external pure returns (uint256) {
    return 123;
  }

  // ┌─ transfer ─────
  function transfer(address, uint256) external pure returns (bool) {
    return false;
  }
}

// ┌─ LibERC20MissingDecimalsToken ─────────────────────────────────────────────
contract LibERC20MissingDecimalsToken { }

// ┌─ LibERC20Test ─────────────────────────────────────────────────────────────
contract LibERC20Test is TestKernel {
  LibERC20External internal wrapper;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    wrapper = LibERC20External(_deployCode('test/libraries/LibERC20.t.sol:LibERC20External'));
  }

  // ░░▒▒▓▓██ [ SAFE TRANSFERS ] ───────────────────────────────────────────────

  // ┌─ test_safeTransfer_NoReturnData ─────
  function test_safeTransfer_NoReturnData() external {
    LibERC20NoReturnToken token = new LibERC20NoReturnToken();
    address to = address(0xB0B);

    wrapper.safeTransfer(address(token), to, 123);

    assertEq(token.lastSender(), address(wrapper), 'lastSender');
    assertEq(token.lastTo(), to, 'lastTo');
    assertEq(token.lastAmount(), 123, 'lastAmount');
    assertFalse(token.transferFromCalled(), 'transferFromCalled');
  }

  // ┌─ test_safeTransferFrom_NoReturnData ─────
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

  // ┌─ test_safeTransfer_ReturningFalseReverts ─────
  function test_safeTransfer_ReturningFalseReverts() external {
    LibERC20FalseReturnToken token = new LibERC20FalseReturnToken();

    vm.expectRevert(LibERC20.TransferFailed.selector);
    wrapper.safeTransfer(address(token), address(0xB0B), 1);

    vm.expectRevert(LibERC20.TransferFromFailed.selector);
    wrapper.safeTransferFrom(address(token), address(0xA11CE), address(0xB0B), 1);
  }

  // ┌─ test_safeTransferAll_BalanceOfNoReturnReverts ─────
  function test_safeTransferAll_BalanceOfNoReturnReverts() external {
    LibERC20NoBalanceReturnToken token = new LibERC20NoBalanceReturnToken();

    vm.expectRevert(LibERC20.TransferFailed.selector);
    wrapper.safeTransferAll(address(token), address(0xB0B));
  }

  // ┌─ test_safeTransferAll_TransferReturningFalseReverts ─────
  function test_safeTransferAll_TransferReturningFalseReverts() external {
    LibERC20BalanceFalseTransferToken token = new LibERC20BalanceFalseTransferToken();

    vm.expectRevert(LibERC20.TransferFailed.selector);
    wrapper.safeTransferAll(address(token), address(0xB0B));
  }

  // ░░▒▒▓▓██ [ TOKEN QUERIES ] ────────────────────────────────────────────────

  // ┌─ test_balanceOf_NoReturnReverts ─────
  function test_balanceOf_NoReturnReverts() external {
    LibERC20NoBalanceReturnToken token = new LibERC20NoBalanceReturnToken();

    vm.expectRevert(LibERC20.BalanceOfFailed.selector);
    wrapper.balanceOf(address(token), address(this));
  }

  // ┌─ test_decimals_MissingDecimalsReverts ─────
  function test_decimals_MissingDecimalsReverts() external {
    LibERC20MissingDecimalsToken token = new LibERC20MissingDecimalsToken();

    vm.expectRevert(LibERC20.DecimalsFailed.selector);
    wrapper.decimals(address(token));
  }

  // ┌─ test_nameAndSymbol_Bytes32Metadata ─────
  function test_nameAndSymbol_Bytes32Metadata() external {
    LibERC20Bytes32Metadata token = new LibERC20Bytes32Metadata();

    assertEq(wrapper.name(address(token)), 'TestToken', 'name');
    assertEq(wrapper.symbol(address(token)), 'TEST', 'symbol');
  }
}
