// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // Test12
// ║  ██▀▀     ▀▀██   Legacy JSON, transient-storage, and script experiments.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  TRANSIENT JSON VALUES
// ║  reserveTSlot()
// ║  jsonValueToString(...)
// ║
// ║  TRANSIENT ALLOCATION
// ║  next()
// ║
// ║  SCRIPT EXPERIMENTS
// ║  run()
// ║  internalFunction()
// ║
// ║  ENVIRONMENT CHECKS
// ║  checkFfiEnabled()
// ║  isFfiEnabled()
// ║  checkDirectoryExistsAndAccessible(...)
// ║  checkDirectoryAccess(...)
// ║
// ║  PATHS
// ║  pathJoin(...)
// ║  join(...)
// ║
// ║  COMPILER INPUT
// ║  writeStandardJson(...)
// ║  checkForBashFile()
// ║
// ║  COMPOSITE VALUES
// ║  serializeObject(...)
// ║  serializeArray(...)
// ║
// ║  SCALAR VALUES
// ║  serializeBool(...)
// ║  serializeUint256(...)
// ║  serializeInt256(...)
// ║  toHexString(...)
// ║  serializeAddress(...)
// ║  serializeBytes32(...)
// ║  serializeBytes(...)
// ║  serializeString(...)
// ║
// ║  TYPED ARRAYS
// ║  serializeBoolArray(...)
// ║  serializeUint256Array(...)
// ║  serializeInt256Array(...)
// ║  serializeAddressArray(...)
// ║  serializeBytes32Array(...)
// ║  serializeStringArray(...)
// ║
// ║  DECIMAL STRINGS
// ║  toString(...)
// ║  toString(...)
// ║
// ║  HEXADECIMAL STRINGS
// ║  toHexString(...)
// ║  toHexString(...)
// ║  toHexString(...)
// ║  toHexStringNoPrefix(...)
// ║  toHexStringNoPrefix(...)
// ║  toHexStringNoPrefix(...)
// ╚═════

import 'src/WildcatSanctionsSentinel.sol';
import 'src/WildcatArchController.sol';
import 'forge-std/Script.sol';
import 'forge-std/Vm.sol';

type Json is uint;
using JsonLib for Json global;
/*
Json objects:
key[]
key => { index, mPointer }
removeKey (key) {
  index = keysMap[key].index

}

Types:
- Hex String (address, bytes<n>, bytes)
- Number (small/big, int/uint)
- Array
- Object
- Null
- Bool

- null, bool, uint, int, string, hex_string, array, object

3 bits for type:

Type      | Value
Null      | 000
Bool      | 001
Uint      | 010
Int       | 011
String    | 100
HexString | 101
Array     | 110
Object    | 111

with additional bit for whether it's a pointer, only
applying to String, HexString, Array, Object, Uint, Int

BigUint   | 0101
BigInt    | 0111
BigString | 1001
BigBytes  | 1011

All types have two components:
[0:4] Type information - type ID and whether the value is contained in the word
[4:256] Value information - either a packed form of the value or a reference to it

JsonType always stored in memory.
For an array, the memory value tracks the length and a transient pointer to the data section.
Then the data section is a packed array of 32 bit memory pointer of elements.

function get(JsonArray array, uint index) view returns (uint mPointerElement) {
  assembly {
    let tPointerArray := shr(144, shl(20, array))
    // Elements are stored in groups of 8, and written right to left in the chunk
    let tPointerSiblings := add(tPointerArray, div(index, 8))
    let siblings := tload(tPointerSiblings)
    let offsetFromRight := shl(5, mod(index, 8))
    mPointerElement := and(0xffffffff, shr(offsetFromRight, siblings))
  }
}

function push(JsonArray array, uint mPointerElement) {
  assembly {
    // Read the array length
    let index := shr(240, shl(4, array))
    let tPointerArray := shr(144, shl(20, array))
    // Elements are stored in groups of 8, and written right to left in the chunk
    let tPointerSiblings := add(tPointerArray, div(index, 8))
    let siblings := tload(tPointerSiblings)
    let offsetFromRight := shl(5, mod(index, 8))
    let newSiblings := or(shl(offsetFromRight, mPointerElement), siblings)
    tstore(tPointerSiblings, newSiblings)
    index := add(index, 1)
  }
}

// -------------------------------- JsonArray -------------------------------- //
[0:4]     | 1100          |
[4:36]    | mPointerSelf  | Memory pointer to the array object itself (for updates)
[36:148]  | tPointerData  | Position of data section of array (first element)
[148:164] | Array length  |

For an array at transient storage location tPointerArray:
`tPointerData` is initialized to the first 112 bits of the hash of `tPointerArray`; however,
it does not necessarily always keep this value, especially if the array itself is moved to
a new position in transient storage
Every subsequent element at index `i` is stored at `tPointerData + i`

To add an element:
1. Get `tPointerElement = tPointerData + length`
2. Increment `length`
3. Store the element at `tPointerElement`

To remove an element at index `i`:
1. If `i == length - 1`:
  a. Decrement `length`
2. Otherwise:
  a. Get `tPointerLast = tPointerData + length - 1`
  b. Get `tPointerElement = tPointerData + i`
  c. Copy `tPointerLast` to `tPointerElement`
  d.

For arrays, the next 16 bits are used to store the length of the array,
and the remainder
*/

