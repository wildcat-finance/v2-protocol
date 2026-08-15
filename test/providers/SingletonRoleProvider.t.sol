// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/access/BaseAccessControls.sol';
import 'src/access/OpenTermHooks.sol';
import 'src/access/ProviderStructs.sol';
import 'src/access/SingletonOpenTermHooks.sol';
import 'src/providers/AccessListRoleProviderFactory.sol';
import 'src/providers/ISingletonRoleProviderFactory.sol';
import 'src/providers/SingletonRoleProvider.sol';
import 'src/providers/SingletonRoleProviderFactory.sol';
import 'src/types/RoleProvider.sol';
import 'test/shared/mocks/MockRoleProvider.sol';

contract SingletonRoleProviderCaller {
  function createRoleProvider(
    SingletonRoleProviderFactory factory,
    bytes calldata data
  ) external returns (address provider) {
    provider = factory.createRoleProvider(data);
  }
}

contract SingletonRoleProviderTest is Test {
  address internal constant Lender = address(0x1EAD);
  address internal constant Other = address(0xB0B);

  SingletonRoleProviderFactory internal factory;

  function setUp() external {
    vm.warp(1_714_737_030);
    factory = new SingletonRoleProviderFactory();
  }

  function _inputs(
    address lender,
    bytes32 salt
  ) internal pure returns (SingletonRoleProviderFactoryInputs memory inputs) {
    inputs = SingletonRoleProviderFactoryInputs({ lender: lender, salt: salt });
  }

  function _singletonHookInputs(
    address lender,
    bytes32 salt
  ) internal view returns (SingletonOpenTermHooksInputs memory inputs) {
    inputs.lender = lender;
    inputs.accessControlInputs.name = 'Single lender';
    inputs.accessControlInputs.roleProviderFactory = address(factory);
    inputs.accessControlInputs.newProviderInputs = new CreateProviderInputs[](1);
    inputs.accessControlInputs.newProviderInputs[0] = CreateProviderInputs({
      timeToLive: 0,
      providerFactoryCalldata: abi.encode(_inputs(lender, salt))
    });
  }

  function test_providerOnlyCredentialsItsLender() external {
    SingletonRoleProvider provider = new SingletonRoleProvider(Lender);

    assertTrue(provider.isPullProvider(), 'pull provider');
    assertEq(provider.lender(), Lender, 'lender');
    assertEq(provider.getCredential(Lender), uint32(block.timestamp), 'lender credential');
    assertEq(provider.getCredential(Other), 0, 'other credential');
    assertEq(provider.validateCredential(Other, ''), 0, 'other validated credential');
  }

  function test_zeroLenderReverts() external {
    vm.expectRevert(SingletonRoleProvider.InvalidLender.selector);
    new SingletonRoleProvider(address(0));
  }

  function test_factoryDeploysAtPredictedAddress() external {
    SingletonRoleProviderFactoryInputs memory inputs = _inputs(Lender, bytes32('singleton'));
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address provider = factory.createSingletonRoleProvider(inputs);

    assertEq(provider, expected, 'predicted provider');
    assertEq(SingletonRoleProvider(provider).lender(), Lender, 'provider lender');
  }

  function test_factoryNamespacesSaltsByCaller() external {
    SingletonRoleProviderFactoryInputs memory inputs = _inputs(Lender, bytes32('shared'));
    SingletonRoleProviderCaller caller = new SingletonRoleProviderCaller();

    address first = factory.createRoleProvider(abi.encode(inputs));
    address second = caller.createRoleProvider(factory, abi.encode(inputs));

    assertNotEq(first, second, 'distinct callers');
    assertEq(second, factory.computeRoleProviderAddress(address(caller), inputs), 'caller prediction');
  }

  function test_singletonHooksSealTheProviderConfiguration() external {
    SingletonOpenTermHooksInputs memory inputs = _singletonHookInputs(Lender, bytes32('hook'));
    SingletonOpenTermHooks hooks = new SingletonOpenTermHooks(
      address(this),
      abi.encode(inputs)
    );
    address expectedProvider = factory.computeRoleProviderAddress(address(hooks), _inputs(Lender, bytes32('hook')));
    RoleProvider[] memory pullProviders = hooks.getPullProviders();

    assertTrue(hooks.roleProviderConfigurationSealed(), 'provider configuration sealed');
    assertEq(pullProviders.length, 1, 'pull provider count');
    assertEq(pullProviders[0].providerAddress(), expectedProvider, 'singleton provider');
    assertEq(SingletonRoleProvider(expectedProvider).lender(), Lender, 'singleton lender');
    assertEq(hooks.version(), 'SingletonOpenTermHooks', 'version');
  }

  function test_singletonHooksRejectProviderMutations() external {
    SingletonOpenTermHooks hooks = new SingletonOpenTermHooks(
      address(this),
      abi.encode(_singletonHookInputs(Lender, bytes32('locked')))
    );
    MockRoleProvider otherProvider = new MockRoleProvider();
    address singletonProvider = factory.computeRoleProviderAddress(
      address(hooks),
      _inputs(Lender, bytes32('locked'))
    );

    vm.expectRevert(BaseAccessControls.RoleProviderConfigurationAlreadySealed.selector);
    hooks.createRoleProvider(address(factory), 0, abi.encode(_inputs(Other, bytes32('new'))));

    vm.expectRevert(BaseAccessControls.RoleProviderConfigurationAlreadySealed.selector);
    hooks.addRoleProvider(address(otherProvider), 0);

    vm.expectRevert(BaseAccessControls.RoleProviderConfigurationAlreadySealed.selector);
    hooks.removeRoleProvider(singletonProvider);
  }

  function test_singletonHooksRejectNonSingletonFactory() external {
    SingletonOpenTermHooksInputs memory inputs = _singletonHookInputs(Lender, bytes32('factory'));
    inputs.accessControlInputs.roleProviderFactory = address(new AccessListRoleProviderFactory());

    vm.expectRevert();
    new SingletonOpenTermHooks(address(this), abi.encode(inputs));
  }

  function test_singletonHooksRejectNonzeroTtl() external {
    SingletonOpenTermHooksInputs memory inputs = _singletonHookInputs(Lender, bytes32('ttl'));
    inputs.accessControlInputs.newProviderInputs[0].timeToLive = 1;

    vm.expectRevert(SingletonOpenTermHooks.InvalidSingletonProviderInputs.selector);
    new SingletonOpenTermHooks(address(this), abi.encode(inputs));
  }
}
