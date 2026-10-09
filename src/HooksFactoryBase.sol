// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // HooksFactoryBase
//  \ ^ /   Shared hooks lifecycle and deterministic market deployment.
//    V
//
//  SETUP
//  constructor(...)
//  registerWithArchController()
//  archController()
//
//  HOOKS TEMPLATES
//  onlyArchControllerOwner()
//  addHooksTemplate(...)
//  disableHooksTemplate(...)
//
//  TEMPLATE FEES
//  updateHooksTemplateFees(...)
//  _validateFees(...)
//  pushProtocolFeeBipsUpdates(...)
//  pushProtocolFeeBipsUpdates(...)
//
//  TEMPLATE QUERIES
//  getHooksTemplateDetails(...)
//  isHooksTemplate(...)
//  getHooksTemplates()
//  getHooksTemplates(...)
//  getHooksTemplatesCount()
//
//  HOOKS DEPLOYMENT
//  deployHooksInstance(...)
//  _deployHooksInstance(...)
//  _resolveBorrowerPrincipal(...)
//  isHooksInstance(...)
//
//  HOOKS ADMINISTRATION
//  onHooksAdministratorTransferred(...)
//  getHooksInstancesForAdministrator(...)
//  getHooksInstancesForAdministrator(...)
//  getHooksInstancesCountForAdministrator(...)
//  getHooksInstancesForBorrower(...)
//  getHooksInstancesCountForBorrower(...)
//
//  MARKET DEPLOYMENT
//  _deployMarket(...)
//  _packString(...)
//  _emitMarketDeployment(...)
//  computeMarketAddress(...)
//
//  MARKET DATA
//  _storeMarketData(...)
//  _clearMarketData()
//  _emitMarketData(...)
//
//  CONSTRUCTOR PARAMETERS
//  getMarketParameters()
//
//  MARKET QUERIES
//  getMarketsForHooksTemplate(...)
//  getMarketsForHooksTemplate(...)
//  getMarketsForHooksTemplateCount(...)
//  getMarketsForHooksInstance(...)
//  getMarketsForHooksInstance(...)
//  getMarketsForHooksInstanceCount(...)
//  _slice(...)
// ═════

import './libraries/LibERC20.sol';
import './interfaces/IWildcatArchController.sol';
import './libraries/LibStoredInitCode.sol';
import './libraries/MathUtils.sol';
import './ReentrancyGuard.sol';
import './interfaces/WildcatStructsAndEnums.sol';
import './access/IHooks.sol';
import './IHooksFactory.sol';
import './types/TransientBytesArray.sol';
import './spherex/SphereXProtectedRegisteredBase.sol';
import './access/IHooksAdministrator.sol';
import './interfaces/IBorrowerIdentityRegistry.sol';
import './types/RoleProvider.sol';

/// @dev deployment values outside `DeployMarketInputs`, grouped to stay within the stack limit.
struct DeployMarketRuntimeParameters {
  address borrowerPrincipal;
  address hooksTemplate;
  HooksConfig requestedHooks;
  bytes32 salt;
  address originationFeeAsset;
  uint256 originationFeeAmount;
  /// @dev revolving factory only; the standard factory leaves it zero and never reads it.
  uint16 commitmentFeeBips;
}