uint256 constant FreeTransientSlot = 0x40;

enum JsonType {
  Null,
  Bool,
  SmallUint,
  BigUint,
  SmallInt,
  BigInt,
  String,
  FixedBytes,
  Bytes,
  Object,
  Array
}

struct JsonValue {
  JsonType t;
  uint index;
  uint mPointer;
}

// ░░▒▒▓▓██ [ TRANSIENT JSON VALUES ] ──────────────────────────────────────────

// ┌─ reserveTSlot ─────
function reserveTSlot() returns (uint256 slot) {
  assembly {
    slot := tload(FreeTransientSlot)
    tstore(FreeTransientSlot, add(slot, 1))
    mstore(0, slot)
    slot := keccak256(0, 32)
  }
}

// ┌─ jsonValueToString ─────
function jsonValueToString(Json value) view returns (string memory str) {
  JsonType _type;
  assembly {
    _type := shr(248, value)
  }
  if (_type == JsonType.Null) {
    assembly {
      str := mload(0x40)
      mstore(0x40, add(str, 0x40))
      calldatacopy(str, calldatasize(), 0x40)
      // ABI string: length 4 followed by "null".
      mstore(str, 0x046e756c6c)
    }
    return str;
  }
  if (_type == JsonType.Bool) {
    assembly {
      str := mload(0x40)
      mstore(0x40, add(str, 0x40))
      calldatacopy(str, calldatasize(), 0x40)
      let isTrue := and(value, 0x01)
      switch isTrue
      case 1 {
        // ABI string: length 4 followed by "true".
        mstore(add(str, 4), 0x0474727565)
      }
      default {
        // ABI string: length 5 followed by "false".
        mstore(add(str, 5), 0x0566616c7365)
      }
    }
    return str;
  }
  if (_type == JsonType.SmallUint) {
    uint num;
    assembly {
      // strip the type tag from the top byte.
      num := shr(8, shl(8, value))
    }
    return LibJson.serializeUint256(num);
  }
  if (_type == JsonType.BigUint) {
    uint num;
    assembly {
      // the low four bytes identify the transient storage slot.
      let tSlot := and(value, 0xffffffff)
      num := tload(tSlot)
    }
    return LibJson.serializeUint256(num);
  }
  if (_type == JsonType.SmallInt) {
    int num;
    assembly {
      num := shr(8, shl(8, value))
      num := signextend(30, num)
    }
    return LibJson.serializeInt256(num);
  }
  if (_type == JsonType.BigInt) {
    int num;
    assembly {
      // the low four bytes identify the transient storage slot.
      let tSlot := and(value, 0xffffffff)
      num := tload(tSlot)
    }
    return LibJson.serializeInt256(num);
  }
}

