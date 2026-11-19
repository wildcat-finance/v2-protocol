// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // StringQuery.t
//  \ ^ /   Strict and best-effort string metadata boundary tests.
//    V
//
//  FAILED STRING RESPONSES
//  setGiveRevertData(...)
//  name()
//  symbol()
//
//  MALFORMED STRING RESPONSES
//  name()
//  symbol()
//
//  TRAILING STRING RESPONSES
//  name()
//
//  FIXTURE
//  setUp()
//
//  STRICT METADATA READS
//  test_name()
//  test_symbol()
//  test_bytes32ToString_DoesNotDropHighBitFinalByte()
//  test_name_RejectsTruncatedDynamicString()
//  test_symbol_RejectsNonCanonicalDynamicStringOffset()
//  test_name_AcceptsTrailingReturnData()
//  queryName(...)
//  querySymbol(...)
//
//  BEST EFFORT METADATA
//  testFuzz_bestEffort_ArbitraryReturnDataPreservesLaterReads(...)
//  test_emptyDynamicStrings_AcceptCanonicalEncoding()
//  test_emptyDynamicHeader_RejectsNonzeroLengthAndWrongOffset()
//  test_bestEffort_FailedMissingAndOversizedResponsesAreEmpty()
//  test_bestEffort_AcceptsLegacyAndTrailingData()
//  testFuzz_dynamicStrings_RoundTripWithinCosmeticBound(...)
//  test_bestEffort_TextLengthBoundaries()
//  queryNameOrEmpty(...)
//  queryNamesOrEmpty(...)
// ═════

import 'src/libraries/StringQuery.sol';
import 'src/libraries/LibERC20.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// ┌─ Bytes32Metadata ──────────────────────────────────────────────────────────
contract Bytes32Metadata {
  bytes32 public constant name = 'TestA';
  bytes32 public constant symbol = 'TestA';
}

// ┌─ StringMetadata ───────────────────────────────────────────────────────────
contract StringMetadata {
  string public name = 'TestB';
  string public symbol = 'TestB';
}

// ┌─ LongStrings ──────────────────────────────────────────────────────────────
contract LongStrings {
  string public name = 'Wow this is such a long name you would never expect this to be used in a real token';
  string public symbol = 'The symbol too? what is going on here? surely this is far too long for a ticker';
}

// ┌─ BadStrings ───────────────────────────────────────────────────────────────
contract BadStrings {
  bool giveRevertData;

  // ░░▒▒▓▓██ [ FAILED STRING RESPONSES ] ──────────────────────────────────────

  // ┌─ setGiveRevertData ─────
  function setGiveRevertData(bool _giveRevertData) external {
    giveRevertData = _giveRevertData;
  }

  // ┌─ name ─────
  function name() external view {
    if (giveRevertData) {
      revert('name');
    } else {
      revert();
    }
  }

  // ┌─ symbol ─────
  function symbol() external view {
    if (giveRevertData) {
      revert('symbol');
    } else {
      revert();
    }
  }
}

// ┌─ MalformedStringMetadata ──────────────────────────────────────────────────
contract MalformedStringMetadata {
  // ░░▒▒▓▓██ [ MALFORMED STRING RESPONSES ] ───────────────────────────────────

  // ┌─ name ─────
  function name() external pure {
    assembly {
      mstore(0x00, 0x20)
      mstore(0x20, 33)
      mstore(0x40, '01234567890123456789012345678901')
      return(0x00, 0x60)
    }
  }

  // ┌─ symbol ─────
  function symbol() external pure {
    assembly {
      mstore(0x00, 0x40)
      mstore(0x20, 1)
      mstore(0x40, 'A')
      return(0x00, 0x60)
    }
  }
}

// ┌─ TrailingStringMetadata ───────────────────────────────────────────────────
contract TrailingStringMetadata {
  // ░░▒▒▓▓██ [ TRAILING STRING RESPONSES ] ────────────────────────────────────

  // ┌─ name ─────
  function name() external pure {
    assembly {
      mstore(0x00, 0x20)
      mstore(0x20, 1)
      mstore(0x40, shl(248, 0x41))
      mstore(0x60, 0xdeadbeef)
      return(0x00, 0x80)
    }
  }
}

