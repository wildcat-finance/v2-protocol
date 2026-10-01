// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // IHooksFactoryRevolving
// ║  ██▀▀     ▀▀██   Revolving factory registration, hooks lifecycle, and deployment.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SETUP
// ║  registerWithArchController()
// ║  archController()
// ║  name()
// ║  sanctionsSentinel()
// ║  wrapperFactory()
// ║  borrowerIdentityRegistry()
// ║  marketInitCodeStorage()
// ║  marketInitCodeHash()
// ║
// ║  HOOKS TEMPLATES
// ║  addHooksTemplate(...)
// ║  disableHooksTemplate(...)
// ║
// ║  TEMPLATE FEES
// ║  updateHooksTemplateFees(...)
// ║  pushProtocolFeeBipsUpdates(...)
// ║  pushProtocolFeeBipsUpdates(...)
// ║
// ║  TEMPLATE QUERIES
// ║  getHooksTemplateDetails(...)
// ║  getHooksTemplateInitCodeHash(...)
// ║  isHooksTemplate(...)
// ║  getHooksTemplates()
// ║  getHooksTemplates(...)
// ║  getHooksTemplatesCount()
// ║
// ║  HOOKS DEPLOYMENT
// ║  deployHooksInstance(...)
// ║  getHooksInstanceDeploymentNonce(...)
// ║  isHooksInstance(...)
// ║  getHooksTemplateForInstance(...)
// ║
// ║  HOOKS ADMINISTRATION
// ║  onHooksAdministratorTransferred(...)
// ║  getHooksAdministrator(...)
// ║  getHooksInstancesForAdministrator(...)
// ║  getHooksInstancesForAdministrator(...)
// ║  getHooksInstancesCountForAdministrator(...)
// ║  getHooksInstancesForBorrower(...)
// ║  getHooksInstancesCountForBorrower(...)
// ║
// ║  MARKET DEPLOYMENT
// ║  deployMarket(...)
// ║  deployMarketAndHooks(...)
// ║  computeMarketAddress(...)
// ║
// ║  CONSTRUCTOR PARAMETERS
// ║  getMarketParameters()
// ║  getRevolvingMarketCommitmentFeeBips()
// ║
// ║  MARKET QUERIES
// ║  getMarketsForHooksTemplate(...)
// ║  getMarketsForHooksTemplate(...)
// ║  getMarketsForHooksTemplateCount(...)
// ║  getMarketsForHooksInstance(...)
// ║  getMarketsForHooksInstance(...)
// ║  getMarketsForHooksInstanceCount(...)
// ╚═════

import './IHooksFactory.sol';
import './interfaces/WildcatStructsAndEnums.sol';

// ┌─ IHooksFactoryRevolving ───────────────────────────────────────────────────
/// @title Wildcat revolving hooks factory
///
/// @notice standard hooks-template and instance registry with revolving-market deployment data.
///
/// @dev `marketData` belongs to the factory, not the hooks instance. the current encoding is
///      `abi.encode(uint8(1), uint16 commitmentFeeBips)`.
interface IHooksFactoryRevolving is IHooksFactoryEventsAndErrors {
  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev `marketData` does not have the expected static encoding length.
  error InvalidMarketData();

  /// @dev `marketData` uses a version this factory does not understand.
  error UnsupportedMarketDataVersion();

  /// @dev the commitment fee exceeds 10,000 bips.
  error InvalidCommitmentFeeBips();

  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  /// @notice emitted with the fixed commitment fee captured by a new revolving market.
  event RevolvingMarketDeployed(address indexed market, uint256 commitmentFeeBips);

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ registerWithArchController ─────
  /// @notice registers this factory as an ArchController controller.
  ///
  /// @dev permissionless to trigger once this contract is an approved controller factory.
  function registerWithArchController() external;

  // ┌─ archController ─────
  /// @notice ArchController that authorizes this factory and receives market registrations.
  function archController() external view returns (address);

  // ┌─ name ─────
  /// @notice stable factory name used by discovery tooling.
  function name() external view returns (string memory);

  // ┌─ sanctionsSentinel ─────
  /// @notice sanctions sentinel written into newly deployed markets.
  function sanctionsSentinel() external view returns (address);

  // ┌─ wrapperFactory ─────
  /// @notice wrapper factory written into newly deployed markets.
  function wrapperFactory() external view returns (address);

  // ┌─ borrowerIdentityRegistry ─────
  /// @notice registry used to resolve callers to registered borrower principals.
  function borrowerIdentityRegistry() external view returns (address);

  // ┌─ marketInitCodeStorage ─────
  /// @notice contract holding the revolving-market creation code.
  function marketInitCodeStorage() external view returns (address);

