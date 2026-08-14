// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { Test as ForgeTest } from 'forge-std/Test.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

import '../BaseMarketTest.sol';
import { fastForward } from '../helpers/VmUtils.sol';
import 'src/access/BaseAccessControls.sol';
import 'src/providers/ERC20RoleProvider.sol';
import 'src/providers/IERC20RoleProvider.sol';

contract RevertingERC20BalanceToken {
  function balanceOf(address) external pure returns (uint256) {
    revert('BALANCE_REVERTED');
  }
}

contract ERC20RoleProviderPropertyTest is ForgeTest {
  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);

  function setUp() external {
    vm.warp(1_714_737_030);
  }

  function testFuzz_credentialMatchesCurrentBalance(
    uint96 balanceSeed,
    uint96 minimumBalanceSeed
  ) external {
    uint256 balance = uint256(balanceSeed);
    MockERC20 token = new MockERC20('Gate', 'GATE', 18);
    token.mint(Holder, balance);
    uint256 minimumBalance = bound(uint256(minimumBalanceSeed), 1, balance + 1);
    ERC20RoleProvider provider = new ERC20RoleProvider(address(token), minimumBalance);
    uint32 expectedCredential = balance >= minimumBalance ? uint32(block.timestamp) : 0;

    assertEq(provider.getCredential(Holder), expectedCredential, 'pull credential');
    assertEq(
      provider.validateCredential(Holder, hex'deadbeef'),
      expectedCredential,
      'validated credential'
    );
  }

  function testFuzz_exactBalanceBoundary(uint96 balanceSeed) external {
    uint256 balance = bound(uint256(balanceSeed), 1, type(uint96).max);
    MockERC20 token = new MockERC20('Gate', 'GATE', 18);
    token.mint(Holder, balance);
    ERC20RoleProvider exactProvider = new ERC20RoleProvider(address(token), balance);
    ERC20RoleProvider aboveProvider = new ERC20RoleProvider(address(token), balance + 1);

    assertEq(exactProvider.getCredential(Holder), uint32(block.timestamp), 'exact threshold');
    assertEq(aboveProvider.getCredential(Holder), 0, 'above threshold');
  }

  function testFuzz_transferMovesCredential(uint96 balanceSeed) external {
    uint256 balance = bound(uint256(balanceSeed), 1, type(uint96).max);
    MockERC20 token = new MockERC20('Gate', 'GATE', 18);
    token.mint(Holder, balance);
    ERC20RoleProvider provider = new ERC20RoleProvider(address(token), balance);

    assertEq(provider.getCredential(Holder), uint32(block.timestamp), 'original credential');
    vm.prank(Holder);
    token.transfer(Recipient, balance);

    assertEq(provider.getCredential(Holder), 0, 'stale credential');
    assertEq(provider.getCredential(Recipient), uint32(block.timestamp), 'new credential');
  }
}

