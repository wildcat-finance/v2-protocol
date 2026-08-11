// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/WildcatArchController.sol';
import 'src/WildcatBorrowerIdentityRegistry.sol';
import 'src/interfaces/IBorrowerIdentityRegistry.sol';

contract MockBorrowerAccount {}

contract MockBorrowerAccountFactory {
  IBorrowerIdentityRegistry public immutable registry;

  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  function deployAccount(address principal) external returns (address account) {
    account = address(new MockBorrowerAccount());
    registry.registerBorrowerAccount(account, principal);
  }

  function registerAccount(address account, address principal) external {
    registry.registerBorrowerAccount(account, principal);
  }
}

contract WildcatBorrowerIdentityRegistryTest is Test {
  WildcatArchController internal archController;
  WildcatBorrowerIdentityRegistry internal registry;
  MockBorrowerAccountFactory internal accountFactory;

  address internal constant principal = address(0xA11CE);
  address internal constant secondPrincipal = address(0xB0B);

  function setUp() public {
    archController = new WildcatArchController();
    registry = new WildcatBorrowerIdentityRegistry(address(archController));
    accountFactory = new MockBorrowerAccountFactory(address(registry));

    archController.registerBorrower(principal);
    registry.addAccountFactory(address(accountFactory));
  }

  function test_constructor() external view {
    assertEq(registry.archController(), address(archController));
  }

  function test_constructor_InvalidArchController() external {
    vm.expectRevert(IBorrowerIdentityRegistry.InvalidArchController.selector);
    new WildcatBorrowerIdentityRegistry(address(0));

    vm.expectRevert(IBorrowerIdentityRegistry.InvalidArchController.selector);
    new WildcatBorrowerIdentityRegistry(address(0xBEEF));
  }

  function test_addAccountFactory() external {
    MockBorrowerAccountFactory secondFactory = new MockBorrowerAccountFactory(address(registry));

    vm.expectEmit(address(registry));
    emit IBorrowerIdentityRegistry.AccountFactoryAdded(address(secondFactory));
    registry.addAccountFactory(address(secondFactory));

    assertTrue(registry.isAccountFactory(address(secondFactory)));
    assertEq(registry.getAccountFactoriesCount(), 2);
    address[] memory factories = registry.getAccountFactories();
    assertEq(factories[0], address(accountFactory));
    assertEq(factories[1], address(secondFactory));
  }

  function test_addAccountFactory_CallerNotArchControllerOwner() external {
    MockBorrowerAccountFactory secondFactory = new MockBorrowerAccountFactory(address(registry));
    vm.prank(address(0xBAD));
    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotArchControllerOwner.selector);
    registry.addAccountFactory(address(secondFactory));
  }

  function test_addAccountFactory_InvalidAccountFactory() external {
    vm.expectRevert(IBorrowerIdentityRegistry.InvalidAccountFactory.selector);
    registry.addAccountFactory(address(0));

    vm.expectRevert(IBorrowerIdentityRegistry.InvalidAccountFactory.selector);
    registry.addAccountFactory(address(0xBEEF));
  }

  function test_addAccountFactory_AccountFactoryAlreadyExists() external {
    vm.expectRevert(IBorrowerIdentityRegistry.AccountFactoryAlreadyExists.selector);
    registry.addAccountFactory(address(accountFactory));
  }

  function test_addAccountFactory_FollowsArchControllerOwner() external {
    address newOwner = address(0xB055);
    MockBorrowerAccountFactory secondFactory = new MockBorrowerAccountFactory(address(registry));
    archController.transferOwnership(newOwner);

    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotArchControllerOwner.selector);
    registry.addAccountFactory(address(secondFactory));

    vm.prank(newOwner);
    registry.addAccountFactory(address(secondFactory));
    assertTrue(registry.isAccountFactory(address(secondFactory)));
  }

  function test_removeAccountFactory() external {
    address account = accountFactory.deployAccount(principal);

    vm.expectEmit(address(registry));
    emit IBorrowerIdentityRegistry.AccountFactoryRemoved(address(accountFactory));
    registry.removeAccountFactory(address(accountFactory));

    assertFalse(registry.isAccountFactory(address(accountFactory)));
    assertEq(registry.getAccountFactoriesCount(), 0);
    assertEq(registry.resolveBorrower(account), principal);
    assertEq(registry.accountFactoryOf(account), address(accountFactory));
    assertEq(registry.getBorrowerAccountsForFactoryCount(address(accountFactory)), 1);

    address secondAccount = address(new MockBorrowerAccount());
    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotAccountFactory.selector);
    accountFactory.registerAccount(secondAccount, principal);
  }

  function test_removeAccountFactory_CallerNotArchControllerOwner() external {
    vm.prank(address(0xBAD));
    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotArchControllerOwner.selector);
    registry.removeAccountFactory(address(accountFactory));
  }

  function test_removeAccountFactory_AccountFactoryDoesNotExist() external {
    MockBorrowerAccountFactory secondFactory = new MockBorrowerAccountFactory(address(registry));
    vm.expectRevert(IBorrowerIdentityRegistry.AccountFactoryDoesNotExist.selector);
    registry.removeAccountFactory(address(secondFactory));
  }

  function test_registerBorrowerAccount() external {
    vm.recordLogs();
    address account = accountFactory.deployAccount(principal);
    Vm.Log[] memory logs = vm.getRecordedLogs();

    assertEq(logs.length, 1);
    assertEq(logs[0].emitter, address(registry));
    assertEq(logs[0].topics[0], IBorrowerIdentityRegistry.BorrowerAccountRegistered.selector);
    assertEq(address(uint160(uint256(logs[0].topics[1]))), account);
    assertEq(address(uint160(uint256(logs[0].topics[2]))), principal);
    assertEq(address(uint160(uint256(logs[0].topics[3]))), address(accountFactory));

    assertEq(registry.principalOf(account), principal);
    assertEq(registry.accountFactoryOf(account), address(accountFactory));
    assertEq(registry.resolveBorrower(account), principal);
    assertEq(registry.getBorrowerAccountsCount(principal), 1);
    assertEq(registry.getBorrowerAccountsForFactoryCount(address(accountFactory)), 1);
    assertEq(registry.getBorrowerAccounts(principal)[0], account);
    assertEq(registry.getBorrowerAccountsForFactory(address(accountFactory))[0], account);
  }

  function test_registerBorrowerAccount_MultipleAccountsForPrincipal() external {
    address firstAccount = accountFactory.deployAccount(principal);
    address secondAccount = accountFactory.deployAccount(principal);

    address[] memory accounts = registry.getBorrowerAccounts(principal);
    assertEq(accounts.length, 2);
    assertEq(accounts[0], firstAccount);
    assertEq(accounts[1], secondAccount);
    assertEq(registry.resolveBorrower(firstAccount), principal);
    assertEq(registry.resolveBorrower(secondAccount), principal);
  }

  function test_registerBorrowerAccount_CallerNotAccountFactory() external {
    address account = address(new MockBorrowerAccount());
    vm.expectRevert(IBorrowerIdentityRegistry.CallerNotAccountFactory.selector);
    registry.registerBorrowerAccount(account, principal);
  }

  function test_registerBorrowerAccount_InvalidBorrowerAccount() external {
    vm.expectRevert(IBorrowerIdentityRegistry.InvalidBorrowerAccount.selector);
    accountFactory.registerAccount(address(0), principal);

    vm.expectRevert(IBorrowerIdentityRegistry.InvalidBorrowerAccount.selector);
    accountFactory.registerAccount(address(0xBEEF), principal);

    MockBorrowerAccount account = new MockBorrowerAccount();
    archController.registerBorrower(address(account));
    vm.expectRevert(IBorrowerIdentityRegistry.InvalidBorrowerAccount.selector);
    accountFactory.registerAccount(address(account), address(account));
  }

  function test_registerBorrowerAccount_BorrowerPrincipalNotRegistered() external {
    address account = address(new MockBorrowerAccount());
    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerPrincipalNotRegistered.selector);
    accountFactory.registerAccount(account, secondPrincipal);
  }

  function test_registerBorrowerAccount_ZeroPrincipalRegisteredOnArchController() external {
    archController.registerBorrower(address(0));
    address account = address(new MockBorrowerAccount());

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerPrincipalNotRegistered.selector);
    accountFactory.registerAccount(account, address(0));
    assertEq(registry.principalOf(account), address(0));
  }

  function test_registerBorrowerAccount_AmbiguousAccount() external {
    address account = address(new MockBorrowerAccount());
    archController.registerBorrower(account);

    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    accountFactory.registerAccount(account, principal);
  }

  function test_registerBorrowerAccount_AmbiguousPrincipal() external {
    address principalAccount = accountFactory.deployAccount(principal);
    archController.registerBorrower(principalAccount);
    address account = address(new MockBorrowerAccount());

    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    accountFactory.registerAccount(account, principalAccount);
  }

  function test_registerBorrowerAccount_BorrowerAccountAlreadyRegistered() external {
    address account = accountFactory.deployAccount(principal);
    archController.registerBorrower(secondPrincipal);

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerAccountAlreadyRegistered.selector);
    accountFactory.registerAccount(account, secondPrincipal);

    assertEq(registry.principalOf(account), principal);
    assertEq(registry.accountFactoryOf(account), address(accountFactory));
  }

  function testFuzz_registerBorrowerAccount_AssociationIsImmutable(
    address replacementPrincipal
  ) external {
    vm.assume(replacementPrincipal != address(0));
    vm.assume(replacementPrincipal != principal);
    address account = accountFactory.deployAccount(principal);
    archController.registerBorrower(replacementPrincipal);

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerAccountAlreadyRegistered.selector);
    accountFactory.registerAccount(account, replacementPrincipal);

    assertEq(registry.principalOf(account), principal);
  }

  function test_resolveBorrower_DirectPrincipal() external view {
    assertEq(registry.resolveBorrower(principal), principal);
  }

  function test_resolveBorrower_BorrowerIdentityNotFound() external {
    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerIdentityNotFound.selector);
    registry.resolveBorrower(address(0));

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerIdentityNotFound.selector);
    registry.resolveBorrower(address(0xBEEF));
  }

  function test_resolveBorrower_BorrowerPrincipalNotRegistered() external {
    address account = accountFactory.deployAccount(principal);
    archController.removeBorrower(principal);

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerPrincipalNotRegistered.selector);
    registry.resolveBorrower(account);
  }

  function test_resolveBorrower_AmbiguousBorrowerIdentity() external {
    address account = accountFactory.deployAccount(principal);
    archController.registerBorrower(account);

    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    registry.resolveBorrower(account);
  }

  function test_getAccountFactories_Pagination() external {
    MockBorrowerAccountFactory secondFactory = new MockBorrowerAccountFactory(address(registry));
    registry.addAccountFactory(address(secondFactory));

    address[] memory factories = registry.getAccountFactories(1, 10);
    assertEq(factories.length, 1);
    assertEq(factories[0], address(secondFactory));
    assertEq(registry.getAccountFactories(2, 2).length, 0);
    assertEq(registry.getAccountFactories(10, 20).length, 0);

    vm.expectRevert(IBorrowerIdentityRegistry.InvalidPaginationRange.selector);
    registry.getAccountFactories(2, 1);
  }

  function test_getBorrowerAccounts_Pagination() external {
    address firstAccount = accountFactory.deployAccount(principal);
    address secondAccount = accountFactory.deployAccount(principal);

    address[] memory accounts = registry.getBorrowerAccounts(principal, 1, 10);
    assertEq(accounts.length, 1);
    assertEq(accounts[0], secondAccount);
    assertEq(registry.getBorrowerAccounts(principal, 2, 2).length, 0);
    assertEq(registry.getBorrowerAccounts(principal, 10, 20).length, 0);

    accounts = registry.getBorrowerAccountsForFactory(address(accountFactory), 0, 1);
    assertEq(accounts.length, 1);
    assertEq(accounts[0], firstAccount);

    vm.expectRevert(IBorrowerIdentityRegistry.InvalidPaginationRange.selector);
    registry.getBorrowerAccounts(principal, 2, 1);

    vm.expectRevert(IBorrowerIdentityRegistry.InvalidPaginationRange.selector);
    registry.getBorrowerAccountsForFactory(address(accountFactory), 2, 1);
  }
}
