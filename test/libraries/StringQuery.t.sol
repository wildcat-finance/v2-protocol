// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import 'src/libraries/StringQuery.sol';
import 'src/libraries/LibERC20.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract Bytes32Metadata {
  bytes32 public constant name = 'TestA';
  bytes32 public constant symbol = 'TestA';
}

contract StringMetadata {
  string public name = 'TestB';
  string public symbol = 'TestB';
}

contract LongStrings {
  string public name =
    'Wow this is such a long name you would never expect this to be used in a real token';
  string public symbol =
    'The symbol too? what is going on here? surely this is far too long for a ticker';
}

contract BadStrings {
  bool giveRevertData;

  function setGiveRevertData(bool _giveRevertData) external {
    giveRevertData = _giveRevertData;
  }

  function name() external view {
    if (giveRevertData) {
      revert('name');
    } else {
      revert();
    }
  }

  function symbol() external view {
    if (giveRevertData) {
      revert('symbol');
    } else {
      revert();
    }
  }
}

contract MalformedStringMetadata {
  function name() external pure {
    assembly {
      mstore(0x00, 0x20)
      mstore(0x20, 33)
      mstore(0x40, '01234567890123456789012345678901')
      return(0x00, 0x60)
    }
  }

  function symbol() external pure {
    assembly {
      mstore(0x00, 0x40)
      mstore(0x20, 1)
      mstore(0x40, 'A')
      return(0x00, 0x60)
    }
  }
}

contract TrailingStringMetadata {
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

contract StringQueryTest is TestKernel {
  using LibERC20 for address;
  Bytes32Metadata internal bytes32Metadata;
  StringMetadata internal stringMetadata;
  LongStrings internal longStrings;
  BadStrings internal badStrings;
  MalformedStringMetadata internal malformedStringMetadata;
  TrailingStringMetadata internal trailingStringMetadata;

  function setUp() external {
    bytes32Metadata = Bytes32Metadata(
      _deployCode('test/libraries/StringQuery.t.sol:Bytes32Metadata')
    );
    stringMetadata = StringMetadata(
      _deployCode('test/libraries/StringQuery.t.sol:StringMetadata')
    );
    longStrings = LongStrings(_deployCode('test/libraries/StringQuery.t.sol:LongStrings'));
    badStrings = BadStrings(_deployCode('test/libraries/StringQuery.t.sol:BadStrings'));
    malformedStringMetadata = MalformedStringMetadata(
      _deployCode('test/libraries/StringQuery.t.sol:MalformedStringMetadata')
    );
    trailingStringMetadata = TrailingStringMetadata(
      _deployCode('test/libraries/StringQuery.t.sol:TrailingStringMetadata')
    );
  }

  function queryName(address token) external view returns (string memory) {
    return token.name();
  }

  function querySymbol(address token) external view returns (string memory) {
    return token.symbol();
  }

  function test_name() external {
    assertEq(address(bytes32Metadata).name(), 'TestA');
    assertEq(address(stringMetadata).name(), 'TestB');
    assertEq(
      address(longStrings).name(),
      'Wow this is such a long name you would never expect this to be used in a real token'
    );

    vm.expectRevert(LibERC20.NameFailed.selector);
    this.queryName(address(badStrings));

    badStrings.setGiveRevertData(true);
    vm.expectRevert(bytes('name'));
    this.queryName(address(badStrings));
  }

  function test_symbol() external {
    assertEq(address(bytes32Metadata).symbol(), 'TestA');
    assertEq(address(stringMetadata).symbol(), 'TestB');
    assertEq(
      address(longStrings).symbol(),
      'The symbol too? what is going on here? surely this is far too long for a ticker'
    );

    vm.expectRevert(LibERC20.SymbolFailed.selector);
    this.querySymbol(address(badStrings));

    badStrings.setGiveRevertData(true);
    vm.expectRevert(bytes('symbol'));
    this.querySymbol(address(badStrings));
  }

  function test_bytes32ToString_DoesNotDropHighBitFinalByte() external pure {
    bytes32 value = 0xc380000000000000000000000000000000000000000000000000000000000000;
    assertEq(bytes(bytes32ToString(value)), hex'c380');
  }

  function test_name_RejectsTruncatedDynamicString() external {
    vm.expectRevert(bytes4(0x4cb9c000));
    this.queryName(address(malformedStringMetadata));
  }

  function test_symbol_RejectsNonCanonicalDynamicStringOffset() external {
    vm.expectRevert(bytes4(0x4cb9c000));
    this.querySymbol(address(malformedStringMetadata));
  }

  function test_name_AcceptsTrailingReturnData() external view {
    assertEq(address(trailingStringMetadata).name(), 'A');
  }
}