// ┌─ JsonLib ──────────────────────────────────────────────────────────────────
library JsonLib {
  uint internal constant TSLOT_NEXT_INDEX = uint256(keccak256('Transient:TmpMarketParametersStorage')) - 1;

  // ░░▒▒▓▓██ [ TRANSIENT ALLOCATION ] ─────────────────────────────────────────

  // ┌─ next ─────
  function next() internal returns (Json nextObj) {
    uint t = TSLOT_NEXT_INDEX;
    assembly {
      nextObj := tload(t)
      tstore(t, add(nextObj, 1))
    }
  }
}

Vm constant forgeVm = Vm(address(uint160(uint256(keccak256('hevm cheat code')))));

// ┌─ Test12 ───────────────────────────────────────────────────────────────────
contract Test12 is Script {
  // ░░▒▒▓▓██ [ SCRIPT EXPERIMENTS ] ───────────────────────────────────────────

  // ┌─ run ─────
  function run() external {
    // checkFfiEnabled();
    checkDirectoryExistsAndAccessible('deployments');
    // checkDirectoryAccess('deployments');
    // uint32 _selector = uint32(Test12.internalFunction.selector);
    // bool result;
    // assembly {
    //   mstore(0, _selector)
    //   result := call(gas(), address(), 0, 0x1c, 0x04, 0, 0)
    // }
    // console2.log('result: ', result);
    // console2.logBytes32(bytes32(bytes4(_selector)));
    // console2.log('ffi enabled: ', isFfiEnabled());
  }

  // ┌─ internalFunction ─────
  function internalFunction() external {
    string[] memory args = new string[](4);
    args[0] = 'forge';
    args[1] = 'config';
    args[2] = '--basic';
    args[3] = '--json';
    string memory contractPath = 'src/HooksFactory.sol:HooksFactory';

    string memory result = string(vm.ffi(args));
    // console2.log("Result: ", result);
    // string memory result;
    // assembly
    string memory out = vm.parseJsonString(result, '.out');
    console2.log('OUT DIR: ', out);
    StandardInputJson.writeStandardJson(contractPath);
    // string memory _default = "default";
    // string memory foundryProfile = vm.envOr("FOUNDRY_PROFILE", _default);
    // console2.log("FOUNDRY_PROFILE: ", foundryProfile);
    // console2.log('Exit code: ', result.exitCode);
  }

  // ░░▒▒▓▓██ [ ENVIRONMENT CHECKS ] ───────────────────────────────────────────

  // ┌─ checkFfiEnabled ─────
  function checkFfiEnabled() internal {
    if (!isFfiEnabled()) {
      revert('Please enable FFI in foundry.toml with "ffi=true" to use the Deployments library.');
    }
  }

  // ┌─ isFfiEnabled ─────
  function isFfiEnabled() internal returns (bool result) {
    string[] memory args = new string[](2);
    args[0] = 'echo';
    args[1] = 'ok';
    bytes memory cd = abi.encodeWithSelector(VmSafe.ffi.selector, args);
    bytes32 expectedResponse = 'ok';
    address vmAddress = address(forgeVm);
    assembly {
      if call(gas(), vmAddress, 0, add(cd, 0x20), mload(cd), 0, 0) {
        returndatacopy(0, 0x40, 0x20)
        result := eq(mload(0), expectedResponse)
      }
    }
  }

  // ┌─ checkDirectoryExistsAndAccessible ─────
  function checkDirectoryExistsAndAccessible(string memory dir) internal {
    string memory readErrorMessage = string.concat(
      'The Deployments library requires access to the `',
      dir,
      '` directory.',
      ' Please grant read-write permission for `',
      dir,
      '` in foundry.toml.'
    );
    string memory writeErrorMessage = string.concat(
      'The Deployments library requires access to the `',
      dir,
      '` directory.',
      ' The current configuration only allows read access.',
      ' Please grant read-write permission for `',
      dir,
      '` in foundry.toml.'
    );
    bool dirExists;
    try vm.exists(dir) returns (bool exists) {
      dirExists = exists;
    } catch {
      revert(readErrorMessage);
    }
    if (!dirExists) {
      try vm.createDir(dir, true) {
        console.log(string.concat('Created directory: ', dir));
      } catch {
        revert(writeErrorMessage);
      }
    }
    try vm.writeFile(pathJoin(dir, 'test'), '') {
      vm.removeFile(pathJoin(dir, 'test'));
    } catch {
      revert(writeErrorMessage);
    }
  }

  // ┌─ checkDirectoryAccess ─────
  function checkDirectoryAccess(string memory filePath) internal {
    bytes memory cd = abi.encodeWithSelector(VmSafe.fsMetadata.selector, filePath);
    (bool success, bytes memory result) = address(forgeVm).staticcall(cd);
    if (!success) {
      revert('Failed to check directory access');
    }
    VmSafe.FsMetadata memory metadata = abi.decode(result, (VmSafe.FsMetadata));
    console.log('readOnly:', metadata.readOnly);
    // FsMetadata memory
  }
}
string constant bashFilePath = 'deployments/write-standard-json.sh';

