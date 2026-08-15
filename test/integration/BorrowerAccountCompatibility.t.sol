// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

import 'src/WildcatArchController.sol';
import 'src/WildcatBorrowerIdentityRegistry.sol';
import 'src/WildcatSanctionsSentinel.sol';
import 'src/HooksFactory.sol';
import 'src/HooksFactoryRevolving.sol';
import 'src/IHooksFactory.sol';
import 'src/IHooksFactoryRevolving.sol';
import 'src/providers/AccessListRoleProvider.sol';
import 'src/providers/AccessListRoleProviderFactory.sol';
import 'src/providers/MerkleRoleProvider.sol';
import 'src/access/BaseAccessControls.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import 'src/providers/IAccessListRoleProviderFactory.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import 'src/access/ProviderStructs.sol';
import 'src/interfaces/IMarketEventsAndErrors.sol';
import 'src/interfaces/IWildcatMarketRevolving.sol';
import 'src/interfaces/WildcatStructsAndEnums.sol';
import 'src/libraries/LibStoredInitCode.sol';
import 'src/market/WildcatMarket.sol';
import 'src/market/WildcatMarketRevolving.sol';
import 'src/types/HooksConfig.sol';
import 'src/types/RoleProvider.sol';
import 'src/vault/Wildcat4626Wrapper.sol';
import 'src/vault/Wildcat4626WrapperFactory.sol';

import { MockChainalysis } from '../shared/mocks/MockChainalysis.sol';
import { MockCredentialedBorrowHooks } from '../shared/mocks/MockCredentialedBorrowHooks.sol';
import {
  MockExecutingBorrowerAccount,
  MockExecutingBorrowerAccountFactory
} from '../shared/mocks/MockExecutingBorrowerAccount.sol';

interface IMinimumDepositHooks {
  function setMinimumDeposit(address market, uint128 newMinimumDeposit) external;
}

interface IBorrowerMarketActions {
  function setMaxTotalSupply(uint256 maxTotalSupply) external;

  function borrow(uint256 amount) external;

  function repay(uint256 amount) external;

  function closeMarket() external;

  function requestBorrowerTransfer(address newBorrower) external;

  function acceptBorrowerTransfer() external;
}

interface IERC20AccountActions {
  function transfer(address recipient, uint256 amount) external returns (bool);

  function approve(address spender, uint256 amount) external returns (bool);
}

enum AccountCompatibilityHooksKind {
  OpenTerm,
  FixedTerm,
  PeriodicTerm,
  CredentialedBorrow
}

enum AccountCompatibilityMarketKind {
  Standard,
  Revolving
}

struct AccountCompatibilityDeployment {
  WildcatMarket market;
  BaseAccessControls hooks;
  AccountCompatibilityMarketKind marketKind;
}

/**
 * @dev Runs the v2.5 deployment and market paths through a contract borrower.
 *      The account is only a registered caller with a generic execution
 *      function. It does not assume a v2.6 Borrower Account ABI or delegation
 *      rules.
 */
