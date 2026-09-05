// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import './IHooksFactory.sol';
import './interfaces/WildcatStructsAndEnums.sol';

/// @title Wildcat revolving hooks factory
/// @notice standard hooks-template and instance registry with revolving-market deployment data.
/// @dev `marketData` belongs to the factory, not the hooks instance. the current encoding is
///      `abi.encode(uint8(1), uint16 commitmentFeeBips)`.
interface IHooksFactoryRevolving is IHooksFactoryEventsAndErrors {
  /// @dev `marketData` does not have the expected static encoding length.
  error InvalidMarketData();
  /// @dev `marketData` uses a version this factory does not understand.
  error UnsupportedMarketDataVersion();
  /// @dev the commitment fee exceeds 10,000 bips.
  error InvalidCommitmentFeeBips();

  /// @notice emitted with the fixed commitment fee captured by a new revolving market.
  event RevolvingMarketDeployed(address indexed market, uint256 commitmentFeeBips);

  /// @notice ArchController that authorizes this factory and receives market registrations.
  function archController() external view returns (address);

  /// @notice sanctions sentinel written into newly deployed markets.
  function sanctionsSentinel() external view returns (address);

  /// @notice wrapper factory written into newly deployed markets.
  function wrapperFactory() external view returns (address);

  /// @notice registry used to resolve callers to registered borrower principals.
  function borrowerIdentityRegistry() external view returns (address);

  /// @notice contract holding the revolving-market creation code.
  function marketInitCodeStorage() external view returns (address);

  /// @notice hash of the revolving-market initcode held by `marketInitCodeStorage`.
  function marketInitCodeHash() external view returns (uint256);

  /// @notice registers this factory as an ArchController controller.
  /// @dev permissionless to trigger once this contract is an approved controller factory.
  function registerWithArchController() external;

  /// @notice stable factory name used by discovery tooling.
  function name() external view returns (string memory);

  // ========================================================================== //
  //                               Hooks Templates                              //
  // ========================================================================== //

  /// @notice registers a hooks template and its fee configuration.
  /// @dev only the ArchController owner can call this.
  function addHooksTemplate(
    address hooksTemplate,
    string calldata name,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external;

  /// @notice updates the fees used by future markets for `hooksTemplate`.
  /// @dev only the ArchController owner can call this. existing market protocol fees change only
  ///      after a fee-push call.
  function updateHooksTemplateFees(
    address hooksTemplate,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external;

  /// @notice disables new instance deployments from `hooksTemplate`.
  /// @dev only the ArchController owner can call this. existing instances may still deploy markets;
  ///      there is no re-enable path.
  function disableHooksTemplate(address hooksTemplate) external;

  /// @notice returns the factory metadata for `hooksTemplate`.
  function getHooksTemplateDetails(
    address hooksTemplate
  ) external view returns (HooksTemplate memory);

  /// @notice returns whether `hooksTemplate` was registered, including if it is disabled.
  function isHooksTemplate(address hooksTemplate) external view returns (bool);

  /// @notice returns all registered hooks templates in insertion order.
  function getHooksTemplates() external view returns (address[] memory);

  /// @notice returns templates in `[start, min(end, count))`.
  function getHooksTemplates(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr);

  /// @notice returns the number of registered hooks templates.
  function getHooksTemplatesCount() external view returns (uint256);

  /// @notice returns every market deployed from any instance of `hooksTemplate`.
  function getMarketsForHooksTemplate(
    address hooksTemplate
  ) external view returns (address[] memory);

  /// @notice returns template markets in `[start, min(end, count))`.
  function getMarketsForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr);

  /// @notice returns the number of markets deployed from `hooksTemplate`.
  function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256);

  // ========================================================================== //
  //                               Hooks Instances                              //
  // ========================================================================== //

  /// @notice deploys a hooks instance administered by the caller's resolved principal.
  /// @dev this does not charge an origination fee.
  function deployHooksInstance(
    address hooksTemplate,
    bytes calldata constructorArgs
  ) external returns (address hooksDeployment);

  /// @notice returns the administrator tracked by the factory for `hooks`.
  function getHooksAdministrator(address hooks) external view returns (address);

