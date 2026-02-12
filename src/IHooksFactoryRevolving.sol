// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import './IHooksFactory.sol';
import './interfaces/WildcatStructsAndEnums.sol';

interface IHooksFactoryRevolving is IHooksFactoryEventsAndErrors {
  function archController() external view returns (address);

  function sanctionsSentinel() external view returns (address);

  function marketInitCodeStorage() external view returns (address);

  function marketInitCodeHash() external view returns (uint256);

  /// @dev Set-up function to register the factory as a controller with the arch-controller.
  ///      This enables the factory to register new markets.
  function registerWithArchController() external;

  function name() external view returns (string memory);

  // ========================================================================== //
  //                               Hooks Templates                              //
  // ========================================================================== //

  function addHooksTemplate(
    address hooksTemplate,
    string calldata name,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external;

  function updateHooksTemplateFees(
    address hooksTemplate,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external;

  function disableHooksTemplate(address hooksTemplate) external;

  function getHooksTemplateDetails(
    address hooksTemplate
  ) external view returns (HooksTemplate memory);

  function isHooksTemplate(address hooksTemplate) external view returns (bool);

  function getHooksTemplates() external view returns (address[] memory);

  function getHooksTemplates(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr);

  function getHooksTemplatesCount() external view returns (uint256);

  function getMarketsForHooksTemplate(
    address hooksTemplate
  ) external view returns (address[] memory);

  function getMarketsForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr);

  function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256);

  // ========================================================================== //
  //                               Hooks Instances                              //
  // ========================================================================== //

  function deployHooksInstance(
    address hooksTemplate,
    bytes calldata constructorArgs
  ) external returns (address hooksDeployment);

  function getHooksInstancesForBorrower(address borrower) external view returns (address[] memory);

  function getHooksInstancesCountForBorrower(address borrower) external view returns (uint256);

  function isHooksInstance(address hooks) external view returns (bool);

  function getHooksTemplateForInstance(address hooks) external view returns (address);

  // ========================================================================== //
  //                                   Markets                                  //
  // ========================================================================== //

  function getMarketsForHooksInstance(
    address hooksInstance
  ) external view returns (address[] memory);

  function getMarketsForHooksInstance(
    address hooksInstance,
    uint256 start,
    uint256 len
  ) external view returns (address[] memory arr);

  function getMarketsForHooksInstanceCount(address hooksInstance) external view returns (uint256);

  function getMarketParameters() external view returns (MarketParameters memory parameters);

  /// @dev Deploy a revolving market with an existing hooks deployment.
  ///
  ///      `hooksData` is hook-owned data forwarded unchanged to hooks callbacks.
  ///      `marketData` is factory-owned data decoded by this factory.
  function deployMarket(
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes calldata marketData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external returns (address market);

  /// @dev Deploy hooks for an approved template, then deploy a revolving market.
  function deployMarketAndHooks(
    address hooksTemplate,
    bytes calldata hooksConstructorArgs,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes calldata marketData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external returns (address market, address hooks);

  function computeMarketAddress(bytes32 salt) external view returns (address);

  function pushProtocolFeeBipsUpdates(
    address hooksTemplate,
    uint marketStartIndex,
    uint marketEndIndex
  ) external;

  function pushProtocolFeeBipsUpdates(address hooksTemplate) external;
}
