// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IHooks } from 'src/access/IHooks.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { WildcatBorrowerIdentityRegistry } from 'src/WildcatBorrowerIdentityRegistry.sol';
import { WildcatSanctionsSentinel } from 'src/WildcatSanctionsSentinel.sol';
import { IBorrowerIdentityRegistry } from 'src/interfaces/IBorrowerIdentityRegistry.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { DeployMarketInputs, MarketParameters } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { EmptyHooksConfig, HooksConfig } from 'src/types/HooksConfig.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { BorrowerIdentityAccountFactoryMock } from '../mocks/BorrowerIdentityMocks.sol';
import { BorrowerIdentityAccountMock } from '../mocks/BorrowerIdentityMocks.sol';
import { HookDispatchFactoryMock } from '../mocks/HookDispatchMocks.sol';
import { SanctionsListMock } from '../mocks/SanctionsMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract WildcatMarketBorrowerTransferTest is TestKernel {
  struct Fixture {
    WildcatMarket market;
    MockERC20 asset;
    OpenTermHooks hooks;
    WildcatArchController archController;
    WildcatBorrowerIdentityRegistry registry;
    WildcatSanctionsSentinel sentinel;
    SanctionsListMock sanctionsList;
    HookDispatchFactoryMock marketFactory;
    BorrowerIdentityAccountFactoryMock accountFactory;
  }

  event BorrowerTransferRequested(
    address indexed borrower,
    address indexed previousPendingBorrower,
    address indexed pendingBorrower,
    address borrowerPrincipal,
    address previousPendingBorrowerPrincipal,
    address pendingBorrowerPrincipal
  );

  event BorrowerTransferCancelled(
    address indexed borrower,
    address indexed cancelledPendingBorrower,
    address borrowerPrincipal,
    address cancelledPendingBorrowerPrincipal
  );

  event BorrowerTransferred(
    address indexed previousBorrower,
    address indexed newBorrower,
    address previousBorrowerPrincipal,
    address indexed newBorrowerPrincipal
  );

  address internal constant Borrower = address(0xB04405E4);
  address internal constant SecondPrincipal = address(0xB0B);
  address internal constant ThirdPrincipal = address(0xCAFE);
  address internal constant Lender = address(0xA11CE);
  address internal constant Outsider = address(0xBAD);
  address internal constant FeeRecipient = address(0xFEE);

  function _packString(string memory value) private pure returns (bytes32 word0, bytes32 word1) {
    require(bytes(value).length <= 63, 'fixture string too long');
    assembly {
      word0 := mload(add(value, 0x1f))
      word1 := mul(mload(add(value, 0x3f)), gt(mload(value), 0x1f))
    }
  }

  function _marketParameters(
    Fixture memory fixture,
    HooksConfig hooksConfig
  ) private pure returns (MarketParameters memory parameters) {
    (parameters.packedNameWord0, parameters.packedNameWord1) = _packString('Wildcat Token');
    (parameters.packedSymbolWord0, parameters.packedSymbolWord1) = _packString('WCTKN');
    parameters.asset = address(fixture.asset);
    parameters.decimals = 18;
    parameters.borrower = Borrower;
    parameters.feeRecipient = FeeRecipient;
    parameters.sentinel = address(fixture.sentinel);
    parameters.wrapperFactory = address(0x4626);
    parameters.maxTotalSupply = type(uint104).max;
    parameters.protocolFeeBips = 1_000;
    parameters.annualInterestBips = 1_000;
    parameters.delinquencyFeeBips = 1_000;
    parameters.withdrawalBatchDuration = 1 days;
    parameters.reserveRatioBips = 2_000;
    parameters.delinquencyGracePeriod = 2_000;
    parameters.archController = address(fixture.archController);
    parameters.hooks = hooksConfig;
    parameters.borrowerPrincipal = Borrower;
    parameters.borrowerIdentityRegistry = address(fixture.registry);
  }

  function _deploymentInputs(
    Fixture memory fixture,
    HooksConfig hooksConfig
  ) private pure returns (DeployMarketInputs memory inputs) {
    inputs.asset = address(fixture.asset);
    inputs.namePrefix = 'Wildcat ';
    inputs.symbolPrefix = 'WC';
    inputs.maxTotalSupply = type(uint104).max;
    inputs.annualInterestBips = 1_000;
    inputs.delinquencyFeeBips = 1_000;
    inputs.withdrawalBatchDuration = 1 days;
    inputs.reserveRatioBips = 2_000;
    inputs.delinquencyGracePeriod = 2_000;
    inputs.hooks = hooksConfig;
  }

  function _newFixture() private returns (Fixture memory fixture) {
    fixture.archController = WildcatArchController(
      _deployCode('src/WildcatArchController.sol:WildcatArchController')
    );
    fixture.registry = WildcatBorrowerIdentityRegistry(
      _deployCode(
        'src/WildcatBorrowerIdentityRegistry.sol:WildcatBorrowerIdentityRegistry',
        abi.encode(address(fixture.archController))
      )
    );
    fixture.sanctionsList = SanctionsListMock(
      _deployCode('test-next/mocks/SanctionsMocks.sol:SanctionsListMock')
    );
    fixture.sentinel = WildcatSanctionsSentinel(
      _deployCode(
        'src/WildcatSanctionsSentinel.sol:WildcatSanctionsSentinel',
        abi.encode(address(fixture.archController), address(fixture.sanctionsList))
      )
    );
    fixture.marketFactory = HookDispatchFactoryMock(
      _deployCode('test-next/mocks/HookDispatchMocks.sol:HookDispatchFactoryMock')
    );
    fixture.accountFactory = BorrowerIdentityAccountFactoryMock(
      _deployCode(
        'test-next/mocks/BorrowerIdentityMocks.sol:BorrowerIdentityAccountFactoryMock',
        abi.encode(address(fixture.registry))
      )
    );
    fixture.asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode('Token', 'TKN', uint8(18))
      )
    );
    fixture.hooks = OpenTermHooks(
      _deployCode('src/access/OpenTermHooks.sol:OpenTermHooks', abi.encode(Borrower, bytes('')))
    );

    fixture.archController.registerBorrower(Borrower);
    fixture.registry.addAccountFactory(address(fixture.accountFactory));

    HooksConfig requestedHooks = EmptyHooksConfig.setHooksAddress(address(fixture.hooks));
    HooksConfig marketHooks = requestedHooks.mergeFlags(fixture.hooks.config());
    fixture.marketFactory.setMarketParameters(_marketParameters(fixture, marketHooks));
    fixture.market = WildcatMarket(
      fixture.marketFactory.deployMarket(vm.getCode('src/market/WildcatMarket.sol:WildcatMarket'))
    );

    HooksConfig configuredHooks = fixture.hooks.onCreateMarket(
      Borrower,
      address(fixture.market),
      _deploymentInputs(fixture, requestedHooks),
      abi.encode(uint128(0), false)
    );
    assertEq(HooksConfig.unwrap(configuredHooks), HooksConfig.unwrap(marketHooks), 'hooks config');

    fixture.archController.registerControllerFactory(address(fixture.marketFactory));
    vm.prank(address(fixture.marketFactory));
    fixture.archController.registerController(address(fixture.marketFactory));
    vm.prank(address(fixture.marketFactory));
    fixture.archController.registerMarket(address(fixture.market));
  }

  function _registerPrincipal(Fixture memory fixture, address principal) private {
    if (!fixture.archController.isRegisteredBorrower(principal)) {
      fixture.archController.registerBorrower(principal);
    }
  }

  function _deployAccount(
    Fixture memory fixture,
    address principal
  ) private returns (address account) {
    _registerPrincipal(fixture, principal);
    account = _deployCode('test-next/mocks/BorrowerIdentityMocks.sol:BorrowerIdentityAccountMock');
    fixture.accountFactory.registerAccount(account, principal);
  }

  function _transferAccountPrincipal(
    Fixture memory fixture,
    address account,
    address currentPrincipal,
    address newPrincipal
  ) private {
    _registerPrincipal(fixture, newPrincipal);
    vm.prank(currentPrincipal);
    fixture.registry.requestBorrowerAccountPrincipalTransfer(account, newPrincipal);
    vm.prank(newPrincipal);
    fixture.registry.acceptBorrowerAccountPrincipalTransfer(account);
  }

  function _request(Fixture memory fixture, address currentBorrower, address newBorrower) private {
    vm.prank(currentBorrower);
    fixture.market.requestBorrowerTransfer(newBorrower);
  }

  function _accept(Fixture memory fixture, address newBorrower) private {
    vm.prank(newBorrower);
    fixture.market.acceptBorrowerTransfer();
  }

  function _transfer(Fixture memory fixture, address currentBorrower, address newBorrower) private {
    _request(fixture, currentBorrower, newBorrower);
    _accept(fixture, newBorrower);
  }

  function _marketStateHash(Fixture memory fixture) private view returns (bytes32 result) {
    bytes32[7] memory slots;
    for (uint256 i; i < slots.length; i++) {
      slots[i] = vm.load(address(fixture.market), bytes32(i));
    }
    return keccak256(abi.encode(slots));
  }

  function _fundAndApprove(Fixture memory fixture, address account, uint256 amount) private {
    fixture.asset.mint(account, amount);
    vm.prank(account);
    fixture.asset.approve(address(fixture.market), amount);
  }

  function _deposit(Fixture memory fixture, address account, uint256 amount) private {
    _fundAndApprove(fixture, account, amount);
    vm.prank(account);
    fixture.market.deposit(amount);
  }

  function _assertPending(
    Fixture memory fixture,
    address borrower,
    address principal
  ) private view {
    assertEq(fixture.market.pendingBorrower(), borrower, 'pending borrower');
    assertEq(fixture.market.pendingBorrowerPrincipal(), principal, 'pending principal');
  }

  function test_requestReplacementCancellationAndAuthorization() external {
    Fixture memory fixture = _newFixture();
    _registerPrincipal(fixture, SecondPrincipal);
    _registerPrincipal(fixture, ThirdPrincipal);
    bytes32 stateHash = _marketStateHash(fixture);

    vm.expectEmit(address(fixture.market));
    emit BorrowerTransferRequested(
      Borrower,
      address(0),
      SecondPrincipal,
      Borrower,
      address(0),
      SecondPrincipal
    );
    _request(fixture, Borrower, SecondPrincipal);
    _assertPending(fixture, SecondPrincipal, SecondPrincipal);
    assertEq(fixture.market.borrower(), Borrower, 'current borrower');
    assertEq(_marketStateHash(fixture), stateHash, 'request changed accounting');

    vm.prank(SecondPrincipal);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    fixture.market.setMaxTotalSupply(type(uint104).max - 1);

    vm.expectEmit(address(fixture.market));
    emit BorrowerTransferRequested(
      Borrower,
      SecondPrincipal,
      ThirdPrincipal,
      Borrower,
      SecondPrincipal,
      ThirdPrincipal
    );
    _request(fixture, Borrower, ThirdPrincipal);
    _assertPending(fixture, ThirdPrincipal, ThirdPrincipal);

    vm.prank(SecondPrincipal);
    vm.expectRevert(IMarketEventsAndErrors.NotPendingBorrower.selector);
    fixture.market.acceptBorrowerTransfer();

    vm.prank(Outsider);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    fixture.market.requestBorrowerTransfer(SecondPrincipal);
    vm.prank(Outsider);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    fixture.market.cancelBorrowerTransfer();
    vm.prank(Outsider);
    vm.expectRevert(IMarketEventsAndErrors.NotPendingBorrower.selector);
    fixture.market.acceptBorrowerTransfer();

    vm.expectEmit(address(fixture.market));
    emit BorrowerTransferCancelled(Borrower, ThirdPrincipal, Borrower, ThirdPrincipal);
    vm.prank(Borrower);
    fixture.market.cancelBorrowerTransfer();
    _assertPending(fixture, address(0), address(0));
    assertEq(_marketStateHash(fixture), stateHash, 'cancel changed accounting');

    vm.prank(Borrower);
    vm.expectRevert(IMarketEventsAndErrors.NoPendingBorrowerTransfer.selector);
    fixture.market.cancelBorrowerTransfer();
  }

  function test_requestRejectsInvalidIdentityTargets() external {
    Fixture memory fixture = _newFixture();

    vm.startPrank(Borrower);
    vm.expectRevert(IMarketEventsAndErrors.InvalidBorrowerTransferTarget.selector);
    fixture.market.requestBorrowerTransfer(address(0));
    vm.expectRevert(IMarketEventsAndErrors.InvalidBorrowerTransferTarget.selector);
    fixture.market.requestBorrowerTransfer(Borrower);
    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerIdentityNotFound.selector);
    fixture.market.requestBorrowerTransfer(Outsider);
    vm.stopPrank();
  }

  function test_requestRejectsMalformedRegistryResponses() external {
    Fixture memory fixture = _newFixture();
    _registerPrincipal(fixture, SecondPrincipal);
    bytes memory resolveCall = abi.encodeCall(
      IBorrowerIdentityRegistry.resolveBorrower,
      (SecondPrincipal)
    );

    vm.mockCall(address(fixture.registry), resolveCall, hex'01');
    vm.prank(Borrower);
    vm.expectRevert();
    fixture.market.requestBorrowerTransfer(SecondPrincipal);
    vm.clearMockedCalls();

    vm.mockCall(address(fixture.registry), resolveCall, abi.encode(uint256(type(uint160).max) + 1));
    vm.prank(Borrower);
    vm.expectRevert();
    fixture.market.requestBorrowerTransfer(SecondPrincipal);
    vm.clearMockedCalls();
  }

  function test_acceptSupportsEveryIdentityTransitionAndRemovedFactory() external {
    Fixture memory fixture = _newFixture();
    _registerPrincipal(fixture, SecondPrincipal);
    _registerPrincipal(fixture, ThirdPrincipal);
    address firstSecondAccount = _deployAccount(fixture, SecondPrincipal);
    address secondSecondAccount = _deployAccount(fixture, SecondPrincipal);
    address thirdAccount = _deployAccount(fixture, ThirdPrincipal);
    bytes32 stateHash = _marketStateHash(fixture);

    _request(fixture, Borrower, SecondPrincipal);
    vm.expectEmit(address(fixture.market));
    emit BorrowerTransferred(Borrower, SecondPrincipal, Borrower, SecondPrincipal);
    _accept(fixture, SecondPrincipal);
    assertEq(fixture.market.borrower(), SecondPrincipal, 'direct borrower');
    assertEq(fixture.market.borrowerPrincipal(), SecondPrincipal, 'direct principal');

    _transfer(fixture, SecondPrincipal, firstSecondAccount);
    assertEq(fixture.market.borrower(), firstSecondAccount, 'first account');
    assertEq(fixture.market.borrowerPrincipal(), SecondPrincipal, 'first account principal');

    _transfer(fixture, firstSecondAccount, secondSecondAccount);
    assertEq(fixture.market.borrower(), secondSecondAccount, 'rotated account');
    assertEq(fixture.market.borrowerPrincipal(), SecondPrincipal, 'rotated principal');

    fixture.registry.removeAccountFactory(address(fixture.accountFactory));
    _transfer(fixture, secondSecondAccount, thirdAccount);
    assertEq(fixture.market.borrower(), thirdAccount, 'removed-factory account');
    assertEq(fixture.market.borrowerPrincipal(), ThirdPrincipal, 'new account principal');

    _transfer(fixture, thirdAccount, ThirdPrincipal);
    assertEq(fixture.market.borrower(), ThirdPrincipal, 'account to direct');
    assertEq(fixture.market.borrowerPrincipal(), ThirdPrincipal, 'final principal');
    _assertPending(fixture, address(0), address(0));
    assertEq(_marketStateHash(fixture), stateHash, 'identity transitions changed accounting');

    vm.prank(thirdAccount);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    fixture.market.setMaxTotalSupply(type(uint104).max - 1);
    vm.prank(ThirdPrincipal);
    fixture.market.setMaxTotalSupply(type(uint104).max - 1);
  }

  function test_sameAccountPrincipalMigrationBindsPendingPrincipal() external {
    Fixture memory fixture = _newFixture();
    address expectedPrincipal = address(0x1000);
    address changedPrincipal = address(0x3000);
    address account = _deployAccount(fixture, Borrower);
    _transfer(fixture, Borrower, account);
    bytes32 stateHash = _marketStateHash(fixture);

    _transferAccountPrincipal(fixture, account, Borrower, expectedPrincipal);
    assertEq(
      fixture.market.borrowerPrincipal(),
      Borrower,
      'principal changed before market accepts'
    );

    vm.expectEmit(address(fixture.market));
    emit BorrowerTransferRequested(
      account,
      address(0),
      account,
      Borrower,
      address(0),
      expectedPrincipal
    );
    _request(fixture, account, account);
    _assertPending(fixture, account, expectedPrincipal);

    _transferAccountPrincipal(fixture, account, expectedPrincipal, changedPrincipal);
    vm.prank(account);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.PendingBorrowerPrincipalChanged.selector,
        expectedPrincipal,
        changedPrincipal
      )
    );
    fixture.market.acceptBorrowerTransfer();
    _assertPending(fixture, account, expectedPrincipal);

    vm.startPrank(account);
    fixture.market.cancelBorrowerTransfer();
    fixture.market.requestBorrowerTransfer(account);
    fixture.market.acceptBorrowerTransfer();
    vm.stopPrank();

    assertEq(fixture.market.borrower(), account, 'same account');
    assertEq(fixture.market.borrowerPrincipal(), changedPrincipal, 'updated principal');
    assertEq(_marketStateHash(fixture), stateHash, 'principal migration changed accounting');
  }

  function test_requestUsesRawSanctionsAndCancellationRemainsAvailable() external {
    Fixture memory cancelFixture = _newFixture();
    _registerPrincipal(cancelFixture, SecondPrincipal);
    _request(cancelFixture, Borrower, SecondPrincipal);
    cancelFixture.sanctionsList.sanction(Borrower);
    vm.prank(Borrower);
    cancelFixture.market.cancelBorrowerTransfer();
    _assertPending(cancelFixture, address(0), address(0));

    Fixture memory currentFixture = _newFixture();
    _registerPrincipal(currentFixture, SecondPrincipal);
    currentFixture.sanctionsList.sanction(Borrower);
    vm.prank(Borrower);
    currentFixture.sentinel.overrideSanction(Borrower);
    vm.prank(Borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.BorrowerTransferWhileSanctioned.selector,
        Borrower
      )
    );
    currentFixture.market.requestBorrowerTransfer(SecondPrincipal);

    Fixture memory targetFixture = _newFixture();
    _registerPrincipal(targetFixture, SecondPrincipal);
    targetFixture.sanctionsList.sanction(SecondPrincipal);
    vm.prank(Borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.BorrowerTransferWhileSanctioned.selector,
        SecondPrincipal
      )
    );
    targetFixture.market.requestBorrowerTransfer(SecondPrincipal);

    Fixture memory migrationFixture = _newFixture();
    address account = _deployAccount(migrationFixture, Borrower);
    _transfer(migrationFixture, Borrower, account);
    _transferAccountPrincipal(migrationFixture, account, Borrower, SecondPrincipal);
    migrationFixture.sanctionsList.sanction(Borrower);
    vm.prank(account);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.BorrowerTransferWhileSanctioned.selector,
        Borrower
      )
    );
    migrationFixture.market.requestBorrowerTransfer(account);
  }

  function test_acceptRevalidatesIdentityAndEverySanctionsIdentity() external {
    Fixture memory directFixture = _newFixture();
    _registerPrincipal(directFixture, SecondPrincipal);
    _request(directFixture, Borrower, SecondPrincipal);
    directFixture.archController.removeBorrower(SecondPrincipal);
    vm.prank(SecondPrincipal);
    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerIdentityNotFound.selector);
    directFixture.market.acceptBorrowerTransfer();
    _assertPending(directFixture, SecondPrincipal, SecondPrincipal);

    Fixture memory principalFixture = _newFixture();
    address principalAccount = _deployAccount(principalFixture, SecondPrincipal);
    _request(principalFixture, Borrower, principalAccount);
    principalFixture.archController.removeBorrower(SecondPrincipal);
    vm.prank(principalAccount);
    vm.expectRevert(IBorrowerIdentityRegistry.BorrowerPrincipalNotRegistered.selector);
    principalFixture.market.acceptBorrowerTransfer();

    Fixture memory ambiguousFixture = _newFixture();
    address ambiguousAccount = _deployAccount(ambiguousFixture, SecondPrincipal);
    _request(ambiguousFixture, Borrower, ambiguousAccount);
    ambiguousFixture.archController.registerBorrower(ambiguousAccount);
    vm.prank(ambiguousAccount);
    vm.expectRevert(IBorrowerIdentityRegistry.AmbiguousBorrowerIdentity.selector);
    ambiguousFixture.market.acceptBorrowerTransfer();

    Fixture memory currentSanctionFixture = _newFixture();
    address currentAccount = _deployAccount(currentSanctionFixture, Borrower);
    _transfer(currentSanctionFixture, Borrower, currentAccount);
    _registerPrincipal(currentSanctionFixture, SecondPrincipal);
    _request(currentSanctionFixture, currentAccount, SecondPrincipal);
    currentSanctionFixture.sanctionsList.sanction(Borrower);
    vm.prank(SecondPrincipal);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.BorrowerTransferWhileSanctioned.selector,
        Borrower
      )
    );
    currentSanctionFixture.market.acceptBorrowerTransfer();

    Fixture memory accountSanctionFixture = _newFixture();
    address sanctionedAccount = _deployAccount(accountSanctionFixture, SecondPrincipal);
    _request(accountSanctionFixture, Borrower, sanctionedAccount);
    accountSanctionFixture.sanctionsList.sanction(sanctionedAccount);
    vm.prank(sanctionedAccount);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.BorrowerTransferWhileSanctioned.selector,
        sanctionedAccount
      )
    );
    accountSanctionFixture.market.acceptBorrowerTransfer();

    Fixture memory targetSanctionFixture = _newFixture();
    address targetAccount = _deployAccount(targetSanctionFixture, SecondPrincipal);
    _request(targetSanctionFixture, Borrower, targetAccount);
    targetSanctionFixture.sanctionsList.sanction(SecondPrincipal);
    vm.prank(targetAccount);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMarketEventsAndErrors.BorrowerTransferWhileSanctioned.selector,
        SecondPrincipal
      )
    );
    targetSanctionFixture.market.acceptBorrowerTransfer();
  }

  function test_borrowChecksOperationalBorrowerAndPrincipalRawSanctions() external {
    Fixture memory fixture = _newFixture();
    _deposit(fixture, Lender, 10e18);
    address account = _deployAccount(fixture, Borrower);
    _transfer(fixture, Borrower, account);

    fixture.sanctionsList.sanction(account);
    vm.prank(Borrower);
    fixture.sentinel.overrideSanction(account);
    vm.prank(account);
    vm.expectRevert(IMarketEventsAndErrors.BorrowWhileSanctioned.selector);
    fixture.market.borrow(1e18);

    fixture.sanctionsList.unsanction(account);
    fixture.sanctionsList.sanction(Borrower);
    vm.prank(Borrower);
    fixture.sentinel.overrideSanction(Borrower);
    vm.prank(account);
    vm.expectRevert(IMarketEventsAndErrors.BorrowWhileSanctioned.selector);
    fixture.market.borrow(1e18);
  }

  function test_lenderSanctionsNamespaceFollowsBorrowerPrincipal() external {
    Fixture memory rotationFixture = _newFixture();
    address firstAccount = _deployAccount(rotationFixture, Borrower);
    address secondAccount = _deployAccount(rotationFixture, Borrower);
    rotationFixture.sanctionsList.sanction(Lender);
    vm.prank(Borrower);
    rotationFixture.sentinel.overrideSanction(Lender);
    _transfer(rotationFixture, Borrower, firstAccount);
    _transfer(rotationFixture, firstAccount, secondAccount);
    _deposit(rotationFixture, Lender, 1e18);
    assertEq(rotationFixture.market.balanceOf(Lender), 1e18, 'same-principal override');

    Fixture memory migrationFixture = _newFixture();
    address migratedAccount = _deployAccount(migrationFixture, SecondPrincipal);
    migrationFixture.sanctionsList.sanction(Lender);
    vm.prank(Borrower);
    migrationFixture.sentinel.overrideSanction(Lender);
    _transfer(migrationFixture, Borrower, migratedAccount);
    assertFalse(migrationFixture.sentinel.isSanctioned(Borrower, Lender), 'old namespace');
    assertTrue(migrationFixture.sentinel.isSanctioned(SecondPrincipal, Lender), 'new namespace');

    _fundAndApprove(migrationFixture, Lender, 1e18);
    vm.prank(Lender);
    vm.expectRevert(IMarketEventsAndErrors.AccountBlocked.selector);
    migrationFixture.market.deposit(1e18);
    vm.prank(SecondPrincipal);
    migrationFixture.sentinel.overrideSanction(Lender);
    vm.prank(Lender);
    migrationFixture.market.deposit(1e18);
  }

  function test_acceptPreservesActiveDelinquentAndClosedAccounting() external {
    Fixture memory activeFixture = _newFixture();
    _deposit(activeFixture, Lender, 10e18);
    vm.prank(Borrower);
    activeFixture.market.borrow(4e18);
    _registerPrincipal(activeFixture, SecondPrincipal);
    _request(activeFixture, Borrower, SecondPrincipal);
    bytes32 activeHash = _marketStateHash(activeFixture);
    _accept(activeFixture, SecondPrincipal);
    assertEq(_marketStateHash(activeFixture), activeHash, 'active accounting');

    Fixture memory delinquentFixture = _newFixture();
    _deposit(delinquentFixture, Lender, 10e18);
    vm.prank(Borrower);
    delinquentFixture.market.borrow(8e18);
    vm.prank(Lender);
    delinquentFixture.market.queueWithdrawal(10e18);
    MarketState memory delinquentState = delinquentFixture.market.currentState();
    assertTrue(delinquentState.isDelinquent, 'fixture should be delinquent');
    _registerPrincipal(delinquentFixture, SecondPrincipal);
    _request(delinquentFixture, Borrower, SecondPrincipal);
    bytes32 delinquentHash = _marketStateHash(delinquentFixture);
    _accept(delinquentFixture, SecondPrincipal);
    assertEq(_marketStateHash(delinquentFixture), delinquentHash, 'delinquent accounting');

    Fixture memory closedFixture = _newFixture();
    vm.prank(Borrower);
    closedFixture.market.closeMarket();
    _registerPrincipal(closedFixture, SecondPrincipal);
    _request(closedFixture, Borrower, SecondPrincipal);
    bytes32 closedHash = _marketStateHash(closedFixture);
    _accept(closedFixture, SecondPrincipal);
    assertTrue(closedFixture.market.isClosed(), 'closed state');
    assertEq(_marketStateHash(closedFixture), closedHash, 'closed accounting');
  }

  function testFuzz_replacementAcceptsOnlyLatestTarget(
    uint160 firstSeed,
    uint160 secondSeed
  ) external {
    Fixture memory fixture = _newFixture();
    address firstTarget = address(uint160(bound(firstSeed, 1, type(uint160).max)));
    address secondTarget = address(uint160(bound(secondSeed, 1, type(uint160).max)));
    vm.assume(firstTarget != Borrower);
    vm.assume(secondTarget != Borrower && secondTarget != firstTarget);
    _registerPrincipal(fixture, firstTarget);
    _registerPrincipal(fixture, secondTarget);

    _request(fixture, Borrower, firstTarget);
    _request(fixture, Borrower, secondTarget);

    vm.prank(firstTarget);
    vm.expectRevert(IMarketEventsAndErrors.NotPendingBorrower.selector);
    fixture.market.acceptBorrowerTransfer();
    _accept(fixture, secondTarget);

    assertEq(fixture.market.borrower(), secondTarget, 'latest target');
    assertEq(fixture.market.borrowerPrincipal(), secondTarget, 'latest principal');
    _assertPending(fixture, address(0), address(0));
  }
}
