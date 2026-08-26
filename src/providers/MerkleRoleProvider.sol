// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import 'solady/utils/MerkleProofLib.sol';
import '../libraries/SafeCastLib.sol';
import './IMerkleRoleProvider.sol';
import './ManagedRoleProvider.sol';

using SafeCastLib for uint256;

/// @notice Merkle allowlist provider that validates address membership proofs.
/// @dev Proofs use sorted pairs (same as Solady/OZ). Leaf = keccak256(abi.encode(account)).
///      hooksData must be `abi.encodePacked(provider, abi.encode(proof))` where
///      `proof` is `bytes32[]` encoded with standard ABI (offset + length + elements).
///      Malformed hooksData returns no credential (fail closed).
contract MerkleRoleProvider is IMerkleRoleProvider, ManagedRoleProvider {
  bool public constant override isPullProvider = false;

  bytes32 public override root;

  constructor(
    address administrator_,
    bytes32 root_
  ) ManagedRoleProvider(administrator_) {
    root = root_;
  }

  function updateRoot(bytes32 newRoot) external override onlyAdministrator {
    bytes32 previousRoot = root;
    root = newRoot;
    emit RootUpdated(msg.sender, previousRoot, newRoot);
  }

  function isMember(
    address account,
    bytes32[] calldata proof
  ) external view override returns (bool) {
    return MerkleProofLib.verifyCalldata(proof, root, keccak256(abi.encode(account)));
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
    uint256 proofLength;
    assembly {
      offset := calldataload(data.offset)
      proofLength := calldataload(add(data.offset, 0x20))
    }
    if (offset != 0x20 || proofLength > (data.length - 0x40) / 0x20) return 0;
    if (data.length != 0x40 + proofLength * 0x20) return 0;
    bytes32[] calldata proof;
    assembly {
      proof.length := proofLength
      proof.offset := add(data.offset, 0x40)
    }
    bytes32 leaf = keccak256(abi.encode(account));
    if (MerkleProofLib.verifyCalldata(proof, root, leaf)) {
      return block.timestamp.toUint32();
    }
    return 0;
  }
}
