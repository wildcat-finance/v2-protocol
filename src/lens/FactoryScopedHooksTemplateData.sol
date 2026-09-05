// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import './HooksTemplateData.sol';

/// @notice one hooks template row with the factory that supplied its metadata.
/// @dev unlike address-deduplicated aggregate results, this preserves duplicate template addresses
///      registered by different factory generations.
struct FactoryScopedHooksTemplateData {
  address hooksFactory;
  HooksTemplateData hooksTemplateData;
}
