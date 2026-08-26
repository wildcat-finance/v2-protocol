// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { HooksFactory } from 'src/HooksFactory.sol';
import { HooksFactoryRevolving } from 'src/HooksFactoryRevolving.sol';
import { IHooksFactory } from 'src/IHooksFactory.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { WildcatBorrowerIdentityRegistry } from 'src/WildcatBorrowerIdentityRegistry.sol';
import { WildcatSanctionsSentinel } from 'src/WildcatSanctionsSentinel.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { IWildcatMarketRevolving } from 'src/interfaces/IWildcatMarketRevolving.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { MathUtils, RAY } from 'src/libraries/MathUtils.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { Wildcat4626WrapperFactory } from 'src/vault/Wildcat4626WrapperFactory.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { SanctionsListMock } from '../mocks/SanctionsMocks.sol';
import { TestKernel } from './TestKernel.sol';

abstract contract ProductionMatrixFixture is TestKernel {
  using MathUtils for uint256;

  enum MatrixHooksKind {
    OpenTerm,
    FixedTerm,
    PeriodicTerm
  }

  enum MatrixMarketKind {
    Standard,
    Revolving
  }

  struct MatrixOptions {
    MatrixHooksKind hooksKind;
    MatrixMarketKind marketKind;
    uint128 maxTotalSupply;
    uint16 annualInterestBips;
    uint16 reserveRatioBips;
    uint16 delinquencyFeeBips;
    uint32 delinquencyGracePeriod;
    uint32 withdrawalBatchDuration;
    uint128 minimumDeposit;
    bool transfersDisabled;
    uint16 commitmentFeeBips;
    uint32 fixedTermDuration;
    uint32 firstWindowDelay;
    uint32 periodDuration;
    uint32 withdrawalWindowDuration;
  }

  struct ProductionStack {
    WildcatArchController archController;
    WildcatBorrowerIdentityRegistry registry;
    WildcatSanctionsSentinel sentinel;
    SanctionsListMock sanctionsList;
    Wildcat4626WrapperFactory wrapperFactory;
    HooksFactory standardFactory;
    HooksFactoryRevolving revolvingFactory;
    MockERC20 asset;
    MockRoleProvider roleProvider;
    address[3] hooksTemplates;
  }

  struct MatrixCell {
    MatrixOptions options;
    WildcatMarket market;
    BaseAccessControls hooks;
    address hooksTemplate;
    address operationalBorrower;
    address borrowerPrincipal;
    uint256 deployedAt;
  }

  address internal constant MatrixBorrower = address(0xB04405E4);
  address internal constant MatrixAlice = address(0xA11CE);
  address internal constant MatrixBob = address(0xB0B);
  address internal constant MatrixCaller = address(0xCA11E2);
  uint256 internal constant MatrixDust = 1e4;

  function _storeInitCode(
    string memory artifact
  ) internal returns (address storageContract, uint256 initCodeHash) {
    bytes memory initCode = vm.getCode(artifact);
    storageContract = LibStoredInitCode.deployInitCode(initCode);
    initCodeHash = uint256(keccak256(initCode));
  }

  function _deployProductionStack() internal returns (ProductionStack memory stack) {
    stack.archController = WildcatArchController(
      _deployCode('src/WildcatArchController.sol:WildcatArchController')
    );
    stack.registry = WildcatBorrowerIdentityRegistry(
      _deployCode(
        'src/WildcatBorrowerIdentityRegistry.sol:WildcatBorrowerIdentityRegistry',
        abi.encode(address(stack.archController))
      )
    );
    stack.sanctionsList = SanctionsListMock(
      _deployCode('test/mocks/SanctionsMocks.sol:SanctionsListMock')
    );
    stack.sentinel = WildcatSanctionsSentinel(
      _deployCode(
        'src/WildcatSanctionsSentinel.sol:WildcatSanctionsSentinel',
        abi.encode(address(stack.archController), address(stack.sanctionsList))
      )
    );
    stack.wrapperFactory = Wildcat4626WrapperFactory(
      _deployCode(
        'src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory',
        abi.encode(address(stack.archController), address(0))
      )
    );
    stack.asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode('Matrix Token', 'MTRX', uint8(18))
      )
    );
    stack.roleProvider = MockRoleProvider(
      _deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider')
    );

    stack.archController.registerBorrower(MatrixBorrower);
    stack.standardFactory = _deployStandardFactory(stack);
    stack.revolvingFactory = _deployRevolvingFactory(stack);
    _deployAndRegisterTemplates(stack);
  }

  function _deployStandardFactory(
    ProductionStack memory stack
  ) private returns (HooksFactory factory) {
    (address marketStorage, uint256 marketHash) = _storeInitCode(
      'src/market/WildcatMarket.sol:WildcatMarket'
    );
    factory = HooksFactory(
      _deployCode(
        'src/HooksFactory.sol:HooksFactory',
        abi.encode(
          address(stack.archController),
          address(stack.sentinel),
          address(stack.wrapperFactory),
          marketStorage,
          marketHash,
          address(stack.registry)
        )
      )
    );
    stack.archController.registerControllerFactory(address(factory));
    factory.registerWithArchController();
  }

  function _deployRevolvingFactory(
    ProductionStack memory stack
  ) private returns (HooksFactoryRevolving factory) {
    (address marketStorage, uint256 marketHash) = _storeInitCode(
      'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving'
    );
    factory = HooksFactoryRevolving(
      _deployCode(
        'src/HooksFactoryRevolving.sol:HooksFactoryRevolving',
        abi.encode(
          address(stack.archController),
          address(stack.sentinel),
          address(stack.wrapperFactory),
          marketStorage,
          marketHash,
          address(stack.registry)
        )
      )
    );
    stack.archController.registerControllerFactory(address(factory));
    factory.registerWithArchController();
  }

  function _deployAndRegisterTemplates(ProductionStack memory stack) private {
    stack.hooksTemplates[uint256(MatrixHooksKind.OpenTerm)] = LibStoredInitCode.deployInitCode(
      vm.getCode('src/access/OpenTermHooks.sol:OpenTermHooks')
    );
    stack.hooksTemplates[uint256(MatrixHooksKind.FixedTerm)] = LibStoredInitCode.deployInitCode(
      vm.getCode('src/access/FixedTermHooks.sol:FixedTermHooks')
    );
    stack.hooksTemplates[uint256(MatrixHooksKind.PeriodicTerm)] = LibStoredInitCode.deployInitCode(
      vm.getCode('src/access/PeriodicTermHooks.sol:PeriodicTermHooks')
    );

    for (uint256 i; i < stack.hooksTemplates.length; i++) {
      string memory name = i == uint256(MatrixHooksKind.OpenTerm)
        ? 'Open Term'
        : i == uint256(MatrixHooksKind.FixedTerm)
        ? 'Fixed Term'
        : 'Periodic Term';
      stack.standardFactory.addHooksTemplate(
        stack.hooksTemplates[i],
        name,
        address(0),
        address(0),
        0,
        0
      );
      stack.revolvingFactory.addHooksTemplate(
        stack.hooksTemplates[i],
        name,
        address(0),
        address(0),
        0,
        0
      );
    }
  }

  function _defaultMatrixOptions(
    MatrixHooksKind hooksKind,
    MatrixMarketKind marketKind
  ) internal pure returns (MatrixOptions memory options) {
    options.hooksKind = hooksKind;
    options.marketKind = marketKind;
    options.maxTotalSupply = 1_000_000e18;
    options.annualInterestBips = 1_000;
    options.reserveRatioBips = 2_000;
    options.delinquencyFeeBips = 1_000;
    options.delinquencyGracePeriod = 1 days;
    options.withdrawalBatchDuration = 1 days;
    options.commitmentFeeBips = 200;
    options.fixedTermDuration = 60 days;
    options.firstWindowDelay = 30 days;
    options.periodDuration = 30 days;
    options.withdrawalWindowDuration = 7 days;
  }

  function _factoryFor(
    ProductionStack memory stack,
    MatrixMarketKind kind
  ) internal pure returns (IHooksFactory factory) {
    factory = IHooksFactory(
      kind == MatrixMarketKind.Standard
        ? address(stack.standardFactory)
        : address(stack.revolvingFactory)
    );
  }

  function _marketSalt(address deployer, uint96 nonce) internal pure returns (bytes32) {
    return bytes32((uint256(uint160(deployer)) << 96) | uint256(nonce));
  }

  function _hooksData(
    MatrixOptions memory options,
    uint256 deployedAt
  ) internal pure returns (bytes memory) {
    if (options.hooksKind == MatrixHooksKind.OpenTerm) {
      return abi.encode(options.minimumDeposit, options.transfersDisabled);
    }
    if (options.hooksKind == MatrixHooksKind.FixedTerm) {
      return
        abi.encode(
          uint32(deployedAt + options.fixedTermDuration),
          options.minimumDeposit,
          options.transfersDisabled,
          true,
          true
        );
    }
    return
      abi.encode(
        uint32(deployedAt + options.firstWindowDelay),
        options.periodDuration,
        options.withdrawalWindowDuration,
        options.minimumDeposit,
        options.transfersDisabled
      );
  }

  function _marketInputs(
    ProductionStack memory stack,
    MatrixOptions memory options,
    HooksConfig hooks
  ) internal pure returns (DeployMarketInputs memory inputs) {
    inputs.asset = address(stack.asset);
    inputs.namePrefix = 'Wildcat ';
    inputs.symbolPrefix = 'wc';
    inputs.maxTotalSupply = options.maxTotalSupply;
    inputs.annualInterestBips = options.annualInterestBips;
    inputs.delinquencyFeeBips = options.delinquencyFeeBips;
    inputs.withdrawalBatchDuration = options.withdrawalBatchDuration;
    inputs.reserveRatioBips = options.reserveRatioBips;
    inputs.delinquencyGracePeriod = options.delinquencyGracePeriod;
    inputs.hooks = hooks;
  }

  function _deployMatrixCell(
    ProductionStack memory stack,
    MatrixOptions memory options,
    address operationalBorrower,
    address borrowerPrincipal,
    uint96 nonce
  ) internal returns (MatrixCell memory cell) {
    cell.options = options;
    cell.operationalBorrower = operationalBorrower;
    cell.borrowerPrincipal = borrowerPrincipal;
    cell.deployedAt = vm.getBlockTimestamp();
    cell.hooksTemplate = stack.hooksTemplates[uint256(options.hooksKind)];
    IHooksFactory factory = _factoryFor(stack, options.marketKind);

    vm.prank(operationalBorrower);
    cell.hooks = BaseAccessControls(factory.deployHooksInstance(cell.hooksTemplate, ''));

    HooksDeploymentConfig deploymentConfig = IHooks(address(cell.hooks)).config();
    HooksConfig requestedHooks = deploymentConfig
      .optionalFlags()
      .setHooksAddress(address(cell.hooks))
      .mergeAllFlags(deploymentConfig.requiredFlags());
    DeployMarketInputs memory inputs = _marketInputs(stack, options, requestedHooks);
    bytes memory hooksData = _hooksData(options, cell.deployedAt);
    bytes32 salt = _marketSalt(operationalBorrower, nonce);

    vm.prank(operationalBorrower);
    if (options.marketKind == MatrixMarketKind.Standard) {
      cell.market = WildcatMarket(
        stack.standardFactory.deployMarket(inputs, hooksData, salt, address(0), 0)
      );
    } else {
      cell.market = WildcatMarket(
        stack.revolvingFactory.deployMarket(
          inputs,
          hooksData,
          abi.encode(uint8(1), options.commitmentFeeBips),
          salt,
          address(0),
          0
        )
      );
    }

    vm.prank(borrowerPrincipal);
    cell.hooks.addRoleProvider(address(stack.roleProvider), type(uint32).max);
  }

  function _authorize(
    ProductionStack memory stack,
    MatrixCell memory cell,
    address account
  ) internal {
    vm.prank(address(stack.roleProvider));
    cell.hooks.grantRole(account, uint32(vm.getBlockTimestamp()));
  }

  function _fundAndApprove(
    ProductionStack memory stack,
    MatrixCell memory cell,
    address account,
    uint256 amount
  ) internal {
    stack.asset.mint(account, amount);
    vm.prank(account);
    stack.asset.approve(address(cell.market), type(uint256).max);
  }

  function _deposit(
    ProductionStack memory stack,
    MatrixCell memory cell,
    address account,
    uint256 amount
  ) internal {
    _fundAndApprove(stack, cell, account, amount);
    vm.prank(account);
    cell.market.depositUpTo(amount);
  }

  function _approveBorrower(
    ProductionStack memory stack,
    MatrixCell memory cell,
    uint256 amount
  ) internal {
    stack.asset.mint(cell.operationalBorrower, amount);
    vm.prank(cell.operationalBorrower);
    stack.asset.approve(address(cell.market), type(uint256).max);
  }

  function _borrow(MatrixCell memory cell, uint256 amount) internal {
    vm.prank(cell.operationalBorrower);
    cell.market.borrow(amount);
  }

  function _repay(MatrixCell memory cell, uint256 amount) internal {
    vm.prank(cell.operationalBorrower);
    cell.market.repay(amount);
  }

  function _close(MatrixCell memory cell) internal {
    vm.prank(cell.operationalBorrower);
    cell.market.closeMarket();
  }

  function _expectedScaleFactorAt(
    MatrixCell memory cell,
    uint256 timestamp
  ) internal view returns (uint256 expectedScaleFactor) {
    MarketState memory state = cell.market.previousState();
    require(
      state.pendingWithdrawalExpiry == 0 || state.pendingWithdrawalExpiry >= timestamp,
      'oracle crosses batch expiry'
    );
    uint256 elapsed = timestamp - state.lastInterestAccruedTimestamp;
    uint256 baseInterestRay;
    if (cell.options.marketKind == MatrixMarketKind.Standard) {
      baseInterestRay = MathUtils.calculateLinearInterestFromBips(
        state.annualInterestBips,
        elapsed
      );
    } else if (elapsed > 0 && state.scaledTotalSupply > 0 && !state.isClosed) {
      baseInterestRay = MathUtils.calculateLinearInterestFromBips(
        cell.options.commitmentFeeBips,
        elapsed
      );
      uint256 drawn = IWildcatMarketRevolving(address(cell.market)).drawnAmount();
      if (state.annualInterestBips > 0 && drawn > 0) {
        uint256 utilizationInterestRay = MathUtils.calculateLinearInterestFromBips(
          state.annualInterestBips,
          elapsed
        );
        baseInterestRay += MathUtils.mulDiv(
          utilizationInterestRay,
          MathUtils.min(drawn, state.totalSupply()),
          state.totalSupply()
        );
      }
    }
    uint256 delinquencyFeeRay = MathUtils.calculateLinearInterestFromBips(
      cell.options.delinquencyFeeBips,
      _expectedPenaltyTime(cell.options, state, elapsed)
    );
    expectedScaleFactor = uint256(state.scaleFactor).rayMul(
      RAY + baseInterestRay + delinquencyFeeRay
    );
  }

  function _expectedPenaltyTime(
    MatrixOptions memory options,
    MarketState memory state,
    uint256 elapsed
  ) private pure returns (uint256) {
    if (state.isDelinquent) {
      return
        elapsed.satSub(
          uint256(options.delinquencyGracePeriod).satSub(uint256(state.timeDelinquent))
        );
    }
    return
      MathUtils.min(uint256(state.timeDelinquent).satSub(options.delinquencyGracePeriod), elapsed);
  }

  function _accrueAndCheck(MatrixCell memory cell, uint256 elapsed) internal {
    uint256 target = vm.getBlockTimestamp() + elapsed;
    uint256 expected = _expectedScaleFactorAt(cell, target);
    vm.warp(target);
    cell.market.updateState();
    assertEq(uint256(cell.market.scaleFactor()), expected, 'matrix scale factor');
  }

  function _warpToWithdrawalAccess(MatrixCell memory cell) internal {
    if (cell.options.hooksKind == MatrixHooksKind.FixedTerm) {
      uint256 termEnd = cell.deployedAt + cell.options.fixedTermDuration;
      if (vm.getBlockTimestamp() < termEnd) vm.warp(termEnd);
    } else if (cell.options.hooksKind == MatrixHooksKind.PeriodicTerm) {
      PeriodicTermHooks hooks = PeriodicTermHooks(address(cell.hooks));
      if (hooks.isWithdrawalWindowOpen(address(cell.market))) return;
      uint256 windowStart = cell.deployedAt + cell.options.firstWindowDelay;
      if (vm.getBlockTimestamp() >= windowStart) {
        uint256 periodsElapsed = (vm.getBlockTimestamp() - windowStart) /
          cell.options.periodDuration;
        windowStart += (periodsElapsed + 1) * cell.options.periodDuration;
      }
      vm.warp(windowStart);
    }
  }

  function _templateVersion(MatrixHooksKind kind) internal pure returns (string memory) {
    if (kind == MatrixHooksKind.OpenTerm) return 'OpenTermHooks';
    if (kind == MatrixHooksKind.FixedTerm) return 'FixedTermHooks';
    return 'PeriodicTermHooks';
  }
}
