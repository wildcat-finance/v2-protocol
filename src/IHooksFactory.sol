// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import './access/IHooks.sol';
import './interfaces/WildcatStructsAndEnums.sol';

struct HooksTemplate {
  /// @dev Asset used to pay origination fee
  address originationFeeAsset;
  /// @dev Amount of `originationFeeAsset` paid to deploy a new market using
  ///      an instance of this template.
  uint80 originationFeeAmount;
  /// @dev Basis points paid on interest for markets deployed using hooks
  ///      based on this template
  uint16 protocolFeeBips;
  /// @dev Whether the template exists
  bool exists;
  /// @dev Whether the template is enabled
  bool enabled;
  /// @dev Index of the template address in the array of hooks templates
  uint24 index;
  /// @dev Address to pay origination and interest fees
  address feeRecipient;
  /// @dev Name of the template
  string name;
}

interface IHooksFactoryEventsAndErrors {
  error FeeMismatch();
  error NotApprovedBorrower();
  error HooksTemplateNotFound();
  error HooksTemplateNotAvailable();
  error HooksTemplateAlreadyExists();
  error DeploymentFailed();
  error HooksInstanceNotFound();
  error CallerNotArchControllerOwner();
  error InvalidFeeConfiguration();
  error SaltDoesNotContainSender();
  error MarketAlreadyExists();
  error MarketDeploymentAddressMismatch();
  error HooksInstanceAlreadyExists();
  error NameOrSymbolTooLong();
  error AssetBlacklisted();
  error SetProtocolFeeBipsFailed();
  error InvalidPaginationRange();
  error InvalidHooksAdministrator();
  error InvalidHooksInstanceAssociation();

  event HooksInstanceDeployed(
    address indexed hooksInstance,
    address indexed hooksTemplate,
    address indexed administrator
  );
  event HooksInstanceAdministratorTransferred(
    address indexed hooksInstance,
    address indexed previousAdministrator,
    address indexed newAdministrator
  );
  event HooksTemplateAdded(
    address hooksTemplate,
    string name,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  );
  event HooksTemplateDisabled(address hooksTemplate);
  event HooksTemplateFeesUpdated(
    address hooksTemplate,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  );

  event MarketDeployed(
    address indexed hooksTemplate,
    address indexed market,
    string name,
    string symbol,
    address asset,
    uint256 maxTotalSupply,
    uint256 annualInterestBips,
    uint256 delinquencyFeeBips,
    uint256 withdrawalBatchDuration,
    uint256 reserveRatioBips,
    uint256 delinquencyGracePeriod,
    HooksConfig hooks
  );
}

interface IHooksFactory is IHooksFactoryEventsAndErrors {
  function archController() external view returns (address);

  function sanctionsSentinel() external view returns (address);

  function wrapperFactory() external view returns (address);

  function borrowerIdentityRegistry() external view returns (address);

  function marketInitCodeStorage() external view returns (address);

  function marketInitCodeHash() external view returns (uint256);

  /// @dev Set-up function to register the factory as a controller with the arch-controller.
  ///      This enables the factory to register new markets.
  function registerWithArchController() external;

  function name() external view returns (string memory);

  // ========================================================================== //
  //                               Hooks Templates                              //
  // ========================================================================== //

