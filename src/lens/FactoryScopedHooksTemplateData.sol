// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // FactoryScopedHooksTemplateData
// ║  ██▀▀     ▀▀██   Factory-qualified hooks-template records for aggregation.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ╚═════

import './HooksTemplateData.sol';

/// @notice one hooks template row with the factory that supplied its metadata.
///
/// @dev unlike address-deduplicated aggregate results, this preserves duplicate template addresses
///      registered by different factory generations.
struct FactoryScopedHooksTemplateData {
  address hooksFactory;
  HooksTemplateData hooksTemplateData;
}
