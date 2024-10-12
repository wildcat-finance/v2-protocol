// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { console, console2, StdAssertions, StdChains, StdCheats, stdError, StdInvariant, stdJson, stdMath, StdStorage, stdStorage, StdUtils, Vm, StdStyle, Test as ForgeTest } from 'forge-std/Test.sol';
import { VmSafe } from 'forge-std/Vm.sol';
import { Prankster } from 'sol-utils/test/Prankster.sol';

import 'src/WildcatArchController.sol';
import '../helpers/VmUtils.sol' as VmUtils;
import '../helpers/Assertions.sol';
import { MockEngine } from './mocks/MockEngine.sol';
import './mocks/MockSanctionsSentinel.sol';
import { deployMockChainalysis } from './mocks/MockChainalysis.sol';
import { AlwaysAuthorizedRoleProvider } from './mocks/AlwaysAuthorizedRoleProvider.sol';
import { MockRoleProvider } from './mocks/MockRoleProvider.sol';
import { HooksFactory, IHooksFactoryEventsAndErrors } from 'src/HooksFactory.sol';
import { MockHooks } from './mocks/MockHooks.sol';
import 'src/libraries/LibStoredInitCode.sol';
import 'src/market/WildcatMarket.sol';
import 'src/access/AccessControlHooks.sol';
import { AccessControlHooksFuzzInputs, AccessControlHooksFuzzContext, LibAccessControlHooksFuzzContext, createAccessControlHooksFuzzContext, FunctionKind } from '../helpers/fuzz/AccessControlHooksFuzzContext.sol';

struct MarketInputParameters {
  address asset;
  string namePrefix;
  string symbolPrefix;
  address borrower;
  address feeRecipient;
  address sentinel;
  uint128 maxTotalSupply;
  uint16 protocolFeeBips;
  uint16 annualInterestBips;
  uint16 delinquencyFeeBips;
  uint32 withdrawalBatchDuration;
  uint16 reserveRatioBips;
  uint32 delinquencyGracePeriod;
  address sphereXEngine;
  address hooksTemplate;
  bytes deployHooksConstructorArgs;
  bytes deployMarketHooksData;
  HooksConfig hooksConfig;
  uint128 minimumDeposit;
  bool transfersDisabled;
  bool allowForceBuyBack;
}