// ░░▒▒▓▓██ [ PATHS ] ──────────────────────────────────────────────────────────

// ┌─ pathJoin ─────
function pathJoin(string memory a, string memory b) pure returns (string memory) {
  return join(a, b, '/');
}

// ┌─ join ─────
function join(string memory a, string memory b, string memory separator) pure returns (string memory) {
  if (bytes(a).length == 0) return b;
  if (bytes(b).length == 0) return a;
  return string.concat(a, separator, b);
}

// ┌─ StandardInputJson ────────────────────────────────────────────────────────
library StandardInputJson {
  // ░░▒▒▓▓██ [ COMPILER INPUT ] ───────────────────────────────────────────────

  // ┌─ writeStandardJson ─────
  function writeStandardJson(string memory namePath) internal {
    checkForBashFile();
    string[] memory args = new string[](4);
    args[0] = 'bash';
    args[1] = bashFilePath;
    args[2] = namePath;
    args[3] = pathJoin('deployments/test', 'standard-input.json');
    bytes memory result = forgeVm.ffi(args);
    bytes32 resultBytes;
    assembly {
      resultBytes := mload(add(result, 32))
    }
    if (resultBytes != 'ok') {
      if (result.length > 0) {
        console.logBytes('Output from bash script:');
        console.logBytes(result);
      }
      revert('Failed to write standard input json');
    }
    console.logBytes(result);
  }

  // ┌─ checkForBashFile ─────
  function checkForBashFile() internal {
    if (!forgeVm.exists(bashFilePath)) {
      string memory bashFile =
        'forge verify-contract --show-standard-json-input 0x0000000000000000000000000000000000000000 $1 > $2 && echo ok';
      forgeVm.writeFile(bashFilePath, bashFile);
      console.log(string.concat('Wrote bash file to ', bashFilePath));
    }
  }
}

