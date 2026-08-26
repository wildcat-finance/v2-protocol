// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'test/shared/Test.sol';
import 'src/access/BaseAccessControls.sol';
import { FixedTermHooks, HookedMarket as FixedTermHookedMarket } from 'src/access/FixedTermHooks.sol';
import 'src/access/ProviderStructs.sol';
import 'src/access/SingletonFixedTermHooks.sol';
import 'src/interfaces/WildcatStructsAndEnums.sol';
import 'src/libraries/LibStoredInitCode.sol';
import 'src/providers/ISingletonRoleProviderFactory.sol';
import 'src/providers/SingletonRoleProviderFactory.sol';
import 'src/types/HooksConfig.sol';
import 'src/market/WildcatMarket.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { MockRoleProvider } from 'test/shared/mocks/MockRoleProvider.sol';

contract SingletonFixedTermHooksIntegrationTest is Test {
  address internal constant Lender = address(0x1EAD);
  address internal constant Other = address(0xB0B);
  uint32 internal constant TermDuration = 30 days;

  SingletonRoleProviderFactory internal providerFactory;
  MockERC20 internal asset;
  address internal singletonTemplate;

  function setUp() external {
    providerFactory = new SingletonRoleProviderFactory();
    asset = new MockERC20('Singleton Asset', 'SINGLE', 6);
    singletonTemplate = LibStoredInitCode.deployInitCode(type(SingletonFixedTermHooks).creationCode);
    hooksFactory.addHooksTemplate(
      singletonTemplate,
      'SingletonFixedTermHooks',
      address(0),
      address(0),
      0,
      0
    );
    archController.registerBorrower(address(this));
  }

  function _constructorArgs() internal view returns (bytes memory) {
    SingletonRoleProviderFactoryInputs memory providerInputs = SingletonRoleProviderFactoryInputs({
      lender: Lender,
      salt: bytes32('singleton-fixed')
    });
    NameAndProviderInputs memory accessControlInputs;
    accessControlInputs.name = 'one fixed-term lender';
    accessControlInputs.roleProviderFactory = address(providerFactory);
    accessControlInputs.newProviderInputs = new CreateProviderInputs[](1);
    accessControlInputs.newProviderInputs[0] = CreateProviderInputs({
      timeToLive: 0,
      providerFactoryCalldata: abi.encode(providerInputs)
    });
    return
      abi.encode(
        SingletonFixedTermHooksInputs({ accessControlInputs: accessControlInputs, lender: Lender })
      );
  }

  function _marketInputs(
    bool useOnDeposit,
    bool useOnTransfer
  ) internal view returns (DeployMarketInputs memory inputs) {
    inputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: 'Wildcat ',
      symbolPrefix: 'WC',
      maxTotalSupply: 1_000_000e6,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 0,
      withdrawalBatchDuration: 1 days,
      reserveRatioBips: 1_000,
      delinquencyGracePeriod: 1 days,
      hooks: encodeHooksConfig({
        hooksAddress: address(0),
        useOnDeposit: useOnDeposit,
        useOnQueueWithdrawal: false,
        useOnExecuteWithdrawal: false,
        useOnTransfer: useOnTransfer,
        useOnBorrow: false,
        useOnRepay: false,
        useOnCloseMarket: false,
        useOnNukeFromOrbit: false,
        useOnSetMaxTotalSupply: false,
        useOnSetAnnualInterestAndReserveRatioBips: false,
        useOnSetProtocolFeeBips: false
      })
    });
  }

  function _hooksData(
    bool transfersDisabled,
    bool allowClosureBeforeTerm,
    bool allowTermReduction
  ) internal view returns (bytes memory) {
    return
      abi.encode(
        uint32(block.timestamp + TermDuration),
        uint128(0),
        transfersDisabled,
        allowClosureBeforeTerm,
        allowTermReduction
      );
  }

  function _deployMarket(
    uint256 saltNonce,
    bool transfersDisabled
  ) internal returns (WildcatMarket market, SingletonFixedTermHooks hooks) {
    bytes32 marketSalt = bytes32((uint256(uint160(address(this))) << 96) | saltNonce);
    (address marketAddress, address hooksAddress) = hooksFactory.deployMarketAndHooks(
      singletonTemplate,
      _constructorArgs(),
      _marketInputs(true, true),
      _hooksData(transfersDisabled, false, false),
      marketSalt,
      address(0),
      0
    );
    market = WildcatMarket(marketAddress);
    hooks = SingletonFixedTermHooks(hooksAddress);
  }

  function test_deployMarketAndHooksCreatesSealedFixedTermSingleton() external {
    bytes memory constructorArgs = _constructorArgs();
    uint256 deploymentNonce = hooksFactory.getHooksInstanceDeploymentNonce(address(this));
    address expectedHooks = getNextInstanceAddress(
      singletonTemplate,
      address(this),
      constructorArgs
    );
    bytes32 marketSalt = bytes32((uint256(uint160(address(this))) << 96) | uint256(1));
    address expectedMarket = hooksFactory.computeMarketAddress(marketSalt);

    (WildcatMarket market, SingletonFixedTermHooks hooks) = _deployMarket(1, false);
    FixedTermHookedMarket memory hookedMarket = hooks.getHookedMarket(address(market));

    assertEq(deploymentNonce, 0, 'initial nonce');
    assertEq(address(hooks), expectedHooks, 'hooks address');
    assertEq(address(market), expectedMarket, 'market address');
    assertEq(hooks.administrator(), address(this), 'borrower remains administrator');
    assertTrue(hooks.roleProviderConfigurationSealed(), 'provider configuration sealed');
    assertEq(hooks.getPushProviders().length, 0, 'no push providers');
    assertEq(hooks.getPullProviders().length, 1, 'one pull provider');
    assertTrue(hookedMarket.depositRequiresAccess, 'deposit access');
    assertTrue(hookedMarket.transferRequiresAccess, 'transfer access');
    assertFalse(hookedMarket.withdrawalRequiresAccess, 'withdrawal access is not required');
    assertFalse(hookedMarket.allowClosureBeforeTerm, 'no early closure');
    assertFalse(hookedMarket.allowTermReduction, 'no term reduction');
  }

  function test_deployMarketAndHooksRejectsUnsafePolicy() external {
    bytes32 salt = bytes32((uint256(uint160(address(this))) << 96) | uint256(2));

    vm.expectRevert(SingletonFixedTermHooks.DepositAccessRequired.selector);
    hooksFactory.deployMarketAndHooks(
      singletonTemplate,
      _constructorArgs(),
      _marketInputs(false, true),
      _hooksData(false, false, false),
      salt,
      address(0),
      0
    );

    vm.expectRevert(SingletonFixedTermHooks.TransferHookRequired.selector);
    hooksFactory.deployMarketAndHooks(
      singletonTemplate,
      _constructorArgs(),
      _marketInputs(true, false),
      _hooksData(false, false, false),
      salt,
      address(0),
      0
    );

    vm.expectRevert(SingletonFixedTermHooks.InvalidMarketHooksData.selector);
    hooksFactory.deployMarketAndHooks(
      singletonTemplate,
      _constructorArgs(),
      _marketInputs(true, true),
      abi.encode(uint32(block.timestamp + TermDuration)),
      salt,
      address(0),
      0
    );

    vm.expectRevert(SingletonFixedTermHooks.ClosureBeforeTermNotAllowed.selector);
    hooksFactory.deployMarketAndHooks(
      singletonTemplate,
      _constructorArgs(),
      _marketInputs(true, true),
      _hooksData(false, true, false),
      salt,
      address(0),
      0
    );

    vm.expectRevert(SingletonFixedTermHooks.TermReductionNotAllowed.selector);
    hooksFactory.deployMarketAndHooks(
      singletonTemplate,
      _constructorArgs(),
      _marketInputs(true, true),
      _hooksData(false, false, true),
      salt,
      address(0),
      0
    );
  }

  function test_onlyTheConfiguredLenderCanDepositOrReceiveMarketTokens() external {
    (WildcatMarket market,) = _deployMarket(3, false);
    asset.mint(Lender, 2e6);
    asset.mint(Other, 2e6);

    vm.startPrank(Lender);
    asset.approve(address(market), 2e6);
    market.deposit(1e6);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.transfer(Other, 1);
    market.approve(address(this), 1);
    vm.stopPrank();

    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.transferFrom(Lender, Other, 1);

    vm.startPrank(Other);
    asset.approve(address(market), 2e6);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.deposit(1e6);
    vm.stopPrank();
  }

  function test_canonicalWrapperCanReceiveAndReturnSingletonPosition() external {
    (WildcatMarket market,) = _deployMarket(4, false);
    Wildcat4626Wrapper wrapper = Wildcat4626Wrapper(wrapperFactory.createWrapper(address(market)));
    asset.mint(Lender, 1e6);

    vm.startPrank(Lender);
    asset.approve(address(market), 1e6);
    market.deposit(1e6);
    market.approve(address(wrapper), 1e6);

    uint256 shares = wrapper.deposit(1e6, Lender);
    assertEq(shares, 1e6, 'wrapper shares');
    assertEq(market.balanceOf(address(wrapper)), 1e6, 'wrapper market balance');

    uint256 assets = wrapper.redeem(shares, Lender, Lender);
    assertEq(assets, 1e6, 'redeemed assets');
    assertEq(market.balanceOf(Lender), 1e6, 'returned lender balance');
    vm.stopPrank();
  }

  function test_fixedTermPolicyCannotChangeBeforeMaturity() external {
    (WildcatMarket market, SingletonFixedTermHooks hooks) = _deployMarket(5, false);

    vm.expectRevert(FixedTermHooks.ClosureDisabledBeforeTerm.selector);
    market.closeMarket();

    vm.expectRevert(FixedTermHooks.TermReductionDisabled.selector);
    hooks.setFixedTermEndTime(address(market), uint32(block.timestamp));

    vm.expectRevert(SingletonFixedTermHooks.RateOrReserveRatioChangeBeforeTermEnd.selector);
    market.setAnnualInterestAndReserveRatioBips(1_001, 1_000);

    vm.expectRevert(SingletonFixedTermHooks.RateOrReserveRatioChangeBeforeTermEnd.selector);
    market.setAnnualInterestAndReserveRatioBips(1_000, 999);

    vm.warp(block.timestamp + TermDuration);
    market.setAnnualInterestAndReserveRatioBips(1_001, 999);
    assertEq(market.annualInterestBips(), 1_001, 'rate changes after term');
    assertEq(market.reserveRatioBips(), 1_000, 'base hook preserves reserve ratio');
  }

  function test_providerMutationsRemainLocked() external {
    (, SingletonFixedTermHooks hooks) = _deployMarket(6, false);
    MockRoleProvider otherProvider = new MockRoleProvider();

    vm.expectRevert(BaseAccessControls.RoleProviderConfigurationAlreadySealed.selector);
    hooks.createRoleProvider(address(providerFactory), 0, abi.encode(Lender, bytes32('new')));

    vm.expectRevert(BaseAccessControls.RoleProviderConfigurationAlreadySealed.selector);
    hooks.addRoleProvider(address(otherProvider), 0);

    address provider = hooks.getPullProviders()[0].providerAddress();
    vm.expectRevert(BaseAccessControls.RoleProviderConfigurationAlreadySealed.selector);
    hooks.removeRoleProvider(provider);
  }
}
