// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // ZeroValueTransferReview.t
//  \ ^ /   Origination-fee transfer behavior across factories and routes.
//    V
//
//  TRANSFER REJECTION TARGET
//  constructor(...)
//  transferFrom(...)
//
//  FIXTURE
//  setUp()
//  _feeToken(...)
//  _configureFee(...)
//  deployCell(...)
//
//  ZERO FEE TRANSFERS
//  test_zeroFeeSkipsRejectingTokenAcrossFactoriesAndRoutes()
//  test_zeroFeeNullRecipientNeedsNoTransferAcrossFactoriesAndRoutes()
//  test_zeroFeeMakesNoCallEvenWhenTokenWouldAcceptTransfer()
//  test_noFeeTokenNeedsNoTransferAcrossFactoriesAndRoutes()
//
//  POSITIVE FEE TRANSFERS
//  test_positiveFeeTransfersExactlyOnceAcrossFactoriesAndRoutes()
//  test_feeMismatchPrecedesTransferAcrossFactoriesAndRoutes()
//  test_positiveFeeCannotBeBypassedWithZeroAmount()
//  test_positiveFeeStillRequiresSuccessfulTransfer()
//
//  DEPLOYMENT ASSERTIONS
//  _expectDeploymentConfig(...)
//  _assertDeployed(...)
// ═════

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { IHooksFactory, IHooksFactoryEventsAndErrors } from 'src/IHooksFactory.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { LibERC20 } from 'src/libraries/LibERC20.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { HooksConfig, HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';

// ┌─ ZeroTransferReviewToken ──────────────────────────────────────────────────
/// @dev conventional balance accounting, with configurable transfer rejection.
contract ZeroTransferReviewToken is MockERC20 {
  bool internal immutable rejectZeroAmount;
  uint256 public transferFromCalls;

  // ░░▒▒▓▓██ [ TRANSFER REJECTION TARGET ] ────────────────────────────────────

  // ┌─ constructor ─────
  constructor(bool rejectZeroAmount_) MockERC20('Review Fee Token', 'RFT', 18) {
    rejectZeroAmount = rejectZeroAmount_;
  }

  // ┌─ transferFrom ─────
  function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
    transferFromCalls++;
    require(to != address(0), 'ZERO_RECIPIENT');
    require(!rejectZeroAmount || amount != 0, 'ZERO_AMOUNT');
    return super.transferFrom(from, to, amount);
  }
}

