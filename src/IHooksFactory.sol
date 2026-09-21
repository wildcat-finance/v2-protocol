// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import './access/IHooks.sol';
import './interfaces/WildcatStructsAndEnums.sol';
import './types/RoleProvider.sol';

/// @notice factory-owned metadata and fees for one approved hooks template.
struct HooksTemplate {
  /// @dev asset used to pay the origination fee.
  address originationFeeAsset;
  /// @dev amount paid to deploy a market using an instance of this template.
  uint80 originationFeeAmount;
  /// @dev protocol fee applied to new markets, in basis points of lender interest.
  uint16 protocolFeeBips;
  /// @dev whether the template was registered. disabled templates still exist.
  bool exists;
  /// @dev whether new instances may be deployed from the template.
  bool enabled;
  /// @dev index of the template in the factory's enumeration.
  uint24 index;
  /// @dev recipient of origination and protocol fees.
  address feeRecipient;
  /// @dev factory-assigned display name.
  string name;
}

/// @dev reads optional string metadata through a bounded call. a failed or malformed response
///      returns an empty string instead of breaking deployment event emission.
function getHooksInstanceString(
  address hooksInstance,
  bytes4 selector
) view returns (string memory value) {
  value = '';
  uint32 selectorWord = uint32(selector);
  assembly ('memory-safe') {
    let ptr := mload(0x40)
    mstore(ptr, shl(224, selectorWord))
    if staticcall(100000, hooksInstance, ptr, 0x04, ptr, 0x40) {
      let size := returndatasize()
      if and(
        and(iszero(lt(size, 0x40)), iszero(gt(size, 0x1040))),
        eq(mload(ptr), 0x20)
      ) {
        let length := mload(add(ptr, 0x20))
        if iszero(gt(length, sub(size, 0x40))) {
          value := ptr
          mstore(ptr, length)
          returndatacopy(add(ptr, 0x20), 0x40, length)
          mstore(0x40, and(add(add(ptr, length), 0x3f), not(0x1f)))
        }
      }
    }
  }
}

/// @dev reads optional access-control metadata through a bounded call. malformed or oversized
///      responses return `(false, [])`.
function tryGetHooksInstanceRoleProviders(
  address hooksInstance,
  bytes4 selector
) view returns (bool success, RoleProvider[] memory providers) {
  providers = new RoleProvider[](0);
  uint32 selectorWord = uint32(selector);
  assembly ('memory-safe') {
    let ptr := mload(0x40)
    mstore(ptr, shl(224, selectorWord))
    if staticcall(1000000, hooksInstance, ptr, 0x04, ptr, 0x40) {
      let size := returndatasize()
      if and(
        and(iszero(lt(size, 0x40)), iszero(gt(size, 0x2040))),
        eq(mload(ptr), 0x20)
      ) {
        let length := mload(add(ptr, 0x20))
        if iszero(gt(length, shr(5, sub(size, 0x40)))) {
          providers := ptr
          mstore(ptr, length)
          returndatacopy(add(ptr, 0x20), 0x40, shl(5, length))
          mstore(0x40, add(add(ptr, 0x20), shl(5, length)))
          success := 1
        }
      }
    }
  }
}

/// @dev reads pull and push provider metadata as one optional feature. if either probe fails, the
///      function reports unavailable and returns both arrays empty.
function getHooksInstanceRoleProviders(
  address hooksInstance
)
  view
  returns (
    bool metadataAvailable,
    RoleProvider[] memory pullProviders,
    RoleProvider[] memory pushProviders
  )
{
  bool hasPullProviderMetadata;
  bool hasPushProviderMetadata;
  (hasPullProviderMetadata, pullProviders) = tryGetHooksInstanceRoleProviders(
    hooksInstance,
    bytes4(keccak256('getPullProviders()'))
  );
  (hasPushProviderMetadata, pushProviders) = tryGetHooksInstanceRoleProviders(
    hooksInstance,
    bytes4(keccak256('getPushProviders()'))
  );
  metadataAvailable = hasPullProviderMetadata && hasPushProviderMetadata;
  if (!metadataAvailable) {
    pullProviders = new RoleProvider[](0);
    pushProviders = new RoleProvider[](0);
  }
}

