// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/WildcatArchController.sol';
import 'src/WildcatBorrowerIdentityRegistry.sol';
import 'src/HooksFactory.sol';
import 'src/HooksFactoryRevolving.sol';
import 'src/IHooksFactory.sol';
import 'src/access/BaseAccessControls.sol';
import 'src/access/OpenTermHooks.sol';
import 'src/interfaces/IBorrowerIdentityRegistry.sol';
import 'src/interfaces/IMarketEventsAndErrors.sol';
import 'src/libraries/LibStoredInitCode.sol';
import 'src/market/WildcatMarket.sol';
import 'src/market/WildcatMarketRevolving.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

// Deliberately has no market or factory ABI. v2.5 only authenticates the account address.
contract OriginationTestBorrowerAccount {}

contract OriginationTestBorrowerAccountFactory {
  IBorrowerIdentityRegistry public immutable registry;

  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  function deployAccount(address principal) external returns (address account) {
    account = address(new OriginationTestBorrowerAccount());
    registry.registerBorrowerAccount(account, principal);
  }
}

contract BorrowerAccountOriginationTest is Test {
  WildcatArchController internal archController;
  WildcatBorrowerIdentityRegistry internal borrowerIdentityRegistry;
  OriginationTestBorrowerAccountFactory internal accountFactory;
  HooksFactory internal standardFactory;
  HooksFactoryRevolving internal revolvingFactory;
  MockERC20 internal asset;

  address internal hooksTemplate;
  address internal borrowerAccount;

  address internal constant principal = address(0xA11CE);
  address internal constant secondPrincipal = address(0xB0B);
  address internal constant sanctionsSentinel = address(0x51);

  function setUp() public {
    archController = new WildcatArchController();
    borrowerIdentityRegistry = new WildcatBorrowerIdentityRegistry(address(archController));
    accountFactory = new OriginationTestBorrowerAccountFactory(
      address(borrowerIdentityRegistry)
    );
    asset = new MockERC20('Underlying', 'UND', 18);

    archController.registerBorrower(principal);
    borrowerIdentityRegistry.addAccountFactory(address(accountFactory));
    borrowerAccount = accountFactory.deployAccount(principal);

    hooksTemplate = LibStoredInitCode.deployInitCode(type(OpenTermHooks).creationCode);
    standardFactory = _deployStandardFactory();
    revolvingFactory = _deployRevolvingFactory();
  }

  function _deployStandardFactory() internal returns (HooksFactory factory) {
    bytes memory marketInitCode = type(WildcatMarket).creationCode;
    factory = new HooksFactory(
      address(archController),
      sanctionsSentinel,
      address(this),
      LibStoredInitCode.deployInitCode(marketInitCode),
      uint256(keccak256(marketInitCode)),
      address(borrowerIdentityRegistry)
    );
    archController.registerControllerFactory(address(factory));
    factory.registerWithArchController();
    factory.addHooksTemplate(hooksTemplate, 'Open Term', address(0), address(0), 0, 0);
  }

  function _deployRevolvingFactory() internal returns (HooksFactoryRevolving factory) {
    bytes memory marketInitCode = type(WildcatMarketRevolving).creationCode;
    factory = new HooksFactoryRevolving(
      address(archController),
      sanctionsSentinel,
      address(this),
      LibStoredInitCode.deployInitCode(marketInitCode),
      uint256(keccak256(marketInitCode)),
      address(borrowerIdentityRegistry)
    );
    archController.registerControllerFactory(address(factory));
    factory.registerWithArchController();
    factory.addHooksTemplate(hooksTemplate, 'Open Term', address(0), address(0), 0, 0);
  }

  function _marketInputs(address hooksInstance) internal view returns (DeployMarketInputs memory) {
    return
      DeployMarketInputs({
        asset: address(asset),
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

  function _transferAccountPrincipal(address newPrincipal) internal {
    archController.registerBorrower(newPrincipal);
    vm.prank(principal);
    borrowerIdentityRegistry.requestBorrowerAccountPrincipalTransfer(
      borrowerAccount,
      newPrincipal
    );
    vm.prank(newPrincipal);
    borrowerIdentityRegistry.acceptBorrowerAccountPrincipalTransfer(borrowerAccount);
  }

  function _assertAccountAuthority(address marketAddress) internal {
    WildcatMarket market = WildcatMarket(marketAddress);
    uint256 updatedMaximumSupply = market.maxTotalSupply() - 1;

    vm.prank(principal);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    market.setMaxTotalSupply(updatedMaximumSupply);

    vm.prank(borrowerAccount);
    market.setMaxTotalSupply(updatedMaximumSupply);
    assertEq(market.maxTotalSupply(), updatedMaximumSupply);
  }

  function test_standardAccountDeploysHookAndMarket() external {
    vm.expectEmit(false, true, true, true, address(standardFactory));
    emit IHooksFactoryEventsAndErrors.HooksInstanceDeployed(
      address(0),
      hooksTemplate,
      principal,
      borrowerAccount,
      '',
      'OpenTermHooks'
    );
    vm.startPrank(borrowerAccount);
    address hooksInstance = standardFactory.deployHooksInstance(hooksTemplate, '');
    address market = standardFactory.deployMarket(
      _marketInputs(hooksInstance),
      '',
      _marketSalt(borrowerAccount, 1),
      address(0),
      0
    );
    vm.stopPrank();

    _assertMarketIdentity(market, hooksInstance, borrowerAccount, principal);
    assertEq(standardFactory.getHooksAdministrator(hooksInstance), principal);
    assertEq(standardFactory.getHooksInstancesCountForAdministrator(principal), 1);
    assertEq(standardFactory.getHooksInstancesCountForAdministrator(borrowerAccount), 0);
    assertEq(standardFactory.getHooksInstanceDeploymentNonce(principal), 1);
    assertEq(standardFactory.getHooksInstanceDeploymentNonce(borrowerAccount), 0);
    _assertAccountAuthority(market);
  }

  function test_revolvingAccountDeploysHookAndMarket() external {
    vm.expectEmit(false, true, true, true, address(revolvingFactory));
    emit IHooksFactoryEventsAndErrors.HooksInstanceDeployed(
      address(0),
      hooksTemplate,
      principal,
      borrowerAccount,
      '',
      'OpenTermHooks'
    );
    vm.startPrank(borrowerAccount);
    address hooksInstance = revolvingFactory.deployHooksInstance(hooksTemplate, '');
    address market = revolvingFactory.deployMarket(
      _marketInputs(hooksInstance),
      '',
      abi.encode(uint8(1), uint16(100)),
      _marketSalt(borrowerAccount, 1),
      address(0),
      0
    );
    vm.stopPrank();

    _assertMarketIdentity(market, hooksInstance, borrowerAccount, principal);
    assertEq(revolvingFactory.getHooksAdministrator(hooksInstance), principal);
    assertEq(revolvingFactory.getHooksInstancesCountForAdministrator(principal), 1);
    assertEq(revolvingFactory.getHooksInstancesCountForAdministrator(borrowerAccount), 0);
    assertEq(revolvingFactory.getHooksInstanceDeploymentNonce(principal), 1);
    assertEq(revolvingFactory.getHooksInstanceDeploymentNonce(borrowerAccount), 0);
    _assertAccountAuthority(market);
  }

  function test_standardAccountDeploysMarketAndHookTogether() external {
    vm.prank(borrowerAccount);
    (address market, address hooksInstance) = standardFactory.deployMarketAndHooks(
      hooksTemplate,
      '',
      _marketInputs(address(0)),
      '',
      _marketSalt(borrowerAccount, 2),
      address(0),
      0
    );

    _assertMarketIdentity(market, hooksInstance, borrowerAccount, principal);
    assertEq(standardFactory.getHooksAdministrator(hooksInstance), principal);
  }

  function test_revolvingAccountDeploysMarketAndHookTogether() external {
    vm.prank(borrowerAccount);
    (address market, address hooksInstance) = revolvingFactory.deployMarketAndHooks(
      hooksTemplate,
      '',
      _marketInputs(address(0)),
      '',
      abi.encode(uint8(1), uint16(100)),
      _marketSalt(borrowerAccount, 2),
      address(0),
      0
    );

    _assertMarketIdentity(market, hooksInstance, borrowerAccount, principal);
    assertEq(revolvingFactory.getHooksAdministrator(hooksInstance), principal);
  }

  function test_accountPaysOriginationFees() external {
    address feeRecipient = address(0xFEE);
    uint80 originationFeeAmount = 1e18;
    standardFactory.updateHooksTemplateFees(
      hooksTemplate,
      feeRecipient,
      address(asset),
      originationFeeAmount,
      0
    );
    revolvingFactory.updateHooksTemplateFees(
      hooksTemplate,
      feeRecipient,
      address(asset),
      originationFeeAmount,
      0
    );
    asset.mint(borrowerAccount, uint256(originationFeeAmount) * 2);

    vm.startPrank(borrowerAccount);
    asset.approve(address(standardFactory), originationFeeAmount);
    standardFactory.deployMarketAndHooks(
      hooksTemplate,
      '',
      _marketInputs(address(0)),
      '',
      _marketSalt(borrowerAccount, 20),
      address(asset),
      originationFeeAmount
    );
    asset.approve(address(revolvingFactory), originationFeeAmount);
    revolvingFactory.deployMarketAndHooks(
      hooksTemplate,
      '',
      _marketInputs(address(0)),
      '',
      abi.encode(uint8(1), uint16(100)),
      _marketSalt(borrowerAccount, 20),
      address(asset),
      originationFeeAmount
    );
    vm.stopPrank();

    assertEq(asset.balanceOf(feeRecipient), uint256(originationFeeAmount) * 2);
    assertEq(asset.balanceOf(borrowerAccount), 0);
    assertEq(asset.balanceOf(principal), 0);
  }

  function test_accountOriginationUsesCurrentRegistryPrincipal() external {
    _transferAccountPrincipal(secondPrincipal);

    vm.prank(borrowerAccount);
    (address standardMarket, address standardHooks) = standardFactory.deployMarketAndHooks(
      hooksTemplate,
      '',
      _marketInputs(address(0)),
      '',
      _marketSalt(borrowerAccount, 3),
      address(0),
      0
    );
    vm.prank(borrowerAccount);
    (address revolvingMarket, address revolvingHooks) = revolvingFactory.deployMarketAndHooks(
      hooksTemplate,
      '',
      _marketInputs(address(0)),
      '',
      abi.encode(uint8(1), uint16(100)),
      _marketSalt(borrowerAccount, 3),
      address(0),
      0
    );

    _assertMarketIdentity(
      standardMarket,
      standardHooks,
      borrowerAccount,
      secondPrincipal
    );
    _assertMarketIdentity(
      revolvingMarket,
      revolvingHooks,
      borrowerAccount,
      secondPrincipal
    );
  }

  function test_accountsUnderOnePrincipalCanShareHooks() external {
    address secondAccount = accountFactory.deployAccount(principal);

    vm.prank(principal);
    address standardHooks = standardFactory.deployHooksInstance(hooksTemplate, '');
    vm.prank(borrowerAccount);
    address firstStandardMarket = standardFactory.deployMarket(
      _marketInputs(standardHooks),
      '',
      _marketSalt(borrowerAccount, 10),
      address(0),
      0
    );
    vm.prank(secondAccount);
    address secondStandardMarket = standardFactory.deployMarket(
      _marketInputs(standardHooks),
      '',
      _marketSalt(secondAccount, 11),
      address(0),
      0
    );

    vm.prank(principal);
    address revolvingHooks = revolvingFactory.deployHooksInstance(hooksTemplate, '');
    vm.prank(borrowerAccount);
    address firstRevolvingMarket = revolvingFactory.deployMarket(
      _marketInputs(revolvingHooks),
      '',
      abi.encode(uint8(1), uint16(100)),
      _marketSalt(borrowerAccount, 10),
      address(0),
      0
    );
    vm.prank(secondAccount);
    address secondRevolvingMarket = revolvingFactory.deployMarket(
      _marketInputs(revolvingHooks),
      '',
      abi.encode(uint8(1), uint16(100)),
      _marketSalt(secondAccount, 11),
      address(0),
      0
    );

    _assertMarketIdentity(firstStandardMarket, standardHooks, borrowerAccount, principal);
    _assertMarketIdentity(secondStandardMarket, standardHooks, secondAccount, principal);
    _assertMarketIdentity(firstRevolvingMarket, revolvingHooks, borrowerAccount, principal);
    _assertMarketIdentity(secondRevolvingMarket, revolvingHooks, secondAccount, principal);
    assertEq(standardFactory.getMarketsForHooksInstanceCount(standardHooks), 2);
    assertEq(revolvingFactory.getMarketsForHooksInstanceCount(revolvingHooks), 2);
  }

  function test_accountsUnderOnePrincipalShareHookDeploymentNonce() external {
    address secondAccount = accountFactory.deployAccount(principal);

    vm.prank(borrowerAccount);
    address firstStandardHooks = standardFactory.deployHooksInstance(hooksTemplate, '');
    vm.prank(secondAccount);
    address secondStandardHooks = standardFactory.deployHooksInstance(hooksTemplate, '');

    vm.prank(borrowerAccount);
    address firstRevolvingHooks = revolvingFactory.deployHooksInstance(hooksTemplate, '');
    vm.prank(secondAccount);
    address secondRevolvingHooks = revolvingFactory.deployHooksInstance(hooksTemplate, '');

    assertTrue(firstStandardHooks != secondStandardHooks);
    assertTrue(firstRevolvingHooks != secondRevolvingHooks);
    assertEq(standardFactory.getHooksAdministrator(firstStandardHooks), principal);
    assertEq(standardFactory.getHooksAdministrator(secondStandardHooks), principal);
    assertEq(revolvingFactory.getHooksAdministrator(firstRevolvingHooks), principal);
    assertEq(revolvingFactory.getHooksAdministrator(secondRevolvingHooks), principal);
    assertEq(standardFactory.getHooksInstanceDeploymentNonce(principal), 2);
    assertEq(revolvingFactory.getHooksInstanceDeploymentNonce(principal), 2);
    assertEq(standardFactory.getHooksInstancesCountForAdministrator(principal), 2);
    assertEq(revolvingFactory.getHooksInstancesCountForAdministrator(principal), 2);
  }

  function test_accountCannotOriginateAfterPrincipalRemoval() external {
    archController.removeBorrower(principal);

    vm.prank(borrowerAccount);
    vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedBorrower.selector);
    standardFactory.deployHooksInstance(hooksTemplate, '');

    vm.prank(borrowerAccount);
    vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedBorrower.selector);
    revolvingFactory.deployHooksInstance(hooksTemplate, '');

    assertEq(standardFactory.getHooksInstanceDeploymentNonce(principal), 0);
    assertEq(revolvingFactory.getHooksInstanceDeploymentNonce(principal), 0);
  }

  function test_accountOriginationSurvivesAccountFactoryRemoval() external {
    borrowerIdentityRegistry.removeAccountFactory(address(accountFactory));

    vm.prank(borrowerAccount);
    (address standardMarket, address standardHooks) = standardFactory.deployMarketAndHooks(
      hooksTemplate,
      '',
      _marketInputs(address(0)),
      '',
      _marketSalt(borrowerAccount, 12),
      address(0),
      0
    );
    vm.prank(borrowerAccount);
    (address revolvingMarket, address revolvingHooks) = revolvingFactory.deployMarketAndHooks(
      hooksTemplate,
      '',
      _marketInputs(address(0)),
      '',
      abi.encode(uint8(1), uint16(100)),
      _marketSalt(borrowerAccount, 12),
      address(0),
      0
    );

    _assertMarketIdentity(standardMarket, standardHooks, borrowerAccount, principal);
    _assertMarketIdentity(revolvingMarket, revolvingHooks, borrowerAccount, principal);
  }

  function test_accountCannotUseHookFromAnotherPrincipal() external {
    archController.registerBorrower(secondPrincipal);

    vm.prank(secondPrincipal);
    address standardHooks = standardFactory.deployHooksInstance(hooksTemplate, '');
    vm.prank(borrowerAccount);
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    standardFactory.deployMarket(
      _marketInputs(standardHooks),
      '',
      _marketSalt(borrowerAccount, 4),
      address(0),
      0
    );

    vm.prank(secondPrincipal);
    address revolvingHooks = revolvingFactory.deployHooksInstance(hooksTemplate, '');
    vm.prank(borrowerAccount);
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    revolvingFactory.deployMarket(
      _marketInputs(revolvingHooks),
      '',
      abi.encode(uint8(1), uint16(100)),
      _marketSalt(borrowerAccount, 4),
      address(0),
      0
    );
  }
}
