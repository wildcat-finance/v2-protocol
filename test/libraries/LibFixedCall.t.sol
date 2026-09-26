// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import 'src/libraries/LibFixedCall.sol';
import 'src/interfaces/IWildcatArchController.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract FixedCallReader {
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
    return
      LibFixedCall.readBool(target, IWildcatArchController.isRegisteredBorrower.selector, argument);
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
      keccak256(
        abi.encodeCall(IWildcatArchController.isRegisteredBorrower, (address(uint160(rawArgument))))
      )
    );
    (bool referenceSuccess, bytes memory referenceData) = address(reader).staticcall(
      abi.encodeCall(FixedCallReader.referenceBool, (address(target), rawArgument))
    );
    (bool candidateSuccess, bytes memory candidateData) = address(reader).staticcall(
      abi.encodeCall(FixedCallReader.candidateBool, (address(target), rawArgument))
    );
    assertEq(candidateSuccess, referenceSuccess);
    assertEq(candidateData, referenceData);
  }

  function testFuzz_boolMatchesSolidity(
    bytes memory response,
    bool shouldRevert,
    uint256 argument
  ) external {
    _compare(response, shouldRevert, argument);
  }

  function testFuzz_boolValidWithTrailingData(
    bool value,
    bytes memory trailing,
    uint256 argument
  ) external {
    _compare(bytes.concat(abi.encode(value), trailing), false, argument);
    assertEq(reader.candidateBool(address(target), argument), value);
  }

  function test_boolRejectsEveryShortLength() external {
    for (uint256 length; length < 32; ++length) _compare(new bytes(length), false, 123);
  }

  function testFuzz_boolRejectsDirtyWord(uint256 word) external {
    word = bound(word, 2, type(uint256).max);
    _compare(abi.encode(word), false, 123);
    (bool success, ) = address(reader).staticcall(
      abi.encodeCall(FixedCallReader.candidateBool, (address(target), 123))
    );
    assertFalse(success);
  }

  function test_boolRejectsEmptyAccount() external {
    vm.expectRevert();
    reader.candidateBool(address(0x1234), 123);
    vm.expectRevert();
    reader.referenceBool(address(0x1234), 123);
  }
}
