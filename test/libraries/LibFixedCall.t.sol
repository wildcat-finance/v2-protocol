// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import 'src/libraries/LibFixedCall.sol';
import 'src/interfaces/IWildcatArchController.sol';
import { TestKernel } from '../shared/TestKernel.sol';

import { IMarketApr } from 'src/access/types/PeriodicTermHookTypes.sol';

contract FixedCallReader {
  function referenceWord(address target) external view returns (uint256) {
    return IMarketApr(target).annualInterestBips();
  }

  function candidateWord(address target) external view returns (uint256) {
    return LibFixedCall.readWord(target, IMarketApr.annualInterestBips.selector);
  }

  function referenceBool(address target, uint256 rawArgument) external view returns (bool) {
    address argument;
    assembly {
      argument := rawArgument
    }
    return IWildcatArchController(target).isRegisteredBorrower(argument);
  }

  function candidateBool(address target, uint256 rawArgument) external view returns (bool) {
    address argument;
    assembly {
      argument := rawArgument
    }
    return LibFixedCall.readBool(target, IWildcatArchController.isRegisteredBorrower.selector, argument);
  }
}

contract FixedCallTarget {
  bytes internal _response;
  bool internal _revert;
  bytes32 internal _expectedCalldata;

  function configure(bytes memory response, bool shouldRevert, bytes32 expectedCalldata) external {
    _response = response;
    _revert = shouldRevert;
    _expectedCalldata = expectedCalldata;
  }

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

contract LibFixedCallTest is TestKernel {
  FixedCallReader internal reader;
  FixedCallTarget internal target;

  function setUp() external {
    reader = FixedCallReader(_deployCode('test/libraries/LibFixedCall.t.sol:FixedCallReader'));
    target = FixedCallTarget(_deployCode('test/libraries/LibFixedCall.t.sol:FixedCallTarget'));
  }

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

  function testFuzz_boolMatchesSolidity(bytes memory response, bool shouldRevert, uint256 argument) external {
    _compare(response, shouldRevert, argument);
  }

  function testFuzz_boolValidWithTrailingData(bool value, bytes memory trailing, uint256 argument) external {
    _compare(bytes.concat(abi.encode(value), trailing), false, argument);
    assertEq(reader.candidateBool(address(target), argument), value);
  }

  function test_boolRejectsEveryShortLength() external {
    for (uint256 length; length < 32; ++length) {
      _compare(new bytes(length), false, 123);
    }
  }

  function testFuzz_boolRejectsDirtyWord(uint256 word) external {
    word = bound(word, 2, type(uint256).max);
    _compare(abi.encode(word), false, 123);
    (bool success,) = address(reader).staticcall(abi.encodeCall(FixedCallReader.candidateBool, (address(target), 123)));
    assertFalse(success);
  }

  function test_boolRejectsEmptyAccount() external {
    vm.expectRevert();
    reader.candidateBool(address(0x1234), 123);
    vm.expectRevert();
    reader.referenceBool(address(0x1234), 123);
  }

  function _compareWord(bytes memory response, bool shouldRevert) internal {
    target.configure(response, shouldRevert, keccak256(abi.encodeCall(IMarketApr.annualInterestBips, ())));
    (bool referenceSuccess, bytes memory referenceData) =
      address(reader).staticcall(abi.encodeCall(FixedCallReader.referenceWord, (address(target))));
    (bool candidateSuccess, bytes memory candidateData) =
      address(reader).staticcall(abi.encodeCall(FixedCallReader.candidateWord, (address(target))));
    assertEq(candidateSuccess, referenceSuccess);
    assertEq(candidateData, referenceData);
  }

  function testFuzz_wordMatchesSolidity(bytes memory response, bool shouldRevert) external {
    _compareWord(response, shouldRevert);
  }

  function testFuzz_wordValidWithTrailingData(uint256 value, bytes memory trailing) external {
    _compareWord(bytes.concat(abi.encode(value), trailing), false);
    assertEq(reader.candidateWord(address(target)), value);
  }

  function test_wordRejectsEveryShortLength() external {
    for (uint256 length; length < 32; ++length) {
      _compareWord(new bytes(length), false);
    }
  }

  function testFuzz_wordPreservesFullWidth(uint256 word) external {
    word = bound(word, 65536, type(uint256).max);
    _compareWord(abi.encode(word), false);
    assertEq(reader.candidateWord(address(target)), word);
  }

  function test_wordRejectsEmptyAccount() external {
    vm.expectRevert();
    reader.candidateWord(address(0x1234));
    vm.expectRevert();
    reader.referenceWord(address(0x1234));
  }
}
