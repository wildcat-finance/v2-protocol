// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

import '../BaseMarketTest.sol';
import 'src/HooksFactoryRevolving.sol';
import 'src/market/WildcatMarketRevolving.sol';
import { PeriodicTermHooks, PendingAprChange, HookedMarket as PeriodicHookedMarket } from 'src/access/PeriodicTermHooks.sol';

enum MatrixHooksKind {
  OpenTerm,
  FixedTerm,
  PeriodicTerm
}

enum MatrixMarketKind {
  Standard,
  Revolving
}

/// @dev One cell of the hooks x market configuration matrix.
///
///      Protocol fees are intentionally not configurable in v1 of the harness:
///      templates are registered with zero fees so the interest oracle in the
///      scenarios stays closed-form. Delinquency parameters are configured but
///      the lifecycle scenarios keep markets collateralized, asserting
///      `!isDelinquent` before every accrual check.
struct Cell {
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
  // Revolving only
  uint16 commitmentFeeBips;
  // FixedTerm only: term ends at deployment time + fixedTermDuration
  uint32 fixedTermDuration;
  // PeriodicTerm only: first window opens at deployment time + firstWindowDelay
  uint32 firstWindowDelay;
  uint32 periodDuration;
  uint32 withdrawalWindowDuration;
}

struct DeployedCell {
  Cell cell;
  WildcatMarket market;
  address hooksInstance;
  address hooksTemplate;
  uint256 deployedAt;
}

