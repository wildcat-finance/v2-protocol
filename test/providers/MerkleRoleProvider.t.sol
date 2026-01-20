// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import '../BaseMarketTest.sol';
import { fastForward } from '../helpers/VmUtils.sol';
import 'src/providers/MerkleRoleProvider.sol';

contract MerkleRoleProviderTest is BaseMarketTest {
  MerkleRoleProvider internal provider;

  address internal approvedLender;
  address internal unapprovedLender;
  address internal otherLender;

  bytes32 internal approvedLeaf;
  bytes32 internal otherLeaf;
  bytes32 internal merkleRoot;

  function setUp() public override {
    super.setUp();
    _deauthorizeLender(alice);

    approvedLender = alice;
    unapprovedLender = bob;
    otherLender = address(0xbeef);

    approvedLeaf = _leaf(approvedLender);
    otherLeaf = _leaf(otherLender);
    merkleRoot = _hashPair(approvedLeaf, otherLeaf);

    provider = new MerkleRoleProvider(parameters.borrower, merkleRoot);

    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), type(uint32).max);
    vm.stopPrank();
  }

  /// @dev Merkle members can deposit using a valid proof.
  function test_deposit_allows_merkle_member() external {
    bytes32[] memory proof = _proofForApproved();
    bytes memory hooksData = _hooksData(proof);
    _depositWithHooksData(approvedLender, 1e18, hooksData);
  }

  /// @dev Non-members are rejected even with an unrelated proof.
  function test_deposit_reverts_merkle_nonmember() external {
    bytes32[] memory proof = _proofForApproved();
    bytes memory hooksData = _hooksData(proof);
    _expectDepositRevertNotApproved(unapprovedLender, 1e18, hooksData);
  }

  /// @dev Cached credentials persist until TTL expiry after root updates.
  function test_deposit_merkle_expires_after_ttl() external {
    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 1);
    vm.stopPrank();

    bytes32[] memory proof = _proofForApproved();
    bytes memory hooksData = _hooksData(proof);

    _depositWithHooksData(approvedLender, 1e18, hooksData);

    bytes32 newRoot = _hashPair(otherLeaf, _leaf(address(0xdead)));
    vm.prank(parameters.borrower);
    provider.updateRoot(newRoot);

    _depositWithHooksData(approvedLender, 1e18, hooksData);

    fastForward(2);

    _expectDepositRevertNotApproved(approvedLender, 1e18, hooksData);
  }

  /// @dev Only the admin can update the merkle root.
  function test_updateRoot_reverts_non_admin() external {
    vm.expectRevert(MerkleRoleProvider.CallerNotAdmin.selector);
    vm.prank(unapprovedLender);
    provider.updateRoot(bytes32(uint256(123)));
  }

  /// @dev Malformed hooks data is treated as invalid credentials.
  function test_deposit_reverts_invalid_hooks_data_short() external {
    bytes memory hooksData = abi.encodePacked(address(provider), bytes1(0x01));
    _expectDepositRevertNotApproved(approvedLender, 1e18, hooksData);
  }

  /// @dev Malformed hooks data with an invalid offset fails closed.
  function test_deposit_reverts_invalid_hooks_data_offset() external {
    bytes memory invalidData = abi.encodePacked(uint256(1), uint256(0));
    bytes memory hooksData = abi.encodePacked(address(provider), invalidData);
    _expectDepositRevertNotApproved(approvedLender, 1e18, hooksData);
  }

  /// @dev Admin must be a non-zero address.
  function test_constructor_reverts_invalid_admin() external {
    vm.expectRevert(MerkleRoleProvider.InvalidAdmin.selector);
    new MerkleRoleProvider(address(0), bytes32(0));
  }

  /// @dev Empty proofs are valid for a single-leaf tree.
  function test_deposit_allows_single_leaf_root() external {
    bytes32 singleRoot = _leaf(approvedLender);
    MerkleRoleProvider singleProvider = new MerkleRoleProvider(
      parameters.borrower,
      singleRoot
    );
    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(singleProvider), type(uint32).max);
    vm.stopPrank();

    bytes32[] memory proof = new bytes32[](0);
    bytes memory hooksData = abi.encodePacked(address(singleProvider), abi.encode(proof));
    _depositWithHooksData(approvedLender, 1e18, hooksData);
  }

  /// @dev Root updates can enable new members with a valid proof.
  function test_updateRoot_allows_new_member() external {
    bytes32 newLeaf = _leaf(unapprovedLender);
    bytes32 siblingLeaf = _leaf(otherLender);
    bytes32 newRoot = _hashPair(newLeaf, siblingLeaf);

    vm.prank(parameters.borrower);
    provider.updateRoot(newRoot);

    bytes32[] memory proof = new bytes32[](1);
    proof[0] = siblingLeaf;
    bytes memory hooksData = _hooksData(proof);

    _depositWithHooksData(unapprovedLender, 1e18, hooksData);
  }

  /// @dev Malformed hooks data with an oversized proof length fails closed.
  function test_deposit_reverts_invalid_hooks_data_length() external {
    bytes memory invalidData = abi.encodePacked(
      uint256(0x20),
      uint256(2),
      bytes32(uint256(1))
    );
    bytes memory hooksData = abi.encodePacked(address(provider), invalidData);
    _expectDepositRevertNotApproved(approvedLender, 1e18, hooksData);
  }

  function _depositWithHooksData(
    address from,
    uint256 amount,
    bytes memory hooksData
  ) internal returns (uint256) {
    MarketState memory state = pendingState();
    (uint256 currentScaledBalance, uint256 currentBalance) = _getBalance(state, from);

    asset.mint(from, amount);

    vm.startPrank(from);
    asset.approve(address(market), amount);

    (uint104 scaledAmount, uint256 expectedNormalizedAmount) = _trackDeposit(state, from, amount);

    bytes memory data = abi.encodePacked(
      abi.encodeWithSelector(WildcatMarket.depositUpTo.selector, amount),
      hooksData
    );
    (bool success, bytes memory returnData) = address(market).call(data);
    vm.stopPrank();

    if (!success) {
      assembly {
        revert(add(returnData, 0x20), mload(returnData))
      }
    }

    uint256 actualNormalizedAmount = abi.decode(returnData, (uint256));
    assertEq(actualNormalizedAmount, expectedNormalizedAmount, 'Actual amount deposited');
    _checkState(state);
    assertEq(
      market.balanceOf(from),
      currentBalance + state.normalizeAmount(scaledAmount),
      'Resulting balance != old balance + normalize(scale(deposit))'
    );
    assertApproxEqAbs(
      market.balanceOf(from),
      currentBalance + amount,
      1,
      'Resulting balance not within 1 wei of old balance + amount deposited'
    );
    assertEq(
      market.scaledBalanceOf(from),
      currentScaledBalance + scaledAmount,
      'Resulting scaled balance'
    );
    return actualNormalizedAmount;
  }

  function _expectDepositRevertNotApproved(
    address from,
    uint256 amount,
    bytes memory hooksData
  ) internal {
    asset.mint(from, amount);

    vm.startPrank(from);
    asset.approve(address(market), amount);

    bytes memory data = abi.encodePacked(
      abi.encodeWithSelector(WildcatMarket.depositUpTo.selector, amount),
      hooksData
    );
    (bool success, bytes memory returnData) = address(market).call(data);
    vm.stopPrank();

    assertFalse(success, 'expected deposit to revert');
    bytes4 selector;
    assembly {
      selector := mload(add(returnData, 0x20))
    }
    assertEq(selector, AccessControlHooks.NotApprovedLender.selector, 'expected NotApprovedLender');
  }

  function _hooksData(bytes32[] memory proof) internal view returns (bytes memory) {
    return abi.encodePacked(address(provider), abi.encode(proof));
  }

  function _proofForApproved() internal view returns (bytes32[] memory proof) {
    proof = new bytes32[](1);
    proof[0] = otherLeaf;
  }

  function _leaf(address account) internal pure returns (bytes32) {
    return keccak256(abi.encode(account));
  }

  function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
    return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
  }
}
