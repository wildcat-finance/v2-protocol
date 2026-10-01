// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // LibFixedCall.t
// ║  ██▀▀     ▀▀██   Bounded word and boolean staticcall equivalence tests.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  WORD READERS
// ║  referenceWord(...)
// ║  candidateWord(...)
// ║
// ║  BOOLEAN READERS
// ║  referenceBool(...)
// ║  candidateBool(...)
// ║
// ║  CONFIGURABLE RESPONSES
// ║  configure(...)
// ║  fallback()
// ║
// ║  FIXTURE
// ║  setUp()
// ║
// ║  BOOLEAN RESPONSES
// ║  testFuzz_boolMatchesSolidity(...)
// ║  testFuzz_boolValidWithTrailingData(...)
// ║  test_boolRejectsEveryShortLength()
// ║  testFuzz_boolRejectsDirtyWord(...)
// ║  test_boolRejectsEmptyAccount()
// ║  _compare(...)
// ║
// ║  WORD RESPONSES
// ║  testFuzz_wordMatchesSolidity(...)
// ║  testFuzz_wordValidWithTrailingData(...)
// ║  test_wordRejectsEveryShortLength()
// ║  testFuzz_wordPreservesFullWidth(...)
// ║  test_wordRejectsEmptyAccount()
// ║  _compareWord(...)
// ╚═════

import 'src/libraries/LibFixedCall.sol';
import 'src/interfaces/IWildcatArchController.sol';
import { TestKernel } from '../shared/TestKernel.sol';

import { IMarketApr } from 'src/access/types/PeriodicTermHookTypes.sol';

// ┌─ FixedCallReader ──────────────────────────────────────────────────────────
contract FixedCallReader {
  // ░░▒▒▓▓██ [ WORD READERS ] ─────────────────────────────────────────────────

  // ┌─ referenceWord ─────
  function referenceWord(address target) external view returns (uint256) {
    return IMarketApr(target).annualInterestBips();
  }

  // ┌─ candidateWord ─────
  function candidateWord(address target) external view returns (uint256) {
    return LibFixedCall.readWord(target, IMarketApr.annualInterestBips.selector);
  }

  // ░░▒▒▓▓██ [ BOOLEAN READERS ] ──────────────────────────────────────────────

  // ┌─ referenceBool ─────
  function referenceBool(address target, uint256 rawArgument) external view returns (bool) {
    address argument;
    assembly {
      argument := rawArgument
    }
    return IWildcatArchController(target).isRegisteredBorrower(argument);
  }

  // ┌─ candidateBool ─────
  function candidateBool(address target, uint256 rawArgument) external view returns (bool) {
    address argument;
    assembly {
      argument := rawArgument
    }
    return LibFixedCall.readBool(target, IWildcatArchController.isRegisteredBorrower.selector, argument);
  }
}

// ┌─ FixedCallTarget ──────────────────────────────────────────────────────────
contract FixedCallTarget {
  bytes internal _response;
  bool internal _revert;
  bytes32 internal _expectedCalldata;

  // ░░▒▒▓▓██ [ CONFIGURABLE RESPONSES ] ───────────────────────────────────────

  // ┌─ configure ─────
  function configure(bytes memory response, bool shouldRevert, bytes32 expectedCalldata) external {
    _response = response;
    _revert = shouldRevert;
    _expectedCalldata = expectedCalldata;
  }

  // ┌─ fallback ─────
  fallback() external {
    require(keccak256(msg.data) == _expectedCalldata, 'wrong calldata');
    bytes memory response = _response;
    bool shouldRevert = _revert;
    assembly {
      if shouldRevert {
        revert(add(response, 0x20), mload(response))
      }
      return(add(response, 0x20), mload(response))
    }
  }
}