  /// @notice next CREATE2 deployment nonce for `administrator`.
  function getHooksInstanceDeploymentNonce(address administrator) external view returns (uint256);

  /// @notice returns every hooks instance currently indexed to `administrator`.
  function getHooksInstancesForAdministrator(
    address administrator
  ) external view returns (address[] memory);

  /// @notice returns administrator instances in `[start, min(end, count))`.
  function getHooksInstancesForAdministrator(
    address administrator,
    uint256 start,
    uint256 end
  ) external view returns (address[] memory);

  /// @notice returns the number of hooks instances indexed to `administrator`.
  function getHooksInstancesCountForAdministrator(
    address administrator
  ) external view returns (uint256);

  /// @notice compatibility alias for `getHooksInstancesForAdministrator`.
  function getHooksInstancesForBorrower(address borrower) external view returns (address[] memory);

  /// @notice compatibility alias for `getHooksInstancesCountForAdministrator`.
  function getHooksInstancesCountForBorrower(address borrower) external view returns (uint256);

  /// @notice updates the factory index after a hooks instance accepts an administrator transfer.
  /// @dev only the hooks instance itself can make a valid call.
  function onHooksAdministratorTransferred(
    address previousAdministrator,
    address newAdministrator
  ) external;

  /// @notice returns whether `hooks` was deployed by this factory.
  function isHooksInstance(address hooks) external view returns (bool);

  /// @notice returns the template used to deploy `hooks`, or zero if it is unknown.
  function getHooksTemplateForInstance(address hooks) external view returns (address);

  // ========================================================================== //
  //                                   Markets                                  //
  // ========================================================================== //

  /// @notice returns every market attached to `hooksInstance`.
  function getMarketsForHooksInstance(
    address hooksInstance
  ) external view returns (address[] memory);

  /// @notice returns instance markets in `[start, min(end, count))`.
  function getMarketsForHooksInstance(
    address hooksInstance,
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr);

  /// @notice returns the number of markets attached to `hooksInstance`.
  function getMarketsForHooksInstanceCount(address hooksInstance) external view returns (uint256);

  /// @notice returns constructor parameters for the market currently being deployed.
  /// @dev only valid during the market constructor call. outside deployment, decoding the empty
  ///      transient parameter array reverts.
  function getMarketParameters() external view returns (MarketParameters memory parameters);

  /// @notice commitment fee for the revolving market currently being constructed.
  /// @dev only valid during market deployment; it reverts after transient state is cleared.
  function getRevolvingMarketCommitmentFeeBips() external view returns (uint16);

  /// @notice deploys a revolving market using the existing instance in `parameters.hooks`.
  /// @dev the caller becomes the operational borrower. its resolved principal is passed to the
  ///      hooks and market, fee arguments must match the template, and `salt` binds to the caller.
  /// @param hooksData opaque data forwarded to the hooks instance.
  /// @param marketData `abi.encode(uint8 version, uint16 commitmentFeeBips)`; current version is 1.
  function deployMarket(
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes calldata marketData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external returns (address market);

  /// @notice deploys a principal-administered hooks instance and a revolving market using it.
  /// @dev both deployments are atomic. `marketData` uses the same encoding as `deployMarket`.
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

  /// @notice returns the CREATE2 market address for `salt` and this factory's initcode.
  /// @dev the first 20 bytes must name the nonzero caller. borrower accounts use the account
  ///      address here, not the resolved principal.
  function computeMarketAddress(bytes32 salt) external view returns (address);

  /// @notice pushes a template's current protocol fee to markets in an index range.
  /// @dev permissionless. `marketEndIndex` is clamped to the market count; after that, equal bounds
  ///      are a no-op and `marketStartIndex > marketEndIndex` reverts.
  function pushProtocolFeeBipsUpdates(
    address hooksTemplate,
    uint marketStartIndex,
    uint marketEndIndex
  ) external;

  /// @notice pushes a template's current protocol fee to all of its markets.
  /// @dev permissionless. one market failure reverts the whole call.
  function pushProtocolFeeBipsUpdates(address hooksTemplate) external;
}
