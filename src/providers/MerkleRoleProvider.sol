// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';
import 'solady/utils/MerkleProofLib.sol';

/// @notice Merkle allowlist provider that validates address membership proofs.
contract MerkleRoleProvider is IRoleProvider {
  error CallerNotAdmin();
  error InvalidAdmin();

  event RootUpdated(bytes32 oldRoot, bytes32 newRoot);

  address public immutable admin;
  bytes32 public root;

  constructor(address _admin, bytes32 _root) {
    if (_admin == address(0)) revert InvalidAdmin();
    admin = _admin;
    root = _root;
  }

  function updateRoot(bytes32 newRoot) external {
    if (msg.sender != admin) revert CallerNotAdmin();
    bytes32 oldRoot = root;
    root = newRoot;
    emit RootUpdated(oldRoot, newRoot);
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
    if ((offset & 0x1f) != 0 || offset + 0x20 > data.length) return 0;
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
