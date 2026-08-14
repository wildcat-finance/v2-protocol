// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import '../BaseMarketTest.sol';
import { fastForward } from '../helpers/VmUtils.sol';
import 'src/access/BaseAccessControls.sol';
import 'src/access/IManagedRoleProvider.sol';
import 'src/providers/IMerkleRoleProvider.sol';
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
    hooks.addRoleProvider(address(provider), 0);
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

  function test_deposit_merkle_zero_ttl_requires_fresh_proof() external {
    bytes32[] memory proof = _proofForApproved();
    bytes memory hooksData = _hooksData(proof);
    _depositWithHooksData(approvedLender, 1e18, hooksData);

    bytes32 newRoot = _hashPair(otherLeaf, _leaf(address(0xdead)));
    vm.prank(parameters.borrower);
    provider.updateRoot(newRoot);
    vm.warp(block.timestamp + 1);

    _expectDepositRevertNotApproved(approvedLender, 1e18, hooksData);
  }

  function test_deposit_merkle_zero_ttl_uses_same_timestamp_credential() external {
    bytes32[] memory proof = _proofForApproved();
    _depositWithHooksData(approvedLender, 1e18, _hooksData(proof));

    bytes32 newRoot = _hashPair(otherLeaf, _leaf(address(0xdead)));
    vm.prank(parameters.borrower);
    provider.updateRoot(newRoot);

    _depositWithHooksData(approvedLender, 1e18, '');
  }

  /// @dev Only the admin can update the merkle root.
  function test_updateRoot_reverts_non_admin() external {
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    vm.prank(unapprovedLender);
    provider.updateRoot(bytes32(uint256(123)));
  }

  function test_updateRoot_emits_administrator() external {
    bytes32 newRoot = bytes32(uint256(123));
    vm.expectEmit(address(provider));
    emit IMerkleRoleProvider.RootUpdated(parameters.borrower, merkleRoot, newRoot);
    vm.prank(parameters.borrower);
    provider.updateRoot(newRoot);
  }

  function test_administratorTransfer_moves_root_authority() external {
    address newAdministrator = address(0xa11ce);
    bytes32 newRoot = bytes32(uint256(123));

    vm.prank(parameters.borrower);
    provider.requestAdministratorTransfer(newAdministrator);

    vm.prank(newAdministrator);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.updateRoot(newRoot);

    vm.prank(newAdministrator);
    provider.acceptAdministratorTransfer();

    assertEq(provider.administrator(), newAdministrator, 'administrator');
    assertEq(provider.root(), merkleRoot, 'root');

    vm.prank(parameters.borrower);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.updateRoot(newRoot);

    vm.prank(newAdministrator);
    provider.updateRoot(newRoot);
    assertEq(provider.root(), newRoot, 'new root');
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

  function test_validateCredential_rejects_oversized_aligned_offset() external view {
    bytes memory invalidData = abi.encodePacked(type(uint256).max - 31, uint256(0));
    assertEq(provider.validateCredential(approvedLender, invalidData), 0, 'credential');
  }

  function test_validateCredential_rejects_noncanonical_empty_proof() external {
    MerkleRoleProvider singleProvider = new MerkleRoleProvider(
      parameters.borrower,
      _leaf(approvedLender)
    );
    bytes memory invalidData = abi.encodePacked(uint256(0), uint256(0));
    assertEq(singleProvider.validateCredential(approvedLender, invalidData), 0, 'credential');
  }

  function test_validateCredential_rejects_trailing_data() external view {
    bytes32[] memory proof = _proofForApproved();
    bytes memory invalidData = abi.encodePacked(abi.encode(proof), bytes32(uint256(1)));
    assertEq(provider.validateCredential(approvedLender, invalidData), 0, 'credential');
  }

  function testFuzz_validateCredential_acceptsGeneratedProof(
    address account,
    bytes32[] calldata proof
  ) external {
    vm.assume(proof.length <= 64);
    bytes32 root = _rootFor(account, proof);
    MerkleRoleProvider generatedProvider = new MerkleRoleProvider(parameters.borrower, root);

    assertEq(
      generatedProvider.validateCredential(account, abi.encode(proof)),
      uint32(block.timestamp),
      'credential'
    );
  }

  function testFuzz_validateCredential_rejectsDifferentAccount(
    address account,
    bytes32[] calldata proof
  ) external {
    vm.assume(proof.length <= 64);
    bytes32 root = _rootFor(account, proof);
    MerkleRoleProvider generatedProvider = new MerkleRoleProvider(parameters.borrower, root);
    address differentAccount = address(uint160(account) ^ uint160(1));

    assertEq(
      generatedProvider.validateCredential(differentAccount, abi.encode(proof)),
      0,
      'credential'
    );
  }

  function testFuzz_validateCredential_malformedData_failsClosed(
    bytes calldata data
  ) external view {
    assertEq(provider.validateCredential(unapprovedLender, data), 0, 'credential');
  }

  /// @dev Administrator must be a non-zero address.
  function test_constructor_reverts_invalid_admin() external {
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
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
    hooks.addRoleProvider(address(singleProvider), 0);
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

  /// @dev isMember mirrors proof verification against the current root.
  function test_isMember_checks_proof() external {
    bytes32[] memory proof = _proofForApproved();
    assertTrue(provider.isMember(approvedLender, proof), 'expected member with proof');
    assertFalse(provider.isMember(unapprovedLender, proof), 'expected non-member with proof');
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
    assertEq(selector, BaseAccessControls.NotApprovedLender.selector, 'expected NotApprovedLender');
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

  function _rootFor(
    address account,
    bytes32[] calldata proof
  ) internal pure returns (bytes32 root) {
    root = _leaf(account);
    for (uint256 i; i < proof.length; i++) {
      root = _hashPair(root, proof[i]);
    }
  }
}
