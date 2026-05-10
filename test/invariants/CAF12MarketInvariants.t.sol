// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { Test as ForgeTest } from 'forge-std/Test.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

import { HooksFactory } from 'src/HooksFactory.sol';
import { HooksFactoryRevolving } from 'src/HooksFactoryRevolving.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { MathUtils, RAY } from 'src/libraries/MathUtils.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { IWildcatMarketRevolving } from 'src/interfaces/IWildcatMarketRevolving.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { WildcatMarketRevolving } from 'src/market/WildcatMarketRevolving.sol';

import { MockHooks } from '../shared/mocks/MockHooks.sol';
import { MockSanctionsSentinel } from '../shared/mocks/MockSanctionsSentinel.sol';
import { deployMockChainalysis } from '../shared/mocks/MockChainalysis.sol';

abstract contract CAF12InvariantDeployer is ForgeTest {
  using MathUtils for uint256;

  address internal constant Borrower = address(0xB04405E4);
  address internal constant FeeRecipient = address(0xFEE);

  uint256 internal nextSalt = 1;

  function _storeMarketInitCode(
    bool revolving
  ) internal returns (address initCodeStorage, uint256 initCodeHash) {
    bytes memory marketInitCode = revolving
      ? type(WildcatMarketRevolving).creationCode
      : type(WildcatMarket).creationCode;
    initCodeHash = uint256(keccak256(marketInitCode));
    initCodeStorage = LibStoredInitCode.deployInitCode(marketInitCode);
  }

  function _deployStandardMarket()
    internal
    returns (
      WildcatMarket market,
      MockERC20 asset,
      address borrower,
      MockSanctionsSentinel sanctionsSentinel
    )
  {
    borrower = Borrower;
    deployMockChainalysis();

    WildcatArchController archController = new WildcatArchController();
    sanctionsSentinel = new MockSanctionsSentinel(address(archController));
    (address marketTemplate, uint256 marketInitCodeHash) = _storeMarketInitCode(false);

    HooksFactory hooksFactory = new HooksFactory(
      address(archController),
      address(sanctionsSentinel),
      marketTemplate,
      marketInitCodeHash
    );
    archController.registerControllerFactory(address(hooksFactory));
    hooksFactory.registerWithArchController();

    address hooksTemplate = LibStoredInitCode.deployInitCode(type(MockHooks).creationCode);
    hooksFactory.addHooksTemplate(hooksTemplate, 'caf12-mock', FeeRecipient, address(0), 0, 100);
    archController.registerBorrower(borrower);

    vm.prank(borrower);
    address hooksInstance = hooksFactory.deployHooksInstance(hooksTemplate, bytes(''));

    asset = new MockERC20('CAF12 Token', 'CAF12', 18);
    DeployMarketInputs memory params = DeployMarketInputs({
      asset: address(asset),
      namePrefix: 'Wildcat ',
      symbolPrefix: 'wc',
      maxTotalSupply: 1_000_000e18,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 1_000,
      withdrawalBatchDuration: 1 days,
      reserveRatioBips: 2_000,
      delinquencyGracePeriod: 1 days,
      hooks: EmptyHooksConfig.setHooksAddress(hooksInstance)
    });

    vm.prank(borrower);
    market = WildcatMarket(
      hooksFactory.deployMarket(params, bytes(''), bytes32(nextSalt++), address(0), 0)
    );
  }

  function _deployRevolvingMarket()
    internal
    returns (
      WildcatMarket market,
      IWildcatMarketRevolving revolvingMarket,
      MockERC20 asset,
      address borrower
    )
  {
    borrower = Borrower;
    deployMockChainalysis();

    WildcatArchController archController = new WildcatArchController();
    MockSanctionsSentinel sanctionsSentinel = new MockSanctionsSentinel(address(archController));
    (address marketTemplate, uint256 marketInitCodeHash) = _storeMarketInitCode(true);

    HooksFactoryRevolving hooksFactory = new HooksFactoryRevolving(
      address(archController),
      address(sanctionsSentinel),
      marketTemplate,
      marketInitCodeHash
    );
    archController.registerControllerFactory(address(hooksFactory));
    hooksFactory.registerWithArchController();

    address hooksTemplate = LibStoredInitCode.deployInitCode(type(MockHooks).creationCode);
    hooksFactory.addHooksTemplate(hooksTemplate, 'caf12-rcf-mock', address(0), address(0), 0, 0);
    archController.registerBorrower(borrower);

    vm.prank(borrower);
    address hooksInstance = hooksFactory.deployHooksInstance(hooksTemplate, bytes(''));

    asset = new MockERC20('CAF12 RCF Token', 'CAF12R', 18);
    DeployMarketInputs memory params = DeployMarketInputs({
      asset: address(asset),
      namePrefix: 'Wildcat ',
      symbolPrefix: 'wc',
      maxTotalSupply: 1_000_000e18,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 0,
      withdrawalBatchDuration: 1 days,
      reserveRatioBips: 2_000,
      delinquencyGracePeriod: 1 days,
      hooks: EmptyHooksConfig.setHooksAddress(hooksInstance)
    });

    vm.prank(borrower);
    address marketAddress = hooksFactory.deployMarket(
      params,
      bytes(''),
      abi.encode(uint8(1), uint16(200)),
      bytes32(nextSalt++),
      address(0),
      0
    );
    market = WildcatMarket(marketAddress);
    revolvingMarket = IWildcatMarketRevolving(marketAddress);
  }
}

