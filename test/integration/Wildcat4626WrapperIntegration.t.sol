// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { WildcatBorrowerIdentityRegistry } from 'src/WildcatBorrowerIdentityRegistry.sol';
import { WildcatSanctionsSentinel } from 'src/WildcatSanctionsSentinel.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { IWildcatSanctionsEscrow } from 'src/interfaces/IWildcatSanctionsEscrow.sol';
import { DeployMarketInputs, MarketParameters } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { LibERC20 } from 'src/libraries/LibERC20.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { WildcatMarketRevolving } from 'src/market/WildcatMarketRevolving.sol';
import { ERC20RoleProvider } from 'src/providers/ERC20RoleProvider.sol';
import { ERC4626AssetsRoleProvider } from 'src/providers/ERC4626AssetsRoleProvider.sol';
import { EmptyHooksConfig, HooksConfig } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { Wildcat4626WrapperFactory } from 'src/vault/Wildcat4626WrapperFactory.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { BorrowerIdentityAccountFactoryMock } from '../mocks/BorrowerIdentityMocks.sol';
import { HookDispatchFactoryMock } from '../mocks/HookDispatchMocks.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { SanctionsListMock } from '../mocks/SanctionsMocks.sol';
import { WrapperQueueAccountMock } from '../mocks/WrapperQueueAccountMock.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// Keep the concrete hooks and revolving market imports even though deployment uses vm.getCode.
// The isolated coverage profile only instruments contracts reachable from this source graph.
contract Wildcat4626WrapperIntegrationTest is TestKernel {
  enum HooksKind {
    OpenTerm,
    FixedTerm,
    PeriodicTerm
  }

  struct Fixture {
    WildcatMarket market;
    MockERC20 asset;
    BaseAccessControls hooks;
    WildcatArchController archController;
    WildcatBorrowerIdentityRegistry registry;
    WildcatSanctionsSentinel sentinel;
    SanctionsListMock sanctionsList;
    HookDispatchFactoryMock marketFactory;
    BorrowerIdentityAccountFactoryMock accountFactory;
    Wildcat4626WrapperFactory wrapperFactory;
    MockRoleProvider roleProvider;
  }

  address internal constant Borrower = address(0xB04405E4);
  address internal constant SecondPrincipal = address(0xB0B);
  address internal constant Lender = address(0xA11CE);
  address internal constant OtherLender = address(0xCA401);
  address internal constant Outsider = address(0xBAD);
  address internal constant FeeRecipient = address(0xFEE);
  uint256 internal constant DepositAmount = 100e18;

  function _packString(string memory value) private pure returns (bytes32 word0, bytes32 word1) {
    require(bytes(value).length <= 63, 'fixture string too long');
    assembly ('memory-safe') {
      word0 := mload(add(value, 0x1f))
      word1 := mul(mload(add(value, 0x3f)), gt(mload(value), 0x1f))
    }
  }

  function _deployHooks(HooksKind kind) private returns (BaseAccessControls hooks) {
    string memory artifact;
    if (kind == HooksKind.OpenTerm) {
      artifact = 'src/access/OpenTermHooks.sol:OpenTermHooks';
    } else if (kind == HooksKind.FixedTerm) {
      artifact = 'src/access/FixedTermHooks.sol:FixedTermHooks';
    } else {
      artifact = 'src/access/PeriodicTermHooks.sol:PeriodicTermHooks';
    }
    hooks = BaseAccessControls(_deployCode(artifact, abi.encode(Borrower, bytes(''))));
  }

  function _hooksData(HooksKind kind) private view returns (bytes memory) {
    if (kind == HooksKind.OpenTerm) return abi.encode(uint128(0), false);
    if (kind == HooksKind.FixedTerm) {
      return abi.encode(uint32(vm.getBlockTimestamp() + 60 days), uint128(0), false, true, true);
    }
    return
      abi.encode(
        uint32(vm.getBlockTimestamp() + 23 days),
        uint32(30 days),
        uint32(7 days),
        uint96(0),
        false
      );
  }

  function _requestedHooks(address hooks) private pure returns (HooksConfig config) {
    return
      EmptyHooksConfig
        .setHooksAddress(hooks)
        .setFlag(Bit_Enabled_Deposit)
        .setFlag(Bit_Enabled_QueueWithdrawal)
        .setFlag(Bit_Enabled_Transfer);
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
    parameters.wrapperFactory = address(fixture.wrapperFactory);
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
    HooksConfig requestedHooks
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
    inputs.hooks = requestedHooks;
  }

  function _newFixture(HooksKind kind, bool revolving) private returns (Fixture memory fixture) {
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
      _deployCode('test/mocks/SanctionsMocks.sol:SanctionsListMock')
    );
    fixture.sentinel = WildcatSanctionsSentinel(
      _deployCode(
        'src/WildcatSanctionsSentinel.sol:WildcatSanctionsSentinel',
        abi.encode(address(fixture.archController), address(fixture.sanctionsList))
      )
    );
    fixture.wrapperFactory = Wildcat4626WrapperFactory(
      _deployCode(
        'src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory',
        abi.encode(address(fixture.archController), address(0))
      )
    );
    fixture.marketFactory = HookDispatchFactoryMock(
      _deployCode('test/mocks/HookDispatchMocks.sol:HookDispatchFactoryMock')
    );
    fixture.accountFactory = BorrowerIdentityAccountFactoryMock(
      _deployCode(
        'test/mocks/BorrowerIdentityMocks.sol:BorrowerIdentityAccountFactoryMock',
        abi.encode(address(fixture.registry))
      )
    );
    fixture.roleProvider = MockRoleProvider(
      _deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider')
    );
    fixture.asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode('Token', 'TKN', uint8(18))
      )
    );
    fixture.hooks = _deployHooks(kind);

    fixture.archController.registerBorrower(Borrower);
    fixture.registry.addAccountFactory(address(fixture.accountFactory));

    HooksConfig requestedHooks = _requestedHooks(address(fixture.hooks));
    HooksConfig marketHooks = requestedHooks.mergeFlags(IHooks(address(fixture.hooks)).config());
    fixture.marketFactory.setMarketParameters(_marketParameters(fixture, marketHooks));
    bytes memory marketCreationCode = revolving
      ? vm.getCode('src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving')
      : vm.getCode('src/market/WildcatMarket.sol:WildcatMarket');
    fixture.market = WildcatMarket(fixture.marketFactory.deployMarket(marketCreationCode));

    HooksConfig configuredHooks = IHooks(address(fixture.hooks)).onCreateMarket(
      Borrower,
      address(fixture.market),
      _deploymentInputs(fixture, requestedHooks),
      _hooksData(kind)
    );
    assertEq(HooksConfig.unwrap(configuredHooks), HooksConfig.unwrap(marketHooks), 'hooks config');

    fixture.archController.registerControllerFactory(address(fixture.marketFactory));
    vm.prank(address(fixture.marketFactory));
    fixture.archController.registerController(address(fixture.marketFactory));
    vm.prank(address(fixture.marketFactory));
    fixture.archController.registerMarket(address(fixture.market));

    vm.prank(Borrower);
    fixture.hooks.addRoleProvider(address(fixture.roleProvider), type(uint32).max);
    _authorize(fixture, Lender);
    _authorize(fixture, OtherLender);
  }

  function _authorize(Fixture memory fixture, address account) private {
    vm.prank(address(fixture.roleProvider));
    fixture.hooks.grantRole(account, uint32(vm.getBlockTimestamp()));
  }

  function _replaceLenderAccessProvider(Fixture memory fixture, address provider) private {
    vm.prank(Borrower);
    fixture.hooks.addRoleProvider(provider, 0);
    vm.prank(address(fixture.roleProvider));
    fixture.hooks.revokeRole(Lender);
  }

  function _deployWrapper(
    Fixture memory fixture,
    bool authorize
  ) private returns (Wildcat4626Wrapper wrapper) {
    wrapper = Wildcat4626Wrapper(fixture.wrapperFactory.createWrapper(address(fixture.market)));
    if (authorize) _authorize(fixture, address(wrapper));
  }

  function _fundAndApprove(Fixture memory fixture, address account, uint256 amount) private {
    fixture.asset.mint(account, amount);
    vm.prank(account);
    fixture.asset.approve(address(fixture.market), type(uint256).max);
  }

  function _deployAdditionalMarket(
    Fixture memory fixture,
    MockERC20 asset
  ) private returns (WildcatMarket market) {
    fixture.asset = asset;
    HooksConfig requestedHooks = _requestedHooks(address(fixture.hooks));
    HooksConfig marketHooks = requestedHooks.mergeFlags(IHooks(address(fixture.hooks)).config());
    fixture.marketFactory.setMarketParameters(_marketParameters(fixture, marketHooks));
    market = WildcatMarket(
      fixture.marketFactory.deployMarket(vm.getCode('src/market/WildcatMarket.sol:WildcatMarket'))
    );
    HooksConfig configuredHooks = IHooks(address(fixture.hooks)).onCreateMarket(
      Borrower,
      address(market),
      _deploymentInputs(fixture, requestedHooks),
      _hooksData(HooksKind.OpenTerm)
    );
    assertEq(HooksConfig.unwrap(configuredHooks), HooksConfig.unwrap(marketHooks), 'target hooks');
    vm.prank(address(fixture.marketFactory));
    fixture.archController.registerMarket(address(market));
  }

  function _newAsset(string memory name, string memory symbol) private returns (MockERC20 asset) {
    asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode(name, symbol, uint8(18))
      )
    );
  }

  function _fundTargetDeposit(MockERC20 asset, WildcatMarket market) private {
    asset.mint(Lender, 1e18);
    vm.prank(Lender);
    asset.approve(address(market), type(uint256).max);
  }

  function _expectTargetDepositDenied(WildcatMarket market) private {
    vm.prank(Lender);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.depositUpTo(1e18);
  }

  function _deposit(Fixture memory fixture, address account, uint256 amount) private {
    _fundAndApprove(fixture, account, amount);
    vm.prank(account);
    fixture.market.deposit(amount);
  }

  function _wrap(
    Fixture memory fixture,
    Wildcat4626Wrapper wrapper,
    address account,
    uint256 amount
  ) private returns (uint256 shares) {
    _deposit(fixture, account, amount);
    vm.startPrank(account);
    fixture.market.approve(address(wrapper), type(uint256).max);
    shares = wrapper.deposit(amount, account);
    vm.stopPrank();
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
    account = _deployCode('test/mocks/BorrowerIdentityMocks.sol:BorrowerIdentityAccountMock');
    fixture.accountFactory.registerAccount(account, principal);
  }

  function _transferBorrower(
    Fixture memory fixture,
    address currentBorrower,
    address newBorrower
  ) private {
    vm.prank(currentBorrower);
    fixture.market.requestBorrowerTransfer(newBorrower);
    vm.prank(newBorrower);
    fixture.market.acceptBorrowerTransfer();
  }

  function test_registrationAndReadinessUseProductionMarketsAndEveryBuiltInHook() external {
    for (uint256 i; i < 3; i++) {
      Fixture memory fixture = _newFixture(HooksKind(i), false);

      vm.expectRevert(IMarketEventsAndErrors.NotWrapperFactory.selector);
      fixture.market.registerWrapper(address(0xBEEF));

      Wildcat4626Wrapper wrapper = _deployWrapper(fixture, false);
      assertEq(fixture.market.registeredWrapper(), address(wrapper), 'market registration');
      assertEq(
        fixture.wrapperFactory.wrapperForMarket(address(fixture.market)),
        address(wrapper),
        'factory registration'
      );
      assertEq(wrapper.maxDeposit(Lender), 0, 'uncredentialed deposit limit');
      assertEq(wrapper.maxMint(Lender), 0, 'uncredentialed mint limit');
      assertTrue(wrapper.previewDeposit(1e18) > 0, 'preview should remain arithmetic');

      _authorize(fixture, address(wrapper));
      assertTrue(wrapper.maxDeposit(Lender) > 0, 'credentialed deposit limit');
      assertTrue(wrapper.maxMint(Lender) > 0, 'credentialed mint limit');

      vm.prank(address(fixture.wrapperFactory));
      vm.expectRevert(IMarketEventsAndErrors.WrapperAlreadyRegistered.selector);
      fixture.market.registerWrapper(address(0xBEEF));
    }
  }

  function test_redeemAndScaledQueueRemainAtomicAcrossMarketTypes() external {
    for (uint256 revolving; revolving < 2; revolving++) {
      _assertRedeemAndScaledQueue(false, revolving == 1);
      _assertRedeemAndScaledQueue(true, revolving == 1);
    }
  }

  function _assertRedeemAndScaledQueue(bool shouldFail, bool revolving) private {
    uint256 directScaledBalance = 10e18;
    uint256 wrappedShares = 25e18;
    Fixture memory fixture = _newFixture(HooksKind.OpenTerm, revolving);
    Wildcat4626Wrapper wrapper = _deployWrapper(fixture, true);
    WrapperQueueAccountMock account = WrapperQueueAccountMock(
      _deployCode('test/mocks/WrapperQueueAccountMock.sol:WrapperQueueAccountMock')
    );
    _authorize(fixture, address(account));

    fixture.asset.mint(address(account), directScaledBalance + wrappedShares);
    vm.startPrank(address(account));
    fixture.asset.approve(address(fixture.market), type(uint256).max);
    fixture.market.deposit(directScaledBalance + wrappedShares);
    fixture.market.approve(address(wrapper), type(uint256).max);
    wrapper.deposit(wrappedShares, address(account));
    vm.stopPrank();
    assertEq(fixture.market.scaledBalanceOf(address(account)), directScaledBalance, 'direct scale');

    vm.warp(vm.getBlockTimestamp() + 30 days);
    if (shouldFail) {
      bytes32 stateBefore = keccak256(abi.encode(fixture.market.currentState()));
      vm.expectRevert(abi.encodeWithSelector(bytes4(0x4e487b71), uint256(0x11)));
      account.redeemAndQueue(
        wrapper,
        fixture.market,
        wrappedShares,
        directScaledBalance + wrappedShares + 1
      );
      assertEq(wrapper.balanceOf(address(account)), wrappedShares, 'rollback shares');
      assertEq(wrapper.totalSupply(), wrappedShares, 'rollback supply');
      assertEq(fixture.market.scaledBalanceOf(address(wrapper)), wrappedShares, 'rollback backing');
      assertEq(
        fixture.market.scaledBalanceOf(address(account)),
        directScaledBalance,
        'rollback direct scale'
      );
      assertEq(
        keccak256(abi.encode(fixture.market.currentState())),
        stateBefore,
        'rollback market state'
      );
      return;
    }

    (uint256 assets, uint32 expiry) = account.redeemAndQueue(
      wrapper,
      fixture.market,
      wrappedShares,
      wrappedShares
    );
    assertTrue(assets > wrappedShares, 'accrued redemption');
    assertEq(wrapper.balanceOf(address(account)), 0, 'remaining shares');
    assertEq(wrapper.totalSupply(), 0, 'remaining supply');
    assertEq(fixture.market.scaledBalanceOf(address(wrapper)), 0, 'remaining backing');
    assertEq(
      fixture.market.scaledBalanceOf(address(account)),
      directScaledBalance,
      'direct scale changed'
    );
    assertEq(
      fixture.market.getAccountWithdrawalStatus(address(account), expiry).scaledAmount,
      wrappedShares,
      'queued scale'
    );
  }

  function test_wrapperCoordinatesDirectAndShareQuarantineWithoutFreezingOtherHolders() external {
    Fixture memory fixture = _newFixture(HooksKind.OpenTerm, false);
    Wildcat4626Wrapper wrapper = _deployWrapper(fixture, true);
    uint256 lenderShares = _wrap(fixture, wrapper, Lender, DepositAmount);
    uint256 otherShares = _wrap(fixture, wrapper, OtherLender, DepositAmount);
    _deposit(fixture, Lender, DepositAmount);

    uint256 backingBefore = fixture.market.scaledBalanceOf(address(wrapper));
    uint256 supplyBefore = wrapper.totalSupply();
    fixture.sanctionsList.sanction(Lender);
    vm.prank(Outsider);
    wrapper.nukeFromOrbit(Lender);

    address escrow = fixture.sentinel.getEscrowAddress(Borrower, Lender, address(wrapper));
    assertEq(fixture.market.scaledBalanceOf(Lender), 0, 'direct position');
    assertEq(wrapper.balanceOf(Lender), 0, 'holder shares');
    assertEq(wrapper.balanceOf(escrow), lenderShares, 'escrow shares');
    assertEq(wrapper.balanceOf(OtherLender), otherShares, 'other holder shares');
    assertEq(wrapper.totalSupply(), supplyBefore, 'share supply');
    assertEq(fixture.market.scaledBalanceOf(address(wrapper)), backingBefore, 'wrapper backing');

    (address escrowedAsset, uint256 escrowedShares) = IWildcatSanctionsEscrow(escrow)
      .escrowedAsset();
    assertEq(escrowedAsset, address(wrapper), 'escrow asset');
    assertEq(escrowedShares, lenderShares, 'escrow balance');

    uint256 otherMarketBalanceBefore = fixture.market.scaledBalanceOf(OtherLender);
    vm.prank(OtherLender);
    wrapper.redeem(otherShares, OtherLender, OtherLender);
    assertEq(
      fixture.market.scaledBalanceOf(OtherLender),
      otherMarketBalanceBefore + otherShares,
      'other holder redemption'
    );
    assertEq(wrapper.balanceOf(escrow), lenderShares, 'escrow after redemption');
    assertEq(wrapper.totalSupply(), lenderShares, 'remaining supply');
    assertEq(
      fixture.market.scaledBalanceOf(address(wrapper)),
      wrapper.totalSupply(),
      'remaining backing'
    );
  }

  function test_marketAndWrapperNukesComposeWithoutPuttingBackingAtRisk() external {
    Fixture memory fixture = _newFixture(HooksKind.OpenTerm, false);
    Wildcat4626Wrapper wrapper = _deployWrapper(fixture, true);
    uint256 lenderShares = _wrap(fixture, wrapper, Lender, DepositAmount);
    uint256 otherShares = _wrap(fixture, wrapper, OtherLender, DepositAmount);
    _deposit(fixture, Lender, DepositAmount);

    fixture.sanctionsList.sanction(Lender);
    fixture.market.nukeFromOrbit(Lender);
    assertEq(fixture.market.scaledBalanceOf(Lender), 0, 'market quarantine');
    assertEq(wrapper.balanceOf(Lender), lenderShares, 'market moved wrapper shares');

    vm.prank(Lender);
    vm.expectRevert(abi.encodeWithSelector(Wildcat4626Wrapper.SanctionedAccount.selector, Lender));
    wrapper.transfer(OtherLender, lenderShares);

    wrapper.nukeFromOrbit(Lender);
    address lenderEscrow = fixture.sentinel.getEscrowAddress(Borrower, Lender, address(wrapper));
    assertEq(wrapper.balanceOf(lenderEscrow), lenderShares, 'wrapper quarantine');

    uint256 backingBefore = fixture.market.scaledBalanceOf(address(wrapper));
    fixture.sanctionsList.sanction(address(wrapper));
    vm.expectRevert(Wildcat4626Wrapper.CannotNukeWrapper.selector);
    wrapper.nukeFromOrbit(address(wrapper));
    vm.expectRevert(IMarketEventsAndErrors.CannotNukeWrapper.selector);
    fixture.market.nukeFromOrbit(address(wrapper));
    assertEq(fixture.market.scaledBalanceOf(address(wrapper)), backingBefore, 'backing changed');
    assertEq(wrapper.maxRedeem(OtherLender), 0, 'sanctioned wrapper limit');

    fixture.sanctionsList.unsanction(address(wrapper));
    vm.prank(OtherLender);
    wrapper.redeem(otherShares, OtherLender, OtherLender);
    assertEq(wrapper.totalSupply(), lenderShares, 'recovered supply');
    assertEq(fixture.market.scaledBalanceOf(address(wrapper)), lenderShares, 'recovered backing');
  }

  function test_foreignPrincipalEscrowCannotReleaseSharesToSanctionedHolder() external {
    Fixture memory fixture = _newFixture(HooksKind.OpenTerm, false);
    Wildcat4626Wrapper wrapper = _deployWrapper(fixture, true);
    uint256 shares = _wrap(fixture, wrapper, OtherLender, DepositAmount);
    fixture.sanctionsList.sanction(Lender);

    vm.prank(OtherLender);
    vm.expectRevert(abi.encodeWithSelector(Wildcat4626Wrapper.SanctionedAccount.selector, Lender));
    wrapper.transfer(Lender, shares);

    address foreignEscrow = fixture.sentinel.createEscrow(Outsider, Lender, address(wrapper));
    vm.prank(OtherLender);
    wrapper.transfer(foreignEscrow, shares);
    vm.prank(Outsider);
    fixture.sentinel.overrideSanction(Lender);

    assertTrue(fixture.sentinel.isSanctioned(Borrower, Lender), 'live principal sanction');
    assertFalse(fixture.sentinel.isSanctioned(Outsider, Lender), 'foreign override');
    vm.expectRevert(LibERC20.TransferFailed.selector);
    IWildcatSanctionsEscrow(foreignEscrow).releaseEscrow();
    assertEq(wrapper.balanceOf(foreignEscrow), shares, 'foreign escrow rollback');
    assertEq(wrapper.balanceOf(Lender), 0, 'sanctioned holder balance');
  }

  function test_precreatedCurrentPrincipalEscrowIsAuthorizedWhenWrapperNukesHolder() external {
    Fixture memory fixture = _newFixture(HooksKind.OpenTerm, false);
    Wildcat4626Wrapper wrapper = _deployWrapper(fixture, true);
    uint256 shares = _wrap(fixture, wrapper, Lender, DepositAmount);
    address escrow = fixture.sentinel.createEscrow(Borrower, Lender, address(wrapper));

    fixture.sanctionsList.sanction(Lender);
    wrapper.nukeFromOrbit(Lender);
    assertEq(wrapper.balanceOf(escrow), shares, 'precreated escrow funding');

    vm.prank(Borrower);
    fixture.sentinel.overrideSanction(Lender);
    IWildcatSanctionsEscrow(escrow).releaseEscrow();

    assertEq(wrapper.balanceOf(escrow), 0, 'precreated escrow remainder');
    assertEq(wrapper.balanceOf(Lender), shares, 'current principal release');
  }

  function test_wrapperEscrowsRemainReleasableInTheirOriginalPrincipalNamespace() external {
    Fixture memory fixture = _newFixture(HooksKind.OpenTerm, false);
    Wildcat4626Wrapper wrapper = _deployWrapper(fixture, true);
    uint256 shares = _wrap(fixture, wrapper, Lender, DepositAmount);
    fixture.sanctionsList.sanction(Lender);
    wrapper.nukeFromOrbit(Lender);

    address oldEscrow = fixture.sentinel.getEscrowAddress(Borrower, Lender, address(wrapper));
    assertEq(wrapper.balanceOf(oldEscrow), shares, 'old escrow funding');
    vm.expectRevert(IWildcatSanctionsEscrow.CanNotReleaseEscrow.selector);
    IWildcatSanctionsEscrow(oldEscrow).releaseEscrow();

    _registerPrincipal(fixture, SecondPrincipal);
    _transferBorrower(fixture, Borrower, SecondPrincipal);
    fixture.sanctionsList.sanction(oldEscrow);
    vm.prank(Borrower);
    fixture.sentinel.overrideSanction(Lender);
    IWildcatSanctionsEscrow(oldEscrow).releaseEscrow();

    assertEq(wrapper.balanceOf(Lender), shares, 'old escrow release');
    assertEq(wrapper.balanceOf(oldEscrow), 0, 'old escrow remainder');
    assertTrue(fixture.sentinel.isSanctioned(SecondPrincipal, Lender), 'new namespace');

    wrapper.nukeFromOrbit(Lender);
    address newEscrow = fixture.sentinel.getEscrowAddress(
      SecondPrincipal,
      Lender,
      address(wrapper)
    );
    assertTrue(newEscrow != oldEscrow, 'escrow namespace');
    assertEq(wrapper.balanceOf(newEscrow), shares, 'new escrow funding');
    vm.prank(SecondPrincipal);
    fixture.sentinel.overrideSanction(Lender);
    IWildcatSanctionsEscrow(newEscrow).releaseEscrow();
    assertEq(wrapper.balanceOf(Lender), shares, 'new escrow release');
    assertEq(wrapper.balanceOf(newEscrow), 0, 'new escrow remainder');
  }

  function test_wrapperNamespaceAndSweepAuthorityFollowTheLiveBorrowerIdentity() external {
    Fixture memory fixture = _newFixture(HooksKind.OpenTerm, false);
    Wildcat4626Wrapper wrapper = _deployWrapper(fixture, true);
    uint256 shares = _wrap(fixture, wrapper, Lender, DepositAmount);
    address account = _deployAccount(fixture, SecondPrincipal);
    _transferBorrower(fixture, Borrower, account);

    fixture.sanctionsList.sanction(Lender);
    wrapper.nukeFromOrbit(Lender);
    address principalEscrow = fixture.sentinel.getEscrowAddress(
      SecondPrincipal,
      Lender,
      address(wrapper)
    );
    address accountEscrow = fixture.sentinel.getEscrowAddress(account, Lender, address(wrapper));
    assertTrue(principalEscrow != accountEscrow, 'principal namespace');
    assertEq(wrapper.balanceOf(principalEscrow), shares, 'principal escrow');
    assertEq(accountEscrow.code.length, 0, 'account escrow');
    assertEq(IWildcatSanctionsEscrow(principalEscrow).borrower(), SecondPrincipal, 'escrow owner');

    MockERC20 stray = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode('Stray', 'STRAY', uint8(18))
      )
    );
    stray.mint(address(wrapper), DepositAmount);
    assertEq(wrapper.marketOwner(), account, 'market owner');
    vm.prank(Borrower);
    vm.expectRevert(Wildcat4626Wrapper.NotMarketOwner.selector);
    wrapper.sweep(address(stray), Borrower);
    vm.prank(SecondPrincipal);
    vm.expectRevert(Wildcat4626Wrapper.NotMarketOwner.selector);
    wrapper.sweep(address(stray), SecondPrincipal);
    vm.prank(account);
    wrapper.sweep(address(stray), account);
    assertEq(stray.balanceOf(account), DepositAmount, 'swept balance');
  }

  function test_lenderOverridesStayWithThePrincipalAndWrapperReadinessTracksMigration() external {
    Fixture memory fixture = _newFixture(HooksKind.OpenTerm, false);
    Wildcat4626Wrapper wrapper = _deployWrapper(fixture, true);
    address firstAccount = _deployAccount(fixture, Borrower);
    address secondAccount = _deployAccount(fixture, Borrower);

    fixture.sanctionsList.sanction(Lender);
    vm.prank(Borrower);
    fixture.sentinel.overrideSanction(Lender);
    _transferBorrower(fixture, Borrower, firstAccount);
    _transferBorrower(fixture, firstAccount, secondAccount);
    assertTrue(wrapper.maxDeposit(Lender) > 0, 'same-principal readiness');

    address migratedAccount = _deployAccount(fixture, SecondPrincipal);
    _transferBorrower(fixture, secondAccount, migratedAccount);
    assertEq(wrapper.maxDeposit(Lender), 0, 'old override survived migration');
    vm.prank(SecondPrincipal);
    fixture.sentinel.overrideSanction(Lender);
    assertTrue(wrapper.maxDeposit(Lender) > 0, 'new-principal readiness');
  }

  function test_zeroBalanceRepeatAndRevolvingNukesShareTheSameQuarantineRules() external {
    Fixture memory emptyFixture = _newFixture(HooksKind.OpenTerm, false);
    Wildcat4626Wrapper emptyWrapper = _deployWrapper(emptyFixture, true);
    emptyFixture.sanctionsList.sanction(Lender);
    address emptyEscrow = emptyFixture.sentinel.getEscrowAddress(
      Borrower,
      Lender,
      address(emptyWrapper)
    );
    emptyWrapper.nukeFromOrbit(Lender);
    emptyWrapper.nukeFromOrbit(Lender);
    assertEq(emptyEscrow.code.length, 0, 'empty escrow deployed');

    Fixture memory revolvingFixture = _newFixture(HooksKind.OpenTerm, true);
    Wildcat4626Wrapper revolvingWrapper = _deployWrapper(revolvingFixture, true);
    uint256 shares = _wrap(revolvingFixture, revolvingWrapper, Lender, DepositAmount);
    _deposit(revolvingFixture, Lender, DepositAmount);
    revolvingFixture.sanctionsList.sanction(Lender);
    revolvingWrapper.nukeFromOrbit(Lender);
    address revolvingEscrow = revolvingFixture.sentinel.getEscrowAddress(
      Borrower,
      Lender,
      address(revolvingWrapper)
    );
    assertEq(revolvingFixture.market.scaledBalanceOf(Lender), 0, 'revolving direct balance');
    assertEq(revolvingWrapper.balanceOf(Lender), 0, 'revolving shares');
    assertEq(revolvingWrapper.balanceOf(revolvingEscrow), shares, 'revolving escrow');
    revolvingWrapper.nukeFromOrbit(Lender);
    assertEq(revolvingWrapper.balanceOf(revolvingEscrow), shares, 'repeat revolving nuke');
  }

  function test_wildcatDebtTokenCannotAuthorizeDepositsIntoItsOwnMarket() external {
    Fixture memory fixture = _newFixture(HooksKind.OpenTerm, false);
    _deposit(fixture, Lender, 1e18);
    ERC20RoleProvider provider = ERC20RoleProvider(
      _deployCode(
        'src/providers/ERC20RoleProvider.sol:ERC20RoleProvider',
        abi.encode(address(fixture.market), 1e18)
      )
    );
    assertEq(provider.getCredential(Lender), uint32(vm.getBlockTimestamp()), 'outside credential');

    _replaceLenderAccessProvider(fixture, address(provider));
    fixture.asset.mint(Lender, 1e18);
    _expectTargetDepositDenied(fixture.market);
    assertEq(
      provider.getCredential(Lender),
      uint32(vm.getBlockTimestamp()),
      'credential after blocked deposit'
    );
  }

  function test_wildcatDebtTokenInterestCanAuthorizeADifferentMarket() external {
    Fixture memory fixture = _newFixture(HooksKind.OpenTerm, false);
    _deposit(fixture, Lender, DepositAmount);
    uint256 borrowableAssets = fixture.market.borrowableAssets();
    vm.prank(Borrower);
    fixture.market.borrow(borrowableAssets);

    uint256 minimumBalance = fixture.market.balanceOf(Lender) + 1e18;
    ERC20RoleProvider provider = ERC20RoleProvider(
      _deployCode(
        'src/providers/ERC20RoleProvider.sol:ERC20RoleProvider',
        abi.encode(address(fixture.market), minimumBalance)
      )
    );
    MockERC20 targetAsset = _newAsset('Target Token', 'TGT');
    WildcatMarket targetMarket = _deployAdditionalMarket(fixture, targetAsset);
    _replaceLenderAccessProvider(fixture, address(provider));
    _fundTargetDeposit(targetAsset, targetMarket);

    assertEq(provider.getCredential(Lender), 0, 'credential before interest');
    _expectTargetDepositDenied(targetMarket);
    vm.warp(vm.getBlockTimestamp() + 365 days);
    fixture.market.updateState();

    assertTrue(fixture.market.balanceOf(Lender) >= minimumBalance, 'debt-token balance');
    assertEq(provider.getCredential(Lender), uint32(vm.getBlockTimestamp()), 'credential');
    vm.prank(Lender);
    targetMarket.depositUpTo(1e18);
  }

  function test_wildcatWrapperInterestCanAuthorizeADifferentMarket() external {
    Fixture memory fixture = _newFixture(HooksKind.OpenTerm, false);
    _deposit(fixture, Lender, DepositAmount);
    uint256 borrowableAssets = fixture.market.borrowableAssets();
    vm.prank(Borrower);
    fixture.market.borrow(borrowableAssets);
    Wildcat4626Wrapper wrapper = _deployWrapper(fixture, true);
    vm.startPrank(Lender);
    fixture.market.approve(address(wrapper), type(uint256).max);
    uint256 shares = wrapper.deposit(DepositAmount, Lender);
    vm.stopPrank();

    uint256 minimumAssets = wrapper.convertToAssets(shares) + 1e18;
    ERC4626AssetsRoleProvider provider = ERC4626AssetsRoleProvider(
      _deployCode(
        'src/providers/ERC4626AssetsRoleProvider.sol:ERC4626AssetsRoleProvider',
        abi.encode(address(wrapper), minimumAssets)
      )
    );
    MockERC20 targetAsset = _newAsset('Target Token', 'TGT');
    WildcatMarket targetMarket = _deployAdditionalMarket(fixture, targetAsset);
    _replaceLenderAccessProvider(fixture, address(provider));
    _fundTargetDeposit(targetAsset, targetMarket);

    assertEq(provider.getCredential(Lender), 0, 'credential before interest');
    _expectTargetDepositDenied(targetMarket);
    vm.warp(vm.getBlockTimestamp() + 365 days);
    fixture.market.updateState();

    assertTrue(wrapper.convertToAssets(shares) >= minimumAssets, 'wrapped claim');
    assertEq(provider.getCredential(Lender), uint32(vm.getBlockTimestamp()), 'credential');
    vm.prank(Lender);
    targetMarket.depositUpTo(1e18);
  }
}
