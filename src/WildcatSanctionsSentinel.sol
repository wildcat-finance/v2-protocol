// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // WildcatSanctionsSentinel
// ║  ██▀▀     ▀▀██   Sanctions overrides, status queries, and escrow deployment.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SETUP
// ║  constructor(...)
// ║
// ║  SANCTION OVERRIDES
// ║  overrideSanction(...)
// ║  removeSanctionOverride(...)
// ║
// ║  SANCTION QUERIES
// ║  isSanctioned(...)
// ║  isFlaggedByChainalysis(...)
// ║
// ║  ESCROW DEPLOYMENT
// ║  createEscrow(...)
// ║  getEscrowAddress(...)
// ║  _deriveSalt(...)
// ║  _resetTmpEscrowParams()
// ╚═════

import { IChainalysisSanctionsList } from './interfaces/IChainalysisSanctionsList.sol';
import { IWildcatSanctionsSentinel } from './interfaces/IWildcatSanctionsSentinel.sol';
import { WildcatSanctionsEscrow } from './WildcatSanctionsEscrow.sol';

// ┌─ WildcatSanctionsSentinel ─────────────────────────────────────────────────
/// @title Wildcat sanctions sentinel
///
/// @notice combine the external sanctions list with borrower-scoped overrides and escrows.
///
/// @dev overrides allow a flagged account; they do not change the external list.
contract WildcatSanctionsSentinel is IWildcatSanctionsSentinel {
  // ░░▒▒▓▓██ [ CONSTANTS ] ────────────────────────────────────────────────────

  bytes32 public constant override WildcatSanctionsEscrowInitcodeHash =
    keccak256(type(WildcatSanctionsEscrow).creationCode);

  address public immutable override chainalysisSanctionsList;

  address public immutable override archController;

  // ░░▒▒▓▓██ [ STORAGE ] ──────────────────────────────────────────────────────

  TmpEscrowParams public override tmpEscrowParams;

  mapping(address borrower => mapping(address account => bool sanctionOverride)) public override sanctionOverrides;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address _archController, address _chainalysisSanctionsList) {
    archController = _archController;
    chainalysisSanctionsList = _chainalysisSanctionsList;
    _resetTmpEscrowParams();
  }

  // ░░▒▒▓▓██ [ SANCTION OVERRIDES ] ───────────────────────────────────────────

  // ┌─ overrideSanction ─────
  /// @inheritdoc IWildcatSanctionsSentinel
  function overrideSanction(address account) public override {
    sanctionOverrides[msg.sender][account] = true;
    emit SanctionOverride(msg.sender, account);
  }

  // ┌─ removeSanctionOverride ─────
  /// @inheritdoc IWildcatSanctionsSentinel
  function removeSanctionOverride(address account) public override {
    sanctionOverrides[msg.sender][account] = false;
    emit SanctionOverrideRemoved(msg.sender, account);
  }

  // ░░▒▒▓▓██ [ SANCTION QUERIES ] ─────────────────────────────────────────────

  // ┌─ isSanctioned ─────
  /// @inheritdoc IWildcatSanctionsSentinel
  function isSanctioned(address borrower, address account) public view override returns (bool) {
    return !sanctionOverrides[borrower][account] && isFlaggedByChainalysis(account);
  }

  // ┌─ isFlaggedByChainalysis ─────
  /// @inheritdoc IWildcatSanctionsSentinel
  function isFlaggedByChainalysis(address account) public view override returns (bool) {
    bool isFlagged;
    address sanctionsList = chainalysisSanctionsList;
    assembly ('memory-safe') {
      // 0x00 through 0x3f is Solidity's scratch space. that's exactly enough for a selector and
      // one address, and we can reuse the first word for the result.
      mstore(0, 0xdf592f7d)
      mstore(0x20, account)

      // mstore leaves the selector in the last four bytes of the first word. starting at 0x1c
      // gives us selector | account, or 0x24 bytes of ordinary ABI calldata.
      if iszero(staticcall(gas(), sanctionsList, 0x1c, 0x24, 0, 0x20)) {
        // the call only writes one word for us, but a revert may be longer. copy the whole error
        // over scratch space and bubble it up. this path ends here, so nothing sees that memory
        // afterward.
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }

      // Solidity's bool decoder expects one full word containing zero or one. keep the same
      // rules here; trailing data is harmless because we only read that first word.
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      isFlagged := mload(0)
      if gt(isFlagged, 1) {
        revert(0, 0)
      }
    }
    return isFlagged;
  }

  // ░░▒▒▓▓██ [ ESCROW DEPLOYMENT ] ────────────────────────────────────────────

  // ┌─ createEscrow ─────
  /// @inheritdoc IWildcatSanctionsSentinel
  function createEscrow(
    address borrower,
    address account,
    address asset
  )
    public
    override
    returns (address escrowContract)
  {
    escrowContract = getEscrowAddress(borrower, account, asset);

    if (escrowContract.code.length != 0) return escrowContract;

    tmpEscrowParams = TmpEscrowParams(borrower, account, asset);

    new WildcatSanctionsEscrow{ salt: _deriveSalt(borrower, account, asset) }();

    emit NewSanctionsEscrow(borrower, account, asset);

    sanctionOverrides[borrower][escrowContract] = true;

    emit SanctionOverride(borrower, escrowContract);

    _resetTmpEscrowParams();
  }

  // ┌─ getEscrowAddress ─────
  /// @inheritdoc IWildcatSanctionsSentinel
  function getEscrowAddress(
    address borrower,
    address account,
    address asset
  )
    public
    view
    override
    returns (address escrowAddress)
  {
    bytes32 salt = _deriveSalt(borrower, account, asset);
    bytes32 initCodeHash = WildcatSanctionsEscrowInitcodeHash;
    assembly {
      // the hash buffer borrows 0x40; restore it before leaving.
      let freeMemoryPointer := mload(0x40)

      // bytes 11:32 hold 0xff followed by address(this).
      mstore(0x00, or(0xff0000000000000000000000000000000000000000, address()))

      // bytes 32:64 hold the salt.
      mstore(0x20, salt)

      // bytes 64:96 hold the initcode hash.
      mstore(0x40, initCodeHash)

      escrowAddress := and(keccak256(0x0b, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)

      mstore(0x40, freeMemoryPointer)
    }
  }

  // ┌─ _deriveSalt ─────
  /// @dev derive the CREATE2 salt for one borrower, account, and asset tuple.
  function _deriveSalt(address borrower, address account, address asset) internal pure returns (bytes32 salt) {
    assembly {
      // the third ABI word borrows 0x40; restore it after hashing.
      let freeMemoryPointer := mload(0x40)
      // `keccak256(abi.encode(borrower, account, asset))`
      mstore(0x00, borrower)
      mstore(0x20, account)
      mstore(0x40, asset)
      salt := keccak256(0, 0x60)
      mstore(0x40, freeMemoryPointer)
    }
  }

  // ┌─ _resetTmpEscrowParams ─────
  function _resetTmpEscrowParams() internal {
    tmpEscrowParams = TmpEscrowParams(address(1), address(1), address(1));
  }
}
