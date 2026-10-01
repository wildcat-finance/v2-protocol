// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // IERC20
// ║  ██▀▀     ▀▀██   Token allowances, transfers, balances, and metadata.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  ALLOWANCES
// ║  approve(...)
// ║  increaseAllowance(...)
// ║  decreaseAllowance(...)
// ║  allowance(...)
// ║
// ║  TRANSFERS
// ║  transfer(...)
// ║  transferFrom(...)
// ║
// ║  BALANCES AND SUPPLY
// ║  balanceOf(...)
// ║  totalSupply()
// ║
// ║  METADATA
// ║  name()
// ║  symbol()
// ║  decimals()
// ╚═════

// ┌─ IERC20 ───────────────────────────────────────────────────────────────────
/// @notice ERC-20 interface used by the protocol, including metadata and allowance helpers.
interface IERC20 {
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  // ░░▒▒▓▓██ [ ALLOWANCES ] ───────────────────────────────────────────────────

  // ┌─ approve ─────
  function approve(address spender, uint256 amount) external returns (bool);

  // ┌─ increaseAllowance ─────
  function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

  // ┌─ decreaseAllowance ─────
  function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

  // ┌─ allowance ─────
  function allowance(address owner, address spender) external view returns (uint256);

  // ░░▒▒▓▓██ [ TRANSFERS ] ────────────────────────────────────────────────────

  // ┌─ transfer ─────
  function transfer(address recipient, uint256 amount) external returns (bool);

  // ┌─ transferFrom ─────
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

  // ░░▒▒▓▓██ [ BALANCES AND SUPPLY ] ──────────────────────────────────────────

  // ┌─ balanceOf ─────
  function balanceOf(address account) external view returns (uint256);

  // ┌─ totalSupply ─────
  function totalSupply() external view returns (uint256);

  // ░░▒▒▓▓██ [ METADATA ] ─────────────────────────────────────────────────────

  // ┌─ name ─────
  function name() external view returns (string memory);

  // ┌─ symbol ─────
  function symbol() external view returns (string memory);

  // ┌─ decimals ─────
  function decimals() external view returns (uint8);
}
