// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import './libraries/LibERC20.sol';
import './interfaces/IWildcatArchController.sol';
import './libraries/LibStoredInitCode.sol';
import './libraries/MathUtils.sol';
import './ReentrancyGuard.sol';
import './interfaces/WildcatStructsAndEnums.sol';
import './access/IHooks.sol';
import './IHooksFactoryRevolving.sol';
import './types/TransientBytesArray.sol';
import './spherex/SphereXProtectedRegisteredBase.sol';
import './access/IHooksAdministrator.sol';
import './interfaces/IBorrowerIdentityRegistry.sol';
import './types/RoleProvider.sol';

struct TmpRevolvingMarketParameterStorage {
  address borrower;
  address asset;
  address feeRecipient;
  uint16 protocolFeeBips;
  uint128 maxTotalSupply;
  uint16 annualInterestBips;
  uint16 delinquencyFeeBips;
  uint32 withdrawalBatchDuration;
  uint16 reserveRatioBips;
  uint32 delinquencyGracePeriod;
  bytes32 packedNameWord0;
  bytes32 packedNameWord1;
  bytes32 packedSymbolWord0;
  bytes32 packedSymbolWord1;
  uint8 decimals;
  HooksConfig hooks;
}

/**
 * @dev Deployment parameters that are not part of `DeployMarketInputs`,
 *      bundled to avoid stack-too-deep in `_deployMarket`.
 */
struct DeployRevolvingMarketRuntimeParameters {
  address hooksTemplate;
  address borrowerPrincipal;
  HooksConfig requestedHooks;
  bytes32 salt;
  address originationFeeAsset;
  uint256 originationFeeAmount;
  uint16 commitmentFeeBips;
}