/// @dev Base fixture for integration tests over the hooks x market matrix.
///
///      Extends the unit-test environment (arch controller, standard hooks
///      factory, SphereX mock engine) with a revolving factory and a uniform
///      `deployCell` that can stand up any {Open,Fixed,Periodic} x
///      {Standard,Revolving} combination with production-like access control
///      (deposits require credentials, withdrawals use the known-lender path).
contract MarketConfigMatrix is BaseMarketTest {
  using MathUtils for uint256;
  using SafeCastLib for uint256;

  uint256 internal constant DUST = 1e4;

  HooksFactoryRevolving internal revolvingFactory;
  address internal periodicHooksTemplate;
  address internal revolvingMarketInitCodeStorage;
  uint256 internal revolvingMarketInitCodeHash;

  // template address => registered on revolving factory
  mapping(address => bool) internal _registeredOnRevolving;
  // template address => registered on standard factory
  mapping(address => bool) internal _registeredOnStandard;

  function setUp() public virtual override {
    // Deliberately does not call super.setUp(): the base class deploys a
    // single open-term market, while each matrix test deploys its own cell.
    asset = new MockERC20('Token', 'TKN', 18);
    parameters.asset = address(asset);

    asset.mint(alice, type(uint128).max);
    asset.mint(bob, type(uint128).max);
    asset.mint(borrower, type(uint128).max);

    startPrank(address(this));
    if (!archController.isRegisteredBorrower(borrower)) {
      archController.registerBorrower(borrower);
    }
    stopPrank();

    _deployRevolvingFactory();
    periodicHooksTemplate = LibStoredInitCode.deployInitCode(type(PeriodicTermHooks).creationCode);
  }

  // ========================================================================== //
  //                              Cell construction                             //
  // ========================================================================== //

  /// @dev Baseline cell: 10% APR, 20% reserve ratio, 1 day batches. Fixed term
  ///      of 60 days; periodic windows of 7 days every 30 days, first window
  ///      opening 30 days after deployment; 2% commitment fee on revolving.
  function defaultCell(
    MatrixHooksKind hooksKind,
    MatrixMarketKind marketKind
  ) internal pure returns (Cell memory) {
    return
      Cell({
        hooksKind: hooksKind,
        marketKind: marketKind,
        maxTotalSupply: 1_000_000e18,
        annualInterestBips: 1_000,
        reserveRatioBips: 2_000,
        delinquencyFeeBips: 1_000,
        delinquencyGracePeriod: 1 days,
        withdrawalBatchDuration: 1 days,
        minimumDeposit: 0,
        transfersDisabled: false,
        commitmentFeeBips: 200,
        fixedTermDuration: 60 days,
        firstWindowDelay: 30 days,
        periodDuration: 30 days,
        withdrawalWindowDuration: 7 days
      });
  }

  function deployCell(Cell memory cell) internal returns (DeployedCell memory deployed) {
    deployed.cell = cell;
    deployed.deployedAt = block.timestamp;
    deployed.hooksTemplate = _templateFor(cell.hooksKind);
    _registerTemplate(deployed.hooksTemplate, cell.marketKind);

    startPrank(borrower);
    address instance = _factoryFor(cell.marketKind).deployHooksInstance(deployed.hooksTemplate, '');
    deployed.hooksInstance = instance;

    // Enable the template's full flag set (its own optional and required
    // flags), mirroring production deployments: deposits and transfers are
    // credential-gated, withdrawals use the known-lender path.
    HooksDeploymentConfig deploymentConfig = IHooks(instance).config();
    HooksConfig hooksConfig = deploymentConfig
      .optionalFlags()
      .setHooksAddress(instance)
      .mergeAllFlags(deploymentConfig.requiredFlags());

    DeployMarketInputs memory inputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: 'Wildcat ',
      symbolPrefix: 'wc',
      maxTotalSupply: cell.maxTotalSupply,
      annualInterestBips: cell.annualInterestBips,
      delinquencyFeeBips: cell.delinquencyFeeBips,
      withdrawalBatchDuration: cell.withdrawalBatchDuration,
      reserveRatioBips: cell.reserveRatioBips,
      delinquencyGracePeriod: cell.delinquencyGracePeriod,
      hooks: hooksConfig
    });
    bytes memory hooksData = _hooksDataFor(cell);

    if (cell.marketKind == MatrixMarketKind.Standard) {
      deployed.market = WildcatMarket(
        hooksFactory.deployMarket(inputs, hooksData, _nextSalt(borrower), address(0), 0)
      );
    } else {
      deployed.market = WildcatMarket(
        revolvingFactory.deployMarket(
          inputs,
          hooksData,
          abi.encode(uint8(1), cell.commitmentFeeBips),
          _nextSalt(borrower),
          address(0),
          0
        )
      );
    }

    BaseAccessControls(instance).addRoleProvider(
      address(ecdsaRoleProvider),
      type(uint32).max
    );
    stopPrank();

    // Credential both lenders through an explicit provider.
    _grantHookRole(instance, alice);
    _grantHookRole(instance, bob);

    _approveMarket(alice, address(deployed.market));
    _approveMarket(bob, address(deployed.market));
    _approveMarket(borrower, address(deployed.market));
  }

  function _grantHookRole(address hooksInstance, address account) internal {
    vm.prank(address(ecdsaRoleProvider));
    BaseAccessControls(hooksInstance).grantRole(account, uint32(block.timestamp));
  }

  function _templateFor(MatrixHooksKind kind) internal view returns (address) {
    if (kind == MatrixHooksKind.OpenTerm) return hooksTemplate;
    if (kind == MatrixHooksKind.FixedTerm) return fixedTermHooksTemplate;
    return periodicHooksTemplate;
  }

  function _factoryFor(MatrixMarketKind kind) internal view returns (IHooksFactory) {
    return
      kind == MatrixMarketKind.Standard
        ? IHooksFactory(address(hooksFactory))
        : IHooksFactory(address(revolvingFactory));
  }

  function _hooksDataFor(Cell memory cell) internal view returns (bytes memory) {
    if (cell.hooksKind == MatrixHooksKind.OpenTerm) {
      return abi.encode(cell.minimumDeposit, cell.transfersDisabled);
    }
    if (cell.hooksKind == MatrixHooksKind.FixedTerm) {
      return
        abi.encode(
          uint32(block.timestamp + cell.fixedTermDuration),
          cell.minimumDeposit,
          cell.transfersDisabled,
          true, // allowClosureBeforeTerm
          true // allowTermReduction
        );
    }
    // Note: PeriodicTermHooks stores the minimum as uint96 and checks the
    // downcast at deployment.
    return
      abi.encode(
        uint32(block.timestamp + cell.firstWindowDelay),
        cell.periodDuration,
        cell.withdrawalWindowDuration,
        cell.minimumDeposit,
        cell.transfersDisabled
      );
  }

  function _registerTemplate(address template, MatrixMarketKind marketKind) internal asSelf {
    if (marketKind == MatrixMarketKind.Standard) {
      if (!_registeredOnStandard[template] && !hooksFactory.isHooksTemplate(template)) {
        hooksFactory.addHooksTemplate(template, 'template', address(0), address(0), 0, 0);
      }
      _registeredOnStandard[template] = true;
    } else {
      if (!_registeredOnRevolving[template] && !revolvingFactory.isHooksTemplate(template)) {
        revolvingFactory.addHooksTemplate(template, 'template', address(0), address(0), 0, 0);
      }
      _registeredOnRevolving[template] = true;
    }
  }

  function _deployRevolvingFactory() internal asSelf {
    bytes memory initCode = type(WildcatMarketRevolving).creationCode;
    revolvingMarketInitCodeHash = uint256(keccak256(initCode));
    revolvingMarketInitCodeStorage = LibStoredInitCode.deployInitCode(initCode);
    revolvingFactory = new HooksFactoryRevolving(
      address(archController),
      address(sanctionsSentinel),
      address(wrapperFactory),
      revolvingMarketInitCodeStorage,
      revolvingMarketInitCodeHash,
      address(borrowerIdentityRegistry)
    );
    archController.registerControllerFactory(address(revolvingFactory));
    revolvingFactory.registerWithArchController();
  }

  function _approveMarket(address account, address marketAddress) internal asAccount(account) {
    asset.approve(marketAddress, type(uint256).max);
  }

  // ========================================================================== //
  //                                Actor actions                               //
  // ========================================================================== //

  function _depositAs(
    DeployedCell memory d,
    address lender,
    uint256 amount
  ) internal asAccount(lender) {
    d.market.depositUpTo(amount);
  }

  function _borrowAs(DeployedCell memory d, uint256 amount) internal asAccount(borrower) {
    d.market.borrow(amount);
  }

  function _repayAs(DeployedCell memory d, uint256 amount) internal asAccount(borrower) {
    d.market.repay(amount);
  }

  function _queueFullWithdrawalAs(
    DeployedCell memory d,
    address lender
  ) internal asAccount(lender) returns (uint32 expiry) {
    expiry = d.market.queueFullWithdrawal();
  }

  function _queueWithdrawalAs(
    DeployedCell memory d,
    address lender,
    uint256 amount
  ) internal asAccount(lender) returns (uint32 expiry) {
    expiry = d.market.queueWithdrawal(amount);
  }

  function _executeWithdrawalAs(
    DeployedCell memory d,
    address lender,
    uint32 expiry
  ) internal returns (uint256 amountWithdrawn) {
    return d.market.executeWithdrawal(lender, expiry);
  }

  function _closeMarketAs(DeployedCell memory d) internal asAccount(borrower) {
    d.market.closeMarket();
  }

  // ========================================================================== //
  //                                Time helpers                                //
  // ========================================================================== //

  function fastForward(uint256 duration) internal {
    vm.warp(block.timestamp + duration);
  }

  /// @dev Warp to the start of the next periodic withdrawal window (no-op for
  ///      other hook kinds if the market is open for withdrawals already).
  function _warpToNextWithdrawalWindow(DeployedCell memory d) internal {
    PeriodicTermHooks pth = PeriodicTermHooks(d.hooksInstance);
    if (pth.isWithdrawalWindowOpen(address(d.market))) return;
    PeriodicHookedMarket memory hooked = pth.getHookedMarket(address(d.market));
    uint256 start = hooked.firstWithdrawalWindowStart;
    if (block.timestamp >= start) {
      uint256 periodsElapsed = (block.timestamp - start) / hooked.periodDuration;
      start += (periodsElapsed + 1) * hooked.periodDuration;
    }
    vm.warp(start);
    assertTrue(pth.isWithdrawalWindowOpen(address(d.market)), 'window should be open after warp');
  }

  /// @dev Seconds until withdrawals may first be queued for this cell; zero
  ///      if the gate is already open.
  function _timeUntilWithdrawalsOpen(DeployedCell memory d) internal view returns (uint256) {
    if (d.cell.hooksKind == MatrixHooksKind.FixedTerm) {
      uint256 termEnd = d.deployedAt + d.cell.fixedTermDuration;
      return termEnd > block.timestamp ? termEnd - block.timestamp : 0;
    }
    if (d.cell.hooksKind == MatrixHooksKind.PeriodicTerm) {
      PeriodicTermHooks pth = PeriodicTermHooks(d.hooksInstance);
      if (pth.isWithdrawalWindowOpen(address(d.market))) return 0;
      PeriodicHookedMarket memory hooked = pth.getHookedMarket(address(d.market));
      uint256 start = hooked.firstWithdrawalWindowStart;
      if (block.timestamp >= start) {
        uint256 periodsElapsed = (block.timestamp - start) / hooked.periodDuration;
        start += (periodsElapsed + 1) * hooked.periodDuration;
      }
      return start - block.timestamp;
    }
    return 0;
  }

  /// @dev Warp to the first time withdrawals may be queued for this cell.
  function _warpToWithdrawalsOpen(DeployedCell memory d) internal {
    if (d.cell.hooksKind == MatrixHooksKind.FixedTerm) {
      uint256 termEnd = d.deployedAt + d.cell.fixedTermDuration;
      if (block.timestamp < termEnd) vm.warp(termEnd);
    } else if (d.cell.hooksKind == MatrixHooksKind.PeriodicTerm) {
      _warpToNextWithdrawalWindow(d);
    }
  }

  // ========================================================================== //
  //                               Interest oracle                              //
  // ========================================================================== //

  /// @dev Closed-form expected scale factor for a single accrual from the
  ///      market's current state to `timestamp`, including delinquency
  ///      penalties. Only valid when no pending withdrawal batch expires
  ///      inside the interval and protocol fees are zero (as configured by
  ///      this harness).
  function _expectedScaleFactorAt(
    DeployedCell memory d,
    uint256 timestamp
  ) internal view returns (uint256 expectedScaleFactor) {
    MarketState memory state = d.market.previousState();
    require(
      state.pendingWithdrawalExpiry == 0 || state.pendingWithdrawalExpiry >= timestamp,
      'oracle: batch expires within interval'
    );
    uint256 timeDelta = timestamp - state.lastInterestAccruedTimestamp;
    uint256 baseInterestRay = _expectedBaseInterestRay(d, state, timeDelta);
    uint256 delinquencyFeeRay = MathUtils.calculateLinearInterestFromBips(
      d.cell.delinquencyFeeBips,
      _expectedPenaltyTime(d, state, timeDelta)
    );
    return uint256(state.scaleFactor).rayMul(RAY + baseInterestRay + delinquencyFeeRay);
  }

  /// @dev Mirror of `FeeMath.updateTimeDelinquentAndGetPenaltyTime`: while the
  ///      market is delinquent, penalty time is the part of the interval spent
  ///      past the grace period; while healthy, previously accumulated
  ///      delinquency decays and still charges for the portion that remains
  ///      beyond the grace period.
  function _expectedPenaltyTime(
    DeployedCell memory d,
    MarketState memory state,
    uint256 timeDelta
  ) internal pure returns (uint256 timeWithPenalty) {
    uint256 previousTimeDelinquent = state.timeDelinquent;
    uint256 gracePeriod = d.cell.delinquencyGracePeriod;
    if (state.isDelinquent) {
      return timeDelta.satSub(gracePeriod.satSub(previousTimeDelinquent));
    }
    return MathUtils.min(previousTimeDelinquent.satSub(gracePeriod), timeDelta);
  }

  function _expectedBaseInterestRay(
    DeployedCell memory d,
    MarketState memory state,
    uint256 timeDelta
  ) internal view returns (uint256 baseInterestRay) {
    if (d.cell.marketKind == MatrixMarketKind.Standard) {
      return MathUtils.calculateLinearInterestFromBips(state.annualInterestBips, timeDelta);
    }
    // Revolving: commitment fee on the full supply plus APR on the drawn
    // portion; no accrual on closed or empty markets.
    if (timeDelta == 0 || state.scaledTotalSupply == 0 || state.isClosed) return 0;
    baseInterestRay = MathUtils.calculateLinearInterestFromBips(
      d.cell.commitmentFeeBips,
      timeDelta
    );
    uint256 drawn = IWildcatMarketRevolving(address(d.market)).drawnAmount();
    if (state.annualInterestBips > 0 && drawn > 0) {
      uint256 annualInterestRay = MathUtils.calculateLinearInterestFromBips(
        state.annualInterestBips,
        timeDelta
      );
      uint256 totalSupply = state.totalSupply();
      uint256 drawnClamped = MathUtils.min(drawn, totalSupply);
      baseInterestRay += MathUtils.mulDiv(annualInterestRay, drawnClamped, totalSupply);
    }
  }

  /// @dev Warp forward, poke the market, and assert the resulting scale factor
  ///      matches the closed-form oracle exactly.
  function _accrueAndCheck(DeployedCell memory d, uint256 duration) internal {
    uint256 target = block.timestamp + duration;
    uint256 expected = _expectedScaleFactorAt(d, target);
    vm.warp(target);
    d.market.updateState();
    assertEq(uint256(d.market.scaleFactor()), expected, 'scaleFactor vs oracle');
  }
}
