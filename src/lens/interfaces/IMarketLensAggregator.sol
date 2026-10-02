// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // IMarketLensAggregator
// ║  ██▀▀     ▀▀██   Default, explicit, and cross-factory query surfaces.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  BORROWER HOOKS DATA
// ║  getHooksDataForBorrower(...)
// ║  getHooksDataForBorrower(...)
// ║  getAggregatedHooksDataForBorrower(...)
// ║
// ║  HOOKS INSTANCES
// ║  getHooksInstancesForBorrower(...)
// ║  getHooksInstancesForBorrower(...)
// ║  getAggregatedHooksInstancesForBorrower(...)
// ║
// ║  HOOKS TEMPLATES
// ║  getHooksTemplateForBorrower(...)
// ║  getHooksTemplateForBorrower(...)
// ║  getHooksTemplatesForBorrower(...)
// ║  getHooksTemplatesForBorrower(...)
// ║  getAllHooksTemplatesForBorrower(...)
// ║  getAllHooksTemplatesForBorrower(...)
// ║  getAggregatedAllHooksTemplatesForBorrower(...)
// ║  getAggregatedHooksTemplatesForBorrowerWithFactory(...)
// ║
// ║  TEMPLATE MARKETS
// ║  getMarketsForHooksTemplateCount(...)
// ║  getMarketsForHooksTemplateCount(...)
// ║  getAggregatedMarketsForHooksTemplateCount(...)
// ║  getPaginatedMarketsDataForHooksTemplate(...)
// ║  getPaginatedMarketsDataForHooksTemplate(...)
// ║  getPaginatedMarketsDataV2ForHooksTemplate(...)
// ║  getPaginatedMarketsDataV2ForHooksTemplate(...)
// ║  getAllMarketsDataForHooksTemplate(...)
// ║  getAllMarketsDataForHooksTemplate(...)
// ║  getAllMarketsDataV2ForHooksTemplate(...)
// ║  getAllMarketsDataV2ForHooksTemplate(...)
// ║  getAggregatedAllMarketsDataForHooksTemplate(...)
// ║  getAggregatedAllMarketsDataV2ForHooksTemplate(...)
// ╚═════

import '../FactoryScopedHooksTemplateData.sol';
import '../HooksDataForBorrower.sol';
import '../HooksInstanceData.sol';
import '../HooksTemplateData.sol';
import '../MarketData.sol';

// ┌─ IMarketLensAggregator ────────────────────────────────────────────────────
/// @title hooks-factory aggregation lens
///
/// @notice read hooks and market data from a default factory, an explicit factory, or every active
///         factory discoverable through the ArchController.
///
/// @dev aggregate results preserve first-seen controller and factory order. address-based variants
///      deduplicate across factories unless the function name explicitly keeps the factory.
interface IMarketLensAggregator {
  // ░░▒▒▓▓██ [ BORROWER HOOKS DATA ] ──────────────────────────────────────────

  // ┌─ getHooksDataForBorrower ─────
  /// @notice return borrower-facing hooks data from the default factory.
  function getHooksDataForBorrower(address borrower) external view returns (HooksDataForBorrower memory data);

  // ┌─ getHooksDataForBorrower ─────
  /// @notice return borrower-facing hooks data from `hooksFactoryAddress`.
  function getHooksDataForBorrower(
    address hooksFactoryAddress,
    address borrower
  )
    external
    view
    returns (HooksDataForBorrower memory data);

  // ┌─ getAggregatedHooksDataForBorrower ─────
  /// @notice combine hooks data across every active hooks factory.
  function getAggregatedHooksDataForBorrower(address borrower) external view returns (HooksDataForBorrower memory data);

  // ░░▒▒▓▓██ [ HOOKS INSTANCES ] ──────────────────────────────────────────────

  // ┌─ getHooksInstancesForBorrower ─────
  /// @notice return instances indexed to `borrower` by the default factory.
  function getHooksInstancesForBorrower(address borrower) external view returns (HooksInstanceData[] memory data);

  // ┌─ getHooksInstancesForBorrower ─────
  /// @notice return instances indexed to `borrower` by `hooksFactoryAddress`.
  function getHooksInstancesForBorrower(
    address hooksFactoryAddress,
    address borrower
  )
    external
    view
    returns (HooksInstanceData[] memory data);

  // ┌─ getAggregatedHooksInstancesForBorrower ─────
  /// @notice combine instances across active factories, deduplicated by instance address.
  function getAggregatedHooksInstancesForBorrower(address borrower)
    external
    view
    returns (HooksInstanceData[] memory data);

  // ░░▒▒▓▓██ [ HOOKS TEMPLATES ] ──────────────────────────────────────────────

  // ┌─ getHooksTemplateForBorrower ─────
  /// @notice return one template with default-factory fee readiness for `borrower`.
  function getHooksTemplateForBorrower(
    address borrower,
    address hooksTemplate
  )
    external
    view
    returns (HooksTemplateData memory data);

  // ┌─ getHooksTemplateForBorrower ─────
  /// @notice return one template with explicit-factory fee readiness for `borrower`.
  function getHooksTemplateForBorrower(
    address hooksFactoryAddress,
    address borrower,
    address hooksTemplate
  )
    external
    view
    returns (HooksTemplateData memory data);

