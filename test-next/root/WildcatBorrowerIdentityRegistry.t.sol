// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { WildcatArchController } from 'src/WildcatArchController.sol';
import { WildcatBorrowerIdentityRegistry } from 'src/WildcatBorrowerIdentityRegistry.sol';
import { IBorrowerIdentityRegistry } from 'src/interfaces/IBorrowerIdentityRegistry.sol';
import { IWildcatArchController } from 'src/interfaces/IWildcatArchController.sol';
import { BorrowerIdentityAccountFactoryMock } from '../mocks/BorrowerIdentityMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract WildcatBorrowerIdentityRegistryTest is TestKernel {
  struct Fixture {
    WildcatArchController archController;
    WildcatBorrowerIdentityRegistry registry;
    BorrowerIdentityAccountFactoryMock accountFactory;
  }

  address internal constant Principal = address(0xA11CE);
  address internal constant SecondPrincipal = address(0xB0B);
  address internal constant ThirdPrincipal = address(0xCAFE);
  address internal constant BadCaller = address(0xBAD);
  address internal constant NewOwner = address(0xB055);

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

  function _deployFactory(
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

  function _newFixture() internal returns (Fixture memory fixture) {
    fixture.archController = _deployArchController();
    fixture.registry = _deployRegistry(address(fixture.archController));
    fixture.accountFactory = _deployFactory(fixture.registry);
    fixture.archController.registerBorrower(Principal);
    fixture.registry.addAccountFactory(address(fixture.accountFactory));
  }

  function _registerAccount(
    Fixture memory fixture,
    address principal
  ) internal returns (address account) {
    account = _deployAccount();
    fixture.accountFactory.registerAccount(account, principal);
  }

  function _requestTransfer(
    Fixture memory fixture,
    address account,
    address currentPrincipal,
    address newPrincipal
  ) internal {
    vm.prank(currentPrincipal);
    fixture.registry.requestBorrowerAccountPrincipalTransfer(account, newPrincipal);
  }

  function _acceptTransfer(Fixture memory fixture, address account, address newPrincipal) internal {
    vm.prank(newPrincipal);
    fixture.registry.acceptBorrowerAccountPrincipalTransfer(account);
  }

  // ========================================================================== //
  //                         Construction and ABI reads                         //
  // ========================================================================== //

  function test_constructor_StoresArchController() external {
    Fixture memory fixture = _newFixture();
    assertEq(fixture.registry.archController(), address(fixture.archController));
  }

  function test_constructor_RejectsInvalidArchController() external {
    vm.expectRevert(IBorrowerIdentityRegistry.InvalidArchController.selector);
    _deployRegistry(address(0));

    vm.expectRevert(IBorrowerIdentityRegistry.InvalidArchController.selector);
    _deployRegistry(address(0xBEEF));
  }

  function test_archControllerOwnerRead_ValidatesAndBubblesResponse() external {
    Fixture memory fixture = _newFixture();
    BorrowerIdentityAccountFactoryMock secondFactory = _deployFactory(fixture.registry);
    address controller = address(fixture.archController);
    bytes memory callData = abi.encodeWithSignature('owner()');

    vm.mockCall(controller, callData, hex'01');
    vm.expectRevert();
    fixture.registry.addAccountFactory(address(secondFactory));
    vm.clearMockedCalls();

    vm.mockCall(controller, callData, abi.encode(uint256(1) << 160));
    vm.expectRevert();
    fixture.registry.addAccountFactory(address(secondFactory));
    vm.clearMockedCalls();

    bytes memory revertData = hex'deadbeef';
    vm.mockCallRevert(controller, callData, revertData);
    vm.expectRevert(revertData);
    fixture.registry.addAccountFactory(address(secondFactory));
    vm.clearMockedCalls();

    vm.mockCall(controller, callData, bytes.concat(abi.encode(address(this)), hex'deadbeef'));
    fixture.registry.addAccountFactory(address(secondFactory));
    assertTrue(fixture.registry.isAccountFactory(address(secondFactory)));
    vm.clearMockedCalls();
  }

  function test_registeredBorrowerRead_ValidatesAndBubblesResponse() external {
    Fixture memory fixture = _newFixture();
    bytes memory callData = abi.encodeCall(
      IWildcatArchController.isRegisteredBorrower,
      (Principal)
    );
    address controller = address(fixture.archController);

    vm.mockCall(controller, callData, hex'01');
    vm.expectRevert();
    fixture.registry.resolveBorrower(Principal);
    vm.clearMockedCalls();

    vm.mockCall(controller, callData, abi.encode(uint256(2)));
    vm.expectRevert();
    fixture.registry.resolveBorrower(Principal);
    vm.clearMockedCalls();

    bytes memory revertData = hex'deadbeef';
    vm.mockCallRevert(controller, callData, revertData);
    vm.expectRevert(revertData);
    fixture.registry.resolveBorrower(Principal);
    vm.clearMockedCalls();

    vm.mockCall(controller, callData, bytes.concat(abi.encode(true), hex'deadbeef'));
    assertEq(fixture.registry.resolveBorrower(Principal), Principal);
    vm.clearMockedCalls();
  }

  // ========================================================================== //
  //                             Account factories                              //
  // ========================================================================== //

  function test_addAccountFactory_EmitsAndEnumerates() external {
    Fixture memory fixture = _newFixture();
    BorrowerIdentityAccountFactoryMock secondFactory = _deployFactory(fixture.registry);

    vm.expectEmit(address(fixture.registry));
    emit IBorrowerIdentityRegistry.AccountFactoryAdded(address(this), address(secondFactory));
    fixture.registry.addAccountFactory(address(secondFactory));

    assertTrue(fixture.registry.isAccountFactory(address(secondFactory)));
    assertEq(fixture.registry.getAccountFactoriesCount(), 2);
    address[] memory factories = fixture.registry.getAccountFactories();
    assertEq(factories.length, 2);
    assertEq(factories[0], address(fixture.accountFactory));
    assertEq(factories[1], address(secondFactory));
  }

  function test_addAccountFactory_FollowsCurrentArchControllerOwner() external {
    Fixture memory fixture = _newFixture();
    BorrowerIdentityAccountFactoryMock secondFactory = _deployFactory(fixture.registry);

    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotArchControllerOwner.selector);
    vm.prank(BadCaller);
    fixture.registry.addAccountFactory(address(secondFactory));

    fixture.archController.transferOwnership(NewOwner);
    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotArchControllerOwner.selector);
    fixture.registry.addAccountFactory(address(secondFactory));

    vm.prank(NewOwner);
    fixture.registry.addAccountFactory(address(secondFactory));
    assertTrue(fixture.registry.isAccountFactory(address(secondFactory)));
  }

  function test_addAccountFactory_RejectsInvalidAddress() external {
    Fixture memory fixture = _newFixture();

    vm.expectRevert(IBorrowerIdentityRegistry.InvalidAccountFactory.selector);
    fixture.registry.addAccountFactory(address(0));
    vm.expectRevert(IBorrowerIdentityRegistry.InvalidAccountFactory.selector);
    fixture.registry.addAccountFactory(address(0xBEEF));
  }

  function test_addAccountFactory_RejectsDuplicate() external {
    Fixture memory fixture = _newFixture();
    vm.expectRevert(IBorrowerIdentityRegistry.AccountFactoryAlreadyExists.selector);
    fixture.registry.addAccountFactory(address(fixture.accountFactory));
  }

  function test_removeAccountFactory_PreservesRegisteredAccountProvenance() external {
    Fixture memory fixture = _newFixture();
    address account = _registerAccount(fixture, Principal);

    vm.expectEmit(address(fixture.registry));
    emit IBorrowerIdentityRegistry.AccountFactoryRemoved(
      address(this),
      address(fixture.accountFactory)
    );
    fixture.registry.removeAccountFactory(address(fixture.accountFactory));

    assertFalse(fixture.registry.isAccountFactory(address(fixture.accountFactory)));
    assertEq(fixture.registry.getAccountFactoriesCount(), 0);
    assertEq(fixture.registry.resolveBorrower(account), Principal);
    assertEq(fixture.registry.accountFactoryOf(account), address(fixture.accountFactory));
    assertEq(
      fixture.registry.getBorrowerAccountsForFactoryCount(address(fixture.accountFactory)),
      1
    );

    address secondAccount = _deployAccount();
    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotAccountFactory.selector);
    fixture.accountFactory.registerAccount(secondAccount, Principal);
  }

  function test_removeAccountFactory_RequiresOwnerAndExistingFactory() external {
    Fixture memory fixture = _newFixture();

    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotArchControllerOwner.selector);
    vm.prank(BadCaller);
    fixture.registry.removeAccountFactory(address(fixture.accountFactory));

    BorrowerIdentityAccountFactoryMock missingFactory = _deployFactory(fixture.registry);
    vm.expectRevert(IBorrowerIdentityRegistry.AccountFactoryDoesNotExist.selector);
    fixture.registry.removeAccountFactory(address(missingFactory));
  }

  function test_getAccountFactories_PaginatesAndValidatesRange() external {
    Fixture memory fixture = _newFixture();
    BorrowerIdentityAccountFactoryMock secondFactory = _deployFactory(fixture.registry);
    fixture.registry.addAccountFactory(address(secondFactory));

    address[] memory factories = fixture.registry.getAccountFactories(1, 10);
    assertEq(factories.length, 1);
    assertEq(factories[0], address(secondFactory));
    assertEq(fixture.registry.getAccountFactories(2, 2).length, 0);
    assertEq(fixture.registry.getAccountFactories(10, 20).length, 0);

    vm.expectRevert(IBorrowerIdentityRegistry.InvalidPaginationRange.selector);
    fixture.registry.getAccountFactories(2, 1);
  }

  // ========================================================================== //
  //                         Borrower account registry                          //
  // ========================================================================== //

  function test_registerAccount_EmitsAndIndexesIdentity() external {
    Fixture memory fixture = _newFixture();
    address account = _deployAccount();

    vm.expectEmit(address(fixture.registry));
    emit IBorrowerIdentityRegistry.BorrowerAccountRegistered(
      account,
      Principal,
      address(fixture.accountFactory)
    );
    fixture.accountFactory.registerAccount(account, Principal);

    assertEq(fixture.registry.principalOf(account), Principal);
    assertEq(fixture.registry.pendingPrincipalOf(account), address(0));
    assertEq(fixture.registry.accountFactoryOf(account), address(fixture.accountFactory));
    assertEq(fixture.registry.resolveBorrower(account), Principal);
    assertEq(fixture.registry.getBorrowerAccountsCount(Principal), 1);
    assertEq(
      fixture.registry.getBorrowerAccountsForFactoryCount(address(fixture.accountFactory)),
      1
    );
    assertEq(fixture.registry.getBorrowerAccounts(Principal)[0], account);
    assertEq(
      fixture.registry.getBorrowerAccountsForFactory(address(fixture.accountFactory))[0],
      account
    );
  }

  function test_registerAccount_AllowsMultipleAccountsForOnePrincipal() external {
    Fixture memory fixture = _newFixture();
    address firstAccount = _registerAccount(fixture, Principal);
    address secondAccount = _registerAccount(fixture, Principal);

    address[] memory accounts = fixture.registry.getBorrowerAccounts(Principal);
    assertEq(accounts.length, 2);
    assertEq(accounts[0], firstAccount);
    assertEq(accounts[1], secondAccount);
    assertEq(fixture.registry.resolveBorrower(firstAccount), Principal);
    assertEq(fixture.registry.resolveBorrower(secondAccount), Principal);
  }

  function test_registerAccount_RequiresApprovedFactory() external {
    Fixture memory fixture = _newFixture();
    address account = _deployAccount();
    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotAccountFactory.selector);
    fixture.registry.registerBorrowerAccount(account, Principal);
  }

  function test_registerAccount_RejectsInvalidAccount() external {
    Fixture memory fixture = _newFixture();

    vm.expectRevert(IBorrowerIdentityRegistry.InvalidBorrowerAccount.selector);
    fixture.accountFactory.registerAccount(address(0), Principal);
    vm.expectRevert(IBorrowerIdentityRegistry.InvalidBorrowerAccount.selector);
    fixture.accountFactory.registerAccount(address(0xBEEF), Principal);

    address account = _deployAccount();
    fixture.archController.registerBorrower(account);
    vm.expectRevert(IBorrowerIdentityRegistry.InvalidBorrowerAccount.selector);
    fixture.accountFactory.registerAccount(account, account);
  }

  function test_registerAccount_RequiresNonzeroRegisteredPrincipal() external {
    Fixture memory fixture = _newFixture();
    address account = _deployAccount();

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerPrincipalNotRegistered.selector);
    fixture.accountFactory.registerAccount(account, SecondPrincipal);

    fixture.archController.registerBorrower(address(0));
    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerPrincipalNotRegistered.selector);
    fixture.accountFactory.registerAccount(account, address(0));
    assertEq(fixture.registry.principalOf(account), address(0));
  }

  function test_registerAccount_RejectsAmbiguousAccountOrPrincipal() external {
    Fixture memory accountFixture = _newFixture();
    address ambiguousAccount = _deployAccount();
    accountFixture.archController.registerBorrower(ambiguousAccount);
    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    accountFixture.accountFactory.registerAccount(ambiguousAccount, Principal);

    Fixture memory principalFixture = _newFixture();
    address principalAccount = _registerAccount(principalFixture, Principal);
    principalFixture.archController.registerBorrower(principalAccount);
    address account = _deployAccount();
    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    principalFixture.accountFactory.registerAccount(account, principalAccount);
  }

  function testFuzz_registerAccount_RejectsDuplicateWithoutMutation(
    address replacementPrincipal
  ) external {
    Fixture memory fixture = _newFixture();
    address account = _registerAccount(fixture, Principal);
    vm.assume(replacementPrincipal != address(0));
    vm.assume(replacementPrincipal != Principal);
    vm.assume(replacementPrincipal != account);
    fixture.archController.registerBorrower(replacementPrincipal);

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerAccountAlreadyRegistered.selector);
    fixture.accountFactory.registerAccount(account, replacementPrincipal);
    assertEq(fixture.registry.principalOf(account), Principal);
    assertEq(fixture.registry.accountFactoryOf(account), address(fixture.accountFactory));
  }

  // ========================================================================== //
  //                            Principal transfers                             //
  // ========================================================================== //

  function test_requestTransfer_EmitsAndLeavesCurrentPrincipalActive() external {
    Fixture memory fixture = _newFixture();
    address account = _registerAccount(fixture, Principal);
    fixture.archController.registerBorrower(SecondPrincipal);

    vm.expectEmit(address(fixture.registry));
    emit IBorrowerIdentityRegistry.BorrowerAccountPrincipalTransferRequested(
      account,
      Principal,
      address(0),
      SecondPrincipal
    );
    _requestTransfer(fixture, account, Principal, SecondPrincipal);

    assertEq(fixture.registry.principalOf(account), Principal);
    assertEq(fixture.registry.pendingPrincipalOf(account), SecondPrincipal);
    assertEq(fixture.registry.resolveBorrower(account), Principal);
  }

  function test_requestTransfer_ReplacesPendingPrincipal() external {
    Fixture memory fixture = _newFixture();
    address account = _registerAccount(fixture, Principal);
    fixture.archController.registerBorrower(SecondPrincipal);
    fixture.archController.registerBorrower(ThirdPrincipal);
    _requestTransfer(fixture, account, Principal, SecondPrincipal);

    vm.expectEmit(address(fixture.registry));
    emit IBorrowerIdentityRegistry.BorrowerAccountPrincipalTransferRequested(
      account,
      Principal,
      SecondPrincipal,
      ThirdPrincipal
    );
    _requestTransfer(fixture, account, Principal, ThirdPrincipal);

    assertEq(fixture.registry.pendingPrincipalOf(account), ThirdPrincipal);
    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotPendingBorrowerAccountPrincipal.selector);
    vm.prank(SecondPrincipal);
    fixture.registry.acceptBorrowerAccountPrincipalTransfer(account);
  }

  function test_requestTransfer_RequiresRegisteredAccountPrincipal() external {
    Fixture memory fixture = _newFixture();
    address account = _registerAccount(fixture, Principal);
    fixture.archController.registerBorrower(SecondPrincipal);

    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotBorrowerAccountPrincipal.selector);
    vm.prank(SecondPrincipal);
    fixture.registry.requestBorrowerAccountPrincipalTransfer(account, SecondPrincipal);

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerAccountNotRegistered.selector);
    fixture.registry.requestBorrowerAccountPrincipalTransfer(BadCaller, SecondPrincipal);
  }

  function test_requestTransfer_RejectsInvalidOrUnregisteredTarget() external {
    Fixture memory fixture = _newFixture();
    address account = _registerAccount(fixture, Principal);

    address[3] memory invalidTargets = [address(0), Principal, account];
    for (uint256 i; i < invalidTargets.length; i++) {
      vm.expectRevert(
        IBorrowerIdentityRegistry.InvalidBorrowerAccountPrincipalTransferTarget.selector
      );
      _requestTransfer(fixture, account, Principal, invalidTargets[i]);
    }

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerPrincipalNotRegistered.selector);
    _requestTransfer(fixture, account, Principal, SecondPrincipal);
  }

  function test_requestTransfer_RejectsAmbiguousIdentity() external {
    Fixture memory targetFixture = _newFixture();
    address account = _registerAccount(targetFixture, Principal);
    targetFixture.archController.registerBorrower(SecondPrincipal);
    address principalAccount = _registerAccount(targetFixture, SecondPrincipal);
    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    _requestTransfer(targetFixture, account, Principal, principalAccount);

    Fixture memory accountFixture = _newFixture();
    account = _registerAccount(accountFixture, Principal);
    accountFixture.archController.registerBorrower(SecondPrincipal);
    accountFixture.archController.registerBorrower(account);
    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    _requestTransfer(accountFixture, account, Principal, SecondPrincipal);
  }

  function test_cancelTransfer_EmitsAndClearsPendingPrincipal() external {
    Fixture memory fixture = _newFixture();
    address account = _registerAccount(fixture, Principal);
    fixture.archController.registerBorrower(SecondPrincipal);
    _requestTransfer(fixture, account, Principal, SecondPrincipal);

    vm.expectEmit(address(fixture.registry));
    emit IBorrowerIdentityRegistry.BorrowerAccountPrincipalTransferCancelled(
      account,
      Principal,
      SecondPrincipal
    );
    vm.prank(Principal);
    fixture.registry.cancelBorrowerAccountPrincipalTransfer(account);

    assertEq(fixture.registry.principalOf(account), Principal);
    assertEq(fixture.registry.pendingPrincipalOf(account), address(0));
  }

  function test_cancelTransfer_RequiresPrincipalAndPendingTransfer() external {
    Fixture memory fixture = _newFixture();
    address account = _registerAccount(fixture, Principal);
    fixture.archController.registerBorrower(SecondPrincipal);
    _requestTransfer(fixture, account, Principal, SecondPrincipal);

    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotBorrowerAccountPrincipal.selector);
    vm.prank(SecondPrincipal);
    fixture.registry.cancelBorrowerAccountPrincipalTransfer(account);

    vm.prank(Principal);
    fixture.registry.cancelBorrowerAccountPrincipalTransfer(account);
    vm.expectRevert(IBorrowerIdentityRegistry.NoPendingBorrowerAccountPrincipalTransfer.selector);
    vm.prank(Principal);
    fixture.registry.cancelBorrowerAccountPrincipalTransfer(account);
  }

  function test_acceptTransfer_EmitsMovesCurrentEnumerationAndKeepsFactoryHistory() external {
    Fixture memory fixture = _newFixture();
    address firstAccount = _registerAccount(fixture, Principal);
    address secondAccount = _registerAccount(fixture, Principal);
    fixture.archController.registerBorrower(SecondPrincipal);
    _requestTransfer(fixture, firstAccount, Principal, SecondPrincipal);

    vm.expectEmit(address(fixture.registry));
    emit IBorrowerIdentityRegistry.BorrowerAccountPrincipalTransferred(
      firstAccount,
      Principal,
      SecondPrincipal
    );
    _acceptTransfer(fixture, firstAccount, SecondPrincipal);

    assertEq(fixture.registry.principalOf(firstAccount), SecondPrincipal);
    assertEq(fixture.registry.pendingPrincipalOf(firstAccount), address(0));
    assertEq(fixture.registry.resolveBorrower(firstAccount), SecondPrincipal);
    assertEq(fixture.registry.getBorrowerAccountsCount(Principal), 1);
    assertEq(fixture.registry.getBorrowerAccountsCount(SecondPrincipal), 1);

    address[] memory principalAccounts = fixture.registry.getBorrowerAccounts(Principal);
    address[] memory secondPrincipalAccounts = fixture.registry.getBorrowerAccounts(
      SecondPrincipal
    );
    assertEq(principalAccounts[0], secondAccount);
    assertEq(secondPrincipalAccounts[0], firstAccount);
    assertEq(fixture.registry.accountFactoryOf(firstAccount), address(fixture.accountFactory));

    address[] memory factoryAccounts = fixture.registry.getBorrowerAccountsForFactory(
      address(fixture.accountFactory)
    );
    assertEq(factoryAccounts.length, 2);
    assertEq(factoryAccounts[0], firstAccount);
    assertEq(factoryAccounts[1], secondAccount);
  }

  function test_acceptTransfer_UpdatesAuthorityAndSupportsRoundTrip() external {
    Fixture memory fixture = _newFixture();
    address account = _registerAccount(fixture, Principal);
    fixture.archController.registerBorrower(SecondPrincipal);
    _requestTransfer(fixture, account, Principal, SecondPrincipal);
    _acceptTransfer(fixture, account, SecondPrincipal);

    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotBorrowerAccountPrincipal.selector);
    _requestTransfer(fixture, account, Principal, Principal);

    _requestTransfer(fixture, account, SecondPrincipal, Principal);
    _acceptTransfer(fixture, account, Principal);
    assertEq(fixture.registry.principalOf(account), Principal);
  }

  function test_acceptTransfer_SurvivesFactoryOrCurrentPrincipalRemoval() external {
    Fixture memory factoryFixture = _newFixture();
    address factoryAccount = _registerAccount(factoryFixture, Principal);
    factoryFixture.archController.registerBorrower(SecondPrincipal);
    factoryFixture.registry.removeAccountFactory(address(factoryFixture.accountFactory));
    _requestTransfer(factoryFixture, factoryAccount, Principal, SecondPrincipal);
    _acceptTransfer(factoryFixture, factoryAccount, SecondPrincipal);
    assertEq(factoryFixture.registry.resolveBorrower(factoryAccount), SecondPrincipal);

    Fixture memory principalFixture = _newFixture();
    address principalAccount = _registerAccount(principalFixture, Principal);
    principalFixture.archController.registerBorrower(SecondPrincipal);
    principalFixture.archController.removeBorrower(Principal);
    _requestTransfer(principalFixture, principalAccount, Principal, SecondPrincipal);
    _acceptTransfer(principalFixture, principalAccount, SecondPrincipal);
    assertEq(principalFixture.registry.resolveBorrower(principalAccount), SecondPrincipal);
  }

  function test_acceptTransfer_RevalidatesTargetAndAccountIdentity() external {
    Fixture memory targetFixture = _newFixture();
    address targetAccount = _registerAccount(targetFixture, Principal);
    targetFixture.archController.registerBorrower(SecondPrincipal);
    _requestTransfer(targetFixture, targetAccount, Principal, SecondPrincipal);
    targetFixture.archController.removeBorrower(SecondPrincipal);

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerPrincipalNotRegistered.selector);
    _acceptTransfer(targetFixture, targetAccount, SecondPrincipal);
    assertEq(targetFixture.registry.principalOf(targetAccount), Principal);
    assertEq(targetFixture.registry.pendingPrincipalOf(targetAccount), SecondPrincipal);

    Fixture memory accountFixture = _newFixture();
    address ambiguousAccount = _registerAccount(accountFixture, Principal);
    accountFixture.archController.registerBorrower(SecondPrincipal);
    _requestTransfer(accountFixture, ambiguousAccount, Principal, SecondPrincipal);
    accountFixture.archController.registerBorrower(ambiguousAccount);

    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    _acceptTransfer(accountFixture, ambiguousAccount, SecondPrincipal);
    assertEq(accountFixture.registry.principalOf(ambiguousAccount), Principal);
    assertEq(accountFixture.registry.pendingPrincipalOf(ambiguousAccount), SecondPrincipal);
  }

  // ========================================================================== //
  //                          Resolution and pagination                         //
  // ========================================================================== //

  function test_resolveBorrower_HandlesDirectPrincipalAndUnknownAddress() external {
    Fixture memory fixture = _newFixture();
    assertEq(fixture.registry.resolveBorrower(Principal), Principal);

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerIdentityNotFound.selector);
    fixture.registry.resolveBorrower(address(0));
    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerIdentityNotFound.selector);
    fixture.registry.resolveBorrower(address(0xBEEF));
  }

  function test_resolveBorrower_RejectsStaleOrAmbiguousIdentity() external {
    Fixture memory staleFixture = _newFixture();
    address staleAccount = _registerAccount(staleFixture, Principal);
    staleFixture.archController.removeBorrower(Principal);
    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerPrincipalNotRegistered.selector);
    staleFixture.registry.resolveBorrower(staleAccount);

    Fixture memory ambiguousFixture = _newFixture();
    address ambiguousAccount = _registerAccount(ambiguousFixture, Principal);
    ambiguousFixture.archController.registerBorrower(ambiguousAccount);
    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    ambiguousFixture.registry.resolveBorrower(ambiguousAccount);

    Fixture memory nestedFixture = _newFixture();
    address accountPrincipal = _deployAccount();
    nestedFixture.archController.registerBorrower(accountPrincipal);
    address nestedAccount = _registerAccount(nestedFixture, accountPrincipal);
    nestedFixture.archController.removeBorrower(accountPrincipal);
    nestedFixture.archController.registerBorrower(SecondPrincipal);
    nestedFixture.accountFactory.registerAccount(accountPrincipal, SecondPrincipal);
    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    nestedFixture.registry.resolveBorrower(nestedAccount);
  }

  function test_getBorrowerAccounts_PaginatesPrincipalAndFactoryIndexes() external {
    Fixture memory fixture = _newFixture();
    address firstAccount = _registerAccount(fixture, Principal);
    address secondAccount = _registerAccount(fixture, Principal);

    address[] memory accounts = fixture.registry.getBorrowerAccounts(Principal, 1, 10);
    assertEq(accounts.length, 1);
    assertEq(accounts[0], secondAccount);
    assertEq(fixture.registry.getBorrowerAccounts(Principal, 2, 2).length, 0);
    assertEq(fixture.registry.getBorrowerAccounts(Principal, 10, 20).length, 0);

    accounts = fixture.registry.getBorrowerAccountsForFactory(
      address(fixture.accountFactory),
      0,
      1
    );
    assertEq(accounts.length, 1);
    assertEq(accounts[0], firstAccount);

    accounts = fixture.registry.getBorrowerAccountsForFactory(
      address(fixture.accountFactory),
      1,
      10
    );
    assertEq(accounts.length, 1);
    assertEq(accounts[0], secondAccount);
    assertEq(
      fixture.registry.getBorrowerAccountsForFactory(address(fixture.accountFactory), 2, 2).length,
      0
    );
    assertEq(
      fixture
        .registry
        .getBorrowerAccountsForFactory(address(fixture.accountFactory), 10, 20)
        .length,
      0
    );
    assertEq(
      fixture.registry.getBorrowerAccountsForFactoryCount(address(fixture.accountFactory)),
      2
    );

    vm.expectRevert(IBorrowerIdentityRegistry.InvalidPaginationRange.selector);
    fixture.registry.getBorrowerAccounts(Principal, 2, 1);
    vm.expectRevert(IBorrowerIdentityRegistry.InvalidPaginationRange.selector);
    fixture.registry.getBorrowerAccountsForFactory(address(fixture.accountFactory), 2, 1);
  }
}