contract Test is ForgeTest, Prankster, Assertions {
  HooksFactory internal hooksFactory;
  WildcatArchController internal archController;
  AccessControlHooks internal hooks;
  WildcatMarket internal market;
  MockSanctionsSentinel internal sanctionsSentinel;
  MockRoleProvider internal ecdsaRoleProvider;
  MockRoleProvider internal roleProvider1;
  MockRoleProvider internal roleProvider2;
  address internal hooksTemplate;
  address internal SphereXAdmin = address(this);
  address internal SphereXOperator = address(0x08374708);
  address internal SphereXEngine;
  uint internal numDeployedMarkets;
  uint internal roleProviderSignerPrivateKey;
  bool depositRequiresAccess;
  bool transferRequiresAccess;

  function _nextSalt(address borrower) internal returns (bytes32 salt) {
    return bytes32((uint256(uint160(borrower)) << 96) | numDeployedMarkets++);
  }

  modifier asSelf() {
    startPrank(address(this));
    _;
    stopPrank();
  }

  constructor() {
    deployBaseContracts();
    // Set block.timestamp to 4:50 am, May 3 2024
    VmUtils.warp(1714737030);
  }

  function _storeMarketInitCode()
    internal
    virtual
    returns (address initCodeStorage, uint256 initCodeHash)
  {
    bytes memory marketInitCode = type(WildcatMarket).creationCode;
    initCodeHash = uint256(keccak256(marketInitCode));
    initCodeStorage = LibStoredInitCode.deployInitCode(marketInitCode);
  }

  function deployBaseContracts(bool withEngine) internal asSelf {
    deployMockChainalysis();
    archController = new WildcatArchController();
    if (withEngine) {
      deploySphereXEngine();
    } else {
      SphereXEngine = address(0);
    }
    // Update the SphereXOperator and SphereXEngine on the ArchController
    updateArchControllerEngine();
    sanctionsSentinel = new MockSanctionsSentinel(address(archController));

    (address marketTemplate, uint256 marketInitCodeHash) = _storeMarketInitCode();
    hooksFactory = new HooksFactory(
      address(archController),
      address(sanctionsSentinel),
      marketTemplate,
      marketInitCodeHash
    );

    // Register the hooks factory as a controller factory so it can register
    // itself as a controller with the ArchController
    archController.registerControllerFactory(address(hooksFactory));
    _checkSphereXConfig(address(hooksFactory), 'HooksFactory');
    vm.expectEmit(address(archController));
    emit ControllerAdded(address(hooksFactory), address(hooksFactory));

    // Have the hooks factory register itself as a controller so it can
    // register markets.
    hooksFactory.registerWithArchController();
    _checkSphereXConfig(address(hooksFactory), 'HooksFactory');

    // Deploy initcode storage for hooks template
    if (hooksTemplate == address(0)) {
      hooksTemplate = _getHooksTemplate();
    }
    vm.expectEmit(address(hooksFactory));
    emit IHooksFactoryEventsAndErrors.HooksTemplateAdded(
      hooksTemplate,
      'SingleBorrowerAccessControlHooks',
      address(0),
      address(0),
      0,
      0
    );
    hooksFactory.addHooksTemplate(
      hooksTemplate,
      'SingleBorrowerAccessControlHooks',
      address(0),
      address(0),
      0,
      0
    );

    // Deploy a role provider for the hooks
    ecdsaRoleProvider = new MockRoleProvider();
    VmSafe.Wallet memory wallet = vm.createWallet('roleProviderSigner');
    roleProviderSignerPrivateKey = wallet.privateKey;
    ecdsaRoleProvider.setRequiredSigner(wallet.addr);
    roleProvider1 = new MockRoleProvider();
    roleProvider2 = new MockRoleProvider();
  }

  function _getHooksTemplate() internal virtual returns (address) {
    return LibStoredInitCode.deployInitCode(type(AccessControlHooks).creationCode);
  }

  function deployBaseContracts() internal {
    deployBaseContracts(true);
  }

  function updateArchControllerEngine() internal asSelf {
    if (archController.sphereXOperator() != SphereXOperator) {
      archController.changeSphereXOperator(SphereXOperator);
    }
    startPrank(SphereXOperator);
    archController.changeSphereXEngine(SphereXEngine);
    stopPrank();
  }

  function deploySphereXEngine() internal asSelf {
    SphereXEngine = address(new MockEngine(archController));
    archController.changeSphereXOperator(SphereXOperator);
    startPrank(SphereXOperator);
    archController.changeSphereXEngine(SphereXEngine);
    stopPrank();
  }

  function _checkSphereXConfig(address contractAddress, string memory label) internal asSelf {
    SphereXProtectedRegisteredBase _contract = SphereXProtectedRegisteredBase(contractAddress);
    assertEq(
      _contract.sphereXOperator(),
      address(archController),
      string.concat(label, ': sphereXOperator')
    );
    assertEq(_contract.sphereXEngine(), SphereXEngine, string.concat(label, ': sphereXEngine'));
  }

  event ControllerAdded(address indexed controllerFactory, address controller);
  event ChangedSpherexOperator(address oldSphereXAdmin, address newSphereXAdmin);
  event ChangedSpherexEngineAddress(address oldEngineAddress, address newEngineAddress);
  event SpherexAdminTransferStarted(address currentAdmin, address pendingAdmin);
  event SpherexAdminTransferCompleted(address oldAdmin, address newAdmin);
  event NewAllowedSenderOnchain(address sender);
  event NewController(address borrower, address controller);
  event MarketAdded(address indexed controller, address market);
  event NewSenderOnEngine(address sender);

  function getNextInstanceAddress(
    address hooksTemplate,
    address borrower,
    bytes memory constructorArgs
  ) internal view returns (address) {
    uint256 initCodeHash;

    assembly {
      let initCodePointer := mload(0x40)
      let initCodeSize := sub(extcodesize(hooksTemplate), 1)
      // Copy code from target address to memory starting at byte 1
      extcodecopy(hooksTemplate, initCodePointer, 1, initCodeSize)
      let endInitCodePointer := add(initCodePointer, initCodeSize)
      // Write the address of the caller as the first parameter
      mstore(endInitCodePointer, borrower)
      // Write the offset to the encoded constructor args
      mstore(add(endInitCodePointer, 0x20), 0x40)
      // Write the length of the encoded constructor args
      let constructorArgsSize := mload(constructorArgs)
      mstore(add(endInitCodePointer, 0x40), constructorArgsSize)
      // Copy constructor args to initcode after the bytes length
      mcopy(add(endInitCodePointer, 0x60), add(constructorArgs, 0x20), constructorArgsSize)
      // Get the full size of the initcode with the constructor args
      let initCodeSizeWithArgs := add(add(initCodeSize, 0x60), constructorArgsSize)
      initCodeHash := keccak256(initCodePointer, initCodeSizeWithArgs)
    }

    uint256 numPreviousInstances = hooksFactory.getHooksInstancesCountForBorrower(borrower);
    bytes32 salt;

    assembly {
      salt := or(shl(96, borrower), numPreviousInstances)
    }

    return
      LibStoredInitCode.calculateCreate2Address(
        LibStoredInitCode.getCreate2Prefix(address(hooksFactory)),
        salt,
        initCodeHash
      );
  }

  function deployHooksInstance(
    MarketInputParameters memory parameters,
    bool authorizeAll
  ) internal asSelf returns (AccessControlHooks hooksInstance) {
    if (!archController.isRegisteredBorrower(parameters.borrower)) {
      archController.registerBorrower(parameters.borrower);
    }
    if (parameters.hooksTemplate == address(0)) {
      parameters.hooksTemplate = hooksTemplate;
    }
    startPrank(parameters.borrower);
    bool emptyConfig = HooksConfig.unwrap(parameters.hooksConfig) == 0;
    if (parameters.hooksConfig.hooksAddress() == address(0)) {
      uint previousCount = hooksFactory.getHooksInstancesCountForBorrower(parameters.borrower);
      hooksInstance = AccessControlHooks(
        getNextInstanceAddress(
          parameters.hooksTemplate,
          parameters.borrower,
          parameters.deployHooksConstructorArgs
        )
      );
      vm.expectEmit(address(hooksFactory));
      emit IHooksFactoryEventsAndErrors.HooksInstanceDeployed(
        address(hooksInstance),
        parameters.hooksTemplate
      );
      assertEq(
        hooksFactory.deployHooksInstance(
          parameters.hooksTemplate,
          parameters.deployHooksConstructorArgs
        ),
        address(hooksInstance),
        'hooksInstance address'
      );
      parameters.hooksConfig = parameters.hooksConfig.setHooksAddress(address(hooksInstance));
      assertEq(
        hooksFactory.getHooksInstancesCountForBorrower(parameters.borrower),
        previousCount + 1,
        'did not update instance count for borrower'
      );
      address[] memory instances = hooksFactory.getHooksInstancesForBorrower(parameters.borrower);
      assertEq(
        instances[instances.length - 1],
        address(hooksInstance),
        'did not add instance to borrower list'
      );
    } else {
      hooksInstance = AccessControlHooks(parameters.hooksConfig.hooksAddress());
    }
    if (emptyConfig) {
      HooksDeploymentConfig _config = hooksInstance.config();
      // Enable all hooks by default, other than transfer
      HooksConfig config = _config
        .optionalFlags()
        .setHooksAddress(address(hooksInstance))
        .mergeAllFlags(_config.requiredFlags())
        .clearFlag(Bit_Enabled_Transfer);
      parameters.hooksConfig = config;
    }
    if (authorizeAll) {
      AlwaysAuthorizedRoleProvider provider = new AlwaysAuthorizedRoleProvider();
      hooksInstance.addRoleProvider(address(provider), type(uint32).max);
    }
    hooksInstance.addRoleProvider(address(ecdsaRoleProvider), type(uint32).max);
    stopPrank();
    hooks = hooksInstance;
  }

  event UpdateProtocolFeeConfiguration(
    address feeRecipient,
    uint16 protocolFeeBips,
    address originationFeeAsset,
    uint256 originationFeeAmount
  );

  function updateFeeConfiguration(MarketInputParameters memory parameters) internal asSelf {
    vm.expectEmit(address(hooksFactory));
    emit IHooksFactoryEventsAndErrors.HooksTemplateFeesUpdated(
      parameters.hooksTemplate,
      parameters.feeRecipient,
      address(0),
      0,
      parameters.protocolFeeBips
    );

    hooksFactory.updateHooksTemplateFees(
      parameters.hooksTemplate,
      parameters.feeRecipient,
      address(0),
      0,
      parameters.protocolFeeBips
    );
  }

  function _expectMarketDeployedEvents(
    MarketInputParameters memory parameters,
    address expectedMarket
  ) internal {
    if (
      parameters.minimumDeposit > 0 &&
      keccak256(bytes(hooksFactory.getHooksTemplateDetails(parameters.hooksTemplate).name)) ==
      keccak256('SingleBorrowerAccessControlHooks')
    ) {
      vm.expectEmit(parameters.hooksConfig.hooksAddress());
      emit AccessControlHooks.MinimumDepositUpdated(expectedMarket, parameters.minimumDeposit);
    }

    vm.expectEmit(expectedMarket);
    emit ChangedSpherexOperator(address(0), address(archController));

    vm.expectEmit(expectedMarket);
    emit ChangedSpherexEngineAddress(address(0), SphereXEngine);

    if (SphereXEngine != address(0)) {
      vm.expectEmit(SphereXEngine);
      emit NewSenderOnEngine(expectedMarket);
      vm.expectEmit(address(archController));
      emit NewAllowedSenderOnchain(expectedMarket);
    }

    vm.expectEmit(address(archController));
    emit MarketAdded(address(hooksFactory), expectedMarket);

    string memory expectedName = string.concat(
      parameters.namePrefix,
      IERC20(parameters.asset).name()
    );
    string memory expectedSymbol = string.concat(
      parameters.symbolPrefix,
      IERC20(parameters.asset).symbol()
    );
    HooksConfig expectedConfig = parameters.hooksConfig;
    if (
      keccak256(bytes(IHooks(expectedConfig.hooksAddress()).version())) ==
      keccak256('SingleBorrowerAccessControlHooks')
    ) {
      if (expectedConfig.useOnQueueWithdrawal()) {
        expectedConfig = expectedConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer);
      }
    }
    vm.expectEmit(address(hooksFactory));
    emit IHooksFactoryEventsAndErrors.MarketDeployed(
      parameters.hooksTemplate,
      expectedMarket,
      expectedName,
      expectedSymbol,
      parameters.asset,
      parameters.maxTotalSupply,
      parameters.annualInterestBips,
      parameters.delinquencyFeeBips,
      parameters.withdrawalBatchDuration,
      parameters.reserveRatioBips,
      parameters.delinquencyGracePeriod,
      expectedConfig
    );
  }

  function deployMarket(
    MarketInputParameters memory parameters
  ) internal asAccount(parameters.borrower) returns (WildcatMarket) {
    updateFeeConfiguration(parameters);

    if (parameters.deployMarketHooksData.length == 0) {
      parameters.deployMarketHooksData = abi.encode(
        parameters.minimumDeposit,
        parameters.transfersDisabled,
        parameters.allowForceBuyBack
      );
    }

    bytes32 salt = _nextSalt(parameters.borrower);

    address expectedMarket = hooksFactory.computeMarketAddress(salt);

    DeployMarketInputs memory deployInputs = DeployMarketInputs({
      asset: parameters.asset,
      namePrefix: parameters.namePrefix,
      symbolPrefix: parameters.symbolPrefix,
      maxTotalSupply: parameters.maxTotalSupply,
      annualInterestBips: parameters.annualInterestBips,
      delinquencyFeeBips: parameters.delinquencyFeeBips,
      withdrawalBatchDuration: parameters.withdrawalBatchDuration,
      reserveRatioBips: parameters.reserveRatioBips,
      delinquencyGracePeriod: parameters.delinquencyGracePeriod,
      hooks: parameters.hooksConfig
    });
    _expectMarketDeployedEvents(parameters, expectedMarket);
    market = WildcatMarket(
      hooksFactory.deployMarket(deployInputs, parameters.deployMarketHooksData, salt, address(0), 0)
    );
    assertTrue(
      archController.isRegisteredMarket(address(market)),
      'deployed market is not recognized by the arch controller'
    );
    _checkSphereXConfig(address(market), 'WildcatMarket');
    validateMarketConfiguration(parameters);
    return market;
  }

  function validateMarketConfiguration(MarketInputParameters memory parameters) internal {
    HooksConfig expectedConfig = parameters.hooksConfig;
    if (
      keccak256(bytes(IHooks(expectedConfig.hooksAddress()).version())) ==
      keccak256('SingleBorrowerAccessControlHooks')
    ) {
      depositRequiresAccess = expectedConfig.useOnDeposit();
      transferRequiresAccess = expectedConfig.useOnTransfer();
      if (expectedConfig.useOnQueueWithdrawal()) {
        expectedConfig = expectedConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer);
      }
    }
    assertEq(market.asset(), parameters.asset, 'asset');
    assertEq(market.hooks(), expectedConfig, 'hooks');
    assertEq(market.maxTotalSupply(), parameters.maxTotalSupply, 'maxTotalSupply');
    assertEq(market.annualInterestBips(), parameters.annualInterestBips, 'annualInterestBips');
    assertEq(market.reserveRatioBips(), parameters.reserveRatioBips, 'reserveRatioBips');
    assertEq(market.borrower(), parameters.borrower, 'borrower');
    assertEq(market.archController(), address(archController), 'archController');
    assertEq(market.feeRecipient(), parameters.feeRecipient, 'feeRecipient');
    assertEq(market.factory(), address(hooksFactory), 'factory');
    MarketState memory state = market.previousState();
    MarketState memory expectedState = MarketState({
      isClosed: false,
      maxTotalSupply: parameters.maxTotalSupply,
      accruedProtocolFees: 0,
      normalizedUnclaimedWithdrawals: 0,
      scaledTotalSupply: 0,
      scaledPendingWithdrawals: 0,
      pendingWithdrawalExpiry: 0,
      isDelinquent: false,
      timeDelinquent: 0,
      protocolFeeBips: parameters.protocolFeeBips,
      annualInterestBips: parameters.annualInterestBips,
      reserveRatioBips: parameters.reserveRatioBips,
      scaleFactor: uint112(RAY),
      lastInterestAccruedTimestamp: uint32(block.timestamp)
    });
    assertEq(state, expectedState, 'initial state');
    assertEq(market.delinquencyFeeBips(), parameters.delinquencyFeeBips, 'delinquencyFeeBips');
    assertEq(
      market.delinquencyGracePeriod(),
      parameters.delinquencyGracePeriod,
      'delinquencyGracePeriod'
    );
    assertEq(
      market.withdrawalBatchDuration(),
      parameters.withdrawalBatchDuration,
      'withdrawalBatchDuration'
    );
    assertEq(
      market.name(),
      string.concat(parameters.namePrefix, IERC20(parameters.asset).name()),
      'name'
    );
    assertEq(
      market.symbol(),
      string.concat(parameters.symbolPrefix, IERC20(parameters.asset).symbol()),
      'symbol'
    );
    assertEq(market.decimals(), IERC20(parameters.asset).decimals(), 'decimals');
    address hooksAddress = parameters.hooksConfig.hooksAddress();
    if (
      keccak256(bytes(IHooks(hooksAddress).version())) ==
      keccak256('SingleBorrowerAccessControlHooks')
    ) {
      HookedMarket memory hookedMarket = AccessControlHooks(hooksAddress).getHookedMarket(
        address(market)
      );
      assertTrue(hookedMarket.isHooked, 'getHookedMarket');
      assertEq(
        hookedMarket.transferRequiresAccess,
        transferRequiresAccess,
        'transferRequiresAccess'
      );
      assertEq(hookedMarket.depositRequiresAccess, depositRequiresAccess, 'depositRequiresAccess');
    }
  }

  function bound(
    uint256 value,
    uint256 min,
    uint256 max
  ) internal pure virtual override returns (uint256 result) {
    return VmUtils.bound(value, min, max);
  }

  function dbound(
    uint256 value1,
    uint256 value2,
    uint256 min,
    uint256 max
  ) internal view virtual returns (uint256, uint256) {
    return VmUtils.dbound(value1, value2, min, max);
  }

  function getSignedCredentialHooksData(
    address account,
    uint32 timestamp
  ) internal view returns (bytes memory hooksData) {
    bytes32 digest = keccak256(abi.encode(account, timestamp));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(roleProviderSignerPrivateKey, digest);
    bytes memory signature = abi.encodePacked(r, s, v);
    hooksData = abi.encodePacked(address(ecdsaRoleProvider), abi.encode(timestamp, signature));
  }
}
