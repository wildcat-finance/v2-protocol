// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'forge-std/Test.sol';
import { ERC20 } from 'solady/tokens/ERC20.sol';
import { MathUtils, RAY } from 'src/libraries/MathUtils.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { IWildcatMarketToken } from 'src/vault/Wildcat4626Wrapper.sol';
import { HooksConfig, EmptyHooksConfig } from 'src/types/HooksConfig.sol';

contract SettableSentinel {
  mapping(address => bool) public sanctioned;

  function isSanctioned(address, address account) external view returns (bool) {
    return sanctioned[account];
  }

  function sanction(address account) external {
    sanctioned[account] = true;
  }

  function unsanction(address account) external {
    sanctioned[account] = false;
  }

  function getEscrowAddress(address, address, address) external pure returns (address) {
    return address(0xE5C0);
  }
}

contract PlainMockERC20 {
  mapping(address => uint256) public balanceOf;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    uint256 balance = balanceOf[msg.sender];
    require(balance >= amount, 'BALANCE');
    unchecked {
      balanceOf[msg.sender] = balance - amount;
      balanceOf[to] += amount;
    }
    return true;
  }
}

contract GuardMockMarket is IWildcatMarketToken {
  using MathUtils for uint256;

  string public constant name = 'HEX6';
  string public constant symbol = 'HEX6';
  uint8 public immutable override decimals;

  uint256 public override scaleFactor = RAY;
  address public immutable override borrower;
  address public immutable override borrowerPrincipal;
  address public immutable override sentinel;
  address public immutable override wrapperFactory;
  uint256 internal _maxTotalSupply = type(uint128).max;
  int256 internal _transferSkew;

  mapping(address => uint256) internal _scaledBalances;
  mapping(address => mapping(address => uint256)) public override allowance;
  uint256 internal _scaledTotalSupply;

  constructor(uint8 decimals_, address borrower_, address sentinel_) {
    decimals = decimals_;
    borrower = borrower_;
    borrowerPrincipal = borrower_;
    sentinel = sentinel_;
    wrapperFactory = msg.sender;
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _scaledBalances[account].rayMul(scaleFactor);
  }

  function hooks() external view override returns (HooksConfig) {
    return EmptyHooksConfig.setHooksAddress(address(this));
  }

  function isMarketTransferRecipientAllowed(address market, address) external view returns (bool) {
    return market == address(this);
  }

  function totalSupply() external view returns (uint256) {
    return _scaledTotalSupply.rayMul(scaleFactor);
  }

  function scaledBalanceOf(address account) external view override returns (uint256) {
    return _scaledBalances[account];
  }

  function maxTotalSupply() external view override returns (uint256) {
    return _maxTotalSupply;
  }

  function setScaleFactor(uint256 newScaleFactor) external {
    scaleFactor = newScaleFactor;
  }

  function setMaxTotalSupply(uint256 newMaxTotalSupply) external {
    _maxTotalSupply = newMaxTotalSupply;
  }

  function setTransferSkew(int256 skewScaled) external {
    _transferSkew = skewScaled;
  }

  // Mirrors the real market's deposit scaling, including the null-mint revert.
  function mint(address to, uint256 assets) external {
    uint256 scaled = MathUtils.mulDiv(assets, RAY, scaleFactor);
    require(scaled != 0, 'SCALED_ZERO');
    require(scaled <= type(uint104).max, 'UINT104');
    _scaledBalances[to] += scaled;
    _scaledTotalSupply += scaled;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    _transfer(msg.sender, to, amount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    uint256 allowed = allowance[from][msg.sender];
    if (allowed != type(uint256).max) {
      require(allowed >= amount, 'ALLOWANCE');
      allowance[from][msg.sender] = allowed - amount;
    }
    _transfer(from, to, amount);
    return true;
  }

  // Mirrors WildcatMarketToken._transfer floor scaling, then lets tests skew
  // the actual scaled transfer amount to trip the wrapper's mismatch guards.
  function _transfer(address from, address to, uint256 amount) internal {
    uint256 scaled = MathUtils.mulDiv(amount, RAY, scaleFactor);
    require(scaled != 0, 'SCALED_ZERO');
    require(scaled <= type(uint104).max, 'UINT104');

    int256 adjustedScaled = int256(scaled) + _transferSkew;
    require(adjustedScaled > 0, 'SCALED_ZERO');
    uint256 actualScaled = uint256(adjustedScaled);
    require(actualScaled <= type(uint104).max, 'UINT104');

    uint256 fromBalance = _scaledBalances[from];
    require(fromBalance >= actualScaled, 'BALANCE');
    unchecked {
      _scaledBalances[from] = fromBalance - actualScaled;
      _scaledBalances[to] += actualScaled;
    }
  }
}

contract Wildcat4626WrapperGuardsTest is Test {
  using MathUtils for uint256;

  event TokensSwept(address indexed token, address indexed to, uint256 amount);

  SettableSentinel internal sanctionsSentinel;
  GuardMockMarket internal market;
  Wildcat4626Wrapper internal wrapper;

  address internal constant HOLDER = address(0xA11CE);
  address internal constant RECEIVER = address(0xB0B);
  address internal constant SPENDER = address(0x5EED);
  address internal constant BORROWER = address(0xB0123123);

  uint256 internal constant UNIT = 1e6;

  function setUp() external {
    sanctionsSentinel = new SettableSentinel();
    market = new GuardMockMarket(6, BORROWER, address(sanctionsSentinel));
    wrapper = new Wildcat4626Wrapper(address(market));
  }

  function _fundAndApprove(address account, uint256 assets) internal {
    market.mint(account, assets);
    vm.prank(account);
    market.approve(address(wrapper), type(uint256).max);
  }

  function _deposit(address account, uint256 assets) internal returns (uint256 shares) {
    _fundAndApprove(account, assets);
    vm.prank(account);
    shares = wrapper.deposit(assets, account);
  }

  function _expectSanctioned(address account) internal {
    vm.expectRevert(abi.encodeWithSelector(Wildcat4626Wrapper.SanctionedAccount.selector, account));
  }

  function _assertMintSucceedsAtScale(uint256 scaleFactor, uint256 shares) internal {
    GuardMockMarket localMarket = new GuardMockMarket(6, BORROWER, address(sanctionsSentinel));
    Wildcat4626Wrapper localWrapper = new Wildcat4626Wrapper(address(localMarket));
    localMarket.setScaleFactor(scaleFactor);

    uint256 expectedAssets = MathUtils.mulDivUp(shares, scaleFactor, RAY);
    localMarket.mint(HOLDER, expectedAssets);
    vm.prank(HOLDER);
    localMarket.approve(address(localWrapper), type(uint256).max);

    vm.prank(HOLDER);
    uint256 assets = localWrapper.mint(shares, HOLDER);

    assertEq(assets, expectedAssets, 'assets');
    assertEq(localWrapper.balanceOf(HOLDER), shares, 'shares');
    assertEq(localMarket.scaledBalanceOf(address(localWrapper)), shares, 'scaled balance');
  }

  function test_constructor_revertsForZeroMarket() external {
    vm.expectRevert(Wildcat4626Wrapper.ZeroAddress.selector);
    new Wildcat4626Wrapper(address(0));
  }

  function test_constructor_revertsForZeroBorrower() external {
    GuardMockMarket badMarket = new GuardMockMarket(6, address(0), address(sanctionsSentinel));

    vm.expectRevert(Wildcat4626Wrapper.ZeroAddress.selector);
    new Wildcat4626Wrapper(address(badMarket));
  }

  function test_constructor_revertsForZeroSentinel() external {
    GuardMockMarket badMarket = new GuardMockMarket(6, BORROWER, address(0));

    vm.expectRevert(Wildcat4626Wrapper.ZeroAddress.selector);
    new Wildcat4626Wrapper(address(badMarket));
  }

  function test_constructor_rejectsMalformedDecimals() external {
    GuardMockMarket badMarket = new GuardMockMarket(6, BORROWER, address(sanctionsSentinel));
    bytes memory callData = abi.encodeWithSignature('decimals()');

    vm.mockCall(address(badMarket), callData, hex'01');
    vm.expectRevert();
    new Wildcat4626Wrapper(address(badMarket));
    vm.clearMockedCalls();

    vm.mockCall(address(badMarket), callData, abi.encode(uint256(type(uint8).max) + 1));
    vm.expectRevert();
    new Wildcat4626Wrapper(address(badMarket));
  }

  function test_metadata_usesSixDecimalMarket() external view {
    assertEq(wrapper.decimals(), 6, 'decimals');
    assertEq(wrapper.name(), 'HEX6 [4626 Vault Shares]', 'name');
    assertEq(wrapper.symbol(), 'v-HEX6', 'symbol');
    assertEq(wrapper.market(), address(market), 'market');
    assertEq(wrapper.asset(), address(market), 'asset');
  }

  function test_rates_equalRayAtInitialScale() external view {
    uint256 assetsPerShare = wrapper.assetsPerShareRay();
    uint256 sharesPerAsset = wrapper.sharesPerAssetRay();
    uint256 nearInverse = MathUtils.mulDiv(assetsPerShare, sharesPerAsset, RAY);

    assertEq(assetsPerShare, RAY, 'assets per share');
    assertEq(sharesPerAsset, RAY, 'shares per asset');
    assertEq(nearInverse, RAY, 'inverse');
  }

  function test_rates_fractionalScaleUseFloorInverse() external {
    uint256 scaleFactor = RAY + RAY / 3;
    market.setScaleFactor(scaleFactor);

    uint256 expectedSharesPerAsset = MathUtils.mulDiv(RAY, RAY, scaleFactor);
    uint256 assetsPerShare = wrapper.assetsPerShareRay();
    uint256 sharesPerAsset = wrapper.sharesPerAssetRay();
    uint256 nearInverse = MathUtils.mulDiv(assetsPerShare, sharesPerAsset, RAY);

    assertEq(assetsPerShare, scaleFactor, 'assets per share');
    assertEq(sharesPerAsset, expectedSharesPerAsset, 'shares per asset');
    assertLe(nearInverse, RAY, 'inverse upper bound');
    assertEq(nearInverse, RAY - 1, 'inverse floor');
  }

  function test_zeroInput_viewsReturnZero() external view {
    assertEq(wrapper.convertToShares(0), 0, 'convertToShares');
    assertEq(wrapper.convertToAssets(0), 0, 'convertToAssets');
    assertEq(wrapper.previewMint(0), 0, 'previewMint');
    assertEq(wrapper.previewWithdraw(0), 0, 'previewWithdraw');
  }

  function test_zeroInput_depositRevertsZeroAssets() external {
    vm.expectRevert(Wildcat4626Wrapper.ZeroAssets.selector);
    vm.prank(HOLDER);
    wrapper.deposit(0, RECEIVER);
  }

  function test_zeroInput_mintRevertsZeroShares() external {
    vm.expectRevert(Wildcat4626Wrapper.ZeroShares.selector);
    vm.prank(HOLDER);
    wrapper.mint(0, RECEIVER);
  }

  function test_zeroInput_withdrawRevertsZeroAssets() external {
    vm.expectRevert(Wildcat4626Wrapper.ZeroAssets.selector);
    vm.prank(HOLDER);
    wrapper.withdraw(0, RECEIVER, HOLDER);
  }

  function test_zeroInput_redeemRevertsZeroShares() external {
    vm.expectRevert(Wildcat4626Wrapper.ZeroShares.selector);
    vm.prank(HOLDER);
    wrapper.redeem(0, RECEIVER, HOLDER);
  }

  function test_sanctions_maxValuesZeroForSanctionedAccount() external {
    uint256 shares = _deposit(HOLDER, 10 * UNIT);
    uint256 expectedMaxDeposit = type(uint128).max - wrapper.totalAssets();
    uint256 expectedMaxWithdraw = MathUtils.mulDivUp(shares + 1, RAY, RAY) - 1;

    assertEq(wrapper.maxDeposit(HOLDER), expectedMaxDeposit, 'unsanctioned maxDeposit');
    assertEq(wrapper.maxMint(HOLDER), expectedMaxDeposit, 'unsanctioned maxMint');
    assertEq(wrapper.maxWithdraw(HOLDER), expectedMaxWithdraw, 'unsanctioned maxWithdraw');
    assertEq(wrapper.maxRedeem(HOLDER), shares, 'unsanctioned maxRedeem');

    sanctionsSentinel.sanction(HOLDER);

    assertEq(wrapper.maxDeposit(HOLDER), 0, 'sanctioned maxDeposit');
    assertEq(wrapper.maxMint(HOLDER), 0, 'sanctioned maxMint');
    assertEq(wrapper.maxWithdraw(HOLDER), 0, 'sanctioned maxWithdraw');
    assertEq(wrapper.maxRedeem(HOLDER), 0, 'sanctioned maxRedeem');
  }

  function test_sanctionsResponseValidation() external {
    bytes memory callData = abi.encodeWithSignature(
      'isSanctioned(address,address)',
      BORROWER,
      HOLDER
    );
    address sentinel = address(sanctionsSentinel);

    vm.mockCall(sentinel, callData, hex'01');
    vm.expectRevert();
    wrapper.maxRedeem(HOLDER);
    vm.clearMockedCalls();

    vm.mockCall(sentinel, callData, abi.encode(uint256(2)));
    vm.expectRevert();
    wrapper.maxRedeem(HOLDER);
    vm.clearMockedCalls();

    bytes memory revertData = hex'deadbeef';
    vm.mockCallRevert(sentinel, callData, revertData);
    vm.expectRevert(revertData);
    wrapper.maxRedeem(HOLDER);
    vm.clearMockedCalls();

    vm.mockCall(sentinel, callData, bytes.concat(abi.encode(true), hex'deadbeef'));
    assertEq(wrapper.maxRedeem(HOLDER), 0, 'sanctioned max redeem');
  }

  function test_marketWordResponseValidation() external {
    bytes memory callData = abi.encodeWithSignature('scaleFactor()');
    address marketAddress = address(market);

    vm.mockCall(marketAddress, callData, hex'01');
    vm.expectRevert();
    wrapper.convertToShares(UNIT);
    vm.clearMockedCalls();

    bytes memory revertData = hex'deadbeef';
    vm.mockCallRevert(marketAddress, callData, revertData);
    vm.expectRevert(revertData);
    wrapper.convertToShares(UNIT);
    vm.clearMockedCalls();

    vm.mockCall(marketAddress, callData, bytes.concat(abi.encode(RAY), hex'deadbeef'));
    assertEq(wrapper.convertToShares(UNIT), UNIT, 'shares');
  }

  function test_marketAccountWordResponseValidation() external {
    bytes memory callData = abi.encodeWithSignature('balanceOf(address)', address(wrapper));
    address marketAddress = address(market);

    vm.mockCall(marketAddress, callData, hex'01');
    vm.expectRevert();
    wrapper.totalAssets();
    vm.clearMockedCalls();

    bytes memory revertData = hex'deadbeef';
    vm.mockCallRevert(marketAddress, callData, revertData);
    vm.expectRevert(revertData);
    wrapper.totalAssets();
    vm.clearMockedCalls();

    vm.mockCall(marketAddress, callData, bytes.concat(abi.encode(UNIT), hex'deadbeef'));
    assertEq(wrapper.totalAssets(), UNIT, 'assets');
  }

  function test_marketAddressResponseValidation() external {
    bytes memory callData = abi.encodeWithSignature('borrower()');
    address marketAddress = address(market);

    vm.mockCall(marketAddress, callData, hex'01');
    vm.expectRevert();
    wrapper.marketOwner();
    vm.clearMockedCalls();

    vm.mockCall(marketAddress, callData, abi.encode((uint256(1) << 160) | uint160(BORROWER)));
    vm.expectRevert();
    wrapper.marketOwner();
    vm.clearMockedCalls();

    bytes memory revertData = hex'deadbeef';
    vm.mockCallRevert(marketAddress, callData, revertData);
    vm.expectRevert(revertData);
    wrapper.marketOwner();
    vm.clearMockedCalls();

    vm.mockCall(marketAddress, callData, bytes.concat(abi.encode(BORROWER), hex'deadbeef'));
    assertEq(wrapper.marketOwner(), BORROWER, 'borrower');
  }

  function test_zeroAccountSkipsBorrowerPrincipalProbe() external {
    vm.mockCallRevert(
      address(market),
      abi.encodeWithSignature('borrowerPrincipal()'),
      hex'deadbeef'
    );
    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626Wrapper.AccountNotSanctioned.selector, address(0))
    );
    wrapper.nukeFromOrbit(address(0));
  }

  function test_transferPolicyResponseValidation() external {
    bytes memory callData = abi.encodeWithSignature(
      'isMarketTransferRecipientAllowed(address,address)',
      address(market),
      address(wrapper)
    );
    address policy = address(market);

    vm.mockCall(policy, callData, hex'01');
    assertEq(wrapper.maxDeposit(HOLDER), 0, 'short response');
    vm.clearMockedCalls();

    vm.mockCall(policy, callData, abi.encode(uint256(2)));
    assertEq(wrapper.maxDeposit(HOLDER), 0, 'dirty response');
    vm.clearMockedCalls();

    vm.mockCallRevert(policy, callData, hex'deadbeef');
    assertEq(wrapper.maxDeposit(HOLDER), 0, 'reverting response');
    vm.clearMockedCalls();

    vm.mockCall(policy, callData, bytes.concat(abi.encode(true), hex'deadbeef'));
    assertGt(wrapper.maxDeposit(HOLDER), 0, 'valid response');
  }

  function test_escrowAddressResponseValidation() external {
    _deposit(HOLDER, 10 * UNIT);
    sanctionsSentinel.sanction(HOLDER);
    address escrow = address(0xE5C0);
    address sentinel = address(sanctionsSentinel);
    bytes memory callData = abi.encodeWithSignature(
      'getEscrowAddress(address,address,address)',
      BORROWER,
      HOLDER,
      address(wrapper)
    );

    vm.mockCall(sentinel, callData, hex'01');
    vm.prank(HOLDER);
    vm.expectRevert();
    wrapper.transfer(escrow, UNIT);
    vm.clearMockedCalls();

    vm.mockCall(sentinel, callData, abi.encode((uint256(1) << 160) | uint160(escrow)));
    vm.prank(HOLDER);
    vm.expectRevert();
    wrapper.transfer(escrow, UNIT);
    vm.clearMockedCalls();

    bytes memory revertData = hex'deadbeef';
    vm.mockCallRevert(sentinel, callData, revertData);
    vm.prank(HOLDER);
    vm.expectRevert(revertData);
    wrapper.transfer(escrow, UNIT);
    vm.clearMockedCalls();

    vm.mockCall(sentinel, callData, bytes.concat(abi.encode(escrow), hex'deadbeef'));
    vm.prank(HOLDER);
    wrapper.transfer(escrow, UNIT);
    assertEq(wrapper.balanceOf(escrow), UNIT, 'escrow shares');
  }

  function test_sanctions_depositRevertsForSanctionedCaller() external {
    _fundAndApprove(HOLDER, 2 * UNIT);
    sanctionsSentinel.sanction(HOLDER);

    _expectSanctioned(HOLDER);
    vm.prank(HOLDER);
    wrapper.deposit(UNIT, RECEIVER);
  }

  function test_sanctions_mintRevertsForSanctionedCaller() external {
    _fundAndApprove(HOLDER, 2 * UNIT);
    sanctionsSentinel.sanction(HOLDER);

    _expectSanctioned(HOLDER);
    vm.prank(HOLDER);
    wrapper.mint(UNIT, RECEIVER);
  }

  function test_sanctions_withdrawRevertsForSanctionedCaller() external {
    _deposit(HOLDER, 10 * UNIT);
    vm.prank(HOLDER);
    wrapper.approve(SPENDER, UNIT);
    sanctionsSentinel.sanction(SPENDER);

    _expectSanctioned(SPENDER);
    vm.prank(SPENDER);
    wrapper.withdraw(UNIT, RECEIVER, HOLDER);
  }

  function test_sanctions_withdrawRevertsForSanctionedReceiver() external {
    _deposit(HOLDER, 10 * UNIT);
    sanctionsSentinel.sanction(RECEIVER);

    _expectSanctioned(RECEIVER);
    vm.prank(HOLDER);
    wrapper.withdraw(UNIT, RECEIVER, HOLDER);
  }

  function test_sanctions_redeemRevertsForSanctionedCaller() external {
    _deposit(HOLDER, 10 * UNIT);
    vm.prank(HOLDER);
    wrapper.approve(SPENDER, UNIT);
    sanctionsSentinel.sanction(SPENDER);

    _expectSanctioned(SPENDER);
    vm.prank(SPENDER);
    wrapper.redeem(UNIT, RECEIVER, HOLDER);
  }

  function test_sanctions_redeemRevertsForSanctionedReceiver() external {
    _deposit(HOLDER, 10 * UNIT);
    sanctionsSentinel.sanction(RECEIVER);

    _expectSanctioned(RECEIVER);
    vm.prank(HOLDER);
    wrapper.redeem(UNIT, RECEIVER, HOLDER);
  }

  function test_sanctions_shareTransferRevertsThenSucceedsAfterUnsanction() external {
    _deposit(HOLDER, 10 * UNIT);
    sanctionsSentinel.sanction(RECEIVER);

    _expectSanctioned(RECEIVER);
    vm.prank(HOLDER);
    wrapper.transfer(RECEIVER, UNIT);

    sanctionsSentinel.unsanction(RECEIVER);

    vm.prank(HOLDER);
    bool success = wrapper.transfer(RECEIVER, UNIT);

    assertTrue(success, 'transfer success');
    assertEq(wrapper.balanceOf(HOLDER), 9 * UNIT, 'holder shares');
    assertEq(wrapper.balanceOf(RECEIVER), UNIT, 'receiver shares');
  }

  function test_sanctions_shareTransferRevertsForSanctionedSender() external {
    _deposit(HOLDER, 10 * UNIT);
    sanctionsSentinel.sanction(HOLDER);

    _expectSanctioned(HOLDER);
    vm.prank(HOLDER);
    wrapper.transfer(RECEIVER, UNIT);
  }

  function test_sanctions_zeroShareTransferSucceedsWithoutBalanceChanges() external {
    vm.prank(HOLDER);
    bool success = wrapper.transfer(RECEIVER, 0);

    assertTrue(success, 'transfer success');
    assertEq(wrapper.balanceOf(HOLDER), 0, 'holder shares');
    assertEq(wrapper.balanceOf(RECEIVER), 0, 'receiver shares');
  }

  function test_sanctions_sweepRevertsForSanctionedRecipient() external {
    PlainMockERC20 stray = new PlainMockERC20();
    stray.mint(address(wrapper), UNIT);
    sanctionsSentinel.sanction(RECEIVER);

    _expectSanctioned(RECEIVER);
    vm.prank(BORROWER);
    wrapper.sweep(address(stray), RECEIVER);
  }

  function test_cap_heldAtCapZerosLimitsAndExecutionReverts() external {
    _deposit(HOLDER, 10 * UNIT);
    uint256 held = wrapper.totalAssets();
    market.setMaxTotalSupply(held);

    assertEq(wrapper.maxDeposit(HOLDER), 0, 'maxDeposit');
    assertEq(wrapper.maxMint(HOLDER), 0, 'maxMint');

    vm.expectRevert(Wildcat4626Wrapper.CapExceeded.selector);
    vm.prank(HOLDER);
    wrapper.deposit(UNIT, HOLDER);

    vm.expectRevert(Wildcat4626Wrapper.CapExceeded.selector);
    vm.prank(HOLDER);
    wrapper.mint(UNIT, HOLDER);
  }

  function test_cap_oneWeiCapacityRoundsToZeroShares() external {
    market.setScaleFactor(RAY + RAY / 2);
    market.setMaxTotalSupply(1);

    assertEq(wrapper.maxDeposit(HOLDER), 0, 'maxDeposit');
    assertEq(wrapper.maxMint(HOLDER), 0, 'maxMint');

    vm.expectRevert(Wildcat4626Wrapper.ZeroShares.selector);
    vm.prank(HOLDER);
    wrapper.deposit(1, HOLDER);
  }

  function test_cap_mintRevertsWhenSharesExceedFloorCapacity() external {
    market.setScaleFactor(RAY + RAY / 2);
    market.setMaxTotalSupply(3);

    assertEq(wrapper.maxMint(HOLDER), 2, 'maxMint');

    vm.expectRevert(Wildcat4626Wrapper.CapExceeded.selector);
    vm.prank(HOLDER);
    wrapper.mint(3, HOLDER);
  }

  function test_cap_depositRevertsWhenAssetsExceedLimit() external {
    market.setMaxTotalSupply(10 * UNIT);

    vm.expectRevert(Wildcat4626Wrapper.CapExceeded.selector);
    vm.prank(HOLDER);
    wrapper.deposit(10 * UNIT + 1, HOLDER);
  }

  function test_cap_depositMaxDepositSucceedsAtFractionalScale() external {
    market.setScaleFactor(RAY + RAY / 2);
    market.setMaxTotalSupply(15 * UNIT);
    uint256 maxDeposit = wrapper.maxDeposit(HOLDER);
    uint256 expectedShares = MathUtils.mulDiv(maxDeposit, RAY, market.scaleFactor());
    _fundAndApprove(HOLDER, maxDeposit);

    vm.prank(HOLDER);
    uint256 shares = wrapper.deposit(maxDeposit, HOLDER);

    assertEq(maxDeposit, 15 * UNIT, 'maxDeposit');
    assertEq(shares, expectedShares, 'shares');
    assertEq(wrapper.balanceOf(HOLDER), 10 * UNIT, 'holder shares');
    assertEq(wrapper.totalAssets(), 15 * UNIT, 'total assets');
  }

  function test_cap_mintMaxMintSucceedsAtFractionalScale() external {
    market.setScaleFactor(RAY + RAY / 2);
    market.setMaxTotalSupply(15 * UNIT);
    uint256 maxMint = wrapper.maxMint(HOLDER);
    uint256 expectedAssets = MathUtils.mulDivUp(maxMint, market.scaleFactor(), RAY);
    _fundAndApprove(HOLDER, expectedAssets);

    vm.prank(HOLDER);
    uint256 assets = wrapper.mint(maxMint, HOLDER);

    assertEq(maxMint, 10 * UNIT, 'maxMint');
    assertEq(assets, expectedAssets, 'assets');
    assertEq(wrapper.balanceOf(HOLDER), 10 * UNIT, 'holder shares');
    assertEq(wrapper.totalAssets(), 15 * UNIT, 'total assets');
  }

  function test_sharesMismatch_depositRevertsWhenTransferCreditsExtraScaled() external {
    uint256 assets = 10 * UNIT;
    uint256 expectedShares = MathUtils.mulDiv(assets, RAY, market.scaleFactor());
    _fundAndApprove(HOLDER, assets + 1);
    market.setTransferSkew(1);

    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626Wrapper.SharesMismatch.selector,
        expectedShares,
        expectedShares + 1
      )
    );
    vm.prank(HOLDER);
    wrapper.deposit(assets, HOLDER);
  }

  function test_sharesMismatch_mintRevertsWhenTransferCreditsExtraScaled() external {
    uint256 shares = 10 * UNIT;
    uint256 assets = MathUtils.mulDivUp(shares, market.scaleFactor(), RAY);
    _fundAndApprove(HOLDER, assets + 1);
    market.setTransferSkew(1);

    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626Wrapper.SharesMismatch.selector, shares, shares + 1)
    );
    vm.prank(HOLDER);
    wrapper.mint(shares, HOLDER);
  }

  function test_sharesMismatch_withdrawRevertsWhenTransferDebitsTooLittleScaled() external {
    _deposit(HOLDER, 10 * UNIT);
    market.setTransferSkew(-1);
    uint256 assets = 4 * UNIT;
    uint256 expectedShares = MathUtils.mulDiv(assets, RAY, market.scaleFactor());

    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626Wrapper.SharesMismatch.selector,
        expectedShares,
        expectedShares - 1
      )
    );
    vm.prank(HOLDER);
    wrapper.withdraw(assets, RECEIVER, HOLDER);
  }

  function test_sharesMismatch_redeemRevertsWhenTransferDebitsTooLittleScaled() external {
    _deposit(HOLDER, 10 * UNIT);
    market.setTransferSkew(-1);
    uint256 shares = 4 * UNIT;

    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626Wrapper.SharesMismatch.selector, shares, shares - 1)
    );
    vm.prank(HOLDER);
    wrapper.redeem(shares, RECEIVER, HOLDER);
  }

  function test_sharesMismatch_sweepRevertsWhenTransferDebitsTooLittleScaled() external {
    uint256 strandedAssets = 10 * UNIT;
    market.mint(address(wrapper), strandedAssets);
    market.setTransferSkew(-1);
    uint256 strandedScaled = market.scaledBalanceOf(address(wrapper));

    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626Wrapper.SharesMismatch.selector,
        strandedScaled,
        strandedScaled - 1
      )
    );
    vm.prank(BORROWER);
    wrapper.sweep(address(market), BORROWER);
  }

  function test_sharesMismatch_mintRoundTripIdentityHoldsForValidFractionalScales() external {
    // The mint pre-transfer guard is unreachable for scaleFactor >= RAY:
    // floor(ceil(shares * scaleFactor / RAY) * RAY / scaleFactor) == shares.
    _assertMintSucceedsAtScale(RAY + 1, 7 * UNIT + 13);
    _assertMintSucceedsAtScale(RAY + RAY / 10, 7 * UNIT + 13);
    _assertMintSucceedsAtScale(RAY + RAY / 3, 7 * UNIT + 13);
  }

  function test_sweep_revertsForNonOwner() external {
    vm.expectRevert(Wildcat4626Wrapper.NotMarketOwner.selector);
    vm.prank(HOLDER);
    wrapper.sweep(address(market), HOLDER);
  }

  function test_sweep_revertsForZeroToken() external {
    vm.expectRevert(Wildcat4626Wrapper.ZeroAddress.selector);
    vm.prank(BORROWER);
    wrapper.sweep(address(0), BORROWER);
  }

  function test_sweep_revertsForZeroRecipient() external {
    vm.expectRevert(Wildcat4626Wrapper.ZeroAddress.selector);
    vm.prank(BORROWER);
    wrapper.sweep(address(market), address(0));
  }

  function test_sweep_marketTokenRevertsWithZeroStrandedBalance() external {
    vm.expectRevert(Wildcat4626Wrapper.ZeroAssets.selector);
    vm.prank(BORROWER);
    wrapper.sweep(address(market), BORROWER);
  }

  function test_sweep_unrelatedTokenRevertsWithZeroBalance() external {
    PlainMockERC20 stray = new PlainMockERC20();

    vm.expectRevert(Wildcat4626Wrapper.ZeroAssets.selector);
    vm.prank(BORROWER);
    wrapper.sweep(address(stray), BORROWER);
  }

  function test_sweep_marketTokenSweepsStrandedBalanceAndEmits() external {
    market.setScaleFactor(RAY + RAY / 2);
    uint256 strandedAssets = 15 * UNIT;
    market.mint(address(wrapper), strandedAssets);
    uint256 strandedScaled = market.scaledBalanceOf(address(wrapper));
    uint256 expectedAmount = MathUtils.mulDivUp(strandedScaled, market.scaleFactor(), RAY);

    vm.expectEmit(true, true, false, true, address(wrapper));
    emit TokensSwept(address(market), BORROWER, expectedAmount);
    vm.prank(BORROWER);
    uint256 swept = wrapper.sweep(address(market), BORROWER);

    assertEq(swept, expectedAmount, 'swept');
    assertEq(expectedAmount, strandedAssets, 'amount');
    assertEq(market.balanceOf(BORROWER), strandedAssets, 'borrower balance');
    assertEq(market.scaledBalanceOf(address(wrapper)), 0, 'wrapper scaled');
  }

  function test_sweep_unrelatedTokenSweepsBalanceAndEmits() external {
    PlainMockERC20 stray = new PlainMockERC20();
    uint256 amount = 42 * UNIT;
    stray.mint(HOLDER, amount);
    vm.prank(HOLDER);
    stray.transfer(address(wrapper), amount);

    vm.expectEmit(true, true, false, true, address(wrapper));
    emit TokensSwept(address(stray), BORROWER, amount);
    vm.prank(BORROWER);
    uint256 swept = wrapper.sweep(address(stray), BORROWER);

    assertEq(swept, amount, 'swept');
    assertEq(stray.balanceOf(BORROWER), amount, 'borrower balance');
    assertEq(stray.balanceOf(address(wrapper)), 0, 'wrapper balance');
  }

  function test_allowance_withdrawWithExactAllowanceSucceedsAndSpendsToZero() external {
    _deposit(HOLDER, 10 * UNIT);
    vm.prank(HOLDER);
    wrapper.approve(SPENDER, 4 * UNIT);

    vm.prank(SPENDER);
    uint256 burned = wrapper.withdraw(4 * UNIT, RECEIVER, HOLDER);

    assertEq(burned, 4 * UNIT, 'burned');
    assertEq(wrapper.allowance(HOLDER, SPENDER), 0, 'allowance');
    assertEq(wrapper.balanceOf(HOLDER), 6 * UNIT, 'holder shares');
    assertEq(market.balanceOf(RECEIVER), 4 * UNIT, 'receiver assets');
  }

  function test_allowance_withdrawWithMaxAllowanceKeepsAllowance() external {
    _deposit(HOLDER, 10 * UNIT);
    vm.prank(HOLDER);
    wrapper.approve(SPENDER, type(uint256).max);

    vm.prank(SPENDER);
    uint256 burned = wrapper.withdraw(4 * UNIT, RECEIVER, HOLDER);

    assertEq(burned, 4 * UNIT, 'burned');
    assertEq(wrapper.allowance(HOLDER, SPENDER), type(uint256).max, 'allowance');
    assertEq(wrapper.balanceOf(HOLDER), 6 * UNIT, 'holder shares');
  }

  function test_allowance_withdrawWithInsufficientAllowanceRevertsSoladyERC20() external {
    _deposit(HOLDER, 10 * UNIT);
    vm.prank(HOLDER);
    wrapper.approve(SPENDER, 4 * UNIT - 1);

    // Solady ERC20._spendAllowance uses InsufficientAllowance().
    vm.expectRevert(ERC20.InsufficientAllowance.selector);
    vm.prank(SPENDER);
    wrapper.withdraw(4 * UNIT, RECEIVER, HOLDER);
  }

  function test_allowance_redeemWithExactAllowanceSucceedsAndSpendsToZero() external {
    _deposit(HOLDER, 10 * UNIT);
    vm.prank(HOLDER);
    wrapper.approve(SPENDER, 4 * UNIT);

    vm.prank(SPENDER);
    uint256 assets = wrapper.redeem(4 * UNIT, RECEIVER, HOLDER);

    assertEq(assets, 4 * UNIT, 'assets');
    assertEq(wrapper.allowance(HOLDER, SPENDER), 0, 'allowance');
    assertEq(wrapper.balanceOf(HOLDER), 6 * UNIT, 'holder shares');
    assertEq(market.balanceOf(RECEIVER), 4 * UNIT, 'receiver assets');
  }

  function test_allowance_redeemWithMaxAllowanceKeepsAllowance() external {
    _deposit(HOLDER, 10 * UNIT);
    vm.prank(HOLDER);
    wrapper.approve(SPENDER, type(uint256).max);

    vm.prank(SPENDER);
    uint256 assets = wrapper.redeem(4 * UNIT, RECEIVER, HOLDER);

    assertEq(assets, 4 * UNIT, 'assets');
    assertEq(wrapper.allowance(HOLDER, SPENDER), type(uint256).max, 'allowance');
    assertEq(wrapper.balanceOf(HOLDER), 6 * UNIT, 'holder shares');
  }

  function test_allowance_redeemWithInsufficientAllowanceRevertsSoladyERC20() external {
    _deposit(HOLDER, 10 * UNIT);
    vm.prank(HOLDER);
    wrapper.approve(SPENDER, 4 * UNIT - 1);

    // Solady ERC20._spendAllowance uses InsufficientAllowance().
    vm.expectRevert(ERC20.InsufficientAllowance.selector);
    vm.prank(SPENDER);
    wrapper.redeem(4 * UNIT, RECEIVER, HOLDER);
  }

  // ------------------------- Residual branch pins -------------------------- //

  /// @dev maxWithdraw for an unsanctioned account with no shares is zero.
  function test_maxWithdraw_zeroBalanceReturnsZero() external view {
    assertEq(wrapper.maxWithdraw(RECEIVER), 0, 'maxWithdraw for empty account');
  }

  /// @dev A withdrawal amount that floors to zero shares reverts ZeroShares
  ///      (distinct from the zero-assets guard).
  function test_withdraw_dustAmountFloorsToZeroShares() external {
    market.setScaleFactor(RAY + RAY / 2);
    _deposit(HOLDER, 10 * UNIT);
    vm.expectRevert(Wildcat4626Wrapper.ZeroShares.selector);
    vm.prank(HOLDER);
    wrapper.withdraw(1, HOLDER, HOLDER);
  }

  /// @dev Zero-amount share transfers take _beforeTokenTransfer's early
  ///      return and succeed (after the sanctions checks).
  function test_shareTransfer_zeroAmountSucceeds() external {
    _deposit(HOLDER, 10 * UNIT);
    vm.prank(HOLDER);
    assertTrue(wrapper.transfer(RECEIVER, 0), 'zero-amount transfer failed');
    assertEq(wrapper.balanceOf(RECEIVER), 0, 'receiver balance changed');
  }
}