/// @notice errors and deployment events shared by standard and revolving hooks factories.
interface IHooksFactoryEventsAndErrors {
  /// @dev deployment fee arguments do not match the registered template terms.
  error FeeMismatch();
  /// @dev the identity registry could not resolve the caller to an approved borrower principal.
  error NotApprovedBorrower();
  /// @dev the requested hooks template is not registered.
  error HooksTemplateNotFound();
  /// @dev the requested hooks template is disabled for new instance deployments.
  error HooksTemplateNotAvailable();
  /// @dev the requested hooks template is already registered.
  error HooksTemplateAlreadyExists();
  /// @dev CREATE2 failed while deploying a hooks instance.
  error DeploymentFailed();
  /// @dev the requested hooks instance was not deployed by this factory.
  error HooksInstanceNotFound();
  /// @dev the caller is not the current ArchController owner.
  error CallerNotArchControllerOwner();
  /// @dev the template fee recipient, fee asset, or protocol fee is invalid.
  error InvalidFeeConfiguration();
  /// @dev the salt has a zero prefix or does not bind the market deployment caller.
  error SaltDoesNotContainSender();
  /// @dev a market already has code at the derived CREATE2 address.
  error MarketAlreadyExists();
  /// @dev stored-initcode deployment returned an address other than the derived market address.
  error MarketDeploymentAddressMismatch();
  /// @dev a hooks instance already occupies the expected deployment address.
  error HooksInstanceAlreadyExists();
  /// @dev the market name or symbol exceeds the factory's 63-byte packed encoding.
  error NameOrSymbolTooLong();
  /// @dev the market asset is currently blacklisted by the ArchController.
  error AssetBlacklisted();
  /// @dev a market rejected a batched protocol-fee update.
  error SetProtocolFeeBipsFailed();
  /// @dev the requested pagination start exceeds the requested end.
  error InvalidPaginationRange();
  /// @dev a hooks administrator transfer failed factory-side identity or state checks.
  error InvalidHooksAdministrator();
  /// @dev the hooks instance is not at its recorded position in the administrator index.
  error InvalidHooksInstanceAssociation();

  /// @notice emitted after a hooks instance is deployed and indexed.
  event HooksInstanceDeployed(
    address indexed hooksInstance,
    address indexed hooksTemplate,
    address indexed administrator,
    address deployer,
    string name,
    string version
  );
  /// @notice emitted with optional provider metadata reported by a new hooks instance.
  event HooksInstanceRoleProviders(
    address indexed hooksInstance,
    bool metadataAvailable,
    RoleProvider[] pullProviders,
    RoleProvider[] pushProviders
  );
  /// @notice emitted after a hooks instance accepts a new administrator.
  event HooksInstanceAdministratorTransferred(
    address indexed hooksInstance,
    address indexed previousAdministrator,
    address indexed newAdministrator
  );
  /// @notice emitted when the ArchController owner registers a hooks template.
  event HooksTemplateAdded(
    address indexed hooksTemplate,
    address indexed caller,
    string name,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  );
  /// @notice emitted when the ArchController owner disables new deployments from a template.
  event HooksTemplateDisabled(address indexed hooksTemplate, address indexed caller);
  /// @notice emitted when a template's fees for future markets change.
  event HooksTemplateFeesUpdated(
    address indexed hooksTemplate,
    address indexed caller,
    address previousFeeRecipient,
    address newFeeRecipient,
    address previousOriginationFeeAsset,
    address newOriginationFeeAsset,
    uint80 previousOriginationFeeAmount,
    uint80 newOriginationFeeAmount,
    uint16 previousProtocolFeeBips,
    uint16 newProtocolFeeBips
  );

  /// @notice emitted with the identities, metadata, asset, and callback flags of a new market.
  event MarketDeployed(
    address indexed hooksTemplate,
    address indexed hooksInstance,
    address indexed market,
    address borrower,
    address borrowerPrincipal,
    address borrowerIdentityRegistry,
    string name,
    string symbol,
    address asset,
    HooksConfig requestedHooks,
    HooksConfig hooks
  );
  /// @notice emitted with the financial configuration fixed for a new market.
  event MarketDeploymentConfig(
    address indexed market,
    uint256 maxTotalSupply,
    uint256 annualInterestBips,
    uint256 delinquencyFeeBips,
    uint256 withdrawalBatchDuration,
    uint256 reserveRatioBips,
    uint256 delinquencyGracePeriod,
    address feeRecipient,
    uint256 protocolFeeBips,
    address originationFeeAsset,
    uint256 originationFeeAmount
  );
  /// @notice emitted with the opaque hook data used to create a market.
  event MarketHooksData(address indexed market, bytes hooksData);
}