// ┌─ LibFixedCallTest ─────────────────────────────────────────────────────────
contract LibFixedCallTest is TestKernel {
  FixedCallReader internal reader;
  FixedCallTarget internal target;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    reader = FixedCallReader(_deployCode('test/libraries/LibFixedCall.t.sol:FixedCallReader'));
    target = FixedCallTarget(_deployCode('test/libraries/LibFixedCall.t.sol:FixedCallTarget'));
  }

  // ░░▒▒▓▓██ [ BOOLEAN RESPONSES ] ────────────────────────────────────────────

  // ┌─ testFuzz_boolMatchesSolidity ─────
  function testFuzz_boolMatchesSolidity(bytes memory response, bool shouldRevert, uint256 argument) external {
    _compare(response, shouldRevert, argument);
  }

  // ┌─ testFuzz_boolValidWithTrailingData ─────
  function testFuzz_boolValidWithTrailingData(bool value, bytes memory trailing, uint256 argument) external {
    _compare(bytes.concat(abi.encode(value), trailing), false, argument);
    assertEq(reader.candidateBool(address(target), argument), value);
  }

  // ┌─ test_boolRejectsEveryShortLength ─────
  function test_boolRejectsEveryShortLength() external {
    for (uint256 length; length < 32; ++length) {
      _compare(new bytes(length), false, 123);
    }
  }

  // ┌─ testFuzz_boolRejectsDirtyWord ─────
  function testFuzz_boolRejectsDirtyWord(uint256 word) external {
    word = bound(word, 2, type(uint256).max);
    _compare(abi.encode(word), false, 123);
    (bool success,) = address(reader).staticcall(abi.encodeCall(FixedCallReader.candidateBool, (address(target), 123)));
    assertFalse(success);
  }

  // ┌─ test_boolRejectsEmptyAccount ─────
  function test_boolRejectsEmptyAccount() external {
    vm.expectRevert();
    reader.candidateBool(address(0x1234), 123);
    vm.expectRevert();
    reader.referenceBool(address(0x1234), 123);
  }

  // ┌─ _compare ─────
  function _compare(bytes memory response, bool shouldRevert, uint256 rawArgument) internal {
    target.configure(
      response,
      shouldRevert,
      keccak256(abi.encodeCall(IWildcatArchController.isRegisteredBorrower, (address(uint160(rawArgument)))))
    );
    (bool referenceSuccess, bytes memory referenceData) =
      address(reader).staticcall(abi.encodeCall(FixedCallReader.referenceBool, (address(target), rawArgument)));
    (bool candidateSuccess, bytes memory candidateData) =
      address(reader).staticcall(abi.encodeCall(FixedCallReader.candidateBool, (address(target), rawArgument)));
    assertEq(candidateSuccess, referenceSuccess);
    assertEq(candidateData, referenceData);
  }

  // ░░▒▒▓▓██ [ WORD RESPONSES ] ───────────────────────────────────────────────

  // ┌─ testFuzz_wordMatchesSolidity ─────
  function testFuzz_wordMatchesSolidity(bytes memory response, bool shouldRevert) external {
    _compareWord(response, shouldRevert);
  }

  // ┌─ testFuzz_wordValidWithTrailingData ─────
  function testFuzz_wordValidWithTrailingData(uint256 value, bytes memory trailing) external {
    _compareWord(bytes.concat(abi.encode(value), trailing), false);
    assertEq(reader.candidateWord(address(target)), value);
  }

  // ┌─ test_wordRejectsEveryShortLength ─────
  function test_wordRejectsEveryShortLength() external {
    for (uint256 length; length < 32; ++length) {
      _compareWord(new bytes(length), false);
    }
  }

  // ┌─ testFuzz_wordPreservesFullWidth ─────
  function testFuzz_wordPreservesFullWidth(uint256 word) external {
    word = bound(word, 65536, type(uint256).max);
    _compareWord(abi.encode(word), false);
    assertEq(reader.candidateWord(address(target)), word);
  }

  // ┌─ test_wordRejectsEmptyAccount ─────
  function test_wordRejectsEmptyAccount() external {
    vm.expectRevert();
    reader.candidateWord(address(0x1234));
    vm.expectRevert();
    reader.referenceWord(address(0x1234));
  }

  // ┌─ _compareWord ─────
  function _compareWord(bytes memory response, bool shouldRevert) internal {
    target.configure(response, shouldRevert, keccak256(abi.encodeCall(IMarketApr.annualInterestBips, ())));
    (bool referenceSuccess, bytes memory referenceData) =
      address(reader).staticcall(abi.encodeCall(FixedCallReader.referenceWord, (address(target))));
    (bool candidateSuccess, bytes memory candidateData) =
      address(reader).staticcall(abi.encodeCall(FixedCallReader.candidateWord, (address(target))));
    assertEq(candidateSuccess, referenceSuccess);
    assertEq(candidateData, referenceData);
  }
}