// ┌─ LibJson ──────────────────────────────────────────────────────────────────
library LibJson {
  using LibJson for *;
  using LibStringStub for *;

  using LibJson for address;
  using LibJson for uint256;
  using LibJson for uint256[];

  // ░░▒▒▓▓██ [ COMPOSITE VALUES ] ─────────────────────────────────────────────

  // ┌─ serializeObject ─────
  function serializeObject(string[] memory keys, string[] memory values) internal pure returns (string memory output) {
    output = '{';
    uint256 lastIndex = keys.length - 1;
    for (uint256 i = 0; i < lastIndex; i++) {
      output = string.concat(output, '"', keys[i], '": ', values[i], ',');
    }
    output = string.concat(output, '"', keys[lastIndex], '":', values[lastIndex], '}');
  }

  // StringLiteral internal constant Comma = StringLiteral.wrap(0x012c000000000000000000000000000000000000000000000000000000000000);
  // StringLiteral internal constant Colon = StringLiteral.wrap(0x013a000000000000000000000000000000000000000000000000000000000000);
  // StringLiteral internal constant Quote = StringLiteral.wrap(0x0122000000000000000000000000000000000000000000000000000000000000);
  // ┌─ serializeArray ─────
  function serializeArray(
    uint256[] memory arr,
    function(uint256) pure returns /* element */ (string memory) serializeElement
  )
    internal
    pure
    returns (string memory output)
  {
    output = '[';
    uint256 lastIndex = arr.length - 1;
    for (uint256 i = 0; i < lastIndex; i++) {
      output = string.concat(output, serializeElement(arr[i]), ',');
    }
    output = string.concat(output, serializeElement(arr[lastIndex]), ']');
  }

  // ░░▒▒▓▓██ [ SCALAR VALUES ] ────────────────────────────────────────────────

  // ┌─ serializeBool ─────
  function serializeBool(bool value) internal pure returns (string memory) {
    return value ? 'true' : 'false';
  }

  // ┌─ serializeUint256 ─────
  function serializeUint256(uint256 value) internal pure returns (string memory) {
    // larger integers need strings to survive JavaScript's number precision.
    if (value > 9007199254740991) {
      return value.toHexString().serializeString();
    }
    return value.toString();
  }

  // ┌─ serializeInt256 ─────
  function serializeInt256(int256 value) internal pure returns (string memory) {
    // integers outside JavaScript's exact range need string encoding.
    if (value > 9007199254740991 || value < -9007199254740991) {
      return value.toHexString().serializeString();
    }
    return value.toString();
  }

  // ┌─ toHexString ─────
  function toHexString(int256 value) internal pure returns (string memory str) {
    if (value >= 0) {
      return uint256(value).toHexString();
    }
    unchecked {
      str = uint256(-value).toHexString();
    }
    /// @solidity memory-safe-assembly
    assembly {
      // the formatter leaves prefix room before the digits; reuse it for the minus sign.
      let length := mload(str)
      mstore(str, 0x2d) // '-'
      str := sub(str, 1)
      mstore(str, add(length, 1))
    }
  }

  // ┌─ serializeAddress ─────
  function serializeAddress(address value) internal pure returns (string memory) {
    return value.toHexString().serializeString();
  }

  // ┌─ serializeBytes32 ─────
  function serializeBytes32(bytes32 value) internal pure returns (string memory) {
    return uint256(value).toHexString().serializeString();
  }

  // ┌─ serializeBytes ─────
  function serializeBytes(bytes memory value) internal pure returns (string memory) {
    return value.toHexString().serializeString();
  }

  // ┌─ serializeString ─────
  function serializeString(string memory value) internal pure returns (string memory) {
    return string.concat('"', value, '"');
  }

  // ░░▒▒▓▓██ [ TYPED ARRAYS ] ─────────────────────────────────────────────────

  // ┌─ serializeBoolArray ─────
  function serializeBoolArray(bool[] memory arr) internal pure returns (string memory) {
    function(uint256[] memory, function(uint256) pure returns (string memory)) internal pure returns (string memory)
      _fn = serializeArray;
    function(bool[] memory, function(bool) pure returns (string memory)) internal pure returns (string memory) fn;
    assembly {
      fn := _fn
    }
    return fn(arr, serializeBool);
  }

  // ┌─ serializeUint256Array ─────
  function serializeUint256Array(uint256[] memory arr) internal pure returns (string memory) {
    return serializeArray(arr, serializeUint256);
  }

  // ┌─ serializeInt256Array ─────
  function serializeInt256Array(int256[] memory arr) internal pure returns (string memory) {
    function(uint256[] memory, function(uint256) pure returns (string memory)) internal pure returns (string memory)
      _fn = serializeArray;
    function(int256[] memory, function(int256) pure returns (string memory)) internal pure returns (string memory) fn;
    assembly {
      fn := _fn
    }
    return fn(arr, serializeInt256);
  }

  // ┌─ serializeAddressArray ─────
  function serializeAddressArray(address[] memory arr) internal pure returns (string memory) {
    function(uint256[] memory, function(uint256) pure returns (string memory)) internal pure returns (string memory)
      _fn = serializeArray;
    function(address[] memory, function(address) pure returns (string memory)) internal pure returns (string memory) fn;
    assembly {
      fn := _fn
    }
    return fn(arr, serializeAddress);
  }

  // ┌─ serializeBytes32Array ─────
  function serializeBytes32Array(bytes32[] memory arr) internal pure returns (string memory) {
    function(uint256[] memory, function(uint256) pure returns (string memory)) internal pure returns (string memory)
      _fn = serializeArray;
    function(bytes32[] memory, function(bytes32) pure returns (string memory)) internal pure returns (string memory) fn;
    assembly {
      fn := _fn
    }
    return fn(arr, serializeBytes32);
  }

  // ┌─ serializeStringArray ─────
  function serializeStringArray(string[] memory arr) internal pure returns (string memory) {
    function(uint256[] memory, function(uint256) pure returns (string memory)) internal pure returns (string memory)
      _fn = serializeArray;
    function(string[] memory, function(string memory) pure returns (string memory))
      internal
      pure returns (string memory) fn;
    assembly {
      fn := _fn
    }
    return fn(arr, serializeString);
  }
}