// ┌─ HooksFactoryBase ─────────────────────────────────────────────────────────
/// @title Wildcat hooks factory base
///
/// @notice manage hooks templates and instances, then deploy Wildcat markets with them.
///
/// @dev `HooksFactory` and `HooksFactoryRevolving` add their own deployment entry points and any
///      factory-owned market data. market constructors read their parameters back from transient
///      storage. templates hold raw, compressed, or split creation code, recovered before CREATE2
///      deployment.
abstract contract HooksFactoryBase is SphereXProtectedRegisteredBase, ReentrancyGuard, IHooksFactoryBase {
  using LibERC20 for address;

  // ░░▒▒▓▓██ [ DEPLOYMENT CONSTANTS ] ─────────────────────────────────────────

  /// @dev constructor parameters exposed to the market during deployment.
  TransientBytesArray internal constant _tmpMarketParameters =
    TransientBytesArray.wrap(uint256(keccak256('Transient:TmpMarketParametersStorage')) - 1);

  uint256 internal immutable ownCreate2Prefix = LibStoredInitCode.getCreate2Prefix(address(this));

  address public immutable override marketInitCodeStorage;

  uint256 public immutable override marketInitCodeHash;

  address public immutable override sanctionsSentinel;

  address public immutable override wrapperFactory;

  address public immutable override borrowerIdentityRegistry;

  // ░░▒▒▓▓██ [ REGISTRIES ] ───────────────────────────────────────────────────

  address[] internal _hooksTemplates;

  /// @dev hooks instances currently administered by each address.
  mapping(address administrator => address[] hooksInstances) internal _hooksInstancesByAdministrator;

  /// @notice current administrator tracked for each hooks instance, or zero if unknown.
  mapping(address hooksInstance => address administrator) public override getHooksAdministrator;

  /// @dev position of each hooks instance in its administrator's array.
  mapping(address hooksInstance => uint256 index) internal _hooksInstanceIndex;

  /// @notice next CREATE2 deployment nonce for each hooks administrator.
  mapping(address administrator => uint256 nonce) public override getHooksInstanceDeploymentNonce;

  /// @dev markets grouped by template so fee changes can reach every affected market.
  mapping(address hooksTemplate => address[] markets) internal _marketsByHooksTemplate;

  /// @dev markets grouped by hooks instance, primarily for off-chain queries.
  mapping(address hooksInstance => address[] markets) internal _marketsByHooksInstance;

  /// @dev fee configuration and name for each hooks template.
  mapping(address hooksTemplate => HooksTemplate details) internal _templateDetails;

  mapping(address hooksInstance => address hooksTemplate) public override getHooksTemplateForInstance;

  /// @notice immutable artifact commitment for each registered template.
  mapping(address hooksTemplate => bytes32 initCodeHash) public override getHooksTemplateInitCodeHash;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
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

  // ┌─ registerWithArchController ─────
  /// @inheritdoc IHooksFactoryBase
  function registerWithArchController() external override {
    IWildcatArchController(_archController).registerController(address(this));
  }

  // ┌─ archController ─────
  function archController() external view override returns (address) {
    return _archController;
  }

  // ░░▒▒▓▓██ [ HOOKS TEMPLATES ] ──────────────────────────────────────────────

  // ┌─ onlyArchControllerOwner ─────
  modifier onlyArchControllerOwner() {
    if (msg.sender != IWildcatArchController(_archController).owner()) {
      revert CallerNotArchControllerOwner();
    }
    _;
  }

  // ┌─ addHooksTemplate ─────
  /// @dev ArchController-owner-only registration for a hooks template and fee config.
  ///      initCodeHash commits to the compiled template before constructor arguments.
  function addHooksTemplate(
    address hooksTemplate,
    string calldata name,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips,
    bytes32 initCodeHash
  )
    external
    override
    onlyArchControllerOwner
  {
    if (_templateDetails[hooksTemplate].exists) {
      revert HooksTemplateAlreadyExists();
    }
    _validateFees(feeRecipient, originationFeeAsset, originationFeeAmount, protocolFeeBips);
    if (keccak256(LibStoredInitCode.getInitCode(hooksTemplate)) != initCodeHash) {
      revert HooksTemplateInitCodeHashMismatch();
    }
    getHooksTemplateInitCodeHash[hooksTemplate] = initCodeHash;
    _templateDetails[hooksTemplate] = HooksTemplate({
      exists: true,
      name: name,
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
      name,
      feeRecipient,
      originationFeeAsset,
      originationFeeAmount,
      protocolFeeBips
    );
    emit HooksTemplateInitCodeHashRecorded(hooksTemplate, initCodeHash);
  }

  // ┌─ disableHooksTemplate ─────
  /// @dev only the ArchController owner can disable a template. unknown templates revert.
  function disableHooksTemplate(address hooksTemplate) external override onlyArchControllerOwner {
    if (!_templateDetails[hooksTemplate].exists) {
      revert HooksTemplateNotFound();
    }
    // disabling leaves `exists` set. the template can't be re-added or re-enabled.
    _templateDetails[hooksTemplate].enabled = false;
    emit HooksTemplateDisabled(hooksTemplate, msg.sender);
  }

  // ░░▒▒▓▓██ [ TEMPLATE FEES ] ────────────────────────────────────────────────

  // ┌─ updateHooksTemplateFees ─────
  /// @inheritdoc IHooksFactoryBase
  function updateHooksTemplateFees(
    address hooksTemplate,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  )
    external
    override
    onlyArchControllerOwner
  {
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

  // ┌─ _validateFees ─────
  function _validateFees(
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  )
    internal
    pure
  {
    bool hasOriginationFee = originationFeeAmount > 0;
    bool nullFeeRecipient = feeRecipient == address(0);
    bool nullOriginationFeeAsset = originationFeeAsset == address(0);
    if (
      (protocolFeeBips > 0 && nullFeeRecipient) || (hasOriginationFee && nullFeeRecipient)
        || (hasOriginationFee && nullOriginationFeeAsset) || protocolFeeBips > 1_000
    ) {
      revert InvalidFeeConfiguration();
    }
  }

  // ┌─ pushProtocolFeeBipsUpdates ─────
  /// @inheritdoc IHooksFactoryBase
  function pushProtocolFeeBipsUpdates(
    address hooksTemplate,
    uint marketStartIndex,
    uint marketEndIndex
  )
    public
    override
    nonReentrant
  {
    HooksTemplate memory details = _templateDetails[hooksTemplate];
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
      // reuse one setProtocolFeeBips(uint16) calldata buffer for every market.
      setProtocolFeeBipsCalldataPointer := mload(0x40)
      mstore(0x40, add(setProtocolFeeBipsCalldataPointer, 0x40))
      mstore(setProtocolFeeBipsCalldataPointer, 0xae6ea191)
      mstore(add(setProtocolFeeBipsCalldataPointer, 0x20), protocolFeeBips)
      // skip the 28 leading bytes before the right-aligned selector.
      setProtocolFeeBipsCalldataPointer := add(setProtocolFeeBipsCalldataPointer, 0x1c)
    }
    for (uint256 i = 0; i < count; i++) {
      address market = markets[marketStartIndex + i];
      assembly {
        // isClosed() includes funded repayment closure that hasn't been written yet.
        mstore(0, 0xc2b6b58c)
        let success := staticcall(gas(), market, 0x1c, 0x04, 0, 0x20)
        // require a complete, canonical bool. failed reads must not silently skip a market.
        if or(lt(returndatasize(), 0x20), gt(mload(0), 1)) {
          success := 0
        }
        if and(success, iszero(mload(0))) {
          success := call(gas(), market, 0, setProtocolFeeBipsCalldataPointer, 0x24, 0, 0)
        }
        if iszero(success) {
          // equivalent to `revert SetProtocolFeeBipsFailed()`
          mstore(0, 0x4484a4a9)
          revert(0x1c, 0x04)
        }
      }
    }
  }

  // ┌─ pushProtocolFeeBipsUpdates ─────
  /// @inheritdoc IHooksFactoryBase
  function pushProtocolFeeBipsUpdates(address hooksTemplate) external override {
    pushProtocolFeeBipsUpdates(hooksTemplate, 0, type(uint256).max);
  }

  // ░░▒▒▓▓██ [ TEMPLATE QUERIES ] ─────────────────────────────────────────────

  // ┌─ getHooksTemplateDetails ─────
  function getHooksTemplateDetails(address hooksTemplate) external view override returns (HooksTemplate memory) {
    return _templateDetails[hooksTemplate];
  }

  // ┌─ isHooksTemplate ─────
  function isHooksTemplate(address hooksTemplate) external view override returns (bool) {
    return _templateDetails[hooksTemplate].exists;
  }

  // ┌─ getHooksTemplates ─────
  function getHooksTemplates() external view override returns (address[] memory) {
    return _hooksTemplates;
  }

  // ┌─ getHooksTemplates ─────
  function getHooksTemplates(uint256 start, uint256 end) external view override returns (address[] memory arr) {
    return _slice(_hooksTemplates, start, end);
  }

  // ┌─ getHooksTemplatesCount ─────
  function getHooksTemplatesCount() external view override returns (uint256) {
    return _hooksTemplates.length;
  }

  // ░░▒▒▓▓██ [ HOOKS DEPLOYMENT ] ─────────────────────────────────────────────

  // ┌─ deployHooksInstance ─────
  /// @dev deploy an approved template under the caller's resolved principal.
  ///      origination fees apply when a market uses the instance, not when the instance is created.
  function deployHooksInstance(
    address hooksTemplate,
    bytes calldata constructorArgs
  )
    external
    override
    nonReentrant
    returns (address hooksInstance)
  {
    address administrator = _resolveBorrowerPrincipal(msg.sender);
    hooksInstance = _deployHooksInstance(administrator, hooksTemplate, constructorArgs);
  }

  // ┌─ _deployHooksInstance ─────
  /// @dev checks that the template exists before anything else, so callers can rely on its
  ///      `HooksTemplateNotFound` instead of checking first. templates are never removed.
  function _deployHooksInstance(
    address administrator,
    address hooksTemplate,
    bytes calldata constructorArgs
  )
    internal
    returns (address hooksInstance)
  {
    HooksTemplate storage template = _templateDetails[hooksTemplate];
    if (!template.exists) {
      revert HooksTemplateNotFound();
    }
    if (!template.enabled) {
      revert HooksTemplateNotAvailable();
    }

    uint256 deploymentNonce = getHooksInstanceDeploymentNonce[administrator];
    bytes32 salt;
    bytes memory initCode = LibStoredInitCode.getInitCode(hooksTemplate);
    // hash these bytes before appending instance arguments, then pass the same buffer to CREATE2.
    if (keccak256(initCode) != getHooksTemplateInitCodeHash[hooksTemplate]) {
      revert HooksTemplateInitCodeHashMismatch();
    }
    assembly {
      salt := or(shl(96, administrator), deploymentNonce)
      let initCodePointer := add(initCode, 0x20)
      let initCodeSize := mload(initCode)
      let endInitCodePointer := add(initCodePointer, initCodeSize)
      // append ABI-encoded (administrator, constructorArgs) after the initcode.
      mstore(endInitCodePointer, administrator)
      mstore(add(endInitCodePointer, 0x20), 0x40)
      let constructorArgsSize := constructorArgs.length
      mstore(add(endInitCodePointer, 0x40), constructorArgsSize)
      calldatacopy(add(endInitCodePointer, 0x60), constructorArgs.offset, constructorArgsSize)
      let initCodeSizeWithArgs := add(add(initCodeSize, 0x60), constructorArgsSize)
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
    (bool metadataAvailable, RoleProvider[] memory pullProviders, RoleProvider[] memory pushProviders) =
      getHooksInstanceRoleProviders(hooksInstance);
    emit HooksInstanceRoleProviders(hooksInstance, metadataAvailable, pullProviders, pushProviders);
    getHooksTemplateForInstance[hooksInstance] = hooksTemplate;
  }

  // ┌─ _resolveBorrowerPrincipal ─────
  function _resolveBorrowerPrincipal(address borrower) internal view returns (address principal) {
    (bool success, bytes memory returnData) =
      borrowerIdentityRegistry.staticcall(abi.encodeCall(IBorrowerIdentityRegistry.resolveBorrower, (borrower)));
    if (!success || returnData.length != 0x20) revert NotApprovedBorrower();
    principal = abi.decode(returnData, (address));
    if (principal == address(0)) revert NotApprovedBorrower();
  }

  // ┌─ isHooksInstance ─────
  /// @inheritdoc IHooksFactoryBase
  function isHooksInstance(address hooksInstance) external view override returns (bool) {
    return getHooksTemplateForInstance[hooksInstance] != address(0);
  }

  // ░░▒▒▓▓██ [ HOOKS ADMINISTRATION ] ─────────────────────────────────────────

  // ┌─ onHooksAdministratorTransferred ─────
  /// @inheritdoc IHooksFactoryBase
  function onHooksAdministratorTransferred(
    address previousAdministrator,
    address newAdministrator
  )
    external
    override
    nonReentrant
  {
    address hooksInstance = msg.sender;
    if (getHooksTemplateForInstance[hooksInstance] == address(0)) {
      revert HooksInstanceNotFound();
    }
    if (
      previousAdministrator == newAdministrator || newAdministrator == address(0)
        || getHooksAdministrator[hooksInstance] != previousAdministrator
        || IHooksAdministrator(hooksInstance).administrator() != newAdministrator
        || IHooksAdministrator(hooksInstance).pendingAdministrator() != address(0)
        || !IWildcatArchController(_archController).isRegisteredBorrower(newAdministrator)
    ) {
      revert InvalidHooksAdministrator();
    }

    address[] storage previousHooksInstances = _hooksInstancesByAdministrator[previousAdministrator];
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

    emit HooksInstanceAdministratorTransferred(hooksInstance, previousAdministrator, newAdministrator);
  }

  // ┌─ getHooksInstancesForAdministrator ─────
  function getHooksInstancesForAdministrator(address administrator) external view override returns (address[] memory) {
    return _hooksInstancesByAdministrator[administrator];
  }

  // ┌─ getHooksInstancesForAdministrator ─────
  function getHooksInstancesForAdministrator(
    address administrator,
    uint256 start,
    uint256 end
  )
    external
    view
    override
    returns (address[] memory arr)
  {
    return _slice(_hooksInstancesByAdministrator[administrator], start, end);
  }

  // ┌─ getHooksInstancesCountForAdministrator ─────
  function getHooksInstancesCountForAdministrator(address administrator) external view override returns (uint256) {
    return _hooksInstancesByAdministrator[administrator].length;
  }

  // ┌─ getHooksInstancesForBorrower ─────
  function getHooksInstancesForBorrower(address borrower) external view override returns (address[] memory) {
    return _hooksInstancesByAdministrator[borrower];
  }

  // ┌─ getHooksInstancesCountForBorrower ─────
  function getHooksInstancesCountForBorrower(address borrower) external view override returns (uint256) {
    return _hooksInstancesByAdministrator[borrower].length;
  }

  // ░░▒▒▓▓██ [ MARKET DEPLOYMENT ] ────────────────────────────────────────────

  // ┌─ _deployMarket ─────
  /// @dev callers resolve the borrower principal and hooks template, and decode any factory-owned
  ///      market data, before deploying through here.
  function _deployMarket(
    DeployMarketInputs memory parameters,
    bytes calldata hooksData,
    DeployMarketRuntimeParameters memory runtimeParams
  )
    internal
    returns (address market)
  {
    HooksTemplate memory templateDetails = _templateDetails[runtimeParams.hooksTemplate];
    if (IWildcatArchController(_archController).isBlacklistedAsset(parameters.asset)) {
      revert AssetBlacklisted();
    }
    address hooksInstance = parameters.hooks.hooksAddress();

    if (address(bytes20(runtimeParams.salt)) != msg.sender) {
      revert SaltDoesNotContainSender();
    }

    if (
      runtimeParams.originationFeeAsset != templateDetails.originationFeeAsset
        || runtimeParams.originationFeeAmount != templateDetails.originationFeeAmount
    ) {
      revert FeeMismatch();
    }

    // positive template fees need a token and recipient; zero fees need no token call.
    if (runtimeParams.originationFeeAmount != 0) {
      runtimeParams.originationFeeAsset
        .safeTransferFrom(msg.sender, templateDetails.feeRecipient, runtimeParams.originationFeeAmount);
    }

    market = LibStoredInitCode.calculateCreate2Address(ownCreate2Prefix, runtimeParams.salt, marketInitCodeHash);

    parameters.hooks =
      IHooks(hooksInstance).onCreateMarket(runtimeParams.borrowerPrincipal, market, parameters, hooksData);
    uint8 decimals = parameters.asset.decimals();

    string memory name = string.concat(parameters.namePrefix, parameters.asset.name());
    string memory symbol = string.concat(parameters.symbolPrefix, parameters.asset.symbol());

    // everything except sphereXEngine, which getMarketParameters reads live.
    MarketParameters memory marketParameters;
    marketParameters.asset = parameters.asset;
    marketParameters.decimals = decimals;
    marketParameters.borrower = msg.sender;
    marketParameters.feeRecipient = templateDetails.feeRecipient;
    marketParameters.sentinel = sanctionsSentinel;
    marketParameters.wrapperFactory = wrapperFactory;
    marketParameters.maxTotalSupply = parameters.maxTotalSupply;
    marketParameters.protocolFeeBips = templateDetails.protocolFeeBips;
    marketParameters.annualInterestBips = parameters.annualInterestBips;
    marketParameters.delinquencyFeeBips = parameters.delinquencyFeeBips;
    marketParameters.withdrawalBatchDuration = parameters.withdrawalBatchDuration;
    marketParameters.reserveRatioBips = parameters.reserveRatioBips;
    marketParameters.delinquencyGracePeriod = parameters.delinquencyGracePeriod;
    marketParameters.archController = _archController;
    marketParameters.hooks = parameters.hooks;
    marketParameters.borrowerPrincipal = runtimeParams.borrowerPrincipal;
    marketParameters.borrowerIdentityRegistry = borrowerIdentityRegistry;
    marketParameters.repaymentDate = parameters.repaymentDate;
    marketParameters.repaymentPeriod = parameters.repaymentPeriod;
    (marketParameters.packedNameWord0, marketParameters.packedNameWord1) = _packString(name);
    (marketParameters.packedSymbolWord0, marketParameters.packedSymbolWord1) = _packString(symbol);

    _tmpMarketParameters.write(abi.encode(marketParameters));
    _storeMarketData(runtimeParams);

    if (market.code.length != 0) {
      revert MarketAlreadyExists();
    }
    {
      bytes memory initCode = LibStoredInitCode.getInitCode(marketInitCodeStorage);
      // check the artifact hash before executing its constructor. use these same decoded bytes.
      if (uint256(keccak256(initCode)) != marketInitCodeHash) {
        revert MarketDeploymentAddressMismatch();
      }
      if (LibStoredInitCode.create2WithInitCode(initCode, runtimeParams.salt, 0) != market) {
        revert MarketDeploymentAddressMismatch();
      }
    }

    IWildcatArchController(_archController).registerMarket(market);

    _tmpMarketParameters.setEmpty();
    _clearMarketData();

    _marketsByHooksTemplate[runtimeParams.hooksTemplate].push(market);
    _marketsByHooksInstance[hooksInstance].push(market);

    _emitMarketDeployment(market, name, symbol, marketParameters, runtimeParams, hooksData);
  }

  // ┌─ _packString ─────
  /// @dev pack up to 63 bytes into two words. word 0 holds one length byte and 31 string bytes;
  ///      word 1 holds the remaining 32 bytes. longer strings revert.
  function _packString(string memory str) internal pure returns (bytes32 word0, bytes32 word1) {
    assembly {
      let length := mload(str)
      // equivalent to:
      // if (str.length > 63) revert NameOrSymbolTooLong();
      if gt(length, 0x3f) {
        mstore(0, 0x19a65cb6)
        revert(0x1c, 0x04)
      }
      // +31 keeps only the low length byte, followed by the first 31 string bytes.
      word0 := mload(add(str, 0x1f))
      // short strings don't use word 1; discard whatever follows them in memory.
      word1 := mul(mload(add(str, 0x3f)), gt(mload(str), 0x1f))
    }
  }

  // ┌─ _emitMarketDeployment ─────
  function _emitMarketDeployment(
    address market,
    string memory name,
    string memory symbol,
    MarketParameters memory marketParameters,
    DeployMarketRuntimeParameters memory runtimeParams,
    bytes calldata hooksData
  )
    internal
  {
    emit MarketDeployed(
      runtimeParams.hooksTemplate,
      runtimeParams.requestedHooks.hooksAddress(),
      market,
      marketParameters.borrower,
      runtimeParams.borrowerPrincipal,
      borrowerIdentityRegistry,
      name,
      symbol,
      marketParameters.asset,
      runtimeParams.requestedHooks,
      marketParameters.hooks
    );
    emit MarketDeploymentConfig(
      market,
      marketParameters.maxTotalSupply,
      marketParameters.annualInterestBips,
      marketParameters.delinquencyFeeBips,
      marketParameters.withdrawalBatchDuration,
      marketParameters.reserveRatioBips,
      marketParameters.delinquencyGracePeriod,
      marketParameters.feeRecipient,
      marketParameters.protocolFeeBips,
      runtimeParams.originationFeeAsset,
      runtimeParams.originationFeeAmount
    );
    emit MarketHooksData(market, hooksData);
    _emitMarketData(market, runtimeParams);
    emit MarketRepaymentTerms(market, marketParameters.repaymentDate, marketParameters.repaymentPeriod);
  }

  // ┌─ computeMarketAddress ─────
  /// @dev returns the CREATE2 market address for `salt` and this factory's init code.
  ///      the first 20 bytes name the deployer and can't be zero. deployment also
  ///      requires that address to be `msg.sender`.
  function computeMarketAddress(bytes32 salt) external view override returns (address) {
    if (bytes20(salt) == bytes20(0)) revert SaltDoesNotContainSender();
    return LibStoredInitCode.calculateCreate2Address(ownCreate2Prefix, salt, marketInitCodeHash);
  }

  // ░░▒▒▓▓██ [ MARKET DATA ] ──────────────────────────────────────────────────

  // ┌─ _storeMarketData ─────
  /// @dev expose factory-owned market data to the market constructor, next to its parameters.
  function _storeMarketData(DeployMarketRuntimeParameters memory runtimeParams) internal virtual { }

  // ┌─ _clearMarketData ─────
  /// @dev clear anything `_storeMarketData` wrote once the market is registered.
  function _clearMarketData() internal virtual { }

  // ┌─ _emitMarketData ─────
  /// @dev emit factory-owned market data between `MarketHooksData` and `MarketRepaymentTerms`.
  function _emitMarketData(address market, DeployMarketRuntimeParameters memory runtimeParams) internal virtual { }

  // ░░▒▒▓▓██ [ CONSTRUCTOR PARAMETERS ] ───────────────────────────────────────

  // ┌─ getMarketParameters ─────
  /// @inheritdoc IHooksFactoryBase
  function getMarketParameters() external view override returns (MarketParameters memory parameters) {
    parameters = abi.decode(_tmpMarketParameters.read(), (MarketParameters));
    parameters.sphereXEngine = IWildcatArchController(_archController).sphereXEngine();
  }

  // ░░▒▒▓▓██ [ MARKET QUERIES ] ───────────────────────────────────────────────

  // ┌─ getMarketsForHooksTemplate ─────
  function getMarketsForHooksTemplate(address hooksTemplate) external view override returns (address[] memory) {
    return _marketsByHooksTemplate[hooksTemplate];
  }

  // ┌─ getMarketsForHooksTemplate ─────
  function getMarketsForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    external
    view
    override
    returns (address[] memory arr)
  {
    return _slice(_marketsByHooksTemplate[hooksTemplate], start, end);
  }

  // ┌─ getMarketsForHooksTemplateCount ─────
  function getMarketsForHooksTemplateCount(address hooksTemplate) external view override returns (uint256) {
    return _marketsByHooksTemplate[hooksTemplate].length;
  }

  // ┌─ getMarketsForHooksInstance ─────
  function getMarketsForHooksInstance(address hooksInstance) external view override returns (address[] memory) {
    return _marketsByHooksInstance[hooksInstance];
  }

  // ┌─ getMarketsForHooksInstance ─────
  function getMarketsForHooksInstance(
    address hooksInstance,
    uint256 start,
    uint256 end
  )
    external
    view
    override
    returns (address[] memory arr)
  {
    return _slice(_marketsByHooksInstance[hooksInstance], start, end);
  }

  // ┌─ getMarketsForHooksInstanceCount ─────
  function getMarketsForHooksInstanceCount(address hooksInstance) external view override returns (uint256) {
    return _marketsByHooksInstance[hooksInstance].length;
  }

  // ┌─ _slice ─────
  /// @dev return `values` in `[start, min(end, length))`. an empty or out-of-bounds range is empty.
  function _slice(address[] storage values, uint256 start, uint256 end) internal view returns (address[] memory arr) {
    end = MathUtils.min(end, values.length);
    if (start >= end) return new address[](0);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = values[start + i];
    }
  }
}
