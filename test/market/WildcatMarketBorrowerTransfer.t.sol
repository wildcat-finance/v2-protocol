// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../BaseMarketTest.sol';
import 'src/interfaces/IBorrowerIdentityRegistry.sol';

contract BorrowerTransferTestAccount {}

contract BorrowerTransferTestAccountFactory {
  IBorrowerIdentityRegistry public immutable registry;

  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  function deployAccount(address principal) external returns (address account) {
    account = address(new BorrowerTransferTestAccount());
    registry.registerBorrowerAccount(account, principal);
  }
}

contract WildcatMarketBorrowerTransferTest is BaseMarketTest {
  BorrowerTransferTestAccountFactory internal accountFactory;

  address internal constant secondPrincipal = address(0xB0B);
  address internal constant thirdPrincipal = address(0xCAFE);

  function setUp() public override {
    super.setUp();
    accountFactory = new BorrowerTransferTestAccountFactory(address(borrowerIdentityRegistry));
    borrowerIdentityRegistry.addAccountFactory(address(accountFactory));
  }

  function _registerPrincipal(address principal) internal {
    if (!archController.isRegisteredBorrower(principal)) {
      archController.registerBorrower(principal);
    }
  }

  function _deployAccount(address principal) internal returns (address) {
    _registerPrincipal(principal);
    return accountFactory.deployAccount(principal);
  }

  function _requestTransfer(address currentBorrower, address newBorrower) internal {
    vm.prank(currentBorrower);
    market.requestBorrowerTransfer(newBorrower);
  }

  function _acceptTransfer(address newBorrower) internal {
    vm.prank(newBorrower);
    market.acceptBorrowerTransfer();
  }

  function _marketStateHash() internal view returns (bytes32 result) {
    bytes32[7] memory slots;
    for (uint256 i = 0; i < slots.length; i++) {
      slots[i] = vm.load(address(market), bytes32(i));
    }
    result = keccak256(abi.encode(slots));
  }

  function _expectTransfer(
    address previousBorrower,
    address newBorrower,
    address previousPrincipal,
    address newPrincipal
  ) internal {
    vm.expectEmit(address(market));
    emit BorrowerTransferred(previousBorrower, newBorrower, previousPrincipal, newPrincipal);
    _acceptTransfer(newBorrower);
  }

  function test_requestBorrowerTransfer() external {
    _registerPrincipal(secondPrincipal);
    bytes32 stateHash = _marketStateHash();

    vm.expectEmit(address(market));
    emit BorrowerTransferRequested(
      borrower,
      address(0),
      secondPrincipal,
      borrower,
      secondPrincipal
    );
    _requestTransfer(borrower, secondPrincipal);

    assertEq(market.borrower(), borrower);
    assertEq(market.borrowerPrincipal(), borrower);
    assertEq(market.pendingBorrower(), secondPrincipal);
    assertEq(_marketStateHash(), stateHash, 'sequential market state changed');

    vm.prank(secondPrincipal);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    market.setMaxTotalSupply(DefaultMaximumSupply - 1);
  }

  function test_requestBorrowerTransfer_ReplacesPendingTarget() external {
    _registerPrincipal(secondPrincipal);
    _registerPrincipal(thirdPrincipal);
    _requestTransfer(borrower, secondPrincipal);

    vm.expectEmit(address(market));
    emit BorrowerTransferRequested(
      borrower,
      secondPrincipal,
      thirdPrincipal,
      borrower,
      thirdPrincipal
    );
    _requestTransfer(borrower, thirdPrincipal);

    assertEq(market.pendingBorrower(), thirdPrincipal);
    vm.prank(secondPrincipal);
    vm.expectRevert(IMarketEventsAndErrors.NotPendingBorrower.selector);
    market.acceptBorrowerTransfer();
  }

  function test_cancelBorrowerTransfer() external {
    _registerPrincipal(secondPrincipal);
    _requestTransfer(borrower, secondPrincipal);

    vm.expectEmit(address(market));
    emit BorrowerTransferCancelled(borrower, secondPrincipal, borrower);
    vm.prank(borrower);
    market.cancelBorrowerTransfer();

    assertEq(market.pendingBorrower(), address(0));
    vm.prank(secondPrincipal);
    vm.expectRevert(IMarketEventsAndErrors.NotPendingBorrower.selector);
    market.acceptBorrowerTransfer();
  }

  function test_cancelBorrowerTransfer_RemainsAvailableWhileBorrowerIsSanctioned() external {
    _registerPrincipal(secondPrincipal);
    _requestTransfer(borrower, secondPrincipal);
    sanctionsSentinel.sanction(borrower);

    vm.prank(borrower);
    market.cancelBorrowerTransfer();

    assertEq(market.pendingBorrower(), address(0));
  }

  function test_cancelBorrowerTransfer_NoPendingTransfer() external {
    vm.prank(borrower);
    vm.expectRevert(IMarketEventsAndErrors.NoPendingBorrowerTransfer.selector);
    market.cancelBorrowerTransfer();
  }

  function test_borrowerTransfer_Authorization() external {
    _registerPrincipal(secondPrincipal);

    vm.prank(alice);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    market.requestBorrowerTransfer(secondPrincipal);

    _requestTransfer(borrower, secondPrincipal);

    vm.prank(alice);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    market.cancelBorrowerTransfer();

    vm.prank(alice);
    vm.expectRevert(IMarketEventsAndErrors.NotPendingBorrower.selector);
    market.acceptBorrowerTransfer();
  }

  function test_requestBorrowerTransfer_InvalidTargets() external {
    vm.startPrank(borrower);
    vm.expectRevert(IMarketEventsAndErrors.InvalidBorrowerTransferTarget.selector);
    market.requestBorrowerTransfer(address(0));

    vm.expectRevert(IMarketEventsAndErrors.InvalidBorrowerTransferTarget.selector);
    market.requestBorrowerTransfer(borrower);

    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerIdentityNotFound.selector);
    market.requestBorrowerTransfer(address(0xBAD));
    vm.stopPrank();
  }

  function test_acceptBorrowerTransfer_DirectPrincipalToDirectPrincipal() external {
    _registerPrincipal(secondPrincipal);
    _requestTransfer(borrower, secondPrincipal);
    bytes32 stateHash = _marketStateHash();

    _expectTransfer(borrower, secondPrincipal, borrower, secondPrincipal);

    assertEq(market.borrower(), secondPrincipal);
    assertEq(market.borrowerPrincipal(), secondPrincipal);
    assertEq(market.pendingBorrower(), address(0));
    assertEq(_marketStateHash(), stateHash, 'sequential market state changed');

    _registerPrincipal(thirdPrincipal);
    vm.prank(borrower);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    market.requestBorrowerTransfer(thirdPrincipal);

    _requestTransfer(secondPrincipal, thirdPrincipal);
    assertEq(market.pendingBorrower(), thirdPrincipal);
  }

  function test_acceptBorrowerTransfer_DirectPrincipalToAccount() external {
    address account = _deployAccount(borrower);
    _requestTransfer(borrower, account);

    _expectTransfer(borrower, account, borrower, borrower);

    assertEq(market.borrower(), account);
    assertEq(market.borrowerPrincipal(), borrower);
  }

  function test_acceptBorrowerTransfer_AccountRotation() external {
    address firstAccount = _deployAccount(borrower);
    address secondAccount = _deployAccount(borrower);
    _requestTransfer(borrower, firstAccount);
    _acceptTransfer(firstAccount);

    _requestTransfer(firstAccount, secondAccount);
    _expectTransfer(firstAccount, secondAccount, borrower, borrower);

    assertEq(market.borrower(), secondAccount);
    assertEq(market.borrowerPrincipal(), borrower);
  }

  function test_acceptBorrowerTransfer_AccountToDirectPrincipal() external {
    address account = _deployAccount(borrower);
    _registerPrincipal(secondPrincipal);
    _requestTransfer(borrower, account);
    _acceptTransfer(account);

    _requestTransfer(account, secondPrincipal);
    _expectTransfer(account, secondPrincipal, borrower, secondPrincipal);

    assertEq(market.borrower(), secondPrincipal);
    assertEq(market.borrowerPrincipal(), secondPrincipal);
  }

  function test_acceptBorrowerTransfer_AccountToAccountOfNewPrincipal() external {
    address firstAccount = _deployAccount(borrower);
    address secondAccount = _deployAccount(secondPrincipal);
    _requestTransfer(borrower, firstAccount);
    _acceptTransfer(firstAccount);

    _requestTransfer(firstAccount, secondAccount);
    _expectTransfer(firstAccount, secondAccount, borrower, secondPrincipal);

    assertEq(market.borrower(), secondAccount);
    assertEq(market.borrowerPrincipal(), secondPrincipal);
  }

  function test_acceptBorrowerTransfer_AccountSurvivesFactoryRemoval() external {
    address account = _deployAccount(borrower);
    borrowerIdentityRegistry.removeAccountFactory(address(accountFactory));

    _requestTransfer(borrower, account);
    _acceptTransfer(account);

    assertEq(market.borrower(), account);
    assertEq(market.borrowerPrincipal(), borrower);
  }

  function test_acceptBorrowerTransfer_RevalidatesDirectPrincipalRegistration() external {
    _registerPrincipal(secondPrincipal);
    _requestTransfer(borrower, secondPrincipal);
    archController.removeBorrower(secondPrincipal);

    vm.prank(secondPrincipal);
    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerIdentityNotFound.selector);
    market.acceptBorrowerTransfer();

    assertEq(market.borrower(), borrower);
    assertEq(market.pendingBorrower(), secondPrincipal);
  }

  function test_acceptBorrowerTransfer_RevalidatesAccountPrincipalRegistration() external {
    address account = _deployAccount(secondPrincipal);
    _requestTransfer(borrower, account);
    archController.removeBorrower(secondPrincipal);

    vm.prank(account);
    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerPrincipalNotRegistered.selector);
    market.acceptBorrowerTransfer();

    assertEq(market.borrower(), borrower);
    assertEq(market.pendingBorrower(), account);
  }

  function test_acceptBorrowerTransfer_RevalidatesAmbiguousIdentity() external {
    address account = _deployAccount(secondPrincipal);
    _requestTransfer(borrower, account);
    archController.registerBorrower(account);

    vm.prank(account);
    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    market.acceptBorrowerTransfer();

    assertEq(market.borrower(), borrower);
    assertEq(market.pendingBorrower(), account);
  }

  function test_requestBorrowerTransfer_RejectsRawSanctionsDespiteOverride() external {
    _registerPrincipal(secondPrincipal);
    sanctionsSentinel.sanction(borrower);
    vm.prank(borrower);
    sanctionsSentinel.overrideSanction(borrower);

    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.BorrowerTransferWhileSanctioned.selector,
        borrower
      )
    );
    market.requestBorrowerTransfer(secondPrincipal);
  }

  function test_requestBorrowerTransfer_RejectsSanctionedTarget() external {
    _registerPrincipal(secondPrincipal);
    sanctionsSentinel.sanction(secondPrincipal);

    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.BorrowerTransferWhileSanctioned.selector,
        secondPrincipal
      )
    );
    market.requestBorrowerTransfer(secondPrincipal);
  }

  function test_acceptBorrowerTransfer_RevalidatesCurrentPrincipalSanctions() external {
    address account = _deployAccount(borrower);
    _registerPrincipal(secondPrincipal);
    _requestTransfer(borrower, account);
    _acceptTransfer(account);
    _requestTransfer(account, secondPrincipal);
    sanctionsSentinel.sanction(borrower);

    vm.prank(secondPrincipal);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.BorrowerTransferWhileSanctioned.selector,
        borrower
      )
    );
    market.acceptBorrowerTransfer();
  }

  function test_acceptBorrowerTransfer_RevalidatesTargetAccountSanctions() external {
    address account = _deployAccount(secondPrincipal);
    _requestTransfer(borrower, account);
    sanctionsSentinel.sanction(account);

    vm.prank(account);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.BorrowerTransferWhileSanctioned.selector,
        account
      )
    );
    market.acceptBorrowerTransfer();
  }

  function test_acceptBorrowerTransfer_RevalidatesTargetPrincipalSanctions() external {
    address account = _deployAccount(secondPrincipal);
    _requestTransfer(borrower, account);
    sanctionsSentinel.sanction(secondPrincipal);

    vm.prank(account);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.BorrowerTransferWhileSanctioned.selector,
        secondPrincipal
      )
    );
    market.acceptBorrowerTransfer();
  }

  function test_acceptBorrowerTransfer_ActiveMarketPreservesAccounting() external {
    _deposit(alice, 10e18);
    _borrow(4e18);
    _registerPrincipal(secondPrincipal);
    _requestTransfer(borrower, secondPrincipal);
    bytes32 stateHash = _marketStateHash();

    _acceptTransfer(secondPrincipal);

    assertEq(_marketStateHash(), stateHash, 'active market accounting changed');
  }

  function test_acceptBorrowerTransfer_DelinquentMarketPreservesAccounting() external {
    _depositBorrowWithdraw(alice, 10e18, 8e18, 10e18);
    assertTrue(market.currentState().isDelinquent, 'market should be delinquent');
    _registerPrincipal(secondPrincipal);
    _requestTransfer(borrower, secondPrincipal);
    bytes32 stateHash = _marketStateHash();

    _acceptTransfer(secondPrincipal);

    assertEq(_marketStateHash(), stateHash, 'delinquent market accounting changed');
  }

  function test_acceptBorrowerTransfer_ClosedMarketPreservesAccounting() external {
    _closeMarket();
    _registerPrincipal(secondPrincipal);
    _requestTransfer(borrower, secondPrincipal);
    bytes32 stateHash = _marketStateHash();

    _acceptTransfer(secondPrincipal);

    assertTrue(market.isClosed());
    assertEq(_marketStateHash(), stateHash, 'closed market accounting changed');
  }

  function testFuzz_borrowerTransferReplacementAcceptsOnlyLatestTarget(
    uint160 firstSeed,
    uint160 secondSeed
  ) external {
    address firstTarget = address(uint160(bound(firstSeed, 1, type(uint160).max)));
    address secondTarget = address(uint160(bound(secondSeed, 1, type(uint160).max)));
    vm.assume(firstTarget != borrower);
    vm.assume(secondTarget != borrower && secondTarget != firstTarget);
    _registerPrincipal(firstTarget);
    _registerPrincipal(secondTarget);

    _requestTransfer(borrower, firstTarget);
    _requestTransfer(borrower, secondTarget);

    vm.prank(firstTarget);
    vm.expectRevert(IMarketEventsAndErrors.NotPendingBorrower.selector);
    market.acceptBorrowerTransfer();

    _acceptTransfer(secondTarget);
    assertEq(market.borrower(), secondTarget);
    assertEq(market.borrowerPrincipal(), secondTarget);
    assertEq(market.pendingBorrower(), address(0));
  }
}
