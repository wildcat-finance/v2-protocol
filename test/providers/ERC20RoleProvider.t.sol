// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

import '../BaseMarketTest.sol';
import { fastForward } from '../helpers/VmUtils.sol';
import 'src/providers/ERC20RoleProvider.sol';

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

    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), type(uint32).max);
    vm.stopPrank();
  }

  /// @dev Holders of the configured ERC20 can deposit.
  function test_deposit_allows_erc20_holder() external {
    _deposit(approvedLender, 1e18, false);
  }

  /// @dev Non-holders are rejected even if they can fund the deposit.
  function test_deposit_reverts_erc20_below_min_balance() external {
    uint256 amount = 1e18;
    asset.mint(unapprovedLender, amount);

    vm.startPrank(unapprovedLender);
    asset.approve(address(market), amount);
    vm.expectRevert(AccessControlHooks.NotApprovedLender.selector);
    market.depositUpTo(amount);
    vm.stopPrank();
  }

  /// @dev Pull-provider credentials remain valid until TTL expiry.
  function test_deposit_erc20_expires_after_ttl() external {
    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 1);
    vm.stopPrank();

    _deposit(approvedLender, 1e18, false);

    vm.prank(approvedLender);
    gatingToken.transfer(unapprovedLender, minBalance);

    _deposit(approvedLender, 1e18, false);

    fastForward(2);

    uint256 amount = 1e18;
    asset.mint(approvedLender, amount);

    vm.startPrank(approvedLender);
    asset.approve(address(market), amount);
    vm.expectRevert(AccessControlHooks.NotApprovedLender.selector);
    market.depositUpTo(amount);
    vm.stopPrank();
  }

  function test_constructor_reverts_without_code() external {
    vm.expectRevert(ERC20RoleProvider.InvalidTokenAddress.selector);
    new ERC20RoleProvider(address(0), minBalance);
  }
}
