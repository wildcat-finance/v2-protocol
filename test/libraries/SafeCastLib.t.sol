// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // SafeCastLib.t
//  \ ^ /   Checked unsigned cast boundaries in ascending bit widths.
//    V
//
//  FIXTURE
//  setUp()
//
//  UNSIGNED CASTS
//  test_toUint8(...)
//  test_toUint16(...)
//  test_toUint24(...)
//  test_toUint32(...)
//  test_toUint40(...)
//  test_toUint48(...)
//  test_toUint56(...)
//  test_toUint64(...)
//  test_toUint72(...)
//  test_toUint80(...)
//  test_toUint88(...)
//  test_toUint96(...)
//  test_toUint104(...)
//  test_toUint112(...)
//  test_toUint120(...)
//  test_toUint128(...)
//  test_toUint136(...)
//  test_toUint144(...)
//  test_toUint152(...)
//  test_toUint160(...)
//  test_toUint168(...)
//  test_toUint176(...)
//  test_toUint184(...)
//  test_toUint192(...)
//  test_toUint200(...)
//  test_toUint208(...)
//  test_toUint216(...)
//  test_toUint224(...)
//  test_toUint232(...)
//  test_toUint240(...)
//  test_toUint248(...)
// ═════

import './wrappers/SafeCastLibExternal.sol';
import { TestKernel } from '../shared/TestKernel.sol';

bytes4 constant Panic_ErrorSelector = 0x4e487b71;
uint256 constant Panic_Arithmetic = 0x11;