  // ┌─ marketInitCodeHash ─────
  /// @notice hash of the revolving-market initcode held by `marketInitCodeStorage`.
  function marketInitCodeHash() external view returns (uint256);

  // ░░▒▒▓▓██ [ HOOKS TEMPLATES ] ──────────────────────────────────────────────

  // ┌─ addHooksTemplate ─────
  /// @notice registers a hooks template and its fee configuration.
  ///
  /// @dev only the ArchController owner can call this. initCodeHash must come from the compiled
  ///      artifact, before per-instance constructor arguments are appended.
  function addHooksTemplate(
    address hooksTemplate,
    string calldata name,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips,
    bytes32 initCodeHash
  )
    external;

  // ┌─ disableHooksTemplate ─────
  /// @notice disables new instance deployments from `hooksTemplate`.
  ///
  /// @dev only the ArchController owner can call this. existing instances may still deploy markets;
  ///      there is no re-enable path.
  function disableHooksTemplate(address hooksTemplate) external;

  // ░░▒▒▓▓██ [ TEMPLATE FEES ] ────────────────────────────────────────────────

  // ┌─ updateHooksTemplateFees ─────
  /// @notice updates the fees used by future markets for `hooksTemplate`.
  ///
  /// @dev only the ArchController owner can call this. existing market protocol fees change only
  ///      after a fee-push call.
  function updateHooksTemplateFees(
    address hooksTemplate,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  )
    external;

  // ┌─ pushProtocolFeeBipsUpdates ─────
  /// @notice pushes a template's current protocol fee to markets in an index range.
  ///
  /// @dev permissionless. `marketEndIndex` is clamped to the market count; after that, equal bounds
  ///      are a no-op and `marketStartIndex > marketEndIndex` reverts. closed markets are skipped;
  ///      a failed closure query or fee update reverts the whole call.
  function pushProtocolFeeBipsUpdates(address hooksTemplate, uint marketStartIndex, uint marketEndIndex) external;

  // ┌─ pushProtocolFeeBipsUpdates ─────
  /// @notice pushes a template's current protocol fee to all of its markets.
  ///
  /// @dev permissionless. closed markets are skipped; any other market failure reverts the call.
  function pushProtocolFeeBipsUpdates(address hooksTemplate) external;

  // ░░▒▒▓▓██ [ TEMPLATE QUERIES ] ─────────────────────────────────────────────

  // ┌─ getHooksTemplateDetails ─────
  /// @notice returns the factory metadata for `hooksTemplate`.
  function getHooksTemplateDetails(address hooksTemplate) external view returns (HooksTemplate memory);

  // ┌─ getHooksTemplateInitCodeHash ─────
  /// @notice registered creation-code hash for a template, or zero if it is unknown.
  function getHooksTemplateInitCodeHash(address hooksTemplate) external view returns (bytes32);

  // ┌─ isHooksTemplate ─────
  /// @notice returns whether `hooksTemplate` was registered, including if it is disabled.
  function isHooksTemplate(address hooksTemplate) external view returns (bool);

  // ┌─ getHooksTemplates ─────
  /// @notice returns all registered hooks templates in insertion order.
  function getHooksTemplates() external view returns (address[] memory);

  // ┌─ getHooksTemplates ─────
  /// @notice returns templates in `[start, min(end, count))`.
  function getHooksTemplates(uint256 start, uint256 end) external view returns (address[] memory arr);

  // ┌─ getHooksTemplatesCount ─────
  /// @notice returns the number of registered hooks templates.
  function getHooksTemplatesCount() external view returns (uint256);

  // ░░▒▒▓▓██ [ HOOKS DEPLOYMENT ] ─────────────────────────────────────────────

  // ┌─ deployHooksInstance ─────
  /// @notice deploys a hooks instance administered by the caller's resolved principal.
  ///
  /// @dev this does not charge an origination fee.
  function deployHooksInstance(
    address hooksTemplate,
    bytes calldata constructorArgs
  )
    external
    returns (address hooksDeployment);

  // ┌─ getHooksInstanceDeploymentNonce ─────
  /// @notice next CREATE2 deployment nonce for `administrator`.
  function getHooksInstanceDeploymentNonce(address administrator) external view returns (uint256);

  // ┌─ isHooksInstance ─────
  /// @notice returns whether `hooks` was deployed by this factory.
  function isHooksInstance(address hooks) external view returns (bool);

  // ┌─ getHooksTemplateForInstance ─────
  /// @notice returns the template used to deploy `hooks`, or zero if it is unknown.
  function getHooksTemplateForInstance(address hooks) external view returns (address);

  // ░░▒▒▓▓██ [ HOOKS ADMINISTRATION ] ─────────────────────────────────────────

