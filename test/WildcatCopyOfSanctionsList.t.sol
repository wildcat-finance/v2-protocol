// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "forge-std/Test.sol";
import "src/WildcatCopyOfChainalysisList.sol";

contract WildcatCopyOfChainalysisListTest is Test {
    WildcatCopyOfChainalysisList list;
    address owner = address(this);
    address nonOwner = address(0xBEEF);
    address addr1 = address(0x1);
    address addr2 = address(0x2);
    address addr3 = address(0x3);

    function setUp() public {
        list = new WildcatCopyOfChainalysisList();
    }

    // --- HELPERS ---

    function _assertContains(address a, bool expected) internal view {
        bool isSanctioned = list.isSanctioned(a);
        assertEq(isSanctioned, expected, "Unexpected sanction status");
    }

    function _assertListEq(address[] memory a, address[] memory b) internal pure {
        assertEq(a.length, b.length, "length mismatch");
        for (uint256 i; i < a.length; i++) {
            assertEq(a[i], b[i], "element mismatch");
        }
    }

    // --- TESTS ---

    function testInitialOwner() public {
        assertEq(list.owner(), owner, "Owner should be deployer");
    }

    function testAddToSanctionsList() public {
        address[] memory arr = new address[](2);
        arr[0] = addr1;
        arr[1] = addr2;

        vm.expectEmit(true, true, true, true);
        emit WildcatCopyOfChainalysisList.SanctionedAddressesAdded(arr);
        list.addToSanctionsList(arr);

        _assertContains(addr1, true);
        _assertContains(addr2, true);
        assertEq(list.getSanctionedAddressesCount(), 2);
    }

    function testAddRevertsIfNotOwner() public {
        vm.prank(nonOwner);
        address[] memory arr = new address[](1);
        arr[0] = addr1;
        vm.expectRevert(Ownable.Unauthorized.selector);
        list.addToSanctionsList(arr);
    }

    function testRemoveFromSanctionsList() public {
        address[] memory arr = new address[](2);
        arr[0] = addr1;
        arr[1] = addr2;
        list.addToSanctionsList(arr);

        address[] memory toRemove = new address[](1);
        toRemove[0] = addr1;

        vm.expectEmit(true, true, true, true);
        emit WildcatCopyOfChainalysisList.SanctionedAddressesRemoved(toRemove);
        list.removeFromSanctionsList(toRemove);

        _assertContains(addr1, false);
        _assertContains(addr2, true);
        assertEq(list.getSanctionedAddressesCount(), 1);
    }

    function testRemoveRevertsIfNotOwner() public {
        address[] memory arr = new address[](1);
        arr[0] = addr1;
        list.addToSanctionsList(arr);

        vm.prank(nonOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        list.removeFromSanctionsList(arr);
    }

    function testAddRemoveAddSameAddress() public {
        address[] memory arr = new address[](1);
        arr[0] = addr1;

        list.addToSanctionsList(arr);
        _assertContains(addr1, true);

        list.removeFromSanctionsList(arr);
        _assertContains(addr1, false);

        assertEq(list.getSanctionedAddressesCount(), 0);
        address[] memory empty;
        assertEq(list.getSanctionedAddresses(), empty);

        list.addToSanctionsList(arr);
        _assertContains(addr1, true);

        assertEq(list.getSanctionedAddressesCount(), 1);
        address[] memory sanctioned = list.getSanctionedAddresses();
        assertEq(sanctioned[0], addr1);
    }

    function testUpdateSanctionsList_AddAndRemove() public {
        address[] memory addArr = new address[](2);
        addArr[0] = addr1;
        addArr[1] = addr2;

        address[] memory removeArr = new address[](1);
        removeArr[0] = addr3; // removing non-existent should be fine

        // Add two, remove none effectively
        vm.expectEmit(true, true, true, true);
        emit WildcatCopyOfChainalysisList.SanctionedAddressesAdded(addArr);
        list.updateSanctionsList(addArr, removeArr);

        _assertContains(addr1, true);
        _assertContains(addr2, true);
        _assertContains(addr3, false);

        // Now remove one and add another
        address[] memory addArr2 = new address[](1);
        addArr2[0] = addr3;
        address[] memory removeArr2 = new address[](1);
        removeArr2[0] = addr1;

        vm.expectEmit(true, true, true, true);
        emit WildcatCopyOfChainalysisList.SanctionedAddressesAdded(addArr2);
        vm.expectEmit(true, true, true, true);
        emit WildcatCopyOfChainalysisList.SanctionedAddressesRemoved(removeArr2);
        list.updateSanctionsList(addArr2, removeArr2);

        _assertContains(addr1, false);
        _assertContains(addr2, true);
        _assertContains(addr3, true);
    }

    function testUpdateRevertsIfNotOwner() public {
        address[] memory a = new address[](1);
        a[0] = addr1;
        vm.prank(nonOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        address[] memory a2 = new address[](0);
        list.updateSanctionsList(a, a2);
    }

    function testGetSanctionedAddressesPagination() public {
        address[] memory addrs = new address[](3);
        addrs[0] = addr1;
        addrs[1] = addr2;
        addrs[2] = addr3;
        list.addToSanctionsList(addrs);

        // [0, 1)
        address[] memory slice1 = list.getSanctionedAddresses(0, 1);
        assertEq(slice1.length, 1);
        assertEq(slice1[0], addr1);

        // [1, 3)
        address[] memory slice2 = list.getSanctionedAddresses(1, 3);
        assertEq(slice2.length, 2);
        assertEq(slice2[0], addr2);
        assertEq(slice2[1], addr3);

        // [0, len] returns all
        address[] memory all = list.getSanctionedAddresses(0, 10);
        _assertListEq(all, addrs);
    }

    function testCheckSanctionsList() public {
        address[] memory addArr = new address[](2);
        addArr[0] = addr1;
        addArr[1] = addr2;
        list.addToSanctionsList(addArr);

        address[] memory check = new address[](3);
        check[0] = addr1;
        check[1] = addr2;
        check[2] = addr3;

        bool[] memory results = list.checkSanctionsList(check);
        assertEq(results.length, 3);
        assertTrue(results[0]);
        assertTrue(results[1]);
        assertFalse(results[2]);
    }

    function testEmptyArraysDoNotRevert() public {
        address[] memory empty = new address[](0);

        // Should not revert nor emit
        list.addToSanctionsList(empty);
        list.removeFromSanctionsList(empty);
        list.updateSanctionsList(empty, empty);

        assertEq(list.getSanctionedAddressesCount(), 0);
    }
}
