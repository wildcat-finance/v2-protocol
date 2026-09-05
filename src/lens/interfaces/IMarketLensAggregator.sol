// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../FactoryScopedHooksTemplateData.sol';
import '../HooksDataForBorrower.sol';
import '../HooksInstanceData.sol';
import '../HooksTemplateData.sol';
import '../MarketData.sol';

/// @title hooks-factory aggregation lens
/// @notice reads hooks and market data from a default factory, an explicit factory, or every active
///         factory discoverable through the ArchController.
/// @dev aggregate results preserve first-seen controller and factory order. address-based variants
///      deduplicate across factories unless the function name explicitly keeps the factory.
interface IMarketLensAggregator {
  /// @notice returns borrower-facing hooks data from the default factory.
  function getHooksDataForBorrower(
    address borrower
  ) external view returns (HooksDataForBorrower memory data);

  /// @notice returns borrower-facing hooks data from `hooksFactoryAddress`.
  function getHooksDataForBorrower(
    address hooksFactoryAddress,
    address borrower
  ) external view returns (HooksDataForBorrower memory data);

  /// @notice combines hooks data across every active hooks factory.
  function getAggregatedHooksDataForBorrower(
    address borrower
  ) external view returns (HooksDataForBorrower memory data);

  /// @notice returns instances indexed to `borrower` by the default factory.
  function getHooksInstancesForBorrower(
    address borrower
  ) external view returns (HooksInstanceData[] memory data);

  /// @notice returns instances indexed to `borrower` by `hooksFactoryAddress`.
  function getHooksInstancesForBorrower(
    address hooksFactoryAddress,
    address borrower
  ) external view returns (HooksInstanceData[] memory data);

  /// @notice combines instances across active factories, deduplicated by instance address.
  function getAggregatedHooksInstancesForBorrower(
    address borrower
  ) external view returns (HooksInstanceData[] memory data);

  /// @notice returns one template with default-factory fee readiness for `borrower`.
  function getHooksTemplateForBorrower(
    address borrower,
    address hooksTemplate
  ) external view returns (HooksTemplateData memory data);

  /// @notice returns one template with explicit-factory fee readiness for `borrower`.
  function getHooksTemplateForBorrower(
    address hooksFactoryAddress,
    address borrower,
    address hooksTemplate
  ) external view returns (HooksTemplateData memory data);

  /// @notice returns selected default-factory templates with fee readiness for `borrower`.
  function getHooksTemplatesForBorrower(
    address borrower,
    address[] memory hooksTemplates
  ) external view returns (HooksTemplateData[] memory data);

  /// @notice returns selected explicit-factory templates with fee readiness for `borrower`.
  function getHooksTemplatesForBorrower(
    address hooksFactoryAddress,
    address borrower,
    address[] memory hooksTemplates
  ) external view returns (HooksTemplateData[] memory data);

  /// @notice returns every default-factory template with fee readiness for `borrower`.
  function getAllHooksTemplatesForBorrower(
    address borrower
  ) external view returns (HooksTemplateData[] memory data);

  /// @notice returns every template from `hooksFactoryAddress` with readiness for `borrower`.
  function getAllHooksTemplatesForBorrower(
    address hooksFactoryAddress,
    address borrower
  ) external view returns (HooksTemplateData[] memory data);

  /// @notice combines every template across active factories, deduplicated by template address.
  function getAggregatedAllHooksTemplatesForBorrower(
    address borrower
  ) external view returns (HooksTemplateData[] memory data);

  /// @notice returns one row per `(factory, template)` pair without cross-factory deduplication.
  function getAggregatedHooksTemplatesForBorrowerWithFactory(
    address borrower
  ) external view returns (FactoryScopedHooksTemplateData[] memory data);

  /// @notice returns the default factory's market count for `hooksTemplate`.
  function getMarketsForHooksTemplateCount(
    address hooksTemplate
  ) external view returns (uint256 count);

  /// @notice returns `hooksFactoryAddress`'s market count for `hooksTemplate`.
  function getMarketsForHooksTemplateCount(
    address hooksFactoryAddress,
    address hooksTemplate
  ) external view returns (uint256 count);

  /// @notice sums unique markets for `hooksTemplate` across active factories.
  function getAggregatedMarketsForHooksTemplateCount(
    address hooksTemplate
  ) external view returns (uint256 count);

  /// @notice returns compatibility data for a default-factory market slice.
  /// @dev `start` is inclusive and `end` is exclusive; the factory clamps the end to its count.
  function getPaginatedMarketsDataForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view returns (MarketData[] memory data);

  /// @notice returns compatibility data for an explicit-factory market slice.
  function getPaginatedMarketsDataForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view returns (MarketData[] memory data);

  /// @notice returns V2.5 data for a default-factory market slice.
  function getPaginatedMarketsDataV2ForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view returns (MarketDataV2_5[] memory data);

  /// @notice returns V2.5 data for an explicit-factory market slice.
  function getPaginatedMarketsDataV2ForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view returns (MarketDataV2_5[] memory data);

  /// @notice returns compatibility data for every default-factory template market.
  function getAllMarketsDataForHooksTemplate(
    address hooksTemplate
  ) external view returns (MarketData[] memory data);

  /// @notice returns compatibility data for every matching market from `hooksFactoryAddress`.
  function getAllMarketsDataForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate
  ) external view returns (MarketData[] memory data);

  /// @notice returns V2.5 data for every default-factory template market.
  function getAllMarketsDataV2ForHooksTemplate(
    address hooksTemplate
  ) external view returns (MarketDataV2_5[] memory data);

  /// @notice returns V2.5 data for every matching market from `hooksFactoryAddress`.
  function getAllMarketsDataV2ForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate
  ) external view returns (MarketDataV2_5[] memory data);

  /// @notice returns every unique market for `hooksTemplate` across active factories.
  function getAggregatedAllMarketsDataForHooksTemplate(
    address hooksTemplate
  ) external view returns (MarketData[] memory data);

  /// @notice returns V2.5 data for every unique market across active factories.
  function getAggregatedAllMarketsDataV2ForHooksTemplate(
    address hooksTemplate
  ) external view returns (MarketDataV2_5[] memory data);
}
