// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IHooks } from 'src/access/IHooks.sol';
import { MarketParameters } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { HookDispatchArchControllerMock } from '../mocks/HookDispatchMocks.sol';
import { HookDispatchBorrowerRegistryMock } from '../mocks/HookDispatchMocks.sol';
import { HookDispatchFactoryMock } from '../mocks/HookDispatchMocks.sol';
import { HookDispatchSentinelMock } from '../mocks/HookDispatchMocks.sol';
import { TestKernel } from './TestKernel.sol';

abstract contract MarketFixture is TestKernel {
  enum HooksKind {
    OpenTerm,
    FixedTerm
  }

  struct Options {
    HooksKind hooksKind;
    HooksConfig requestedHooks;
    uint128 maxTotalSupply;
    uint16 protocolFeeBips;
    uint16 annualInterestBips;
    uint16 delinquencyFeeBips;
    uint32 withdrawalBatchDuration;
    uint16 reserveRatioBips;
    uint32 delinquencyGracePeriod;
    uint128 minimumDeposit;
    bool transfersDisabled;
  }

  struct Fixture {
    WildcatMarket market;
    MockERC20 asset;
    IHooks hooks;
    HookDispatchArchControllerMock archController;
    HookDispatchBorrowerRegistryMock registry;
    HookDispatchSentinelMock sentinel;
    HookDispatchFactoryMock factory;
  }

  address internal constant Borrower = address(0xB04405E4);
  address internal constant FeeRecipient = address(0xFEE);
  address internal constant WrapperFactory = address(0x4626);
  uint128 internal constant MaximumMarketSupply = type(uint104).max;

  function _defaultOptions(HooksKind hooksKind) internal pure returns (Options memory options) {
    options.hooksKind = hooksKind;
    options.maxTotalSupply = MaximumMarketSupply;
    options.protocolFeeBips = 1_000;
    options.annualInterestBips = 1_000;
    options.delinquencyFeeBips = 1_000;
    options.withdrawalBatchDuration = 1 days;
    options.reserveRatioBips = 2_000;
    options.delinquencyGracePeriod = 2_000;
  }

  function _packString(string memory value) private pure returns (bytes32 word0, bytes32 word1) {
    require(bytes(value).length <= 63, 'fixture string too long');
    assembly {
      word0 := mload(add(value, 0x1f))
      word1 := mul(mload(add(value, 0x3f)), gt(mload(value), 0x1f))
    }
  }

  function _deployHooks(HooksKind hooksKind) private returns (IHooks hooks) {
    string memory artifact = hooksKind == HooksKind.OpenTerm
      ? 'src/access/OpenTermHooks.sol:OpenTermHooks'
      : 'src/access/FixedTermHooks.sol:FixedTermHooks';
    hooks = IHooks(_deployCode(artifact, abi.encode(Borrower, bytes(''))));
  }

  function _hookData(Options memory options) private view returns (bytes memory) {
    if (options.hooksKind == HooksKind.OpenTerm) {
      return abi.encode(options.minimumDeposit, options.transfersDisabled);
    }
    return
      abi.encode(
        uint32(block.timestamp),
        options.minimumDeposit,
        options.transfersDisabled,
        true,
        true
      );
  }

  function _deployFixtureDependencies(
    HooksKind hooksKind
  ) private returns (Fixture memory fixture) {
    fixture.archController = HookDispatchArchControllerMock(
      _deployCode('test-next/mocks/HookDispatchMocks.sol:HookDispatchArchControllerMock')
    );
    fixture.registry = HookDispatchBorrowerRegistryMock(
      _deployCode(
        'test-next/mocks/HookDispatchMocks.sol:HookDispatchBorrowerRegistryMock',
        abi.encode(address(fixture.archController))
      )
    );
    fixture.sentinel = HookDispatchSentinelMock(
      _deployCode('test-next/mocks/HookDispatchMocks.sol:HookDispatchSentinelMock')
    );
    fixture.factory = HookDispatchFactoryMock(
      _deployCode('test-next/mocks/HookDispatchMocks.sol:HookDispatchFactoryMock')
    );
    fixture.asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode('Token', 'TKN', uint8(18))
      )
    );
    fixture.hooks = _deployHooks(hooksKind);
  }

  function _marketParameters(
    Fixture memory fixture,
    Options memory options,
    HooksConfig marketHooks
  ) private pure returns (MarketParameters memory parameters) {
    (parameters.packedNameWord0, parameters.packedNameWord1) = _packString('Wildcat Token');
    (parameters.packedSymbolWord0, parameters.packedSymbolWord1) = _packString('WCTKN');
    parameters.asset = address(fixture.asset);
    parameters.decimals = 18;
    parameters.borrower = Borrower;
    parameters.feeRecipient = FeeRecipient;
    parameters.sentinel = address(fixture.sentinel);
    parameters.wrapperFactory = WrapperFactory;
    parameters.maxTotalSupply = options.maxTotalSupply;
    parameters.protocolFeeBips = options.protocolFeeBips;
    parameters.annualInterestBips = options.annualInterestBips;
    parameters.delinquencyFeeBips = options.delinquencyFeeBips;
    parameters.withdrawalBatchDuration = options.withdrawalBatchDuration;
    parameters.reserveRatioBips = options.reserveRatioBips;
    parameters.delinquencyGracePeriod = options.delinquencyGracePeriod;
    parameters.archController = address(fixture.archController);
    parameters.hooks = marketHooks;
    parameters.borrowerPrincipal = Borrower;
    parameters.borrowerIdentityRegistry = address(fixture.registry);
  }

  function _deploymentInputs(
    Fixture memory fixture,
    Options memory options,
    HooksConfig requestedHooks
  ) private pure returns (DeployMarketInputs memory inputs) {
    inputs.asset = address(fixture.asset);
    inputs.namePrefix = 'Wildcat ';
    inputs.symbolPrefix = 'WC';
    inputs.maxTotalSupply = options.maxTotalSupply;
    inputs.annualInterestBips = options.annualInterestBips;
    inputs.delinquencyFeeBips = options.delinquencyFeeBips;
    inputs.withdrawalBatchDuration = options.withdrawalBatchDuration;
    inputs.reserveRatioBips = options.reserveRatioBips;
    inputs.delinquencyGracePeriod = options.delinquencyGracePeriod;
    inputs.hooks = requestedHooks;
  }

  function _configureHooks(
    Fixture memory fixture,
    Options memory options,
    HooksConfig requestedHooks,
    HooksConfig expectedHooks
  ) private {
    DeployMarketInputs memory deploymentInputs = _deploymentInputs(
      fixture,
      options,
      requestedHooks
    );
    HooksConfig configuredHooks = fixture.hooks.onCreateMarket(
      Borrower,
      address(fixture.market),
      deploymentInputs,
      _hookData(options)
    );
    assertEq(
      HooksConfig.unwrap(configuredHooks),
      HooksConfig.unwrap(expectedHooks),
      'fixture hooks config'
    );
  }

  function _newMarket(Options memory options) internal returns (Fixture memory fixture) {
    fixture = _deployFixtureDependencies(options.hooksKind);

    HooksConfig requestedHooks = options.requestedHooks.setHooksAddress(address(fixture.hooks));
    HooksConfig marketHooks = requestedHooks.mergeFlags(fixture.hooks.config());
    fixture.factory.setMarketParameters(_marketParameters(fixture, options, marketHooks));
    fixture.market = WildcatMarket(
      fixture.factory.deployMarket(vm.getCode('src/market/WildcatMarket.sol:WildcatMarket'))
    );
    _configureHooks(fixture, options, requestedHooks, marketHooks);
  }

  function _newMarket(HooksKind hooksKind) internal returns (Fixture memory fixture) {
    return _newMarket(_defaultOptions(hooksKind));
  }

  function _fundAndApprove(Fixture memory fixture, address account, uint256 amount) internal {
    fixture.asset.mint(account, amount);
    vm.prank(account);
    fixture.asset.approve(address(fixture.market), amount);
  }

  function _deposit(Fixture memory fixture, address account, uint256 amount) internal {
    _fundAndApprove(fixture, account, amount);
    vm.prank(account);
    fixture.market.deposit(amount);
  }

  function _queueAndExecuteWithdrawal(
    Fixture memory fixture,
    address account,
    uint256 amount
  ) internal returns (uint32 expiry) {
    vm.prank(account);
    expiry = fixture.market.queueWithdrawal(amount);
    vm.warp(uint256(expiry) + 1);
    fixture.market.executeWithdrawal(account, expiry);
  }
}
