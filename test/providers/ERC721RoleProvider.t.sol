// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { MockERC721 } from 'solmate/test/utils/mocks/MockERC721.sol';

import '../BaseMarketTest.sol';
import { fastForward } from '../helpers/VmUtils.sol';
import 'src/providers/ERC721RoleProvider.sol';

contract NonERC721 {}

contract ERC721RoleProviderTest is BaseMarketTest {
  MockERC721 internal nft;
  ERC721RoleProvider internal provider;

  address internal approvedLender;
  address internal unapprovedLender;

  function setUp() public override {
    super.setUp();
    _deauthorizeLender(alice);

    approvedLender = alice;
    unapprovedLender = bob;

    nft = new MockERC721('Access', 'ACCESS');
    provider = new ERC721RoleProvider(address(nft), false);
    nft.mint(approvedLender, 1);

    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), type(uint32).max);
    vm.stopPrank();
  }

  /// @dev Holders of the configured ERC721 can deposit.
  function test_deposit_allows_erc721_holder() external {
    _deposit(approvedLender, 1e18, false);
  }

  /// @dev Non-holders are rejected even if they can fund the deposit.
  function test_deposit_reverts_erc721_nonholder() external {
    uint256 amount = 1e18;
    asset.mint(unapprovedLender, amount);
    assertEq(nft.balanceOf(unapprovedLender), 0, 'expected no ERC721 balance');

    vm.startPrank(unapprovedLender);
    asset.approve(address(market), amount);
    vm.expectRevert(AccessControlHooks.NotApprovedLender.selector);
    market.depositUpTo(amount);
    vm.stopPrank();
  }

  /// @dev Pull-provider credentials remain valid until TTL expiry.
  function test_deposit_erc721_expires_after_ttl() external {
    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 1);
    vm.stopPrank();

    _deposit(approvedLender, 1e18, false);

    vm.prank(approvedLender);
    nft.transferFrom(approvedLender, unapprovedLender, 1);

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
    vm.expectRevert(ERC721RoleProvider.InvalidTokenAddress.selector);
    new ERC721RoleProvider(address(0), false);
  }

  function test_constructor_reverts_without_erc721_interface() external {
    NonERC721 nonErc721 = new NonERC721();
    vm.expectRevert(ERC721RoleProvider.InvalidERC721.selector);
    new ERC721RoleProvider(address(nonErc721), false);
  }

  function test_constructor_allows_skip_interface_check() external {
    NonERC721 nonErc721 = new NonERC721();
    new ERC721RoleProvider(address(nonErc721), true);
  }
}
