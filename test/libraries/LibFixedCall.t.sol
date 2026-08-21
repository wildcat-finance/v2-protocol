// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/libraries/LibFixedCall.sol';

contract FixedCallTarget {
  address internal constant ExpectedAddress = address(0xA11CE);

  function addressValue() external pure returns (address) {
    return ExpectedAddress;
  }

  function addressValueFor(address value) external pure returns (address) {
    return value;
  }

  function wordValue() external pure returns (uint256) {
    return type(uint256).max;
  }

  function isExpectedAddress(address value) external pure returns (bool) {
    return value == ExpectedAddress;
  }
}

contract FixedCallHarness {
  function readWord(address target, bytes4 selector) external view returns (uint256) {
    return LibFixedCall.readWord(target, selector);
  }

  function readAddress(address target, bytes4 selector) external view returns (address) {
    return LibFixedCall.readAddress(target, selector);
  }

  function readAddress(
    address target,
    bytes4 selector,
    address argument
  ) external view returns (address) {
    return LibFixedCall.readAddress(target, selector, argument);
  }

  function readBool(address target, bytes4 selector, address argument) external view returns (bool) {
    return LibFixedCall.readBool(target, selector, argument);
  }
}

contract LibFixedCallTest is Test {
  FixedCallHarness internal harness = new FixedCallHarness();
  FixedCallTarget internal target = new FixedCallTarget();

  function test_readWord() external view {
    assertEq(
      harness.readWord(address(target), FixedCallTarget.wordValue.selector),
      type(uint256).max
    );
  }

  function test_readWord_AcceptsTrailingData() external {
    bytes memory callData = abi.encodeCall(FixedCallTarget.wordValue, ());
    vm.mockCall(
      address(target),
      callData,
      bytes.concat(abi.encode(type(uint256).max), bytes32(uint256(1)))
    );

    assertEq(
      harness.readWord(address(target), FixedCallTarget.wordValue.selector),
      type(uint256).max
    );
  }

  function test_readWord_RejectsShortData() external {
    vm.mockCall(address(target), abi.encodeCall(FixedCallTarget.wordValue, ()), hex'01');

    vm.expectRevert();
    harness.readWord(address(target), FixedCallTarget.wordValue.selector);
  }

  function test_readWord_BubblesRevert() external {
    bytes memory reason = abi.encodeWithSignature('Error(string)', 'no word');
    vm.mockCallRevert(address(target), abi.encodeCall(FixedCallTarget.wordValue, ()), reason);

    vm.expectRevert(reason);
    harness.readWord(address(target), FixedCallTarget.wordValue.selector);
  }

  function test_readAddress() external view {
    assertEq(
      harness.readAddress(address(target), FixedCallTarget.addressValue.selector),
      address(0xA11CE)
    );
  }

  function test_readAddress_AcceptsTrailingData() external {
    bytes memory callData = abi.encodeCall(FixedCallTarget.addressValue, ());
    vm.mockCall(
      address(target),
      callData,
      bytes.concat(abi.encode(address(0xA11CE)), bytes32(uint256(1)))
    );

    assertEq(
      harness.readAddress(address(target), FixedCallTarget.addressValue.selector),
      address(0xA11CE)
    );
  }

  function test_readAddress_RejectsShortData() external {
    vm.mockCall(address(target), abi.encodeCall(FixedCallTarget.addressValue, ()), hex'01');

    vm.expectRevert();
    harness.readAddress(address(target), FixedCallTarget.addressValue.selector);
  }

  function test_readAddress_RejectsDirtyAddress() external {
    vm.mockCall(
      address(target),
      abi.encodeCall(FixedCallTarget.addressValue, ()),
      abi.encode(uint256(1) << 160)
    );

    vm.expectRevert();
    harness.readAddress(address(target), FixedCallTarget.addressValue.selector);
  }

  function test_readAddress_BubblesRevert() external {
    bytes memory reason = abi.encodeWithSignature('Error(string)', 'no address');
    vm.mockCallRevert(address(target), abi.encodeCall(FixedCallTarget.addressValue, ()), reason);

    vm.expectRevert(reason);
    harness.readAddress(address(target), FixedCallTarget.addressValue.selector);
  }

  function test_readAddressWithArgument() external view {
    assertEq(
      harness.readAddress(
        address(target),
        FixedCallTarget.addressValueFor.selector,
        address(0xB0B)
      ),
      address(0xB0B)
    );
  }

  function test_readAddressWithArgument_AcceptsTrailingData() external {
    bytes memory callData = abi.encodeCall(FixedCallTarget.addressValueFor, (address(0xB0B)));
    vm.mockCall(
      address(target),
      callData,
      bytes.concat(abi.encode(address(0xB0B)), bytes32(uint256(1)))
    );

    assertEq(
      harness.readAddress(
        address(target),
        FixedCallTarget.addressValueFor.selector,
        address(0xB0B)
      ),
      address(0xB0B)
    );
  }

  function test_readAddressWithArgument_RejectsShortData() external {
    vm.mockCall(
      address(target),
      abi.encodeCall(FixedCallTarget.addressValueFor, (address(0xB0B))),
      hex'01'
    );

    vm.expectRevert();
    harness.readAddress(
      address(target),
      FixedCallTarget.addressValueFor.selector,
      address(0xB0B)
    );
  }

  function test_readAddressWithArgument_RejectsDirtyAddress() external {
    vm.mockCall(
      address(target),
      abi.encodeCall(FixedCallTarget.addressValueFor, (address(0xB0B))),
      abi.encode(uint256(1) << 160)
    );

    vm.expectRevert();
    harness.readAddress(
      address(target),
      FixedCallTarget.addressValueFor.selector,
      address(0xB0B)
    );
  }

  function test_readAddressWithArgument_BubblesRevert() external {
    bytes memory callData = abi.encodeCall(FixedCallTarget.addressValueFor, (address(0xB0B)));
    bytes memory reason = abi.encodeWithSignature('Error(string)', 'no address');
    vm.mockCallRevert(address(target), callData, reason);

    vm.expectRevert(reason);
    harness.readAddress(
      address(target),
      FixedCallTarget.addressValueFor.selector,
      address(0xB0B)
    );
  }

  function test_readBool() external view {
    assertTrue(
      harness.readBool(
        address(target),
        FixedCallTarget.isExpectedAddress.selector,
        address(0xA11CE)
      )
    );
    assertFalse(
      harness.readBool(
        address(target),
        FixedCallTarget.isExpectedAddress.selector,
        address(0xB0B)
      )
    );
  }

  function test_readBool_AcceptsTrailingData() external {
    bytes memory callData = abi.encodeCall(FixedCallTarget.isExpectedAddress, (address(0xA11CE)));
    vm.mockCall(address(target), callData, bytes.concat(abi.encode(true), bytes32(uint256(1))));

    assertTrue(
      harness.readBool(
        address(target),
        FixedCallTarget.isExpectedAddress.selector,
        address(0xA11CE)
      )
    );
  }

  function test_readBool_RejectsShortData() external {
    vm.mockCall(
      address(target),
      abi.encodeCall(FixedCallTarget.isExpectedAddress, (address(0xA11CE))),
      hex'01'
    );

    vm.expectRevert();
    harness.readBool(
      address(target),
      FixedCallTarget.isExpectedAddress.selector,
      address(0xA11CE)
    );
  }

  function test_readBool_RejectsDirtyBoolean() external {
    vm.mockCall(
      address(target),
      abi.encodeCall(FixedCallTarget.isExpectedAddress, (address(0xA11CE))),
      abi.encode(uint256(2))
    );

    vm.expectRevert();
    harness.readBool(
      address(target),
      FixedCallTarget.isExpectedAddress.selector,
      address(0xA11CE)
    );
  }

  function test_readBool_BubblesRevert() external {
    bytes memory callData = abi.encodeCall(FixedCallTarget.isExpectedAddress, (address(0xA11CE)));
    bytes memory reason = abi.encodeWithSignature('Error(string)', 'no bool');
    vm.mockCallRevert(address(target), callData, reason);

    vm.expectRevert(reason);
    harness.readBool(
      address(target),
      FixedCallTarget.isExpectedAddress.selector,
      address(0xA11CE)
    );
  }
}
