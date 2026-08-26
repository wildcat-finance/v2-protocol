// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IHooks } from 'src/access/IHooks.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { WildcatBorrowerIdentityRegistry } from 'src/WildcatBorrowerIdentityRegistry.sol';
import { MarketParameters } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { WildcatMarketRevolving } from 'src/market/WildcatMarketRevolving.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
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
    uint32 fixedTermEndTime;
    bool transfersDisabled;
    bool revolving;
    uint16 commitmentFeeBips;
  }

  struct Fixture {
    WildcatMarket market;
    MockERC20 asset;
    IHooks hooks;
    WildcatArchController archController;
    WildcatBorrowerIdentityRegistry registry;
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
    options.commitmentFeeBips = 500;
  }

  function _defaultRevolvingOptions(
    HooksKind hooksKind
  ) internal pure returns (Options memory options) {
    options = _defaultOptions(hooksKind);
    options.revolving = true;
  }

  function _packString(string memory value) private pure returns (bytes32 word0, bytes32 word1) {
    require(bytes(value).length <= 63, 'fixture string too long');
    assembly ('memory-safe') {
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
    uint32 fixedTermEndTime = options.fixedTermEndTime;
    if (fixedTermEndTime == 0) fixedTermEndTime = uint32(vm.getBlockTimestamp());
    return
      abi.encode(fixedTermEndTime, options.minimumDeposit, options.transfersDisabled, true, true);
  }

  function _deployFixtureDependencies() private returns (Fixture memory fixture) {
    fixture.archController = WildcatArchController(
      _deployCode('src/WildcatArchController.sol:WildcatArchController')
    );
    fixture.registry = WildcatBorrowerIdentityRegistry(
      _deployCode(
        'src/WildcatBorrowerIdentityRegistry.sol:WildcatBorrowerIdentityRegistry',
        abi.encode(address(fixture.archController))
      )
    );
    fixture.archController.registerBorrower(Borrower);
    fixture.sentinel = HookDispatchSentinelMock(
      _deployCode('test/mocks/HookDispatchMocks.sol:HookDispatchSentinelMock')
    );
    fixture.factory = HookDispatchFactoryMock(
      _deployCode('test/mocks/HookDispatchMocks.sol:HookDispatchFactoryMock')
    );
    fixture.asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode('Token', 'TKN', uint8(18))
      )
    );
  }

  function _buildMarketParameters(
    Fixture memory fixture,
    Options memory options,
    HooksConfig marketHooks
  ) internal pure returns (MarketParameters memory parameters) {
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
    HooksConfig expectedHooks,
    bytes memory hooksData
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
      hooksData
    );
    assertEq(
      HooksConfig.unwrap(configuredHooks),
      HooksConfig.unwrap(expectedHooks),
      'fixture hooks config'
    );
  }

  function _deployMarketFromParameters(
    Fixture memory fixture,
    MarketParameters memory parameters
  ) internal returns (WildcatMarket deployedMarket) {
    return _deployMarketFromParameters(fixture, parameters, false);
  }

  function _deployMarketFromParameters(
    Fixture memory fixture,
    MarketParameters memory parameters,
    bool revolving
  ) internal returns (WildcatMarket deployedMarket) {
    fixture.factory.setMarketParameters(parameters);
    return _deployStoredMarket(fixture, revolving);
  }

  function _deployStoredMarket(
    Fixture memory fixture
  ) internal returns (WildcatMarket deployedMarket) {
    return _deployStoredMarket(fixture, false);
  }

  function _deployStoredMarket(
    Fixture memory fixture,
    bool revolving
  ) internal returns (WildcatMarket deployedMarket) {
    string memory artifact = revolving
      ? 'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving'
      : 'src/market/WildcatMarket.sol:WildcatMarket';
    deployedMarket = WildcatMarket(fixture.factory.deployMarket(vm.getCode(artifact)));
  }

  function _newMarket(Options memory options) internal returns (Fixture memory fixture) {
    return _newMarket(options, _deployHooks(options.hooksKind));
  }

  function _newMarket(
    Options memory options,
    IHooks hooks
  ) internal returns (Fixture memory fixture) {
    return _newMarket(options, hooks, _hookData(options));
  }

  function _newMarket(
    Options memory options,
    IHooks hooks,
    bytes memory hooksData
  ) internal returns (Fixture memory fixture) {
    fixture = _deployFixtureDependencies();
    fixture.hooks = hooks;
    fixture.factory.setRevolvingMarketCommitmentFeeResponse(options.commitmentFeeBips, 32, false);

    HooksConfig requestedHooks = options.requestedHooks.setHooksAddress(address(fixture.hooks));
    HooksConfig marketHooks = requestedHooks.mergeFlags(fixture.hooks.config());
    fixture.market = _deployMarketFromParameters(
      fixture,
      _buildMarketParameters(fixture, options, marketHooks),
      options.revolving
    );
    _configureHooks(fixture, options, requestedHooks, marketHooks, hooksData);
  }

  function _newMarket(HooksKind hooksKind) internal returns (Fixture memory fixture) {
    return _newMarket(_defaultOptions(hooksKind));
  }

  function _newRevolvingMarket(HooksKind hooksKind) internal returns (Fixture memory fixture) {
    return _newMarket(_defaultRevolvingOptions(hooksKind));
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
