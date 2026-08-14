// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../BaseMarketTest.sol';
import './MarketConfigMatrix.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';

contract StaticWithdrawalBatchAccount {
  function redeemAndQueue(
    Wildcat4626Wrapper wrapper,
    WildcatMarket market,
    uint256 shares,
    uint256 scaledAmount
  ) external returns (uint256 assets, uint32 expiry) {
    assets = wrapper.redeem(shares, address(this), address(this));
    expiry = market.queueWithdrawalScaled(scaledAmount);
  }
}

contract WrappedWithdrawalScaledQueueTest is BaseMarketTest {
  uint256 internal constant DirectScaledBalance = 10e18;
  uint256 internal constant WrappedShares = 25e18;

  Wildcat4626Wrapper internal wrapper;
  StaticWithdrawalBatchAccount internal account;

  function setUp() public override {
    super.setUp();

    wrapper = Wildcat4626Wrapper(wrapperFactory.createWrapper(address(market)));
    account = new StaticWithdrawalBatchAccount();
    _authorizeLender(address(account));

    asset.mint(address(account), DirectScaledBalance + WrappedShares);
    vm.startPrank(address(account));
    asset.approve(address(market), type(uint256).max);
    market.depositUpTo(DirectScaledBalance + WrappedShares);
    market.approve(address(wrapper), type(uint256).max);
    wrapper.deposit(WrappedShares, address(account));
    vm.stopPrank();

    assertEq(market.scaledBalanceOf(address(account)), DirectScaledBalance, 'direct balance');
    assertEq(wrapper.balanceOf(address(account)), WrappedShares, 'wrapper shares');
  }

  function test_staticBatchPreservesDirectScaledBalanceAfterInterest() external {
    bytes memory batchCalldata = abi.encodeCall(
      account.redeemAndQueue,
      (wrapper, market, WrappedShares, WrappedShares)
    );

    fastForward(30 days);
    (bool success, bytes memory result) = address(account).call(batchCalldata);
    assertTrue(success, string(result));
    (uint256 redeemedAssets, uint32 expiry) = abi.decode(result, (uint256, uint32));

    assertGt(redeemedAssets, WrappedShares, 'interest did not accrue');
    assertEq(wrapper.balanceOf(address(account)), 0, 'wrapper shares');
    assertEq(wrapper.totalSupply(), 0, 'wrapper supply');
    assertEq(market.scaledBalanceOf(address(wrapper)), 0, 'wrapper backing');
    assertEq(
      market.scaledBalanceOf(address(account)),
      DirectScaledBalance,
      'direct balance changed'
    );

    AccountWithdrawalStatus memory status = market.getAccountWithdrawalStatus(
      address(account),
      expiry
    );
    assertEq(status.scaledAmount, WrappedShares, 'queued scaled amount');
  }

  function test_staticBatchRollsBackRedemptionWhenQueueFails() external {
    fastForward(30 days);
    bytes32 stateBefore = keccak256(abi.encode(market.currentState()));

    vm.expectRevert(abi.encodePacked(uint32(Panic_ErrorSelector), Panic_Arithmetic));
    account.redeemAndQueue(
      wrapper,
      market,
      WrappedShares,
      DirectScaledBalance + WrappedShares + 1
    );

    assertEq(wrapper.balanceOf(address(account)), WrappedShares, 'wrapper shares changed');
    assertEq(wrapper.totalSupply(), WrappedShares, 'wrapper supply changed');
    assertEq(market.scaledBalanceOf(address(wrapper)), WrappedShares, 'wrapper backing changed');
    assertEq(
      market.scaledBalanceOf(address(account)),
      DirectScaledBalance,
      'direct balance changed'
    );
    assertEq(keccak256(abi.encode(market.currentState())), stateBefore, 'market state changed');
  }
}

contract ScaledWithdrawalQueueMarketParityTest is MarketConfigMatrix {
  function test_standardAndRevolvingMarketsQueueExactScaledAmount() external {
    DeployedCell memory standard = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard)
    );
    DeployedCell memory revolving = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Revolving)
    );

    _depositAs(standard, alice, 100e18);
    _depositAs(revolving, alice, 100e18);
    fastForward(30 days);

    uint256 scaledAmount = 25e18;
    vm.prank(alice);
    uint32 standardExpiry = standard.market.queueWithdrawalScaled(scaledAmount);
    vm.prank(alice);
    uint32 revolvingExpiry = revolving.market.queueWithdrawalScaled(scaledAmount);

    assertEq(standard.market.scaledBalanceOf(alice), 75e18, 'standard balance');
    assertEq(revolving.market.scaledBalanceOf(alice), 75e18, 'revolving balance');
    assertEq(
      standard.market.getAccountWithdrawalStatus(alice, standardExpiry).scaledAmount,
      scaledAmount,
      'standard queued amount'
    );
    assertEq(
      revolving.market.getAccountWithdrawalStatus(alice, revolvingExpiry).scaledAmount,
      scaledAmount,
      'revolving queued amount'
    );
  }
}
