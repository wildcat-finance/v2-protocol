// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { HooksFactory } from 'src/HooksFactory.sol';
import { HooksFactoryRevolving } from 'src/HooksFactoryRevolving.sol';
import 'src/IHooksFactory.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { WildcatBorrowerIdentityRegistry } from 'src/WildcatBorrowerIdentityRegistry.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { BorrowerIdentityAccountFactoryMock } from '../mocks/BorrowerIdentityMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract BorrowerAccountOriginationTest is TestKernel {
  enum FactoryKind {
    Standard,
    Revolving
  }

  struct Fixture {
    WildcatArchController archController;
    WildcatBorrowerIdentityRegistry registry;
    BorrowerIdentityAccountFactoryMock accountFactory;
    HooksFactory standardFactory;
    HooksFactoryRevolving revolvingFactory;
    MockERC20 asset;
    address hooksTemplate;
    address borrowerAccount;
  }

  address internal constant Principal = address(0xA11CE);
  address internal constant SecondPrincipal = address(0xB0B);
  address internal constant SanctionsSentinel = address(0x51);

  function _deployArchController() internal returns (WildcatArchController archController) {
    archController = WildcatArchController(
      _deployCode('src/WildcatArchController.sol:WildcatArchController')
    );
  }

  function _deployRegistry(
    address archController
  ) internal returns (WildcatBorrowerIdentityRegistry registry) {
    registry = WildcatBorrowerIdentityRegistry(
      _deployCode(
        'src/WildcatBorrowerIdentityRegistry.sol:WildcatBorrowerIdentityRegistry',
        abi.encode(archController)
      )
    );
  }

  function _deployAccountFactory(
    WildcatBorrowerIdentityRegistry registry
  ) internal returns (BorrowerIdentityAccountFactoryMock factory) {
    factory = BorrowerIdentityAccountFactoryMock(
      _deployCode(
        'test-next/mocks/BorrowerIdentityMocks.sol:BorrowerIdentityAccountFactoryMock',
        abi.encode(address(registry))
      )
    );
  }

  function _deployAccount() internal returns (address account) {
    account = _deployCode('test-next/mocks/BorrowerIdentityMocks.sol:BorrowerIdentityAccountMock');
  }

  function _registerAccount(
    Fixture memory fixture,
    address principal
  ) internal returns (address account) {
    account = _deployAccount();
    fixture.accountFactory.registerAccount(account, principal);
  }

  function _storeInitCode(
    string memory artifact
  ) internal returns (address storageContract, uint256 initCodeHash) {
    bytes memory initCode = vm.getCode(artifact);
    storageContract = LibStoredInitCode.deployInitCode(initCode);
    initCodeHash = uint256(keccak256(initCode));
  }

  function _deployStandardFactory(Fixture memory fixture) internal returns (HooksFactory factory) {
    (address marketInitCodeStorage, uint256 marketInitCodeHash) = _storeInitCode(
      'src/market/WildcatMarket.sol:WildcatMarket'
    );
    factory = HooksFactory(
      _deployCode(
        'src/HooksFactory.sol:HooksFactory',
        abi.encode(
          address(fixture.archController),
          SanctionsSentinel,
          address(this),
          marketInitCodeStorage,
          marketInitCodeHash,
          address(fixture.registry)
        )
      )
    );
  }

  function _deployRevolvingFactory(
    Fixture memory fixture
  ) internal returns (HooksFactoryRevolving factory) {
    (address marketInitCodeStorage, uint256 marketInitCodeHash) = _storeInitCode(
      'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving'
    );
    factory = HooksFactoryRevolving(
      _deployCode(
        'src/HooksFactoryRevolving.sol:HooksFactoryRevolving',
        abi.encode(
          address(fixture.archController),
          SanctionsSentinel,
          address(this),
          marketInitCodeStorage,
          marketInitCodeHash,
          address(fixture.registry)
        )
      )
    );
  }

  function _configureFactory(Fixture memory fixture, address factory) internal {
    fixture.archController.registerControllerFactory(factory);
    IHooksFactory(factory).registerWithArchController();
    IHooksFactory(factory).addHooksTemplate(
      fixture.hooksTemplate,
      'Open Term',
      address(0),
      address(0),
      0,
      0
    );
  }

  function _newFixture() internal returns (Fixture memory fixture) {
    fixture.archController = _deployArchController();
    fixture.registry = _deployRegistry(address(fixture.archController));
    fixture.accountFactory = _deployAccountFactory(fixture.registry);
    fixture.asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode('Underlying', 'UND', uint8(18))
      )
    );

    fixture.archController.registerBorrower(Principal);
    fixture.registry.addAccountFactory(address(fixture.accountFactory));
    fixture.borrowerAccount = _registerAccount(fixture, Principal);
    fixture.hooksTemplate = LibStoredInitCode.deployInitCode(
      vm.getCode('src/access/OpenTermHooks.sol:OpenTermHooks')
    );

    fixture.standardFactory = _deployStandardFactory(fixture);
    fixture.revolvingFactory = _deployRevolvingFactory(fixture);
    _configureFactory(fixture, address(fixture.standardFactory));
    _configureFactory(fixture, address(fixture.revolvingFactory));
  }

  function _factory(Fixture memory fixture, FactoryKind kind) internal pure returns (address) {
    return
      kind == FactoryKind.Standard
        ? address(fixture.standardFactory)
        : address(fixture.revolvingFactory);
  }

  function _marketInputs(
    Fixture memory fixture,
    address hooksInstance
  ) internal pure returns (DeployMarketInputs memory) {
    return
      DeployMarketInputs({
        asset: address(fixture.asset),
        namePrefix: 'Wildcat ',
        symbolPrefix: 'wc',
        maxTotalSupply: 1_000_000e18,
        annualInterestBips: 1_000,
        delinquencyFeeBips: 100,
        withdrawalBatchDuration: 1 days,
        reserveRatioBips: 1_000,
        delinquencyGracePeriod: 1 days,
        hooks: EmptyHooksConfig.setHooksAddress(hooksInstance)
      });
  }

  function _marketSalt(address deployer, uint96 nonce) internal pure returns (bytes32) {
    return bytes32((uint256(uint160(deployer)) << 96) | uint256(nonce));
  }

  function _deployHooks(
    Fixture memory fixture,
    FactoryKind kind
  ) internal returns (address hooksInstance) {
    hooksInstance = IHooksFactory(_factory(fixture, kind)).deployHooksInstance(
      fixture.hooksTemplate,
      ''
    );
  }

  function _deployMarket(
    Fixture memory fixture,
    FactoryKind kind,
    address hooksInstance,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) internal returns (address market) {
    DeployMarketInputs memory inputs = _marketInputs(fixture, hooksInstance);
    if (kind == FactoryKind.Standard) {
      return
        fixture.standardFactory.deployMarket(
          inputs,
          '',
          salt,
          originationFeeAsset,
          originationFeeAmount
        );
    }
    return
      fixture.revolvingFactory.deployMarket(
        inputs,
        '',
        abi.encode(uint8(1), uint16(100)),
        salt,
        originationFeeAsset,
        originationFeeAmount
      );
  }

  function _deployMarketAndHooks(
    Fixture memory fixture,
    FactoryKind kind,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) internal returns (address market, address hooksInstance) {
    DeployMarketInputs memory inputs = _marketInputs(fixture, address(0));
    if (kind == FactoryKind.Standard) {
      return
        fixture.standardFactory.deployMarketAndHooks(
          fixture.hooksTemplate,
          '',
          inputs,
          '',
          salt,
          originationFeeAsset,
          originationFeeAmount
        );
    }
    return
      fixture.revolvingFactory.deployMarketAndHooks(
        fixture.hooksTemplate,
        '',
        inputs,
        '',
        abi.encode(uint8(1), uint16(100)),
        salt,
        originationFeeAsset,
        originationFeeAmount
      );
  }

  function _assertMarketIdentity(
    address marketAddress,
    address hooksInstance,
    address expectedBorrower,
    address expectedPrincipal
  ) internal view {
    WildcatMarket market = WildcatMarket(marketAddress);
    assertEq(market.borrower(), expectedBorrower, 'operational borrower');
    assertEq(market.borrowerPrincipal(), expectedPrincipal, 'borrower principal');
    assertEq(OpenTermHooks(hooksInstance).administrator(), expectedPrincipal, 'hook administrator');
  }

  function _assertAccountAuthority(address marketAddress, address borrowerAccount) internal {
    WildcatMarket market = WildcatMarket(marketAddress);
    uint256 updatedMaximumSupply = market.maxTotalSupply() - 1;

    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    vm.prank(Principal);
    market.setMaxTotalSupply(updatedMaximumSupply);

    vm.prank(borrowerAccount);
    market.setMaxTotalSupply(updatedMaximumSupply);
    assertEq(market.maxTotalSupply(), updatedMaximumSupply);
  }

  function _transferAccountPrincipal(Fixture memory fixture, address newPrincipal) internal {
    fixture.archController.registerBorrower(newPrincipal);
    vm.prank(Principal);
    fixture.registry.requestBorrowerAccountPrincipalTransfer(fixture.borrowerAccount, newPrincipal);
    vm.prank(newPrincipal);
    fixture.registry.acceptBorrowerAccountPrincipalTransfer(fixture.borrowerAccount);
  }

  // ========================================================================== //
  //                            Origination matrix                              //
  // ========================================================================== //

  function test_accountDeploysHookThenMarket_AcrossFactories() external {
    Fixture memory fixture = _newFixture();
    for (uint8 i; i <= uint8(FactoryKind.Revolving); i++) {
      FactoryKind kind = FactoryKind(i);
      address factory = _factory(fixture, kind);
      vm.expectEmit(false, true, true, true, factory);
      emit IHooksFactoryEventsAndErrors.HooksInstanceDeployed(
        address(0),
        fixture.hooksTemplate,
        Principal,
        fixture.borrowerAccount,
        '',
        'OpenTermHooks'
      );
      vm.prank(fixture.borrowerAccount);
      address hooksInstance = _deployHooks(fixture, kind);
      vm.prank(fixture.borrowerAccount);
      address market = _deployMarket(
        fixture,
        kind,
        hooksInstance,
        _marketSalt(fixture.borrowerAccount, 1),
        address(0),
        0
      );

      _assertMarketIdentity(market, hooksInstance, fixture.borrowerAccount, Principal);
      IHooksFactory commonFactory = IHooksFactory(factory);
      assertEq(commonFactory.getHooksAdministrator(hooksInstance), Principal);
      assertEq(commonFactory.getHooksInstancesCountForAdministrator(Principal), 1);
      assertEq(commonFactory.getHooksInstancesCountForAdministrator(fixture.borrowerAccount), 0);
      assertEq(commonFactory.getHooksInstanceDeploymentNonce(Principal), 1);
      assertEq(commonFactory.getHooksInstanceDeploymentNonce(fixture.borrowerAccount), 0);
      _assertAccountAuthority(market, fixture.borrowerAccount);
    }
  }

  function test_accountDeploysMarketAndHookTogether_AcrossFactories() external {
    Fixture memory fixture = _newFixture();
    for (uint8 i; i <= uint8(FactoryKind.Revolving); i++) {
      FactoryKind kind = FactoryKind(i);
      vm.prank(fixture.borrowerAccount);
      (address market, address hooksInstance) = _deployMarketAndHooks(
        fixture,
        kind,
        _marketSalt(fixture.borrowerAccount, 2),
        address(0),
        0
      );
      _assertMarketIdentity(market, hooksInstance, fixture.borrowerAccount, Principal);
      assertEq(
        IHooksFactory(_factory(fixture, kind)).getHooksAdministrator(hooksInstance),
        Principal
      );
    }
  }

  function test_accountPaysOriginationFees_AcrossFactories() external {
    Fixture memory fixture = _newFixture();
    address feeRecipient = address(0xFEE);
    uint80 originationFeeAmount = 1e18;
    for (uint8 i; i <= uint8(FactoryKind.Revolving); i++) {
      IHooksFactory(_factory(fixture, FactoryKind(i))).updateHooksTemplateFees(
        fixture.hooksTemplate,
        feeRecipient,
        address(fixture.asset),
        originationFeeAmount,
        0
      );
    }
    fixture.asset.mint(fixture.borrowerAccount, uint256(originationFeeAmount) * 2);

    for (uint8 i; i <= uint8(FactoryKind.Revolving); i++) {
      FactoryKind kind = FactoryKind(i);
      address factory = _factory(fixture, kind);
      vm.startPrank(fixture.borrowerAccount);
      fixture.asset.approve(factory, originationFeeAmount);
      _deployMarketAndHooks(
        fixture,
        kind,
        _marketSalt(fixture.borrowerAccount, 20),
        address(fixture.asset),
        originationFeeAmount
      );
      vm.stopPrank();
    }

    assertEq(fixture.asset.balanceOf(feeRecipient), uint256(originationFeeAmount) * 2);
    assertEq(fixture.asset.balanceOf(fixture.borrowerAccount), 0);
    assertEq(fixture.asset.balanceOf(Principal), 0);
  }

  function test_accountOriginationUsesCurrentRegistryPrincipal_AcrossFactories() external {
    Fixture memory fixture = _newFixture();
    _transferAccountPrincipal(fixture, SecondPrincipal);

    for (uint8 i; i <= uint8(FactoryKind.Revolving); i++) {
      FactoryKind kind = FactoryKind(i);
      vm.prank(fixture.borrowerAccount);
      (address market, address hooksInstance) = _deployMarketAndHooks(
        fixture,
        kind,
        _marketSalt(fixture.borrowerAccount, 3),
        address(0),
        0
      );
      _assertMarketIdentity(market, hooksInstance, fixture.borrowerAccount, SecondPrincipal);
    }
  }

  function test_accountsForOnePrincipalShareHooks_AcrossFactories() external {
    Fixture memory fixture = _newFixture();
    address secondAccount = _registerAccount(fixture, Principal);

    for (uint8 i; i <= uint8(FactoryKind.Revolving); i++) {
      FactoryKind kind = FactoryKind(i);
      vm.prank(Principal);
      address hooksInstance = _deployHooks(fixture, kind);

      vm.prank(fixture.borrowerAccount);
      address firstMarket = _deployMarket(
        fixture,
        kind,
        hooksInstance,
        _marketSalt(fixture.borrowerAccount, 10),
        address(0),
        0
      );
      vm.prank(secondAccount);
      address secondMarket = _deployMarket(
        fixture,
        kind,
        hooksInstance,
        _marketSalt(secondAccount, 11),
        address(0),
        0
      );

      _assertMarketIdentity(firstMarket, hooksInstance, fixture.borrowerAccount, Principal);
      _assertMarketIdentity(secondMarket, hooksInstance, secondAccount, Principal);
      assertEq(
        IHooksFactory(_factory(fixture, kind)).getMarketsForHooksInstanceCount(hooksInstance),
        2
      );
    }
  }

  function test_accountsForOnePrincipalShareHookNonce_AcrossFactories() external {
    Fixture memory fixture = _newFixture();
    address secondAccount = _registerAccount(fixture, Principal);

    for (uint8 i; i <= uint8(FactoryKind.Revolving); i++) {
      FactoryKind kind = FactoryKind(i);
      IHooksFactory factory = IHooksFactory(_factory(fixture, kind));
      vm.prank(fixture.borrowerAccount);
      address firstHooks = _deployHooks(fixture, kind);
      vm.prank(secondAccount);
      address secondHooks = _deployHooks(fixture, kind);

      assertTrue(firstHooks != secondHooks);
      assertEq(factory.getHooksAdministrator(firstHooks), Principal);
      assertEq(factory.getHooksAdministrator(secondHooks), Principal);
      assertEq(factory.getHooksInstanceDeploymentNonce(Principal), 2);
      assertEq(factory.getHooksInstancesCountForAdministrator(Principal), 2);
    }
  }

  function test_accountCannotOriginateAfterPrincipalRemoval_AcrossFactories() external {
    Fixture memory fixture = _newFixture();
    fixture.archController.removeBorrower(Principal);

    for (uint8 i; i <= uint8(FactoryKind.Revolving); i++) {
      FactoryKind kind = FactoryKind(i);
      vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedBorrower.selector);
      vm.prank(fixture.borrowerAccount);
      _deployHooks(fixture, kind);
      assertEq(
        IHooksFactory(_factory(fixture, kind)).getHooksInstanceDeploymentNonce(Principal),
        0
      );
    }
  }

  function test_accountOriginationSurvivesFactoryRemoval_AcrossFactories() external {
    Fixture memory fixture = _newFixture();
    fixture.registry.removeAccountFactory(address(fixture.accountFactory));

    for (uint8 i; i <= uint8(FactoryKind.Revolving); i++) {
      FactoryKind kind = FactoryKind(i);
      vm.prank(fixture.borrowerAccount);
      (address market, address hooksInstance) = _deployMarketAndHooks(
        fixture,
        kind,
        _marketSalt(fixture.borrowerAccount, 12),
        address(0),
        0
      );
      _assertMarketIdentity(market, hooksInstance, fixture.borrowerAccount, Principal);
    }
  }

  function test_accountCannotUseOtherPrincipalHook_AcrossFactories() external {
    Fixture memory fixture = _newFixture();
    fixture.archController.registerBorrower(SecondPrincipal);

    for (uint8 i; i <= uint8(FactoryKind.Revolving); i++) {
      FactoryKind kind = FactoryKind(i);
      vm.prank(SecondPrincipal);
      address hooksInstance = _deployHooks(fixture, kind);

      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      vm.prank(fixture.borrowerAccount);
      _deployMarket(
        fixture,
        kind,
        hooksInstance,
        _marketSalt(fixture.borrowerAccount, 4),
        address(0),
        0
      );
    }
  }
}