contract CAF12MarketAccountingHandler is ForgeTest {
  using MathUtils for uint256;

  WildcatMarket public immutable market;
  MockERC20 public immutable asset;
  MockSanctionsSentinel public immutable sanctionsSentinel;
  address public immutable borrower;

  address[] internal actors;
  uint32[] internal expiries;
  mapping(uint32 expiry => bool trackedExpiry) internal trackedExpiries;
  mapping(address actor => bool sanctionedActor) internal sanctionedActors;

  uint256 public arithmeticPanicCount;
  uint256 public sanctionsFailureCount;
  bool public scaleFactorDecreased;
  uint256 public lastObservedScaleFactor;

  constructor(
    WildcatMarket market_,
    MockERC20 asset_,
    MockSanctionsSentinel sanctionsSentinel_,
    address borrower_
  ) {
    market = market_;
    asset = asset_;
    sanctionsSentinel = sanctionsSentinel_;
    borrower = borrower_;

    actors.push(address(0xA11CE));
    actors.push(address(0xB0B));
    actors.push(address(0xCAFE));
    actors.push(address(0xD00D));

    lastObservedScaleFactor = market.scaleFactor();
  }

  function actorCount() external view returns (uint256) {
    return actors.length;
  }

  function actorAt(uint256 index) external view returns (address) {
    return actors[index];
  }

  function expiryCount() external view returns (uint256) {
    return expiries.length;
  }

  function expiryAt(uint256 index) external view returns (uint32) {
    return expiries[index];
  }

  function deposit(uint256 actorSeed, uint256 amount) external {
    if (market.isClosed()) return;

    uint256 maxDeposit = market.maximumDeposit();
    if (maxDeposit == 0) return;

    address actor = _actor(actorSeed);
    amount = bound(amount, 1, MathUtils.min(maxDeposit, 50_000e18));

    asset.mint(actor, amount);
    vm.prank(actor);
    asset.approve(address(market), amount);

    _callAs(actor, address(market), abi.encodeCall(WildcatMarket.depositUpTo, (amount)));
    _observeScaleFactor();
  }

  function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
    address from = _actor(fromSeed);
    address to = _actor(toSeed);
    if (from == to) return;

    uint256 balance = market.balanceOf(from);
    if (balance == 0) return;

    amount = bound(amount, 1, balance);
    _callAs(from, address(market), abi.encodeWithSignature('transfer(address,uint256)', to, amount));
    _observeScaleFactor();
  }

  function borrow(uint256 amount) external {
    if (market.isClosed()) return;
    if (market.scaledTotalSupply() == 0) return;

    uint256 borrowable = market.borrowableAssets();
    if (borrowable == 0) return;

    amount = bound(amount, 1, MathUtils.min(borrowable, 50_000e18));
    (bool success, ) = _callAs(
      borrower,
      address(market),
      abi.encodeCall(WildcatMarket.borrow, (amount))
    );
    if (success && sanctionedActors[borrower]) {
      sanctionsFailureCount++;
    }
    _observeScaleFactor();
  }

  function repay(uint256 amount) external {
    if (market.isClosed()) return;

    amount = bound(amount, 1, 50_000e18);
    asset.mint(borrower, amount);
    vm.prank(borrower);
    asset.approve(address(market), amount);

    _callAs(borrower, address(market), abi.encodeCall(WildcatMarket.repay, (amount)));
    _observeScaleFactor();
  }

  function queueWithdrawal(uint256 actorSeed, uint256 amount) external {
    if (market.isClosed()) return;

    address actor = _actor(actorSeed);
    uint256 balance = market.balanceOf(actor);
    if (balance == 0) return;

    amount = bound(amount, 1, balance);
    (bool success, bytes memory result) = _callAs(
      actor,
      address(market),
      abi.encodeWithSignature('queueWithdrawal(uint256)', amount)
    );
    if (success && result.length == 32) {
      _trackExpiry(abi.decode(result, (uint32)));
    }
    _observeScaleFactor();
  }

  function queueFullWithdrawal(uint256 actorSeed) external {
    if (market.isClosed()) return;

    address actor = _actor(actorSeed);
    if (market.scaledBalanceOf(actor) == 0) return;

    (bool success, bytes memory result) = _callAs(
      actor,
      address(market),
      abi.encodeWithSignature('queueFullWithdrawal()')
    );
    if (success && result.length == 32) {
      _trackExpiry(abi.decode(result, (uint32)));
    }
    _observeScaleFactor();
  }

  function executeWithdrawal(uint256 actorSeed, uint256 expirySeed) external {
    if (expiries.length == 0) return;

    uint32 expiry = expiries[expirySeed % expiries.length];
    if (expiry >= block.timestamp) return;

    address actor = _actor(actorSeed);
    _callAs(
      actor,
      address(market),
      abi.encodeWithSignature('executeWithdrawal(address,uint32)', actor, expiry)
    );
    _observeScaleFactor();
  }

  function repayAndProcess(uint256 amount, uint256 maxBatches) external {
    if (market.isClosed()) return;

    amount = bound(amount, 0, 50_000e18);
    maxBatches = bound(maxBatches, 0, 8);

    if (amount > 0) {
      asset.mint(borrower, amount);
      vm.prank(borrower);
      asset.approve(address(market), amount);
    }

    _callAs(
      borrower,
      address(market),
      abi.encodeWithSignature(
        'repayAndProcessUnpaidWithdrawalBatches(uint256,uint256)',
        amount,
        maxBatches
      )
    );
    _observeScaleFactor();
  }

  function updateState() external {
    _callAs(borrower, address(market), abi.encodeCall(WildcatMarket.updateState, ()));
    _observeScaleFactor();
  }

  function collectFees() external {
    _callAs(borrower, address(market), abi.encodeCall(WildcatMarket.collectFees, ()));
    _observeScaleFactor();
  }

  function closeMarket() external {
    if (market.isClosed()) return;

    uint256 repayAmount = market.totalDebts();
    asset.mint(borrower, repayAmount);
    vm.prank(borrower);
    asset.approve(address(market), repayAmount);

    _callAs(borrower, address(market), abi.encodeCall(WildcatMarket.closeMarket, ()));
    _observeScaleFactor();
  }

  function sanctionLender(uint256 actorSeed) external {
    address actor = _actor(actorSeed);
    sanctionsSentinel.sanction(actor);
    sanctionedActors[actor] = true;
  }

  function sanctionBorrower() external {
    sanctionsSentinel.sanction(borrower);
    sanctionedActors[borrower] = true;
  }

  function nukeFromOrbit(uint256 actorSeed) external {
    address actor = _actor(actorSeed);
    if (!sanctionedActors[actor]) return;

    uint256 scaledBalanceBefore = market.scaledBalanceOf(actor);
    (bool success, ) = _callAs(
      actor,
      address(market),
      abi.encodeWithSignature('nukeFromOrbit(address)', actor)
    );
    if (success) {
      if (scaledBalanceBefore > 0 && market.scaledBalanceOf(actor) != 0) {
        sanctionsFailureCount++;
      }
      uint32 expiry = market.previousState().pendingWithdrawalExpiry;
      if (expiry > 0) _trackExpiry(expiry);
    }
    _observeScaleFactor();
  }

  function warp(uint256 timeDelta) external {
    timeDelta = bound(timeDelta, 1, 30 days);
    vm.warp(block.timestamp + timeDelta);
  }

  function sumActorScaledBalances() external view returns (uint256 sum) {
    for (uint256 i = 0; i < actors.length; i++) {
      sum += market.scaledBalanceOf(actors[i]);
    }
  }

  function sumTrackedScaledPendingWithdrawals() external view returns (uint256 sum) {
    for (uint256 i = 0; i < expiries.length; i++) {
      WithdrawalBatch memory batch = market.getWithdrawalBatch(expiries[i]);
      if (batch.scaledAmountBurned > batch.scaledTotalAmount) {
        return type(uint256).max;
      }
      sum += batch.scaledTotalAmount - batch.scaledAmountBurned;
    }
  }

  function sumTrackedAvailableWithdrawals() external view returns (uint256 sum) {
    for (uint256 i = 0; i < expiries.length; i++) {
      uint32 expiry = expiries[i];
      if (expiry >= block.timestamp) continue;

      for (uint256 j = 0; j < actors.length; j++) {
        try market.getAvailableWithdrawalAmount(actors[j], expiry) returns (uint256 amount) {
          sum += amount;
        } catch {}
      }
    }
  }

  function _actor(uint256 seed) internal view returns (address) {
    return actors[seed % actors.length];
  }

  function _trackExpiry(uint32 expiry) internal {
    if (expiry == 0 || trackedExpiries[expiry]) return;
    trackedExpiries[expiry] = true;
    expiries.push(expiry);
  }

  function _observeScaleFactor() internal {
    uint256 scaleFactor = market.scaleFactor();
    if (scaleFactor < lastObservedScaleFactor) {
      scaleFactorDecreased = true;
    }
    lastObservedScaleFactor = scaleFactor;
  }

  function _callAs(
    address caller,
    address target,
    bytes memory data
  ) internal returns (bool success, bytes memory result) {
    vm.prank(caller);
    (success, result) = target.call(data);
    if (!success) {
      if (_isArithmeticPanic(result)) {
        arithmeticPanicCount++;
      }
    }
  }

  function _isArithmeticPanic(bytes memory result) internal pure returns (bool isPanic) {
    if (result.length != 0x24) return false;

    bytes4 selector;
    uint256 panicCode;
    assembly {
      selector := mload(add(result, 0x20))
      panicCode := mload(add(result, 0x24))
    }
    return selector == bytes4(0x4e487b71) && panicCode == 0x11;
  }
}

