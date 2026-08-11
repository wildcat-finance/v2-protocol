// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../BaseMarketTest.sol';
import 'src/interfaces/IBorrowerIdentityRegistry.sol';
import 'src/interfaces/IWildcatSanctionsEscrow.sol';
import 'src/vault/Wildcat4626Wrapper.sol';
import { MockChainalysis } from '../shared/mocks/MockChainalysis.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

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

  function _transferBorrower(address currentBorrower, address newBorrower) internal {
    _requestTransfer(currentBorrower, newBorrower);
    _acceptTransfer(newBorrower);
  }

  function _clearSanction(address account) internal {
    MockChainalysis(sanctionsSentinel.chainalysisSanctionsList()).unsanction(account);
  }

  function _deployWrapper() internal returns (Wildcat4626Wrapper wrapper) {
    wrapper = Wildcat4626Wrapper(wrapperFactory.createWrapper(address(market)));
    _authorizeLender(address(wrapper));
  }

  function _wrap(
    Wildcat4626Wrapper wrapper,
    address account,
    uint256 amount
  ) internal returns (uint256 shares) {
    _deposit(account, amount);
    vm.startPrank(account);
    market.approve(address(wrapper), amount);
    shares = wrapper.deposit(amount, account);
    vm.stopPrank();
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

  function test_borrowerAccountDrawChecksOperationalBorrowerAndPrincipal() external {
    _deposit(alice, 10e18);
    address account = _deployAccount(borrower);
    _transferBorrower(borrower, account);

    sanctionsSentinel.sanction(account);
    vm.prank(borrower);
    sanctionsSentinel.overrideSanction(account);

    vm.prank(account);
    vm.expectRevert(IMarketEventsAndErrors.BorrowWhileSanctioned.selector);
    market.borrow(1e18);

    _clearSanction(account);
    sanctionsSentinel.sanction(borrower);
    vm.prank(borrower);
    sanctionsSentinel.overrideSanction(borrower);

    vm.prank(account);
    vm.expectRevert(IMarketEventsAndErrors.BorrowWhileSanctioned.selector);
    market.borrow(1e18);
  }

  function test_samePrincipalAccountRotationPreservesLenderSanctionsOverride() external {
    Wildcat4626Wrapper wrapper = _deployWrapper();
    address firstAccount = _deployAccount(borrower);
    address secondAccount = _deployAccount(borrower);

    sanctionsSentinel.sanction(alice);
    vm.prank(borrower);
    sanctionsSentinel.overrideSanction(alice);

    _transferBorrower(borrower, firstAccount);
    _transferBorrower(firstAccount, secondAccount);

    vm.prank(alice);
    market.deposit(1e18);

    assertEq(market.borrower(), secondAccount);
    assertEq(market.borrowerPrincipal(), borrower);
    assertGt(wrapper.maxDeposit(alice), 0, 'wrapper lost principal override');
  }

  function test_principalMigrationStartsNewLenderSanctionsNamespace() external {
    Wildcat4626Wrapper wrapper = _deployWrapper();
    address account = _deployAccount(secondPrincipal);

    sanctionsSentinel.sanction(alice);
    vm.prank(borrower);
    sanctionsSentinel.overrideSanction(alice);
    _transferBorrower(borrower, account);

    assertFalse(sanctionsSentinel.isSanctioned(borrower, alice));
    assertTrue(sanctionsSentinel.isSanctioned(secondPrincipal, alice));

    vm.prank(alice);
    vm.expectRevert(IMarketEventsAndErrors.AccountBlocked.selector);
    market.deposit(1e18);
    assertEq(wrapper.maxDeposit(alice), 0, 'wrapper retained old principal override');

    vm.prank(secondPrincipal);
    sanctionsSentinel.overrideSanction(alice);
    vm.prank(alice);
    market.deposit(1e18);
    assertGt(wrapper.maxDeposit(alice), 0, 'wrapper ignored new principal override');
  }

  function test_sanctionedWithdrawalUsesPrincipalNamespace() external {
    address account = _deployAccount(secondPrincipal);
    _transferBorrower(borrower, account);
    _deposit(alice, 10e18);
    sanctionsSentinel.sanction(alice);

    market.nukeFromOrbit(alice);
    uint32 expiry = market.previousState().pendingWithdrawalExpiry;
    fastForward(parameters.withdrawalBatchDuration + 1);
    market.updateState();
    market.executeWithdrawal(alice, expiry);

    address principalEscrow = sanctionsSentinel.getEscrowAddress(
      secondPrincipal,
      alice,
      address(asset)
    );
    address accountEscrow = sanctionsSentinel.getEscrowAddress(account, alice, address(asset));

    assertTrue(principalEscrow != accountEscrow, 'escrow namespaces collided');
    assertGt(asset.balanceOf(principalEscrow), 0, 'principal escrow was not funded');
    assertEq(accountEscrow.code.length, 0, 'operational account escrow was deployed');
    assertEq(IWildcatSanctionsEscrow(principalEscrow).borrower(), secondPrincipal);
  }

  function test_existingMarketEscrowRemainsReleasableAfterPrincipalMigration() external {
    _deposit(alice, 10e18);
    sanctionsSentinel.sanction(alice);
    market.nukeFromOrbit(alice);
    uint32 expiry = market.previousState().pendingWithdrawalExpiry;
    fastForward(parameters.withdrawalBatchDuration + 1);
    market.updateState();
    market.executeWithdrawal(alice, expiry);

    address escrow = sanctionsSentinel.getEscrowAddress(borrower, alice, address(asset));
    uint256 escrowedAmount = asset.balanceOf(escrow);
    assertGt(escrowedAmount, 0, 'old escrow was not funded');

    _registerPrincipal(secondPrincipal);
    _transferBorrower(borrower, secondPrincipal);
    vm.prank(borrower);
    sanctionsSentinel.overrideSanction(alice);

    uint256 balanceBefore = asset.balanceOf(alice);
    IWildcatSanctionsEscrow(escrow).releaseEscrow();

    assertEq(asset.balanceOf(alice), balanceBefore + escrowedAmount);
    assertTrue(sanctionsSentinel.isSanctioned(secondPrincipal, alice));
  }

  function test_existingWrapperEscrowRemainsReleasableAfterPrincipalMigration() external {
    Wildcat4626Wrapper wrapper = _deployWrapper();
    uint256 shares = _wrap(wrapper, alice, 10e18);
    sanctionsSentinel.sanction(alice);
    wrapper.nukeFromOrbit(alice);

    address escrow = sanctionsSentinel.getEscrowAddress(borrower, alice, address(wrapper));
    assertEq(wrapper.balanceOf(escrow), shares, 'old wrapper escrow was not funded');

    _registerPrincipal(secondPrincipal);
    _transferBorrower(borrower, secondPrincipal);
    assertTrue(sanctionsSentinel.isSanctioned(secondPrincipal, alice));
    sanctionsSentinel.sanction(escrow);

    vm.prank(borrower);
    sanctionsSentinel.overrideSanction(alice);
    IWildcatSanctionsEscrow(escrow).releaseEscrow();

    assertEq(wrapper.balanceOf(alice), shares, 'old wrapper escrow did not release');
    assertEq(wrapper.balanceOf(escrow), 0, 'old wrapper escrow retained shares');
    assertTrue(sanctionsSentinel.isSanctioned(secondPrincipal, alice));
  }

  function test_existingWrapperEscrowRemainsReleasableAfterNewPrincipalOverride() external {
    Wildcat4626Wrapper wrapper = _deployWrapper();
    uint256 shares = _wrap(wrapper, alice, 10e18);
    sanctionsSentinel.sanction(alice);
    wrapper.nukeFromOrbit(alice);

    address escrow = sanctionsSentinel.getEscrowAddress(borrower, alice, address(wrapper));
    assertEq(wrapper.balanceOf(escrow), shares, 'old wrapper escrow was not funded');

    _registerPrincipal(secondPrincipal);
    _transferBorrower(borrower, secondPrincipal);
    sanctionsSentinel.sanction(escrow);

    vm.prank(borrower);
    sanctionsSentinel.overrideSanction(alice);
    vm.prank(secondPrincipal);
    sanctionsSentinel.overrideSanction(alice);
    IWildcatSanctionsEscrow(escrow).releaseEscrow();

    assertEq(wrapper.balanceOf(alice), shares, 'old wrapper escrow did not release');
    assertEq(wrapper.balanceOf(escrow), 0, 'old wrapper escrow retained shares');
    assertFalse(sanctionsSentinel.isSanctioned(secondPrincipal, alice));
  }

  function test_sanctionedWrapperSharesUsePrincipalNamespace() external {
    Wildcat4626Wrapper wrapper = _deployWrapper();
    uint256 shares = _wrap(wrapper, alice, 10e18);
    address account = _deployAccount(secondPrincipal);
    _transferBorrower(borrower, account);
    sanctionsSentinel.sanction(alice);

    wrapper.nukeFromOrbit(alice);

    address principalEscrow = sanctionsSentinel.getEscrowAddress(
      secondPrincipal,
      alice,
      address(wrapper)
    );
    address accountEscrow = sanctionsSentinel.getEscrowAddress(account, alice, address(wrapper));

    assertTrue(principalEscrow != accountEscrow, 'escrow namespaces collided');
    assertEq(wrapper.balanceOf(principalEscrow), shares, 'principal escrow was not funded');
    assertEq(accountEscrow.code.length, 0, 'operational account escrow was deployed');
    assertEq(IWildcatSanctionsEscrow(principalEscrow).borrower(), secondPrincipal);
  }

  function test_wrapperSweepAuthorityFollowsOperationalBorrower() external {
    Wildcat4626Wrapper wrapper = _deployWrapper();
    address account = _deployAccount(borrower);
    MockERC20 stray = new MockERC20('Stray', 'STRAY', 18);
    stray.mint(address(wrapper), 10e18);

    _transferBorrower(borrower, account);

    assertEq(wrapper.marketOwner(), account);
    vm.prank(borrower);
    vm.expectRevert(Wildcat4626Wrapper.NotMarketOwner.selector);
    wrapper.sweep(address(stray), borrower);

    vm.prank(account);
    wrapper.sweep(address(stray), account);
    assertEq(stray.balanceOf(account), 10e18);
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
