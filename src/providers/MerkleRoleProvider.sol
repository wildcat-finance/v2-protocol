// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MerkleRoleProvider
// ║  ██▀▀     ▀▀██   Managed Merkle roots and proof-based lender credentials.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SETUP
// ║  constructor(...)
// ║
// ║  ROOT MANAGEMENT
// ║  updateRoot(...)
// ║  isMember(...)
// ║
// ║  CREDENTIALS
// ║  getCredential(...)
// ║  validateCredential(...)
// ╚═════

import 'solady/utils/MerkleProofLib.sol';
import '../libraries/SafeCastLib.sol';
import './IMerkleRoleProvider.sol';
import './ManagedRoleProvider.sol';

using SafeCastLib for uint256;

// ┌─ MerkleRoleProvider ───────────────────────────────────────────────────────
/// @notice validates address membership against an administrator-managed Merkle root.
///
/// @dev proofs use sorted pairs and leaves are `keccak256(abi.encode(account))`. hook data is
///      `abi.encodePacked(provider, abi.encode(proof))`. malformed proof encoding fails closed with
///      a zero credential instead of reverting.
contract MerkleRoleProvider is IMerkleRoleProvider, ManagedRoleProvider {
  bool public constant override isPullProvider = false;

  bytes32 public override root;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  /// @param administrator_ initial authority over the root and provider administration.
  /// @param root_          initial sorted-pair Merkle root.
  constructor(address administrator_, bytes32 root_) ManagedRoleProvider(administrator_) {
    root = root_;
  }

  // ░░▒▒▓▓██ [ ROOT MANAGEMENT ] ──────────────────────────────────────────────

  // ┌─ updateRoot ─────
  /// @notice replaces the root without changing this provider's address or hook attachments.
  ///
  /// @dev a cached credential from the previous root stays usable through its hook-defined expiry.
  function updateRoot(bytes32 newRoot) external override onlyAdministrator {
    bytes32 previousRoot = root;
    root = newRoot;
    emit RootUpdated(msg.sender, previousRoot, newRoot);
  }

  // ┌─ isMember ─────
  function isMember(address account, bytes32[] calldata proof) external view override returns (bool) {
    return MerkleProofLib.verifyCalldata(proof, root, keccak256(abi.encode(account)));
  }

  // ░░▒▒▓▓██ [ CREDENTIALS ] ──────────────────────────────────────────────────

  // ┌─ getCredential ─────
  /// @dev proofs are caller-supplied, so this provider cannot refresh credentials through the pull
  ///      path.
  function getCredential(address) external pure override returns (uint32 timestamp) {
    return 0;
  }

  // ┌─ validateCredential ─────
  /// @notice validates the standard ABI encoding of a `bytes32[]` proof for `account`.
  ///
  /// @return timestamp current timestamp for a valid proof, or zero for malformed data or
  ///         non-members.
  function validateCredential(address account, bytes calldata data) external view override returns (uint32 timestamp) {
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