contract CAF12MarketAccountingInvariant is CAF12InvariantDeployer {
  CAF12MarketAccountingHandler internal handler;
  WildcatMarket internal market;

  function setUp() public {
    MockERC20 asset;
    address borrower;
    MockSanctionsSentinel sanctionsSentinel;
    (market, asset, borrower, sanctionsSentinel) = _deployStandardMarket();
    handler = new CAF12MarketAccountingHandler(market, asset, sanctionsSentinel, borrower);

    bytes4[] memory selectors = new bytes4[](14);
    selectors[0] = CAF12MarketAccountingHandler.deposit.selector;
    selectors[1] = CAF12MarketAccountingHandler.transfer.selector;
    selectors[2] = CAF12MarketAccountingHandler.borrow.selector;
    selectors[3] = CAF12MarketAccountingHandler.repay.selector;
    selectors[4] = CAF12MarketAccountingHandler.queueWithdrawal.selector;
    selectors[5] = CAF12MarketAccountingHandler.queueFullWithdrawal.selector;
    selectors[6] = CAF12MarketAccountingHandler.executeWithdrawal.selector;
    selectors[7] = CAF12MarketAccountingHandler.repayAndProcess.selector;
    selectors[8] = CAF12MarketAccountingHandler.updateState.selector;
    selectors[9] = CAF12MarketAccountingHandler.collectFees.selector;
    selectors[10] = CAF12MarketAccountingHandler.warp.selector;
    selectors[11] = CAF12MarketAccountingHandler.sanctionLender.selector;
    selectors[12] = CAF12MarketAccountingHandler.sanctionBorrower.selector;
    selectors[13] = CAF12MarketAccountingHandler.nukeFromOrbit.selector;

    targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    targetContract(address(handler));
  }

  function invariant_scaledSupplyConservation() public view {
    MarketState memory state = market.currentState();
    uint256 actorBalances = handler.sumActorScaledBalances();
    assertEq(
      actorBalances + state.scaledPendingWithdrawals,
      state.scaledTotalSupply,
      'scaled supply conservation'
    );
  }

  function invariant_withdrawalLiabilityConservation() public view {
    MarketState memory state = market.currentState();
    assertEq(
      handler.sumTrackedScaledPendingWithdrawals(),
      state.scaledPendingWithdrawals,
      'tracked pending withdrawals'
    );
    assertLe(
      handler.sumTrackedAvailableWithdrawals(),
      state.normalizedUnclaimedWithdrawals,
      'available withdrawals exceed unclaimed pool'
    );
  }

  function invariant_scaleFactorNeverDecreases() public view {
    assertFalse(handler.scaleFactorDecreased(), 'scale factor decreased');
    assertGe(market.scaleFactor(), RAY, 'scale factor below ray');
  }

  function invariant_noArithmeticPanicInUnderwaterPaths() public view {
    assertEq(handler.arithmeticPanicCount(), 0, 'arithmetic panic');
  }

  function invariant_sanctionsStateSafety() public view {
    assertEq(handler.sanctionsFailureCount(), 0, 'sanctions failure');
  }
}

