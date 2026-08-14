// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';
import 'solady/utils/MerkleProofLib.sol';
import './ManagedRoleProvider.sol';

/// @notice Merkle allowlist provider that validates address membership proofs.
/// @dev Proofs use sorted pairs (same as Solady/OZ). Leaf = keccak256(abi.encode(account)).
///      hooksData must be `abi.encodePacked(provider, abi.encode(proof))` where
///      `proof` is `bytes32[]` encoded with standard ABI (offset + length + elements).
///      Malformed hooksData returns no credential (fail closed).
///      SDK note: when adding a helper, return `abi.encodePacked(provider, abi.encode(proof))`
///      to match the encoding expected by access hooks.
contract MerkleRoleProvider is IRoleProvider, ManagedRoleProvider {
  event RootUpdated(
    address indexed administrator,
    bytes32 previousRoot,
    bytes32 newRoot
  );

  bytes32 public root;

  constructor(
    address administrator_,
    bytes32 root_
  ) ManagedRoleProvider(administrator_) {
    root = root_;
  }

  function updateRoot(bytes32 newRoot) external onlyAdministrator {
    bytes32 previousRoot = root;
    root = newRoot;
    emit RootUpdated(msg.sender, previousRoot, newRoot);
  }

  function isMember(address account, bytes32[] calldata proof) external view returns (bool) {
    return MerkleProofLib.verifyCalldata(proof, root, keccak256(abi.encode(account)));
  }

  function isPullProvider() external pure override returns (bool) {
    return false;
  }

  function getCredential(address) external pure override returns (uint32 timestamp) {
    return 0;
  }

  function validateCredential(
    address account,
    bytes calldata data
  ) external view override returns (uint32 timestamp) {
    if (data.length < 0x40) return 0;
    uint256 offset;
    assembly {
      offset := calldataload(data.offset)
    }
    if ((offset & 0x1f) != 0 || offset > data.length - 0x20) return 0;
    bytes32[] calldata proof;
    assembly {
      let proofOffset := add(data.offset, offset)
      proof.length := calldataload(proofOffset)
      proof.offset := add(proofOffset, 0x20)
    }
    if (proof.length > (data.length - offset - 0x20) / 0x20) return 0;
    bytes32 leaf = keccak256(abi.encode(account));
    if (MerkleProofLib.verifyCalldata(proof, root, leaf)) {
      return uint32(block.timestamp);
    }
    return 0;
  }
}