contract HooksFactoryRevolving is
  SphereXProtectedRegisteredBase,
  ReentrancyGuard,
  IHooksFactoryRevolving
{
  using LibERC20 for address;

  TransientBytesArray internal constant _tmpMarketParameters =
    TransientBytesArray.wrap(
      uint256(keccak256('Transient:TmpRevolvingMarketParameterStorage')) - 1
    );

  uint256 internal constant _TMP_BORROWER_PRINCIPAL_SLOT =
    uint256(keccak256('Transient:TmpBorrowerPrincipal')) - 1;

  TransientBytesArray internal constant _tmpRevolvingMarketData =
    TransientBytesArray.wrap(uint256(keccak256('Transient:TmpRevolvingMarketData')) - 1);

  /// @dev Length of `abi.encode(uint8 version, uint16 commitmentFeeBips)`
  uint256 internal constant _MARKET_DATA_LENGTH = 0x40;

  uint8 internal constant _MARKET_DATA_VERSION = 1;

  uint16 internal constant _MAX_COMMITMENT_FEE_BIPS = 10_000;

  uint256 internal immutable ownCreate2Prefix = LibStoredInitCode.getCreate2Prefix(address(this));

  address public immutable override marketInitCodeStorage;

  uint256 public immutable override marketInitCodeHash;

  address public immutable override sanctionsSentinel;

  address public immutable override wrapperFactory;

  address public immutable override borrowerIdentityRegistry;

  /**
   * @dev Return the contract name "WildcatHooksFactoryRevolving"
   */
  function name() external pure override returns (string memory) {
    return 'WildcatHooksFactoryRevolving';
  }

  address[] internal _hooksTemplates;

  /// @dev Hooks instances currently administered by each address.
  mapping(address administrator => address[] hooksInstances)
    internal _hooksInstancesByAdministrator;

  /// @dev Current administrator for each hooks instance deployed by this factory.
  mapping(address hooksInstance => address administrator)
    public
    override getHooksAdministrator;

  /// @dev Position of each hooks instance in its administrator's array.
  mapping(address hooksInstance => uint256 index) internal _hooksInstanceIndex;

  /// @dev Monotonic deployment nonce used in hook CREATE2 salts.
  mapping(address administrator => uint256 nonce)
    public
    override getHooksInstanceDeploymentNonce;

  /**
   * @dev Mapping from hooks template to markets created with it.
   *      Used for pushing protocol fee changes to affected markets.
   */
  mapping(address hooksTemplate => address[] markets) internal _marketsByHooksTemplate;

  /**
   * @dev Mapping from hooks instance to markets deployed using it.
   *      Intended primarily for off-chain queries.
   */
  mapping(address hooksInstance => address[] markets) internal _marketsByHooksInstance;

  /**
   * @dev Mapping from hooks template to its fee configuration and name.
   */
  mapping(address hooksTemplate => HooksTemplate details) internal _templateDetails;

  mapping(address hooksInstance => address hooksTemplate)
    public
    override getHooksTemplateForInstance;

  constructor(
    address archController_,
    address _sanctionsSentinel,
    address _wrapperFactory,
    address _marketInitCodeStorage,
    uint256 _marketInitCodeHash,
    address _borrowerIdentityRegistry
  ) {
    marketInitCodeStorage = _marketInitCodeStorage;
    marketInitCodeHash = _marketInitCodeHash;
    _archController = archController_;
    sanctionsSentinel = _sanctionsSentinel;
    wrapperFactory = _wrapperFactory;
    borrowerIdentityRegistry = _borrowerIdentityRegistry;
    __SphereXProtectedRegisteredBase_init(IWildcatArchController(archController_).sphereXEngine());
  }

  /**
   * @dev Registers the factory as a controller with the arch-controller, allowing
   *      it to register new markets.
   *      Needs to be executed once at deployment.
   *      Does not need checks for whether it has already been registered as the
   *      arch-controller will revert if it is already registered.
   */
  function registerWithArchController() external override {
    IWildcatArchController(_archController).registerController(address(this));
  }

  function archController() external view override returns (address) {
    return _archController;
  }

  // ========================================================================== //
  //                          Internal Storage Helpers                          //
  // ========================================================================== //

  /**
   * @dev Get the temporary market parameters from transient storage.
   */
  function _getTmpMarketParameters()
    internal
    view
    returns (TmpRevolvingMarketParameterStorage memory parameters)
  {
    return abi.decode(_tmpMarketParameters.read(), (TmpRevolvingMarketParameterStorage));
  }

  /**
   * @dev Set the temporary market parameters in transient storage.
   */
  function _setTmpMarketParameters(TmpRevolvingMarketParameterStorage memory parameters) internal {
    _tmpMarketParameters.write(abi.encode(parameters));
  }

  function _getTmpBorrowerPrincipal() internal view returns (address principal) {
    uint256 slot = _TMP_BORROWER_PRINCIPAL_SLOT;
    assembly {
      principal := tload(slot)
    }
  }

  function _setTmpBorrowerPrincipal(address principal) internal {
    uint256 slot = _TMP_BORROWER_PRINCIPAL_SLOT;
    assembly {
      tstore(slot, principal)
    }
  }

  /**
   * @dev Set the temporary commitment fee in transient storage.
   */
  function _setTmpCommitmentFeeBips(uint16 commitmentFeeBips) internal {
    _tmpRevolvingMarketData.write(abi.encode(commitmentFeeBips));
  }

  /**
   * @dev Get the temporary commitment fee from transient storage.
   */
  function _getTmpCommitmentFeeBips() internal view returns (uint16 commitmentFeeBips) {
    return abi.decode(_tmpRevolvingMarketData.read(), (uint16));
  }

  // ========================================================================== //
  //                                  Modifiers                                 //
  // ========================================================================== //

  modifier onlyArchControllerOwner() {
    if (msg.sender != IWildcatArchController(_archController).owner()) {
      revert CallerNotArchControllerOwner();
    }
    _;
  }

  function _resolveBorrowerPrincipal(address borrower) internal view returns (address principal) {
    address registry = borrowerIdentityRegistry;
    uint256 resolveBorrowerSelector = uint32(
      IBorrowerIdentityRegistry.resolveBorrower.selector
    );
    uint256 notApprovedBorrowerSelector = uint32(NotApprovedBorrower.selector);
    assembly ('memory-safe') {
      mstore(0, resolveBorrowerSelector)
      mstore(0x20, borrower)
      let success := staticcall(gas(), registry, 0x1c, 0x24, 0, 0x20)
      if iszero(and(success, eq(returndatasize(), 0x20))) {
        mstore(0, notApprovedBorrowerSelector)
        revert(0x1c, 0x04)
      }
      principal := mload(0)
      // Match Solidity's address decoder instead of silently truncating dirty returndata.
      if shr(160, principal) {
        revert(0, 0)
      }
      if iszero(principal) {
        mstore(0, notApprovedBorrowerSelector)
        revert(0x1c, 0x04)
      }
    }
  }

  // ========================================================================== //
  //                               Hooks Templates                              //
  // ========================================================================== //

  function addHooksTemplate(
    address hooksTemplate,
    string calldata name_,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external override onlyArchControllerOwner {
    if (_templateDetails[hooksTemplate].exists) {
      revert HooksTemplateAlreadyExists();
    }
    _validateFees(feeRecipient, originationFeeAsset, originationFeeAmount, protocolFeeBips);
    _templateDetails[hooksTemplate] = HooksTemplate({
      exists: true,
      name: name_,
      feeRecipient: feeRecipient,
      originationFeeAsset: originationFeeAsset,
      originationFeeAmount: originationFeeAmount,
      protocolFeeBips: protocolFeeBips,
      enabled: true,
      index: uint24(_hooksTemplates.length)
    });
    _hooksTemplates.push(hooksTemplate);
    emit HooksTemplateAdded(
      hooksTemplate,
      msg.sender,
      name_,
      feeRecipient,
      originationFeeAsset,
      originationFeeAmount,
      protocolFeeBips
    );
  }

  function _validateFees(
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) internal pure {
    bool hasOriginationFee = originationFeeAmount > 0;
    bool nullFeeRecipient = feeRecipient == address(0);
    bool nullOriginationFeeAsset = originationFeeAsset == address(0);
    if (
      (protocolFeeBips > 0 && nullFeeRecipient) ||
      (hasOriginationFee && nullFeeRecipient) ||
      (hasOriginationFee && nullOriginationFeeAsset) ||
      protocolFeeBips > 1_000
    ) {
      revert InvalidFeeConfiguration();
    }
  }

  /// @dev Update the fees for a hooks template
  /// Note: The new fee structure will apply to all NEW markets created with existing
  ///       or future instances of the hooks template, and the protocol fee can be pushed
  ///       to existing markets using `pushProtocolFeeBipsUpdates`.
  function updateHooksTemplateFees(
    address hooksTemplate,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external override onlyArchControllerOwner {
    if (!_templateDetails[hooksTemplate].exists) {
      revert HooksTemplateNotFound();
    }
    _validateFees(feeRecipient, originationFeeAsset, originationFeeAmount, protocolFeeBips);
    HooksTemplate storage template = _templateDetails[hooksTemplate];
    address previousFeeRecipient = template.feeRecipient;
    address previousOriginationFeeAsset = template.originationFeeAsset;
    uint80 previousOriginationFeeAmount = template.originationFeeAmount;
    uint16 previousProtocolFeeBips = template.protocolFeeBips;
    template.feeRecipient = feeRecipient;
    template.originationFeeAsset = originationFeeAsset;
    template.originationFeeAmount = originationFeeAmount;
    template.protocolFeeBips = protocolFeeBips;
    emit HooksTemplateFeesUpdated(
      hooksTemplate,
      msg.sender,
      previousFeeRecipient,
      feeRecipient,
      previousOriginationFeeAsset,
      originationFeeAsset,
      previousOriginationFeeAmount,
      originationFeeAmount,
      previousProtocolFeeBips,
      protocolFeeBips
    );
  }

  function disableHooksTemplate(address hooksTemplate) external override onlyArchControllerOwner {
    if (!_templateDetails[hooksTemplate].exists) {
      revert HooksTemplateNotFound();
    }
    // The template is only disabled, not removed: `exists` stays true, so it
    // can not be re-added and there is no re-enable path.
    _templateDetails[hooksTemplate].enabled = false;
    emit HooksTemplateDisabled(hooksTemplate, msg.sender);
  }

  function getHooksTemplateDetails(
    address hooksTemplate
  ) external view override returns (HooksTemplate memory) {
    return _templateDetails[hooksTemplate];
  }

  function isHooksTemplate(address hooksTemplate) external view override returns (bool) {
    return _templateDetails[hooksTemplate].exists;
  }

  function getHooksTemplates() external view override returns (address[] memory) {
    return _hooksTemplates;
  }

  function getHooksTemplates(
    uint256 start,
    uint256 end
  ) external view override returns (address[] memory arr) {
    uint256 len = _hooksTemplates.length;
    end = MathUtils.min(end, len);
    if (start >= end) return new address[](0);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _hooksTemplates[start + i];
    }
  }

  function getHooksTemplatesCount() external view override returns (uint256) {
    return _hooksTemplates.length;
  }

  function getMarketsForHooksTemplate(
    address hooksTemplate
  ) external view override returns (address[] memory) {
    return _marketsByHooksTemplate[hooksTemplate];
  }

  function getMarketsForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view override returns (address[] memory arr) {
    address[] storage markets = _marketsByHooksTemplate[hooksTemplate];
    uint256 len = markets.length;
    end = MathUtils.min(end, len);
    if (start >= end) return new address[](0);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = markets[start + i];
    }
  }

  function getMarketsForHooksTemplateCount(
    address hooksTemplate
  ) external view override returns (uint256) {
    return _marketsByHooksTemplate[hooksTemplate].length;
  }

  // ========================================================================== //
  //                               Hooks Instances                              //
  // ========================================================================== //

  /// @dev Deploy a hooks instance for an approved template with constructor args.
  ///      Hooks are deployed and indexed under the caller's resolved principal.
  ///      Origination fees are not charged here; they are paid when a market
  ///      is deployed with the instance.
  function deployHooksInstance(
    address hooksTemplate,
    bytes calldata constructorArgs
  ) external override nonReentrant returns (address hooksInstance) {
    address administrator = _resolveBorrowerPrincipal(msg.sender);
    hooksInstance = _deployHooksInstance(administrator, hooksTemplate, constructorArgs);
  }

  function getHooksInstancesForAdministrator(
    address administrator
  ) external view override returns (address[] memory) {
    return _hooksInstancesByAdministrator[administrator];
  }

  function getHooksInstancesForAdministrator(
    address administrator,
    uint256 start,
    uint256 end
  ) external view override returns (address[] memory arr) {
    address[] storage hooksInstances = _hooksInstancesByAdministrator[administrator];
    end = MathUtils.min(end, hooksInstances.length);
    if (start >= end) return new address[](0);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = hooksInstances[start + i];
    }
  }

  function getHooksInstancesCountForAdministrator(
    address administrator
  ) external view override returns (uint256) {
    return _hooksInstancesByAdministrator[administrator].length;
  }

  function getHooksInstancesForBorrower(
    address borrower
  ) external view override returns (address[] memory) {
    return _hooksInstancesByAdministrator[borrower];
  }

  function getHooksInstancesCountForBorrower(
    address borrower
  ) external view override returns (uint256) {
    return _hooksInstancesByAdministrator[borrower].length;
  }

  /**
   * @dev Moves a hooks instance to its new administrator's array. Removal uses
   *      swap-and-pop, so an administrator's enumeration is not ordered.
   */
  function onHooksAdministratorTransferred(
    address previousAdministrator,
    address newAdministrator
  ) external override nonReentrant {
    address hooksInstance = msg.sender;
    if (getHooksTemplateForInstance[hooksInstance] == address(0)) {
      revert HooksInstanceNotFound();
    }
    if (
      previousAdministrator == newAdministrator ||
      newAdministrator == address(0) ||
      getHooksAdministrator[hooksInstance] != previousAdministrator ||
      IHooksAdministrator(hooksInstance).administrator() != newAdministrator ||
      IHooksAdministrator(hooksInstance).pendingAdministrator() != address(0) ||
      !IWildcatArchController(_archController).isRegisteredBorrower(newAdministrator)
    ) {
      revert InvalidHooksAdministrator();
    }

    address[] storage previousHooksInstances = _hooksInstancesByAdministrator[
      previousAdministrator
    ];
    uint256 indexToRemove = _hooksInstanceIndex[hooksInstance];
    uint256 previousCount = previousHooksInstances.length;
    if (indexToRemove >= previousCount || previousHooksInstances[indexToRemove] != hooksInstance) {
      revert InvalidHooksInstanceAssociation();
    }
    uint256 lastIndex = previousCount - 1;
    if (indexToRemove != lastIndex) {
      address movedHooksInstance = previousHooksInstances[lastIndex];
      previousHooksInstances[indexToRemove] = movedHooksInstance;
      _hooksInstanceIndex[movedHooksInstance] = indexToRemove;
    }
    previousHooksInstances.pop();

    _hooksInstanceIndex[hooksInstance] = _hooksInstancesByAdministrator[newAdministrator].length;
    _hooksInstancesByAdministrator[newAdministrator].push(hooksInstance);
    getHooksAdministrator[hooksInstance] = newAdministrator;

    emit HooksInstanceAdministratorTransferred(
      hooksInstance,
      previousAdministrator,
      newAdministrator
    );
  }

  function isHooksInstance(address hooksInstance) external view override returns (bool) {
    return getHooksTemplateForInstance[hooksInstance] != address(0);
  }

  function _deployHooksInstance(
    address administrator,
    address hooksTemplate,
    bytes calldata constructorArgs
  ) internal returns (address hooksInstance) {
    HooksTemplate storage template = _templateDetails[hooksTemplate];
    if (!template.exists) {
      revert HooksTemplateNotFound();
    }
    if (!template.enabled) {
      revert HooksTemplateNotAvailable();
    }

    uint256 deploymentNonce = getHooksInstanceDeploymentNonce[administrator];
    bytes32 salt;
    assembly {
      salt := or(shl(96, administrator), deploymentNonce)
      let initCodePointer := mload(0x40)
      let initCodeSize := sub(extcodesize(hooksTemplate), 1)
      // Copy code from target address to memory starting at byte 1
      extcodecopy(hooksTemplate, initCodePointer, 1, initCodeSize)
      let endInitCodePointer := add(initCodePointer, initCodeSize)
      // Write the administrator as the first parameter
      mstore(endInitCodePointer, administrator)
      // Write the offset to the encoded constructor args
      mstore(add(endInitCodePointer, 0x20), 0x40)
      // Write the length of the encoded constructor args
      let constructorArgsSize := constructorArgs.length
      mstore(add(endInitCodePointer, 0x40), constructorArgsSize)
      // Copy constructor args to initcode after the bytes length
      calldatacopy(add(endInitCodePointer, 0x60), constructorArgs.offset, constructorArgsSize)
      // Get the full size of the initcode with the constructor args
      let initCodeSizeWithArgs := add(add(initCodeSize, 0x60), constructorArgsSize)
      // Deploy the contract with the initcode
      hooksInstance := create2(0, initCodePointer, initCodeSizeWithArgs, salt)
      if iszero(hooksInstance) {
        mstore(0x00, 0x30116425) // DeploymentFailed()
        revert(0x1c, 0x04)
      }
    }
    getHooksInstanceDeploymentNonce[administrator] = deploymentNonce + 1;
    _hooksInstanceIndex[hooksInstance] = _hooksInstancesByAdministrator[administrator].length;
    _hooksInstancesByAdministrator[administrator].push(hooksInstance);
    getHooksAdministrator[hooksInstance] = administrator;

    emit HooksInstanceDeployed(
      hooksInstance,
      hooksTemplate,
      administrator,
      msg.sender,
      getHooksInstanceString(hooksInstance, bytes4(keccak256('name()'))),
      getHooksInstanceString(hooksInstance, IHooks.version.selector)
    );
    (
      bool metadataAvailable,
      RoleProvider[] memory pullProviders,
      RoleProvider[] memory pushProviders
    ) = getHooksInstanceRoleProviders(hooksInstance);
    emit HooksInstanceRoleProviders(
      hooksInstance,
      metadataAvailable,
      pullProviders,
      pushProviders
    );
    getHooksTemplateForInstance[hooksInstance] = hooksTemplate;
  }

  // ========================================================================== //
  //                                   Markets                                  //
  // ========================================================================== //

  function getMarketsForHooksInstance(
    address hooksInstance
  ) external view override returns (address[] memory) {
    return _marketsByHooksInstance[hooksInstance];
  }

  function getMarketsForHooksInstance(
    address hooksInstance,
    uint256 start,
    uint256 end
  ) external view override returns (address[] memory arr) {
    address[] storage markets = _marketsByHooksInstance[hooksInstance];
    end = MathUtils.min(end, markets.length);
    if (start >= end) return new address[](0);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = markets[start + i];
    }
  }

  function getMarketsForHooksInstanceCount(
    address hooksInstance
  ) external view override returns (uint256) {
    return _marketsByHooksInstance[hooksInstance].length;
  }

  /**
   * @dev Get the temporarily stored market parameters for a market that is
   *      currently being deployed.
   */
  function getMarketParameters()
    external
    view
    override
    returns (MarketParameters memory parameters)
  {
    TmpRevolvingMarketParameterStorage memory tmp = _getTmpMarketParameters();

    parameters.asset = tmp.asset;
    parameters.packedNameWord0 = tmp.packedNameWord0;
    parameters.packedNameWord1 = tmp.packedNameWord1;
    parameters.packedSymbolWord0 = tmp.packedSymbolWord0;
    parameters.packedSymbolWord1 = tmp.packedSymbolWord1;
    parameters.decimals = tmp.decimals;
    parameters.borrower = tmp.borrower;
    parameters.feeRecipient = tmp.feeRecipient;
    parameters.sentinel = sanctionsSentinel;
    parameters.wrapperFactory = wrapperFactory;
    parameters.maxTotalSupply = tmp.maxTotalSupply;
    parameters.protocolFeeBips = tmp.protocolFeeBips;
    parameters.annualInterestBips = tmp.annualInterestBips;
    parameters.delinquencyFeeBips = tmp.delinquencyFeeBips;
    parameters.withdrawalBatchDuration = tmp.withdrawalBatchDuration;
    parameters.reserveRatioBips = tmp.reserveRatioBips;
    parameters.delinquencyGracePeriod = tmp.delinquencyGracePeriod;
    parameters.archController = _archController;
    parameters.sphereXEngine = sphereXEngine();
    parameters.hooks = tmp.hooks;
    parameters.borrowerPrincipal = _getTmpBorrowerPrincipal();
    parameters.borrowerIdentityRegistry = borrowerIdentityRegistry;
  }

  function computeMarketAddress(bytes32 salt) external view override returns (address) {
    if (bytes20(salt) == bytes20(0)) revert SaltDoesNotContainSender();
    return LibStoredInitCode.calculateCreate2Address(ownCreate2Prefix, salt, marketInitCodeHash);
  }

  /**
   * @dev Given a string of at most 63 bytes, produces a packed version with two words,
   *      where the first word contains the length byte and the first 31 bytes of the string,
   *      and the second word contains the second 32 bytes of the string.
   */
  function _packString(string memory str) internal pure returns (bytes32 word0, bytes32 word1) {
    assembly {
      let length := mload(str)
      // Equivalent to:
      // if (str.length > 63) revert NameOrSymbolTooLong();
      if gt(length, 0x3f) {
        mstore(0, 0x19a65cb6)
        revert(0x1c, 0x04)
      }
      // Load the length and first 31 bytes of the string into the first word
      // by reading from 31 bytes after the length pointer.
      word0 := mload(add(str, 0x1f))
      // If the string is less than 32 bytes, the second word will be zeroed out.
      word1 := mul(mload(add(str, 0x3f)), gt(mload(str), 0x1f))
    }
  }

  /**
   * @dev Decode the factory-owned `marketData` provided to the deployment
   *      functions, currently `abi.encode(uint8 version, uint16 commitmentFeeBips)`.
   */
  function _decodeMarketData(
    bytes calldata marketData
  ) internal pure returns (uint16 commitmentFeeBips) {
    if (marketData.length != _MARKET_DATA_LENGTH) {
      revert InvalidMarketData();
    }

    (uint8 version, uint16 decodedCommitmentFeeBips) = abi.decode(marketData, (uint8, uint16));
    if (version != _MARKET_DATA_VERSION) {
      revert UnsupportedMarketDataVersion();
    }
    if (decodedCommitmentFeeBips > _MAX_COMMITMENT_FEE_BIPS) {
      revert InvalidCommitmentFeeBips();
    }
    commitmentFeeBips = decodedCommitmentFeeBips;
  }

  function _emitMarketDeployment(
    address market,
    string memory name,
    string memory symbol,
    TmpRevolvingMarketParameterStorage memory tmp,
    DeployRevolvingMarketRuntimeParameters memory runtimeParams,
    bytes calldata hooksData
  ) internal {
    emit MarketDeployed(
      runtimeParams.hooksTemplate,
      runtimeParams.requestedHooks.hooksAddress(),
      market,
      tmp.borrower,
      runtimeParams.borrowerPrincipal,
      borrowerIdentityRegistry,
      name,
      symbol,
      tmp.asset,
      runtimeParams.requestedHooks,
      tmp.hooks
    );
    emit MarketDeploymentConfig(
      market,
      tmp.maxTotalSupply,
      tmp.annualInterestBips,
      tmp.delinquencyFeeBips,
      tmp.withdrawalBatchDuration,
      tmp.reserveRatioBips,
      tmp.delinquencyGracePeriod,
      tmp.feeRecipient,
      tmp.protocolFeeBips,
      runtimeParams.originationFeeAsset,
      runtimeParams.originationFeeAmount
    );
    emit MarketHooksData(market, hooksData);
    emit RevolvingMarketDeployed(market, runtimeParams.commitmentFeeBips);
  }

  function _deployMarket(
    DeployMarketInputs memory parameters,
    bytes calldata hooksData,
    DeployRevolvingMarketRuntimeParameters memory runtimeParams
  ) internal returns (address market) {
    HooksTemplate storage templateDetails = _templateDetails[runtimeParams.hooksTemplate];
    if (!templateDetails.exists) {
      revert HooksTemplateNotFound();
    }
    // Snapshot only the fee fields used below. Copying the whole struct also loads its
    // dynamic name, and reading these fields later would let callbacks change this deployment.
    address templateOriginationFeeAsset = templateDetails.originationFeeAsset;
    uint80 templateOriginationFeeAmount = templateDetails.originationFeeAmount;
    address templateFeeRecipient = templateDetails.feeRecipient;
    uint16 templateProtocolFeeBips = templateDetails.protocolFeeBips;

    if (IWildcatArchController(_archController).isBlacklistedAsset(parameters.asset)) {
      revert AssetBlacklisted();
    }
    address hooksInstance = parameters.hooks.hooksAddress();

    if (address(bytes20(runtimeParams.salt)) != msg.sender) {
      revert SaltDoesNotContainSender();
    }

    if (
      runtimeParams.originationFeeAsset != templateOriginationFeeAsset ||
      runtimeParams.originationFeeAmount != templateOriginationFeeAmount
    ) {
      revert FeeMismatch();
    }

    if (runtimeParams.originationFeeAsset != address(0)) {
      runtimeParams.originationFeeAsset.safeTransferFrom(
        msg.sender,
        templateFeeRecipient,
        runtimeParams.originationFeeAmount
      );
    }

    market = LibStoredInitCode.calculateCreate2Address(
      ownCreate2Prefix,
      runtimeParams.salt,
      marketInitCodeHash
    );

    parameters.hooks = IHooks(hooksInstance).onCreateMarket(
      runtimeParams.borrowerPrincipal,
      market,
      parameters,
      hooksData
    );
    uint8 decimals = parameters.asset.decimals();

    string memory name = string.concat(parameters.namePrefix, parameters.asset.name());
    string memory symbol = string.concat(parameters.symbolPrefix, parameters.asset.symbol());

    TmpRevolvingMarketParameterStorage memory tmp = TmpRevolvingMarketParameterStorage({
      borrower: msg.sender,
      asset: parameters.asset,
      packedNameWord0: bytes32(0),
      packedNameWord1: bytes32(0),
      packedSymbolWord0: bytes32(0),
      packedSymbolWord1: bytes32(0),
      decimals: decimals,
      feeRecipient: templateFeeRecipient,
      protocolFeeBips: templateProtocolFeeBips,
      maxTotalSupply: parameters.maxTotalSupply,
      annualInterestBips: parameters.annualInterestBips,
      delinquencyFeeBips: parameters.delinquencyFeeBips,
      withdrawalBatchDuration: parameters.withdrawalBatchDuration,
      reserveRatioBips: parameters.reserveRatioBips,
      delinquencyGracePeriod: parameters.delinquencyGracePeriod,
      hooks: parameters.hooks
    });
    {
      (tmp.packedNameWord0, tmp.packedNameWord1) = _packString(name);
      (tmp.packedSymbolWord0, tmp.packedSymbolWord1) = _packString(symbol);
    }

    _setTmpMarketParameters(tmp);
    _setTmpBorrowerPrincipal(runtimeParams.borrowerPrincipal);
    _setTmpCommitmentFeeBips(runtimeParams.commitmentFeeBips);

    if (market.code.length != 0) {
      revert MarketAlreadyExists();
    }
    if (
      LibStoredInitCode.create2WithStoredInitCode(marketInitCodeStorage, runtimeParams.salt) !=
      market
    ) {
      revert MarketDeploymentAddressMismatch();
    }

    IWildcatArchController(_archController).registerMarket(market);

    _tmpMarketParameters.setEmpty();
    _setTmpBorrowerPrincipal(address(0));
    _tmpRevolvingMarketData.setEmpty();

    _marketsByHooksTemplate[runtimeParams.hooksTemplate].push(market);
    _marketsByHooksInstance[hooksInstance].push(market);

    _emitMarketDeployment(market, name, symbol, tmp, runtimeParams, hooksData);
  }

  /**
   * @dev Commitment fee for the revolving market currently being deployed.
   *      Read by the `WildcatMarketRevolving` constructor; only valid during
   *      market deployment.
   */
  function getRevolvingMarketCommitmentFeeBips() external view override returns (uint16) {
    return _getTmpCommitmentFeeBips();
  }

  function deployMarket(
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes calldata marketData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external override nonReentrant returns (address market) {
    address borrowerPrincipal = _resolveBorrowerPrincipal(msg.sender);
    uint16 commitmentFeeBips = _decodeMarketData(marketData);
    address hooksTemplate = getHooksTemplateForInstance[parameters.hooks.hooksAddress()];
    if (hooksTemplate == address(0)) {
      revert HooksInstanceNotFound();
    }
    DeployRevolvingMarketRuntimeParameters
      memory runtimeParams = DeployRevolvingMarketRuntimeParameters({
        hooksTemplate: hooksTemplate,
        borrowerPrincipal: borrowerPrincipal,
        requestedHooks: parameters.hooks,
        salt: salt,
        originationFeeAsset: originationFeeAsset,
        originationFeeAmount: originationFeeAmount,
        commitmentFeeBips: commitmentFeeBips
      });
    market = _deployMarket(parameters, hooksData, runtimeParams);
  }

  function deployMarketAndHooks(
    address hooksTemplate,
    bytes calldata hooksConstructorArgs,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes calldata marketData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external override nonReentrant returns (address market, address hooksInstance) {
    address borrowerPrincipal = _resolveBorrowerPrincipal(msg.sender);
    DeployRevolvingMarketRuntimeParameters
      memory runtimeParams = DeployRevolvingMarketRuntimeParameters({
        hooksTemplate: hooksTemplate,
        borrowerPrincipal: borrowerPrincipal,
        requestedHooks: parameters.hooks,
        salt: salt,
        originationFeeAsset: originationFeeAsset,
        originationFeeAmount: originationFeeAmount,
        commitmentFeeBips: _decodeMarketData(marketData)
      });
    // `_deployHooksInstance` reverts if the template does not exist or is disabled.
    hooksInstance = _deployHooksInstance(
      borrowerPrincipal,
      hooksTemplate,
      hooksConstructorArgs
    );
    DeployMarketInputs memory marketInputs = parameters;
    marketInputs.hooks = marketInputs.hooks.setHooksAddress(hooksInstance);
    runtimeParams.requestedHooks = marketInputs.hooks;
    market = _deployMarket(marketInputs, hooksData, runtimeParams);
  }

  /**
   * @dev Push any changes to the fee configuration of `hooksTemplate` to markets
   *      using any instances of that template at `_marketsByHooksTemplate[hooksTemplate]`.
   *      Starts at `marketStartIndex` and ends one before `marketEndIndex` or markets.length,
   *      whichever is lower.
   */
  function pushProtocolFeeBipsUpdates(
    address hooksTemplate,
    uint marketStartIndex,
    uint marketEndIndex
  ) public override nonReentrant {
    HooksTemplate storage details = _templateDetails[hooksTemplate];
    if (!details.exists) revert HooksTemplateNotFound();

    address[] storage markets = _marketsByHooksTemplate[hooksTemplate];
    uint256 marketCount = markets.length;
    marketEndIndex = MathUtils.min(marketEndIndex, marketCount);
    // CAF-13 fix: reject ranges that would underflow after clamping, but allow
    // boundary-empty pages to no-op for fixed-size operational pagination.
    if (marketStartIndex > marketEndIndex) revert InvalidPaginationRange();
    if (marketStartIndex == marketEndIndex) return;
    uint256 count = marketEndIndex - marketStartIndex;
    uint256 setProtocolFeeBipsCalldataPointer;
    uint16 protocolFeeBips = details.protocolFeeBips;
    assembly {
      // Write the calldata for `market.setProtocolFeeBips(protocolFeeBips)`
      // this will be reused for every market
      setProtocolFeeBipsCalldataPointer := mload(0x40)
      mstore(0x40, add(setProtocolFeeBipsCalldataPointer, 0x40))
      // Write selector for `setProtocolFeeBips(uint16)`
      mstore(setProtocolFeeBipsCalldataPointer, 0xae6ea191)
      mstore(add(setProtocolFeeBipsCalldataPointer, 0x20), protocolFeeBips)
      // Add 28 bytes to get the exact pointer to the first byte of the selector
      setProtocolFeeBipsCalldataPointer := add(setProtocolFeeBipsCalldataPointer, 0x1c)
    }
    for (uint256 i = 0; i < count; i++) {
      address market = markets[marketStartIndex + i];
      assembly {
        if iszero(call(gas(), market, 0, setProtocolFeeBipsCalldataPointer, 0x24, 0, 0)) {
          // Equivalent to `revert SetProtocolFeeBipsFailed()`
          mstore(0, 0x4484a4a9)
          revert(0x1c, 0x04)
        }
      }
    }
  }

  /**
   * @dev Push any changes to the fee configuration of `hooksTemplate` to all markets
   *      using any instances of that template at `_marketsByHooksTemplate[hooksTemplate]`.
   */
  function pushProtocolFeeBipsUpdates(address hooksTemplate) external override {
    pushProtocolFeeBipsUpdates(hooksTemplate, 0, type(uint256).max);
  }
}