  // ┌─ onHooksAdministratorTransferred ─────
  /// @notice updates the factory index after a hooks instance accepts an administrator transfer.
  ///
  /// @dev only the hooks instance itself can make a valid call.
  function onHooksAdministratorTransferred(address previousAdministrator, address newAdministrator) external;

  // ┌─ getHooksAdministrator ─────
  /// @notice returns the administrator tracked by the factory for `hooks`.
  function getHooksAdministrator(address hooks) external view returns (address);

  // ┌─ getHooksInstancesForAdministrator ─────
  /// @notice returns every hooks instance currently indexed to `administrator`.
  function getHooksInstancesForAdministrator(address administrator) external view returns (address[] memory);

  // ┌─ getHooksInstancesForAdministrator ─────
  /// @notice returns administrator instances in `[start, min(end, count))`.
  function getHooksInstancesForAdministrator(
    address administrator,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (address[] memory);

  // ┌─ getHooksInstancesCountForAdministrator ─────
  /// @notice returns the number of hooks instances indexed to `administrator`.
  function getHooksInstancesCountForAdministrator(address administrator) external view returns (uint256);

  // ┌─ getHooksInstancesForBorrower ─────
  /// @notice compatibility alias for `getHooksInstancesForAdministrator`.
  function getHooksInstancesForBorrower(address borrower) external view returns (address[] memory);

  // ┌─ getHooksInstancesCountForBorrower ─────
  /// @notice compatibility alias for `getHooksInstancesCountForAdministrator`.
  function getHooksInstancesCountForBorrower(address borrower) external view returns (uint256);

  // ░░▒▒▓▓██ [ MARKET DEPLOYMENT ] ────────────────────────────────────────────

  // ┌─ deployMarket ─────
  /// @notice deploys a revolving market using the existing instance in `parameters.hooks`.
  ///
  /// @dev the caller becomes the operational borrower. its resolved principal is passed to the
  ///      hooks and market, fee arguments must match the template, and `salt` binds to the caller.
  ///
  /// @param hooksData  opaque data forwarded to the hooks instance.
  /// @param marketData `abi.encode(uint8 version, uint16 commitmentFeeBips)`; current version is 1.
  function deployMarket(
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes calldata marketData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  )
    external
    returns (address market);

  // ┌─ deployMarketAndHooks ─────
  /// @notice deploys a principal-administered hooks instance and a revolving market using it.
  ///
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
  )
    external
    returns (address market, address hooks);

  // ┌─ computeMarketAddress ─────
  /// @notice returns the CREATE2 market address for `salt` and this factory's initcode.
  ///
  /// @dev the first 20 bytes must name the nonzero caller. borrower accounts use the account
  ///      address here, not the resolved principal.
  function computeMarketAddress(bytes32 salt) external view returns (address);

  // ░░▒▒▓▓██ [ CONSTRUCTOR PARAMETERS ] ───────────────────────────────────────

  // ┌─ getMarketParameters ─────
  /// @notice returns constructor parameters for the market currently being deployed.
  ///
  /// @dev only valid during the market constructor call. outside deployment, decoding the empty
  ///      transient parameter array reverts.
  function getMarketParameters() external view returns (MarketParameters memory parameters);

  // ┌─ getRevolvingMarketCommitmentFeeBips ─────
  /// @notice commitment fee for the revolving market currently being constructed.
  ///
  /// @dev only valid during market deployment; it reverts after transient state is cleared.
  function getRevolvingMarketCommitmentFeeBips() external view returns (uint16);

  // ░░▒▒▓▓██ [ MARKET QUERIES ] ───────────────────────────────────────────────

  // ┌─ getMarketsForHooksTemplate ─────
  /// @notice returns every market deployed from any instance of `hooksTemplate`.
  function getMarketsForHooksTemplate(address hooksTemplate) external view returns (address[] memory);

  // ┌─ getMarketsForHooksTemplate ─────
  /// @notice returns template markets in `[start, min(end, count))`.
  function getMarketsForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (address[] memory arr);

  // ┌─ getMarketsForHooksTemplateCount ─────
  /// @notice returns the number of markets deployed from `hooksTemplate`.
  function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256);

  // ┌─ getMarketsForHooksInstance ─────
  /// @notice returns every market attached to `hooksInstance`.
  function getMarketsForHooksInstance(address hooksInstance) external view returns (address[] memory);

  // ┌─ getMarketsForHooksInstance ─────
  /// @notice returns instance markets in `[start, min(end, count))`.
  function getMarketsForHooksInstance(
    address hooksInstance,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (address[] memory arr);

  // ┌─ getMarketsForHooksInstanceCount ─────
  /// @notice returns the number of markets attached to `hooksInstance`.
  function getMarketsForHooksInstanceCount(address hooksInstance) external view returns (uint256);
}