contract CAF12RevolvingDrawnAmountHandler is ForgeTest {
  using MathUtils for uint256;

  WildcatMarket public immutable market;
  IWildcatMarketRevolving public immutable revolvingMarket;
  MockERC20 public immutable asset;
  address public immutable borrower;

  uint256 public arithmeticPanicCount;
  uint256 public drawnFailureCount;
  uint256 public interestFailureCount;

  constructor(
    WildcatMarket market_,
    IWildcatMarketRevolving revolvingMarket_,
    MockERC20 asset_,
    address borrower_
  ) {
    market = market_;
    revolvingMarket = revolvingMarket_;
    asset = asset_;
    borrower = borrower_;
  }

  function deposit(uint256 amount) external {
    if (market.isClosed()) return;

    uint256 maxDeposit = market.maximumDeposit();
    if (maxDeposit == 0) return;

    amount = bound(amount, 1, MathUtils.min(maxDeposit, 50_000e18));
    asset.mint(address(this), amount);
    asset.approve(address(market), amount);

    _callAs(address(this), address(market), abi.encodeCall(WildcatMarket.depositUpTo, (amount)));
  }

  function borrow(uint256 amount) external {
    if (market.isClosed()) return;

    uint256 borrowable = market.borrowableAssets();
    if (borrowable == 0) return;

    amount = bound(amount, 1, MathUtils.min(borrowable, 50_000e18));
    uint256 drawnBefore = revolvingMarket.drawnAmount();
    (bool success, ) = _callAs(
      borrower,
      address(market),
      abi.encodeCall(WildcatMarket.borrow, (amount))
    );
    if (success && revolvingMarket.drawnAmount() != drawnBefore + amount) {
      drawnFailureCount++;
    }
  }

  function repay(uint256 amount) external {
    if (market.isClosed()) return;

    uint256 outstandingDebt = market.totalDebts().satSub(market.totalAssets());
    if (outstandingDebt == 0) return;

    amount = bound(amount, 1, MathUtils.min(outstandingDebt, 50_000e18));
    uint256 expectedDrawn = _expectedDrawnAfterRepay(amount);

    asset.mint(borrower, amount);
    vm.prank(borrower);
    asset.approve(address(market), amount);

    (bool success, ) = _callAs(
      borrower,
      address(market),
      abi.encodeCall(WildcatMarket.repay, (amount))
    );
    if (success && revolvingMarket.drawnAmount() != expectedDrawn) {
      drawnFailureCount++;
    }
  }

  function repayAndProcess(uint256 amount) external {
    if (market.isClosed()) return;

    uint256 outstandingDebt = market.totalDebts().satSub(market.totalAssets());
    if (outstandingDebt == 0) return;

    amount = bound(amount, 0, MathUtils.min(outstandingDebt, 50_000e18));
    uint256 expectedDrawn = amount == 0
      ? revolvingMarket.drawnAmount()
      : _expectedDrawnAfterRepay(amount);

    if (amount > 0) {
      asset.mint(borrower, amount);
      vm.prank(borrower);
      asset.approve(address(market), amount);
    }

    (bool success, ) = _callAs(
      borrower,
      address(market),
      abi.encodeWithSignature(
        'repayAndProcessUnpaidWithdrawalBatches(uint256,uint256)',
        amount,
        uint256(0)
      )
    );
    if (success && revolvingMarket.drawnAmount() != expectedDrawn) {
      drawnFailureCount++;
    }
  }

  function updateState() external {
    if (market.isClosed()) return;

    MarketState memory stateBefore = market.previousState();
    uint256 expectedScaleFactor = _expectedScaleFactorAfterUpdate(stateBefore);
    uint256 drawnBefore = revolvingMarket.drawnAmount();

    (bool success, ) = _callAs(
      borrower,
      address(market),
      abi.encodeCall(WildcatMarket.updateState, ())
    );
    if (success) {
      MarketState memory stateAfter = market.previousState();
      if (stateAfter.scaleFactor != expectedScaleFactor) {
        interestFailureCount++;
      }
      if (revolvingMarket.drawnAmount() != drawnBefore) {
        drawnFailureCount++;
      }
    }
  }

  function closeMarket() external {
    if (market.isClosed()) return;

    uint256 repayAmount = market.totalDebts();
    asset.mint(borrower, repayAmount);
    vm.prank(borrower);
    asset.approve(address(market), repayAmount);

    (bool success, ) = _callAs(
      borrower,
      address(market),
      abi.encodeCall(WildcatMarket.closeMarket, ())
    );
    if (success && revolvingMarket.drawnAmount() != 0) {
      drawnFailureCount++;
    }
  }

  function warp(uint256 timeDelta) external {
    timeDelta = bound(timeDelta, 1, 30 days);
    vm.warp(block.timestamp + timeDelta);
  }

  function _expectedDrawnAfterRepay(uint256 amount) internal view returns (uint256) {
    uint256 drawnBefore = revolvingMarket.drawnAmount();
    uint256 outstandingDebtBefore = market.totalDebts().satSub(market.totalAssets());
    return MathUtils.min(drawnBefore, outstandingDebtBefore.satSub(amount));
  }

  function _expectedScaleFactorAfterUpdate(
    MarketState memory state
  ) internal view returns (uint256 expectedScaleFactor) {
    expectedScaleFactor = state.scaleFactor;

    uint256 timeDelta = block.timestamp - state.lastInterestAccruedTimestamp;
    if (timeDelta == 0 || state.scaledTotalSupply == 0) return expectedScaleFactor;

    uint256 baseInterestRay = MathUtils.calculateLinearInterestFromBips(200, timeDelta);
    uint256 drawn = revolvingMarket.drawnAmount();
    if (state.annualInterestBips > 0 && drawn > 0) {
      uint256 annualInterestRay = MathUtils.calculateLinearInterestFromBips(
        state.annualInterestBips,
        timeDelta
      );
      uint256 totalSupply = state.totalSupply();
      uint256 drawnClamped = MathUtils.min(drawn, totalSupply);
      baseInterestRay += MathUtils.mulDiv(annualInterestRay, drawnClamped, totalSupply);
    }

    expectedScaleFactor += uint256(state.scaleFactor).rayMul(baseInterestRay);
  }

  function _callAs(
    address caller,
    address target,
    bytes memory data
  ) internal returns (bool success, bytes memory result) {
    vm.prank(caller);
    (success, result) = target.call(data);
    if (!success && _isArithmeticPanic(result)) {
      arithmeticPanicCount++;
    }
  }

  function _isArithmeticPanic(bytes memory result) internal pure returns (bool isPanic) {
    if (result.length != 0x24) return false;

    bytes4 selector;
    uint256 panicCode;
    assembly {
      selector := mload(add(result, 0x20))
      panicCode := mload(add(result, 0x24))
    }
    return selector == bytes4(0x4e487b71) && panicCode == 0x11;
  }
}