// ┌─ ZeroValueTransferReviewTest ──────────────────────────────────────────────
/// @dev regression coverage for amount-based origination-fee transfers.
contract ZeroValueTransferReviewTest is ProductionMatrixFixture {
  ProductionStack internal stack;
  address internal constant FeeRecipient = address(0xFEE);

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    stack = _deployProductionStack();
  }

  // ┌─ _feeToken ─────
  function _feeToken(bool rejectZeroAmount) internal returns (ZeroTransferReviewToken) {
    return ZeroTransferReviewToken(
      _deployCode('test/factories/ZeroValueTransferReview.t.sol:ZeroTransferReviewToken', abi.encode(rejectZeroAmount))
    );
  }

  // ┌─ _configureFee ─────
  function _configureFee(MatrixMarketKind kind, address recipient, address token, uint80 amount) internal {
    _factoryFor(stack, kind).updateHooksTemplateFees(stack.hooksTemplates[0], recipient, token, amount, 0);
  }

  // ┌─ deployCell ─────
  /// @dev keep expectRevert on the complete deployment, not intermediate hooks construction.
  function deployCell(
    MatrixMarketKind kind,
    bool newHooks,
    address feeAsset,
    uint256 feeAmount,
    uint96 nonce
  )
    external
    returns (address market)
  {
    require(msg.sender == address(this));
    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, kind);
    IHooksFactory factory = _factoryFor(stack, kind);
    HooksConfig hooks;
    vm.startPrank(MatrixBorrower);
    if (!newHooks) {
      address instance = factory.deployHooksInstance(stack.hooksTemplates[0], '');
      HooksDeploymentConfig config = IHooks(instance).config();
      hooks = config.optionalFlags().setHooksAddress(instance).mergeAllFlags(config.requiredFlags());
    }
    DeployMarketInputs memory inputs = _marketInputs(stack, options, hooks);
    bytes memory hooksData = _hooksData(options, vm.getBlockTimestamp());
    bytes32 salt = _marketSalt(MatrixBorrower, nonce);
    if (kind == MatrixMarketKind.Standard) {
      if (newHooks) {
        (market,) =
          factory.deployMarketAndHooks(stack.hooksTemplates[0], '', inputs, hooksData, salt, feeAsset, feeAmount);
      } else {
        market = factory.deployMarket(inputs, hooksData, salt, feeAsset, feeAmount);
      }
    } else {
      bytes memory marketData = abi.encode(uint8(1), options.commitmentFeeBips);
      if (newHooks) {
        (market,) = stack.revolvingFactory
          .deployMarketAndHooks(stack.hooksTemplates[0], '', inputs, hooksData, marketData, salt, feeAsset, feeAmount);
      } else {
        market = stack.revolvingFactory.deployMarket(inputs, hooksData, marketData, salt, feeAsset, feeAmount);
      }
    }
    vm.stopPrank();
  }

  // ░░▒▒▓▓██ [ ZERO FEE TRANSFERS ] ───────────────────────────────────────────

  // ┌─ test_zeroFeeSkipsRejectingTokenAcrossFactoriesAndRoutes ─────
  function test_zeroFeeSkipsRejectingTokenAcrossFactoriesAndRoutes() external {
    ZeroTransferReviewToken token = _feeToken(true);
    for (uint256 i; i < 2; i++) {
      MatrixMarketKind kind = MatrixMarketKind(i);
      _configureFee(kind, FeeRecipient, address(token), 0);
      for (uint256 route; route < 2; route++) {
        _expectDeploymentConfig(kind, address(token), FeeRecipient, uint96(route + 1));
        _assertDeployed(this.deployCell(kind, route == 1, address(token), 0, uint96(route + 1)));
      }
    }
  }

  // ┌─ test_zeroFeeNullRecipientNeedsNoTransferAcrossFactoriesAndRoutes ─────
  function test_zeroFeeNullRecipientNeedsNoTransferAcrossFactoriesAndRoutes() external {
    ZeroTransferReviewToken token = _feeToken(false);
    for (uint256 i; i < 2; i++) {
      MatrixMarketKind kind = MatrixMarketKind(i);
      // this configuration is permitted by _validateFees.
      _configureFee(kind, address(0), address(token), 0);
      for (uint256 route; route < 2; route++) {
        _expectDeploymentConfig(kind, address(token), address(0), uint96(route + 1));
        _assertDeployed(this.deployCell(kind, route == 1, address(token), 0, uint96(route + 1)));
      }
    }
  }

  // ┌─ test_zeroFeeMakesNoCallEvenWhenTokenWouldAcceptTransfer ─────
  function test_zeroFeeMakesNoCallEvenWhenTokenWouldAcceptTransfer() external {
    ZeroTransferReviewToken token = _feeToken(false);
    for (uint256 i; i < 2; i++) {
      MatrixMarketKind kind = MatrixMarketKind(i);
      _configureFee(kind, FeeRecipient, address(token), 0);
      for (uint256 route; route < 2; route++) {
        _expectDeploymentConfig(kind, address(token), FeeRecipient, uint96(route + 1));
        _assertDeployed(this.deployCell(kind, route == 1, address(token), 0, uint96(route + 1)));
      }
    }
    assertEq(token.transferFromCalls(), 0);
    assertEq(token.balanceOf(FeeRecipient), 0);
    assertEq(token.balanceOf(MatrixBorrower), 0);
  }

  // ┌─ test_noFeeTokenNeedsNoTransferAcrossFactoriesAndRoutes ─────
  function test_noFeeTokenNeedsNoTransferAcrossFactoriesAndRoutes() external {
    for (uint256 i; i < 2; i++) {
      MatrixMarketKind kind = MatrixMarketKind(i);
      for (uint256 route; route < 2; route++) {
        address market = this.deployCell(kind, route == 1, address(0), 0, uint96(route + 1));
        assertEq(WildcatMarket(market).asset(), address(stack.asset));
      }
    }
  }

  // ░░▒▒▓▓██ [ POSITIVE FEE TRANSFERS ] ───────────────────────────────────────

  // ┌─ test_positiveFeeTransfersExactlyOnceAcrossFactoriesAndRoutes ─────
  function test_positiveFeeTransfersExactlyOnceAcrossFactoriesAndRoutes() external {
    ZeroTransferReviewToken token = _feeToken(true);
    token.mint(MatrixBorrower, 492);
    for (uint256 i; i < 2; i++) {
      MatrixMarketKind kind = MatrixMarketKind(i);
      _configureFee(kind, FeeRecipient, address(token), 123);
      vm.prank(MatrixBorrower);
      token.approve(address(_factoryFor(stack, kind)), 246);
      for (uint256 route; route < 2; route++) {
        address market = this.deployCell(kind, route == 1, address(token), 123, uint96(route + 1));
        assertEq(WildcatMarket(market).asset(), address(stack.asset));
        assertEq(token.balanceOf(FeeRecipient), 123 * (i * 2 + route + 1));
      }
      assertEq(token.allowance(MatrixBorrower, address(_factoryFor(stack, kind))), 0);
    }
    assertEq(token.balanceOf(MatrixBorrower), 0);
    assertEq(token.transferFromCalls(), 4);
  }

  // ┌─ test_feeMismatchPrecedesTransferAcrossFactoriesAndRoutes ─────
  function test_feeMismatchPrecedesTransferAcrossFactoriesAndRoutes() external {
    ZeroTransferReviewToken token = _feeToken(true);
    for (uint256 i; i < 2; i++) {
      MatrixMarketKind kind = MatrixMarketKind(i);
      _configureFee(kind, FeeRecipient, address(token), 0);
      for (uint256 route; route < 2; route++) {
        vm.expectRevert(IHooksFactoryEventsAndErrors.FeeMismatch.selector);
        this.deployCell(kind, route == 1, address(token), 1, uint96(route + 1));
        vm.expectRevert(IHooksFactoryEventsAndErrors.FeeMismatch.selector);
        this.deployCell(kind, route == 1, address(0), 0, uint96(route + 1));
      }
    }
  }

  // ┌─ test_positiveFeeCannotBeBypassedWithZeroAmount ─────
  function test_positiveFeeCannotBeBypassedWithZeroAmount() external {
    ZeroTransferReviewToken token = _feeToken(true);
    for (uint256 i; i < 2; i++) {
      MatrixMarketKind kind = MatrixMarketKind(i);
      _configureFee(kind, FeeRecipient, address(token), 123);
      for (uint256 route; route < 2; route++) {
        vm.expectRevert(IHooksFactoryEventsAndErrors.FeeMismatch.selector);
        this.deployCell(kind, route == 1, address(token), 0, uint96(route + 1));
      }
    }
  }

  // ┌─ test_positiveFeeStillRequiresSuccessfulTransfer ─────
  function test_positiveFeeStillRequiresSuccessfulTransfer() external {
    ZeroTransferReviewToken token = _feeToken(true);
    token.mint(MatrixBorrower, 492);
    // omit approval: positive fees must still fail deployment.
    for (uint256 i; i < 2; i++) {
      MatrixMarketKind kind = MatrixMarketKind(i);
      _configureFee(kind, FeeRecipient, address(token), 123);
      for (uint256 route; route < 2; route++) {
        vm.expectRevert(LibERC20.TransferFromFailed.selector);
        this.deployCell(kind, route == 1, address(token), 123, uint96(route + 1));
      }
    }
  }

  // ░░▒▒▓▓██ [ DEPLOYMENT ASSERTIONS ] ────────────────────────────────────────

  // ┌─ _expectDeploymentConfig ─────
  function _expectDeploymentConfig(MatrixMarketKind kind, address feeAsset, address recipient, uint96 nonce) internal {
    IHooksFactory factory = _factoryFor(stack, kind);
    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, kind);
    address expectedMarket = factory.computeMarketAddress(_marketSalt(MatrixBorrower, nonce));
    vm.expectEmit(address(factory));
    emit IHooksFactoryEventsAndErrors.MarketDeploymentConfig(
      expectedMarket,
      options.maxTotalSupply,
      options.annualInterestBips,
      options.delinquencyFeeBips,
      options.withdrawalBatchDuration,
      options.reserveRatioBips,
      options.delinquencyGracePeriod,
      recipient,
      0,
      feeAsset,
      0
    );
  }

  // ┌─ _assertDeployed ─────
  function _assertDeployed(address market) internal view {
    assertEq(WildcatMarket(market).asset(), address(stack.asset));
    assertEq(WildcatMarket(market).borrower(), MatrixBorrower);
    address hooks = WildcatMarket(market).hooks().hooksAddress();
    assertTrue(hooks != address(0));
    assertTrue(stack.archController.isRegisteredMarket(market));
  }
}
