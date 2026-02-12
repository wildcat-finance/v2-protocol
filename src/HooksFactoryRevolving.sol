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

contract HooksFactoryRevolving is
  SphereXProtectedRegisteredBase,
  ReentrancyGuard,
  IHooksFactoryRevolving
{
  using LibERC20 for address;

  TransientBytesArray internal constant _tmpMarketParameters =
    TransientBytesArray.wrap(uint256(keccak256('Transient:TmpRevolvingMarketParameterStorage')) - 1);

  uint256 internal immutable ownCreate2Prefix = LibStoredInitCode.getCreate2Prefix(address(this));

  address public immutable override marketInitCodeStorage;

  uint256 public immutable override marketInitCodeHash;

  address public immutable override sanctionsSentinel;

  function name() external pure override returns (string memory) {
    // NOTE(rcf-v2): Legacy `HooksFactory.name()` uses a Yul implementation for
    // size/gas micro-optimization. Keep this readable Solidity form during
    // rollout bring-up, then consider parity optimization in a follow-up.
    return 'WildcatHooksFactoryRevolving';
  }

  address[] internal _hooksTemplates;

  /// @dev Mapping from borrower to their deployed hooks instances
  mapping(address borrower => address[] hooksInstances) internal _hooksInstancesByBorrower;

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
    override
    getHooksTemplateForInstance;

  constructor(
    address archController_,
    address _sanctionsSentinel,
    address _marketInitCodeStorage,
    uint256 _marketInitCodeHash
  ) {
    marketInitCodeStorage = _marketInitCodeStorage;
    marketInitCodeHash = _marketInitCodeHash;
    _archController = archController_;
    sanctionsSentinel = _sanctionsSentinel;
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

  function _getTmpMarketParameters()
    internal
    view
    returns (TmpRevolvingMarketParameterStorage memory parameters)
  {
    return abi.decode(_tmpMarketParameters.read(), (TmpRevolvingMarketParameterStorage));
  }

  function _setTmpMarketParameters(TmpRevolvingMarketParameterStorage memory parameters) internal {
    _tmpMarketParameters.write(abi.encode(parameters));
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
    template.feeRecipient = feeRecipient;
    template.originationFeeAsset = originationFeeAsset;
    template.originationFeeAmount = originationFeeAmount;
    template.protocolFeeBips = protocolFeeBips;
    emit HooksTemplateFeesUpdated(
      hooksTemplate,
      feeRecipient,
      originationFeeAsset,
      originationFeeAmount,
      protocolFeeBips
    );
  }

  function disableHooksTemplate(address hooksTemplate) external override onlyArchControllerOwner {
    if (!_templateDetails[hooksTemplate].exists) {
      revert HooksTemplateNotFound();
    }
    _templateDetails[hooksTemplate].enabled = false;
    emit HooksTemplateDisabled(hooksTemplate);
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

  function deployHooksInstance(
    address hooksTemplate,
    bytes calldata constructorArgs
  ) external override nonReentrant returns (address hooksInstance) {
    if (!IWildcatArchController(_archController).isRegisteredBorrower(msg.sender)) {
      revert NotApprovedBorrower();
    }
    hooksInstance = _deployHooksInstance(hooksTemplate, constructorArgs);
  }

  function getHooksInstancesForBorrower(
    address borrower
  ) external view override returns (address[] memory) {
    return _hooksInstancesByBorrower[borrower];
  }

  function getHooksInstancesCountForBorrower(
    address borrower
  ) external view override returns (uint256) {
    return _hooksInstancesByBorrower[borrower].length;
  }

  function isHooksInstance(address hooksInstance) external view override returns (bool) {
    return getHooksTemplateForInstance[hooksInstance] != address(0);
  }

  function _deployHooksInstance(
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

    uint256 numHooksForBorrower = _hooksInstancesByBorrower[msg.sender].length;
    bytes32 salt;
    assembly {
      salt := or(shl(96, caller()), numHooksForBorrower)
      let initCodePointer := mload(0x40)
      let initCodeSize := sub(extcodesize(hooksTemplate), 1)
      extcodecopy(hooksTemplate, initCodePointer, 1, initCodeSize)
      let endInitCodePointer := add(initCodePointer, initCodeSize)
      mstore(endInitCodePointer, caller())
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
    _hooksInstancesByBorrower[msg.sender].push(hooksInstance);
    emit HooksInstanceDeployed(hooksInstance, hooksTemplate);
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
  }

  function computeMarketAddress(bytes32 salt) external view override returns (address) {
    return LibStoredInitCode.calculateCreate2Address(ownCreate2Prefix, salt, marketInitCodeHash);
  }

  function deployMarket(
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes calldata marketData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external override nonReentrant returns (address market) {
    parameters;
    hooksData;
    marketData;
    salt;
    originationFeeAsset;
    originationFeeAmount;
    market;
    revert DeploymentFailed();
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
    hooksTemplate;
    hooksConstructorArgs;
    parameters;
    hooksData;
    marketData;
    salt;
    originationFeeAsset;
    originationFeeAmount;
    market;
    hooksInstance;
    revert DeploymentFailed();
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
    HooksTemplate memory details = _templateDetails[hooksTemplate];
    if (!details.exists) revert HooksTemplateNotFound();

    address[] storage markets = _marketsByHooksTemplate[hooksTemplate];
    marketEndIndex = MathUtils.min(marketEndIndex, markets.length);
    uint256 count = marketEndIndex - marketStartIndex;
    uint256 setProtocolFeeBipsCalldataPointer;
    uint16 protocolFeeBips = details.protocolFeeBips;
    assembly {
      setProtocolFeeBipsCalldataPointer := mload(0x40)
      mstore(0x40, add(setProtocolFeeBipsCalldataPointer, 0x40))
      mstore(setProtocolFeeBipsCalldataPointer, 0xae6ea191) // setProtocolFeeBips(uint16)
      mstore(add(setProtocolFeeBipsCalldataPointer, 0x20), protocolFeeBips)
      setProtocolFeeBipsCalldataPointer := add(setProtocolFeeBipsCalldataPointer, 0x1c)
    }
    for (uint256 i = 0; i < count; i++) {
      address market = markets[marketStartIndex + i];
      assembly {
        if iszero(call(gas(), market, 0, setProtocolFeeBipsCalldataPointer, 0x24, 0, 0)) {
          mstore(0, 0x4484a4a9) // SetProtocolFeeBipsFailed()
          revert(0x1c, 0x04)
        }
      }
    }
  }

  function pushProtocolFeeBipsUpdates(address hooksTemplate) external override {
    pushProtocolFeeBipsUpdates(hooksTemplate, 0, type(uint256).max);
  }
}