  // ┌─ getHooksTemplatesForBorrower ─────
  /// @notice return selected default-factory templates with fee readiness for `borrower`.
  function getHooksTemplatesForBorrower(
    address borrower,
    address[] memory hooksTemplates
  )
    external
    view
    returns (HooksTemplateData[] memory data);

  // ┌─ getHooksTemplatesForBorrower ─────
  /// @notice return selected explicit-factory templates with fee readiness for `borrower`.
  function getHooksTemplatesForBorrower(
    address hooksFactoryAddress,
    address borrower,
    address[] memory hooksTemplates
  )
    external
    view
    returns (HooksTemplateData[] memory data);

  // ┌─ getAllHooksTemplatesForBorrower ─────
  /// @notice return every default-factory template with fee readiness for `borrower`.
  function getAllHooksTemplatesForBorrower(address borrower) external view returns (HooksTemplateData[] memory data);

  // ┌─ getAllHooksTemplatesForBorrower ─────
  /// @notice return every template from `hooksFactoryAddress` with readiness for `borrower`.
  function getAllHooksTemplatesForBorrower(
    address hooksFactoryAddress,
    address borrower
  )
    external
    view
    returns (HooksTemplateData[] memory data);

  // ┌─ getAggregatedAllHooksTemplatesForBorrower ─────
  /// @notice combine every template across active factories, deduplicated by template address.
  function getAggregatedAllHooksTemplatesForBorrower(address borrower)
    external
    view
    returns (HooksTemplateData[] memory data);

  // ┌─ getAggregatedHooksTemplatesForBorrowerWithFactory ─────
  /// @notice return one row per `(factory, template)` pair without cross-factory deduplication.
  function getAggregatedHooksTemplatesForBorrowerWithFactory(address borrower)
    external
    view
    returns (FactoryScopedHooksTemplateData[] memory data);

  // ░░▒▒▓▓██ [ TEMPLATE MARKETS ] ─────────────────────────────────────────────

  // ┌─ getMarketsForHooksTemplateCount ─────
  /// @notice return the default factory's market count for `hooksTemplate`.
  function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256 count);

  // ┌─ getMarketsForHooksTemplateCount ─────
  /// @notice return `hooksFactoryAddress`'s market count for `hooksTemplate`.
  function getMarketsForHooksTemplateCount(
    address hooksFactoryAddress,
    address hooksTemplate
  )
    external
    view
    returns (uint256 count);

  // ┌─ getAggregatedMarketsForHooksTemplateCount ─────
  /// @notice sum unique markets for `hooksTemplate` across active factories.
  function getAggregatedMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256 count);

  // ┌─ getPaginatedMarketsDataForHooksTemplate ─────
  /// @notice return compatibility data for a default-factory market slice.
  ///
  /// @dev `start` is inclusive and `end` is exclusive; the factory clamps the end to its count.
  function getPaginatedMarketsDataForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (MarketData[] memory data);

  // ┌─ getPaginatedMarketsDataForHooksTemplate ─────
  /// @notice return compatibility data for an explicit-factory market slice.
  function getPaginatedMarketsDataForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (MarketData[] memory data);

  // ┌─ getPaginatedMarketsDataV2ForHooksTemplate ─────
  /// @notice return V2.5 data for a default-factory market slice.
  function getPaginatedMarketsDataV2ForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (MarketDataV2_5[] memory data);

  // ┌─ getPaginatedMarketsDataV2ForHooksTemplate ─────
  /// @notice return V2.5 data for an explicit-factory market slice.
  function getPaginatedMarketsDataV2ForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (MarketDataV2_5[] memory data);

  // ┌─ getAllMarketsDataForHooksTemplate ─────
  /// @notice return compatibility data for every default-factory template market.
  function getAllMarketsDataForHooksTemplate(address hooksTemplate) external view returns (MarketData[] memory data);

  // ┌─ getAllMarketsDataForHooksTemplate ─────
  /// @notice return compatibility data for every matching market from `hooksFactoryAddress`.
  function getAllMarketsDataForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate
  )
    external
    view
    returns (MarketData[] memory data);

  // ┌─ getAllMarketsDataV2ForHooksTemplate ─────
  /// @notice return V2.5 data for every default-factory template market.
  function getAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
    external
    view
    returns (MarketDataV2_5[] memory data);

  // ┌─ getAllMarketsDataV2ForHooksTemplate ─────
  /// @notice return V2.5 data for every matching market from `hooksFactoryAddress`.
  function getAllMarketsDataV2ForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate
  )
    external
    view
    returns (MarketDataV2_5[] memory data);

  // ┌─ getAggregatedAllMarketsDataForHooksTemplate ─────
  /// @notice return every unique market for `hooksTemplate` across active factories.
  function getAggregatedAllMarketsDataForHooksTemplate(address hooksTemplate)
    external
    view
    returns (MarketData[] memory data);

  // ┌─ getAggregatedAllMarketsDataV2ForHooksTemplate ─────
  /// @notice return V2.5 data for every unique market across active factories.
  function getAggregatedAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
    external
    view
    returns (MarketDataV2_5[] memory data);
}
