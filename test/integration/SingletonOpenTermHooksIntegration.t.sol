// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'test/shared/Test.sol';
import 'src/access/BaseAccessControls.sol';
import 'src/access/ProviderStructs.sol';
import 'src/access/SingletonOpenTermHooks.sol';
import 'src/interfaces/WildcatStructsAndEnums.sol';
import 'src/libraries/LibStoredInitCode.sol';
import 'src/providers/ISingletonRoleProviderFactory.sol';
import 'src/providers/SingletonRoleProviderFactory.sol';
import 'src/types/HooksConfig.sol';
import 'src/market/WildcatMarket.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

contract SingletonOpenTermHooksIntegrationTest is Test {
  address internal constant Lender = address(0x1EAD);

  SingletonRoleProviderFactory internal providerFactory;
  MockERC20 internal asset;
  address internal singletonTemplate;

  function setUp() external {
    providerFactory = new SingletonRoleProviderFactory();
    asset = new MockERC20('Singleton Asset', 'SINGLE', 6);
    singletonTemplate = LibStoredInitCode.deployInitCode(type(SingletonOpenTermHooks).creationCode);
    hooksFactory.addHooksTemplate(
      singletonTemplate,
      'SingletonOpenTermHooks',
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
      salt: bytes32('singleton')
    });
    NameAndProviderInputs memory accessControlInputs;
    accessControlInputs.name = 'one lender';
    accessControlInputs.roleProviderFactory = address(providerFactory);
    accessControlInputs.newProviderInputs = new CreateProviderInputs[](1);
    accessControlInputs.newProviderInputs[0] = CreateProviderInputs({
      timeToLive: 0,
      providerFactoryCalldata: abi.encode(providerInputs)
    });
    return abi.encode(
      SingletonOpenTermHooksInputs({
        accessControlInputs: accessControlInputs,
        lender: Lender
      })
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

  function test_deployMarketAndHooksDeploysSealedSingletonHooksForDirectBorrower() external {
    bytes memory constructorArgs = _constructorArgs();
    uint256 deploymentNonce = hooksFactory.getHooksInstanceDeploymentNonce(address(this));
    address expectedHooks = getNextInstanceAddress(singletonTemplate, address(this), constructorArgs);
    bytes32 marketSalt = bytes32(uint256(uint160(address(this))) << 96 | uint256(7));
    address expectedMarket = hooksFactory.computeMarketAddress(marketSalt);
    DeployMarketInputs memory inputs = _marketInputs(true, true);

    (address market, address hooksInstance) = hooksFactory.deployMarketAndHooks(
      singletonTemplate,
      constructorArgs,
      inputs,
      abi.encode(uint128(0), true),
      marketSalt,
      address(0),
      0
    );

    SingletonOpenTermHooks hooks = SingletonOpenTermHooks(hooksInstance);
    assertEq(deploymentNonce, 0, 'initial nonce');
    assertEq(hooksInstance, expectedHooks, 'hooks address');
    assertEq(market, expectedMarket, 'market address');
    assertEq(hooks.administrator(), address(this), 'borrower remains administrator');
    assertTrue(hooks.roleProviderConfigurationSealed(), 'provider configuration sealed');
    assertEq(hooks.getPushProviders().length, 0, 'no push providers');
    assertEq(hooks.getPullProviders().length, 1, 'one pull provider');
  }

  function test_deployMarketAndHooksRejectsMissingDepositAccess() external {
    vm.expectRevert(SingletonOpenTermHooks.DepositAccessRequired.selector);
    hooksFactory.deployMarketAndHooks(
      singletonTemplate,
      _constructorArgs(),
      _marketInputs(false, true),
      abi.encode(uint128(0), true),
      bytes32(uint256(uint160(address(this))) << 96 | uint256(8)),
      address(0),
      0
    );
  }

  function test_deployMarketAndHooksRejectsMissingTransferHook() external {
    vm.expectRevert(SingletonOpenTermHooks.TransferHookRequired.selector);
    hooksFactory.deployMarketAndHooks(
      singletonTemplate,
      _constructorArgs(),
      _marketInputs(true, false),
      abi.encode(uint128(0), true),
      bytes32(uint256(uint160(address(this))) << 96 | uint256(9)),
      address(0),
      0
    );
  }

  function test_deployMarketAndHooksRejectsEnabledMarketTokenTransfers() external {
    vm.expectRevert(SingletonOpenTermHooks.MarketTokenTransfersMustBeDisabled.selector);
    hooksFactory.deployMarketAndHooks(
      singletonTemplate,
      _constructorArgs(),
      _marketInputs(true, true),
      abi.encode(uint128(0), false),
      bytes32(uint256(uint160(address(this))) << 96 | uint256(10)),
      address(0),
      0
    );
  }

  function test_onlyTheConfiguredLenderCanAcquireThePosition() external {
    bytes32 marketSalt = bytes32(uint256(uint160(address(this))) << 96 | uint256(11));
    (address marketAddress,) = hooksFactory.deployMarketAndHooks(
      singletonTemplate,
      _constructorArgs(),
      _marketInputs(true, true),
      abi.encode(uint128(0), true),
      marketSalt,
      address(0),
      0
    );
    WildcatMarket market = WildcatMarket(marketAddress);
    asset.mint(Lender, 2e6);
    asset.mint(address(0xB0B), 2e6);

    vm.startPrank(Lender);
    asset.approve(address(market), 2e6);
    market.deposit(1e6);
    vm.expectRevert();
    market.transfer(address(0xB0B), 1);
    market.approve(address(this), 1);
    vm.stopPrank();

    vm.expectRevert();
    market.transferFrom(Lender, address(0xB0B), 1);

    vm.startPrank(address(0xB0B));
    asset.approve(address(market), 2e6);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.deposit(1e6);
    vm.stopPrank();
  }
}
