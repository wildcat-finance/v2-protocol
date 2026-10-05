// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // LiveBalanceRoleProviderMock
//  \ ^ /   Live balance credentials for market and wrapper integration tests.
//    V
//
//  BALANCE SOURCE
//  balanceOf(...)
//  convertToAssets(...)
//
//  SETUP
//  constructor(...)
//
//  CREDENTIALS
//  getCredential(...)
//  validateCredential(...)
//  _credentialTimestamp(...)
// ═════

import { IRoleProvider } from 'src/access/IRoleProvider.sol';
import { SafeCastLib } from 'src/libraries/SafeCastLib.sol';

// retain this release compiler input after excluding the merkle provider.
// omitting it changes the lens optimizer output under solidity 0.8.25.
import 'solady/utils/MerkleProofLib.sol';

// ┌─ ILiveBalanceSource ───────────────────────────────────────────────────────
interface ILiveBalanceSource {
  // ░░▒▒▓▓██ [ BALANCE SOURCE ] ──────────────────────────────────────────────

  // ┌─ balanceOf ─────
  function balanceOf(address account) external view returns (uint256);

  // ┌─ convertToAssets ─────
  function convertToAssets(uint256 shares) external view returns (uint256);
}

// ┌─ LiveBalanceRoleProviderMock ───────────────────────────────────────────────
// test-only credential source; reads remain live and propagate source reverts.
contract LiveBalanceRoleProviderMock is IRoleProvider {
  using SafeCastLib for uint256;

  bool public constant override isPullProvider = true;
  ILiveBalanceSource internal immutable _source;
  uint256 internal immutable _minimum;
  bool internal immutable _valueSharesAsAssets;

  // ░░▒▒▓▓██ [ SETUP ] ───────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address source, uint256 minimum, bool valueSharesAsAssets) {
    _source = ILiveBalanceSource(source);
    _minimum = minimum;
    _valueSharesAsAssets = valueSharesAsAssets;
  }

  // ░░▒▒▓▓██ [ CREDENTIALS ] ─────────────────────────────────────────────────

  // ┌─ getCredential ─────
  function getCredential(address account) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  // ┌─ validateCredential ─────
  function validateCredential(address account, bytes calldata) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  // ┌─ _credentialTimestamp ─────
  function _credentialTimestamp(address account) internal view returns (uint32) {
    uint256 balance = _source.balanceOf(account);
    if (_valueSharesAsAssets) {
      if (balance == 0) return 0;
      balance = _source.convertToAssets(balance);
    }
    return balance >= _minimum ? block.timestamp.toUint32() : 0;
  }
}
