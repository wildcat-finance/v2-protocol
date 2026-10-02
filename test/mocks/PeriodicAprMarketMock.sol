// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // PeriodicAprMarketMock
// ║  ██▀▀     ▀▀██   Mutable APR response for periodic hook tests.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  APR CONFIGURATION
// ║  constructor(...)
// ║  setAnnualInterestBips(...)
// ╚═════

// ┌─ PeriodicAprMarketMock ────────────────────────────────────────────────────
contract PeriodicAprMarketMock {
  uint256 public annualInterestBips;

  // ░░▒▒▓▓██ [ APR CONFIGURATION ] ────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(uint256 initialAnnualInterestBips) {
    annualInterestBips = initialAnnualInterestBips;
  }

  // ┌─ setAnnualInterestBips ─────
  function setAnnualInterestBips(uint256 newAnnualInterestBips) external {
    annualInterestBips = newAnnualInterestBips;
  }
}
