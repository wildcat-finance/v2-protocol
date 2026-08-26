// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { MathUtils, RAY } from 'src/libraries/MathUtils.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { ERC20 } from 'solady/tokens/ERC20.sol';
import { WrapperMarketMock, WrapperPlainERC20Mock } from '../mocks/WrapperMocks.sol';
import { WrapperSentinelMock, WrapperSpoofEscrowMock } from '../mocks/WrapperMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract Wildcat4626WrapperTest is TestKernel {
  event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
  event Withdraw(
    address indexed sender,
    address indexed receiver,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );
  event TokensSwept(address indexed token, address indexed to, uint256 amount);
  event SanctionedAccountSharesSentToEscrow(
    address indexed account,
    address indexed escrow,
    uint256 shares
  );

  uint256 internal constant Unit = 1e6;
  address internal constant Borrower = address(0xB0123123);
  address internal constant Holder = address(0xA11CE);
  address internal constant Receiver = address(0xB0B);
  address internal constant Spender = address(0x5EED);

  struct Fixture {
    WrapperSentinelMock sentinel;
    WrapperMarketMock market;
    Wildcat4626Wrapper wrapper;
  }

  function _deployMarket(
    uint8 decimals,
    address borrower,
    address principal,
    address sentinel,
    address wrapperFactory
  ) private returns (WrapperMarketMock) {
    return
      WrapperMarketMock(
        _deployCode(
          'test/mocks/WrapperMocks.sol:WrapperMarketMock',
          abi.encode(decimals, borrower, principal, sentinel, wrapperFactory)
        )
      );
  }

  function _deployWrapper(address market) private returns (Wildcat4626Wrapper) {
    return
      Wildcat4626Wrapper(
        _deployCode('src/vault/Wildcat4626Wrapper.sol:Wildcat4626Wrapper', abi.encode(market))
      );
  }

  function _newFixture() private returns (Fixture memory fixture) {
    fixture.sentinel = WrapperSentinelMock(
      _deployCode('test/mocks/WrapperMocks.sol:WrapperSentinelMock')
    );
    fixture.market = _deployMarket(6, Borrower, Borrower, address(fixture.sentinel), address(this));
    fixture.wrapper = _deployWrapper(address(fixture.market));
  }

  function _fundAndApprove(Fixture memory fixture, address account, uint256 assets) private {
    fixture.market.mint(account, assets);
    vm.prank(account);
    fixture.market.approve(address(fixture.wrapper), type(uint256).max);
  }

  function _deposit(
    Fixture memory fixture,
    address account,
    uint256 assets
  ) private returns (uint256 shares) {
    _fundAndApprove(fixture, account, assets);
    vm.prank(account);
    shares = fixture.wrapper.deposit(assets, account);
  }

  function _absoluteDifference(uint256 left, uint256 right) private pure returns (uint256) {
    return left > right ? left - right : right - left;
  }

  function _expectSanctioned(address account) private {
    vm.expectRevert(abi.encodeWithSelector(Wildcat4626Wrapper.SanctionedAccount.selector, account));
  }

  function test_constructorAndMetadataValidateMarketDependencies() external {
    Fixture memory fixture = _newFixture();

    assertEq(fixture.wrapper.name(), 'friesUSDC [4626 Vault Shares]', 'name');
    assertEq(fixture.wrapper.symbol(), 'v-friesUSDC', 'symbol');
    assertEq(fixture.wrapper.decimals(), 6, 'decimals');
    assertEq(fixture.wrapper.market(), address(fixture.market), 'market');
    assertEq(fixture.wrapper.asset(), address(fixture.market), 'asset');
    assertEq(fixture.wrapper.marketOwner(), Borrower, 'market owner');
    assertEq(address(fixture.wrapper.sanctionsSentinel()), address(fixture.sentinel), 'sentinel');

    vm.expectRevert(Wildcat4626Wrapper.ZeroAddress.selector);
    _deployWrapper(address(0));

    WrapperMarketMock zeroBorrower = _deployMarket(
      6,
      address(0),
      Borrower,
      address(fixture.sentinel),
      address(this)
    );
    vm.expectRevert(Wildcat4626Wrapper.ZeroAddress.selector);
    _deployWrapper(address(zeroBorrower));

    WrapperMarketMock zeroPrincipal = _deployMarket(
      6,
      Borrower,
      address(0),
      address(fixture.sentinel),
      address(this)
    );
    vm.expectRevert(Wildcat4626Wrapper.ZeroAddress.selector);
    _deployWrapper(address(zeroPrincipal));

    WrapperMarketMock zeroSentinel = _deployMarket(
      6,
      Borrower,
      Borrower,
      address(0),
      address(this)
    );
    vm.expectRevert(Wildcat4626Wrapper.ZeroAddress.selector);
    _deployWrapper(address(zeroSentinel));

    WrapperMarketMock wrongFactory = _deployMarket(
      6,
      Borrower,
      Borrower,
      address(fixture.sentinel),
      address(0xBAD)
    );
    vm.expectRevert(Wildcat4626Wrapper.NotWrapperFactory.selector);
    _deployWrapper(address(wrongFactory));

    bytes memory decimalsCall = abi.encodeWithSignature('decimals()');
    vm.mockCall(address(fixture.market), decimalsCall, hex'01');
    vm.expectRevert();
    _deployWrapper(address(fixture.market));
    vm.clearMockedCalls();

    vm.mockCall(address(fixture.market), decimalsCall, abi.encode(uint256(type(uint8).max) + 1));
    vm.expectRevert();
    _deployWrapper(address(fixture.market));
    vm.clearMockedCalls();
  }

  function testFuzz_conversionPreviewsAndRatesFollowScaleFactor(
    uint256 assetsSeed,
    uint256 sharesSeed,
    uint256 scaleOffsetSeed
  ) external {
    Fixture memory fixture = _newFixture();
    uint256 assets = bound(assetsSeed, 1, 1e30);
    uint256 shares = bound(sharesSeed, 1, 1e30);
    uint256 scaleFactor = RAY + bound(scaleOffsetSeed, 0, 10 * RAY);
    fixture.market.setScaleFactor(scaleFactor);

    uint256 sharesDown = MathUtils.mulDiv(assets, RAY, scaleFactor);
    uint256 sharesUp = MathUtils.mulDivUp(assets, RAY, scaleFactor);
    uint256 assetsDown = MathUtils.mulDiv(shares, scaleFactor, RAY);
    uint256 assetsUp = MathUtils.mulDivUp(shares, scaleFactor, RAY);

    assertEq(fixture.wrapper.convertToShares(assets), sharesDown, 'convert shares');
    assertEq(fixture.wrapper.previewDeposit(assets), sharesDown, 'preview deposit');
    assertEq(fixture.wrapper.previewWithdraw(assets), sharesUp, 'preview withdraw');
    assertEq(fixture.wrapper.convertToAssets(shares), assetsDown, 'convert assets');
    assertEq(fixture.wrapper.previewRedeem(shares), assetsDown, 'preview redeem');
    assertEq(fixture.wrapper.previewMint(shares), assetsUp, 'preview mint');
    assertEq(fixture.wrapper.assetsPerShareRay(), scaleFactor, 'assets per share');
    assertEq(
      fixture.wrapper.sharesPerAssetRay(),
      MathUtils.mulDiv(RAY, RAY, scaleFactor),
      'shares per asset'
    );

    assertEq(fixture.wrapper.convertToShares(0), 0, 'zero convert shares');
    assertEq(fixture.wrapper.convertToAssets(0), 0, 'zero convert assets');
    assertEq(fixture.wrapper.previewMint(0), 0, 'zero preview mint');
    assertEq(fixture.wrapper.previewWithdraw(0), 0, 'zero preview withdraw');
    assertEq(fixture.wrapper.maxWithdraw(Holder), 0, 'empty max withdraw');
    assertEq(fixture.wrapper.maxRedeem(Holder), 0, 'empty max redeem');
    assertEq(fixture.wrapper.totalAssets(), 0, 'empty total assets');
    assertEq(fixture.wrapper.maxDeposit(Holder), type(uint128).max, 'max deposit');
    assertEq(
      fixture.wrapper.maxMint(Holder),
      MathUtils.mulDiv(type(uint128).max, RAY, scaleFactor),
      'max mint'
    );
  }

  function testFuzz_depositAndMintCreateExactScaledBacking(
    uint96 assetsSeed,
    uint96 sharesSeed,
    uint96 scaleOffsetSeed
  ) external {
    uint256 scaleFactor = RAY + bound(scaleOffsetSeed, 0, RAY);
    uint256 assets = bound(assetsSeed, 1e9, 100e18);
    uint256 requestedShares = bound(sharesSeed, 1e9, 100e18);

    Fixture memory depositFixture = _newFixture();
    depositFixture.market.setScaleFactor(scaleFactor);
    _fundAndApprove(depositFixture, Holder, assets);
    uint256 expectedShares = MathUtils.mulDiv(assets, RAY, scaleFactor);
    vm.expectEmit(true, true, false, true, address(depositFixture.wrapper));
    emit Deposit(Holder, Receiver, assets, expectedShares);
    vm.prank(Holder);
    uint256 depositedShares = depositFixture.wrapper.deposit(assets, Receiver);

    assertEq(depositedShares, expectedShares, 'deposit shares');
    assertEq(depositedShares, depositFixture.wrapper.previewDeposit(assets), 'deposit preview');
    assertEq(depositFixture.wrapper.balanceOf(Receiver), expectedShares, 'deposit receiver');
    assertEq(depositFixture.wrapper.totalSupply(), expectedShares, 'deposit supply');
    assertEq(
      depositFixture.market.scaledBalanceOf(address(depositFixture.wrapper)),
      expectedShares,
      'deposit backing'
    );
    assertEq(
      depositFixture.wrapper.totalAssets(),
      depositFixture.market.balanceOf(address(depositFixture.wrapper)),
      'deposit assets'
    );

    Fixture memory mintFixture = _newFixture();
    mintFixture.market.setScaleFactor(scaleFactor);
    uint256 expectedAssets = MathUtils.mulDivUp(requestedShares, scaleFactor, RAY);
    _fundAndApprove(mintFixture, Holder, expectedAssets);
    vm.expectEmit(true, true, false, true, address(mintFixture.wrapper));
    emit Deposit(Holder, Receiver, expectedAssets, requestedShares);
    vm.prank(Holder);
    uint256 mintedAssets = mintFixture.wrapper.mint(requestedShares, Receiver);

    assertEq(mintedAssets, expectedAssets, 'mint assets');
    assertEq(mintedAssets, mintFixture.wrapper.previewMint(requestedShares), 'mint preview');
    assertEq(mintFixture.wrapper.balanceOf(Receiver), requestedShares, 'mint receiver');
    assertEq(mintFixture.wrapper.totalSupply(), requestedShares, 'mint supply');
    assertEq(
      mintFixture.market.scaledBalanceOf(address(mintFixture.wrapper)),
      requestedShares,
      'mint backing'
    );
  }

  function testFuzz_withdrawAndRedeemBurnExactScaledBacking(
    uint96 withdrawSeed,
    uint96 redeemSeed,
    uint96 scaleOffsetSeed
  ) external {
    uint256 scaleFactor = RAY + bound(scaleOffsetSeed, 0, RAY);

    Fixture memory withdrawFixture = _newFixture();
    withdrawFixture.market.setScaleFactor(scaleFactor);
    uint256 depositedShares = _deposit(withdrawFixture, Holder, 100e18);
    uint256 minimumAssets = MathUtils.mulDivUp(1, scaleFactor, RAY);
    uint256 withdrawAssets = bound(
      withdrawSeed,
      minimumAssets,
      withdrawFixture.wrapper.maxWithdraw(Holder)
    );
    uint256 expectedBurned = MathUtils.mulDiv(withdrawAssets, RAY, scaleFactor);
    vm.expectEmit(true, true, true, true, address(withdrawFixture.wrapper));
    emit Withdraw(Holder, Receiver, Holder, withdrawAssets, expectedBurned);
    vm.prank(Holder);
    uint256 burnedShares = withdrawFixture.wrapper.withdraw(withdrawAssets, Receiver, Holder);

    assertEq(burnedShares, expectedBurned, 'withdraw burned');
    assertEq(
      withdrawFixture.wrapper.balanceOf(Holder),
      depositedShares - expectedBurned,
      'withdraw shares'
    );
    assertEq(withdrawFixture.market.scaledBalanceOf(Receiver), expectedBurned, 'withdraw receiver');
    assertEq(
      withdrawFixture.market.scaledBalanceOf(address(withdrawFixture.wrapper)),
      withdrawFixture.wrapper.totalSupply(),
      'withdraw backing'
    );

    Fixture memory redeemFixture = _newFixture();
    redeemFixture.market.setScaleFactor(scaleFactor);
    depositedShares = _deposit(redeemFixture, Holder, 100e18);
    uint256 redeemedShares = bound(redeemSeed, 1, depositedShares);
    uint256 expectedRedeemedAssets = MathUtils.mulDivUp(redeemedShares, scaleFactor, RAY);
    vm.expectEmit(true, true, true, true, address(redeemFixture.wrapper));
    emit Withdraw(Holder, Receiver, Holder, expectedRedeemedAssets, redeemedShares);
    vm.prank(Holder);
    uint256 redeemedAssets = redeemFixture.wrapper.redeem(redeemedShares, Receiver, Holder);

    assertEq(redeemedAssets, expectedRedeemedAssets, 'redeem assets');
    assertEq(
      redeemFixture.wrapper.balanceOf(Holder),
      depositedShares - redeemedShares,
      'redeem shares'
    );
    assertEq(redeemFixture.market.scaledBalanceOf(Receiver), redeemedShares, 'redeem receiver');
    assertEq(
      redeemFixture.market.scaledBalanceOf(address(redeemFixture.wrapper)),
      redeemFixture.wrapper.totalSupply(),
      'redeem backing'
    );
  }

  function test_spenderAllowancesCoverExactInfiniteAndInsufficientPaths() external {
    Fixture memory fixture = _newFixture();
    _deposit(fixture, Holder, 40 * Unit);

    vm.prank(Holder);
    fixture.wrapper.approve(Spender, 4 * Unit);
    vm.prank(Spender);
    assertEq(fixture.wrapper.withdraw(4 * Unit, Receiver, Holder), 4 * Unit, 'exact withdraw');
    assertEq(fixture.wrapper.allowance(Holder, Spender), 0, 'spent withdraw allowance');

    vm.prank(Holder);
    fixture.wrapper.approve(Spender, type(uint256).max);
    vm.prank(Spender);
    fixture.wrapper.withdraw(4 * Unit, Receiver, Holder);
    assertEq(
      fixture.wrapper.allowance(Holder, Spender),
      type(uint256).max,
      'infinite withdraw allowance'
    );

    vm.prank(Holder);
    fixture.wrapper.approve(Spender, 4 * Unit - 1);
    vm.prank(Spender);
    vm.expectRevert(ERC20.InsufficientAllowance.selector);
    fixture.wrapper.withdraw(4 * Unit, Receiver, Holder);

    vm.prank(Holder);
    fixture.wrapper.approve(Spender, 4 * Unit);
    vm.prank(Spender);
    assertEq(fixture.wrapper.redeem(4 * Unit, Receiver, Holder), 4 * Unit, 'exact redeem');
    assertEq(fixture.wrapper.allowance(Holder, Spender), 0, 'spent redeem allowance');

    vm.prank(Holder);
    fixture.wrapper.approve(Spender, type(uint256).max);
    vm.prank(Spender);
    fixture.wrapper.redeem(4 * Unit, Receiver, Holder);
    assertEq(
      fixture.wrapper.allowance(Holder, Spender),
      type(uint256).max,
      'infinite redeem allowance'
    );

    vm.prank(Holder);
    fixture.wrapper.approve(Spender, 4 * Unit - 1);
    vm.prank(Spender);
    vm.expectRevert(ERC20.InsufficientAllowance.selector);
    fixture.wrapper.redeem(4 * Unit, Receiver, Holder);
  }

  function test_zeroInputsAndCapacityBoundariesUseExactErrors() external {
    Fixture memory zeroFixture = _newFixture();
    vm.prank(Holder);
    vm.expectRevert(Wildcat4626Wrapper.ZeroAssets.selector);
    zeroFixture.wrapper.deposit(0, Receiver);
    vm.prank(Holder);
    vm.expectRevert(Wildcat4626Wrapper.ZeroShares.selector);
    zeroFixture.wrapper.mint(0, Receiver);
    vm.prank(Holder);
    vm.expectRevert(Wildcat4626Wrapper.ZeroAssets.selector);
    zeroFixture.wrapper.withdraw(0, Receiver, Holder);
    vm.prank(Holder);
    vm.expectRevert(Wildcat4626Wrapper.ZeroShares.selector);
    zeroFixture.wrapper.redeem(0, Receiver, Holder);

    Fixture memory fullFixture = _newFixture();
    _deposit(fullFixture, Holder, 10 * Unit);
    fullFixture.market.setMaxTotalSupply(fullFixture.wrapper.totalAssets());
    assertEq(fullFixture.wrapper.maxDeposit(Holder), 0, 'full max deposit');
    assertEq(fullFixture.wrapper.maxMint(Holder), 0, 'full max mint');
    vm.prank(Holder);
    vm.expectRevert(Wildcat4626Wrapper.CapExceeded.selector);
    fullFixture.wrapper.deposit(Unit, Holder);
    vm.prank(Holder);
    vm.expectRevert(Wildcat4626Wrapper.CapExceeded.selector);
    fullFixture.wrapper.mint(Unit, Holder);

    Fixture memory dustFixture = _newFixture();
    dustFixture.market.setScaleFactor(RAY + RAY / 2);
    dustFixture.market.setMaxTotalSupply(1);
    assertEq(dustFixture.wrapper.maxDeposit(Holder), 0, 'dust max deposit');
    assertEq(dustFixture.wrapper.maxMint(Holder), 0, 'dust max mint');
    vm.prank(Holder);
    vm.expectRevert(Wildcat4626Wrapper.ZeroShares.selector);
    dustFixture.wrapper.deposit(1, Holder);

    Fixture memory fractionalDepositFixture = _newFixture();
    fractionalDepositFixture.market.setScaleFactor(RAY + RAY / 2);
    fractionalDepositFixture.market.setMaxTotalSupply(15 * Unit);
    uint256 maxDeposit = fractionalDepositFixture.wrapper.maxDeposit(Holder);
    _fundAndApprove(fractionalDepositFixture, Holder, maxDeposit + 1);
    vm.prank(Holder);
    assertEq(
      fractionalDepositFixture.wrapper.deposit(maxDeposit, Holder),
      10 * Unit,
      'fractional deposit'
    );

    Fixture memory fractionalMintFixture = _newFixture();
    fractionalMintFixture.market.setScaleFactor(RAY + RAY / 2);
    fractionalMintFixture.market.setMaxTotalSupply(15 * Unit);
    uint256 maxMint = fractionalMintFixture.wrapper.maxMint(Holder);
    uint256 mintAssets = fractionalMintFixture.wrapper.previewMint(maxMint);
    _fundAndApprove(fractionalMintFixture, Holder, mintAssets);
    vm.prank(Holder);
    assertEq(fractionalMintFixture.wrapper.mint(maxMint, Holder), mintAssets, 'fractional mint');

    Fixture memory withdrawDustFixture = _newFixture();
    withdrawDustFixture.market.setScaleFactor(RAY + RAY / 2);
    _deposit(withdrawDustFixture, Holder, 10 * Unit);
    vm.prank(Holder);
    vm.expectRevert(Wildcat4626Wrapper.ZeroShares.selector);
    withdrawDustFixture.wrapper.withdraw(1, Holder, Holder);
  }

  function testFuzz_allEntryPointRoundTripsPreserveScaledOwnership(
    uint96 amountSeed,
    uint96 scaleOffsetSeed
  ) external {
    uint256 amount = bound(amountSeed, 1e12, 100e18);
    uint256 scaleFactor = RAY + bound(scaleOffsetSeed, 0, RAY);

    Fixture memory depositRedeem = _newFixture();
    depositRedeem.market.setScaleFactor(scaleFactor);
    _fundAndApprove(depositRedeem, Holder, amount);
    uint256 initialScaled = depositRedeem.market.scaledBalanceOf(Holder);
    vm.startPrank(Holder);
    uint256 shares = depositRedeem.wrapper.deposit(amount, Holder);
    depositRedeem.wrapper.redeem(shares, Holder, Holder);
    vm.stopPrank();
    assertEq(depositRedeem.market.scaledBalanceOf(Holder), initialScaled, 'deposit redeem scaled');
    assertEq(depositRedeem.wrapper.totalSupply(), 0, 'deposit redeem supply');

    Fixture memory depositWithdraw = _newFixture();
    depositWithdraw.market.setScaleFactor(scaleFactor);
    _fundAndApprove(depositWithdraw, Holder, amount);
    initialScaled = depositWithdraw.market.scaledBalanceOf(Holder);
    vm.startPrank(Holder);
    depositWithdraw.wrapper.deposit(amount, Holder);
    depositWithdraw.wrapper.withdraw(depositWithdraw.wrapper.maxWithdraw(Holder), Holder, Holder);
    vm.stopPrank();
    assertEq(
      depositWithdraw.market.scaledBalanceOf(Holder),
      initialScaled,
      'deposit withdraw scaled'
    );
    assertEq(depositWithdraw.wrapper.totalSupply(), 0, 'deposit withdraw supply');

    uint256 requestedShares = MathUtils.mulDiv(amount, RAY, scaleFactor);
    Fixture memory mintRedeem = _newFixture();
    mintRedeem.market.setScaleFactor(scaleFactor);
    uint256 requiredAssets = mintRedeem.wrapper.previewMint(requestedShares);
    _fundAndApprove(mintRedeem, Holder, requiredAssets);
    initialScaled = mintRedeem.market.scaledBalanceOf(Holder);
    vm.startPrank(Holder);
    mintRedeem.wrapper.mint(requestedShares, Holder);
    mintRedeem.wrapper.redeem(requestedShares, Holder, Holder);
    vm.stopPrank();
    assertEq(mintRedeem.market.scaledBalanceOf(Holder), initialScaled, 'mint redeem scaled');
    assertEq(mintRedeem.wrapper.totalSupply(), 0, 'mint redeem supply');

    Fixture memory mintWithdraw = _newFixture();
    mintWithdraw.market.setScaleFactor(scaleFactor);
    requiredAssets = mintWithdraw.wrapper.previewMint(requestedShares);
    _fundAndApprove(mintWithdraw, Holder, requiredAssets);
    initialScaled = mintWithdraw.market.scaledBalanceOf(Holder);
    vm.startPrank(Holder);
    mintWithdraw.wrapper.mint(requestedShares, Holder);
    mintWithdraw.wrapper.withdraw(mintWithdraw.wrapper.maxWithdraw(Holder), Holder, Holder);
    vm.stopPrank();
    assertEq(mintWithdraw.market.scaledBalanceOf(Holder), initialScaled, 'mint withdraw scaled');
    assertEq(mintWithdraw.wrapper.totalSupply(), 0, 'mint withdraw supply');
  }

  function test_multipleDepositorsAccrueWithoutSocializingDirectTransfers() external {
    Fixture memory fixture = _newFixture();
    uint256 holderShares = _deposit(fixture, Holder, 20 * Unit);
    fixture.market.setScaleFactor(RAY + RAY / 2);
    uint256 receiverShares = _deposit(fixture, Receiver, 30 * Unit);

    assertEq(holderShares, 20 * Unit, 'holder shares');
    assertEq(receiverShares, 20 * Unit, 'receiver shares');
    assertEq(fixture.wrapper.convertToAssets(holderShares), 30 * Unit, 'holder assets');
    assertEq(fixture.wrapper.convertToAssets(receiverShares), 30 * Unit, 'receiver assets');
    assertEq(fixture.wrapper.totalSupply(), 40 * Unit, 'accrued supply');
    assertEq(fixture.wrapper.totalAssets(), 60 * Unit, 'accrued assets');

    fixture.market.mint(Holder, 9 * Unit);
    vm.prank(Holder);
    fixture.market.transfer(address(fixture.wrapper), 9 * Unit);
    assertEq(fixture.wrapper.totalAssets(), 69 * Unit, 'direct transfer assets');
    assertEq(fixture.wrapper.convertToAssets(holderShares), 30 * Unit, 'holder claim');
    assertEq(fixture.wrapper.convertToAssets(receiverShares), 30 * Unit, 'receiver claim');

    vm.prank(Holder);
    fixture.wrapper.redeem(holderShares, Holder, Holder);
    assertEq(fixture.wrapper.balanceOf(Receiver), receiverShares, 'receiver shares remain');
    assertEq(
      fixture.market.scaledBalanceOf(address(fixture.wrapper)),
      receiverShares + 6 * Unit,
      'receiver backing plus donation'
    );
  }

  function test_donationsCannotInflateLaterDepositorShares() external {
    Fixture memory fixture = _newFixture();
    address attacker = address(0xA77AC8E5);
    address victim = address(0xBAD);
    _fundAndApprove(fixture, attacker, 60 * Unit);
    _fundAndApprove(fixture, victim, 20 * Unit);

    vm.prank(attacker);
    uint256 attackerShares = fixture.wrapper.deposit(Unit, attacker);
    vm.prank(attacker);
    fixture.market.transfer(address(fixture.wrapper), 50 * Unit);
    fixture.market.setScaleFactor(RAY + RAY / 2);

    vm.prank(victim);
    uint256 victimShares = fixture.wrapper.deposit(15 * Unit, victim);

    assertEq(attackerShares, Unit, 'attacker shares');
    assertEq(victimShares, 10 * Unit, 'victim shares');
    assertEq(fixture.wrapper.convertToAssets(attackerShares), Unit + Unit / 2, 'attacker claim');
    assertEq(fixture.wrapper.convertToAssets(victimShares), 15 * Unit, 'victim claim');
    assertEq(
      fixture.wrapper.totalAssets() -
        fixture.wrapper.convertToAssets(attackerShares) -
        fixture.wrapper.convertToAssets(victimShares),
      75 * Unit,
      'stranded donation'
    );
  }

  function test_transferAccountingMismatchGuardsRollBackEveryPath() external {
    Fixture memory depositFixture = _newFixture();
    _fundAndApprove(depositFixture, Holder, 10 * Unit + 1);
    depositFixture.market.setTransferSkew(1);
    vm.prank(Holder);
    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626Wrapper.SharesMismatch.selector, 10 * Unit, 10 * Unit + 1)
    );
    depositFixture.wrapper.deposit(10 * Unit, Holder);
    assertEq(depositFixture.wrapper.totalSupply(), 0, 'deposit rollback');

    Fixture memory mintFixture = _newFixture();
    _fundAndApprove(mintFixture, Holder, 10 * Unit + 1);
    mintFixture.market.setTransferSkew(1);
    vm.prank(Holder);
    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626Wrapper.SharesMismatch.selector, 10 * Unit, 10 * Unit + 1)
    );
    mintFixture.wrapper.mint(10 * Unit, Holder);
    assertEq(mintFixture.wrapper.totalSupply(), 0, 'mint rollback');

    Fixture memory withdrawFixture = _newFixture();
    _deposit(withdrawFixture, Holder, 10 * Unit);
    withdrawFixture.market.setTransferSkew(-1);
    vm.prank(Holder);
    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626Wrapper.SharesMismatch.selector, 4 * Unit, 4 * Unit - 1)
    );
    withdrawFixture.wrapper.withdraw(4 * Unit, Receiver, Holder);
    assertEq(withdrawFixture.wrapper.balanceOf(Holder), 10 * Unit, 'withdraw rollback');

    Fixture memory redeemFixture = _newFixture();
    _deposit(redeemFixture, Holder, 10 * Unit);
    redeemFixture.market.setTransferSkew(-1);
    vm.prank(Holder);
    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626Wrapper.SharesMismatch.selector, 4 * Unit, 4 * Unit - 1)
    );
    redeemFixture.wrapper.redeem(4 * Unit, Receiver, Holder);
    assertEq(redeemFixture.wrapper.balanceOf(Holder), 10 * Unit, 'redeem rollback');
  }

  function test_tinyScaleRegressionsKeepMaxWithdrawAndRoundTripsExecutable() external {
    Fixture memory fixture = _newFixture();
    fixture.market.setScaleFactor(RAY + 13_652);
    _fundAndApprove(fixture, Holder, 1e12);
    vm.startPrank(Holder);
    fixture.wrapper.deposit(1e12, Holder);
    uint256 maxWithdraw = fixture.wrapper.maxWithdraw(Holder);
    uint256 sharesBurned = fixture.wrapper.withdraw(maxWithdraw, Holder, Holder);
    vm.stopPrank();

    assertEq(fixture.wrapper.balanceOf(Holder), 0, 'tiny offset shares');
    assertTrue(sharesBurned > 0, 'tiny offset burn');

    Fixture memory dustFixture = _newFixture();
    dustFixture.market.setScaleFactor(RAY + RAY / 5);
    uint256 dustAssets = dustFixture.wrapper.previewMint(1);
    _fundAndApprove(dustFixture, Holder, dustAssets);
    vm.startPrank(Holder);
    dustFixture.wrapper.mint(1, Holder);
    uint256 dustMax = dustFixture.wrapper.maxWithdraw(Holder);
    assertTrue(dustMax > 0, 'dust max');
    assertEq(dustFixture.wrapper.withdraw(dustMax, Holder, Holder), 1, 'dust burn');
    vm.stopPrank();
    assertEq(dustFixture.wrapper.balanceOf(Holder), 0, 'dust shares');

    assertTrue(_absoluteDifference(sharesBurned, 1e12) <= 1, 'tiny offset variance');
  }

  function test_lowLevelReadersValidateWordsAddressesPoliciesAndEscrows() external {
    Fixture memory fixture = _newFixture();
    _deposit(fixture, Holder, 10 * Unit);

    address sentinel = address(fixture.sentinel);
    bytes memory sanctionsCall = abi.encodeWithSignature(
      'isSanctioned(address,address)',
      Borrower,
      Holder
    );
    vm.mockCall(sentinel, sanctionsCall, hex'01');
    vm.expectRevert();
    fixture.wrapper.maxRedeem(Holder);
    vm.clearMockedCalls();
    vm.mockCall(sentinel, sanctionsCall, abi.encode(uint256(2)));
    vm.expectRevert();
    fixture.wrapper.maxRedeem(Holder);
    vm.clearMockedCalls();
    vm.mockCallRevert(sentinel, sanctionsCall, hex'deadbeef');
    vm.expectRevert(bytes(hex'deadbeef'));
    fixture.wrapper.maxRedeem(Holder);
    vm.clearMockedCalls();
    vm.mockCall(sentinel, sanctionsCall, bytes.concat(abi.encode(true), hex'deadbeef'));
    assertEq(fixture.wrapper.maxRedeem(Holder), 0, 'long sanctions response');
    vm.clearMockedCalls();

    address market = address(fixture.market);
    bytes memory scaleCall = abi.encodeWithSignature('scaleFactor()');
    vm.mockCall(market, scaleCall, hex'01');
    vm.expectRevert();
    fixture.wrapper.convertToShares(Unit);
    vm.clearMockedCalls();
    vm.mockCallRevert(market, scaleCall, hex'feedface');
    vm.expectRevert(bytes(hex'feedface'));
    fixture.wrapper.convertToShares(Unit);
    vm.clearMockedCalls();
    vm.mockCall(market, scaleCall, bytes.concat(abi.encode(RAY), hex'deadbeef'));
    assertEq(fixture.wrapper.convertToShares(Unit), Unit, 'long market word');
    vm.clearMockedCalls();

    bytes memory balanceCall = abi.encodeWithSignature(
      'balanceOf(address)',
      address(fixture.wrapper)
    );
    vm.mockCall(market, balanceCall, hex'01');
    vm.expectRevert();
    fixture.wrapper.totalAssets();
    vm.clearMockedCalls();
    vm.mockCallRevert(market, balanceCall, hex'feedface');
    vm.expectRevert(bytes(hex'feedface'));
    fixture.wrapper.totalAssets();
    vm.clearMockedCalls();
    vm.mockCall(market, balanceCall, bytes.concat(abi.encode(Unit), hex'deadbeef'));
    assertEq(fixture.wrapper.totalAssets(), Unit, 'long account word');
    vm.clearMockedCalls();

    bytes memory borrowerCall = abi.encodeWithSignature('borrower()');
    vm.mockCall(market, borrowerCall, hex'01');
    vm.expectRevert();
    fixture.wrapper.marketOwner();
    vm.clearMockedCalls();
    vm.mockCall(market, borrowerCall, abi.encode((uint256(1) << 160) | uint160(Borrower)));
    vm.expectRevert();
    fixture.wrapper.marketOwner();
    vm.clearMockedCalls();
    vm.mockCallRevert(market, borrowerCall, hex'feedface');
    vm.expectRevert(bytes(hex'feedface'));
    fixture.wrapper.marketOwner();
    vm.clearMockedCalls();
    vm.mockCall(market, borrowerCall, bytes.concat(abi.encode(Borrower), hex'deadbeef'));
    assertEq(fixture.wrapper.marketOwner(), Borrower, 'long market address');
    vm.clearMockedCalls();

    bytes memory policyCall = abi.encodeWithSignature(
      'isMarketTransferRecipientAllowed(address,address)',
      market,
      address(fixture.wrapper)
    );
    vm.mockCall(market, policyCall, hex'01');
    assertEq(fixture.wrapper.maxDeposit(Holder), 0, 'short policy response');
    vm.clearMockedCalls();
    vm.mockCall(market, policyCall, abi.encode(uint256(2)));
    assertEq(fixture.wrapper.maxDeposit(Holder), 0, 'dirty policy response');
    vm.clearMockedCalls();
    vm.mockCallRevert(market, policyCall, hex'deadbeef');
    assertEq(fixture.wrapper.maxDeposit(Holder), 0, 'reverting policy response');
    vm.clearMockedCalls();
    vm.mockCall(market, policyCall, bytes.concat(abi.encode(true), hex'deadbeef'));
    assertTrue(fixture.wrapper.maxDeposit(Holder) > 0, 'long policy response');
    vm.clearMockedCalls();

    fixture.sentinel.setSanctioned(Holder, true);
    address escrow = fixture.sentinel.Escrow();
    bytes memory escrowCall = abi.encodeWithSignature(
      'getEscrowAddress(address,address,address)',
      Borrower,
      Holder,
      address(fixture.wrapper)
    );
    vm.mockCall(sentinel, escrowCall, hex'01');
    vm.prank(Holder);
    vm.expectRevert();
    fixture.wrapper.transfer(escrow, Unit);
    vm.clearMockedCalls();
    vm.mockCall(sentinel, escrowCall, abi.encode((uint256(1) << 160) | uint160(escrow)));
    vm.prank(Holder);
    vm.expectRevert();
    fixture.wrapper.transfer(escrow, Unit);
    vm.clearMockedCalls();
    vm.mockCallRevert(sentinel, escrowCall, hex'feedface');
    vm.prank(Holder);
    vm.expectRevert(bytes(hex'feedface'));
    fixture.wrapper.transfer(escrow, Unit);
    vm.clearMockedCalls();
    vm.mockCall(sentinel, escrowCall, bytes.concat(abi.encode(escrow), hex'deadbeef'));
    vm.prank(Holder);
    fixture.wrapper.transfer(escrow, Unit);
    assertEq(fixture.wrapper.balanceOf(escrow), Unit, 'long escrow response');
    vm.clearMockedCalls();

    vm.mockCallRevert(market, abi.encodeWithSignature('borrowerPrincipal()'), hex'deadbeef');
    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626Wrapper.AccountNotSanctioned.selector, address(0))
    );
    fixture.wrapper.nukeFromOrbit(address(0));
    vm.clearMockedCalls();
  }

  function test_sanctionsGateLimitsEntryPointsAndShareTransfers() external {
    Fixture memory fixture = _newFixture();
    _fundAndApprove(fixture, Holder, 40 * Unit);

    fixture.sentinel.setSanctioned(Holder, true);
    _expectSanctioned(Holder);
    vm.prank(Holder);
    fixture.wrapper.deposit(Unit, Receiver);
    _expectSanctioned(Holder);
    vm.prank(Holder);
    fixture.wrapper.mint(Unit, Receiver);

    fixture.sentinel.setSanctioned(Holder, false);
    fixture.sentinel.setSanctioned(Receiver, true);
    _expectSanctioned(Receiver);
    vm.prank(Holder);
    fixture.wrapper.deposit(Unit, Receiver);
    _expectSanctioned(Receiver);
    vm.prank(Holder);
    fixture.wrapper.mint(Unit, Receiver);

    fixture.sentinel.setSanctioned(Receiver, false);
    vm.prank(Holder);
    fixture.wrapper.deposit(20 * Unit, Holder);
    uint256 unsanctionedMaxDeposit = fixture.wrapper.maxDeposit(Holder);
    uint256 unsanctionedMaxMint = fixture.wrapper.maxMint(Holder);
    assertTrue(unsanctionedMaxDeposit > 0, 'unsanctioned max deposit');
    assertTrue(unsanctionedMaxMint > 0, 'unsanctioned max mint');
    assertTrue(fixture.wrapper.maxWithdraw(Holder) > 0, 'unsanctioned max withdraw');
    assertEq(fixture.wrapper.maxRedeem(Holder), 20 * Unit, 'unsanctioned max redeem');

    fixture.sentinel.setSanctioned(Holder, true);
    assertEq(fixture.wrapper.maxDeposit(Holder), 0, 'sanctioned max deposit');
    assertEq(fixture.wrapper.maxMint(Holder), 0, 'sanctioned max mint');
    assertEq(fixture.wrapper.maxWithdraw(Holder), 0, 'sanctioned max withdraw');
    assertEq(fixture.wrapper.maxRedeem(Holder), 0, 'sanctioned max redeem');
    _expectSanctioned(Holder);
    vm.prank(Holder);
    fixture.wrapper.withdraw(Unit, Holder, Holder);
    _expectSanctioned(Holder);
    vm.prank(Holder);
    fixture.wrapper.redeem(Unit, Holder, Holder);
    _expectSanctioned(Holder);
    vm.prank(Holder);
    fixture.wrapper.transfer(Receiver, Unit);

    fixture.sentinel.setSanctioned(Holder, false);
    fixture.sentinel.setSanctioned(Receiver, true);
    _expectSanctioned(Receiver);
    vm.prank(Holder);
    fixture.wrapper.withdraw(Unit, Receiver, Holder);
    _expectSanctioned(Receiver);
    vm.prank(Holder);
    fixture.wrapper.redeem(Unit, Receiver, Holder);
    _expectSanctioned(Receiver);
    vm.prank(Holder);
    fixture.wrapper.transfer(Receiver, Unit);

    fixture.sentinel.setSanctioned(Receiver, false);
    vm.prank(Holder);
    fixture.wrapper.approve(Spender, type(uint256).max);
    fixture.sentinel.setSanctioned(Spender, true);
    _expectSanctioned(Spender);
    vm.prank(Spender);
    fixture.wrapper.withdraw(Unit, Receiver, Holder);
    _expectSanctioned(Spender);
    vm.prank(Spender);
    fixture.wrapper.redeem(Unit, Receiver, Holder);

    fixture.sentinel.setSanctioned(Spender, false);
    fixture.sentinel.setSanctioned(Receiver, true);
    _expectSanctioned(Receiver);
    vm.prank(Spender);
    fixture.wrapper.transferFrom(Holder, Receiver, Unit);

    fixture.sentinel.setSanctioned(Receiver, false);
    fixture.sentinel.setSanctioned(Holder, true);
    _expectSanctioned(Holder);
    vm.prank(Spender);
    fixture.wrapper.transferFrom(Holder, Receiver, Unit);

    fixture.sentinel.setSanctioned(Holder, false);
    vm.prank(Holder);
    assertTrue(fixture.wrapper.transfer(Receiver, 0), 'zero transfer');
    assertEq(fixture.wrapper.balanceOf(Receiver), 0, 'zero transfer balance');
  }

  function test_wrapperSanctionsAndInsolvencyFailClosedUntilRecovered() external {
    Fixture memory sanctionedFixture = _newFixture();
    _deposit(sanctionedFixture, Holder, 10 * Unit);
    sanctionedFixture.sentinel.setSanctioned(address(sanctionedFixture.wrapper), true);

    assertEq(sanctionedFixture.wrapper.maxDeposit(Holder), 0, 'wrapper max deposit');
    assertEq(sanctionedFixture.wrapper.maxMint(Holder), 0, 'wrapper max mint');
    assertEq(sanctionedFixture.wrapper.maxWithdraw(Holder), 0, 'wrapper max withdraw');
    assertEq(sanctionedFixture.wrapper.maxRedeem(Holder), 0, 'wrapper max redeem');
    _expectSanctioned(address(sanctionedFixture.wrapper));
    vm.prank(Holder);
    sanctionedFixture.wrapper.redeem(Unit, Holder, Holder);

    sanctionedFixture.sentinel.setSanctioned(address(sanctionedFixture.wrapper), false);
    vm.prank(Holder);
    sanctionedFixture.wrapper.redeem(10 * Unit, Holder, Holder);
    assertEq(sanctionedFixture.wrapper.totalSupply(), 0, 'wrapper recovery');

    Fixture memory insolventFixture = _newFixture();
    _deposit(insolventFixture, Holder, 10 * Unit);
    vm.prank(address(insolventFixture.wrapper));
    insolventFixture.market.transfer(Receiver, Unit);
    assertEq(insolventFixture.wrapper.maxDeposit(Holder), 0, 'insolvent max deposit');
    assertEq(insolventFixture.wrapper.maxMint(Holder), 0, 'insolvent max mint');
    assertEq(insolventFixture.wrapper.maxWithdraw(Holder), 0, 'insolvent max withdraw');
    assertEq(insolventFixture.wrapper.maxRedeem(Holder), 0, 'insolvent max redeem');
    vm.prank(Holder);
    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626Wrapper.InsolventWrapper.selector, 9 * Unit, 10 * Unit)
    );
    insolventFixture.wrapper.redeem(Unit, Holder, Holder);
  }

  function test_nukeCoordinatesMarketAndEscrowsSharesAtomically() external {
    Fixture memory fixture = _newFixture();

    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626Wrapper.AccountNotSanctioned.selector, Holder)
    );
    fixture.wrapper.nukeFromOrbit(Holder);

    fixture.sentinel.setSanctioned(Holder, true);
    bytes memory trailingCall = abi.encodePacked(
      abi.encodeWithSelector(fixture.wrapper.nukeFromOrbit.selector, Holder),
      hex'01020304'
    );
    (bool success, bytes memory returnData) = address(fixture.wrapper).call(trailingCall);
    assertTrue(success, string(returnData));
    assertEq(fixture.market.lastNukeCalldataHash(), keccak256(trailingCall), 'forwarded calldata');
    assertEq(fixture.sentinel.createEscrowCalls(), 0, 'empty escrow');

    fixture.sentinel.setSanctioned(Holder, false);
    _deposit(fixture, Holder, 10 * Unit);
    fixture.sentinel.setSanctioned(Holder, true);
    vm.expectEmit(true, true, false, true, address(fixture.wrapper));
    emit SanctionedAccountSharesSentToEscrow(Holder, fixture.sentinel.Escrow(), 10 * Unit);
    fixture.wrapper.nukeFromOrbit(Holder);
    address escrow = fixture.sentinel.Escrow();
    assertEq(fixture.wrapper.balanceOf(Holder), 0, 'nuked holder');
    assertEq(fixture.wrapper.balanceOf(escrow), 10 * Unit, 'escrow shares');
    assertEq(fixture.sentinel.createEscrowCalls(), 1, 'escrow calls');

    fixture.wrapper.nukeFromOrbit(Holder);
    assertEq(fixture.wrapper.balanceOf(escrow), 10 * Unit, 'idempotent escrow');
    assertEq(fixture.sentinel.createEscrowCalls(), 1, 'idempotent create');

    fixture.sentinel.setSanctioned(address(fixture.wrapper), true);
    vm.expectRevert(Wildcat4626Wrapper.CannotNukeWrapper.selector);
    fixture.wrapper.nukeFromOrbit(address(fixture.wrapper));

    Fixture memory revertingFixture = _newFixture();
    _deposit(revertingFixture, Holder, 10 * Unit);
    revertingFixture.sentinel.setSanctioned(Holder, true);
    revertingFixture.market.setNukeReverts(true);
    vm.expectRevert(WrapperMarketMock.NukeFailed.selector);
    revertingFixture.wrapper.nukeFromOrbit(Holder);
    assertEq(revertingFixture.wrapper.balanceOf(Holder), 10 * Unit, 'market revert rollback');
    assertEq(revertingFixture.sentinel.createEscrowCalls(), 0, 'market revert escrow');
  }

  function test_spoofedEscrowCannotReleaseSharesToSanctionedAccount() external {
    Fixture memory fixture = _newFixture();
    _deposit(fixture, Holder, 5 * Unit);
    WrapperSpoofEscrowMock spoof = WrapperSpoofEscrowMock(
      _deployCode('test/mocks/WrapperMocks.sol:WrapperSpoofEscrowMock', abi.encode(Borrower))
    );
    vm.prank(Holder);
    fixture.wrapper.transfer(address(spoof), Unit);
    fixture.sentinel.setSanctioned(Receiver, true);

    _expectSanctioned(Receiver);
    spoof.transferShares(fixture.wrapper, Receiver, Unit);
    assertEq(fixture.wrapper.balanceOf(address(spoof)), Unit, 'spoof rollback');
  }

  function testFuzz_sweepAuthorityTracksCurrentBorrowerAndValidatesRecipients(
    uint160 borrowerSeed,
    uint96 amountSeed
  ) external {
    Fixture memory fixture = _newFixture();
    address nextBorrower = address(uint160(bound(borrowerSeed, 1, type(uint160).max)));
    if (nextBorrower == Borrower) nextBorrower = address(uint160(Borrower) + 1);
    uint256 amount = bound(amountSeed, 1, type(uint96).max);
    WrapperPlainERC20Mock token = WrapperPlainERC20Mock(
      _deployCode('test/mocks/WrapperMocks.sol:WrapperPlainERC20Mock')
    );
    token.mint(address(fixture.wrapper), amount);

    vm.prank(Holder);
    vm.expectRevert(Wildcat4626Wrapper.NotMarketOwner.selector);
    fixture.wrapper.sweep(address(token), Holder);

    fixture.market.setBorrower(nextBorrower, Borrower);
    assertEq(fixture.wrapper.marketOwner(), nextBorrower, 'current borrower');
    vm.prank(Borrower);
    vm.expectRevert(Wildcat4626Wrapper.NotMarketOwner.selector);
    fixture.wrapper.sweep(address(token), Borrower);

    vm.prank(nextBorrower);
    vm.expectRevert(Wildcat4626Wrapper.ZeroAddress.selector);
    fixture.wrapper.sweep(address(0), nextBorrower);
    vm.prank(nextBorrower);
    vm.expectRevert(Wildcat4626Wrapper.ZeroAddress.selector);
    fixture.wrapper.sweep(address(token), address(0));

    fixture.sentinel.setSanctioned(Receiver, true);
    _expectSanctioned(Receiver);
    vm.prank(nextBorrower);
    fixture.wrapper.sweep(address(token), Receiver);
    fixture.sentinel.setSanctioned(Receiver, false);

    vm.expectEmit(true, true, false, true, address(fixture.wrapper));
    emit TokensSwept(address(token), Receiver, amount);
    vm.prank(nextBorrower);
    uint256 swept = fixture.wrapper.sweep(address(token), Receiver);
    assertEq(swept, amount, 'swept amount');
    assertEq(token.balanceOf(Receiver), amount, 'sweep recipient');
    assertEq(token.balanceOf(address(fixture.wrapper)), 0, 'wrapper token balance');

    vm.prank(nextBorrower);
    vm.expectRevert(Wildcat4626Wrapper.ZeroAssets.selector);
    fixture.wrapper.sweep(address(token), Receiver);
  }

  function testFuzz_marketSweepRemovesOnlySurplusAndPreservesEveryShareholder(
    uint96 donationSeed,
    uint96 scaleOffsetSeed
  ) external {
    Fixture memory fixture = _newFixture();
    uint256 donation = bound(donationSeed, Unit, 100e18);
    uint256 holderShares = _deposit(fixture, Holder, 20e18);
    uint256 receiverShares = _deposit(fixture, Receiver, 30e18);
    fixture.market.mint(Spender, donation);
    vm.prank(Spender);
    fixture.market.transfer(address(fixture.wrapper), donation);
    fixture.market.setScaleFactor(RAY + bound(scaleOffsetSeed, 0, 10 * RAY));

    uint256 scaledBefore = fixture.market.scaledBalanceOf(address(fixture.wrapper));
    uint256 strandedScaled = scaledBefore - fixture.wrapper.totalSupply();
    uint256 expectedSweep = MathUtils.mulDivUp(strandedScaled, fixture.market.scaleFactor(), RAY);
    uint256 borrowerScaledBefore = fixture.market.scaledBalanceOf(Borrower);
    vm.expectEmit(true, true, false, true, address(fixture.wrapper));
    emit TokensSwept(address(fixture.market), Borrower, expectedSweep);
    vm.prank(Borrower);
    uint256 swept = fixture.wrapper.sweep(address(fixture.market), Borrower);

    assertEq(swept, expectedSweep, 'market sweep amount');
    assertEq(
      fixture.market.scaledBalanceOf(Borrower),
      borrowerScaledBefore + strandedScaled,
      'market sweep recipient'
    );
    assertEq(
      fixture.market.scaledBalanceOf(address(fixture.wrapper)),
      fixture.wrapper.totalSupply(),
      'market sweep backing'
    );

    vm.prank(Borrower);
    vm.expectRevert(Wildcat4626Wrapper.ZeroAssets.selector);
    fixture.wrapper.sweep(address(fixture.market), Borrower);

    vm.prank(Holder);
    fixture.wrapper.redeem(holderShares, Holder, Holder);
    vm.prank(Receiver);
    fixture.wrapper.redeem(receiverShares, Receiver, Receiver);
    assertEq(fixture.wrapper.totalSupply(), 0, 'market sweep final supply');
    assertEq(
      fixture.market.scaledBalanceOf(address(fixture.wrapper)),
      0,
      'market sweep final backing'
    );
  }

  function test_marketSweepMismatchAndEmptyBackingRollBack() external {
    Fixture memory emptyFixture = _newFixture();
    vm.prank(Borrower);
    vm.expectRevert(Wildcat4626Wrapper.ZeroAssets.selector);
    emptyFixture.wrapper.sweep(address(emptyFixture.market), Borrower);

    Fixture memory mismatchFixture = _newFixture();
    mismatchFixture.market.mint(address(mismatchFixture.wrapper), 10 * Unit);
    mismatchFixture.market.setTransferSkew(-1);
    uint256 strandedScaled = mismatchFixture.market.scaledBalanceOf(
      address(mismatchFixture.wrapper)
    );
    vm.prank(Borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626Wrapper.SharesMismatch.selector,
        strandedScaled,
        strandedScaled - 1
      )
    );
    mismatchFixture.wrapper.sweep(address(mismatchFixture.market), Borrower);
    assertEq(
      mismatchFixture.market.scaledBalanceOf(address(mismatchFixture.wrapper)),
      strandedScaled,
      'market sweep rollback'
    );
  }
}
