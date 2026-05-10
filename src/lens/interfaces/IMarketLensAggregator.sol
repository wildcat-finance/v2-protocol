// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "../FactoryScopedHooksTemplateData.sol";
import "../HooksDataForBorrower.sol";
import "../HooksInstanceData.sol";
import "../HooksTemplateData.sol";
import "../MarketData.sol";

interface IMarketLensAggregator {
    function getHooksDataForBorrower(address borrower) external view returns (HooksDataForBorrower memory data);

    function getHooksDataForBorrower(address hooksFactoryAddress, address borrower)
        external
        view
        returns (HooksDataForBorrower memory data);

    function getAggregatedHooksDataForBorrower(address borrower)
        external
        view
        returns (HooksDataForBorrower memory data);

    function getHooksInstancesForBorrower(address borrower) external view returns (HooksInstanceData[] memory data);

    function getHooksInstancesForBorrower(address hooksFactoryAddress, address borrower)
        external
        view
        returns (HooksInstanceData[] memory data);

    function getAggregatedHooksInstancesForBorrower(address borrower)
        external
        view
        returns (HooksInstanceData[] memory data);

    function getHooksTemplateForBorrower(address borrower, address hooksTemplate)
        external
        view
        returns (HooksTemplateData memory data);

    function getHooksTemplateForBorrower(address hooksFactoryAddress, address borrower, address hooksTemplate)
        external
        view
        returns (HooksTemplateData memory data);

    function getHooksTemplatesForBorrower(address borrower, address[] memory hooksTemplates)
        external
        view
        returns (HooksTemplateData[] memory data);

    function getHooksTemplatesForBorrower(
        address hooksFactoryAddress,
        address borrower,
        address[] memory hooksTemplates
    ) external view returns (HooksTemplateData[] memory data);

    function getAllHooksTemplatesForBorrower(address borrower) external view returns (HooksTemplateData[] memory data);

    function getAllHooksTemplatesForBorrower(address hooksFactoryAddress, address borrower)
        external
        view
        returns (HooksTemplateData[] memory data);

    function getAggregatedAllHooksTemplatesForBorrower(address borrower)
        external
        view
        returns (HooksTemplateData[] memory data);

    function getAggregatedHooksTemplatesForBorrowerWithFactory(address borrower)
        external
        view
        returns (FactoryScopedHooksTemplateData[] memory data);

    function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256 count);

    function getMarketsForHooksTemplateCount(address hooksFactoryAddress, address hooksTemplate)
        external
        view
        returns (uint256 count);

    function getAggregatedMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256 count);

    function getPaginatedMarketsDataForHooksTemplate(address hooksTemplate, uint256 start, uint256 end)
        external
        view
        returns (MarketData[] memory data);

    function getPaginatedMarketsDataForHooksTemplate(
        address hooksFactoryAddress,
        address hooksTemplate,
        uint256 start,
        uint256 end
    ) external view returns (MarketData[] memory data);

    function getPaginatedMarketsDataV2ForHooksTemplate(address hooksTemplate, uint256 start, uint256 end)
        external
        view
        returns (MarketDataV2_5[] memory data);

    function getPaginatedMarketsDataV2ForHooksTemplate(
        address hooksFactoryAddress,
        address hooksTemplate,
        uint256 start,
        uint256 end
    ) external view returns (MarketDataV2_5[] memory data);

    function getAllMarketsDataForHooksTemplate(address hooksTemplate) external view returns (MarketData[] memory data);

    function getAllMarketsDataForHooksTemplate(address hooksFactoryAddress, address hooksTemplate)
        external
        view
        returns (MarketData[] memory data);

    function getAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
        external
        view
        returns (MarketDataV2_5[] memory data);

    function getAllMarketsDataV2ForHooksTemplate(address hooksFactoryAddress, address hooksTemplate)
        external
        view
        returns (MarketDataV2_5[] memory data);

    function getAggregatedAllMarketsDataForHooksTemplate(address hooksTemplate)
        external
        view
        returns (MarketData[] memory data);

    function getAggregatedAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
        external
        view
        returns (MarketDataV2_5[] memory data);
}
