// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

contract WildcatMarketTest is MarketFixture {
  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);
  address internal constant Delegate = address(0xDE1E6A7E);
  bytes4 internal constant PanicSelector = 0x4e487b71;
  uint256 internal constant ArithmeticPanic = 0x11;

  function _arithmeticPanic() private pure returns (bytes memory) {
    return abi.encodeWithSelector(PanicSelector, ArithmeticPanic);
  }

  function _tokenOptions(HooksKind kind) private pure returns (Options memory options) {
    options = _defaultOptions(kind);
    options.annualInterestBips = 0;
    options.withdrawalBatchDuration = 0;
  }

  function _newTokenMarket(HooksKind kind) private returns (Fixture memory fixture) {
    return _newMarket(_tokenOptions(kind));
  }

  function _mintMarketTokens(Fixture memory fixture, address account, uint256 amount) private {
    _deposit(fixture, account, amount);
  }

  function _assertSupplyAndBalance(
    Fixture memory fixture,
    address account,
    uint256 expected
  ) private view {
    assertEq(fixture.market.totalSupply(), expected, 'total supply');
    assertEq(fixture.market.balanceOf(account), expected, 'account balance');
  }

  function test_tokenMetadataAndRoundingMarker_AcrossHookKinds() external {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newTokenMarket(HooksKind(i));
      assertEq(fixture.market.name(), 'Wildcat Token', 'name');
      assertEq(fixture.market.symbol(), 'WCTKN', 'symbol');
      assertEq(fixture.market.decimals(), 18, 'decimals');
      assertEq(fixture.market.version(), '2.5', 'version');
      assertEq(
        fixture.market.scaledTransferRounding(),
        keccak256('scaleAmountDown'),
        'rounding marker'
      );
    }
  }

  function test_tokenMintAndBurnAccounting_AcrossHookKinds(
    uint104 rawMintAmount,
    uint104 rawBurnAmount
  ) external {
    uint256 mintAmount = bound(rawMintAmount, 1, MaximumMarketSupply);
    uint256 burnAmount = bound(rawBurnAmount, 1, mintAmount);

    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(fixture, Holder, mintAmount);
      _assertSupplyAndBalance(fixture, Holder, mintAmount);

      _queueAndExecuteWithdrawal(fixture, Holder, burnAmount);
      _assertSupplyAndBalance(fixture, Holder, mintAmount - burnAmount);
    }
  }

  function test_approveStoresExactAllowance_AcrossHookKinds(
    address spender,
    uint256 amount
  ) external {
    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newTokenMarket(HooksKind(i));
      vm.prank(Holder);
      assertTrue(fixture.market.approve(spender, amount), 'approve result');
      assertEq(fixture.market.allowance(Holder, spender), amount, 'allowance');
    }
  }

  function test_transferMovesBalanceAndPreservesSupply_AcrossHookKinds(
    address fuzzRecipient,
    uint104 rawAmount
  ) external {
    vm.assume(fuzzRecipient != address(0) && fuzzRecipient != Holder);
    uint256 amount = bound(rawAmount, 1, MaximumMarketSupply);

    for (uint256 i; i < 2; i++) {
      Fixture memory fixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(fixture, Holder, amount);

      vm.prank(Holder);
      assertTrue(fixture.market.transfer(fuzzRecipient, amount), 'transfer result');
      assertEq(fixture.market.totalSupply(), amount, 'supply after transfer');
      assertEq(fixture.market.balanceOf(Holder), 0, 'sender after transfer');
      assertEq(fixture.market.balanceOf(fuzzRecipient), amount, 'recipient after transfer');

      vm.prank(fuzzRecipient);
      assertTrue(fixture.market.transfer(fuzzRecipient, amount), 'self-transfer result');
      assertEq(fixture.market.totalSupply(), amount, 'supply after self-transfer');
      assertEq(fixture.market.balanceOf(fuzzRecipient), amount, 'self-transfer balance');
    }
  }

  function test_transferFromHandlesFiniteInfiniteAndSelfTransfer_AcrossHookKinds(
    address fuzzRecipient,
    uint104 rawAmount,
    uint104 rawExtraApproval
  ) external {
    vm.assume(fuzzRecipient != Holder);
    uint256 amount = bound(rawAmount, 1, MaximumMarketSupply);
    uint256 extraApproval = bound(rawExtraApproval, 0, MaximumMarketSupply - amount);
    uint256 finiteApproval = amount + extraApproval;

    for (uint256 i; i < 2; i++) {
      Fixture memory finiteFixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(finiteFixture, Holder, amount);
      vm.prank(Holder);
      finiteFixture.market.approve(Delegate, finiteApproval);
      vm.prank(Delegate);
      assertTrue(
        finiteFixture.market.transferFrom(Holder, fuzzRecipient, amount),
        'finite transferFrom result'
      );
      assertEq(finiteFixture.market.allowance(Holder, Delegate), extraApproval, 'finite allowance');
      assertEq(finiteFixture.market.totalSupply(), amount, 'finite supply');
      assertEq(finiteFixture.market.balanceOf(Holder), 0, 'finite sender');
      assertEq(finiteFixture.market.balanceOf(fuzzRecipient), amount, 'finite recipient');

      Fixture memory infiniteFixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(infiniteFixture, Holder, amount);
      vm.prank(Holder);
      infiniteFixture.market.approve(Delegate, type(uint256).max);
      vm.prank(Delegate);
      assertTrue(
        infiniteFixture.market.transferFrom(Holder, Holder, amount),
        'infinite self transferFrom result'
      );
      assertEq(
        infiniteFixture.market.allowance(Holder, Delegate),
        type(uint256).max,
        'infinite allowance'
      );
      _assertSupplyAndBalance(infiniteFixture, Holder, amount);
    }
  }

  function test_transfersRejectInsufficientBalancesAndAllowances_AcrossHookKinds(
    uint104 rawMintAmount,
    uint104 rawExcess
  ) external {
    uint256 mintAmount = bound(rawMintAmount, 1, MaximumMarketSupply - 1);
    uint256 sendAmount = mintAmount + bound(rawExcess, 1, MaximumMarketSupply - mintAmount);

    for (uint256 i; i < 2; i++) {
      Fixture memory transferFixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(transferFixture, Holder, mintAmount);
      vm.prank(Holder);
      vm.expectRevert(_arithmeticPanic());
      transferFixture.market.transfer(Recipient, sendAmount);

      Fixture memory allowanceFixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(allowanceFixture, Holder, sendAmount);
      vm.prank(Holder);
      allowanceFixture.market.approve(Delegate, sendAmount - 1);
      vm.prank(Delegate);
      vm.expectRevert(_arithmeticPanic());
      allowanceFixture.market.transferFrom(Holder, Recipient, sendAmount);

      Fixture memory balanceFixture = _newTokenMarket(HooksKind(i));
      _mintMarketTokens(balanceFixture, Holder, mintAmount);
      vm.prank(Holder);
      balanceFixture.market.approve(Delegate, sendAmount);
      vm.prank(Delegate);
      vm.expectRevert(_arithmeticPanic());
      balanceFixture.market.transferFrom(Holder, Recipient, sendAmount);
    }
  }

  function test_zeroTransfersAndBlockedRecipientsRevert_AcrossHookKinds() external {
    for (uint256 i; i < 2; i++) {
      Fixture memory zeroFixture = _newTokenMarket(HooksKind(i));
      vm.expectRevert(IMarketEventsAndErrors.NullTransferAmount.selector);
      zeroFixture.market.transfer(Recipient, 0);
      vm.expectRevert(IMarketEventsAndErrors.NullTransferAmount.selector);
      zeroFixture.market.transferFrom(Holder, Recipient, 0);

      Options memory blockedOptions = _tokenOptions(HooksKind(i));
      blockedOptions.requestedHooks = blockedOptions.requestedHooks.setFlag(Bit_Enabled_Transfer);
      Fixture memory blockedFixture = _newMarket(blockedOptions);
      _mintMarketTokens(blockedFixture, Holder, 1);
      vm.prank(Borrower);
      if (HooksKind(i) == HooksKind.OpenTerm) {
        OpenTermHooks(address(blockedFixture.hooks)).blockFromDeposits(Recipient);
      } else {
        FixedTermHooks(address(blockedFixture.hooks)).blockFromDeposits(Recipient);
      }
      vm.prank(Holder);
      vm.expectRevert(IMarketEventsAndErrors.NotApprovedLender.selector);
      blockedFixture.market.transfer(Recipient, 1);
    }
  }
}