// ┌─ StringQueryTest ──────────────────────────────────────────────────────────
contract StringQueryTest is TestKernel {
  using LibERC20 for address;
  Bytes32Metadata internal bytes32Metadata;
  StringMetadata internal stringMetadata;
  LongStrings internal longStrings;
  BadStrings internal badStrings;
  MalformedStringMetadata internal malformedStringMetadata;
  TrailingStringMetadata internal trailingStringMetadata;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    bytes32Metadata = Bytes32Metadata(_deployCode('test/libraries/StringQuery.t.sol:Bytes32Metadata'));
    stringMetadata = StringMetadata(_deployCode('test/libraries/StringQuery.t.sol:StringMetadata'));
    longStrings = LongStrings(_deployCode('test/libraries/StringQuery.t.sol:LongStrings'));
    badStrings = BadStrings(_deployCode('test/libraries/StringQuery.t.sol:BadStrings'));
    malformedStringMetadata =
      MalformedStringMetadata(_deployCode('test/libraries/StringQuery.t.sol:MalformedStringMetadata'));
    trailingStringMetadata =
      TrailingStringMetadata(_deployCode('test/libraries/StringQuery.t.sol:TrailingStringMetadata'));
  }

  // ░░▒▒▓▓██ [ STRICT METADATA READS ] ────────────────────────────────────────

  // ┌─ test_name ─────
  function test_name() external {
    assertEq(address(bytes32Metadata).name(), 'TestA');
    assertEq(address(stringMetadata).name(), 'TestB');
    assertEq(
      address(longStrings).name(), 'Wow this is such a long name you would never expect this to be used in a real token'
    );

    vm.expectRevert(LibERC20.NameFailed.selector);
    this.queryName(address(badStrings));

    badStrings.setGiveRevertData(true);
    vm.expectRevert(bytes('name'));
    this.queryName(address(badStrings));
  }

  // ┌─ test_symbol ─────
  function test_symbol() external {
    assertEq(address(bytes32Metadata).symbol(), 'TestA');
    assertEq(address(stringMetadata).symbol(), 'TestB');
    assertEq(
      address(longStrings).symbol(), 'The symbol too? what is going on here? surely this is far too long for a ticker'
    );

    vm.expectRevert(LibERC20.SymbolFailed.selector);
    this.querySymbol(address(badStrings));

    badStrings.setGiveRevertData(true);
    vm.expectRevert(bytes('symbol'));
    this.querySymbol(address(badStrings));
  }

  // ┌─ test_bytes32ToString_DoesNotDropHighBitFinalByte ─────
  function test_bytes32ToString_DoesNotDropHighBitFinalByte() external pure {
    bytes32 value = 0xc380000000000000000000000000000000000000000000000000000000000000;
    assertEq(bytes(bytes32ToString(value)), hex'c380');
  }

  // ┌─ test_name_RejectsTruncatedDynamicString ─────
  function test_name_RejectsTruncatedDynamicString() external {
    vm.expectRevert(bytes4(0x4cb9c000));
    this.queryName(address(malformedStringMetadata));
  }

  // ┌─ test_symbol_RejectsNonCanonicalDynamicStringOffset ─────
  function test_symbol_RejectsNonCanonicalDynamicStringOffset() external {
    vm.expectRevert(bytes4(0x4cb9c000));
    this.querySymbol(address(malformedStringMetadata));
  }

  // ┌─ test_name_AcceptsTrailingReturnData ─────
  function test_name_AcceptsTrailingReturnData() external view {
    assertEq(address(trailingStringMetadata).name(), 'A');
  }

  // ┌─ queryName ─────
  function queryName(address token) external view returns (string memory) {
    return token.name();
  }

  // ┌─ querySymbol ─────
  function querySymbol(address token) external view returns (string memory) {
    return token.symbol();
  }

  // ░░▒▒▓▓██ [ BEST EFFORT METADATA ] ─────────────────────────────────────────

  // ┌─ testFuzz_bestEffort_ArbitraryReturnDataPreservesLaterReads ─────
  function testFuzz_bestEffort_ArbitraryReturnDataPreservesLaterReads(bytes memory response) external {
    vm.mockCall(address(bytes32Metadata), abi.encodeWithSignature('name()'), response);
    (bytes32 firstHash, string memory first, string memory second) =
      this.queryNamesOrEmpty(address(bytes32Metadata), address(stringMetadata));
    assertTrue(bytes(first).length <= 256, 'arbitrary returndata cannot escape text bound');
    assertEq(uint256(keccak256(bytes(first))), uint256(firstHash), 'later read preserves prior allocation');
    assertEq(second, 'TestB', 'malformed or missing first label does not corrupt later metadata');
  }

  // ┌─ test_emptyDynamicStrings_AcceptCanonicalEncoding ─────
  function test_emptyDynamicStrings_AcceptCanonicalEncoding() external {
    vm.mockCall(address(stringMetadata), abi.encodeWithSignature('name()'), abi.encode(''));
    vm.mockCall(address(stringMetadata), abi.encodeWithSignature('symbol()'), abi.encode(''));
    assertEq(this.queryName(address(stringMetadata)), '');
    assertEq(this.querySymbol(address(stringMetadata)), '');
    assertEq(this.queryNameOrEmpty(address(stringMetadata)), '');
  }

  // ┌─ test_emptyDynamicHeader_RejectsNonzeroLengthAndWrongOffset ─────
  function test_emptyDynamicHeader_RejectsNonzeroLengthAndWrongOffset() external {
    bytes memory selector = abi.encodeWithSignature('name()');
    bytes[] memory malformed = new bytes[](3);
    malformed[0] = abi.encode(uint256(32), uint256(1));
    malformed[1] = abi.encode(uint256(64), uint256(0));
    malformed[2] = abi.encode(uint256(32), type(uint256).max);
    for (uint256 i; i < malformed.length; i++) {
      vm.mockCall(address(stringMetadata), selector, malformed[i]);
      vm.expectRevert(bytes4(0x4cb9c000));
      this.queryName(address(stringMetadata));
      assertEq(this.queryNameOrEmpty(address(stringMetadata)), '', 'malformed fallback');
    }
  }

  // ┌─ test_bestEffort_FailedMissingAndOversizedResponsesAreEmpty ─────
  function test_bestEffort_FailedMissingAndOversizedResponsesAreEmpty() external {
    assertEq(this.queryNameOrEmpty(address(badStrings)), '', 'revert without data');
    badStrings.setGiveRevertData(true);
    assertEq(this.queryNameOrEmpty(address(badStrings)), '', 'revert with data');
    assertEq(this.queryNameOrEmpty(address(0xDEAD)), '', 'no code');
    assertEq(this.queryNameOrEmpty(address(malformedStringMetadata)), '', 'truncated data');

    bytes memory oversized = new bytes(321);
    vm.mockCall(address(stringMetadata), abi.encodeWithSignature('name()'), oversized);
    assertEq(this.queryNameOrEmpty(address(stringMetadata)), '', 'response bound');
    vm.mockCall(address(stringMetadata), abi.encodeWithSignature('name()'), hex'41');
    assertEq(this.queryNameOrEmpty(address(stringMetadata)), '', 'short response');
    vm.mockCallRevert(address(stringMetadata), abi.encodeWithSignature('name()'), new bytes(4096));
    assertEq(this.queryNameOrEmpty(address(stringMetadata)), '', 'large revert is not copied');
  }

  // ┌─ test_bestEffort_AcceptsLegacyAndTrailingData ─────
  function test_bestEffort_AcceptsLegacyAndTrailingData() external view {
    assertEq(this.queryNameOrEmpty(address(bytes32Metadata)), 'TestA');
    assertEq(this.queryNameOrEmpty(address(trailingStringMetadata)), 'A');
  }

  // ┌─ testFuzz_dynamicStrings_RoundTripWithinCosmeticBound ─────
  function testFuzz_dynamicStrings_RoundTripWithinCosmeticBound(bytes memory value) external {
    if (value.length > 512) return;
    vm.mockCall(address(stringMetadata), abi.encodeWithSignature('name()'), abi.encode(string(value)));
    assertEq(bytes(this.queryName(address(stringMetadata))), value, 'strict bytes round-trip');
    if (value.length <= 256) {
      assertEq(bytes(this.queryNameOrEmpty(address(stringMetadata))), value, 'cosmetic bytes round-trip');
    } else {
      assertEq(this.queryNameOrEmpty(address(stringMetadata)), '', 'text bound');
    }
  }

  // ┌─ test_bestEffort_TextLengthBoundaries ─────
  function test_bestEffort_TextLengthBoundaries() external {
    uint256[8] memory lengths = [uint256(0), 1, 31, 32, 33, 255, 256, 257];
    for (uint256 i; i < lengths.length; i++) {
      bytes memory value = new bytes(lengths[i]);
      for (uint256 j; j < value.length; j++) {
        value[j] = 'x';
      }
      vm.mockCall(address(stringMetadata), abi.encodeWithSignature('name()'), abi.encode(string(value)));
      if (value.length <= 256) {
        assertEq(bytes(this.queryNameOrEmpty(address(stringMetadata))), value);
      } else {
        assertEq(this.queryNameOrEmpty(address(stringMetadata)), '');
      }
    }
  }

  // ┌─ queryNameOrEmpty ─────
  function queryNameOrEmpty(address token) external view returns (string memory) {
    return queryStringOrBytes32AsStringOrEmpty(token, 0x06fdde03);
  }

  // ┌─ queryNamesOrEmpty ─────
  function queryNamesOrEmpty(
    address firstToken,
    address secondToken
  )
    external
    view
    returns (bytes32 firstHash, string memory first, string memory second)
  {
    first = queryStringOrBytes32AsStringOrEmpty(firstToken, 0x06fdde03);
    firstHash = keccak256(bytes(first));
    second = queryStringOrBytes32AsStringOrEmpty(secondToken, 0x06fdde03);
  }
}