contract BorrowerAccountCompatibilityTest is Test {
  address internal constant Principal = address(0xA11CE);
  address internal constant SecondPrincipal = address(0xCAFE);
  address internal constant Lender = address(0x1EAD);
  address internal constant SecondLender = address(0xB0B);
  address internal constant FeeRecipient = address(0xFEE);
  address internal constant Other = address(0xBAD);

  WildcatArchController internal archController;
  WildcatBorrowerIdentityRegistry internal borrowerIdentityRegistry;
  WildcatSanctionsSentinel internal sanctionsSentinel;
  Wildcat4626WrapperFactory internal wrapperFactory;
  HooksFactory internal standardFactory;
  HooksFactoryRevolving internal revolvingFactory;
  AccessListRoleProviderFactory internal roleProviderFactory;
  AccessListRoleProvider internal sharedProvider;
  MockExecutingBorrowerAccountFactory internal accountFactory;
  MockExecutingBorrowerAccount internal borrowerAccount;
  MockERC20 internal asset;

  address internal openTermTemplate;
  address internal fixedTermTemplate;
  address internal periodicTermTemplate;
  address internal credentialedBorrowTemplate;

  uint96 internal nextStandardSaltNonce = 1;
  uint96 internal nextRevolvingSaltNonce = 1;

  function setUp() public {
    vm.warp(1_714_737_030);

    archController = new WildcatArchController();
    borrowerIdentityRegistry = new WildcatBorrowerIdentityRegistry(address(archController));
    sanctionsSentinel = new WildcatSanctionsSentinel(
      address(archController),
      address(new MockChainalysis())
    );
    wrapperFactory = new Wildcat4626WrapperFactory(address(archController), address(0));
    roleProviderFactory = new AccessListRoleProviderFactory();
    accountFactory = new MockExecutingBorrowerAccountFactory(
      address(borrowerIdentityRegistry)
    );
    asset = new MockERC20('Underlying', 'UND', 18);

    standardFactory = _deployStandardFactory();
    revolvingFactory = _deployRevolvingFactory();
    _deployAndRegisterHooksTemplates();

    archController.registerBorrower(Principal);
    borrowerIdentityRegistry.addAccountFactory(address(accountFactory));
    vm.prank(Principal);
    borrowerAccount = MockExecutingBorrowerAccount(
      payable(accountFactory.deployAccount(Principal))
    );

    address[] memory initialMembers = new address[](1);
    initialMembers[0] = Lender;
    AccessListRoleProviderFactoryInputs memory providerInputs = AccessListRoleProviderFactoryInputs({
      administrator: Principal,
      initialMembers: initialMembers,
      salt: bytes32('shared provider')
    });
    vm.prank(Principal);
    sharedProvider = AccessListRoleProvider(
      roleProviderFactory.createAccessListRoleProvider(providerInputs)
    );
  }

  function _deployStandardFactory() internal returns (HooksFactory factory) {
    bytes memory marketInitCode = type(WildcatMarket).creationCode;
    factory = new HooksFactory(
      address(archController),
      address(sanctionsSentinel),
      address(wrapperFactory),
      LibStoredInitCode.deployInitCode(marketInitCode),
      uint256(keccak256(marketInitCode)),
      address(borrowerIdentityRegistry)
    );
    archController.registerControllerFactory(address(factory));
    factory.registerWithArchController();
  }

  function _deployRevolvingFactory() internal returns (HooksFactoryRevolving factory) {
    bytes memory marketInitCode = type(WildcatMarketRevolving).creationCode;
    (address initCodeStorage, address initCodeStorage2) = LibStoredInitCode
      .deployInitCodeInTwoParts(marketInitCode);
    factory = new HooksFactoryRevolving(
      address(archController),
      address(sanctionsSentinel),
      address(wrapperFactory),
      initCodeStorage,
      initCodeStorage2,
      uint256(keccak256(marketInitCode)),
      address(borrowerIdentityRegistry)
    );
    archController.registerControllerFactory(address(factory));
    factory.registerWithArchController();
  }

  function _deployAndRegisterHooksTemplates() internal {
    openTermTemplate = LibStoredInitCode.deployInitCode(type(OpenTermHooks).creationCode);
    fixedTermTemplate = LibStoredInitCode.deployInitCode(type(FixedTermHooks).creationCode);
    periodicTermTemplate = LibStoredInitCode.deployInitCode(type(PeriodicTermHooks).creationCode);
    credentialedBorrowTemplate = LibStoredInitCode.deployInitCode(
      type(MockCredentialedBorrowHooks).creationCode
    );

    _registerHooksTemplate(openTermTemplate, 'Open Term');
    _registerHooksTemplate(fixedTermTemplate, 'Fixed Term');
    _registerHooksTemplate(periodicTermTemplate, 'Periodic Term');
    _registerHooksTemplate(credentialedBorrowTemplate, 'Credentialed Borrow');
  }

  function _registerHooksTemplate(address template, string memory name) internal {
    standardFactory.addHooksTemplate(template, name, address(0), address(0), 0, 0);
    revolvingFactory.addHooksTemplate(template, name, address(0), address(0), 0, 0);
  }

  function _templateFor(
    AccountCompatibilityHooksKind hooksKind
  ) internal view returns (address template) {
    if (hooksKind == AccountCompatibilityHooksKind.OpenTerm) return openTermTemplate;
    if (hooksKind == AccountCompatibilityHooksKind.FixedTerm) return fixedTermTemplate;
    if (hooksKind == AccountCompatibilityHooksKind.PeriodicTerm) return periodicTermTemplate;
    return credentialedBorrowTemplate;
  }

  function _hooksDataFor(
    AccountCompatibilityHooksKind hooksKind
  ) internal view returns (bytes memory hooksData) {
    if (hooksKind == AccountCompatibilityHooksKind.OpenTerm) {
      return abi.encode(uint128(1e18), false);
    }
    if (hooksKind == AccountCompatibilityHooksKind.FixedTerm) {
      return abi.encode(uint32(block.timestamp + 60 days), uint128(1e18), false, true, true);
    }
    if (hooksKind == AccountCompatibilityHooksKind.PeriodicTerm) {
      return
        abi.encode(
          uint32(block.timestamp + 30 days),
          uint32(30 days),
          uint32(7 days),
          uint128(1e18),
          false
        );
    }
    return '';
  }

  function _marketInputs() internal view returns (DeployMarketInputs memory inputs) {
    HooksConfig hooks = EmptyHooksConfig
      .setFlag(Bit_Enabled_Deposit)
      .setFlag(Bit_Enabled_Transfer);
    inputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: 'Wildcat ',
      symbolPrefix: 'wc',
      maxTotalSupply: 1_000_000e18,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 100,
      withdrawalBatchDuration: 1 days,
      reserveRatioBips: 1_000,
      delinquencyGracePeriod: 1 days,
      hooks: hooks
    });
  }

  function _existingProviderConstructorArgs() internal view returns (bytes memory) {
    NameAndProviderInputs memory inputs;
    inputs.name = 'Borrower Account Hook';
    inputs.existingProviders = new ExistingProviderInputs[](1);
    inputs.existingProviders[0] = ExistingProviderInputs({
      providerAddress: address(sharedProvider),
      timeToLive: 0
    });
    inputs.newProviderInputs = new CreateProviderInputs[](0);
    return abi.encode(inputs);
  }

  function _credentialProviderConstructorArgs(
    MerkleRoleProvider provider
  ) internal pure returns (bytes memory) {
    NameAndProviderInputs memory inputs;
    inputs.name = 'Credentialed Borrow Hook';
    inputs.existingProviders = new ExistingProviderInputs[](1);
    inputs.existingProviders[0] = ExistingProviderInputs({
      providerAddress: address(provider),
      timeToLive: 0
    });
    inputs.newProviderInputs = new CreateProviderInputs[](0);
    return abi.encode(inputs);
  }

  function _emptyProviderConstructorArgs() internal pure returns (bytes memory) {
    NameAndProviderInputs memory inputs;
    inputs.name = 'Provider Pending';
    inputs.existingProviders = new ExistingProviderInputs[](0);
    inputs.newProviderInputs = new CreateProviderInputs[](0);
    return abi.encode(inputs);
  }

  function _newProviderConstructorArgs(
    AccessListRoleProviderFactoryInputs memory providerInputs
  ) internal view returns (bytes memory) {
    NameAndProviderInputs memory inputs;
    inputs.name = 'Provider Created With Hook';
    inputs.roleProviderFactory = address(roleProviderFactory);
    inputs.existingProviders = new ExistingProviderInputs[](0);
    inputs.newProviderInputs = new CreateProviderInputs[](1);
    inputs.newProviderInputs[0] = CreateProviderInputs({
      timeToLive: 0,
      providerFactoryCalldata: abi.encode(providerInputs)
    });
    return abi.encode(inputs);
  }

  function _nextMarketSalt(
    AccountCompatibilityMarketKind marketKind,
    address account
  ) internal returns (bytes32 salt) {
    uint96 nonce = marketKind == AccountCompatibilityMarketKind.Standard
      ? nextStandardSaltNonce++
      : nextRevolvingSaltNonce++;
    salt = bytes32((uint256(uint160(account)) << 96) | nonce);
  }

  function _execute(
    MockExecutingBorrowerAccount account,
    address target,
    bytes memory data
  ) internal returns (bytes memory result) {
    vm.prank(account.principal());
    result = account.execute(target, 0, data);
  }

  function _deploy(
    AccountCompatibilityHooksKind hooksKind,
    AccountCompatibilityMarketKind marketKind,
    bytes memory hooksConstructorArgs
  ) internal returns (AccountCompatibilityDeployment memory deployment) {
    return
      _deploy(
        borrowerAccount,
        hooksKind,
        marketKind,
        hooksConstructorArgs,
        _nextMarketSalt(marketKind, address(borrowerAccount)),
        address(0),
        0
      );
  }

  function _deploy(
    MockExecutingBorrowerAccount account,
    AccountCompatibilityHooksKind hooksKind,
    AccountCompatibilityMarketKind marketKind,
    bytes memory hooksConstructorArgs,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) internal returns (AccountCompatibilityDeployment memory deployment) {
    (address target, bytes memory data) = _deploymentCall(
      hooksKind,
      marketKind,
      hooksConstructorArgs,
      salt,
      originationFeeAsset,
      originationFeeAmount
    );
    bytes memory returnData = _execute(account, target, data);

    (address market, address hooks) = abi.decode(returnData, (address, address));
    deployment = AccountCompatibilityDeployment({
      market: WildcatMarket(market),
      hooks: BaseAccessControls(hooks),
      marketKind: marketKind
    });
  }

  function _deploymentCall(
    AccountCompatibilityHooksKind hooksKind,
    AccountCompatibilityMarketKind marketKind,
    bytes memory hooksConstructorArgs,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) internal view returns (address target, bytes memory data) {
    if (marketKind == AccountCompatibilityMarketKind.Standard) {
      target = address(standardFactory);
      data = abi.encodeCall(
        IHooksFactory.deployMarketAndHooks,
        (
          _templateFor(hooksKind),
          hooksConstructorArgs,
          _marketInputs(),
          _hooksDataFor(hooksKind),
          salt,
          originationFeeAsset,
          originationFeeAmount
        )
      );
    } else {
      target = address(revolvingFactory);
      data = abi.encodeCall(
        IHooksFactoryRevolving.deployMarketAndHooks,
        (
          _templateFor(hooksKind),
          hooksConstructorArgs,
          _marketInputs(),
          _hooksDataFor(hooksKind),
          abi.encode(uint8(1), uint16(200)),
          salt,
          originationFeeAsset,
          originationFeeAmount
        )
      );
    }
  }

  function _deployHookThenMarket(
    AccountCompatibilityMarketKind marketKind
  ) internal returns (AccountCompatibilityDeployment memory deployment) {
    address target = marketKind == AccountCompatibilityMarketKind.Standard
      ? address(standardFactory)
      : address(revolvingFactory);
    bytes memory hookReturnData = _execute(
      borrowerAccount,
      target,
      abi.encodeCall(
        IHooksFactory.deployHooksInstance,
        (openTermTemplate, _existingProviderConstructorArgs())
      )
    );
    address hooks = abi.decode(hookReturnData, (address));

    DeployMarketInputs memory inputs = _marketInputs();
    inputs.hooks = inputs.hooks.setHooksAddress(hooks);
    bytes memory marketReturnData;
    if (marketKind == AccountCompatibilityMarketKind.Standard) {
      marketReturnData = _execute(
        borrowerAccount,
        target,
        abi.encodeCall(
          IHooksFactory.deployMarket,
          (
            inputs,
            _hooksDataFor(AccountCompatibilityHooksKind.OpenTerm),
            _nextMarketSalt(marketKind, address(borrowerAccount)),
            address(0),
            0
          )
        )
      );
    } else {
      marketReturnData = _execute(
        borrowerAccount,
        target,
        abi.encodeCall(
          IHooksFactoryRevolving.deployMarket,
          (
            inputs,
            _hooksDataFor(AccountCompatibilityHooksKind.OpenTerm),
            abi.encode(uint8(1), uint16(200)),
            _nextMarketSalt(marketKind, address(borrowerAccount)),
            address(0),
            0
          )
        )
      );
    }

    deployment = AccountCompatibilityDeployment({
      market: WildcatMarket(abi.decode(marketReturnData, (address))),
      hooks: BaseAccessControls(hooks),
      marketKind: marketKind
    });
  }

  function _assertDeploymentIdentity(
    AccountCompatibilityDeployment memory deployment,
    MockExecutingBorrowerAccount account
  ) internal view {
    assertEq(deployment.market.borrower(), address(account), 'operational borrower');
    assertEq(deployment.market.borrowerPrincipal(), Principal, 'borrower principal');
    assertEq(deployment.hooks.administrator(), Principal, 'hook administrator');

    address factoryAdministrator = deployment.marketKind == AccountCompatibilityMarketKind.Standard
      ? standardFactory.getHooksAdministrator(address(deployment.hooks))
      : revolvingFactory.getHooksAdministrator(address(deployment.hooks));
    assertEq(factoryAdministrator, Principal, 'factory hook administrator');
  }

  function _approveAndDeposit(
    WildcatMarket market,
    address lender,
    uint256 amount
  ) internal {
    asset.mint(lender, amount);
    vm.startPrank(lender);
    asset.approve(address(market), type(uint256).max);
    market.deposit(amount);
    vm.stopPrank();
  }

  function _expectDepositDenied(
    WildcatMarket market,
    address lender,
    uint256 amount
  ) internal {
    asset.mint(lender, amount);
    vm.startPrank(lender);
    asset.approve(address(market), type(uint256).max);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.deposit(amount);
    vm.stopPrank();
  }

  function _principalLeaf(address principal) internal pure returns (bytes32) {
    return keccak256(abi.encode(principal));
  }

  function _credentialedBorrowCallData(
    uint256 amount,
    MerkleRoleProvider provider
  ) internal pure returns (bytes memory) {
    bytes32[] memory proof = new bytes32[](0);
    return
      abi.encodePacked(
        abi.encodeCall(IBorrowerMarketActions.borrow, (amount)),
        address(provider),
        abi.encode(proof)
      );
  }

  function _expectAccountCallRevert(
    MockExecutingBorrowerAccount account,
    address target,
    bytes memory data,
    bytes4 errorSelector
  ) internal {
    address principal = account.principal();
    vm.prank(principal);
    vm.expectRevert(errorSelector);
    account.execute(target, 0, data);
  }

  function _borrowWithCredential(
    MockExecutingBorrowerAccount account,
    WildcatMarket market,
    uint256 amount,
    MerkleRoleProvider provider
  ) internal {
    _execute(
      account,
      address(market),
      _credentialedBorrowCallData(amount, provider)
    );
  }

  function _runCredentialedBorrowCompatibility(
    AccountCompatibilityMarketKind marketKind
  ) internal {
    MerkleRoleProvider provider = new MerkleRoleProvider(
      Principal,
      _principalLeaf(Principal)
    );
    AccountCompatibilityDeployment memory deployment = _deploy(
      AccountCompatibilityHooksKind.CredentialedBorrow,
      marketKind,
      _credentialProviderConstructorArgs(provider)
    );
    MockCredentialedBorrowHooks hooks = MockCredentialedBorrowHooks(
      address(deployment.hooks)
    );

    assertTrue(deployment.market.hooks().useOnBorrow(), 'borrow hook not enabled');
    assertFalse(deployment.market.hooks().useOnDeposit(), 'deposit hook enabled');
    assertFalse(deployment.market.hooks().useOnTransfer(), 'transfer hook enabled');
    assertEq(hooks.administrator(), Principal, 'initial hook administrator');
    assertFalse(hooks.getRoleProvider(address(provider)).isNull(), 'provider not attached');

    _approveAndDeposit(deployment.market, Lender, 100e18);

    _expectAccountCallRevert(
      borrowerAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.borrow, (10e18)),
      MockCredentialedBorrowHooks.BorrowCredentialRequired.selector
    );

    _borrowWithCredential(borrowerAccount, deployment.market, 10e18, provider);
    assertEq(asset.balanceOf(address(borrowerAccount)), 10e18, 'initial draw recipient');
    assertEq(
      hooks.lastBorrower(address(deployment.market)),
      address(borrowerAccount),
      'initial borrower'
    );
    assertEq(
      hooks.lastBorrowerPrincipal(address(deployment.market)),
      Principal,
      'initial principal'
    );

    vm.prank(Principal);
    MockExecutingBorrowerAccount nextAccount = MockExecutingBorrowerAccount(
      payable(accountFactory.deployAccount(Principal))
    );
    _execute(
      borrowerAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.requestBorrowerTransfer, (address(nextAccount)))
    );
    _execute(
      nextAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.acceptBorrowerTransfer, ())
    );

    _expectAccountCallRevert(
      borrowerAccount,
      address(deployment.market),
      _credentialedBorrowCallData(10e18, provider),
      IMarketEventsAndErrors.NotApprovedBorrower.selector
    );

    vm.warp(block.timestamp + 1);
    _borrowWithCredential(nextAccount, deployment.market, 10e18, provider);
    assertEq(asset.balanceOf(address(nextAccount)), 10e18, 'transferred draw recipient');
    assertEq(
      hooks.lastBorrower(address(deployment.market)),
      address(nextAccount),
      'transferred borrower'
    );
    assertEq(
      hooks.lastBorrowerPrincipal(address(deployment.market)),
      Principal,
      'transferred principal'
    );

    archController.registerBorrower(SecondPrincipal);
    vm.prank(Principal);
    borrowerIdentityRegistry.requestBorrowerAccountPrincipalTransfer(
      address(nextAccount),
      SecondPrincipal
    );
    vm.prank(SecondPrincipal);
    borrowerIdentityRegistry.acceptBorrowerAccountPrincipalTransfer(address(nextAccount));
    assertEq(nextAccount.principal(), SecondPrincipal, 'account principal');

    _execute(
      nextAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.requestBorrowerTransfer, (address(nextAccount)))
    );
    _execute(
      nextAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.acceptBorrowerTransfer, ())
    );
    assertEq(deployment.market.borrower(), address(nextAccount), 'migrated borrower');
    assertEq(deployment.market.borrowerPrincipal(), SecondPrincipal, 'migrated principal');

    vm.warp(block.timestamp + 1);
    _expectAccountCallRevert(
      nextAccount,
      address(deployment.market),
      _credentialedBorrowCallData(10e18, provider),
      MockCredentialedBorrowHooks.BorrowCredentialRequired.selector
    );

    vm.prank(Principal);
    hooks.requestAdministratorTransfer(SecondPrincipal);
    vm.prank(SecondPrincipal);
    hooks.acceptAdministratorTransfer();

    vm.prank(Principal);
    provider.requestAdministratorTransfer(SecondPrincipal);
    vm.prank(SecondPrincipal);
    provider.acceptAdministratorTransfer();
    vm.prank(SecondPrincipal);
    provider.updateRoot(_principalLeaf(SecondPrincipal));

    address factoryAdministrator = marketKind == AccountCompatibilityMarketKind.Standard
      ? standardFactory.getHooksAdministrator(address(hooks))
      : revolvingFactory.getHooksAdministrator(address(hooks));
    assertEq(hooks.administrator(), SecondPrincipal, 'migrated hook administrator');
    assertEq(factoryAdministrator, SecondPrincipal, 'factory hook administrator');
    assertEq(provider.administrator(), SecondPrincipal, 'provider administrator');
    assertFalse(hooks.getRoleProvider(address(provider)).isNull(), 'provider detached');

    _borrowWithCredential(nextAccount, deployment.market, 10e18, provider);
    assertEq(asset.balanceOf(address(nextAccount)), 20e18, 'final draw recipient');
    assertEq(
      hooks.lastBorrower(address(deployment.market)),
      address(nextAccount),
      'final borrower'
    );
    assertEq(
      hooks.lastBorrowerPrincipal(address(deployment.market)),
      SecondPrincipal,
      'final principal'
    );
  }

  function _runCompatibilityCell(
    AccountCompatibilityHooksKind hooksKind,
    AccountCompatibilityMarketKind marketKind
  ) internal {
    AccountCompatibilityDeployment memory deployment = _deploy(
      hooksKind,
      marketKind,
      _existingProviderConstructorArgs()
    );
    _assertDeploymentIdentity(deployment, borrowerAccount);

    RoleProvider attachedProvider = deployment.hooks.getRoleProvider(address(sharedProvider));
    assertFalse(attachedProvider.isNull(), 'shared provider not attached');
    assertTrue(attachedProvider.isPullProvider(), 'shared provider is not pull based');
    assertEq(attachedProvider.timeToLive(), 0, 'shared provider ttl');

    _approveAndDeposit(deployment.market, Lender, 10e18);
    _expectDepositDenied(deployment.market, SecondLender, 10e18);

    vm.prank(Principal);
    sharedProvider.addMember(SecondLender);
    _approveAndDeposit(deployment.market, SecondLender, 10e18);

    vm.prank(Principal);
    sharedProvider.removeMember(SecondLender);
    _expectDepositDenied(deployment.market, SecondLender, 10e18);

    vm.prank(Principal);
    IMinimumDepositHooks(address(deployment.hooks)).setMinimumDeposit(
      address(deployment.market),
      2e18
    );

    vm.prank(Principal);
    deployment.hooks.setName('Principal Managed Hook');
    assertEq(deployment.hooks.name(), 'Principal Managed Hook');

    vm.prank(Principal);
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    borrowerAccount.execute(
      address(deployment.hooks),
      0,
      abi.encodeCall(BaseAccessControls.setName, ('Account Managed Hook'))
    );

    uint256 updatedMaximumSupply = deployment.market.maxTotalSupply() - 1;
    vm.prank(Principal);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    deployment.market.setMaxTotalSupply(updatedMaximumSupply);

    _execute(
      borrowerAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.setMaxTotalSupply, (updatedMaximumSupply))
    );
    assertEq(deployment.market.maxTotalSupply(), updatedMaximumSupply);
  }

  function test_accountCompatibility_openTerm_standard() external {
    _runCompatibilityCell(
      AccountCompatibilityHooksKind.OpenTerm,
      AccountCompatibilityMarketKind.Standard
    );
  }

  function test_accountCompatibility_fixedTerm_standard() external {
    _runCompatibilityCell(
      AccountCompatibilityHooksKind.FixedTerm,
      AccountCompatibilityMarketKind.Standard
    );
  }

  function test_accountCompatibility_periodicTerm_standard() external {
    _runCompatibilityCell(
      AccountCompatibilityHooksKind.PeriodicTerm,
      AccountCompatibilityMarketKind.Standard
    );
  }

  function test_accountCompatibility_openTerm_revolving() external {
    _runCompatibilityCell(
      AccountCompatibilityHooksKind.OpenTerm,
      AccountCompatibilityMarketKind.Revolving
    );
  }

  function test_accountCompatibility_fixedTerm_revolving() external {
    _runCompatibilityCell(
      AccountCompatibilityHooksKind.FixedTerm,
      AccountCompatibilityMarketKind.Revolving
    );
  }

  function test_accountCompatibility_periodicTerm_revolving() external {
    _runCompatibilityCell(
      AccountCompatibilityHooksKind.PeriodicTerm,
      AccountCompatibilityMarketKind.Revolving
    );
  }

  function test_credentialedBorrowCompatibility_standard() external {
    _runCredentialedBorrowCompatibility(AccountCompatibilityMarketKind.Standard);
  }

  function test_credentialedBorrowCompatibility_revolving() external {
    _runCredentialedBorrowCompatibility(AccountCompatibilityMarketKind.Revolving);
  }

  function test_reusableProviderWorksAcrossAccountOwnedMarkets() external {
    AccountCompatibilityDeployment memory standard = _deploy(
      AccountCompatibilityHooksKind.OpenTerm,
      AccountCompatibilityMarketKind.Standard,
      _existingProviderConstructorArgs()
    );
    AccountCompatibilityDeployment memory revolving = _deploy(
      AccountCompatibilityHooksKind.OpenTerm,
      AccountCompatibilityMarketKind.Revolving,
      _existingProviderConstructorArgs()
    );

    vm.prank(Principal);
    sharedProvider.addMember(SecondLender);
    _approveAndDeposit(standard.market, SecondLender, 10e18);
    _approveAndDeposit(revolving.market, SecondLender, 10e18);

    vm.prank(Principal);
    sharedProvider.removeMember(SecondLender);
    _expectDepositDenied(standard.market, SecondLender, 10e18);
    _expectDepositDenied(revolving.market, SecondLender, 10e18);
  }

  function test_accountCanDeployHooksAndMarketsInSeparateCalls() external {
    AccountCompatibilityDeployment memory standard = _deployHookThenMarket(
      AccountCompatibilityMarketKind.Standard
    );
    AccountCompatibilityDeployment memory revolving = _deployHookThenMarket(
      AccountCompatibilityMarketKind.Revolving
    );

    _assertDeploymentIdentity(standard, borrowerAccount);
    _assertDeploymentIdentity(revolving, borrowerAccount);
    _approveAndDeposit(standard.market, Lender, 10e18);
    _approveAndDeposit(revolving.market, Lender, 10e18);
  }

  function test_accountCanCreateProviderHookAndMarketInOneCall() external {
    address[] memory initialMembers = new address[](1);
    initialMembers[0] = Lender;
    AccessListRoleProviderFactoryInputs memory providerInputs = AccessListRoleProviderFactoryInputs({
      administrator: Principal,
      initialMembers: initialMembers,
      salt: bytes32('created with hook')
    });

    AccountCompatibilityDeployment memory deployment = _deploy(
      AccountCompatibilityHooksKind.OpenTerm,
      AccountCompatibilityMarketKind.Standard,
      _newProviderConstructorArgs(providerInputs)
    );
    RoleProvider[] memory providers = deployment.hooks.getPullProviders();
    assertEq(providers.length, 1, 'provider count');

    address providerAddress = providers[0].providerAddress();
    assertEq(
      providerAddress,
      roleProviderFactory.computeRoleProviderAddress(address(deployment.hooks), providerInputs),
      'provider address'
    );
    assertEq(
      AccessListRoleProvider(providerAddress).administrator(),
      Principal,
      'provider administrator'
    );
    _approveAndDeposit(deployment.market, Lender, 10e18);
  }

  function test_providerlessDeploymentCanBeConfiguredAfterward() external {
    AccountCompatibilityDeployment memory deployment = _deploy(
      AccountCompatibilityHooksKind.OpenTerm,
      AccountCompatibilityMarketKind.Standard,
      _emptyProviderConstructorArgs()
    );
    assertEq(deployment.hooks.getPullProviders().length, 0, 'unexpected provider');
    _expectDepositDenied(deployment.market, Lender, 10e18);

    vm.prank(Principal);
    deployment.hooks.addRoleProvider(address(sharedProvider), 0);
    _approveAndDeposit(deployment.market, Lender, 10e18);
  }

  function _runMarketLifecycle(AccountCompatibilityMarketKind marketKind) internal {
    AccountCompatibilityDeployment memory deployment = _deploy(
      AccountCompatibilityHooksKind.OpenTerm,
      marketKind,
      _existingProviderConstructorArgs()
    );
    _approveAndDeposit(deployment.market, Lender, 100e18);

    uint256 borrowAmount = deployment.market.borrowableAssets() / 2;
    _execute(
      borrowerAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.borrow, (borrowAmount))
    );
    assertEq(asset.balanceOf(address(borrowerAccount)), borrowAmount, 'draw recipient');

    _execute(
      borrowerAccount,
      address(asset),
      abi.encodeCall(IERC20AccountActions.transfer, (Principal, borrowAmount))
    );
    assertEq(asset.balanceOf(Principal), borrowAmount, 'principal did not receive draw');

    vm.prank(Principal);
    asset.transfer(address(borrowerAccount), borrowAmount);
    _execute(
      borrowerAccount,
      address(asset),
      abi.encodeCall(
        IERC20AccountActions.approve,
        (address(deployment.market), type(uint256).max)
      )
    );
    _execute(
      borrowerAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.repay, (borrowAmount / 2))
    );
    _execute(
      borrowerAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.closeMarket, ())
    );

    assertTrue(deployment.market.isClosed(), 'market not closed');
    assertEq(asset.balanceOf(address(borrowerAccount)), 0, 'account retained underlying');
    if (marketKind == AccountCompatibilityMarketKind.Revolving) {
      assertEq(
        IWildcatMarketRevolving(address(deployment.market)).drawnAmount(),
        0,
        'drawn amount not cleared'
      );
    }
  }

  function test_accountExecutesStandardMarketLifecycle() external {
    _runMarketLifecycle(AccountCompatibilityMarketKind.Standard);
  }

  function test_accountExecutesRevolvingMarketLifecycle() external {
    _runMarketLifecycle(AccountCompatibilityMarketKind.Revolving);
  }

  function test_marketAndWrapperAuthorityMoveToNewAccount() external {
    AccountCompatibilityDeployment memory deployment = _deploy(
      AccountCompatibilityHooksKind.OpenTerm,
      AccountCompatibilityMarketKind.Standard,
      _existingProviderConstructorArgs()
    );
    Wildcat4626Wrapper wrapper = Wildcat4626Wrapper(
      wrapperFactory.createWrapper(address(deployment.market))
    );

    vm.prank(Principal);
    MockExecutingBorrowerAccount nextAccount = MockExecutingBorrowerAccount(
      payable(accountFactory.deployAccount(Principal))
    );

    _execute(
      borrowerAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.requestBorrowerTransfer, (address(nextAccount)))
    );
    _execute(
      nextAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.acceptBorrowerTransfer, ())
    );

    assertEq(deployment.market.borrower(), address(nextAccount), 'new borrower');
    assertEq(deployment.market.borrowerPrincipal(), Principal, 'new principal');
    assertEq(wrapper.marketOwner(), address(nextAccount), 'wrapper authority');
    assertEq(deployment.hooks.administrator(), Principal, 'hook administrator changed');
    assertEq(sharedProvider.administrator(), Principal, 'provider administrator changed');

    uint256 updatedMaximumSupply = deployment.market.maxTotalSupply() - 1;
    vm.prank(Principal);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    borrowerAccount.execute(
      address(deployment.market),
      0,
      abi.encodeCall(IBorrowerMarketActions.setMaxTotalSupply, (updatedMaximumSupply))
    );
    _execute(
      nextAccount,
      address(deployment.market),
      abi.encodeCall(IBorrowerMarketActions.setMaxTotalSupply, (updatedMaximumSupply))
    );

    MockERC20 stray = new MockERC20('Stray', 'STY', 18);
    stray.mint(address(wrapper), 5e18);
    vm.prank(Principal);
    vm.expectRevert(Wildcat4626Wrapper.NotMarketOwner.selector);
    borrowerAccount.execute(
      address(wrapper),
      0,
      abi.encodeCall(Wildcat4626Wrapper.sweep, (address(stray), Principal))
    );
    _execute(
      nextAccount,
      address(wrapper),
      abi.encodeCall(Wildcat4626Wrapper.sweep, (address(stray), Principal))
    );
    assertEq(stray.balanceOf(Principal), 5e18, 'new account could not sweep');
  }

  function test_accountPaysOriginationFeesThroughRealApprovals() external {
    uint80 feeAmount = 1e18;
    standardFactory.updateHooksTemplateFees(
      openTermTemplate,
      FeeRecipient,
      address(asset),
      feeAmount,
      0
    );
    revolvingFactory.updateHooksTemplateFees(
      openTermTemplate,
      FeeRecipient,
      address(asset),
      feeAmount,
      0
    );
    asset.mint(address(borrowerAccount), uint256(feeAmount) * 2);

    _execute(
      borrowerAccount,
      address(asset),
      abi.encodeCall(IERC20AccountActions.approve, (address(standardFactory), feeAmount))
    );
    _deploy(
      borrowerAccount,
      AccountCompatibilityHooksKind.OpenTerm,
      AccountCompatibilityMarketKind.Standard,
      _existingProviderConstructorArgs(),
      _nextMarketSalt(AccountCompatibilityMarketKind.Standard, address(borrowerAccount)),
      address(asset),
      feeAmount
    );

    _execute(
      borrowerAccount,
      address(asset),
      abi.encodeCall(IERC20AccountActions.approve, (address(revolvingFactory), feeAmount))
    );
    _deploy(
      borrowerAccount,
      AccountCompatibilityHooksKind.OpenTerm,
      AccountCompatibilityMarketKind.Revolving,
      _existingProviderConstructorArgs(),
      _nextMarketSalt(AccountCompatibilityMarketKind.Revolving, address(borrowerAccount)),
      address(asset),
      feeAmount
    );

    assertEq(asset.balanceOf(FeeRecipient), uint256(feeAmount) * 2, 'origination fees');
    assertEq(asset.balanceOf(address(borrowerAccount)), 0, 'account fee balance');
  }

  function test_accountBoundSaltRejectsPrincipalPrefix() external {
    bytes32 principalSalt = bytes32((uint256(uint160(Principal)) << 96) | uint96(1));

    _assertSaltRejected(AccountCompatibilityMarketKind.Standard, principalSalt);
    _assertSaltRejected(AccountCompatibilityMarketKind.Revolving, principalSalt);
  }

  function _assertSaltRejected(
    AccountCompatibilityMarketKind marketKind,
    bytes32 salt
  ) internal {
    (address target, bytes memory data) = _deploymentCall(
      AccountCompatibilityHooksKind.OpenTerm,
      marketKind,
      _existingProviderConstructorArgs(),
      salt,
      address(0),
      0
    );

    vm.prank(Principal);
    (bool success, bytes memory revertData) = address(borrowerAccount).call(
      abi.encodeCall(MockExecutingBorrowerAccount.execute, (target, 0, data))
    );
    assertFalse(success, 'principal-prefixed salt accepted');
    assertEq(
      revertData,
      abi.encodeWithSelector(IHooksFactoryEventsAndErrors.SaltDoesNotContainSender.selector),
      'wrong salt rejection'
    );
  }

  function testFuzz_onlyPrincipalCanExecute(address caller) external {
    if (caller == Principal) caller = Other;

    vm.prank(caller);
    vm.expectRevert(MockExecutingBorrowerAccount.CallerNotPrincipal.selector);
    borrowerAccount.execute(
      address(asset),
      0,
      abi.encodeCall(IERC20AccountActions.approve, (address(standardFactory), 1))
    );
  }
}