// coverage workaround for SafeCastLib: the external wrapper uses library-qualified calls
// (XLib.x(value)), so the mapper sees the library identifier instead of value.x().
// ┌─ SafeCastLibTest ──────────────────────────────────────────────────────────
contract SafeCastLibTest is TestKernel {
  SafeCastLibExternal internal wrapper;
  bytes internal ArithmeticError = abi.encodePacked(Panic_ErrorSelector, Panic_Arithmetic);

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    wrapper = SafeCastLibExternal(_deployCode('test/libraries/wrappers/SafeCastLibExternal.sol:SafeCastLibExternal'));
  }

  // ░░▒▒▓▓██ [ UNSIGNED CASTS ] ───────────────────────────────────────────────

  // ┌─ test_toUint8 ─────
  function test_toUint8(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint8).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint8).max);
    assertEq(wrapper.toUint8(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint8(overflowingX);
  }

  // ┌─ test_toUint16 ─────
  function test_toUint16(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint16).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint16).max);
    assertEq(wrapper.toUint16(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint16(overflowingX);
  }

  // ┌─ test_toUint24 ─────
  function test_toUint24(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint24).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint24).max);
    assertEq(wrapper.toUint24(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint24(overflowingX);
  }

  // ┌─ test_toUint32 ─────
  function test_toUint32(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint32).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint32).max);
    assertEq(wrapper.toUint32(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint32(overflowingX);
  }

  // ┌─ test_toUint40 ─────
  function test_toUint40(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint40).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint40).max);
    assertEq(wrapper.toUint40(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint40(overflowingX);
  }

  // ┌─ test_toUint48 ─────
  function test_toUint48(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint48).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint48).max);
    assertEq(wrapper.toUint48(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint48(overflowingX);
  }

  // ┌─ test_toUint56 ─────
  function test_toUint56(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint56).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint56).max);
    assertEq(wrapper.toUint56(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint56(overflowingX);
  }

  // ┌─ test_toUint64 ─────
  function test_toUint64(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint64).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint64).max);
    assertEq(wrapper.toUint64(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint64(overflowingX);
  }

  // ┌─ test_toUint72 ─────
  function test_toUint72(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint72).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint72).max);
    assertEq(wrapper.toUint72(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint72(overflowingX);
  }

  // ┌─ test_toUint80 ─────
  function test_toUint80(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint80).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint80).max);
    assertEq(wrapper.toUint80(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint80(overflowingX);
  }

  // ┌─ test_toUint88 ─────
  function test_toUint88(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint88).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint88).max);
    assertEq(wrapper.toUint88(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint88(overflowingX);
  }

  // ┌─ test_toUint96 ─────
  function test_toUint96(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint96).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint96).max);
    assertEq(wrapper.toUint96(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint96(overflowingX);
  }

  // ┌─ test_toUint104 ─────
  function test_toUint104(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint104).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint104).max);
    assertEq(wrapper.toUint104(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint104(overflowingX);
  }

  // ┌─ test_toUint112 ─────
  function test_toUint112(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint112).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint112).max);
    assertEq(wrapper.toUint112(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint112(overflowingX);
  }

  // ┌─ test_toUint120 ─────
  function test_toUint120(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint120).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint120).max);
    assertEq(wrapper.toUint120(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint120(overflowingX);
  }

  // ┌─ test_toUint128 ─────
  function test_toUint128(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint128).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint128).max);
    assertEq(wrapper.toUint128(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint128(overflowingX);
  }

  // ┌─ test_toUint136 ─────
  function test_toUint136(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint136).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint136).max);
    assertEq(wrapper.toUint136(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint136(overflowingX);
  }

  // ┌─ test_toUint144 ─────
  function test_toUint144(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint144).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint144).max);
    assertEq(wrapper.toUint144(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint144(overflowingX);
  }

  // ┌─ test_toUint152 ─────
  function test_toUint152(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint152).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint152).max);
    assertEq(wrapper.toUint152(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint152(overflowingX);
  }

  // ┌─ test_toUint160 ─────
  function test_toUint160(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint160).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint160).max);
    assertEq(wrapper.toUint160(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint160(overflowingX);
  }

  // ┌─ test_toUint168 ─────
  function test_toUint168(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint168).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint168).max);
    assertEq(wrapper.toUint168(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint168(overflowingX);
  }

  // ┌─ test_toUint176 ─────
  function test_toUint176(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint176).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint176).max);
    assertEq(wrapper.toUint176(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint176(overflowingX);
  }

  // ┌─ test_toUint184 ─────
  function test_toUint184(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint184).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint184).max);
    assertEq(wrapper.toUint184(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint184(overflowingX);
  }

  // ┌─ test_toUint192 ─────
  function test_toUint192(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint192).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint192).max);
    assertEq(wrapper.toUint192(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint192(overflowingX);
  }

  // ┌─ test_toUint200 ─────
  function test_toUint200(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint200).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint200).max);
    assertEq(wrapper.toUint200(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint200(overflowingX);
  }

  // ┌─ test_toUint208 ─────
  function test_toUint208(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint208).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint208).max);
    assertEq(wrapper.toUint208(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint208(overflowingX);
  }

  // ┌─ test_toUint216 ─────
  function test_toUint216(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint216).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint216).max);
    assertEq(wrapper.toUint216(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint216(overflowingX);
  }

  // ┌─ test_toUint224 ─────
  function test_toUint224(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint224).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint224).max);
    assertEq(wrapper.toUint224(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint224(overflowingX);
  }

  // ┌─ test_toUint232 ─────
  function test_toUint232(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint232).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint232).max);
    assertEq(wrapper.toUint232(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint232(overflowingX);
  }

  // ┌─ test_toUint240 ─────
  function test_toUint240(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint240).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint240).max);
    assertEq(wrapper.toUint240(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint240(overflowingX);
  }

  // ┌─ test_toUint248 ─────
  function test_toUint248(uint256 x) external {
    uint256 overflowingX = bound(x, uint256(type(uint248).max) + 1, type(uint256).max);
    x = bound(x, 0, type(uint248).max);
    assertEq(wrapper.toUint248(x), x);

    vm.expectRevert(ArithmeticError);
    wrapper.toUint248(overflowingX);
  }
}