// ┌─ LibStringStub ────────────────────────────────────────────────────────────
library LibStringStub {
  // ░░▒▒▓▓██ [ DECIMAL STRINGS ] ──────────────────────────────────────────────

  // ┌─ toString ─────
  /// @dev return `value` in base 10.
  function toString(uint256 value) internal pure returns (string memory str) {
    /// @solidity memory-safe-assembly
    assembly {
      // uint256 needs at most 78 decimal digits. allocate 0xa0 bytes: three words for
      // digits, one for length, and one for trailing zeros. keep the free pointer aligned.
      str := add(mload(0x40), 0x80)
      mstore(0x40, add(str, 0x20))
      mstore(str, 0)

      let end := str

      let w := not(0)
      // write at least one byte so zero is represented too.
      for {
        let temp := value
      } 1 { } {
        str := add(str, w) // `sub(str, 1)`.
        // ASCII '0' starts at 48.
        mstore8(str, add(48, mod(temp, 10)))
        temp := div(temp, 10)
        if iszero(temp) {
          break
        }
      }

      let length := sub(end, str)
      // prepend the ABI length word.
      str := sub(str, 0x20)
      mstore(str, length)
    }
  }

  // ┌─ toString ─────
  /// @dev return `value` in base 10.
  function toString(int256 value) internal pure returns (string memory str) {
    if (value >= 0) {
      return toString(uint256(value));
    }
    unchecked {
      str = toString(uint256(-value));
    }
    /// @solidity memory-safe-assembly
    assembly {
      // the formatter leaves prefix room before the digits; reuse it for the minus sign.
      let length := mload(str)
      mstore(str, 0x2d) // '-'
      str := sub(str, 1)
      mstore(str, add(length, 1))
    }
  }

  // ░░▒▒▓▓██ [ HEXADECIMAL STRINGS ] ──────────────────────────────────────────

  // ┌─ toHexString ─────
  /// @dev return `value` as whole-byte hex with a 0x prefix; zero is 0x00.
  function toHexString(uint256 value) internal pure returns (string memory str) {
    str = toHexStringNoPrefix(value);

    /// @solidity memory-safe-assembly
    assembly {
      let strLength := add(mload(str), 2)
      mstore(str, 0x3078) // '0x'
      str := sub(str, 2)
      mstore(str, strLength)
    }
  }

  // ┌─ toHexString ─────
  /// @dev return the address as 40 hex digits with a 0x prefix, keeping leading zeros.
  function toHexString(address value) internal pure returns (string memory str) {
    str = toHexStringNoPrefix(value);

    /// @solidity memory-safe-assembly
    assembly {
      let strLength := add(mload(str), 2)
      mstore(str, 0x3078) // '0x'
      str := sub(str, 2)
      mstore(str, strLength)
    }
  }

  // ┌─ toHexString ─────
  /// @dev encode every input byte as two hex digits, including leading zeros.
  function toHexString(bytes memory raw) internal pure returns (string memory str) {
    str = toHexStringNoPrefix(raw);

    /// @solidity memory-safe-assembly
    assembly {
      let strLength := add(mload(str), 2)
      mstore(str, 0x3078) // '0x'
      str := sub(str, 2)
      mstore(str, strLength)
    }
  }

  // ┌─ toHexStringNoPrefix ─────
  /// @dev return whole-byte hex without a prefix, dropping leading zero bytes except for zero.
  function toHexStringNoPrefix(uint256 value) internal pure returns (string memory str) {
    /// @solidity memory-safe-assembly
    assembly {
      // length, trailing zeros, prefix room, and up to 64 hex digits need 0xa0 aligned bytes.
      str := add(mload(0x40), 0x80)
      mstore(0x40, add(str, 0x20))
      mstore(str, 0)

      let end := str
      // nibble-to-ASCII lookup in scratch space.
      mstore(0x0f, 0x30313233343536373839616263646566)

      let w := not(1)
      // write at least one byte so zero is represented too.
      for {
        let temp := value
      } 1 { } {
        str := add(str, w) // `sub(str, 2)`.
        mstore8(add(str, 1), mload(and(temp, 15)))
        mstore8(str, mload(and(shr(4, temp), 15)))
        temp := shr(8, temp)
        if iszero(temp) {
          break
        }
      }

      let strLength := sub(end, str)
      // prepend the ABI length word.
      str := sub(str, 0x20)
      mstore(str, strLength)
    }
  }

  // ┌─ toHexStringNoPrefix ─────
  /// @dev return all 40 address hex digits without a prefix.
  function toHexStringNoPrefix(address value) internal pure returns (string memory str) {
    /// @solidity memory-safe-assembly
    assembly {
      str := mload(0x40)

      // length, trailing zeros, prefix room, and 40 address digits need 0x80 aligned bytes.
      mstore(0x40, add(str, 0x80))

      // nibble-to-ASCII lookup in scratch space.
      mstore(0x0f, 0x30313233343536373839616263646566)

      str := add(str, 2)
      mstore(str, 40)

      let o := add(str, 0x20)
      mstore(add(o, 40), 0)

      value := shl(96, value)

      // encode all 20 address bytes, including leading zeros.
      for {
        let i := 0
      } 1 { } {
        let p := add(o, add(i, i))
        let temp := byte(i, value)
        mstore8(add(p, 1), mload(and(temp, 15)))
        mstore8(p, mload(shr(4, temp)))
        i := add(i, 1)
        if eq(i, 20) {
          break
        }
      }
    }
  }

  // ┌─ toHexStringNoPrefix ─────
  /// @dev encode every input byte as two hex digits, including leading zeros.
  function toHexStringNoPrefix(bytes memory raw) internal pure returns (string memory str) {
    /// @solidity memory-safe-assembly
    assembly {
      let length := mload(raw)
      str := add(mload(0x40), 2) // reserve two bytes for an optional prefix.
      mstore(str, add(length, length))

      // nibble-to-ASCII lookup in scratch space.
      mstore(0x0f, 0x30313233343536373839616263646566)

      let o := add(str, 0x20)
      let end := add(raw, length)

      for { } iszero(eq(raw, end)) { } {
        raw := add(raw, 1)
        mstore8(add(o, 1), mload(and(mload(raw), 15)))
        mstore8(o, mload(and(shr(4, mload(raw)), 15)))
        o := add(o, 2)
      }
      mstore(o, 0)
      mstore(0x40, and(add(o, 31), not(31)))
    }
  }
}