contract ERC20RoleProviderTest is BaseMarketTest {
  MockERC20 internal gatingToken;
  ERC20RoleProvider internal provider;

  address internal approvedLender;
  address internal unapprovedLender;

  uint256 internal minBalance = 100e18;

  function setUp() public override {
    super.setUp();
    _deauthorizeLender(alice);

    approvedLender = alice;
    unapprovedLender = bob;

    gatingToken = new MockERC20('Gate', 'GATE', 18);
    provider = new ERC20RoleProvider(address(gatingToken), minBalance);
    gatingToken.mint(approvedLender, minBalance);

    vm.prank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 0);
  }

  function test_getCredential_exactThreshold() external view {
    assertEq(provider.getCredential(approvedLender), uint32(block.timestamp), 'credential');
  }

  function test_getCredential_rejectsOneUnitBelowThreshold() external {
    ERC20RoleProvider higherThresholdProvider = new ERC20RoleProvider(
      address(gatingToken),
      minBalance + 1
    );
    assertEq(higherThresholdProvider.getCredential(approvedLender), 0, 'credential');
  }

  function test_deposit_allows_erc20_holder() external {
    _deposit(approvedLender, 1e18, false);
  }

  function test_deposit_reverts_erc20_below_min_balance() external {
    _expectDepositRevertNotApproved(unapprovedLender, 1e18);
  }

  function test_deposit_zeroTtlRechecksWithinSameBlock() external {
    _deposit(approvedLender, 1e18, false);

    vm.prank(approvedLender);
    gatingToken.transfer(unapprovedLender, minBalance);

    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_deposit_zeroTtlFollowsTransferredBalance() external {
    vm.prank(approvedLender);
    gatingToken.transfer(unapprovedLender, minBalance);

    _deposit(unapprovedLender, 1e18, false);
  }

  function test_deposit_positiveTtlDelaysRemoval() external {
    vm.prank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 1);

    _deposit(approvedLender, 1e18, false);

    vm.prank(approvedLender);
    gatingToken.transfer(unapprovedLender, minBalance);

    _deposit(approvedLender, 1e18, false);
    fastForward(2);
    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_eligibleAccountRemainsHookBlocked() external {
    _blockLender(approvedLender);
    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_revertingTokenFailsClosed() external {
    RevertingERC20BalanceToken revertingToken = new RevertingERC20BalanceToken();
    ERC20RoleProvider revertingProvider = new ERC20RoleProvider(address(revertingToken), 1);
    vm.startPrank(parameters.borrower);
    hooks.removeRoleProvider(address(provider));
    hooks.addRoleProvider(address(revertingProvider), 0);
    vm.stopPrank();

    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_revertingTokenDoesNotBlockLaterProvider() external {
    RevertingERC20BalanceToken revertingToken = new RevertingERC20BalanceToken();
    ERC20RoleProvider revertingProvider = new ERC20RoleProvider(address(revertingToken), 1);
    vm.startPrank(parameters.borrower);
    hooks.removeRoleProvider(address(provider));
    hooks.addRoleProvider(address(revertingProvider), 0);
    hooks.addRoleProvider(address(provider), 0);
    vm.stopPrank();

    _deposit(approvedLender, 1e18, false);
  }

  function test_constructor_reverts_without_code() external {
    vm.expectRevert(IERC20RoleProvider.InvalidTokenAddress.selector);
    new ERC20RoleProvider(address(0), minBalance);
  }

  function test_constructor_reverts_with_zero_minimum() external {
    vm.expectRevert(IERC20RoleProvider.InvalidMinimumBalance.selector);
    new ERC20RoleProvider(address(gatingToken), 0);
  }

  function _expectDepositRevertNotApproved(address lender, uint256 amount) internal {
    asset.mint(lender, amount);
    vm.startPrank(lender);
    asset.approve(address(market), amount);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.depositUpTo(amount);
    vm.stopPrank();
  }
}

contract ERC20RoleProviderWildcatDebtTokenTest is BaseMarketTest {
  function test_wildcatDebtTokenCannotAuthorizeItsOwnMarket() external {
    _deposit(alice, 1e18, false);
    ERC20RoleProvider provider = new ERC20RoleProvider(address(market), 1e18);
    assertEq(provider.getCredential(alice), uint32(block.timestamp), 'credential outside market');

    vm.prank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 0);
    _deauthorizeLender(alice);

    asset.mint(alice, 1e18);
    vm.startPrank(alice);
    asset.approve(address(market), 1e18);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.depositUpTo(1e18);
    vm.stopPrank();
  }

  function test_wildcatDebtTokenInterestCanAuthorizeAnotherMarket() external {
    uint256 depositedAssets = 100e18;
    _deposit(alice, depositedAssets, false);
    _borrow(market.borrowableAssets());

    WildcatMarket sourceMarket = market;
    uint256 minimumBalance = sourceMarket.balanceOf(alice) + 1e18;
    ERC20RoleProvider provider = new ERC20RoleProvider(
      address(sourceMarket),
      minimumBalance
    );

    MockERC20 targetAsset = new MockERC20('Target Token', 'TGT', 18);
    MarketInputParameters memory targetParameters = parameters;
    targetParameters.asset = address(targetAsset);
    WildcatMarket targetMarket = deployMarket(targetParameters);

    vm.prank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 0);
    _deauthorizeLender(alice);

    assertEq(provider.getCredential(alice), 0, 'credential before interest');
    targetAsset.mint(alice, 1e18);
    vm.startPrank(alice);
    targetAsset.approve(address(targetMarket), 1e18);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    targetMarket.depositUpTo(1e18);
    vm.stopPrank();

    fastForward(365 days);
    sourceMarket.updateState();

    assertGe(sourceMarket.balanceOf(alice), minimumBalance, 'debt token balance');
    assertEq(provider.getCredential(alice), uint32(block.timestamp), 'credential after interest');
    vm.prank(alice);
    targetMarket.depositUpTo(1e18);
  }
}
