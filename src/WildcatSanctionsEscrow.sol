// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // WildcatSanctionsEscrow
//  \ ^ /   Borrower-scoped sanctioned assets and conditional release.
//    V
//
//  SETUP
//  constructor()
//
//  ESCROW RELEASE
//  releaseEscrow()
//  canReleaseEscrow()
//
//  ASSET QUERIES
//  escrowedAsset()
//  balance()
// ═════

import './interfaces/IERC20.sol';
import './interfaces/IWildcatSanctionsEscrow.sol';
import './interfaces/IWildcatSanctionsSentinel.sol';
import './libraries/LibERC20.sol';

// ┌─ WildcatSanctionsEscrow ───────────────────────────────────────────────────
/// @title Wildcat sanctions escrow
///
/// @notice hold one asset for a sanctioned account until its borrower-scoped status clears.
///
/// @dev configuration comes from the deploying sentinel's temporary parameters. the escrow keeps
///      the original borrower namespace even if a market later changes borrower.
contract WildcatSanctionsEscrow is IWildcatSanctionsEscrow {
  using LibERC20 for address;

  address public immutable override sentinel;
  address public immutable override borrower;
  address public immutable override account;
  address internal immutable asset;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor() {
    sentinel = msg.sender;
    (borrower, account, asset) = IWildcatSanctionsSentinel(sentinel).tmpEscrowParams();
  }

  // ░░▒▒▓▓██ [ ESCROW RELEASE ] ───────────────────────────────────────────────

  // ┌─ releaseEscrow ─────
  /// @inheritdoc IWildcatSanctionsEscrow
  function releaseEscrow() public override {
    if (!canReleaseEscrow()) revert CanNotReleaseEscrow();

    uint256 amount = balance();
    address _account = account;
    address _asset = asset;

    asset.safeTransfer(_account, amount);

    emit EscrowReleased(_account, _asset, amount);
  }

  // ┌─ canReleaseEscrow ─────
  /// @inheritdoc IWildcatSanctionsEscrow
  function canReleaseEscrow() public view override returns (bool) {
    return !IWildcatSanctionsSentinel(sentinel).isSanctioned(borrower, account);
  }

  // ░░▒▒▓▓██ [ ASSET QUERIES ] ────────────────────────────────────────────────

  // ┌─ escrowedAsset ─────
  /// @inheritdoc IWildcatSanctionsEscrow
  function escrowedAsset() public view override returns (address, uint256) {
    return (asset, balance());
  }

  // ┌─ balance ─────
  /// @inheritdoc IWildcatSanctionsEscrow
  function balance() public view override returns (uint256) {
    return IERC20(asset).balanceOf(address(this));
  }
}
