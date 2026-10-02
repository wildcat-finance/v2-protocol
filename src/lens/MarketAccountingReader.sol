// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MarketAccountingReader
// ║  ██▀▀     ▀▀██   Strict accounting reads with exact legacy-tuple padding.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  ACCOUNTING QUERIES
// ║  currentState(...)
// ║  previousState(...)
// ║  withdrawalBatch(...)
// ║
// ║  LEGACY DECODING
// ║  _read(...)
// ╚═════

import '../market/WildcatMarket.sol';

// ┌─ MarketAccountingReader ───────────────────────────────────────────────────
/// @dev older markets return one fewer word for state and batch tuples. pad only the
///      exact legacy shape; normal ABI decoding still rejects truncated or dirty values.
library MarketAccountingReader {
  // ░░▒▒▓▓██ [ ACCOUNTING QUERIES ] ───────────────────────────────────────────

  // ┌─ currentState ─────
  function currentState(WildcatMarket market) internal view returns (MarketState memory) {
    return
      abi.decode(_read(address(market), abi.encodeWithSelector(market.currentState.selector), 0x1c0), (MarketState));
  }

  // ┌─ previousState ─────
  function previousState(WildcatMarket market) internal view returns (MarketState memory) {
    return
      abi.decode(_read(address(market), abi.encodeWithSelector(market.previousState.selector), 0x1c0), (MarketState));
  }

  // ┌─ withdrawalBatch ─────
  function withdrawalBatch(WildcatMarket market, uint32 expiry) internal view returns (WithdrawalBatch memory) {
    return abi.decode(
      _read(address(market), abi.encodeWithSelector(market.getWithdrawalBatch.selector, expiry), 0x60),
      (WithdrawalBatch)
    );
  }

  // ░░▒▒▓▓██ [ LEGACY DECODING ] ──────────────────────────────────────────────

  // ┌─ _read ─────
  function _read(address market, bytes memory input, uint256 legacySize) private view returns (bytes memory data) {
    bool success;
    (success, data) = market.staticcall(input);
    if (!success) {
      assembly ('memory-safe') {
        revert(add(data, 0x20), mload(data))
      }
    }
    if (data.length == legacySize) data = bytes.concat(data, bytes32(0));
  }
}