/// @title Wildcat hooks factory
/// @notice registers hooks templates, deploys reusable hooks instances, and deploys markets.
/// @dev borrower accounts are indexed under their resolved principal, while the market stores the
///      calling account as its operational borrower. market salts still bind to that caller;
///      hooks-instance salts use the resolved administrator and its nonce.
interface IHooksFactory is IHooksFactoryEventsAndErrors {
  /// @notice ArchController that authorizes this factory and receives new market registrations.
  function archController() external view returns (address);

  /// @notice sanctions sentinel written into newly deployed markets.
  function sanctionsSentinel() external view returns (address);

  /// @notice wrapper factory written into newly deployed markets.
  function wrapperFactory() external view returns (address);

  /// @notice registry used to resolve callers to registered borrower principals.
  function borrowerIdentityRegistry() external view returns (address);

  /// @notice contract holding the market creation code used by CREATE2 deployments.
  function marketInitCodeStorage() external view returns (address);

  /// @notice hash of the market initcode stored by `marketInitCodeStorage`.
  function marketInitCodeHash() external view returns (uint256);

  /// @notice registers this factory as an ArchController controller.
  /// @dev permissionless to trigger, but the ArchController must already recognize this contract
  ///      as a controller factory. a second call reverts there.
  function registerWithArchController() external;

  /// @notice stable factory name used by discovery tooling.
  function name() external view returns (string memory);

  // ========================================================================== //
  //                               Hooks Templates                              //
  // ========================================================================== //

  /// @notice registers a hooks template and its fee configuration.
  ///
  /// @dev only the ArchController owner can call this. the template address is expected to contain
  ///      the factory's stored-initcode format; deployment is where bad code finally fails.
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
  ///      after somebody calls `pushProtocolFeeBipsUpdates`.
  function updateHooksTemplateFees(
    address hooksTemplate,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external;

  /// @notice disables new instance deployments from `hooksTemplate`.
  /// @dev only the ArchController owner can call this. existing instances may still deploy markets;
  ///      this is not a kill switch, and there is no re-enable path.
  function disableHooksTemplate(address hooksTemplate) external;

  /// @notice returns the factory metadata for `hooksTemplate`.
  function getHooksTemplateDetails(
    address hooksTemplate
  ) external view returns (HooksTemplate memory);

  /// @notice returns whether `hooksTemplate` was registered, including if it is now disabled.
  function isHooksTemplate(address hooksTemplate) external view returns (bool);

  /// @notice returns all registered hooks templates in insertion order.
  function getHooksTemplates() external view returns (address[] memory);

  /// @notice returns templates in `[start, min(end, count))`.
  /// @dev an empty or out-of-bounds range returns an empty array.
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
  /// @dev `constructorArgs` are appended after the administrator argument expected by the stored
  ///      template initcode. this does not charge an origination fee.
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
  /// @dev only the hooks instance itself can make a valid call. the new administrator must be a
  ///      directly registered borrower, and swap-and-pop may change enumeration order.
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
  /// @dev only valid during the CREATE2 market constructor call. outside deployment, the transient
  ///      parameter array is empty and decoding it reverts.
  function getMarketParameters() external view returns (MarketParameters memory parameters);

  /// @notice deploys a market using the existing hooks instance in `parameters.hooks`.
  /// @dev the caller becomes the operational borrower and its resolved principal is stored on the
  ///      market. fee arguments must exactly match current template terms, and the first 20 bytes
  ///      of `salt` must equal the caller.
  /// @param hooksData opaque data forwarded to the hooks instance's `onCreateMarket` callback.
  function deployMarket(
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external returns (address market);

  /// @notice deploys a principal-administered hooks instance and a market using it.
  /// @dev both deployments are atomic. the caller may be a registered borrower account, but the
  ///      hooks instance is administered and indexed under its resolved principal.
  function deployMarketAndHooks(
    address hooksTemplate,
    bytes calldata hooksConstructorArgs,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external returns (address market, address hooks);

  /// @notice returns the CREATE2 market address for `salt` and this factory's initcode.
  /// @dev the first 20 bytes must name the nonzero deployer. for borrower accounts this is the
  ///      account contract, not its principal.
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