  /// @dev Add a hooks template that stores the initcode for the template.
  ///
  ///      On success:
  ///      - Emits `HooksTemplateAdded` on success.
  ///      - Adds the template to the list of templates.
  ///      - Creates `HooksTemplate` struct with the given parameters mapped to the template address.
  ///
  ///      Reverts if:
  ///      - The caller is not the owner of the arch-controller.
  ///      - The template already exists.
  ///      - The fee settings are invalid.
  function addHooksTemplate(
    address hooksTemplate,
    string calldata name,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external;

  /// @dev Update the fees for a hooks template.
  ///
  ///      On success:
  ///      - Emits `HooksTemplateFeesUpdated` on success.
  ///      - Updates the fees for the `HooksTemplate` struct mapped to the template address.
  ///
  ///      Reverts if:
  ///      - The caller is not the owner of the arch-controller.
  ///      - The template does not exist.
  ///      - The fee settings are invalid.
  function updateHooksTemplateFees(
    address hooksTemplate,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external;

  /// @dev Disable a hooks template.
  ///
  ///      On success:
  ///      - Emits `HooksTemplateDisabled` on success.
  ///      - Disables the `HooksTemplate` struct mapped to the template address.
  ///
  ///      Reverts if:
  ///      - The caller is not the owner of the arch-controller.
  ///      - The template does not exist.
  function disableHooksTemplate(address hooksTemplate) external;

  /// @dev Get the name and fee configuration for an approved hooks template.
  function getHooksTemplateDetails(
    address hooksTemplate
  ) external view returns (HooksTemplate memory);

  /// @dev Check if a hooks template is approved.
  function isHooksTemplate(address hooksTemplate) external view returns (bool);

  /// @dev Get the list of approved hooks templates.
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

  /// @dev Deploy a hooks instance for an approved template with constructor args.
  ///
  ///      On success:
  ///      - Emits `HooksInstanceDeployed`.
  ///      - Deploys a new hooks instance with the given templates and constructor args.
  ///      - Maps the hooks instance to the template address.
  ///
  ///      Reverts if:
  ///      - The caller does not resolve to a registered principal.
  ///      - The template does not exist.
  ///      - The template is not enabled.
  ///      - The deployment fails.
  function deployHooksInstance(
    address hooksTemplate,
    bytes calldata constructorArgs
  ) external returns (address hooksDeployment);

  function getHooksAdministrator(address hooks) external view returns (address);

  function getHooksInstanceDeploymentNonce(address administrator) external view returns (uint256);

  function getHooksInstancesForAdministrator(
    address administrator
  ) external view returns (address[] memory);

  function getHooksInstancesForAdministrator(
    address administrator,
    uint256 start,
    uint256 end
  ) external view returns (address[] memory);

  function getHooksInstancesCountForAdministrator(
    address administrator
  ) external view returns (uint256);

  /// @dev Compatibility alias for `getHooksInstancesForAdministrator`.
  function getHooksInstancesForBorrower(address borrower) external view returns (address[] memory);

  /// @dev Compatibility alias for `getHooksInstancesCountForAdministrator`.
  function getHooksInstancesCountForBorrower(address borrower) external view returns (uint256);

  /// @dev Called by a hooks instance after accepting a two-step administrator transfer.
  function onHooksAdministratorTransferred(
    address previousAdministrator,
    address newAdministrator
  ) external;

  /// @dev Check if a hooks instance was deployed by the factory.
  function isHooksInstance(address hooks) external view returns (bool);

  /// @dev Get the template that was used to deploy a hooks instance.
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
    uint256 end
  ) external view returns (address[] memory arr);

  function getMarketsForHooksInstanceCount(address hooksInstance) external view returns (uint256);

  /// @dev Get the temporarily stored market parameters for a market that is
  ///      currently being deployed.
  function getMarketParameters() external view returns (MarketParameters memory parameters);

  /// @dev Deploy a market with an existing hooks deployment (in `parameters.hooks`)
  ///      The caller becomes the market borrower. Its resolved principal is supplied
  ///      to the hook and stored on the market.
  ///
  ///      On success:
  ///      - Pays the origination fee (if applicable).
  ///      - Calls `onCreateMarket` on the hooks contract.
  ///      - Deploys a new market with the given parameters.
  ///      - Emits `MarketDeployed`.
  ///
  ///      Reverts if:
  ///      - The caller does not resolve to a registered principal.
  ///      - The hooks instance does not exist.
  ///      - Payment of origination fee fails.
  ///      - The deployment fails.
  ///      - The call to `onCreateMarket` fails.
  ///      - `originationFeeAsset` does not match the hook template's
  ///      - `originationFeeAmount` does not match the hook template's
  function deployMarket(
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external returns (address market);

  /// @dev Deploy a principal-administered hooks instance, then deploy a new market owned by
  ///      the calling principal or registered account.
  ///      Will call `onCreateMarket` on the new hooks instance.
  function deployMarketAndHooks(
    address hooksTemplate,
    bytes calldata hooksConstructorArgs,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external returns (address market, address hooks);

  /// @dev Returns the CREATE2 market address for `salt` and this factory's init code.
  function computeMarketAddress(bytes32 salt) external view returns (address);

  /// @dev Push a template's current protocol fee bips to a market index range.
  ///      Reverts if the template is unknown, range is invalid or a market update fails.
  function pushProtocolFeeBipsUpdates(
    address hooksTemplate,
    uint marketStartIndex,
    uint marketEndIndex
  ) external;

  /// @dev Push a template's current protocol fee bips to all markets using it.
  function pushProtocolFeeBipsUpdates(address hooksTemplate) external;
}