contract CAF12RevolvingDrawnAmountInvariant is CAF12InvariantDeployer {
  CAF12RevolvingDrawnAmountHandler internal handler;
  WildcatMarket internal market;
  IWildcatMarketRevolving internal revolvingMarket;

  function setUp() public {
    MockERC20 asset;
    address borrower;
    (market, revolvingMarket, asset, borrower) = _deployRevolvingMarket();
    handler = new CAF12RevolvingDrawnAmountHandler(market, revolvingMarket, asset, borrower);

    bytes4[] memory selectors = new bytes4[](7);
    selectors[0] = CAF12RevolvingDrawnAmountHandler.deposit.selector;
    selectors[1] = CAF12RevolvingDrawnAmountHandler.borrow.selector;
    selectors[2] = CAF12RevolvingDrawnAmountHandler.repay.selector;
    selectors[3] = CAF12RevolvingDrawnAmountHandler.repayAndProcess.selector;
    selectors[4] = CAF12RevolvingDrawnAmountHandler.updateState.selector;
    selectors[5] = CAF12RevolvingDrawnAmountHandler.warp.selector;
    selectors[6] = CAF12RevolvingDrawnAmountHandler.closeMarket.selector;

    targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    targetContract(address(handler));
  }

  function invariant_drawnAmountFollowsPrincipalRules() public view {
    assertEq(handler.drawnFailureCount(), 0, 'drawn amount rule failure');

    if (market.isClosed()) {
      assertEq(revolvingMarket.drawnAmount(), 0, 'closed market drawn amount');
    } else {
      assertLe(
        revolvingMarket.drawnAmount(),
        market.totalDebts(),
        'drawn amount exceeds total debts'
      );
    }
  }

  function invariant_utilizationInterestMatchesFormula() public view {
    assertEq(handler.interestFailureCount(), 0, 'interest formula failure');
  }

  function invariant_noArithmeticPanic() public view {
    assertEq(handler.arithmeticPanicCount(), 0, 'arithmetic panic');
  }
}
