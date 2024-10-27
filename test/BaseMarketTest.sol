// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

import './shared/Test.sol';
import './helpers/VmUtils.sol';
import './helpers/ExpectedStateTracker.sol';

contract BaseMarketTest is Test, ExpectedStateTracker {
  using stdStorage for StdStorage;
  using FeeMath for MarketState;
  using SafeCastLib for uint256;

  MockERC20 internal asset;

  address internal wildcatController = address(0x69);
  address internal wlUser = address(0x42);
  address internal nonwlUser = address(0x43);

  function setUp() public virtual {
    setUpContracts(false);
  }

  function setUpContracts(bool authorizeAll) internal {
    MarketInputParameters memory inputs = parameters;
    if (address(hooks) == address(0)) {
      deployHooksInstance(inputs, authorizeAll);
    }

    inputs.asset = address(asset = new MockERC20('Token', 'TKN', 18));
    deployMarket(inputs);
    parameters = inputs;
    hooks = AccessControlHooks(parameters.hooksConfig.hooksAddress());
    _authorizeLender(alice);
    previousState = MarketState({
      isClosed: false,
      maxTotalSupply: inputs.maxTotalSupply,
      scaledTotalSupply: 0,
      isDelinquent: false,
      timeDelinquent: 0,
      reserveRatioBips: inputs.reserveRatioBips,
      annualInterestBips: inputs.annualInterestBips,
      protocolFeeBips: inputs.protocolFeeBips,
      scaleFactor: uint112(RAY),
      lastInterestAccruedTimestamp: uint32(block.timestamp),
      scaledPendingWithdrawals: 0,
      pendingWithdrawalExpiry: 0,
      normalizedUnclaimedWithdrawals: 0,
      accruedProtocolFees: 0
    });
    lastTotalAssets = 0;

    asset.mint(alice, type(uint128).max);
    asset.mint(bob, type(uint128).max);

    _approve(alice, address(market), type(uint256).max);
    _approve(bob, address(market), type(uint256).max);
  }

  function resetWithMockHooks() internal asSelf {
    parameters.hooksTemplate = LibStoredInitCode.deployInitCode(type(MockHooks).creationCode);
    hooksFactory.addHooksTemplate(
      parameters.hooksTemplate,
      'MockHooks',
      address(0),
      address(0),
      0,
      0
    );
    hooks = AccessControlHooks(address(0));
    parameters.deployHooksConstructorArgs = abi.encode(address(this), '');
    parameters.hooksConfig = EmptyHooksConfig;
    setUpContracts(false);
  }

  function _authorizeLender(address account) internal asAccount(parameters.borrower) {
    vm.expectEmit(address(hooks));
    emit BaseAccessControls.AccountAccessGranted(
      parameters.borrower,
      account,
      uint32(block.timestamp)
    );
    hooks.grantRole(account, uint32(block.timestamp));
  }

  function _deauthorizeLender(address account) internal asAccount(parameters.borrower) {
    vm.expectEmit(address(hooks));
    emit BaseAccessControls.AccountAccessRevoked(account);
    hooks.revokeRole(account);
  }

  function _blockLender(address account) internal asAccount(parameters.borrower) {
    vm.expectEmit(address(hooks));
    emit BaseAccessControls.AccountBlockedFromDeposits(account);
    hooks.blockFromDeposits(account);
  }

  function _depositBorrowWithdraw(
    address from,
    uint256 depositAmount,
    uint256 borrowAmount,
    uint256 withdrawalAmount
  ) internal asAccount(from) {
    _deposit(from, depositAmount);
    // Borrow 80% of market assets
    _borrow(borrowAmount);
    // Withdraw 100% of deposits
    _requestWithdrawal(from, withdrawalAmount);
  }

  function _deposit(
    address from,
    uint256 amount,
    bool preAuthorizeLender
  ) internal asAccount(from) returns (uint256) {
    if (preAuthorizeLender) _authorizeLender(from);
    MarketState memory state = pendingState();
    (uint256 currentScaledBalance, uint256 currentBalance) = _getBalance(state, from);
    asset.mint(from, amount);
    asset.approve(address(market), amount);
    (uint104 scaledAmount, uint256 expectedNormalizedAmount) = _trackDeposit(state, from, amount);
    uint256 actualNormalizedAmount = market.depositUpTo(amount);
    assertEq(actualNormalizedAmount, expectedNormalizedAmount, 'Actual amount deposited');
    _checkState(state);
    assertEq(
      market.balanceOf(from),
      currentBalance + state.normalizeAmount(scaledAmount),
      'Resulting balance != old balance + normalize(scale(deposit))'
    );
    assertApproxEqAbs(
      market.balanceOf(from),
      currentBalance + amount,
      1,
      'Resulting balance not within 1 wei of old balance + amount deposited'
    );
    assertEq(
      market.scaledBalanceOf(from),
      currentScaledBalance + scaledAmount,
      'Resulting scaled balance'
    );
    return actualNormalizedAmount;
  }

  function _deposit(address from, uint256 amount) internal returns (uint256) {
    return _deposit(from, amount, true);
  }

  function _requestWithdrawal(
    address from,
    uint256 amount
  ) internal asAccount(from) returns (uint32 expiry) {
    MarketState memory state = pendingState();
    (uint256 currentScaledBalance, uint256 currentBalance) = _getBalance(state, from);
    uint104 scaledAmount;
    (expiry, scaledAmount) = _trackQueueWithdrawal(state, from, amount);
    market.queueWithdrawal(amount);
    _checkState(state);
    assertApproxEqAbs(
      market.balanceOf(from),
      currentBalance - amount,
      1,
      unicode'balance after withdrawal (± 1)'
    );
    assertEq(
      market.balanceOf(from),
      state.normalizeAmount(currentScaledBalance - scaledAmount),
      'balance after withdrawal (exact)'
    );
    assertEq(
      market.scaledBalanceOf(from),
      currentScaledBalance - scaledAmount,
      'scaledBalance after withdrawal'
    );
  }

  function _requestFullWithdrawal(address from) internal asAccount(from) {
    MarketState memory state = pendingState();
    (uint256 currentScaledBalance, uint256 currentBalance) = _getBalance(state, from);
    (, uint104 scaledAmount) = _trackQueueWithdrawal(state, from, currentBalance);
    market.queueFullWithdrawal();
    _checkState(state);
    assertEq(market.balanceOf(from), 0, 'balance after withdrawal (exact)');
    assertEq(market.scaledBalanceOf(from), 0, 'scaledBalance after withdrawal');
  }

  function _closeMarket() internal asAccount(borrower) {
    uint owed = market.totalDebts() - market.totalAssets();
    asset.mint(borrower, owed);
    asset.approve(address(market), owed);
    MarketState memory state = pendingState();
    _trackCloseMarket(state, true);
    market.closeMarket();
    _checkState(state);
  }

  function _borrow(uint256 amount) internal asAccount(borrower) {
    MarketState memory state = pendingState();

    _trackBorrow(amount);
    market.borrow(amount);
    _checkState(state);
  }

  function _approve(address from, address to, uint256 amount) internal asAccount(from) {
    asset.approve(to, amount);
  }

  // function applyFuzzedHooksConfig(MarketHooksConfigFuzzInputs memory inputs) internal {
  //   inputs.minimumDeposit = uint128(bound(inputs.minimumDeposit, 0, parameters.maxTotalSupply));
  //   if (inputs.isAccessControlHooks) {
  //     inputs.allowClosureBeforeTerm = false;
  //     inputs.allowTermReduction = false;
  //     inputs.fixedTermDuration = 0;
  //   } else {
  //     inputs.fixedTermDuration = uint16(bound(inputs.fixedTermDuration, 1, type(uint16).max));
  //   }

  //   parameters.minimumDeposit = inputs.minimumDeposit;
  //   parameters.transfersDisabled = inputs.transfersDisabled;
  //   parameters.allowForceBuyBack = inputs.allowForceBuyBacks;
  //   parameters.fixedTermEndTime = inputs.isAccessControlHooks
  //     ? 0
  //     : uint32(inputs.fixedTermDuration + block.timestamp);
  //   parameters.allowClosureBeforeTerm = inputs.allowClosureBeforeTerm;
  //   parameters.allowTermReduction = inputs.allowTermReduction;

  //   parameters.hooksConfig = encodeHooksConfig({
  //     hooksAddress: address(hooks),
  //     useOnDeposit: inputs.useOnDeposit,
  //     useOnQueueWithdrawal: inputs.useOnQueueWithdrawal,
  //     useOnExecuteWithdrawal: false,
  //     useOnTransfer: inputs.useOnTransfer,
  //     useOnBorrow: false,
  //     useOnRepay: false,
  //     useOnCloseMarket: false,
  //     useOnNukeFromOrbit: false,
  //     useOnSetMaxTotalSupply: false,
  //     useOnSetAnnualInterestAndReserveRatioBips: true,
  //     useOnSetProtocolFeeBips: false
  //   });
  //   resetWithNewHooks(inputs.isAccessControlHooks ? HooksKind.AccessControl : HooksKind.FixedTerm);
  // }

  function applyFuzzedHooksConfig(MarketHooksConfigFuzzInputs memory inputs) internal {
    inputs.minimumDeposit = uint128(bound(inputs.minimumDeposit, 0, parameters.maxTotalSupply));
    if (inputs.isAccessControlHooks) {
      inputs.allowClosureBeforeTerm = false;
      inputs.allowTermReduction = false;
      inputs.fixedTermDuration = 0;
    } else {
      inputs.fixedTermDuration = uint16(bound(inputs.fixedTermDuration, 1, type(uint16).max));
    }

    // parameters.hooksTemplate = inputs.isAccessControlHooks ? hooksTemplate : fixedTermHooksTemplate;
    // parameters.deployMarketHooksData = '';
    parameters.minimumDeposit = inputs.minimumDeposit;
    parameters.transfersDisabled = inputs.transfersDisabled;
    parameters.allowForceBuyBack = inputs.allowForceBuyBacks;
    parameters.fixedTermEndTime = inputs.isAccessControlHooks
      ? 0
      : uint32(inputs.fixedTermDuration + block.timestamp);
    parameters.allowClosureBeforeTerm = inputs.allowClosureBeforeTerm;
    parameters.allowTermReduction = inputs.allowTermReduction;

    // hooks = AccessControlHooks(address(0));

    parameters.hooksConfig = encodeHooksConfig({
      hooksAddress: address(0),
      useOnDeposit: inputs.useOnDeposit,
      useOnQueueWithdrawal: inputs.useOnQueueWithdrawal,
      useOnExecuteWithdrawal: false,
      useOnTransfer: inputs.useOnTransfer,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
      useOnNukeFromOrbit: false,
      useOnSetMaxTotalSupply: false,
      useOnSetAnnualInterestAndReserveRatioBips: true,
      useOnSetProtocolFeeBips: false
    });
    // setUpContracts(false);
    resetWithNewHooks(inputs.isAccessControlHooks ? HooksKind.AccessControl : HooksKind.FixedTerm);
  }

  function resetWithNewHooks(HooksKind kind) internal {
    if (kind == HooksKind.AccessControl) {
      parameters.hooksTemplate = hooksTemplate;
    } else if (kind == HooksKind.FixedTerm) {
      parameters.hooksTemplate = fixedTermHooksTemplate;
    }
    parameters.deployMarketHooksData = '';
    hooks = AccessControlHooks(address(0));
    parameters.hooksConfig = parameters.hooksConfig.setHooksAddress(address(0));
    setUpContracts(false);
  }
}
